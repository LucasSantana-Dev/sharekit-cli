# frozen_string_literal: true

RSpec.describe Sharekit::Cli::Reporter do
  def finding(severity, rule: "Test Rule")
    Sharekit::Cli::Finding.new(rule:, file: "f.txt", line: 1, preview: "p", severity:)
  end

  it "prints a clean message and does not raise when there are no findings" do
    expect { described_class.report([]) }.to output(/No secrets detected/).to_stdout
  end

  it "raises and blocks when a high-severity finding is present without --force" do
    expect { described_class.report([finding(:high)]) }
      .to raise_error(Sharekit::Cli::Error, /export blocked/)
  end

  it "does not raise for a high-severity finding when force: true" do
    expect { described_class.report([finding(:high)], force: true) }.not_to raise_error
  end

  it "does not raise for medium/low findings even without --force" do
    expect { described_class.report([finding(:medium), finding(:low)]) }.not_to raise_error
  end

  it "still prints a warning for medium-severity findings" do
    expect { described_class.report([finding(:medium)]) }.to output(/Secret patterns detected/).to_stdout
  end

  it "formats a finding line via pattern-matching deconstruction" do
    line = described_class.format_line(finding(:high, rule: "AWS Access Key ID"))
    expect(line).to eq("f.txt:1 [AWS Access Key ID] p")
  end
end
