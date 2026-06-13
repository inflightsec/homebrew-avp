# AGENTS.md

Instructions for AI coding assistants (Claude Code, Codex, Cursor, Cline, Aider, etc.) working in this repository. This file follows the [AGENTS.md convention](https://agents.md/). Vendor-specific files (e.g., `CLAUDE.md`) point here.

Human contributors: [`CONTRIBUTING.md`](./CONTRIBUTING.md) is the right doc.

## What this project is

This repo is the **Homebrew tap** for `agent-vault-proxy` — a credential-broker proxy that fetches API credentials from Bitwarden Secrets Manager just-in-time and substitutes them into outbound HTTPS requests so the calling agent's address space never contains the real secret bytes. The daemon itself lives at [`inflightsec/agent-vault-proxy`](https://github.com/inflightsec/agent-vault-proxy) (separate repo, MIT, PyPI distribution).

The tap is small (one formula, a few docs, two workflows) but **security-critical** — it's the single point of compromise for the entire macOS distribution channel. A malicious commit on `main` here ships to every Mac that runs `brew install inflightsec/avp/agent-vault-proxy` or `brew upgrade`. Treat every PR accordingly.

Read [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) before making non-trivial changes. The ADRs in [`docs/adr/`](./docs/adr/) record WHY each design choice was made — particularly ADR-0011 (formula not cask), ADR-0012 (headless sudo posture), ADR-0015 (tap repo structure), and ADR-0017 (comprehensive lockdown).

## Hard constraints

These are non-negotiable. Violating any of them turns a PR into a security incident.

1. **Never edit `Formula/agent-vault-proxy.rb`'s `url` or `sha256` by hand.** The bump workflow (`.github/workflows/bump.yml`) auto-opens a PR when a new version lands on PyPI; the SHA256 is verified against the upstream tarball download. A human reviewer (per CODEOWNERS) merges. Hand-editing those fields bypasses the verification gate.
2. **Never weaken the `bump.yml` SHA256 cross-verification.** The workflow downloads the tarball and re-hashes it before writing the formula. Removing that check would let PyPI metadata drift (or a compromised upstream) ship a different artifact than the one users get.
3. **Never modify `.github/workflows/*.yml` without keeping the hardening posture intact.** Every third-party action must be pinned to a 40-character commit SHA (not `@v1` or other mutable tag); every checkout sets `persist-credentials: false`; every job needs an explicit `permissions:` block scoped to least privilege; the workflow-level default is `permissions: {}`. Use `pull_request`, never `pull_request_target`. The existing workflows are the reference shape — match them.
4. **Never use `pull_request_target`** in any workflow. Forks would get write tokens.
5. **Never claim AVP defends against a threat without an entry in `docs/SECURITY-AUDIT.md` or `docs/WORM-DEFENSE.md`.** Defense claims in the README that aren't backed by an audit entry are how false promises ship.
6. **Never reduce the `_avp` user's isolation.** The `dseditgroup -d staff` step (removing the daemon user from the default `staff` group) is load-bearing — borrowed from SandVault. See ADR-0016 + NOTICE.
7. **Never commit or push.** Open a PR and let the human merge.
8. **Keep AVP-tap single-license MIT with Apache 2.0 attribution.** Don't vendor code from non-MIT-compatible sources. SandVault patterns adapted under Apache 2.0 § 4 are tracked in `NOTICE` and `CREDITS.md`.

## What this repo does NOT contain

Be deliberate about what lives here vs. elsewhere:

- **The daemon code** lives at https://github.com/inflightsec/agent-vault-proxy (separate repo, MIT, PyPI).
- **The actual `avp setup` shell script** ships INSIDE the daemon package on PyPI. The `docs/reference/avp-setup.sh.template` in this repo is a DESIGN-TIME REFERENCE only — it documents what `avp setup` is expected to do. The authoritative implementation is in the daemon repo at `scripts/avp-setup.sh`.
- **The bindings spec** is documented in the daemon repo's `docs/architecture.md` and `bindings.example.yaml`.
- **User isolation (`_claude` user, sandbox-exec)** is in [`webcoyote/sandvault`](https://github.com/webcoyote/sandvault). We DO NOT reimplement.

## Setup

```bash
# Homebrew CLI is the only hard requirement.
brew --version

# Tools used by the loop below.
brew install shellcheck    # for avp-setup.sh.template
# brew-bundle for a Brewfile is overkill at this size.
```

## The loop

```bash
# Lint + audit the formula
brew audit --strict --formula inflightsec/avp/agent-vault-proxy
brew style  --formula inflightsec/avp/agent-vault-proxy

# Shellcheck the setup-script reference
shellcheck docs/reference/avp-setup.sh.template
```

CI runs the same checks on every PR. Passing locally means CI will pass on the same checks.

## Worm-pattern triage for PR reviewers

The following PR shapes are the documented GitHub propagation signatures of supply-chain worms. Treat any PR matching these as a P0 review event, regardless of who opened it:

1. PR branch named `chore/add-codeql-static-analysis` or a near-variant (`chore/codeql`, `feat/security-scanning`, `chore/add-static-analysis`). This is the documented `@redhat-cloud-services` worm propagation signature. The PR will LOOK like a sensible security improvement.
2. PR adds a new GitHub Actions workflow file.
3. PR adds, removes, or version-bumps a dependency (we have very few — be skeptical of any addition).
4. PR adds a `postinstall`, `preinstall`, or similar lifecycle hook.
5. PR bumps `Formula/agent-vault-proxy.rb`'s `url` or `sha256` — this should ONLY happen via the auto-bump bot, and the bot's PR must be human-reviewed with the SHA256 cross-verified against PyPI before merge.
6. PR comes from a first-time contributor AND touches `Formula/`, `.github/workflows/`, or any `docs/adr/`.

If you are uncertain about a PR, the default is REJECT. Open an issue requesting clarification; do not merge.

## Sensitive files, extra care required

Any change here needs human review and most likely an issue first:

| Path | Why it's sensitive |
|---|---|
| `Formula/agent-vault-proxy.rb` | Compromising this ships malicious URLs to every brew user on `brew upgrade`. The `url` + `sha256` fields are the supply-chain anchor. |
| `.github/workflows/bump.yml` | This is the auto-bump pipeline. A change here can silently subvert the SHA256 verification. |
| `.github/workflows/test.yml` | The CI gate. Compromising it lets bad formulas pass review undetected. |
| `docs/reference/avp-setup.sh.template` | Reference for the daemon's setup script. A bug here propagates to the daemon's actual implementation when it's synced. |
| `docs/SECURITY-AUDIT.md` / `docs/WORM-DEFENSE.md` | Public defense claims — must not promise what we don't deliver. |
| `docs/adr/` | Every ADR records a decision a future reader will rely on. Don't quietly invert one. |
| `CODEOWNERS` / `LICENSE` / `NOTICE` | Governance + supply-chain attribution. |

## Things that are explicitly out of scope

Do not propose changes in these directions without a concrete issue and approval first:

- Submitting to `homebrew/core`: v0.2 ambition; the current scope is custom-tap only (formulas with `system "..."` or post-install daemon setup do not pass Core's policy).
- Bundling SandVault or any user-isolation code: per ADR-0013, AVP composes with SandVault, does not reimplement it.
- A signed/notarized `.pkg` cask: per ADR-0011, the formula path won. Reopening that decision needs a fresh ADR.
- A separate `avp-bindings-mac` repo with cosign signatures: per ADR-0014, BWS is the bindings channel.
- Auto-update of the formula or its bindings.
- Telemetry of any kind.

## Commit message style

Imperative, area-prefixed, explain the *why* if non-obvious:

- `formula: bump to v0.5.1 (verified against PyPI tarball)`
- `bump.yml: tighten SHA256 re-verification before opening PR`
- `docs(adr): record decision to keep file-based bindings as escape hatch`
- `setup-template: belt-and-suspenders write NODE_USE_ENV_PROXY into .zshenv`

72 chars max on the summary line. Body explains *why* if the diff doesn't.

## Documentation: minimal, in-tree, no bloat

Keep repo docs tight. `README.md` is for users running `brew install`. `docs/ARCHITECTURE.md` is the single architectural source of truth for the Mac brew distribution; extend existing sections rather than adding new top-level docs. `docs/CONTEXT.md` is the glossary. `docs/adr/` records decisions that meet all three of: hard to reverse, surprising without context, the result of a real trade-off.

Do **not** create new `docs/foo.md` pages for features that fit in an existing section. Don't duplicate content between README, CONTEXT, ADRs, and the daemon repo — pick one home, link from the others.

## When in doubt

Default to opening an issue rather than a PR. The maintainer would rather discuss approach for 15 minutes than review a 500-line PR that takes a direction the project won't merge.
