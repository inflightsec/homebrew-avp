# Lessons from SandVault's CHANGELOG

> Mistakes SandVault has already fixed, that we should not repeat. Extracted 2026-06-02 from https://github.com/webcoyote/sandvault/blob/main/CHANGELOG.md. SandVault is Apache 2.0; this analysis is research, not a copy.

These are the categories of bugs SandVault has shipped fixes for. Each is a landmine we should avoid stepping on by designing or testing around it from day one.

## Sudoers handling

**Their bugs:**
- v1.1.11: "Remove overly permissive sudoers rule" — initial sudoers grant was too broad
- v1.1.12: Emergency revert of a sudoers fix (hotfix release)
- v1.1.13: "Fix sudoers: move validated file to sudoers.d to avoid writing corrupted data"
- v1.1.13: "Reduce sudoers privileges for better security"

**What we do differently:**
- Sudoers drop-in `/etc/sudoers.d/avp` is SCOPED to a `Cmnd_Alias AVP_CMNDS = /opt/homebrew/bin/avp, /usr/local/bin/avp` (and similar absolute paths only). No wildcards, no broad grants.
- Only one effective rule: `Defaults!AVP_CMNDS timestamp_timeout=0`. No `NOPASSWD`. No additional privileges granted.
- ALWAYS write to a temp file first → `visudo -cf <tempfile>` validation → atomic `mv` into place. Never write directly to `/etc/sudoers.d/avp`.
- `avp uninstall` rolls this back atomically; pre-flight checks confirm the file is the one we wrote (matching SHA) before removing.

## Group membership

**Their bugs:**
- v1.1.24: "Remove sandvault user from staff group for better isolation" — staff group has surprisingly wide access on macOS
- v1.11.0: "Fix sandvault user not being added to the sandvault group" — group assignment failed silently

**What we do differently:**
- `avp setup` runs `dseditgroup -o edit -d _avp -t user staff` IMMEDIATELY after user creation
- After EVERY `dseditgroup` call, run `dseditgroup -o read <group>` and verify `_avp` is/isn't in it as intended. Fail the install if verification doesn't match.
- The `avp doctor` health check includes a "system user group membership" probe that flags any unexpected group membership for `_avp`.

## UID/GID allocation

**Their bug:**
- v1.16.0: "Fix race condition and collisions in UID/GID allocation"

**What we do differently:**
- Pre-flight check: `dscl . -search /Users UniqueID <candidate>` returns empty before assigning.
- Same for GroupID.
- Loop over candidate UIDs starting from a project-reserved range (e.g., 250-260) and pick the first available.
- After assignment, verify-read via `dscl . -read /Users/_avp UniqueID` and confirm.

## File permissions & ACLs

**Their bugs:**
- v1.12.0: "File permissions no longer set the execute bit on regular files in the vault"
- v1.17.0: "File ACLs avoid creating files with the `execute` ACL"
- v1.16.0: "Fix TOCTOU vulnerability in shared-folder ACL removal"
- v1.1.30: Added `--fix-permissions` flag with umask detection

**What we do differently:**
- AVP's state dir at `/Library/Application Support/agent-vault-proxy/` has explicit modes set: directories `0750`, regular files `0640`, the BWS token `0400`. No `a+rwX` patterns.
- No shared workspace, no ACLs, no `file_inherit`. AVP owns its files exclusively.
- `avp doctor` includes a permission audit: walks the state dir and flags any file with unexpected perms.
- Install scripts run with explicit `umask 077` to prevent umask-leakage corruption.

## Homebrew path resolution

**Their bugs:**
- v1.18.0: "Fix Homebrew path resolution when sandvault is installed under `libexec` instead of `Cellar`"
- v1.1.32: "Fix WORKSPACE path to use Homebrew opt/ symlink instead of Cellar"
- v1.1.11: "Fix workspace resolution for Homebrew installations"
- v1.1.16: PATH ordering critical: `/opt/homebrew/bin` before `/bin`

