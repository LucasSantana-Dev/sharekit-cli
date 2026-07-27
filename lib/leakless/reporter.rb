# frozen_string_literal: true

module Leakless
  module Cli
    # Formats findings for terminal output and gates high-severity secrets.
    module Reporter
      GREEN = "\e[32m"
      YELLOW = "\e[33m"
      RESET = "\e[0m"

      VERDICT_LABELS = { "true_positive" => "likely real",
                         "false_positive" => "likely placeholder",
                         "uncertain" => "unclear" }.freeze

      module_function

      def report(findings, force: false)
        if findings.empty?
          puts "#{GREEN}  ✓ No secrets detected.\n#{RESET}"
          return
        end

        print_findings(findings)
        gate!(findings, force:)
      end

      def print_findings(findings)
        puts "#{YELLOW}\n  ⚠  Secret patterns detected:#{RESET}"
        findings.each { |finding| puts "#{YELLOW}    #{format_line(finding)}#{RESET}" }
        puts "#{YELLOW}\n  ⚠  Review and redact secrets before pushing to a public repository.#{RESET}"
        if findings.any?(&:triaged?)
          puts "#{YELLOW}  ⚠  AI verdicts are advisory: the high-severity gate ignores them.#{RESET}"
        end
        puts ""
      end

      # Data.define objects deconstruct into a Hash for free, so `in` can match
      # directly on the fields we care about — no case/when + manual field access.
      # The untriaged branch comes first, so a nil verdict never reaches the
      # formatting that assumes one.
      def format_line(finding)
        case finding
        in { verdict: nil, file:, line:, rule:, preview: }
          "#{file}:#{line} [#{rule}] #{preview}"
        in { verdict:, confidence:, rationale:, file:, line:, rule:, preview: }
          "#{file}:#{line} [#{rule}] #{preview}\n" \
            "      → #{VERDICT_LABELS.fetch(verdict, verdict)} " \
            "(#{(confidence * 100).round}% confident) #{rationale}"
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
