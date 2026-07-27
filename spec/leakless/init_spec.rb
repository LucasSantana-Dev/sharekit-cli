# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Leakless::Cli::Init do
  around do |example|
    Dir.mktmpdir("leakless-init-spec-") do |tmp|
      @tmp = tmp
      @source_root = File.join(tmp, "source")
      @profile_dir = File.join(tmp, "sharekit-profile")
      example.run
    end
  end

  def write_source_claude_md(content)
    path = File.join(@source_root, ".claude", "CLAUDE.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def call(force: false, skill_names: [])
    described_class.call(profile_dir: @profile_dir, skill_names:, source_root: @source_root, force:)
  end

  it "scaffolds sharekit.toml even with no source config present" do
    result = call
    expect(File).to exist(File.join(@profile_dir, "sharekit.toml"))
    expect(result.findings).to be_empty
  end

  it "writes a placeholder CLAUDE.md when the source has none" do
    call
    content = File.read(File.join(@profile_dir, "claude", "CLAUDE.md"))
    expect(content).to include("My AI coding instructions")
  end

  it "copies an existing CLAUDE.md instead of writing a placeholder" do
    write_source_claude_md("# real instructions\nNo secrets here.")
    call
    content = File.read(File.join(@profile_dir, "claude", "CLAUDE.md"))
    expect(content).to eq("# real instructions\nNo secrets here.")
  end

  it "surfaces secret findings when the copied CLAUDE.md contains one" do
    write_source_claude_md("# instructions\nAPI_KEY=fakevalue000001")
    result = call
    expect(result.findings).not_to be_empty
    expect(result.findings.map(&:file)).to include(a_string_matching(/CLAUDE\.md/))
  end

  it "does not surface findings for clean source content" do
    write_source_claude_md("# instructions\nNo secrets here.")
    result = call
    expect(result.findings).to be_empty
  end

  it "creates an empty shared/ directory with a .gitkeep" do
    call
    expect(File).to exist(File.join(@profile_dir, "shared", ".gitkeep"))
  end

  it "raises if the profile dir already exists without --force" do
    FileUtils.mkdir_p(@profile_dir)
    expect { call }.to raise_error(Leakless::Cli::Error, /already exists/)
  end

  it "overwrites the existing profile dir with --force" do
    FileUtils.mkdir_p(@profile_dir)
    File.write(File.join(@profile_dir, "stale.txt"), "old")
    call(force: true)
    expect(File).not_to exist(File.join(@profile_dir, "stale.txt"))
    expect(File).to exist(File.join(@profile_dir, "sharekit.toml"))
  end

  it "copies a requested skill directory and scans its files" do
    skill_path = File.join(@source_root, ".claude", "skills", "my-skill", "SKILL.md")
    FileUtils.mkdir_p(File.dirname(skill_path))
    File.write(skill_path, "# my skill\nAKIAEXAMPLEKEY000000")

    result = call(skill_names: ["my-skill"])

    dest = File.join(@profile_dir, "claude", "skills", "my-skill", "SKILL.md")
    expect(File).to exist(dest)
    expect(result.findings.map(&:rule)).to include("AWS Access Key ID")
  end

  it "warns and continues when a requested skill doesn't exist" do
    expect { call(skill_names: ["missing-skill"]) }.to output(/not found/).to_stdout
  end
end
