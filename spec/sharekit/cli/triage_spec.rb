# frozen_string_literal: true

require "tmpdir"

RSpec.describe Sharekit::Cli::Triage do
  # Fake JWT with a deliberately short header segment. The scanner's 30-char
  # preview cuts this JWT after its first dot, leaving a 16-char fragment that
  # the Bearer rule (which needs two dots) no longer matches and that is too
  # short for Redactor's generic backstop, so it survives if anything redacts
  # the preview instead of the original line. That is the leak this pins.
  jwt = "Bearer eyJhbGciOiJIUzI1.eyJzdWIiOiI5MjMifQ.kQ7vRmXbN2wLcZdTgY4Hs"
  jwt_header = "eyJhbGciOiJIUzI1"
  aws_key = "AKIA4RTQZK9WXDLM2PVB"

  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:prompts) { [] }
  let(:content) { { "verdicts" => [] } }

  before do
    allow(RubyLLM).to receive(:chat).and_return(chat)
    allow(chat).to receive(:with_instructions).and_return(chat)
    allow(chat).to receive(:with_schema).and_return(chat)
    allow(chat).to receive(:ask) do |prompt|
      prompts << prompt
      instance_double(RubyLLM::Message, content:)
    end
  end

  def finding(rule: "AWS Access Key ID", preview: "p", severity: :high, file: "f.txt")
    Sharekit::Cli::Finding.new(rule:, file:, line: 1, preview:, severity:)
  end

  def verdict_row(index: 0, verdict: "false_positive", confidence: 0.9, rationale: "docs sample")
    { "index" => index, "verdict" => verdict, "confidence" => confidence, "rationale" => rationale }
  end

  def replying_with(verdicts)
    allow(chat).to receive(:ask)
      .and_return(instance_double(RubyLLM::Message, content: { "verdicts" => verdicts }))
  end

  describe "provider configuration" do
    around do |example|
      env = ENV.to_h
      config = %i[anthropic_api_key openai_api_key ollama_api_base]
               .to_h { |o| [o, RubyLLM.config.public_send(o)] }
      example.run
    ensure
      ENV.replace(env)
      config.each { |option, value| RubyLLM.config.public_send(:"#{option}=", value) }
    end

    it "applies ANTHROPIC_API_KEY from the environment to RubyLLM" do
      ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-value"

      described_class.call([finding])

      expect(RubyLLM.config.anthropic_api_key).to eq("sk-ant-test-value")
    end

    it "applies OPENAI_API_KEY from the environment to RubyLLM" do
      ENV["OPENAI_API_KEY"] = "sk-openai-test-value"

      described_class.call([finding])

      expect(RubyLLM.config.openai_api_key).to eq("sk-openai-test-value")
    end

    it "points Ollama at the local daemon when OLLAMA_API_BASE is unset" do
      ENV.delete("OLLAMA_API_BASE")

      described_class.call([finding])

      expect(RubyLLM.config.ollama_api_base).to eq("http://localhost:11434/v1")
    end
  end

  describe "redaction (security)" do
    it "redacts the line read from disk, not the finding's truncated preview" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "conf.rb")
        File.write(path, %(auth = "#{jwt}"\n))
        scanned = Sharekit::Cli::Scanner.scan(File.read(path), file: path).first

        described_class.call([scanned])

        # Instrument check: the preview really does carry a JWT fragment that the
        # Bearer rule can no longer match, so the assertion below can fail.
        expect(scanned.preview).to include(jwt_header)
        expect(prompts.first).not_to include(jwt_header)
      end
    end

    it "sends no context at all when the file cannot be read" do
      # The preview is truncated, so falling back to it can ship a fragment that
      # matches neither its own rule nor the backstop. Dropping context is correct.
      described_class.call([finding(file: "/nonexistent/x.rb", preview: "k=#{aws_key}")])

      expect(prompts.first).to include("[source unavailable]")
      expect(prompts.first).not_to include(aws_key)
    end

    it "redacts the file path, so a secret in a filename cannot ride along" do
      described_class.call([finding(file: "keys/#{aws_key}.pem")])

      expect(prompts.first).not_to include(aws_key)
      expect(prompts.first).to include("location=keys/")
    end

    it "sends the rule, severity and location the classifier needs" do
      described_class.call([finding])

      expect(prompts.first).to include("rule=AWS Access Key ID", "severity=high", "location=f.txt:1")
    end
  end

  describe ".call" do
    it "makes no request and returns the input when there are no findings" do
      expect(described_class.call([])).to eq([])
      expect(RubyLLM).not_to have_received(:chat)
    end

    context "with a verdict for each finding" do
      let(:content) do
        { "verdicts" => [verdict_row(index: 0, verdict: "false_positive", confidence: 0.9),
                         verdict_row(index: 1, verdict: "true_positive", confidence: 0.4, rationale: "live key")] }
      end

      it "attaches verdicts by index" do
        triaged = described_class.call([finding, finding(rule: "Slack Token")])

        expect(triaged.map(&:verdict)).to eq(%w[false_positive true_positive])
        expect(triaged.map(&:rationale)).to eq(["docs sample", "live key"])
        expect(triaged.first.confidence).to eq(0.9)
      end

      it "leaves the original findings untouched" do
        original = finding
        described_class.call([original, finding])

        expect(original.verdict).to be_nil
      end
    end

    it "leaves a finding untriaged when the model skips its index" do
      replying_with([verdict_row(index: 1)])

      triaged = described_class.call([finding, finding])

      expect(triaged.first).not_to be_triaged
      expect(triaged.last).to be_triaged
    end

    it "drops a verdict for an index that was never sent" do
      replying_with([verdict_row(index: 7)])

      expect(described_class.call([finding]).first).not_to be_triaged
    end

    it "drops a verdict whose label is not one we asked for" do
      replying_with([verdict_row(verdict: "probably_fine")])

      expect(described_class.call([finding]).first).not_to be_triaged
    end

    it "clamps an out-of-range confidence into 0.0..1.0" do
      replying_with([verdict_row(confidence: 4.2)])

      expect(described_class.call([finding]).first.confidence).to eq(1.0)
    end

    it "truncates a rationale that ignores the length we asked for" do
      replying_with([verdict_row(rationale: "x" * 400)])

      rationale = described_class.call([finding]).first.rationale

      expect(rationale.length).to eq(120)
      expect(rationale).to end_with("…")
    end

    it "tolerates a reply that stayed an unparsed String" do
      allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: "not json"))

      expect(described_class.call([finding]).first).not_to be_triaged
    end

    it "raises a Cli::Error when the provider fails" do
      allow(chat).to receive(:ask).and_raise(RubyLLM::ConfigurationError, "no api key")

      expect { described_class.call([finding]) }
        .to raise_error(Sharekit::Cli::Error, /AI triage failed.*no api key/)
    end

    it "passes model and provider through to RubyLLM" do
      described_class.call([finding], model: "qwen3", provider: :ollama, assume_model_exists: true)

      expect(RubyLLM).to have_received(:chat)
        .with(model: "qwen3", provider: :ollama, assume_model_exists: true)
    end
  end
end
