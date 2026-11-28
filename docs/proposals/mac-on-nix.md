---
created: 2026-11-27
source: session (nixos-host)
---

# Mac: switch the home to the Nix route (standalone Home Manager), then decide on nix-darwin

- **What:** Install Nix on the Mac and switch the Mac user's configs and tools from Stow and Homebrew to
  `homeConfigurations."johnmoses@mac"`, a standalone Home Manager configuration activated with
  `highwind-switch`, with Stow kept as the way back. nix-darwin is a later step.
- **Why here:** The Mac and homepc set up the same environment two ways: Homebrew and `bootstrap.sh` on the
  Mac, the flake on homepc (`tucker@homepc`). One route means one place where a tool version or a plugin pin
  is decided.
- **Effort:** small now (the build is done; the cutover is about an hour at the keyboard), large for nix-darwin.
- **Touches:** nothing in the repo for the cutover; the Mac's home. Later, for nix-darwin: `flake.nix`, a
  `darwinConfigurations` output, `.claude/skills/build-proposals/SKILL.md` (its live-validation phase assumes
  Stow on the Mac), `validate.sh` (its brew-based tool lists).
- **Needs the real machine:** yes, with the owner at the keyboard.
- **Notes for the plan:**
  - Decided (2026-11-27): store mode on every machine, the Mac included; a standalone Home Manager
    configuration first, the same shape as homepc; Homebrew stays and keeps everything this repo does not
    manage. No nix-darwin in this step: it would take over system files for little gain today.
  - Built and proven in CI, not on the Mac: `johnmoses@mac` and the Darwin checks build on GitHub's macOS
    runner, which also activates `runner@mac-ci` (dry run, switch, clean login zsh, herdr config and plugins,
    rollback). The `darwin` job in `.github/workflows/nix.yml`.
  - The cutover is the runbook `docs/mac-cutover.md`: install Nix (the official installer, Nix 2.34.9),
    `stow -D` each package, move `~/.oh-my-zsh` aside, `highwind-switch`, checks in a new terminal window,
    and the way back.
  - tuicr stays on Homebrew until nixpkgs carries 0.30.0 or later; Ghostty stays the app in `/Applications`;
    Claude Code stays the native install. `brew uninstall` of the tools Nix now provides is a later,
    optional step.

## Needs decision
For the nix-darwin step only (the cutover above needs nothing): what should nix-darwin own on the Mac? The
candidates are macOS system settings (`defaults`), the Nix daemon's own configuration, `/etc/zshrc` (so a
macOS update cannot remove the Nix hook), and Homebrew (nix-darwin's `homebrew` module, which can uninstall
whatever it does not list).
