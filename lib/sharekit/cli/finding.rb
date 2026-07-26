# frozen_string_literal: true

module Sharekit
  module Cli
    SEVERITY_RANK = { high: 2, medium: 1, low: 0 }.freeze

    # Immutable value object for one scan hit. Data.define gives us structural
    # equality and Hash-pattern deconstruction (`in {severity:, rule:}`) for free —
    # a plain TS interface has neither.
    #
    # The triage fields default to nil, so a scan-only run builds a Finding the
    # same way it always did, and `Triage` layers verdicts on with `#with` rather
    # than mutating anything.
    Finding = Data.define(:rule, :file, :line, :preview, :severity,
                          :verdict, :confidence, :rationale) do
      include Comparable

      def initialize(verdict: nil, confidence: nil, rationale: nil, **) = super

      def <=>(other)
        SEVERITY_RANK.fetch(severity) <=> SEVERITY_RANK.fetch(other.severity)
      end

      def high? = severity == :high
      def triaged? = !verdict.nil?
    end
  end
end
