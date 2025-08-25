require 'thor'
require 'pkg_tracker/package_managers/homebrew'
require 'logger'

module PkgTracker
  class CLI < Thor
    @@logger = Logger.new(STDOUT)
    @@logger.level = Logger::DEBUG

    desc "brew", "Commands for Homebrew package tracking"
    option :days, type: :numeric, default: 7, desc: "Show packages added/updated in the last N days"
    option :only_formula, type: :boolean, default: false, desc: "Show only formulae"
    option :only_cask, type: :boolean, default: false, desc: "Show only casks"
    option :only_new, type: :boolean, default: false, desc: "Show only new packages"
    option :only_updated, type: :boolean, default: false, desc: "Show only updated packages"

    def brew
      homebrew = PkgTracker::PackageManagers::Homebrew.new
      recent_packages = homebrew.find_recent_packages(options[:days])
      @@logger.debug "Received recent_packages: #{recent_packages}"

      puts "Recent Homebrew Packages (last #{options[:days]} days):"

      if options[:only_formula] || (!options[:only_formula] && !options[:only_cask])
        if options[:only_new] || (!options[:only_new] && !options[:only_updated])
          display_packages("🆕 New formulae:", recent_packages[:new_formulae])
        end
        @@logger.debug "Passing updated_formulae to display_packages: #{recent_packages[:updated_formulae]}"
        if options[:only_updated] || (!options[:only_new] && !options[:only_updated])
          display_packages("✏️ Updated formulae:", recent_packages[:updated_formulae])
        end
      end

      if options[:only_cask] || (!options[:only_formula] && !options[:only_cask])
        @@logger.debug "Passing new_casks to display_packages: #{recent_packages[:new_casks]}"
        if options[:only_new] || (!options[:only_new] && !options[:only_updated])
          display_packages("🆕 New casks:", recent_packages[:new_casks])
        end
        @@logger.debug "Passing updated_casks to display_packages: #{recent_packages[:updated_casks]}"
        if options[:only_updated] || (!options[:only_new] && !options[:only_updated])
          display_packages("✏️ Updated casks:", recent_packages[:updated_casks])
        end

      end
    end

    no_commands do
      def display_packages(title, packages)
        if packages.any?
          puts "\n#{title}"
          # Simple display for now, we can enhance this later
          packages.each { |pkg| puts "- #{pkg}" }
        end
      end
    end
  end
end
