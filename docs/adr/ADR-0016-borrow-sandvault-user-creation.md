# ADR-0016 — Borrow user-creation + lockdown patterns from webcoyote/sandvault with Apache 2.0 attribution

**Status:** accepted
**Date:** 2026-06-02
**Decider:** maintainer
**Context source:** grill-with-docs follow-up after Q5

## Decision

The `avp setup` command on macOS implements its `_avp` system user creation and lockdown using the patterns established by [`webcoyote/sandvault`](https://github.com/webcoyote/sandvault) — specifically the `dscl`-based user/group creation flow and the `dseditgroup`-based group-membership lockdown. AVP's setup script does NOT call `sysadminctl -roleAccount` (which I'd recommended in earlier drafts); it uses the lower-level `dscl . -create` pattern for finer-grained control and consistency with SandVault.

Per Apache 2.0 § 4 (SandVault is Apache 2.0), AVP's distribution carries:

1. A copy of the Apache 2.0 LICENSE.
2. A `NOTICE` file (or section in the main `LICENSE` / `README`) attributing the borrowed patterns:
   ```
   This product includes user-creation and lockdown code patterns adapted from
   SandVault (https://github.com/webcoyote/sandvault), Copyright (C) 2026
   Patrick Wyatt, licensed under the Apache License, Version 2.0.
   ```
3. Code-level comments in the borrowed sections naming the upstream source and the SHA of the version we adapted from (so future readers can diff against upstream changes).
4. A `CREDITS.md` in the AVP repo documenting the relationship and the specific patterns adopted.

## Context

After ADR-0013 settled that AVP composes with SandVault (not reinventing it), I read SandVault's source code at the maintainer's request. The user-creation logic uses `dscl` directly — twelve granular attribute-set calls — rather than the higher-level `sysadminctl -roleAccount` I had recommended in earlier architecture drafts.

The relevant SandVault patterns (from `sv` main CLI script, captured via WebFetch 2026-06-02):

```bash
# Group creation
sudo dscl . -create "/Groups/$GROUP"
sudo dscl . -create "/Groups/$GROUP" PrimaryGroupID "$GROUP_ID"
sudo dscl . -create "/Groups/$GROUP" RealName "$GROUP Group"

# User creation (the dscl flow, twelve attribute calls)
sudo dscl . -create "/Users/$USER"
sudo dscl . -create "/Users/$USER" UniqueID "$USER_ID"
sudo dscl . -create "/Users/$USER" PrimaryGroupID "$GROUP_ID"
sudo dscl . -create "/Users/$USER" RealName "$USER User"
sudo dscl . -create "/Users/$USER" NFSHomeDirectory "/Users/$USER"
sudo dscl . -create "/Users/$USER" UserShell "/bin/zsh"
sudo dscl . -passwd "/Users/$USER" "$RANDOM_PASS"
sudo dscl . -create "/Users/$USER" IsHidden 1

# Group membership lockdown — CRITICAL
sudo dseditgroup -o edit -d "$USER" -t user staff       # remove from default staff group
sudo dseditgroup -o edit -a "$USER" -t user "$GROUP"    # add to dedicated group only
```

The `dseditgroup -d ... staff` step is the lockdown move I'd missed entirely in earlier drafts. macOS adds new users to `staff` by default; `staff` has surprisingly wide access. Removing the daemon user from `staff` is essential.

## Why borrow rather than reimplement

1. **Battle-tested.** SandVault has been deployed in real environments. Their dscl ordering, attribute set, and lockdown sequence reflect lessons learned about edge cases (system reboot ordering, group membership inheritance, hidden-user UI behavior).
2. **Consistency.** A Mac with both AVP and SandVault installed will have two system users created by structurally identical patterns. Same audit shape, same failure modes, same operator-mental-model.
3. **License compatibility.** Apache 2.0 explicitly permits adapting code into other projects with proper attribution. AVP is MIT-licensed; Apache 2.0 → MIT requires retaining attribution but is permissible.
4. **Apple-blessed approach.** `dscl` is Apple's documented Directory Services CLI and has been stable across macOS major versions. `sysadminctl` is newer, has had flag changes between releases, and is less universally documented.

## Adaptations for AVP (deltas from SandVault's pattern)

| Aspect | SandVault's choice | AVP's choice | Rationale |
|---|---|---|---|
| Username convention | `sandvault-$USER` (one per real user) | `_avp` (single system user, no $USER suffix) | AVP is a singleton daemon; SandVault is per-user sessions |
| Shell | `/bin/zsh` (users run shells in it) | `/usr/bin/false` (daemon, never interactive) | AVP is never a login target |
| Home directory | `/Users/sandvault-$USER/` (provisioned) | `/var/empty` (no home) | Daemon needs no home; smaller attack surface |
| Group | `sandvault` group with explicit FS ACLs for shared workspace | `_avp` group with no shared ACLs (state files mode 0750 _avp:_avp) | No shared filesystem; daemon owns its own state exclusively |
| LaunchDaemon | None (on-demand `sandbox-exec` spawn) | LaunchDaemon required (always-on proxy) | AVP must be ready BEFORE the agent makes a request; SandVault wraps the agent invocation itself |
| Random password | 32 bytes via OpenSSL | Same — adopt unchanged | Identical reasoning: prevents login even if someone tries |
| `IsHidden 1` | Yes | Yes (adopted) | Hide from login window UI |

## Consequences

**Positive:**
- AVP gains battle-tested lockdown logic (`dseditgroup -d staff` was missing from my earlier drafts).
- Apache 2.0 attribution is a small, well-understood obligation that improves the ecosystem (credits an upstream project's work).
- Operators familiar with SandVault will recognize the AVP setup pattern instantly — same audit shape.
- `dscl` is the more conservative tool choice; less surface for macOS version drift.

**Negative:**
- `dscl` calls are more verbose than `sysadminctl`. Twelve lines instead of one. Mitigation: wrap in a `create_avp_user()` shell function in `avp-setup.sh`.
- Apache 2.0 attribution is an ongoing obligation — if SandVault upstream changes its license, we'd need to evaluate; but Apache 2.0 → other-license-by-upstream isn't a real-world concern.
- We pin against SandVault's current pattern; if they refactor (e.g., switch to `sysadminctl` themselves), we either follow or diverge consciously. Tracked via the SHA pin in our code comments.

**Neutral:**
- AVP must include the Apache 2.0 LICENSE text from SandVault as part of its NOTICE/CREDITS — small additional file in the repo.
- A `CREDITS.md` is added to the AVP repo (or this content goes in the main `README.md`'s "Acknowledgments" section).

## Implementation notes

The `avp setup` script's `create_avp_user()` function MUST have a comment block at the top citing the upstream:

```bash
# create_avp_user — creates the _avp system user with daemon-appropriate
# lockdown. Adapted from webcoyote/sandvault (Apache 2.0), specifically the
# dscl flow in their main `sv` CLI script.
#
# Source: https://github.com/webcoyote/sandvault/blob/<SHA>/sv
# Original copyright: Copyright (C) 2026 Patrick Wyatt
# Adaptations:
#  - Singleton _avp user (not per-real-user)
#  - Shell /usr/bin/false (not /bin/zsh)
#  - Home /var/empty (not a populated dir)
#  - No shared workspace ACLs
#  - Plus the dseditgroup -d staff lockdown step we adopt unchanged.
```

The `<SHA>` placeholder is replaced with the actual commit SHA we copied from at the time `avp setup` ships. Future updates to the borrowed code go through `git log` for traceability.

## Cross-references

- Upstream: https://github.com/webcoyote/sandvault (Apache 2.0)
- ADR-0013 — established that AVP composes with SandVault; this ADR borrows their patterns for AVP's own internal user-creation
- Apache 2.0 attribution boilerplate: https://www.apache.org/licenses/LICENSE-2.0
- AVP repo files affected: `NOTICE` (new), `CREDITS.md` (new), `README.md` (Acknowledgments section), `scripts/avp-setup.sh` (the borrowed code with citation header)
