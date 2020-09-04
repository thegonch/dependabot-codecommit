# This script is designed to loop through all dependencies in an AWS CodeCommit project, creating PRs where necessary.

require 'dependabot/file_fetchers'
require 'dependabot/file_parsers'
require 'dependabot/update_checkers'
require 'dependabot/file_updaters'
require 'dependabot/pull_request_creator'
# dependabot/omnibus provides support for all languages
require 'dependabot/omnibus'
require 'aws-sdk-codecommit'

PACKAGE_MANAGERS = %w[bundler pip npm_and_yarn maven gradle cargo hex composer nuget dep go_modules elm submodules docker terraform github_actions].freeze

package_managers = ARGV[0].split

if ARGV[0] == 'all'
  package_managers = PACKAGE_MANAGERS
elsif !(package_managers - PACKAGE_MANAGERS).empty?
  raise "ARGUMENT ERROR: First argument contains invalid package managers.  Must be at least one of #{PACKAGE_MANAGERS}.  If more than one, please quote them separated by spaces.\n Example: \"bundler pip\""
end

`./dependabot_helpers.sh`

# Communicate to dependabot-core GitHub repo
credentials = [
  {
    'type' => 'git_source',
    'host' => 'github.com',
    'username' => 'x-access-token',
    'password' => ENV['GITHUB_ACCESS_TOKEN'] # A GitHub access token with read access to public repos
  }
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV['PROJECT_PATH'] || 'sgoncher-dependabot' # namespace/project

# Directory where the base dependency files are.
directory = ENV['DIRECTORY_PATH'] || '/'

source = Dependabot::Source.new(
  provider: 'codecommit',
  hostname: ENV['AWS_REGION'],
  repo: repo_name,
  directory: directory,
  branch: 'master'
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
      credentials: credentials,
      assignees: [(ENV['PULL_REQUESTS_ASSIGNEE'])&.to_i],
      label_language: true
    )
    pull_request = pr_creator.create
    puts ' submitted'

    next unless pull_request
  end
end
puts 'Done'
