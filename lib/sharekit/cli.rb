# frozen_string_literal: true

require "thor"
require_relative "cli/version"
require_relative "cli/finding"
require_relative "cli/scanner"
require_relative "cli/reporter"
require_relative "cli/file_lister"

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
    end
  end
end
