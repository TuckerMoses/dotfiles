---
created: 2026-11-27
source: session (nixos-host)
---

# homepc: put `tucker`'s dotfiles on the Nix route

- **What:** `tucker`'s configs and tools on homepc come from the flake's standalone Home Manager
  configuration `homeConfigurations."tucker@homepc"`, in place of Stow and `bootstrap.sh`. He switches it
  himself with `dotfiles-switch`; the system is not involved.
- **Why here:** homepc is the one machine with Nix, so it is where the route is first used for real,
  before the Mac.
- **Decided (owner, 2026-11-27):**
  - **Store mode.** Configs are linked from the build. One `dotfiles-switch` updates everything at once,
    and the `onChange` hooks do the reloads, instead of a reload per edited file.
  - **Standalone configuration, not `dotfiles.users`.** A user activation through the NixOS module would be
    put back to the system's copy at the next boot. The standalone one is the user's own: no root, no
    `safe-switch`, nothing near sshd, Tailscale or the firewall, and it survives a reboot (`vm-switch`).
  - **The login shell stays bash.** herdr panes and Ghostty windows start zsh
    (`dotfiles.interactiveShell`), so an SSH login never depends on `.zshrc`.
  - **Personal profile on**: the herdr-plus projects, worktree layouts and the validate-dotfiles action.
- **Effort:** small, now that the mechanism is built and tested.
- **Touches:** nothing in `nixos/`; `tucker`'s home on homepc. homepc's system path does not change.
- **The cutover**, performed in the change that added this mechanism, as `tucker` on homepc:
  1. `nix run ~/dotfiles#dotfiles-switch -- --dry-run`: the files it would place, and anything in the
     way. Home Manager refuses to replace a file it does not own; any path listed there is moved aside
     first (Stow links: `stow -D <pkg>` in `~/dotfiles`).
  2. `nix run ~/dotfiles#dotfiles-switch`, then a new SSH login and `host-check`.
  3. Back out: `dotfiles-switch --rollback` goes to the previous generation; from the first generation,
     remove what it placed (`home-manager-path` from the profile with `nix-env -e home-manager-path`, and
     the links into the store) and re-stow.
- **Still open after the cutover:**
  - The third-party herdr plugins stay installed by herdr. `dotfiles-herdr-plugins-sync` refuses outside
    a sandbox; `herdr-nix-plugin-builds.md` covers building them with Nix.
  - `validate.sh` is not expected to pass in full on a Nix-managed home (it reads tool lists that assume
    apt or brew). Record what it reports, and fix only what is wrong.
  - Claude Code stays the native install in `~/.local/bin`.
