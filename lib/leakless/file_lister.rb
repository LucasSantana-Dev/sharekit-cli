# frozen_string_literal: true

require "open3"

module Leakless
  module Cli
    # Picks which files a scan should look at. Inside a git repo, defers to
    # `git ls-files` (tracked + untracked-but-not-ignored) so .gitignore is
    # respected for free instead of reimplementing its match semantics.
    # Outside a git repo, falls back to a plain glob with noise directories
    # excluded.
    module FileLister
      DEFAULT_EXCLUDED_DIRS = %w[.git node_modules vendor .bundle].freeze

      module_function

      def list(dir)
        git_tracked_files(dir) || glob_files(dir)
      end

      # Returns nil (not an empty array) when +dir+ isn't inside a git repo or
      # git isn't installed, so the caller falls back to glob_files instead of
      # silently scanning nothing.
      def git_tracked_files(dir)
        out, status = Open3.capture2("git", "-C", dir, "ls-files", "--cached", "--others", "--exclude-standard")
        return nil unless status.success?

        out.lines.map { |line| File.join(dir, line.chomp) }
      rescue Errno::ENOENT
        nil
      end

      def glob_files(dir)
        Dir.glob("#{dir}/**/*").select { |path| File.file?(path) && !excluded?(path) }
      end

      def excluded?(path)
        DEFAULT_EXCLUDED_DIRS.any? { |dir_name| path.split(File::SEPARATOR).include?(dir_name) }
      end
    end
  end
end
