# frozen_string_literal: true

require "leakless/redactor"

RSpec.describe Leakless::Cli::Redactor do
  # Fake credentials, shaped to match each Scanner rule. Nothing here is live.
  #
  # They also have to read as fake to *other* scanners. GitHub's push protection
  # blocks a push whose diff contains something its own detectors recognise, so a
  # fixture that mimics a provider's exact layout gets the branch rejected even
  # when the value is invented. The Slack entry keeps words where a real token has
  # digit groups for that reason: it still matches Scanner's `xox[baprs]-` rule
  # without matching Slack's format. Do not "tidy" it into a realistic shape.
  secrets = {
    "AWS access key" => "AKIA4RTQZK9WXDLM2PVB",
    "GitHub PAT" => "ghp_9fKq2LmZx8RtVwN4dCsB6yTgHjPu3aEr",
    "Slack token" => "xoxb-NOT-A-REAL-SLACK-TOKEN-000000",
    "Google API key" => "AIzaTgV7kQm3XpRb9NwLcZd2YfHs6JuE4Aq",
    # Segments are deliberately not valid base64-JSON: a decodable `{"alg":...}`
    # header is what JWT detectors look for, and GitGuardian failed the PR over it.
    "JWT bearer" => "Bearer eyJ-NOT-A-REAL-JWT.HEADER-IS-FAKE.SIGNATURE-IS-FAKE"
  }.freeze

  describe ".redact" do
    secrets.each do |label, secret|
      it "masks a #{label} and leaves no 12-character run of it behind" do
        redacted = described_class.redact("value = #{secret}")

        expect(redacted).not_to include(secret)
        # A partial mask is still a leak: check every window, not just the whole token.
        secret.delete_prefix("Bearer ").each_char.each_cons(12).map(&:join).each do |window|
          expect(redacted).not_to include(window)
        end
      end
    end

    it "masks every secret on the line, not only the one a scan would report" do
      line = "AKIA4RTQZK9WXDLM2PVB and ghp_9fKq2LmZx8RtVwN4dCsB6yTgHjPu3aEr"

      redacted = described_class.redact(line)

      expect(redacted).not_to include("AKIA4RTQZK9WXDLM2PVB")
      expect(redacted).not_to include("ghp_9fKq2LmZx8RtVwN4dCsB6yTgHjPu3aEr")
    end

    it "masks a sensitive env-var value while keeping the key name" do
      redacted = described_class.redact("API_KEY=s3cretvalue")

      expect(redacted).to start_with("API_KEY=")
      expect(redacted).not_to include("s3cretvalue")
    end

    it "masks a sensitive value that follows a non-sensitive assignment on the same line" do
      # Scanner's ENV_VAR_PATTERN captures `(.*)$`, so the first `KEY=` on a line is
      # the only one it reports. If redaction inherits that, a short secret behind a
      # boring assignment survives: too short for the generic backstop, never seen by
      # the env-var pass.
      redacted = described_class.redact("PATH=/usr/bin API_KEY=short1")

      expect(redacted).not_to include("short1")
    end

    it "masks a high-entropy run that no rule claims" do
      redacted = described_class.redact("blob: Zx8RtVwN4dCsB6yTgHjPu3aErQ")

      expect(redacted).not_to include("Zx8RtVwN4dCsB6yTgHjPu3aErQ")
      expect(redacted).to start_with("blob: ")
    end

    it "masks a home-directory username" do
      expect(described_class.redact("path: /Users/somebody/x")).not_to include("somebody")
    end

    it "keeps surrounding context intact, since that is the triage signal" do
      redacted = described_class.redact("# example only: AKIA4RTQZK9WXDLM2PVB")

      expect(redacted).to start_with("# example only: ")
    end

    it "reports the masked token's length and entropy" do
      expect(described_class.redact("k = AKIA4RTQZK9WXDLM2PVB"))
        .to match(/\[REDACTED chars=20 entropy=\d\.\d\]/)
    end

    it "leaves a line with nothing secret-shaped unchanged" do
      expect(described_class.redact("puts 'hello'")).to eq("puts 'hello'")
    end
  end

  describe ".entropy" do
    it "scores a random token above a repetitive placeholder" do
      expect(described_class.entropy("AKIA4RTQZK9WXDLM2PVB"))
        .to be > described_class.entropy("AAAAAAAAAAAAAAAAAAAA")
    end

    it "is 0.0 for an empty string" do
      expect(described_class.entropy("")).to eq(0.0)
    end
  end
end
