# sharekit-cli

A small CLI that scaffolds a publishable "AI coding setup" profile and scans a directory for
leaked secrets — private keys, cloud/API tokens, sensitive env vars — blocking on high-severity
findings unless you pass `--force`.

It's a Ruby port of the `init` and `scan` commands from
[sharekit](https://github.com/LucasSantana-Dev/sharekit), a TypeScript CLI I built and publish
to npm. This port is deliberately not a line-for-line translation — it's rebuilt around Ruby
idioms that don't have a clean TS equivalent:

- **`Data.define`** for the immutable `Finding` value object, with `Comparable` mixed in for
  free severity-ranked sorting, and free `Hash` deconstruction for pattern matching.
- **A rule table, not an if/elsif chain.** Each secret pattern is a `Scanner::Rule` (a `Data`
  object: pattern + severity + preview metadata), stored in a frozen array. Adding a rule means
  appending to `RULES` — the scan loop itself never changes.
- **`Enumerator` dual API.** `Scanner.scan` yields to a block when one is given, or returns an
  `Enumerator` when it isn't (`return to_enum(:scan, ...) unless block_given?`) — the same
  pattern as `Array#each`. Callers can stream (`each { }`) or collect (`.to_a`, `.first`, `.lazy`)
  without the scanner caring which.
- **`case/in` pattern matching** in `Reporter.format_line`, matching directly on the `Finding`'s
  deconstructed fields instead of manual attribute access.
- **Thor** for CLI dispatch instead of hand-parsed `ARGV`/flags.
- **`git ls-files`, not a hand-rolled ignore-file parser.** `scan` defers to git for
  `.gitignore`-aware file listing when run inside a repo (via `Open3`, argv-array — no shell
  interpolation), instead of reimplementing gitignore match semantics.

## Install

Not yet published to RubyGems. Install straight from git:

```bash
gem install specific_install
gem specific_install https://github.com/LucasSantana-Dev/sharekit-cli.git
```

Or add to a `Gemfile`:

```ruby
gem "sharekit-cli", git: "https://github.com/LucasSantana-Dev/sharekit-cli.git"
```

## Usage

```bash
sharekit-cli scan [DIR]          # scan a directory (default: .)
sharekit-cli scan [DIR] --force  # don't block on high-severity findings

sharekit-cli init [SKILL...]              # scaffold ./sharekit-profile
sharekit-cli init --dir PATH [SKILL...]   # scaffold at a custom path
sharekit-cli init --force                 # overwrite an existing dir; override secret blocking
```

```
$ sharekit-cli scan .

  ⚠  Secret patterns detected:
    .env:1 [AWS Access Key ID] …Y=AKIAEXAMPLEKEY000000

  ⚠  Review and redact secrets before pushing to a public repository.

Secrets export blocked: 1 high-severity finding(s) detected. Review and remove secrets, or re-run with --force to override.
```

Both commands exit `1` when a high-severity secret is found and `--force` wasn't passed; `0`
otherwise. `init` copies `~/.claude/CLAUDE.md` and `~/.cursor/.cursorrules` into the new profile
(or writes placeholders if they don't exist) and scans everything it copies for secrets before
reporting success.

### Rules

| Rule                          | Severity |
|--------------------------------|----------|
| Private Key Block              | high     |
| AWS Access Key ID              | high     |
| GitHub Personal Access Token   | high     |
| Slack Token                    | high     |
| Google API Key                 | high     |
| Bearer Token (JWT)             | high     |
| Home Directory Path Leak       | low      |
| Env Var: Sensitive Key         | medium   |

## Development

```bash
bin/setup                            # install dependencies
bundle exec rspec                    # run the test suite (61 examples)
bundle exec rubocop                  # lint
bundle exec bundler-audit check --update  # dependency vulnerability scan
bin/console                          # interactive prompt
```

## License

MIT.
