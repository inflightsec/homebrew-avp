# ADR-0011 — Mac distribution via Homebrew formula + pipx, not cask + signed .pkg

**Status:** accepted
**Date:** 2026-06-02
**Decider:** maintainer
**Context source:** grill-with-docs Q1 on the AVP-for-Mac architecture

## Decision

The macOS distribution path for `agent-vault-proxy` is a **Homebrew formula** under the `inflightsec/homebrew-avp` tap. The formula installs the PyPI package via `pipx install agent-vault-proxy`. A separate `sudo avp setup` command (which the user runs manually, one time, after `brew install` succeeds) performs the privileged setup steps: create the `_avp` system user, install the LaunchDaemon plist, generate and trust-anchor the TLS-interception CA, drop the BWS access token file at `_avp:_avp` 0400 perms, install the user-session LaunchAgent that exports proxy env vars, and patch the user's shell rc files.

The earlier proposal of a Homebrew cask referencing a signed and notarized `.pkg` from GitHub Releases is rejected.

## Context

`agent-vault-proxy` already ships on PyPI under the `inflightsec` org. The Linux deploy path (the maintainer's Ansible role) uses `uv venv` + `pip install --require-hashes -r requirements.lock` against the project's signed lockfile, with a 7-day supply-chain cooldown gate enforced in CI. The `AGENTS.md` calls out `pip install --require-hashes --only-binary :all:` as a "hard constraint" — replacing it with looser variants is forbidden as a security-affecting change.

When the AVP-for-Mac architecture was first drafted (earlier the same day), the design picked a Homebrew cask + signed `.pkg` path because it delivered "one Installer GUI prompt" for non-technical users like the user. The cask path would bundle a frozen Python interpreter and frozen pip-installed deps inside the `.pkg`, signed and notarized by Apple Developer ID.

## Alternatives considered

| Option | Mechanism | Privileged setup | Notarization | Supply chain | UX cost |
|---|---|---|---|---|---|
| **A. Brew formula + pipx + `avp setup`** *(chosen)* | `brew install` runs Ruby formula calling `pipx install agent-vault-proxy`. the user runs `sudo avp setup` separately. | One sudo prompt at `avp setup` (osascript GUI dialog) | None needed | Identical to Linux: PyPI + `requirements.lock` + `--require-hashes` | Two user actions (brew + setup) instead of one |
| **B. Brew cask + signed/notarized .pkg** *(rejected)* | `brew install --cask` pulls signed .pkg, Installer.app runs its scripts as root | One Installer GUI prompt during .pkg install | Required: $99/yr Apple Developer Program + `notarytool` + stapling | Forks the supply chain — frozen Python interpreter + frozen deps bundled in .pkg, bypassing `requirements.lock` discipline on the user's end | One user action |
| **C. Pure pipx (no Homebrew)** | `pipx install agent-vault-proxy` direct from PyPI, then `sudo avp setup` | Same as A | None | Same as A | Loses the "brew install" mental model Mac users expect |

## Decision drivers

1. **Supply-chain integrity is a G1-G9 invariant.** The AGENTS.md treats `pip install --require-hashes` as non-negotiable. Option B would ship a frozen lockfile at the user's end — different from the live PyPI gate, immune to the 7-day cooldown rotation, and outside the OSV-Scanner CI sweep that runs on every `requirements.lock` change. Accepting the cask path means accepting that Mac users get a different supply chain than Linux users. That's a load-bearing security divergence we are not willing to take to buy one user-interaction.

2. **Sudo is the privilege boundary.** the maintainer's stated principle (this grill, Q1): "every time we want to update AVP of the new bindings, we will have to always go through the sudo because this is the only thing that prevents the agent, such as cloud code, from running it itself." A `sudo avp setup` command makes this gate explicit and the same as `sudo avp deploy latest` later. The cask path hides the sudo behind Apple's Installer.app GUI, which is fine for the install but creates inconsistency with later operations.

3. **No Apple Developer dependency.** Notarization adds $99/yr ongoing cost, an Apple-controlled signing identity that can be revoked, and a CI signing pipeline to maintain. Option A has none of these.

4. **Symmetric architecture across OSes.** The Linux Ansible role installs AVP via `uv pip install --require-hashes`. Option A's formula does effectively the same thing via pipx. One mental model, one set of supply-chain controls, one update path.

5. **The UX delta is small.** Option A requires the user to type one extra command (`sudo avp setup`) and answer a GUI password prompt. Option B requires one Installer.app GUI password prompt. Both involve typing a password. Option A is one extra user action; that is not worth forking the supply chain.

## Consequences

**Positive:**
- Supply chain on Mac matches Linux: same `requirements.lock`, same `--require-hashes`, same `pip` install-time hash enforcement, same OSV-Scanner sweep.
- No Apple Developer Program cost or operational burden.
- `sudo` becomes the consistent privilege boundary for ALL AVP state-changing operations (`setup`, `deploy latest`, `uninstall`).
- Updates flow via standard `pipx upgrade agent-vault-proxy` (under the hood of `brew upgrade agent-vault-proxy`) — same path Linux uses.

**Negative:**
- the user sees two steps: `brew install agent-vault-proxy` followed by `sudo avp setup`. Documentation must guide him explicitly to the second step. The formula's post-install caveat message must be unmissable.
- No GUI installer experience for the privileged setup. The `osascript -e "do shell script ... with administrator privileges"` dialog is Mac-native but feels less polished than Installer.app.
- If the user skips `sudo avp setup`, the daemon never starts and AVP silently does nothing. Mitigation: `avp doctor` flagged as the first thing the formula's post-install message tells the user to run; it fails loudly if setup was skipped.

**Neutral:**
- The Plan B `-dev` formula tap from the earlier draft is also rejected (separate ADR if it ever comes up). Source-build for technical contributors stays in the main repo's CONTRIBUTING.md, not as a tappable formula. Single source of truth.

## Cross-references

- Glossary: `CONTEXT.md` → Brew formula (vs cask), `avp setup`, `Claude proposes, the user applies`
- Architecture doc: `ARCHITECTURE.md` (TL;DR + sections)
- Upstream daemon repo `AGENTS.md` § "Hard constraints" item 5 (the `--require-hashes` invariant this decision honors)
