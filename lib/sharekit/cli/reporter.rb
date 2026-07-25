# frozen_string_literal: true

module Sharekit
  module Cli
    # Formats findings for terminal output and gates high-severity secrets.
    module Reporter
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RESET = "\e[0m"

      module_function

      def report(findings, force: false)
        if findings.empty?
          puts "#{GREEN}  ✓ No secrets detected.\n#{RESET}"
          return
        end

        puts "#{YELLOW}\n  ⚠  Secret patterns detected:#{RESET}"
        findings.each { |finding| puts "#{YELLOW}    #{format_line(finding)}#{RESET}" }
        puts "#{YELLOW}\n  ⚠  Review and redact secrets before pushing to a public repository.\n#{RESET}"

        gate!(findings, force:)
      end

      # Data.define objects deconstruct into a Hash for free, so `in` can match
      # directly on the fields we care about — no case/when + manual field access.
      def format_line(finding)
        case finding
        in { file:, line:, rule:, preview: }
          "#{file}:#{line} [#{rule}] #{preview}"
        end
      end

      def gate!(findings, force:)
        high = findings.select(&:high?)
        return if high.empty? || force

        raise Error, "Secrets export blocked: #{high.size} high-severity finding(s) detected. " \
                      "Review and remove secrets, or re-run with --force to override."
      end
    end
  end
end
