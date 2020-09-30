# frozen_string_literal: true

# !/usr/bin/env ruby

# This script is designed to loop through all dependencies in an AWS CodeCommit
# project, creating PRs where necessary.

require 'dependabot/file_fetchers'
require 'dependabot/file_parsers'
require 'dependabot/update_checkers'
require 'dependabot/file_updaters'
require 'dependabot/pull_request_creator'
# dependabot/omnibus provides support for all languages
require 'dependabot/omnibus'
require 'aws-sdk-codecommit'
require 'optimist'

ENV['DEPENDABOT_NATIVE_HELPERS_PATH'] = "#{Dir.pwd}/native-helpers"
ENV['PATH'] = "#{ENV['PATH']}:#{ENV['DEPENDABOT_NATIVE_HELPERS_PATH']}" \
              "/terraform/bin:#{ENV['DEPENDABOT_NATIVE_HELPERS_PATH']}" \
              "/python/bin:#{ENV['DEPENDABOT_NATIVE_HELPERS_PATH']}" \
              "/go_modules/bin:#{ENV['DEPENDABOT_NATIVE_HELPERS_PATH']}/dep/bin"
ENV['MIX_HOME'] = "#{ENV['DEPENDABOT_NATIVE_HELPERS_PATH']}/hex/mix"

PACKAGE_MANAGERS = %w[
  bundler pip npm_and_yarn maven gradle cargo hex composer nuget dep \
  go_modules elm submodules docker terraform github_actions
].freeze

opts = Optimist.options do
  opt :package_manager_list, 'space-delimited Package Manager(s) to run ' \
  "against from this list:\n#{PACKAGE_MANAGERS}\n\nCANNOT be used with" \
  " --all-package-managers\n\nExample: --package-manager-list bundler " \
  "docker\n ", type: 'strings'

  opt :all_package_managers, 'run against all package managers in ' \
  "#{PACKAGE_MANAGERS}\n\nCANNOT be used with " \
  "--package-manager-list\n ", default: false

  opt :project_path, "name of the AWS CodeCommit repository\n ", type: 'string'

  opt :directory_path, "location of the base dependency files\n ", \
      type: 'string', default: '/'

  opt :codecommit_branch, 'branch of the AWS CodeCommit repository to ' \
  "check against\n ", type: 'string', default: 'master'

  conflicts :package_manager_list, :all_package_managers
end

Optimist.die :package_manager_list, 'must be a space-delimited list from' \
"#{PACKAGE_MANAGERS}" unless opts[:all_package_managers] || \
                             (!opts[:package_manager_list].nil? && \
  (opts[:package_manager_list] - PACKAGE_MANAGERS).empty?)

package_managers = if opts[:all_package_managers]
                     PACKAGE_MANAGERS
                   else
                     opts[:package_manager_list]
                   end

# Create the native helpers
`./dependabot_helpers.sh`

# Communicate to dependabot-core GitHub repo
credentials = [
  {
    'type' => 'git_source',
    'host' => 'github.com',
    'username' => 'x-access-token',
    'password' => ENV['GITHUB_ACCESS_TOKEN'] # read access to repos
  }
]

# Full name of the repo you want to create pull requests for.
repo_name = opts[:project_path]

# Directory where the base dependency files are.
directory = opts[:directory_path]

# Branch of CodeCommit to check
codecommit_branch = opts[:codecommit_branch]

source = Dependabot::Source.new(
  provider: 'codecommit',
  hostname: ENV['AWS_REGION'],
  repo: repo_name,
  directory: directory,
  branch: codecommit_branch
)
package_managers.each do |package_manager|
  ##############################
  # Fetch the dependency files #
  ##############################
  puts "Fetching #{package_manager} dependency files for #{repo_name}"
  fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
    source: source,
    credentials: credentials
  )

  files = fetcher.files
  commit = fetcher.commit

  ##############################
  # Parse the dependency files #
  ##############################
  puts 'Parsing dependencies information'
  parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
    dependency_files: files,
    source: source,
    credentials: credentials
  )

  dependencies = parser.parse

  dependencies.select(&:top_level?).each do |dep|
    #########################################
    # Get update details for the dependency #
    #########################################
    checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials
    )

    next if checker.up_to_date?

    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end

    next if requirements_to_unlock == :update_not_possible

    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )

    #####################################
    # Generate updated dependency files #
    #####################################
    print "  - Updating #{dep.name} (from #{dep.version})…"
    updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
      dependencies: updated_deps,
      dependency_files: files,
      credentials: credentials
    )

    updated_files = updater.updated_dependency_files

    ########################################
    # Create a pull request for the update #
    ########################################
    pr_creator = Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: commit,
      dependencies: updated_deps,
      files: updated_files,
      credentials: credentials
    )
    pull_request = pr_creator.create
    puts ' submitted'

    next unless pull_request
  end
end
puts 'Done'
