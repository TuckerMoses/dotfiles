---
created: 2026-11-27
source: session (nixos-host)
---

# homepc: switch `tucker` to the Home Manager module

- **What:** Name `tucker` in `dotfiles.users` on homepc, so the dotfiles' Home Manager module places his
  configs and tools from the flake, in place of Stow and `bootstrap.sh`.
- **Why here:** The Nix route was built for homepc and checked there (every package builds, `link-modes`
  passes, the sandbox gives a clean zsh), but nothing on the machine uses it. homepc is the one machine
  with Nix, so it is where the route is first used for real, before the Mac.
- **Effort:** medium.
- **Touches:** `nixos/hosts/homepc/default.nix`, possibly `nixos/modules/dotfiles-user.nix`, `validate.sh`
  (what it reports on a home Home Manager placed), `nixos/README.md`, `CLAUDE.md`, `docs/herdr.html`.
- **Needs the real machine:** yes, with the owner present.
- **Notes for the plan:**
  - Recommended: keep bash as `tucker`'s login shell and start zsh from the terminal and from herdr, so
    SSH access never depends on `.zshrc`. The module never sets a login shell, so this is the default.
  - `vm-home` (`nix/tests/`) logs in over SSH after breaking the user's `.zshrc` and records what happens.
    The plan reads that result before it chooses the login shell.
  - Activate with `safe-switch`, and the owner confirms with `safe-confirm` from a new login on port
    2222. Never `nixos-rebuild` or `home-manager switch` directly. `lifeline.nix` is not touched.
  - Home Manager refuses to replace files it does not own: `stow -D` each package in `~/dotfiles`
    before the first activation, and list what that removes. Re-stowing is the way back.
  - The third-party herdr plugins stay installed by herdr. `dotfiles-herdr-plugins-sync` refuses
    outside a sandbox today; the plan says how plugins get installed on a Nix-managed home (or
    whether `herdr-nix-plugin-builds.md` comes first).
  - `validate.sh` is not expected to pass in full on a Nix-managed home (it reads tool lists that
    assume apt or brew). Record what it reports, and fix only what is wrong.
  - Claude Code stays the native install in `~/.local/bin`.

## Needs decision
Should `tucker` use `checkout` mode (configs linked into `~/dotfiles`, so an edit there is live at once,
as with Stow today) or `store` mode (configs linked from the build, so every config change goes through
`safe-switch`)?
