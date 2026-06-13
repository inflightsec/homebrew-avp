# Claude Code instructions

Repo conventions, hard constraints, doc rules, commit-style: see [`AGENTS.md`](./AGENTS.md). This file is Claude-specific operating notes that augment those.

## What this repo is, for Claude

The Homebrew tap that distributes `agent-vault-proxy` on macOS. The daemon code is upstream at [`inflightsec/agent-vault-proxy`](https://github.com/inflightsec/agent-vault-proxy). This tap repo is small, but it's the single point of compromise for the Mac distribution channel — a malicious commit on `main` here ships to every Mac on `brew upgrade`.

## Operating the tap as Claude

The division of labor mirrors the daemon repo's: Claude edits, the operator reviews and merges.

| Action | Who does it |
|---|---|
| Edit `Formula/agent-vault-proxy.rb` (description, topics, dep pins on `python@<minor>` and `pipx`, caveats text) | **Claude** — operator reviews diff |
| Update `docs/ARCHITECTURE.md`, `docs/CONTEXT.md`, `docs/SECURITY-AUDIT.md`, `docs/WORM-DEFENSE.md` | **Claude** — operator reviews diff |
| Write a new ADR in `docs/adr/` when a hard-to-reverse decision is being made | **Claude** — operator reviews and merges |
| Edit `docs/reference/avp-setup.sh.template` | **Claude** — operator reviews; the canonical implementation is in the daemon repo |
| Edit `.github/workflows/*.yml` | **Claude only with extreme care** — every hardening rule in AGENTS.md must hold |
| **Edit the formula's `url` or `sha256`** | **NEVER by hand** — the `bump.yml` auto-PR handles this with SHA256 cross-verification |
| **Merge a PR** | **Operator only** — every PR requires CODEOWNERS review |
| **Approve a Dependabot or auto-bump PR** | **Operator only** — even with green CI, human review is the gate per ADR-0015 |

### Why merge is the operator's job

Merging a PR to `main` here is the action that ships to users' `brew upgrade`. There is no second checkpoint between `main` and `brew install`. If Claude both edits AND merges, the review window collapses to zero — and the worm-pattern triage in CONTRIBUTING.md becomes performative.

The same logic applies to the `bump.yml` auto-bump PR: the bot opens it, the operator reads the diff, verifies the SHA256 in the PR body matches what `bump.yml`'s download step computed, then merges. Claude can comment, suggest, or run additional checks — but the merge button is the operator's.

**R-MERGE.** Any automation that auto-merges into this repo defeats the single-point-of-compromise defense. That includes:
- `auto-merge` on Dependabot PRs (forbidden)
- GitHub Actions that `gh pr merge` from a workflow run (forbidden)
- "while you're in there, just merge the bump bot's PR for me" requests from chat (the operator merges, not Claude, even if asked nicely)
- Any branch protection rule weakening that would allow merge without CODEOWNERS approval

If the bump bot is annoying enough that you want to auto-merge, the fix is a better bot (more thorough SHA verification, better PR body diff), not auto-merge.

## Workflow: "the upstream daemon shipped v0.X.Y"

When the daemon's `release.yml` publishes a new version to PyPI:

1. Within 6 hours, `.github/workflows/bump.yml` opens a PR titled `agent-vault-proxy 0.X.Y`. The PR body records the new URL + SHA256 and notes that the SHA was verified against the tarball download.
2. Read the PR diff yourself. It should ONLY change `Formula/agent-vault-proxy.rb`'s `url` and `sha256`. Anything else is a worm signature — REJECT.
3. Cross-check the SHA256 against PyPI independently:
   ```
   curl -sL https://pypi.org/pypi/agent-vault-proxy/0.X.Y/json | jq -r '.urls[] | select(.filename | endswith(".tar.gz")) | .digests.sha256'
   ```
   This must match the SHA in the PR. If it doesn't, REJECT — and open a separate issue investigating the mismatch.
4. Hand off to the operator for the merge. After merge, the formula is live; the next `brew upgrade agent-vault-proxy` on any user's Mac picks up the new version.

For a manual bump (off-cycle release, hotfix), run the workflow manually via `workflow_dispatch` — same review gate applies. Never hand-edit the formula's URL or hash.

## Workflow: "add a new doc / ADR"

1. **For an ADR:** pass the three-question test — hard to reverse, surprising without context, the result of a real trade-off. If any of the three fails, do NOT add the ADR; the discussion belongs in a CONTEXT term or an ARCHITECTURE section. Number sequentially after the last ADR in `docs/adr/`.
2. **For a CONTEXT term:** add to `docs/CONTEXT.md` alphabetically within its section. Keep the definition to 2-4 sentences. Link to the load-bearing ADR if there is one.
3. **For an ARCHITECTURE section:** prefer extending an existing section. If you genuinely need a new top-level section, that's a sign the architecture has shifted — open an issue first.

## Editing `docs/reference/avp-setup.sh.template` — special care

This file is a REFERENCE in this repo. The authoritative implementation lives in the daemon repo at `scripts/avp-setup.sh` and ships in the PyPI package. Changes here are design-level — they document what `avp setup` is expected to do, and the daemon repo's actual script must follow.

Workflow when changing this template:
1. Edit the template here. Run `shellcheck docs/reference/avp-setup.sh.template`.
2. Open an issue (or matching PR) on `inflightsec/agent-vault-proxy` linking this template change.
3. Land both PRs together, daemon side first.

Never claim the template is the production setup script — it is not. The PyPI-shipped script is.

## Hardening rules for `.github/workflows/`

Mirror the daemon repo's posture. Specifically:

1. Workflow-level default `permissions: {}`.
2. Per-job `permissions:` block scoped to least privilege.
3. Every `uses:` is a 40-character commit SHA, followed by `# vX.Y.Z` comment for human-readable version.
4. `actions/checkout` always sets `persist-credentials: false`.
5. `pull_request`, never `pull_request_target`.
6. `set -euo pipefail` at the top of every multi-line `run:` block.
7. Any download of a binary or installer pins to a specific version, verifies a checksum, and lives behind a `step-security/harden-runner` step in `audit` (or stricter) egress mode if the daemon repo's `security.yml` is being mirrored. The brew tap's `test.yml` and `bump.yml` do not currently use `harden-runner` — adding it is welcomed but optional.

Run `zizmor .github/workflows/` before opening a PR that touches workflows.

## Releasing — there is no release

This repo has no release process of its own. The "release" is just a merge to `main` — at which point users picking up `brew upgrade agent-vault-proxy` get the latest formula. There is no version tag, no PyPI publish, no GitHub Release page.

The daemon repo has all of those concerns; this tap only points at the daemon's latest published wheel.

## What this repo will NOT do

The full out-of-scope list lives in [`AGENTS.md`](AGENTS.md). Highlights:
- No `homebrew/core` submission (v0.2 ambition; the formula creates a system user and installs a LaunchDaemon — incompatible with Core's policy).
- No bundled SandVault. AVP composes with `webcoyote/sandvault`; doesn't reimplement.
- No auto-update of formulas or bindings.
- No telemetry.
