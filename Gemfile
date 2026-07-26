# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in sharekit-cli.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.0"

gem "rubocop", "~> 1.21"
# rubocop pulls parallel (>= 1.10). The entire parallel 2.x line requires Ruby >= 3.3,
# so it cannot install on the 3.2 leg of the CI matrix while the lock is resolved on
# 3.4. 1.28 is the newest release that still supports 3.2. Cap it so one dev-only
# transitive dep does not decide the gem's supported Ruby versions; drop the cap when
# 3.2 leaves the matrix and required_ruby_version moves off it.
gem "parallel", "< 2.0"

gem "bundler-audit", "~> 0.9"
