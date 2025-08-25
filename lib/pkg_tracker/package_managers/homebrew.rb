require 'open3'
require 'logger'

module PkgTracker
  module PackageManagers
    class Homebrew
      @@logger = Logger.new(STDOUT)
      @@logger.level = Logger::DEBUG

      def find_recent_packages(days)
        core_dir = run_brew_command('--repo', 'homebrew/core')
        cask_dir = run_brew_command('--repo', 'homebrew/cask')

        @@logger.debug "Core repo directory: #{core_dir}"
        @@logger.debug "Cask repo directory: #{cask_dir}"

        new_formulae = git_log(core_dir, days, filter: 'A', path: 'Formula/')
        updated_formulae = git_log(core_dir, days, filter: 'M', path: 'Formula/')
        new_casks = git_log(cask_dir, days, filter: 'A', path: 'Casks/')
        updated_casks = git_log(cask_dir, days, filter: 'M', path: 'Casks/')

        @@logger.debug "Raw new formulae output: #{new_formulae}"
        @@logger.debug "Raw updated formulae output: #{updated_formulae}"
        @@logger.debug "Raw new casks output: #{new_casks}"
        @@logger.debug "Raw updated casks output: #{updated_casks}"

        parsed_new_formulae = parse_package_list(new_formulae)
        parsed_updated_formulae = parse_package_list(updated_formulae)
        parsed_new_casks = parse_package_list(new_casks)
        parsed_updated_casks = parse_package_list(updated_casks)

        @@logger.debug "Parsed new formulae: #{parsed_new_formulae}"
        @@logger.debug "Parsed updated formulae: #{parsed_updated_formulae}"
        @@logger.debug "Parsed new casks: #{parsed_new_casks}"
        @@logger.debug "Parsed updated casks: #{parsed_updated_casks}"

        {
 new_formulae: parsed_new_formulae,
 updated_formulae: parsed_updated_formulae,
 new_casks: parsed_new_casks,
 updated_casks: parsed_updated_casks
        }
      end

      private

      def run_brew_command(*args)
        command = ['brew', *args].join(' ')
        stdout, stderr, status = Open3.capture3(command)

        unless status.success?
          raise "Error executing brew command: #{command}\n#{stderr}"
        end

        stdout.strip
      end

      def git_log(repo_dir, days, filter:, path:)
        command = [
          'git', '-C', repo_dir, 'log', "--since=\"#{days} days ago\"",
          "--diff-filter=#{filter}", '--name-only', '--pretty=format:', path
        ]
        @@logger.debug(command.join(" "))
        Open3.capture3(*command)[0] # Return only stdout
      end

      def parse_package_list(output)
        output.split("\n").map { |line| File.basename(line, '.rb') }.sort.uniq
      end
    end
  end
end
