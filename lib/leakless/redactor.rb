# frozen_string_literal: true

require_relative "scanner"

module Leakless
  module Cli
    # Strips secret material out of a line before it can leave the machine.
    #
    # Redaction runs against the *original* line, never a Finding's truncated
    # preview: truncation can cut a secret mid-token so that the rule pattern no
    # longer matches it, which would let the surviving fragment through.
    #
    # A masked secret is replaced by its shape (length + Shannon entropy), which
    # is what a classifier actually needs to tell a live key from EXAMPLE_KEY.
    module Redactor
      # Backstop for high-entropy material no Scanner rule claims. Runs last, so
      # rule-labelled hits keep their own mask.
      GENERIC_SECRET_PATTERN = %r{[A-Za-z0-9+/=_-]{20,}}
      MASK_PREFIX = "[REDACTED"

      module_function

      # Masks every secret-shaped run in +line+: every Scanner rule, then
      # sensitive env-var values, then the generic backstop. All rules run, not
      # just the one that produced the finding, so a second secret sharing the
      # line cannot ride along into a prompt.
      def redact(line)
        masked = Scanner::RULES.reduce(line) do |acc, rule|
          acc.gsub(rule.pattern) { |hit| mask(hit) }
        end
        mask_env_values(masked).gsub(GENERIC_SECRET_PATTERN) { |hit| mask(hit) }
      end

      def mask(secret)
        "#{MASK_PREFIX} chars=#{secret.length} entropy=#{format("%.1f", entropy(secret))}]"
      end

      # Shannon entropy in bits per character. Random tokens land near 4+ bits;
      # placeholders like AKIAIOSFODNN7EXAMPLE sit noticeably lower.
      def entropy(str)
        return 0.0 if str.empty?

        length = str.length.to_f
        str.each_char.tally.values.sum do |count|
          probability = count / length
          -probability * Math.log2(probability)
        end
      end

      # Scanner's ENV_VAR_PATTERN ends in `(.*)$`, which swallows the rest of the line,
      # so the first assignment is the only one it ever examines. That is fine for
      # reporting one finding per line, but as a redaction pass it leaks: in
      # `PATH=/usr/bin API_KEY=short` the boring first key short-circuits the check and
      # the real secret is never masked, while being too short for the generic
      # backstop. Redaction therefore matches one assignment at a time. Quoted forms
      # are listed explicitly because a bare `\S*` stops at the space in `KEY="a b"`.
      ENV_ASSIGNMENT_PATTERN = /(?:^|\s)(?:export\s+)?([A-Z_]+)=("[^"]*"|'[^']*'|\S*)/

      def mask_env_values(line)
        line.gsub(ENV_ASSIGNMENT_PATTERN) do |hit|
          key = Regexp.last_match(1)
          value = Regexp.last_match(2)
          next hit unless Scanner::SENSITIVE_KEY_PATTERN.match?(key)
          next hit if value.empty? || value.start_with?(MASK_PREFIX)

          hit.sub(value, mask(value))
        end
      end
    end
  end
end
