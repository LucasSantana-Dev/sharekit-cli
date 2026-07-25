# frozen_string_literal: true

require "thor"
require_relative "cli/version"
require_relative "cli/finding"
require_relative "cli/scanner"
require_relative "cli/reporter"
require_relative "cli/file_lister"
require_relative "cli/init"

module Sharekit
  module Cli
    class Error < StandardError; end

    # Thor gives us subcommand dispatch, flag parsing, and --help for free —
    # the TS original hand-parses process.argv/flags itself.
    class App < Thor
      def self.exit_on_failure? = true

      desc "scan [DIR]", "scan a directory for secret patterns"
      method_option :force,
                    type: :boolean,
                    default: false,
                    desc: "exit 0 even if high-severity findings detected"
      def scan(dir = ".")
        findings = FileLister.list(dir).flat_map do |path|
          Scanner.scan(File.read(path, encoding: "UTF-8"), file: path).to_a
        rescue ArgumentError, Errno::ENOENT, Errno::EACCES => e
          puts "    ~ Skipped #{path}: #{e.class}"
          []
        end

        Reporter.report(findings, force: options[:force])
      rescue Error => e
        warn e.message
        exit 1
      end

      desc "init [SKILL...]", "scaffold a publishable sharekit profile"
      method_option :force,
                    type: :boolean,
                    default: false,
                    desc: "overwrite existing dir; override secret blocking"
      method_option :dir,
                    type: :string,
                    default: "./sharekit-profile",
                    desc: "profile directory to create"
      def init(*skill_names)
        result = Init.call(profile_dir: options[:dir], skill_names:, force: options[:force])
        print_init_summary(result)
        Reporter.report(result.findings, force: options[:force])
      rescue Error => e
        warn e.message
        exit 1
      end

      no_commands do
        def print_init_summary(result)
          result.created.each { |path| puts "  + #{path}" }
          puts "\n  ✓ Created profile at #{result.profile_dir}\n\n"
        end
      end
    end
  end
end
