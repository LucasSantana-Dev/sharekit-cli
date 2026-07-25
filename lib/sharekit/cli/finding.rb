# frozen_string_literal: true

module Sharekit
  module Cli
    SEVERITY_RANK = { high: 2, medium: 1, low: 0 }.freeze

    # Immutable value object for one scan hit. Data.define gives us structural
    # equality and Hash-pattern deconstruction (`in {severity:, rule:}`) for free —
    # a plain TS interface has neither.
    Finding = Data.define(:rule, :file, :line, :preview, :severity) do
      include Comparable

      def <=>(other)
        SEVERITY_RANK.fetch(severity) <=> SEVERITY_RANK.fetch(other.severity)
      end

      def high? = severity == :high
    end
  end
end
