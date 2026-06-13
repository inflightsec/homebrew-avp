# Contributing

This repo is the Homebrew tap for `agent-vault-proxy`. It's small (one formula, docs, workflows) but **security-critical** — it's the single point of compromise for the entire Mac distribution channel. Treat every PR accordingly.

## Branch protection (enforced on `main`)

- Required reviewers: 1 (per `CODEOWNERS`)
- Required status checks: `test` workflow must pass
- No force-push, no deletion
- Signed commits enforced (org-level setting)

## Required tools

```bash
brew install --formula homebrew/cask/homebrew-cask  # to test casks if added later
brew install shellcheck                              # for avp-setup.sh.template
```

## The loop

```bash
# Lint + audit the formula
brew audit --strict --formula inflightsec/avp/agent-vault-proxy
brew style --formula inflightsec/avp/agent-vault-proxy

# If you touched the avp-setup.sh.template reference
shellcheck docs/reference/avp-setup.sh.template
```

CI runs the same checks. Passing locally means CI will pass on the same checks.

## What this repo does NOT contain

We are deliberate about what lives here and what lives elsewhere:

- **The daemon code** lives at https://github.com/inflightsec/agent-vault-proxy (separate repo, MIT license, PyPI distribution).
- **The actual `avp setup` shell script** ships INSIDE the daemon package on PyPI. The `docs/reference/avp-setup.sh.template` in this repo is a DESIGN-TIME REFERENCE only — it documents what `avp setup` is expected to do. The authoritative implementation is in the daemon repo at `scripts/avp-setup.sh`.
- **The bindings spec** is documented in the daemon repo's `docs/architecture.md` and `bindings.example.yaml`.
- **User isolation (`_claude` user, sandbox-exec)** is in [webcoyote/sandvault](https://github.com/webcoyote/sandvault). We DO NOT reimplement.

## Worm-pattern triage for PR reviewers

The following PR shapes are the documented GitHub propagation signatures of supply-chain worms. **Treat any PR matching these as a P0 review event:**

1. PR branch named `chore/add-codeql-static-analysis` or a near-variant. This is the documented `@redhat-cloud-services` worm propagation signature (HN thread item 48356625). The PR will LOOK like a sensible security improvement.
2. PR adds a new GitHub Actions workflow file.
3. PR adds, removes, or version-bumps any dependency (we have very few — be skeptical of any addition).
4. PR adds a `postinstall`, `preinstall`, or similar lifecycle hook.
5. PR bumps `Formula/agent-vault-proxy.rb`'s `url` or `sha256` (this should ONLY happen via the auto-bump bot, and the bot's PR must be human-reviewed with the SHA256 cross-verified against PyPI before merge).
6. PR comes from a contributor who hasn't contributed before AND touches `Formula/`, `.github/workflows/`, or any `docs/adr/`.

If you are uncertain about a PR, the default is REJECT. Open an issue requesting clarification; do not merge.

## Reporting security issues

DO NOT open public issues, pull requests, or discussions for security bugs.

Use **GitHub's private vulnerability reporting** for this repository:

1. Go to the [Security](../../security) tab.
2. Click **Report a vulnerability**.
3. Fill in the form with reproduction steps and impact.

This delivers the report privately to maintainers and lets us coordinate disclosure without exposing the issue before a fix is available. We follow responsible disclosure norms — see the upstream daemon's `SECURITY.md` at https://github.com/inflightsec/agent-vault-proxy for the response targets and 90-day coordinated-disclosure timeline.

## License

By contributing, you agree your contribution is licensed under the project's MIT license, with the exception that adapted code from upstream projects (currently only [webcoyote/sandvault](https://github.com/webcoyote/sandvault), Apache 2.0) retains the upstream license as noted in `NOTICE` and `CREDITS.md`.
