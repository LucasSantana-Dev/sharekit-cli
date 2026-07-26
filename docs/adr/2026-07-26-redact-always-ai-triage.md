# Redact always in AI triage

- Status: accepted
- Date: 2026-07-26

## Context

`scan` is rule-driven, so it reports what a regex matched, not what the match
means. `AKIAIOSFODNN7EXAMPLE` in `docs/example.md` and a live key in
`config/secrets.env` produce the same high-severity finding, and the gate blocks
on both. Classifying findings needs a model, which means deciding what a secret
scanner is allowed to transmit about the secrets it just found.

The tool's whole promise is that it runs before you publish something. Sending
credentials to a third-party API in order to ask whether they are credentials
would invert that promise, and "we only send it when you pass `--raw`" still
ships a foot-gun in a security tool.

## Decision

Triage sends a finding's shape, never its value, with no opt-out.

- Every payload line is passed through `Redactor` first. A masked token is
  replaced by its length and Shannon entropy, e.g. `[REDACTED chars=20
  entropy=3.8]`.
- Redaction runs against the line re-read from disk, not the `Finding`'s
  `preview`. Truncation can cut a secret mid-token so its own rule no longer
  matches it, and the surviving fragment would ride along into the prompt.
- Every `Scanner` rule is applied, not just the one that produced the finding,
  so a second secret sharing the line is masked too. Sensitive env-var values are
  masked by key name, and a generic backstop masks any remaining run of 20+
  characters from the secret alphabet.
- `--provider ollama` works with no configuration, so the redacted shape can stay
  on the machine as well.
- Verdicts are advisory. The high-severity gate ignores them.

## Consequences

Classification accuracy is lower than it would be with raw values: the model
judges from rule name, path, line number, entropy and surviving context. That
turned out to be enough on the cases that matter, because the strongest signal is
the path (`docs/`, `spec/`, `*.example`) rather than the characters.

The generic backstop is deliberately over-eager. It masks long URLs, hashes and
base64 in prose, which makes some prompts noisier than necessary. Safety over
prompt tidiness: the claim "nothing 20 characters or longer from the secret
alphabet survives" is only true if it applies to material no rule claimed.

Keeping the gate model-independent means a false `false_positive` cannot unblock
a publish. It also means triage does not reduce the work when the verdict is
right, it only tells you where to look first. Letting verdicts relax the gate is
the obvious next request; it stays refused.

## Revisit when

Someone needs triage to change the exit code, or a provider offers an
attestable-local guarantee strong enough to reconsider what may be transmitted.
