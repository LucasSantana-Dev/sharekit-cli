# frozen_string_literal: true

require "ruby_llm"
require "ruby_llm/schema"
require_relative "redactor"

module Sharekit
  module Cli
    # Classifies findings as real leaks or false positives with an LLM.
    #
    # SECURITY: the model never receives secret material, and there is no flag to
    # opt out. Every payload line is rebuilt from the file on disk and passed
    # through Redactor first, so what ships is the finding's *shape*: rule name,
    # path, line number, length and entropy of the masked token, and whatever
    # surrounding context survived redaction. Point --provider at Ollama to keep
    # even that on the machine.
    #
    # Verdicts are advisory. Triage annotates output; it never relaxes the
    # high-severity gate, because a model must not be what decides a live key
    # isn't a key.
    module Triage
      VERDICTS = %w[true_positive false_positive uncertain].freeze

      # Ollama's conventional local endpoint, so --provider ollama needs no setup.
      OLLAMA_DEFAULT_BASE = "http://localhost:11434/v1"

      RATIONALE_LIMIT = 120

      # A missing API key or an unknown model id raise off a different branch of
      # RubyLLM's hierarchy than provider/HTTP faults, and they are the two most
      # likely failures here, so both branches are caught.
      FAILURES = [RubyLLM::Error, RubyLLM::ConfigurationError,
                  RubyLLM::ModelNotFoundError, Faraday::Error].freeze

      # Findings go over as an indexed list in one request, and verdicts are
      # matched back by index. A verdict for an index the model skipped or
      # invented is dropped rather than shifting every later finding's answer.
      class Schema < RubyLLM::Schema
        array :verdicts do
          object do
            integer :index, description: "index of the finding being judged"
            string :verdict, enum: VERDICTS
            number :confidence, description: "0.0 to 1.0"
            string :rationale, description: "one sentence, at most #{RATIONALE_LIMIT} characters"
          end
        end
      end

      SYSTEM_PROMPT = <<~PROMPT
        You triage secret-scanner findings for a tool that runs before someone
        publishes a directory. For each finding decide whether it is a real leaked
        credential (true_positive), a placeholder, example, test fixture or
        documentation sample (false_positive), or genuinely unclear (uncertain).

        Secret values have been redacted before reaching you. A masked token shows
        only its length and Shannon entropy, as
        "[REDACTED chars=20 entropy=3.8]". Judge from the rule name, the file path,
        the line number, and the surrounding context. High entropy and a config or
        source path suggest a real credential; low entropy, or paths like
        spec/, test/, fixtures/, docs/, README, *.example, *.sample suggest not.

        Never claim to have read the secret. Reply for every index you are given.
      PROMPT

      module_function

      # Returns a new array of findings, each with triage fields filled where the
      # model answered. Findings the model skipped come back untouched.
      def call(findings, **chat_options)
        return findings if findings.empty?

        verdicts = request(findings, **chat_options)
        findings.each_with_index.map do |finding, index|
          verdict = verdicts[index]
          verdict ? finding.with(**verdict) : finding
        end
      end

      def request(findings, **chat_options)
        configure
        chat = RubyLLM.chat(**chat_options.compact)
                      .with_instructions(SYSTEM_PROMPT)
                      .with_schema(Schema)
        # On 1.16 a schema-backed reply arrives parsed on #content (there is no
        # #parsed), and stays a String if the provider returned unparseable JSON.
        parse(chat.ask(prompt_for(findings)).content, findings.size)
      rescue *FAILURES => e
        raise Error, "AI triage failed: #{e.class}: #{e.message}"
      end

      # RubyLLM reads no provider credentials from the environment on its own,
      # and a CLI has nowhere else to get them.
      def configure
        RubyLLM.configure do |config|
          config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
          config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
          config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", OLLAMA_DEFAULT_BASE)
        end
      end

      # Rebuilds each finding's line from disk so redaction sees the whole line,
      # never the already-truncated preview. Unreadable files fall back to the
      # preview, which is redacted the same way.
      def prompt_for(findings)
        lines = Hash.new { |cache, path| cache[path] = read_lines(path) }

        findings.each_with_index.map { |finding, index| entry(finding, index, lines) }.join("\n")
      end

      def entry(finding, index, lines)
        raw = lines[finding.file]&.[](finding.line - 1) || finding.preview
        <<~ENTRY
          #{index}. rule=#{finding.rule} severity=#{finding.severity}
             location=#{finding.file}:#{finding.line}
             context=#{Redactor.redact(raw.chomp)}
        ENTRY
      end

      def read_lines(path)
        File.readlines(path, encoding: "UTF-8")
      rescue ArgumentError, SystemCallError
        nil
      end

      def parse(content, count)
        return {} unless content.is_a?(Hash)

        Array(content["verdicts"]).each_with_object({}) do |row, acc|
          index = verdict_index(row, count)
          next unless index

          acc[index] = { verdict: row["verdict"],
                         confidence: row["confidence"].to_f.clamp(0.0, 1.0),
                         rationale: rationale(row["rationale"]) }
        end
      end

      # Models routinely blow past the length the schema asks for, and these land
      # in a terminal one line per finding, so the limit is enforced here too.
      def rationale(raw)
        text = raw.to_s.strip
        return text if text.length <= RATIONALE_LIMIT

        "#{text[0, RATIONALE_LIMIT - 1]}…"
      end

      # Only an in-range index paired with a label we asked for is usable; anything
      # else is dropped so it cannot shift another finding's verdict.
      def verdict_index(row, count)
        return unless row.is_a?(Hash)

        index = row["index"]
        return unless index.is_a?(Integer) && index.between?(0, count - 1)
        return unless VERDICTS.include?(row["verdict"])

        index
      end
    end
  end
end
