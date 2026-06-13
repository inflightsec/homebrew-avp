# ADR-0012 — Headless-compatible sudo posture for the AVP privilege boundary

**Status:** accepted as design. Lands when state-changing `avp` subcommands ship.
**Decider:** maintainer

## Decision

Every privileged AVP operation (`avp setup`, `avp deploy latest`, `avp bindings apply`, `avp uninstall`) enforces fresh authentication on every invocation via three layered mechanisms:

1. **`/etc/sudoers.d/avp` with `Defaults!AVP_CMNDS timestamp_timeout=0`** — sudoers drop-in restricting the cache-bypass rule to the avp command alias only, installed by `avp setup` and validated with `visudo -cf` before being placed.
2. **`sudo -k` invalidation in the `avp` CLI wrapper** before each privileged op — belt-and-suspenders if the sudoers file is missing, corrupted, or someone calls a privileged path directly.
3. **Type-to-confirm phrase for any state-changing op** — `avp deploy latest` and `avp bindings apply` render a diff and require the user to type a literal confirmation string (e.g., `APPLY-NEW-BINDING-api.foo.com`) before applying. The phrase varies per change so it cannot be pre-cached.

The macOS Authorization Services GUI dialog path (`osascript -e "do shell script ... with administrator privileges"`) is explicitly rejected for v0.1 and reserved as a **v0.2+ opportunistic optimization** when a logged-in WindowServer session is detected.

## Context

The privilege boundary stated by captured in design grill Q1: "every time we want to update AVP or the new bindings, we will have to always go through the sudo because this is the only thing that prevents the agent, such as cloud code, from running it itself."

macOS sudo by default caches credentials for 5 minutes (`timestamp_timeout=5`). On the default install, if the user runs ANY `sudo <command>` four minutes before claude attempts `sudo avp deploy latest`, the cached credential satisfies the second sudo without prompting. The stated boundary is permeable for 5 minutes after every legitimate sudo.

A first instinct (Q2 v1 recommendation) used `osascript with administrator privileges`, which calls macOS Authorization Services API — a distinct credential cache from sudo's, always prompts with a Mac-native GUI dialog. This breaks on headless installs.

**The headless-installation case is load-bearing.** Many users buy Mac Minis specifically to run AI agents headlessly, accessed exclusively via SSH. Authorization Services has no headless mode (it requires WindowServer + a logged-in GUI session). Therefore osascript cannot be the primary path.

## Alternatives considered

| Option | Headless? | Robustness | Notes |
|---|---|---|---|
| (a) `osascript do shell script with administrator privileges` | ❌ | High when available | Requires GUI session. Reserved for v0.2 GUI detection. |
| (b) `sudoers.d` with `timestamp_timeout=0` | ✅ | High | Pure POSIX. Restricted to avp command alias. visudo-validated install. |
| (c) `sudo -k` in CLI wrapper | ✅ | Medium | Leaky if attacker races. Solid as belt-and-suspenders. |
| (d) Type-to-confirm phrase | ✅ | Defense-in-depth | Even a captured/social-engineered password gains nothing if the typed phrase is unique per change |
| (e) Hardware key (YubiKey + pam_yubico) | ✅ | Highest | Out of scope for v0.1; assumes hardware ownership we cannot require |

## Decision drivers

1. **SSH/headless is a primary use case** — many Mac Minis are dedicated agent runtimes. Any solution that requires GUI presence rules out an important segment.
2. **The privilege boundary must hold against the documented threat: a prompt-injected agent socially engineering the user into typing a password.** Sudo timestamp caching invalidates the boundary; type-to-confirm survives even a typed password being captured.
3. **Layered defenses cost little.** Three lightweight mechanisms compose; if one fails (corrupted sudoers file, missing CLI wrapper), the others still provide gates.
4. **Reuse existing project machinery.** The type-to-confirm diff renderer is the same semantic-review CLI parked at v0.5 (`avp-bindings-diff-design.md`). Same renderer on Mac and Linux. One audit surface.

## Consequences

**Positive:**
- Boundary holds even after legitimate sudo use elsewhere in the user's session.
- Works identically on GUI Macs and headless Mac Minis.
- Type-to-confirm gates new-host additions even if password is captured.
- The parked v0.5 `bindings diff` CLI gets a concrete v0.1 consumer — accelerates that work.

**Negative:**
- Every `sudo avp ...` invocation prompts for password. No convenience caching even within the same shell session.
- Type-to-confirm phrases add ~5 seconds of friction per update operation. Acceptable for the threat model.
- The sudoers drop-in is a sharp file; one syntax error and the user is locked out of `sudo`. Mitigation: `avp setup` writes to a temp file, validates with `visudo -cf`, then atomically moves into place. Rollback path documented.

**Neutral:**
- v0.2 will add osascript path with GUI detection (`launchctl print user/$UID | grep -q windowserver`) — purely additive, doesn't change the headless primary path.
- Hardware-key path (YubiKey) is plausible v0.3 for highest-assurance users; documented as roadmap.

## Cross-references

- Glossary: `CONTEXT.md` → "Claude proposes, the user applies", "avp setup", "avp deploy latest", "Type-to-confirm"
- ADR-0011 — chose the brew formula path that made `sudo avp ...` the consistent privilege boundary
- Existing parked spec: the daemon repo's bindings-diff design spec — the diff renderer this ADR makes load-bearing for v0.1
