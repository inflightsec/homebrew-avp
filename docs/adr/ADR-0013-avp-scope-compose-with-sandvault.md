# ADR-0013 — AVP brew scope is AVP only; user/filesystem isolation composes with webcoyote/sandvault

**Status:** accepted
**Date:** 2026-06-02
**Decider:** maintainer
**Context source:** grill-with-docs Q3 on the AVP-for-Mac architecture

## Decision

The `agent-vault-proxy` Homebrew formula installs and configures **only** the AVP credential broker — the `_avp` system user, the LaunchDaemon, the bindings policy, the TLS-interception CA, and the shell environment for routing HTTPS through `127.0.0.1:14322`.

It does NOT create a separate `_claude` user. It does NOT install sandbox-exec profiles. It does NOT take any responsibility for filesystem isolation of the agent.

For Mac users who want filesystem and user isolation of the agent (the recommended posture for headless dedicated Mac Minis), the documented composition partner is **[webcoyote/sandvault](https://github.com/webcoyote/sandvault)** — an existing Apache-2.0 Mac-only Homebrew package that creates a `sandvault-$USER` limited Unix account, wraps the agent in `sandbox-exec`, and is explicitly designed to run Claude Code under `--dangerously-skip-permissions`.

The two formulas compose: SandVault provides the kernel-UID isolation; AVP provides the credential brokerage. Both are installed independently; AVP's `avp setup` detects SandVault if present and writes the proxy environment into SandVault's per-user shell config directory (`/Users/Shared/sv-${USER}/user/.zshenv`) instead of (or in addition to) the user's own `~/.zshenv`.

## Context

The earlier draft of the architecture proposed three install postures for v0.1 (AVP-only, AVP + `_claude` user, two-mode install). All three carried meaningful trade-offs and meaningful new design work — `_claude` user provisioning, `~/.claude/` config sync between admin and agent UIDs, sandbox-exec profile authoring.

the maintainer's call: don't reinvent. Either ship narrow (AVP only) or compose with an existing well-scoped tool. webcoyote/sandvault is that tool — Apache-2.0, Mac-native, already on Homebrew (`brew install sandvault`), already integrated with Claude Code, already uses the exact UID-isolation + sandbox-exec defense-in-depth model the architecture was sketching.

The minimum security invariant Named in design: **"as long as claude on his Mac Mini cannot sudo and AVP is running on a separate user, we are gold."** Both invariants are satisfied by AVP-alone (the user's claude isn't in the sudoers file by default, `_avp` is a separate user). The filesystem-reach gap is a separate problem that SandVault solves separately.

## Alternatives considered

| Option | Scope | Effort | Audit surface | Note |
|---|---|---|---|---|
| **A. AVP creates `_claude` itself** | AVP installs become two-mode (dedicated / daily-driver), provisions `_claude`, manages config sync | Largest | Doubled | Reinvents what SandVault already ships |
| **B. AVP-only formula, no isolation story** | Ships narrow, doesn't address fs reach at all | Smallest | Smallest | Honesty problem: dedicated Mac users get worse security than expected |
| **C. AVP-only formula, document SandVault composition** *(chosen)* | Ships narrow, explicit composition recipe for fs isolation | Small | Smallest | Best of both: narrow scope per release, full security model via composition |

## Decision drivers

1. **Don't reinvent the wheel.** webcoyote/sandvault already exists, already does exactly the isolation work AVP would otherwise have to bolt on. Reinventing it would compete with an existing open-source project for no engineering gain.
2. **Single-concern releases.** One brew formula does one thing. `agent-vault-proxy` brokers credentials. `sandvault` isolates users. Each can be audited in isolation; their composition is a documented integration, not a hidden dependency.
3. **The minimum invariant is satisfied by AVP alone.** Claude in the user's user with no sudo + AVP running as `_avp` covers the threat AVP exists to address (env-var API-key exfiltration). Filesystem reach is a different threat, addressed by a different tool. Marketing scope-bounds honestly.
4. **Composition order is flexible.** Users can install AVP-only (env-var protection), SandVault-only (fs isolation, no credential brokerage), or both. Three valid postures, each with clear semantics.
5. **The "AVP on a different machine" alternative is more complex.** The maintainer considered this and rejected it. Confirmed in the ADR for traceability.

## The composition recipe (documented in ARCHITECTURE.md)

On a dedicated Mac Mini intended for agent workloads:

```bash
brew install sandvault                       # creates sandvault-alex user, sandbox-exec profile
sandvault-setup                              # one-time SandVault setup

brew install inflightsec/avp/agent-vault-proxy
sudo avp setup                               # detects SandVault, writes proxy env into
                                             # /Users/Shared/sv-alex/user/.zshenv
                                             # creates _avp user, daemon, CA, bindings

# Daily use
sandvault                                    # enters sandbox-exec shell as sandvault-alex
# inside the sandbox:
claude                                       # runs with HTTPS_PROXY → AVP → real APIs
```

AVP's `avp setup` MUST detect SandVault and integrate non-interactively:
- If `/usr/local/bin/sandvault` (or `/opt/homebrew/bin/sandvault`) exists AND `/Users/Shared/sv-${USER}/user/` exists, write the proxy env block there as well as to `~/.zshenv` (belt-and-suspenders).
- If SandVault is installed AFTER AVP, document `avp integrate sandvault` as the manual re-config step.

## Consequences

**Positive:**
- AVP formula stays narrow (smaller audit surface, simpler ADRs, faster ships).
- The security story is "two narrow tools that compose", which is easier to explain and audit than "one tool that does both".
- webcoyote/sandvault gets a high-leverage downstream user; potential to upstream improvements.
- The "claude cannot sudo" invariant is enforced by SandVault's `sandvault-$USER` not being in sudoers; AVP doesn't have to police it.

**Negative:**
- Users have to install TWO things to get the full security model. Documentation must make the composition explicit and the "AVP-alone is partial" caveat unmissable.
- AVP's `avp setup` has a soft dependency on SandVault paths for integration. If SandVault changes its config-dir convention, AVP's integration breaks. Mitigation: pin against SandVault's documented stable paths; CI test the integration.

**Neutral:**
- The earlier ISCs about `_claude` user creation (Out of Scope items, v0.2 roadmap notes) are removed from the AVP scope entirely. They live with SandVault.
- The dual-mode (`--dedicated` / `--daily-driver`) proposal is dropped. AVP has one mode: AVP. Users compose what else they want around it.

## Cross-references

- Glossary: `CONTEXT.md` → SandVault (newly added)
- ADR-0011 — chose brew formula path; this ADR scopes what the formula installs
- ADR-0012 — sudo posture; complements this by ensuring the AVP control plane stays under the human's password gate
- Upstream: https://github.com/webcoyote/sandvault (Apache 2.0)
