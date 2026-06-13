# agent-vault-proxy for Mac

**Keep your AI agent's API keys out of its environment.** Two commands, runs as its own user, real keys stay in Bitwarden.

---

## What it does

Your AI agent's environment holds **placeholder** strings like `sk-PLACEHOLDER-...` instead of real API keys. When the agent calls OpenAI / GitHub / Anthropic / etc., the request goes through a local proxy running as a dedicated `_avp` system user. The proxy fetches the real key from **Bitwarden Secrets Manager** and substitutes it on the wire. The agent never sees the real bytes.

If the agent gets prompt-injected, or one of its npm/pip packages turns out to be malicious, the only thing that escapes is a placeholder worth nothing.

---

## Install

```bash
brew install inflightsec/avp/agent-vault-proxy
sudo avp setup
```

`sudo avp setup` creates the `_avp` system user, lays out `/usr/local/etc/agent-vault-proxy/` and `/usr/local/var/{lib,log}/agent-vault-proxy/`, prompts for your Bitwarden machine-account token, generates the mitmproxy CA, and installs the LaunchDaemon at `/Library/LaunchDaemons/io.inflightsec.agent-vault-proxy.plist`.

Add `--static` to skip the BWS prompt and use a local file backend (development / testing).

Then add to `~/.zshenv` (NOT `~/.zshrc` — non-interactive shells must inherit too):

```bash
export HTTPS_PROXY="http://127.0.0.1:14322"
export NODE_EXTRA_CA_CERTS="/usr/local/etc/agent-vault-proxy/ca.pem"
export SSL_CERT_FILE="/usr/local/etc/agent-vault-proxy/ca.pem"
export NODE_USE_ENV_PROXY=1                # Node 22.21+/24.5+ ignores HTTPS_PROXY otherwise
```

For MCP servers (`~/.claude.json`, project `.mcp.json`), add the same four env vars to each server's `env` block — stdio MCP servers don't inherit shell env reliably.

Then:

```bash
sudo $EDITOR /usr/local/etc/agent-vault-proxy/bindings.yaml   # set organization_id, api_url
avp env                                                       # write placeholders to ~/.config/avp/env
source ~/.config/avp/env
avp doctor                                                    # verify
```

---

## Adding a secret

1. Create a secret in Bitwarden Secrets Manager. Name it like your agent already knows it (`OPENAI_API_KEY`, `GITHUB_PAT`, etc.).
2. In the Notes field, set the destination — minimum is `host: api.openai.com`. Override the default Bearer auth with `header:` / `format:` / `methods:` / `paths:` if needed (see the daemon's [`bindings.example.yaml`](https://github.com/inflightsec/agent-vault-proxy/blob/main/bindings.example.yaml)).
3. Delete the real key from your `.zshrc` / `.env`.
4. Re-run `avp env` and re-source `~/.config/avp/env`.

---

## CA trust model

The mitmproxy CA AVP generates is **never** added to the macOS Trust Store. It lives at `/usr/local/etc/agent-vault-proxy/ca.pem` and is trusted per-app via `NODE_EXTRA_CA_CERTS` / `SSL_CERT_FILE`. A CA that can mint a cert for any host should not be trusted system-wide.

`avp doctor` checks that the CA is NOT in any flat-file trust-store directory and that the CA private key is `_avp`-owned mode 0600. (It does not yet inspect the macOS keychain — discipline: don't `security add-trusted-cert` the AVP CA.)

---

## Threat model

| Attack | Protected? |
|---|---|
| Prompt injection that exfiltrates `process.env.OPENAI_API_KEY` etc. | **Yes** — placeholder, not real key |
| Shai-Hulud / `@redhat-cloud-services` worm scanning env vars and `.env` / `.npmrc` / `.netrc` for tokens | **Yes** for AVP-brokered keys; **No** for tokens AVP doesn't broker (move them in) |
| Worm scanning `~/.aws`, `~/.ssh`, browser cookies | **No** — AVP only handles env/wire credentials. Compose with [SandVault](https://github.com/webcoyote/sandvault) for filesystem isolation |
| Worm edits `~/.zshenv` to unset `HTTPS_PROXY` and bypass the proxy | **Doesn't leak keys** — your env still holds placeholders, the upstream rejects the call. It's a denial-of-service, not exfiltration. Mitigation: SandVault stops the worm from running as your user in the first place |
| Worm runs `bws` or reads `/usr/local/etc/agent-vault-proxy/bws-token` as your user | **Yes** — token is `0440 root:_avp`, your user can't read it |
| Mac physically stolen | **No** — FileVault is your OS's job |
| Bitwarden account compromised | **No** — Bitwarden's threat model. Use 2FA |
| Your sudo password stolen | **No** — sudo is the master gate; don't give it away |

For the full security model see `docs/SECURITY-AUDIT.md` and `docs/WORM-DEFENSE.md`.

---

## Compose with SandVault for full isolation

```bash
brew install sandvault
brew install inflightsec/avp/agent-vault-proxy
sudo avp setup
# Add the same four env vars from above to /Users/Shared/sv-$USER/user/.zshenv
sandvault          # enter the sandboxed shell; AVP brokers, SandVault isolates
```

SandVault stops the agent from reading your other files; AVP keeps real API keys out of the agent's environment. Use both.

---

## Update

```bash
brew upgrade agent-vault-proxy
sudo launchctl kickstart -k system/io.inflightsec.agent-vault-proxy
```

Both prompt for your sudo password — on purpose. The password is the gate that stops the agent from updating the proxy on its own.

---

## Remove

```bash
sudo launchctl bootout system /Library/LaunchDaemons/io.inflightsec.agent-vault-proxy.plist 2>/dev/null || \
  sudo launchctl unload /Library/LaunchDaemons/io.inflightsec.agent-vault-proxy.plist
sudo rm /Library/LaunchDaemons/io.inflightsec.agent-vault-proxy.plist
sudo chflags nosappnd /usr/local/var/log/agent-vault-proxy/audit.jsonl 2>/dev/null
sudo rm -rf /usr/local/etc/agent-vault-proxy \
            /usr/local/var/lib/agent-vault-proxy \
            /usr/local/var/log/agent-vault-proxy
sudo dscl . -delete /Users/_avp
sudo dscl . -delete /Groups/_avp
brew uninstall agent-vault-proxy
brew untap inflightsec/avp
```

Bitwarden secrets are left alone.

---

## Testing an unreleased branch (maintainers)

Fastest path: the daemon's own automated mac smoke test.

```bash
git clone -b <branch> https://github.com/inflightsec/agent-vault-proxy ~/src/avp
cd ~/src/avp
brew install bats-core
bash tests/setup-e2e/run-macos.sh        # provisions, runs setup.bats, tears down
```

For brew formula testing against a branch, fork this tap and edit `Formula/agent-vault-proxy.rb`'s `head` line to point at the branch, then `brew install --HEAD <your-fork>/avp/agent-vault-proxy`.

---

## License

MIT. Adapted user-creation patterns from [`webcoyote/sandvault`](https://github.com/webcoyote/sandvault) under Apache 2.0 — see `NOTICE` and `CREDITS.md`.
