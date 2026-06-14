# Homebrew formula for agent-vault-proxy. Installs the daemon from PyPI
# into an isolated virtualenv under the brew prefix. Privileged setup
# (`_avp` user, install layout, CA, LaunchDaemon) is handled by the
# `avp setup` command that ships INSIDE the package, not by this formula.

class AgentVaultProxy < Formula
  include Language::Python::Virtualenv

  desc "Credential broker for AI agents — real keys never enter process env"
  homepage "https://github.com/inflightsec/agent-vault-proxy"

  # Populated by the auto-bump bot (see .github/workflows/bump.yml) after
  # each PyPI release. Pre-release sentinel values:
  #   - url keeps PLACEHOLDER path segments so .github/workflows/test.yml's
  #     SHA256-mismatch check sees `*PLACEHOLDER*` and skips verification.
  #   - sha256 is 64 zeros so `brew audit` / `brew style` are clean (the
  #     audit rejects non-hex / wrong-length checksum literals).
  # The `odie` block in `def install` catches any non-HEAD install attempt
  # with a clear message regardless.
  url "https://files.pythonhosted.org/packages/PLACEHOLDER/PLACEHOLDER/agent_vault_proxy-0.5.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  head "https://github.com/inflightsec/agent-vault-proxy.git", branch: "main"

  depends_on "python@3.13"

  # Resource blocks are populated by `brew update-python-resources Formula/agent-vault-proxy.rb`
  # after each upstream release. DO NOT hand-edit — drift from the daemon's
  # lockfile breaks supply-chain integrity. Pre-release, --HEAD is the only
  # working install path; see install method below.

  def install
    virtualenv_create(libexec, "python3.13")

    # Homebrew 6.0.1 on macOS 26 (Tahoe) does not reliably bootstrap pip into
    # the venv after virtualenv_create — the bundled-pip step exits silently
    # and leaves libexec/bin/pip missing. Force it explicitly via ensurepip.
    system libexec/"bin/python", "-m", "ensurepip", "--upgrade"

    if build.head?
      # HEAD: install from the cloned tree using the upstream's hash-pinned
      # lockfile, then the package with --no-deps to skip PyPI re-resolution.
      system libexec/"bin/pip", "install",
             "--require-hashes", "--only-binary=:all:",
             "-r", buildpath/"requirements.lock"
      system libexec/"bin/pip", "install", "--no-deps", buildpath
    else
      # STABLE without resources would install a broken venv. Fail loud.
      odie <<~EOS
        STABLE install requires `resource` blocks not yet populated.
        Use:  brew install --HEAD inflightsec/avp/agent-vault-proxy
        Or wait for v0.5.0 on PyPI + `brew update-python-resources`.
      EOS
    end

    bin.install_symlink libexec/"bin/avp"
  end

  def caveats
    <<~EOS
      One-time setup (creates _avp user, install layout, CA, LaunchDaemon):

        sudo avp setup
        # add `--static` for a local file backend instead of Bitwarden

      Add to ~/.zshenv so all shells (including non-interactive) inherit:

        export HTTPS_PROXY="http://127.0.0.1:14322"
        export NODE_EXTRA_CA_CERTS="/usr/local/etc/agent-vault-proxy/ca.pem"
        export SSL_CERT_FILE="/usr/local/etc/agent-vault-proxy/ca.pem"
        export NODE_USE_ENV_PROXY=1  # Node 22.21+/24.5+ ignores HTTPS_PROXY without this

      Then:  avp env  (writes ~/.config/avp/env with placeholder exports — source it)
             avp doctor  (verify install)
    EOS
  end

  test do
    assert_match "avp", shell_output("#{bin}/avp --help")
    system bin/"avp", "doctor", "--help"
    system bin/"avp", "setup", "--help"
  end
end
