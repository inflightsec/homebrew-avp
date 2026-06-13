# ADR-0015 — Separate tap repo `inflightsec/homebrew-avp` for v0.1; homebrew-core as v0.2 ambition

**Status:** accepted
**Date:** 2026-06-02
**Decider:** maintainer
**Context source:** grill-with-docs Q5 on the AVP-for-Mac architecture

## Decision

The Homebrew formula for `agent-vault-proxy` ships in a **separate tap repository** at `github.com/inflightsec/homebrew-avp`. The daemon source remains in `github.com/inflightsec/agent-vault-proxy` (unchanged). Users install via:

```bash
brew install inflightsec/avp/agent-vault-proxy
```

The tap repo is the **single point of compromise** for the brew distribution channel and MUST have hardened access controls (see Consequences below).

Submitting the formula to **`Homebrew/homebrew-core`** is the v0.2 ambition once v0.1 has a usage track record. Acceptance is not guaranteed (pipx-wrapping formulas are sometimes contentious in core); v0.1 ships in the custom tap to avoid coupling launch timing to core's review cadence.

## Context

After ADR-0011 (formula not cask), ADR-0013 (compose with SandVault), and ADR-0014 (no separate bindings update channel), the Homebrew formula has shrunk to roughly 30 lines of Ruby — install the PyPI package via pipx, register an `avp` binary, drop a caveat directing the user to `sudo avp setup`. All privileged work happens in the Python package's `avp setup` command, not in the Ruby formula.

Three credible repo structures for distribution:

| Option | Layout | User command |
|---|---|---|
| **(a) Separate tap repo** | `inflightsec/homebrew-avp` for formula, `inflightsec/agent-vault-proxy` for daemon | `brew install inflightsec/avp/agent-vault-proxy` |
| (b) Same repo, `Formula/` subdir | Formula at `inflightsec/agent-vault-proxy/Formula/agent-vault-proxy.rb` | `brew tap inflightsec/agent-vault-proxy https://github.com/inflightsec/agent-vault-proxy && brew install inflightsec/agent-vault-proxy/agent-vault-proxy` |
| (c) `Homebrew/homebrew-core` upstream | Formula merged into the canonical core tap | `brew install agent-vault-proxy` |

## Decision drivers

1. **Audit-surface separation matters even for a 30-line formula.** A future security reviewer reads the tap repo's single formula file in seconds, without wading through thousands of lines of daemon Python. The audit surfaces are independent: the formula points at a specific PyPI release URL + SHA256; the daemon's own supply chain (PyPI `--require-hashes`, signed CI lockfiles per AGENTS.md hard constraint #5) handles the rest.

2. **(b) couples concerns falsely.** A daemon code review now also has to verify the formula. A formula bump now has to traverse the daemon repo's larger review process. The repos do different things and update at different cadences.

3. **(c) is the right north star but wrong starting point.** Homebrew-core has strict criteria — formulas that wrap pipx/Python packages sometimes face rejection or are required to vendor the dependencies. Review delays can be weeks. v0.1 needs to be able to ship binding bug fixes within hours, not after a core PR review cycle. v0.2 with a usage track record makes the core submission stronger.

4. **The longer user command in (b) is friction for non-technical users.** `brew install inflightsec/avp/agent-vault-proxy` is short and Mac-idiomatic. The explicit-URL tap command is unfriendly.

5. **Version sync between two repos is not hard.** A tiny GitHub Action in `inflightsec/homebrew-avp` watches `inflightsec/agent-vault-proxy` PyPI releases via the GitHub Releases API, opens a PR bumping the `url` and `sha256`. The PR is one-line and reviewable in seconds.

## Required hardening on the tap repo

The tap repo is the **single point of compromise** for distribution — a takeover ships malicious daemon URLs to every user on the next `brew upgrade`. The following controls are NOT optional:

1. **Branch protection on `main`:** required pull request reviews, required passing checks, no force-pushes, no deletions.
2. **CODEOWNERS file:** Maintainer required-reviewer on every PR.
3. **Two-factor authentication enforced** for all org members with any write access to the repo.
4. **Required status checks:** at minimum, a CI job that diffs the `url` field against the upstream PyPI release and verifies the `sha256` matches PyPI's published hash.
5. **No org-admin token in CI:** the auto-bump GitHub Action runs under a fine-grained PAT with write access to ONLY this one repo.
6. **Repo-level secret-scanning enabled.**
7. **Signed commits required** on `main` (org-level setting).

Matches or exceeds the existing protection on the daemon repo per the project's GitHub Actions hardening checklist (`_Github` skill in the GitHub Actions hardening checklist).

## Consequences

**Positive:**
- 30-line formula audits cleanly in isolation.
- Daemon repo isn't burdened with formula reviews.
- v0.1 ships on inflightsec's release cadence, not homebrew-core's.
- Compromise of one repo doesn't grant compromise of the other (the daemon repo's `--require-hashes` lockfile is still a separate gate).

**Negative:**
- One additional repo to maintain.
- Single-point-of-compromise risk for the brew distribution channel; mitigated by the hardening list above.
- Two-repo version sync requires the GitHub Action to be reliable; outages would delay updates.

**Neutral:**
- The user command `brew install inflightsec/avp/agent-vault-proxy` is two tokens longer than the eventual `brew install agent-vault-proxy` once v0.2 lands in core. Acceptable cost for v0.1.

## v0.2 path: submit to homebrew-core

When v0.1 has stable usage (>~100 installs, >~6 months of production), submit the formula upstream. Steps:

1. Wait until the formula has stabilized (no breaking bumps for ~2 minor releases).
2. Open a PR to `Homebrew/homebrew-core` adding the formula.
3. Be prepared for reviewer requests: vendoring deps instead of pipx-wrapping, simplification of caveats, splitting into multiple formulas.
4. Address feedback; merge when accepted.
5. Once in core, the `inflightsec/homebrew-avp` tap becomes redundant. Keep it for one major version as a fallback; then deprecate with a tap-level message directing users to upgrade their install via `brew uninstall inflightsec/avp/agent-vault-proxy && brew install agent-vault-proxy`.

## Cross-references

- ADR-0011 — formula not cask (parent decision)
- ADR-0014 — no separate bindings update channel (which kept this formula simple)
- the GitHub Actions hardening checklist — branch protection + signing reference for the tap repo
- Existing AVP daemon repo CI workflows in the daemon repo as the reference shape
