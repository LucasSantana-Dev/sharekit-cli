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
- **`Data#with` for the triage pass.** Verdicts are layered onto findings by returning new
  `Finding`s, so the scan result is never mutated and an untriaged finding is structurally
  the same object it always was. The triage fields default to `nil` via a keyword-splat
  `super`, which is how `Data.define` takes defaults at all.
- **`autoload` for the AI path.** `require "ruby_llm"` pulls in a provider stack that a plain
  `scan` never touches, so `Triage` is resolved on first reference. One stdlib line instead of
  an optional-dependency dance.
- **Thor** for CLI dispatch instead of hand-parsed `ARGV`/flags.
- **`git ls-files`, not a hand-rolled ignore-file parser.** `scan` defers to git for
  `.gitignore`-aware file listing when run inside a repo (via `Open3`, argv-array — no shell
  interpolation), instead of reimplementing gitignore match semantics.

## Install

```bash
gem install sharekit-cli
```

Or add to a `Gemfile`:

```ruby
gem "sharekit-cli"
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

### AI triage

`--ai-triage` labels each finding as a real leak, a placeholder, or unclear, so a docs
sample stops looking exactly like a live key:

```bash
sharekit-cli scan --ai-triage                                        # any configured provider
sharekit-cli scan --ai-triage --provider ollama --model qwen3:4b \
                  --assume-model-exists                              # fully local
```

```text
  ⚠  Secret patterns detected:
    config/secrets.env:1 [AWS Access Key ID] …_KEY=AKIAEXAMPLEKEY000000
      → likely real (95% confident) Config path, not a test or docs fixture.
    docs/example.md:3 [AWS Access Key ID] …ple `AKIAIOSFODNN7EXAMPLE…
      → likely placeholder (98% confident) Documentation path, context says "for example".

  ⚠  AI verdicts are advisory: the high-severity gate ignores them.
```

**Secret values are never sent, and there is no flag to send them.** Before a prompt is
built, each finding's line is re-read from disk and every secret in it is replaced by its
shape alone, as `[REDACTED chars=20 entropy=3.8]`. What the model gets is the rule name,
the path, the line number, that shape, and whatever context survived. Redaction runs on the
whole line rather than the truncated `preview` for a reason: truncation can cut a secret so
that its own rule no longer matches it, and the fragment would survive. Reasoning is in
[the ADR](docs/adr/2026-07-26-redact-always-ai-triage.md).

Credentials come from `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`. `--provider ollama` needs
neither and defaults to `http://localhost:11434/v1` (override with `OLLAMA_API_BASE`), which
keeps even the redacted shape on your machine.

Verdicts annotate; they never unblock. A model deciding a live key isn't a key is not a
failure mode worth having, so the gate stays independent of it.

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
bundle exec rspec                    # run the test suite (92 examples)
bundle exec rubocop                  # lint
bundle exec bundler-audit check --update  # dependency vulnerability scan
bin/console                          # interactive prompt
```

## License

MIT.
