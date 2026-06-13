# ADR-0014 — No separate bindings update channel; BWS is the channel (with file fallback)

**Status:** accepted
**Date:** 2026-06-02
**Decider:** maintainer
**Context source:** grill-with-docs Q4 on the AVP-for-Mac architecture
**Parent ADR:** the daemon repo's bindings-in-BWS-notes ADR (the upstream daemon-level decision this depends on)

## Decision

The Mac brew distribution of AVP ships with **NO separate bindings update channel** — no `avp-bindings-mac` repo, no cosign signature infrastructure, no signed-release fetching code in `avp deploy latest`.

Bindings come from one of two sources, depending on user preference:

1. **Default (BWS-notes binding):** Each BWS secret's notes field carries the YAML-encoded binding policy. AVP fetches secret + binding inline at request time. Per the parent ADR-0011 on the daemon side, this is the v0.1 default.

2. **Escape hatch (file-based binding):** Users who prefer pre-generated YAML files (Ansible deploys, air-gapped environments, GitOps workflows) can hand-author or template a `bindings.yaml` and place it at the standard AVP config path. The daemon merges both sources with BWS-notes taking precedence.

`avp deploy latest` becomes a thin wrapper around `brew upgrade agent-vault-proxy && sudo avp post-upgrade-checks` — it updates the daemon binary via the existing PyPI supply chain (which IS the signed channel for daemon code, per `--require-hashes` lockfile discipline). Binding updates happen out-of-band via BWS edits (no AVP-side action required) or via `sudo avp bindings edit` for the file-based path.

## Context

Earlier in the architecture conversation, I floated a "separate `inflightsec/avp-bindings-mac` repo with cosign-signed releases" mechanism for pushing binding updates to Mac users. Q4 of the grill challenged whether this complexity earns its keep.

The decisive insight (noted during design grilling): if bindings live as metadata ON the secret itself in BWS, the binding-distribution problem disappears entirely. BWS is the credential delivery channel; making BWS also the binding delivery channel collapses two channels into one.

Verified: BWS exposes only Name / Value / Notes / Project. Notes is the carrier for structured binding metadata. The daemon parses notes as YAML at fetch time. Fail-closed when notes is empty, malformed, or missing required fields.

## Alternatives considered

| Option | How binding updates flow | Complexity for Mac v0.1 |
|---|---|---|
| (a) Bundle bindings inside the PyPI package, update via PyPI release | Tight coupling between daemon releases and binding changes | Smallest, but limits "thousands of services" reality |
| (b) Separate `avp-bindings-mac` repo + cosign signatures | Independent of daemon releases; signed | Largest — needs key infra, CI, verification code |
| (c) BWS-notes bindings (per ADR-0011) **(chosen)** | Updates happen in BWS; AVP picks them up within 5-min cache TTL; no AVP-side channel needed | Smallest possible — no channel at all |

## Decision drivers

1. **The parent ADR makes (c) free.** Once the daemon reads bindings from BWS notes, the Mac brew side inherits the simplification with zero additional work — there's literally no channel to design.
2. **`brew upgrade agent-vault-proxy` is already the daemon-update channel** via PyPI. That's enough. Pre-paying for a separate binding-update channel that we'd only use rarely is wasted complexity.
3. **The file-based fallback satisfies the Ansible/fleet case.** Users who want to roll out a binding change to a fleet via Ansible can do it the same way they do everything else — template `bindings.yaml`, redeploy. No special tooling needed.
4. **Diagnosability is the real requirement raised in design.** Not "how do bindings update" but "if a binding doesn't work, can the user understand WHY". That's a daemon-side concern (per parent ADR-0011 § Diagnostic UX), not a Mac-brew concern.

## Consequences

**Positive:**
- Mac brew formula has nothing to do with binding distribution. `avp setup` only configures launchd, drops the BWS token, and patches shell env.
- No cosign key management, no separate release repo, no signature verification code, no audit ADRs for the channel itself.
- Mac brew ADR series stays small and on-topic.

**Negative:**
- Mac brew v0.1 depends on the parent daemon ADR (ADR-0011 upstream) landing first. If the daemon refactor stalls, Mac brew v0.1 stalls or has to fall back to file-only.
- Mitigation: per ADR-0011's path C (backward-compatible daemon), Mac brew can ship with file-bindings as the bootstrap path, and migrate users to BWS-notes once the daemon refactor is live. But the cleanest story is for the daemon ADR to land first.

**Neutral:**
- The `avp deploy latest` verb still exists but is now thin — it's effectively `brew upgrade agent-vault-proxy && avp post-upgrade-checks`. Bindings flow independently. Two channels become one.

## Cross-references

- **Parent:** the daemon repo's bindings-in-BWS-notes ADR — the daemon-level decision this Mac-brew ADR depends on
- Glossary: `CONTEXT.md` → Bindings, Bindings diff (semantic review)
- Mac brew ADRs: ADR-0011 (formula not cask), ADR-0012 (sudo posture), ADR-0013 (compose with SandVault) — all in this folder
