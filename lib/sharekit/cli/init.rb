# frozen_string_literal: true

require "fileutils"

module Sharekit
  module Cli
    # Scaffolds a publishable sharekit profile: sharekit.toml, a claude/
    # CLAUDE.md, a cursor/.cursorrules, an empty shared/, and any requested
    # skill directories — copied from the caller's own AI-tooling config, so
    # the result becomes an install target for `sharekit install <user>`.
    class Init
      Result = Data.define(:profile_dir, :findings, :created)
      SourceFile = Data.define(:source, :dest, :placeholder)

      def self.call(profile_dir:, skill_names: [], source_root: ENV.fetch("HOME", Dir.pwd), force: false)
        new(profile_dir:, skill_names:, source_root:, force:).call
      end

      def initialize(profile_dir:, skill_names:, source_root:, force:)
        @profile_dir = profile_dir
        @skill_names = skill_names
        @source_root = source_root
        @force = force
        @findings = []
        @created = []
      end

      STANDARD_FILES = [
        SourceFile.new(source: [".claude", "CLAUDE.md"], dest: %w[claude CLAUDE.md],
                       placeholder: "# My AI coding instructions\n"),
        SourceFile.new(source: [".cursor", ".cursorrules"], dest: %w[cursor .cursorrules],
                       placeholder: "# Cursor IDE rules\n")
      ].freeze

      def call
        prepare_profile_dir
        write_manifest
        STANDARD_FILES.each { |file| scaffold(file) }
        scaffold_shared
        @skill_names.each { |name| scaffold_skill(name) }

        Result.new(profile_dir: @profile_dir, findings: @findings, created: @created)
      end

      private

      def prepare_profile_dir
        if Dir.exist?(@profile_dir)
          raise Error, "Profile directory already exists: #{@profile_dir}. Use --force to overwrite." unless @force

          FileUtils.rm_rf(@profile_dir)
        end
        FileUtils.mkdir_p(@profile_dir)
      end

      def write_manifest
        path = File.join(@profile_dir, "sharekit.toml")
        File.write(path, <<~TOML)
          [profile]
          name = "#{ENV.fetch("USER", "unknown")}"
          version = "0.1.0"
          description = "My AI coding setup"
        TOML
        @created << path
      end

      def scaffold(file)
        source = File.join(@source_root, *file.source)
        dest = File.join(@profile_dir, *file.dest)
        FileUtils.mkdir_p(File.dirname(dest))
        if File.exist?(source)
          FileUtils.cp(source, dest)
          scan_and_record(dest)
        else
          File.write(dest, file.placeholder)
        end
        @created << dest
      end

      def scaffold_shared
        dir = File.join(@profile_dir, "shared")
        FileUtils.mkdir_p(dir)
        FileUtils.touch(File.join(dir, ".gitkeep"))
        @created << dir
      end

      def scaffold_skill(name)
        source_dir = File.join(@source_root, ".claude", "skills", name)
        unless Dir.exist?(source_dir)
          puts "  ~ skill '#{name}' not found at #{source_dir}"
          return
        end

        dest_base = File.join(@profile_dir, "claude", "skills", name)
        Dir.glob("#{source_dir}/**/*").select { |f| File.file?(f) }.each do |source_file|
          copy_skill_file(source_file, source_dir, dest_base)
        end
      end

      def copy_skill_file(source_file, source_dir, dest_base)
        dest_file = File.join(dest_base, source_file.delete_prefix("#{source_dir}/"))
        FileUtils.mkdir_p(File.dirname(dest_file))
        FileUtils.cp(source_file, dest_file)
        scan_and_record(dest_file)
        @created << dest_file
      end

      def scan_and_record(path)
        content = File.read(path, encoding: "UTF-8")
        @findings.concat(Scanner.scan(content, file: path).to_a)
      end
    end
  end
end
