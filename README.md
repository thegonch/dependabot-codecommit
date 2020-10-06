# Dependabot Update Script for AWS CodeCommit

This repo is a fork of [Dependabot Script][dependabot-script]

## Setup and usage

* `rbenv install` (Install Ruby version from `.ruby-version`)
* `bundle install`

### Native helpers with `dependabot_helpers.sh`

The Bash script [`dependabot_helpers.sh`][dependabot_helpers.sh] helps automate the installation of the
Dependabot Native Helpers as described
[here](https://github.com/dependabot/dependabot-script#native-helpers).

It is designed to be run from within
[`aws_codecommit_update_script.rb`][aws_codecommit_update_script.rb] since this
ruby script will first set up the required environment variables.

It is currently designed to install all possible native helpers, which includes:
Terraform, Python, Go (Dep & Modules), Elixir, PHP, JS

This also helps preserve your existing environment variables, including your `PATH`.

### Running `aws_codecommit_update_script.rb`

* Please note the following pre-requisites before running this script
  * An environment variable named `GITHUB_ACCESS_TOKEN` that contains a [personal
    github token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token) with full `repo` access.
  * An environment variable named `AWS_REGION` that passes in the name of the
    AWS Region, i.e. `us-east-1`
  * An AWS authentication that allows for CodeCommit access including:
    * ListPullRequests
    * BatchGetCommits
    * GetBranch
    * GetCommit
    * GetFile
    * GetFolder
    * GetPullRequest
    * GetRepository
    * CreateBranch
    * CreateCommit
    * CreatePullRequest

To execute, run the script as follows from the command prompt:

 `ruby aws_codecommit_update_script.rb [options]`

| Option Name   | Value   |   Required |
| ------------- | ----------------------- | ---- |
| -p, --package-manager-list  | space-delimited package manager(s) to run against from this list:`["bundler", "pip", "npm_and_yarn", "maven", "gradle", "cargo", "hex", "composer", "nuget", "dep", "\n", "go_modules", "elm", "submodules", "docker", "terraform", "github_actions"]` | yes (this OR --all-package-managers)
| -a, --all-package-managers     | run against all package managers (CANNOT be used with --package-manager-list)             | yes (this OR --package-manager-list)
| -r, --project-path  | name of the AWS CodeCommit repository | yes
| -d, --directory-path |  location of the base dependency files (default: /)     | no
|  -c, --codecommit-branch     | branch of the AWS CodeCommit repository to check against (default: master) | no

If you run into any trouble with the above please create an issue!

[dependabot-script]: https://github.com/dependabot/dependabot-script
[dependabot_helpers.sh]: dependabot_helpers.sh
[aws_codecommit_update_script.rb]: aws_codecommit_update_script.rb
