# frozen_string_literal: true

RSpec.describe Leakless::Cli::Finding do
  def finding(severity)
    described_class.new(rule: "r", file: "f", line: 1, preview: "p", severity:)
  end

  it "is immutable (Data.define value semantics)" do
    expect { finding(:high).instance_variable_set(:@rule, "x") }.to raise_error(FrozenError)
  end

  it "compares by severity rank via Comparable" do
    expect(finding(:low)).to be < finding(:medium)
    expect(finding(:medium)).to be < finding(:high)
    expect([finding(:high), finding(:low), finding(:medium)].sort.map(&:severity))
      .to eq(%i[low medium high])
  end

  it "#high? is true only for high severity" do
    expect(finding(:high).high?).to be true
    expect(finding(:medium).high?).to be false
    expect(finding(:low).high?).to be false
  end

  it "deconstructs into a Hash for pattern matching" do
    result = case finding(:high)
             in { severity: :high, rule: }
               "matched:#{rule}"
             end
    expect(result).to eq("matched:r")
  end
end
