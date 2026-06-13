# Credits

## SandVault

This project owes a deep debt to [`webcoyote/sandvault`](https://github.com/webcoyote/sandvault) by Patrick Wyatt, licensed under Apache 2.0.

### Why we're separate projects

`agent-vault-proxy` and `sandvault` solve **different problems** that **compose**:

- **SandVault** isolates the agent's filesystem reach via a Unix `sandvault-$USER` account + `sandbox-exec` profile. An agent inside SandVault cannot read your home directory, your ssh keys, your browser data, or anything else outside the sandbox.
- **AVP** brokers API credentials at the network layer. An agent never holds real API keys in its environment; placeholders are substituted with real BWS-stored secrets on the outbound wire by the `_avp` daemon.

Neither tool subsumes the other. The threat model for a dedicated Mac Mini running AI agents has both attack surfaces. **We strongly recommend installing both** — the install recipe is in [`README.md`](./README.md).

### Patterns adopted from SandVault

The following code patterns are adapted from SandVault's `sv` CLI script (per ADR-0016 in `docs/adr/`):

| Pattern | Why we use it | Where it lives in AVP |
|---|---|---|
| `dscl . -create` flow for user/group creation | More granular than `sysadminctl`, more stable across macOS versions | `docs/reference/avp-setup.sh.template` (and later: `scripts/avp-setup.sh` in the daemon repo) |
| `dseditgroup -o edit -d <user> -t user staff` | Removes the new daemon user from `staff` (which has surprisingly wide access on macOS) — a critical hardening step | Same |
| `dseditgroup -o edit -a <user> -t user <group>` | Adds the daemon user to its dedicated group | Same |
| `openssl rand -base64 32` random password | Makes the account unlogin-able even if someone tries | Same |
| `IsHidden 1` | Hides the daemon account from the login window | Same |
| `visudo -cf` validation before installing sudoers drop-in | SandVault's v1.1.13 changelog: "Fix sudoers: move validated file to sudoers.d to avoid writing corrupted data". Lesson learned from their bug; we adopt the discipline from day one | Same |
| Verify group membership after creation | SandVault's v1.11.0 changelog: "Fix sandvault user not being added to the sandvault group" — group assignment can fail silently. We verify | Same |
| UID/GID collision pre-check | SandVault's v1.16.0: "Fix race condition and collisions in UID/GID allocation" | Same |

### Lessons we adopt from SandVault's CHANGELOG (without copying code)

We're not just borrowing code — we're learning from bugs they've already fixed so we don't repeat them. Compiled in [`docs/LESSONS-FROM-SANDVAULT.md`](./docs/LESSONS-FROM-SANDVAULT.md).

### Where we diverge from SandVault (and why)

| Aspect | SandVault | AVP | Rationale |
|---|---|---|---|
| Username convention | `sandvault-$USER` (per-user, no underscore prefix) | `_avp` (singleton daemon, underscore prefix per Apple convention) | SandVault accounts get used interactively (shell `/bin/zsh`); AVP is a true daemon (shell `/usr/bin/false`, no home), follows Apple's `_appstore`/`_atsserver` daemon-user convention |
| Shell | `/bin/zsh` | `/usr/bin/false` | AVP daemon is never an interactive target |
| Home directory | `/Users/sandvault-$USER/` | `/var/empty` | AVP needs no home; smaller surface |
| Process model | On-demand (`sv claude` spawns a sandboxed session) | Long-running LaunchDaemon (always-on proxy) | AVP must be reachable before the agent makes a request; SandVault wraps the agent invocation itself |
| Shared workspace ACLs | Yes — `sandvault-$USER` and the real user share `/Users/Shared/sv-$USER/` via ACLs | No shared workspace | AVP owns its state files exclusively, mode 0750 `_avp:_avp`, no sharing |

### Apache 2.0 attribution requirements

Per Apache 2.0 § 4, this project includes:
- A copy of the Apache 2.0 LICENSE (referenced in `NOTICE`)
- A `NOTICE` file attributing the borrowed patterns ([`NOTICE`](./NOTICE))
- Code-level comments in `docs/reference/avp-setup.sh.template` (and later in `scripts/avp-setup.sh` of the daemon repo) citing the upstream commit SHA
- A `CREDITS.md` (this file) documenting the relationship and adopted patterns
- A reproduction of SandVault's LICENSE.md at `docs/reference/sandvault-LICENSE.md`

## Other acknowledgments

- **[`agent-vault-proxy`](https://github.com/inflightsec/agent-vault-proxy) (the daemon)** — this tap exists to distribute the upstream daemon on macOS. The daemon project's design, threat model, and supply-chain discipline (`--require-hashes`, OSV-Scanner, 7-day cooldown) are the foundation this packaging rides on.
- **[`mitmproxy`](https://mitmproxy.org/)** — the upstream daemon uses mitmproxy as its TLS-MITM substrate.
- **[Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/)** — the secret backend.
- **[Homebrew](https://brew.sh)** — the distribution mechanism.
