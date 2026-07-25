# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Sharekit::Cli::App do
  def run(*args)
    described_class.start(args)
  end

  around do |example|
    Dir.mktmpdir("sharekit-cli-spec-") do |dir|
      @dir = dir
      example.run
    end
  end

  def write(relative_path, content)
    full = File.join(@dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  it "prints a clean message and exits 0 for a directory with no secrets" do
    write("README.md", "# clean instructions\n")

    expect { run("scan", @dir) }.to output(/No secrets detected/).to_stdout
  end

  it "exits 1 and prints an error for a high-severity secret without --force" do
    write("CLAUDE.md", "# instructions\n-----BEGIN PRIVATE KEY-----\nTest\n-----END PRIVATE KEY-----")

    expect { run("scan", @dir) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
  end

  it "succeeds with --force even when a high-severity secret is present" do
    write("CLAUDE.md", "# instructions\n-----BEGIN PRIVATE KEY-----\nTest\n-----END PRIVATE KEY-----")

    expect { run("scan", @dir, "--force") }.not_to raise_error
  end

  it "warns but does not exit non-zero for medium-severity findings" do
    write("CLAUDE.md", "# instructions\nAPI_TOKEN=faketoken000001")

    expect { run("scan", @dir) }.to output(/Secret patterns detected/).to_stdout
  end

  it "skips unreadable files and still reports findings from readable ones" do
    write("CLAUDE.md", "# instructions\n-----BEGIN PRIVATE KEY-----\nTest\n-----END PRIVATE KEY-----")
    unreadable = File.join(@dir, "secrets.txt")
    File.write(unreadable, "content")
    File.chmod(0o000, unreadable)

    begin
      expect { run("scan", @dir) }.to output(/Skipped.*secrets\.txt/).to_stdout.and raise_error(SystemExit)
    ensure
      File.chmod(0o644, unreadable)
    end
  end

  describe "init" do
    def profile_dir
      File.join(@dir, "sharekit-profile")
    end

    it "scaffolds a profile and exits 0 when the source has no secrets" do
      expect { run("init", "--dir", profile_dir) }.to output(/Created profile/).to_stdout
      expect(File).to exist(File.join(profile_dir, "sharekit.toml"))
    end

    it "exits 1 without --force when the source CLAUDE.md has a high-severity secret" do
      claude_md = File.join(@dir, ".claude", "CLAUDE.md")
      write(".claude/CLAUDE.md", "# instructions\n-----BEGIN PRIVATE KEY-----\nTest\n-----END PRIVATE KEY-----")
      expect(File).to exist(claude_md) # sanity: write helper worked before we override HOME below

      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("HOME", anything).and_return(@dir)

      expect { run("init", "--dir", profile_dir) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end

    it "succeeds with --force even when a high-severity secret is present" do
      write(".claude/CLAUDE.md", "# instructions\n-----BEGIN PRIVATE KEY-----\nTest\n-----END PRIVATE KEY-----")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("HOME", anything).and_return(@dir)

      expect { run("init", "--dir", profile_dir, "--force") }.not_to raise_error
    end
  end
end
