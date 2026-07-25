# frozen_string_literal: true

require_relative "lib/sharekit/cli/version"

Gem::Specification.new do |spec|
  spec.name = "sharekit-cli"
  spec.version = Sharekit::Cli::VERSION
  spec.authors = ["Lucas Santana"]
  spec.email = ["lucas.diassantana@gmail.com"]

  spec.summary = "Scan a directory for leaked secrets before you publish it."
  spec.description = "A small rule-driven CLI that scans files for private keys, cloud/API tokens, " \
                      "and sensitive env vars, and blocks on high-severity findings unless --force is given."
  spec.homepage = "https://github.com/LucasSantana-Dev/sharekit-cli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
