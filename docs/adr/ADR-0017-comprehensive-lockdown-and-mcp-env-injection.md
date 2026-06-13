# ADR-0017 — Comprehensive lockdown: NODE_USE_ENV_PROXY, MCP env injection, deny-unmatched, type-to-confirm new hosts, and a separate `avp lockdown` verb for pf enforcement

**Status:** accepted as design. Future work. The current install path covers the same env-var surface (`NODE_USE_ENV_PROXY`, `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, `HTTPS_PROXY`) by documented manual edits to `~/.zshenv` and per-MCP-server `env` blocks; this ADR captures the work to make those automatic and add the `pf` enforcement layer.
**Decider:** maintainer
**Context source:** Research (4-agent cross-checked, 25 URLs verified) + RedTeam-v2 inline (25 attacks).

## Decision

The v0.1 `avp setup` command is EXPANDED beyond the original shell-rc-only scope to comprehensively configure every documented HTTPS_PROXY / CA / proxy-related surface on macOS that AI agents read. Specifically:

1. **`NODE_USE_ENV_PROXY=1` is mandatory.** Without it, Node 22.21+/24.5+ `fetch()` ignores `HTTPS_PROXY` entirely. Claude-code uses native fetch. This single env var being missing means AVP is structurally bypassed at the Anthropic API call hop. Setup refuses to complete if Node version is older than 22.21.

2. **claude-code `settings.json` `env` block is written in addition to shell env.** Anthropic's docs claim the env block works; six tracked bugs (#10458, #11660, #22512, #22004, #15684, #28942) report it's unreliable. Belt-and-suspenders: shell env IS authoritative; settings.json `env` is the redundancy that catches paths where claude-code reads settings before shell.

3. **MCP server env injection is mandatory.** `avp setup` walks every `mcpServers.*` entry in `~/.claude.json` (user-scoped) and any project-scoped `.mcp.json` files the user's user owns, injecting the AVP env block (`HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`, `NODE_USE_ENV_PROXY=1`, all CA-bundle vars) into each server's `env` block. New MCP servers added later require `avp integrate mcp` or are flagged by `avp doctor --mcp` as missing-env.

4. **Union of CA-bundle env vars.** Different libraries read different vars (Python `requests` reads `REQUESTS_CA_BUNDLE`; `httpx` reads `SSL_CERT_FILE`; Node reads `NODE_EXTRA_CA_CERTS`; curl reads `CURL_CA_BUNDLE`). Setup writes all five: `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`. Plus `CLAUDE_CODE_CERT_STORE=system` to ensure macOS trust store wins.

5. **`unmatched_policy: deny` is the Mac default.** When the daemon sees an outbound HTTPS request to a host that has NO binding match, it REFUSES the request entirely (HTTP 502 to the client) rather than forwarding with the placeholder. Fail-closed at the unmatched-host axis.

6. **Type-to-confirm gate on new-host additions to existing bindings.** A compromised BWS workspace member could edit a secret's binding scope to add `host: api.attacker.com`. The daemon maintains a local `~/.avp/binding-trust-store.json` (mode 0640 `_avp:_avp`) recording the last-the user-approved scope for each binding. Pulling a new scope from BWS DETECTS the addition and refuses to broker to the new host until the user runs `sudo avp bindings approve-new-host <secret> <host>` with a per-host type-to-confirm phrase. The 5-min BWS cache TTL still applies to secret VALUE rotation (rotation works); only scope MUTATION needs the human gate.

7. **BWS token entry is leak-resistant.** Setup uses `read -s`, `set +o history`, `unset HISTFILE`, `HISTSIZE=0` during the entry block. Also accepts `AVP_BWS_TOKEN` env var for unattended/CI installs with explicit `read -s ... | sudo -E avp setup` pattern documented.

8. **`avp doctor --self-test` cross-verifies the avp binary** via `brew verify agent-vault-proxy` against the formula's pinned SHA256. Detects tampering at the install layer.

9. **A separate `avp lockdown` verb** is introduced for the ENFORCEMENT layer (vs. the POLICY layer that `avp setup` covers). Installs a `pf` anchor that drops outbound TCP/443 except to the AVP listen port. Higher blast radius (can lock the user out of his Mac if misconfigured), so it's a separate verb requiring extra type-to-confirm. Recommended for dedicated Mac Mini agent runners; optional for daily-driver Macs.

10. **Multi-user Mac is explicitly out of scope for v0.1.** `avp doctor` detects multi-user installs (more than one human user in `dscl . -list /Users` filtered by IsHidden=0 and UID >= 500) and refuses to certify the install as fully secure. v0.2 work item.

11. **Node version floor: 22.21+ OR 24.5+** because of A1. Older Node is refused at setup time with explicit upgrade instruction.

## Context

The original v0.1 design (ADR-0011 through ADR-0016) treated `avp setup` as a minimal patcher of `~/.zshenv` + `~/Library/LaunchAgents/org.inflightsec.avp.env.plist`. Research (Standard 4-agent cross-checked) and RedTeam-v2 (25 attacks) surfaced that this minimal scope leaves the following AVP-bypass attack surfaces unaddressed:

- **The Node fetch bypass (A1)** — single most-likely real-world AVP defeat. Critical.
- **MCP server env non-inheritance (A3)** — every MCP a user adds bypasses AVP without explicit injection.
- **The `settings.json` reliability gap (A2)** — relying on Anthropic's officially-documented env block alone is non-deterministic.
- **Tool-specific CA env var fragmentation (G4)** — Python and Node libraries read different vars; missing any one leaves a coverage hole.
- **`unmatched_policy: forward_unmodified`'s Mac inappropriateness (A20)** — Linux pragma doesn't fit Mac threat model.
- **BWS workspace member compromise → silent new-host (A7)** — gap that 5-min cache TTL alone doesn't address.

The Research mandate ("user drops it on their laptop and it's a black hole") authorizes the scope expansion. The maximum-paranoia commitment means EVERY documented bypass surface must be addressed in v0.1, not deferred.

## Alternatives considered

| Option | What v0.1 ships | Trade-off |
|---|---|---|
| (a) v0.1 = original minimal scope. Defer everything to v0.2 | Just shell-rc patch + LaunchAgent | Ships fast but has gaping bypasses (A1, A3); contradicts the maximum-paranoia mandate |
| (b) v0.1 = comprehensive policy layer (env vars + tool configs) + separate `avp lockdown` for enforcement *(chosen)* | This ADR's full scope | Larger v0.1 surface but addresses every documented bypass; lockdown verb stays optional for the truly paranoid |
| (c) v0.1 = everything including pf enforcement | All-in single command | Locks-out risk: misconfigured pf can break the user's network; bad first impression; rolling that back from a non-tech user's perspective is hard |

## Decision drivers

1. **The mandate is maximum-paranoia.** Anything less is malpractice for a tool that defends against Shai-Hulud-class adversaries.
2. **The Research findings are concrete.** Every gap (A1-A3, G4-G7) has a documented bypass vector with cited Anthropic / Node / MCP / Python bugs and behaviors. These aren't theoretical.
3. **Belt-and-suspenders is cheap.** Setting an env var both in the shell AND in claude-code's settings.json is one extra file write. The marginal cost is trivial; the marginal coverage is significant.
4. **Fail-closed at the unmatched-host axis is structurally correct.** The Linux daemon's `forward_unmodified` made sense when the threat was "API returns 401, agent moves on". The Mac threat model includes "attacker sets up a host expecting the placeholder to confirm AVP is present" — that's a leak even though the placeholder itself is public.
5. **Lockdown verb separation matches blast-radius.** Setup is safe (no network changes); lockdown can break the user's machine if wrong. Different verbs for different risk profiles.

## Consequences

**Positive:**
- Closes A1, A2, A3, A20 — three CRITICAL/HIGH attacks plus an architectural fail-open.
- MCP support is structurally correct from day one rather than something users discover by trial.
- The Mac install is honestly defensible as "the documented bypass surfaces are all covered".
- `avp lockdown` exists as an opt-in for users who want network-layer enforcement, without forcing it on every install.

**Negative:**
- `avp setup` becomes a larger surface to maintain and test. More files written, more env vars set, more parsers run (walking MCP configs is a non-trivial JSON traversal).
- `avp doctor` becomes longer (more checks). Acceptable cost; `--quick` flag for fast invocations.
- Node version floor (22.21+) excludes users on stable LTS that haven't bumped yet. Mitigated by explicit error message and `brew install node@22` direction.
- The `binding-trust-store.json` is a new piece of state to maintain. Adds complexity. Mitigated by being optional (deletable; AVP re-prompts for all bindings if missing).

**Neutral:**
- Documentation grows. The README's ELI15 section needs to enumerate "what avp setup does" in plain language without losing the user's attention.
- The `avp lockdown` verb opens design space (pf anchor templates, network-service detection, etc.) that's outside v0.1's ship-list — leave as v0.1.x or v0.2.

## Implementation notes for the `avp setup` flow

```
sudo avp setup
  → Phase 1: Pre-flight
    - Refuse if not root.
    - Refuse if Node < 22.21.
    - Refuse if BWS_ACCESS_TOKEN unreadable from env or stdin.
    - Detect SandVault → set composition flag.
    - Detect multi-user Mac → warn + offer to continue with reduced scope.
  → Phase 2: System account (per ADR-0016)
    - dscl create _avp group/user with full lockdown.
    - dseditgroup -d staff.
    - Verify all post-conditions.
  → Phase 3: State directories
    - /Library/Application Support/agent-vault-proxy/  0750 _avp:_avp
    - /var/log/agent-vault-proxy/                       0750 _avp:_avp
  → Phase 4: TLS interception CA
    - Generate; store ca.pem 0640, ca-key.pem 0600 (both _avp).
    - security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain.
  → Phase 5: BWS token entry
    - umask 077; set +o history; HISTSIZE=0; unset HISTFILE.
    - read -s prompt; write to /Library/Application Support/agent-vault-proxy/bws-token 0400 _avp:_avp.
    - Verify BWS reachability with the token.
  → Phase 6: LaunchDaemon
    - Write /Library/LaunchDaemons/com.inflightsec.agent-vault-proxy.plist 0644 root:wheel.
    - launchctl bootstrap; KeepAlive true.
  → Phase 7: Sudoers drop-in (per ADR-0012)
    - Write temp; visudo -cf validate; atomic move to /etc/sudoers.d/avp 0440 root:wheel.
  → Phase 8: Shell + agent env (NEW, per this ADR)
    - Write ~/.zshenv block (between sentinels) with:
        HTTPS_PROXY, HTTP_PROXY, NO_PROXY
        NODE_EXTRA_CA_CERTS, SSL_CERT_FILE, SSL_CERT_DIR
        REQUESTS_CA_BUNDLE, CURL_CA_BUNDLE
        NODE_USE_ENV_PROXY=1
        CLAUDE_CODE_CERT_STORE=system
    - Write ~/Library/LaunchAgents/org.inflightsec.avp.env.plist with same vars in setenv list.
    - launchctl load the LaunchAgent.
    - If SandVault detected: also write the block to /Users/Shared/sv-$USER/user/.zshenv.
  → Phase 9: claude-code settings.json env block (NEW, per this ADR)
    - Idempotently merge env block into ~/.claude/settings.json under .env.
    - If file doesn't exist or is malformed, create minimal valid JSON.
  → Phase 10: MCP env injection (NEW, per this ADR)
    - Walk mcpServers.* in ~/.claude.json.
    - For each server, merge AVP env into the server's env block.
    - Walk every .mcp.json file the user's user owns (locate via `find`).
    - Same merge.
    - Report count of MCPs configured.
  → Phase 11: Verification
    - avp doctor --strict — fail setup if any check fails.
    - Print summary of files modified, env vars set, MCPs configured.

Total interactive moments for the user: ONE sudo password + ONE BWS token paste.
```

## Cross-references

- ADR-0011 — formula path (what's installed)
- ADR-0012 — sudo posture (privilege boundary mechanics)
- ADR-0013 — compose with SandVault (composition recipe; the env block also writes into SandVault's shell config when present)
- ADR-0014 — bindings come from BWS notes; this ADR's type-to-confirm-new-host (A7) is the integrity gate on that channel
- ADR-0015 — tap repo
- ADR-0016 — borrow user-creation from SandVault
- Daemon-level ADR-0011 — BWS-notes bindings; the daemon's diagnostic surface (`avp doctor --secret`) supports the verification work this ADR depends on
- `docs/SECURITY-AUDIT.md` — the standing audit document; A1-A25 findings live there
- Research output (Standard, 25 URLs verified) — the empirical basis for G1-G9 gaps
