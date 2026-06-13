# Worm-class defenses — what AVP-for-Mac actually does (and doesn't) defend against

> Catalog of defenses against the specific class of supply-chain worm typified by Shai-Hulud (Sept 2025), the `@redhat-cloud-services` mini-variant (June 1 2026), and successors. **This document is reviewed and updated after every public supply-chain incident.**
>
> Audit date: 2026-06-02. Next review trigger: next published worm post-mortem or six months, whichever comes first.

---

## TL;DR

AVP defends against the **credential-extraction half** of these worms — the part that reads API keys from environment variables, env-var-laden shell rcs, and `.claude/settings.json`. AVP does NOT defend against the **filesystem-reach half** — reading `~/.aws/`, `~/.ssh/`, browser cookie jars, etc. For that you must also install [SandVault](https://github.com/webcoyote/sandvault).

**Bottom line:** AVP + SandVault on a Mac substantially neuters the current generation of supply-chain credential-harvesting worms. Neither tool alone is sufficient. Both tools have honest scope limits documented below.

---

## Worm behavior catalog (2025-2026)

Sourced from: incident analyses by safedep, snyk, and Hacker News community discussion of the `@redhat-cloud-services` campaign (June 1 2026, HN thread item id 48356625), Shai-Hulud (Sept 2025 originals + May 2026 Mini variant targeting `~/.claude/`).

| # | Worm behavior | AVP defense | Effectiveness |
|---|---|---|---|
| W1 | Reads `process.env.ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GITHUB_TOKEN`, ~125 other env var names | AVP places PLACEHOLDER strings (`sk-PLACEHOLDER-...`) in these vars; real values never reach the agent's process env. Worm reads strings worth nothing. | **HIGH** — direct defense, this is AVP's core promise |
| W2 | Reads `~/.npmrc`, `~/.netrc` for static tokens | AVP does NOT write tokens to these files; AVP's BWS token lives at `/Library/Application Support/agent-vault-proxy/bws-token` (mode 0400 `_avp:_avp` — unreadable by worm running as the user) | **HIGH** for AVP-managed credentials; **NONE** for any tokens the user has pre-existing in these files (those are out of AVP scope) |
| W3 | Reads `.env` files (`.env`, `.env.local`, etc.) | Same as W2: AVP places PLACEHOLDERS, real values in BWS only | **HIGH** for AVP-brokered keys; **NONE** for non-brokered files the user keeps |
| W4 | Reads Bitwarden vault state via `bw export` or similar CLI | AVP's BWS access token is unreadable by the user's user (0400 `_avp:_avp`). Worm running as the user cannot `bws secret get ...` without the token. Worm running as ROOT can read everything (out of threat model — L1 in SECURITY-AUDIT.md) | **HIGH** for the user-context worms; **NONE** for root-context worms |
| W5 | Reads gopass / pass / KeePassXC vaults | Out of AVP scope — those are separate stores the user manages | **NONE** — SandVault helps via filesystem sandbox |
| W6 | Installs `.claude/settings.json` `SessionStart` hook for persistence | AVP itself writes to `~/.claude/settings.json` `env` block only, between sentinels. `avp doctor` detects any content outside the sentinel block — including unauthorized `SessionStart` hooks — and flags it as suspicious | **MED** — AVP detects + alerts but does not auto-remediate. Worm wins the race if it writes after AVP's last doctor run |
| W7 | Installs `.claude/hooks/` directory with malicious scripts | AVP NEVER writes to `.claude/hooks/`. `avp doctor` enumerates the directory and flags any new file since last clean state | **MED** — same detect-not-block tradeoff as W6 |
| W8 | Installs `.vscode/tasks.json` for IDE-context persistence | AVP NEVER writes to `.vscode/`. `avp doctor` does not scan this; out of scope but worth noting | **NONE** — SandVault helps; manual user vigilance |
| W9 | Modifies `.github/workflows/` to propagate via the user's own GitHub Actions | AVP NEVER writes to `.github/workflows/`. `avp doctor` does not scan user repos. SandVault sandbox prevents the worm from reaching user repo paths in the first place when composed | **NONE** for AVP alone; **HIGH** with SandVault composition |
| W10 | Probes `169.254.169.254` (AWS metadata service) for cloud credentials | AVP's `unmatched_policy: deny` (Mac default, per ADR-0017) refuses to forward to unmatched hosts. The metadata IP has no AVP binding; daemon refuses. **The worm gets an HTTP 502 from AVP instead of a successful metadata fetch.** | **HIGH** when `unmatched_policy: deny` is set (default on Mac); MED otherwise |
| W11 | Direct outbound to attacker-controlled domains (exfil C2) | Env-var policy alone doesn't block; `avp lockdown` (separate verb per ADR-0017) installs `pf` anchor that drops outbound TCP/443 except to AVP's listen port — blocks direct exfil entirely | **HIGH** if `avp lockdown` is run; **LOW** if only `avp setup` was run |
| W12 | Anti-analysis: probes for CrowdStrike, SentinelOne, Carbon Black, StepSecurity Harden-Runner — **NOT for AVP, OpenSnitch, or Falco** | AVP is currently uninstrumented by known worms. Asset for now; future risk as AVP becomes known | **HIGH** in the current window — declines as AVP becomes recognized |
| W13 | Anti-analysis env vars (`__FAKE_PLATFORM__`, `__IS_DAEMON`, `SKIP_DOMAIN`) | `avp doctor --self-test` checks for these env vars in the user's process env and flags as worm-fingerprint indicators | **MED** — detect-not-block |
| W14 | Compromises CI publish pipeline (the `@redhat-cloud-services` campaign published malicious versions via the project's own GitHub Actions OIDC trusted publisher → looked legitimate) | Not applicable to AVP's consumed dependencies (we pull AVP from PyPI with `--require-hashes`); applies to OUR OWN publish pipeline (`.github/workflows/bump.yml`) — mitigated by CODEOWNERS + branch protection + manual approval gate per ADR-0015 | **HIGH** for our publish pipeline; downstream consumers should still pin |
| W15 | GitHub propagation via "adds CodeQL static analysis" PR on `chore/add-codeql-static-analysis` branch | Tap repo's CODEOWNERS + PR review process catches this human-pattern signature. Documented in CONTRIBUTING.md (to be written) | **HIGH** with review discipline |

---

## What AVP doctor checks (worm-IOC equivalents)

`avp doctor` and `avp doctor --watchdog` (continuous mode, future) check for the following macOS-equivalent IoCs (Falco-on-Linux analogs):

| Check | Macos primitive | What it catches |
|---|---|---|
| Unauthorized `~/.claude/settings.json` content | Sentinel-block diff against last clean state | W6 |
| `~/.claude/hooks/` new files since last clean state | `find ~/.claude/hooks -newer <reference>` | W7 |
| Unexpected processes running as `_avp` | `ps -U _avp` — only the daemon PID should match | A6 in SECURITY-AUDIT.md |
| Anti-analysis env vars in the user's process env | `launchctl getenv __FAKE_PLATFORM__` etc. | W13 |
| Process spawning `curl` to known exfil paths | `osquery` integration (future v0.2) | W11 (post-hoc) |
| Outbound connection attempts to `169.254.169.254` | `pf` log (when `avp lockdown` installed) | W10 |
| Tampered AVP binary | `brew verify agent-vault-proxy` cross-check | A10 |

This list is incomplete; `avp doctor` is a living check. Updates land in the daemon repo's setup script.

---

## Honest non-defenses

AVP does NOT defend against:

- **The worm reading files in the user's home directory** (~/.aws/credentials, ~/.ssh/id_*, browser cookies, anything not env-var-routed). SandVault's job. Compose both tools.
- **The worm running with sudo** (e.g., user pastes a Stack-Overflow snippet starting with `sudo`). Once sudo is held, all bets off — L1 in SECURITY-AUDIT.md.
- **A compromised BWS workspace at the admin level**. If the workspace admin rotates secrets to attacker-controlled values, AVP serves the attacker's values. Bitwarden's threat model, not ours. L4 in SECURITY-AUDIT.md.
- **A worm targeting AVP itself once AVP is well-known.** Currently unaddressed; AVP will become a target as adoption grows. Future hardening: signed daemon binary, sandbox-exec wrap around the daemon process (v0.2).

---

## Recommended composition (defense in depth)

```bash
# Layer 1: User isolation via SandVault (filesystem sandbox, separate Unix user)
brew install sandvault
sv build

# Layer 2: Credential brokerage via AVP (env-var lockdown)
brew install inflightsec/avp/agent-vault-proxy
sudo avp setup

# Layer 3 (optional, recommended for dedicated Mac Mini agent runners): network enforcement
sudo avp lockdown      # installs pf anchor: drops outbound TCP/443 except to AVP

# Layer 4 (Mac-wide, free): per-process network visibility
brew install --cask lulu                    # objective-see's free firewall (BPF + per-process rules)

# Layer 5 (optional, paid): Little Snitch with Endpoint Security extension gates /dev/bpf
```

Each layer adds defense at a different abstraction. The worm class catalogued above requires multiple layers to fully neutralize.

---

## Update cadence

- **After every public worm post-mortem:** re-audit this catalog, add new behaviors, update mitigation effectiveness.
- **Quarterly otherwise:** re-validate that the listed defenses still hold (e.g., `unmatched_policy: deny` is still the daemon default; CODEOWNERS still in place).
- **When AVP itself is named in a worm:** treat as P0; emergency review of the full design with a new audit document.

## References

- HN thread on @redhat-cloud-services incident: https://news.ycombinator.com/item?id=48356625
- safedep incident analysis of the worm
- snyk advisories on Shai-Hulud variants
- Internal SecOps lessons at the design-doc archive (private)
