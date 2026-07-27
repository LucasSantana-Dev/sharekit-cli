# frozen_string_literal: true

require "thor"
require_relative "leakless/version"
require_relative "leakless/finding"
require_relative "leakless/scanner"
require_relative "leakless/reporter"
require_relative "leakless/file_lister"
require_relative "leakless/init"

module Leakless
  # Command-line entry points for scanning a directory for leaked secrets and
  # scaffolding a publishable profile.
  module Cli
    class Error < StandardError; end

    # Loading ruby_llm pulls in a provider stack that a plain `scan` never needs,
    # so Triage is resolved on first reference instead of at boot.
    autoload :Triage, "leakless/triage"

    # Thor gives us subcommand dispatch, flag parsing, and --help for free —
    # the TS original hand-parses process.argv/flags itself.
    class App < Thor
      def self.exit_on_failure? = true

      desc "scan [DIR]", "scan a directory for secret patterns"
      method_option :force,
                    type: :boolean,
                    default: false,
                    desc: "exit 0 even if high-severity findings detected"
      method_option :ai_triage,
                    type: :boolean,
                    default: false,
                    desc: "label findings true/false positive with an LLM (secret values are redacted first)"
      method_option :model,
                    type: :string,
                    desc: "model id for --ai-triage (default: RubyLLM's configured default)"
      method_option :provider,
                    type: :string,
                    desc: "provider for --ai-triage, e.g. anthropic, openai, ollama"
      method_option :assume_model_exists,
                    type: :boolean,
                    default: false,
                    desc: "skip model-registry validation, needed for local Ollama models"
      def scan(dir = ".")
        findings = collect_findings(dir)
        findings = triage(findings) if options[:ai_triage]
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
        def collect_findings(dir)
          FileLister.list(dir).flat_map do |path|
            Scanner.scan(File.read(path, encoding: "UTF-8"), file: path).to_a
          rescue ArgumentError, Errno::ENOENT, Errno::EACCES => e
            puts "    ~ Skipped #{path}: #{e.class}"
            []
          end
        end

        def triage(findings)
          return findings if findings.empty?

          puts "\n  … AI triage: #{findings.size} finding(s), secret values redacted before sending"
          Triage.call(findings,
                      model: options[:model],
                      provider: options[:provider]&.to_sym,
                      assume_model_exists: options[:assume_model_exists])
        rescue LoadError => e
          # ruby_llm is optional: a scan-only install should not have to carry a
          # provider stack. Autoloading Triage is what surfaces its absence here.
          raise Error, "--ai-triage needs the ruby_llm gem, which is not installed. " \
                        "Install it with `gem install ruby_llm` (or add it to your Gemfile). " \
                        "(#{e.message})"
        end

        def print_init_summary(result)
          result.created.each { |path| puts "  + #{path}" }
          puts "\n  ✓ Created profile at #{result.profile_dir}\n\n"
        end
      end
    end
  end
end
