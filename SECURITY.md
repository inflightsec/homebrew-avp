# Security Policy

This repo is the Homebrew tap for `agent-vault-proxy`. The daemon code, its threat model, and its CVE process live at https://github.com/inflightsec/agent-vault-proxy — report daemon issues there.

This file covers vulnerabilities in **the tap itself**: the formula, the workflows, the auto-bump pipeline, the setup-script reference.

## Reporting a vulnerability

**Do not open public issues, pull requests, or discussions for security bugs.**

Use **GitHub's private vulnerability reporting** for this repository:

1. Go to the [Security](../../security) tab.
2. Click **Report a vulnerability**.
3. Include reproduction steps and impact.

## Scope

In scope:

- Compromise of the formula's `url` / `sha256` (auto-bump bypass, hash drift between PyPI and the formula).
- A worm-pattern PR shape (see `CONTRIBUTING.md` § "Worm-pattern triage") that bypassed CODEOWNERS review.
- Workflow privilege escalation (`pull_request_target` use, unpinned action SHAs, leaked `GITHUB_TOKEN`).
- A setup-script reference (`docs/reference/avp-setup.sh.template`) that, if mirrored to the daemon's actual `scripts/avp-setup.sh`, would weaken the daemon's posture (e.g. CA in System Trust Store, world-readable token).
- Documentation that misleads operators into materially insecure configurations.

Out of scope (report upstream):

- Bugs in the daemon itself — report at https://github.com/inflightsec/agent-vault-proxy.
- Bugs in Homebrew core, `pipx`, `python@3.13`, or any brew dependency we declare.
- Bugs in `webcoyote/sandvault` — report at https://github.com/webcoyote/sandvault.

## Response targets

| Phase | Target |
|---|---|
| Acknowledgement of receipt | 3 business days |
| Initial triage + severity | 7 business days |
| Fix + coordinated disclosure window | 90 days (adjustable by mutual agreement) |

The 90-day clock starts at receipt. Targets, not guarantees — this tap is maintained on a best-effort basis. If a report sits longer, follow up.

## Public disclosure

After a fix ships:

- GitHub Security Advisory with a CVE if applicable.
- Reporter credited (with permission) in the advisory and CHANGELOG.
- Anonymous credit available on request.

No monetary bounty program at this time.
