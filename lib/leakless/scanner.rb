# frozen_string_literal: true

require_relative "finding"

module Leakless
  module Cli
    # Rule-driven secret scanner. Each rule is data (pattern + metadata), not a
    # branch in an if/elsif chain — adding a rule means appending to RULES,
    # never touching the scan loop.
    class Scanner
      Rule = Data.define(:name, :pattern, :severity, :context_before, :max_len, :leading_ellipsis)

      RULES = [
        Rule.new(name: "Private Key Block",
                 pattern: /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
                 severity: :high, context_before: 0, max_len: 40, leading_ellipsis: false),
        Rule.new(name: "AWS Access Key ID",
                 pattern: /AKIA[0-9A-Z]{16}/,
                 severity: :high, context_before: 5, max_len: 20, leading_ellipsis: true),
        Rule.new(name: "GitHub Personal Access Token",
                 pattern: /ghp_[A-Za-z0-9_]{20,}/,
                 severity: :high, context_before: 5, max_len: 40, leading_ellipsis: true),
        Rule.new(name: "GitHub Personal Access Token",
                 pattern: /github_pat_[A-Za-z0-9_]{20,}/,
                 severity: :high, context_before: 5, max_len: 40, leading_ellipsis: true),
        Rule.new(name: "Slack Token",
                 pattern: /xox[baprs]-[A-Za-z0-9-]{10,}/,
                 severity: :high, context_before: 5, max_len: 40, leading_ellipsis: true),
        Rule.new(name: "Google API Key",
                 pattern: /AIza[0-9A-Za-z\-_]{30,40}/,
                 severity: :high, context_before: 5, max_len: 40, leading_ellipsis: true),
        Rule.new(name: "Bearer Token",
                 pattern: /Bearer eyJ[A-Za-z0-9._-]*\.[A-Za-z0-9._-]+\.[A-Za-z0-9._-]+/,
                 severity: :high, context_before: 0, max_len: 30, leading_ellipsis: false),
        Rule.new(name: "Home Directory Path Leak",
                 pattern: %r{(/Users/[a-zA-Z0-9_-]+|/home/[a-zA-Z0-9_-]+)},
                 severity: :low, context_before: 5, max_len: 40, leading_ellipsis: true)
      ].freeze

      ENV_VAR_PATTERN = /(?:^|\s)(?:export\s+)?([A-Z_]+?)=(.*)$/
      SENSITIVE_KEY_PATTERN = /(SECRET|TOKEN|PASSWORD|API_KEY|APIKEY|ACCESS_KEY)/i
      PLACEHOLDER_PREFIXES = ['""', "''", "xxx", "<", "changeme", "your-", "your_"].freeze

      class << self
        # Scans +content+ line by line. Yields each Finding as it's found when
        # a block is given; otherwise returns an Enumerator (same dual API as
        # Array#each), so callers can stream (`each { }`) or collect (`.to_a`,
        # `.first`, `.lazy`) without the scanner caring which.
        def scan(content, file: nil)
          return to_enum(:scan, content, file:) unless block_given?

          content.each_line.with_index(1) do |raw_line, line_num|
            line = raw_line.chomp
            finding = rule_finding(line, file, line_num) || env_var_finding(line, file, line_num)
            yield finding if finding
          end
        end

        def truncate_preview(line, idx, context_before: 5, max_len: 40, leading_ellipsis: true)
          start = [0, idx - context_before].max
          finish = [line.length, idx + max_len].min
          leading = leading_ellipsis && start.positive? ? "…" : ""
          trailing = finish < line.length ? "…" : ""
          "#{leading}#{line[start...finish]}#{trailing}"
        end

        private

        def rule_finding(line, file, line_num)
          rule = RULES.find { |r| r.pattern.match?(line) }
          return unless rule

          match = rule.pattern.match(line)
          preview = truncate_preview(
            line, match.begin(0),
            context_before: rule.context_before, max_len: rule.max_len, leading_ellipsis: rule.leading_ellipsis
          )
          Finding.new(rule: rule.name, file:, line: line_num, preview:, severity: rule.severity)
        end

        def env_var_finding(line, file, line_num)
          match = ENV_VAR_PATTERN.match(line)
          return unless match

          key_name = match[1].upcase
          value = match[2]
          return unless SENSITIVE_KEY_PATTERN.match?(key_name)
          return if placeholder?(value)

          Finding.new(rule: "Env Var: Sensitive Key", file:, line: line_num,
                      preview: "#{key_name}=#{truncate_value(value)}", severity: :medium)
        end

        def placeholder?(value)
          return true if value.empty? || value == '""' || value == "''"

          PLACEHOLDER_PREFIXES.any? { |prefix| value.start_with?(prefix) }
        end

        def truncate_value(value)
          value.length > 8 ? "#{value[0, 8]}…" : value
        end
      end
    end
  end
end
