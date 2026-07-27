## [Unreleased]

## [0.3.0] - 2026-07-27

- Gem renamed from `sharekit-cli` to `leakless`. Module `Sharekit::Cli` is now
  `Leakless::Cli`, the executable is now `leakless`, and the repository moved to
  `github.com/LucasSantana-Dev/leakless`. No behavior changes. `sharekit-cli`
  0.2.0 remains on RubyGems as the final release under the old name.

## [0.2.0] - 2026-07-26

- `scan --ai-triage` labels each finding `true_positive`, `false_positive` or
  `uncertain` with a confidence and a one-line rationale, via RubyLLM structured
  output. Works against any RubyLLM provider; `--provider ollama` needs no setup.
- `ruby_llm` is an **optional** dependency, not a runtime one: `scan` alone pulls
  nothing new, and `--ai-triage` without it reports how to install it. Run
  `gem install ruby_llm` to enable triage.
- Secret values are never transmitted, and there is no opt-out. Findings are
  reduced to their shape (length plus Shannon entropy) before the prompt is
  built. See `docs/adr/2026-07-26-redact-always-ai-triage.md`.
- Verdicts are advisory: the high-severity gate ignores them.

## [0.1.0] - 2026-07-25

- Initial release
