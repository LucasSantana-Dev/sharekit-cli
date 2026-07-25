# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe Sharekit::Cli::FileLister do
  def write(dir, relative_path, content = "x")
    full = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  context "outside a git repo" do
    it "lists files, excluding default noise directories" do
      Dir.mktmpdir do |dir|
        write(dir, "README.md")
        write(dir, "node_modules/pkg/index.js")
        write(dir, "vendor/lib.rb")
        write(dir, ".bundle/config")

        listed = described_class.list(dir).map { |f| f.sub("#{dir}/", "") }

        expect(listed).to contain_exactly("README.md")
      end
    end
  end

  context "inside a git repo" do
    def init_git_repo(dir)
      Open3.capture2("git", "-C", dir, "init", "-q")
      Open3.capture2("git", "-C", dir, "config", "user.email", "test@example.com")
      Open3.capture2("git", "-C", dir, "config", "user.name", "Test")
    end

    it "respects .gitignore instead of a hardcoded exclude list" do
      Dir.mktmpdir do |dir|
        init_git_repo(dir)
        write(dir, ".gitignore", "ignored.txt\n")
        write(dir, "tracked.txt")
        write(dir, "ignored.txt")
        write(dir, "untracked-but-not-ignored.txt")
        Open3.capture2("git", "-C", dir, "add", "tracked.txt", ".gitignore")

        listed = described_class.list(dir).map { |f| f.sub("#{dir}/", "") }

        expect(listed).to include("tracked.txt", "untracked-but-not-ignored.txt")
        expect(listed).not_to include("ignored.txt")
      end
    end
  end

  context "when git is unavailable or the dir isn't a repo" do
    it "falls back to the plain glob without raising" do
      Dir.mktmpdir do |dir|
        write(dir, "a.txt")
        expect(described_class.git_tracked_files(dir)).to be_nil
        expect(described_class.list(dir)).to include(File.join(dir, "a.txt"))
      end
    end
  end
end