**What we do differently:**
- `avp` CLI uses `$(brew --prefix)` for any Homebrew-relative path. Never hardcodes `/opt/homebrew` or `/usr/local`.
- Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) paths are BOTH supported via `brew --prefix` resolution.
- All `Cmnd_Alias` entries in `/etc/sudoers.d/avp` list both possible paths.

## Session/cleanup race conditions

**Their bugs:**
- v1.1.33: "Fix session-exit cleanup scope bug"
- v1.1.6: "Fix race condition in multi-instance session cleanup"

**Less applicable to AVP** because we're a long-running daemon, not a per-session spawn. But the lesson lands: `avp uninstall` MUST be idempotent and safe to run mid-state (e.g., if a previous uninstall was interrupted).

## TMPDIR ownership

**Their bug:**
- v1.1.5: "Fix TMPDIR ownership by creating it as sandvault user"
- v1.1.3: "Set unique TMPDIR to avoid conflicts between users"

**What we do differently:**
- AVP daemon's LaunchDaemon plist sets `TMPDIR=/var/tmp/agent-vault-proxy` (created at install time, mode 0700 `_avp:_avp`).
- Daemon code uses `tempfile.mkstemp` which honors `TMPDIR` automatically.

## Configuration preservation

**Their bug:**
- v1.7.0: "Preserve user customizations to `.gitconfig` and `.claude.json` across sandbox sessions instead of overwriting them on each launch"
- v1.1.29: "Move custom configuration to `$SHARED_WORKSPACE/user`"

**What we do differently:**
- AVP's shell rc patches are wrapped in a SENTINEL block:
  ```
  # ===== BEGIN agent-vault-proxy managed block (do not edit between markers) =====
  ...exports...
  # ===== END agent-vault-proxy managed block =====
  ```
- `avp setup` ONLY touches lines between the sentinels. Any custom user content above/below survives.
- `avp uninstall` removes ONLY the sentinel block.

## Keychain dialogs leaking host context

**Their bug:**
- v1.4.0: "Prevent keychain login dialog from popping up during sandbox sessions"

**What we do differently:**
- AVP does NOT use Keychain for the BWS token. We use a `0400 _avp:_avp` file at `/Library/Application Support/agent-vault-proxy/bws-token`. Zero risk of Keychain UI prompts in headless installs.
- This was caught by the parent project's RedTeam analysis (R9) before this lesson was discovered — convergent reasoning with SandVault's experience reinforces the decision.

## SSH mode edge cases

**Their bugs:**
- v1.1.31: "Fix SSH mode when Remote Login is set to 'All users'"
- v1.1.2: "Continue running when Remote Login is disabled (unless mode=SSH)"

**Applicable to AVP because** headless Mac Mini installs are the primary use case. AVP's `avp setup` MUST work over SSH (no GUI required). Per ADR-0012, the sudo posture uses `/etc/sudoers.d/avp` + `sudo -k` + type-to-confirm — all terminal-compatible.

## Bash 3.2 portability

**Their bug:**
- v1.20.0: "Preserve unicode characters in agent arguments, fix unbound variable expansion in bash 3.2"

**What we do differently:**
- macOS ships bash 3.2 by default. AVP's `avp-setup.sh` script targets bash 3.2 explicitly (no associative arrays, no `${var,,}` case conversion, no `[[ ... =~ ]]` regex assumptions about BASH_REMATCH availability without testing).
- The `#!/usr/bin/env bash` shebang plus `set -euo pipefail` are standard, but everything inside is bash-3.2 compatible.
- CI runs the script under both bash 3.2 (macOS default) and bash 5+ (typical Linux dev env).

## Error handling

**Their bug:**
- v1.20.0: "Error trap handler now writes to stderr instead of stdout"

**What we do differently:**
- `avp-setup.sh` has a `trap 'echo "ERROR at line $LINENO" >&2' ERR` near the top.
- All diagnostic output goes to stderr; only intentional CLI output goes to stdout.

## Summary

SandVault has lived in production long enough to ship 30+ point releases. Their CHANGELOG is a treasure of "things that broke in real-world Mac installs." We adopt the discipline-shape of their fixes from day one rather than discovering each landmine ourselves.

This document is updated when we discover new lessons from SandVault upstream changes.
