## [Unreleased]

## [0.2.0] - 2026-07-26

- `scan --ai-triage` labels each finding `true_positive`, `false_positive` or
  `uncertain` with a confidence and a one-line rationale, via RubyLLM structured
  output. Works against any RubyLLM provider; `--provider ollama` needs no setup.
- Secret values are never transmitted, and there is no opt-out. Findings are
  reduced to their shape (length plus Shannon entropy) before the prompt is
  built. See `docs/adr/2026-07-26-redact-always-ai-triage.md`.
- Verdicts are advisory: the high-severity gate ignores them.

## [0.1.0] - 2026-07-25

- Initial release
