# PR review checklist

> Per `CODEOWNERS`, every PR requires maintainer review. This template is a self-check before opening the PR.

## What this PR changes

(Describe the change. One sentence, plain language.)

## Security-relevant?

- [ ] **YES** — change touches `Formula/`, `.github/workflows/`, `docs/SECURITY-AUDIT.md`, `docs/WORM-DEFENSE.md`, `docs/adr/`, `LICENSE`, `NOTICE`, `CODEOWNERS`, or the `avp-setup.sh.template`. **Linked SECURITY-AUDIT.md change ID:** (or N/A with justification).
- [ ] **NO** — typo, doc clarification, etc.

## Worm-pattern triage

The following PR shapes are the documented GitHub propagation signatures of supply-chain worms (Shai-Hulud, `@redhat-cloud-services` mini, successors). If your PR looks like ANY of these, expect extra scrutiny — and if you ARE a maintainer reviewing such a PR, treat it as a P0 review event.

- [ ] PR branch is named `chore/add-codeql-static-analysis` or a near-variant (`chore/codeql`, `feat/security-scanning`, `chore/add-static-analysis`)
- [ ] PR adds a new GitHub Actions workflow
- [ ] PR adds a new `postinstall`, `preinstall`, or similar lifecycle script (N/A for Ruby formulas but applies to any helper scripts)
- [ ] PR introduces a new dependency
- [ ] PR bumps `Formula/agent-vault-proxy.rb`'s `url` or `sha256` (these MUST be human-reviewed even from the auto-bump bot; see `bump.yml`)

If any of the above checkboxes are ticked, link the SECURITY-AUDIT.md entry that justifies the change.

## Tested?

- [ ] `brew audit --strict --formula inflightsec/avp/agent-vault-proxy` passes locally
- [ ] `brew style --formula inflightsec/avp/agent-vault-proxy` passes locally
- [ ] If touching `avp-setup.sh.template`: shellcheck clean AND tested on macOS 13+

## Documentation

- [ ] CONTEXT.md updated if new terminology
- [ ] ADR added if hard-to-reverse and surprising-without-context (see existing ADRs in `docs/adr/` for the shape)
