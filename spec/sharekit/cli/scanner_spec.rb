# frozen_string_literal: true

RSpec.describe Sharekit::Cli::Scanner do
  def scan(content, file: nil)
    described_class.scan(content, file:).to_a
  end

  it "returns an Enumerator when no block is given" do
    expect(described_class.scan("hello")).to be_an(Enumerator)
  end

  it "yields to a block instead of building an array, when one is given" do
    yielded = []
    described_class.scan("AKIA#{"A" * 16}") { |finding| yielded << finding }
    expect(yielded).not_to be_empty
  end

  it "detects an AWS access key" do
    findings = scan("aws_key = AKIAEXAMPLEKEY000000")
    expect(findings.first.rule).to eq("AWS Access Key ID")
    expect(findings.first.line).to eq(1)
    expect(findings.first.preview).to include("AKIA")
  end

  it "detects a private key block" do
    content = <<~KEY
      -----BEGIN RSA PRIVATE KEY-----
      FAKEKEYBODY
      -----END RSA PRIVATE KEY-----
    KEY
    findings = scan(content)
    expect(findings.first.rule).to eq("Private Key Block")
    expect(findings.first.severity).to eq(:high)
  end

  it "detects a GitHub PAT (ghp_ format)" do
    findings = scan("token = ghp_#{"a" * 36}")
    expect(findings.first.rule).to eq("GitHub Personal Access Token")
    expect(findings.first.severity).to eq(:high)
  end

  it "detects a GitHub PAT (github_pat_ format)" do
    findings = scan("token = github_pat_#{"a" * 22}")
    expect(findings.first.rule).to eq("GitHub Personal Access Token")
  end

  it "detects a Slack token" do
    findings = scan("slack = xoxb-EXAMPLE-NOT-A-REAL-token")
    expect(findings.first.rule).to eq("Slack Token")
    expect(findings.first.severity).to eq(:high)
  end

  it "detects a Google API key" do
    findings = scan("google_key = AIza#{"a" * 35}")
    expect(findings.first.rule).to eq("Google API Key")
  end

  it "detects Google API keys at the 34-char boundary" do
    expect(scan("google_key = AIza#{"a" * 34}")).not_to be_empty
  end

  it "detects Google API keys at the 39-char boundary" do
    expect(scan("google_key = AIza#{"a" * 39}")).not_to be_empty
  end

  it "does not detect Google API keys below the 30-char minimum" do
    expect(scan("google_key = AIza#{"a" * 29}")).to be_empty
  end

  it "detects a bearer token" do
    findings = scan("Authorization: Bearer eyJx.y.z")
    expect(findings.first.rule).to eq("Bearer Token")
    expect(findings.first.severity).to eq(:high)
  end

  it "detects a home directory path leak (macOS)" do
    findings = scan("backup_dir = /Users/alice/.ssh/id_rsa")
    expect(findings.first.rule).to eq("Home Directory Path Leak")
    expect(findings.first.severity).to eq(:low)
  end

  it "detects a home directory path leak (Linux)" do
    findings = scan("backup_dir = /home/bob/.ssh/id_rsa")
    expect(findings.first.rule).to eq("Home Directory Path Leak")
  end

  %w[SECRET TOKEN PASSWORD API_KEY].each do |suffix|
    it "detects an env var with a #{suffix} key" do
      findings = scan("MY_#{suffix}=fakevalue000001")
      expect(findings.map(&:rule)).to include(a_string_matching(/Env/))
    end
  end

  it "detects APIKEY (single word, no underscore)" do
    findings = scan("GITHUB_APIKEY=fakevalue000001")
    expect(findings.map(&:rule)).to include(a_string_matching(/Env/))
  end

  it "detects ACCESS_KEY" do
    findings = scan("AWS_ACCESS_KEY=fakevalue000001")
    expect(findings.map(&:rule)).to include(a_string_matching(/Env/))
  end

  it "detects an `export KEY=value` prefix" do
    findings = scan("export API_KEY=fakevalue000001")
    expect(findings.first.rule).to eq("Env Var: Sensitive Key")
    expect(findings.first.severity).to eq(:medium)
  end

  it "assigns medium severity to sensitive env vars" do
    findings = scan("API_TOKEN=#{"a" * 25}")
    expect(findings.first.severity).to eq(:medium)
  end

  it "ignores an empty env value" do
    expect(scan('API_KEY=""')).to be_empty
  end

  it "ignores placeholder env values" do
    content = <<~ENV
      API_KEY=xxx
      API_TOKEN=<your-token-here>
      DB_PASSWORD=changeme
      SECRET=your-secret
    ENV
    expect(scan(content)).to be_empty
  end

  it "ignores ordinary prose that merely mentions secret-sounding words" do
    content = <<~TEXT
      # My API documentation
      This is a secret between us, but the secret ingredient is love.
      TOKEN of appreciation for your help.
      PASSWORD protected area.
    TEXT
    expect(scan(content)).to be_empty
  end

  it "ignores ordinary non-sensitive KEY=value assignments" do
    content = <<~ENV
      NODE_ENV=production
      DEBUG=false
      SOME_PATH=/usr/local/bin
    ENV
    expect(scan(content)).to be_empty
  end

  it "reports the correct line number for a match past the first line" do
    content = "line 1\nAKIAEXAMPLEKEY000000 on line 2\nline 3"
    findings = scan(content)
    expect(findings.length).to eq(1)
    expect(findings.first.line).to eq(2)
  end

  it "truncates long previews" do
    findings = scan("MY_SECRET=#{"a" * 200}")
    expect(findings.first.preview.length).to be <= 50
    expect(findings.first.preview).to include("…")
  end

  it "includes the given file label on each finding" do
    findings = scan("AKIAEXAMPLEKEY000000", file: "~/.claude/CLAUDE.md")
    expect(findings.first.file).to eq("~/.claude/CLAUDE.md")
  end

  it "detects multiple findings across one piece of content" do
    content = <<~CONTENT
      AKIAEXAMPLEKEY000000
      -----BEGIN PRIVATE KEY-----
      test secret
      -----END PRIVATE KEY-----
      API_TOKEN=faketoken000001
    CONTENT
    expect(scan(content).length).to be >= 2
  end
end
