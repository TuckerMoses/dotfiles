---
created: 2026-11-27
source: session (nixos-host)
---

# Mac: install Nix and switch the home to the Home Manager module

- **What:** Install Nix on the Mac and let the dotfiles' Home Manager module place the Mac user's configs
  and tools, with Stow kept as the way back.
- **Why here:** The Mac and homepc now set up the same environment two ways: Homebrew and `bootstrap.sh`
  on the Mac, the flake on Nix machines. The macOS outputs (`aarch64-darwin` in `flake.nix`) are only
  evaluated; nothing has built or run them, because no Mac has Nix.
- **Effort:** large.
- **Touches:** `flake.nix`, `nix/packages/tools.nix` (its Darwin set), `nix/checks/` (the checks are Linux
  only), `.github/workflows/nix.yml` (a macOS job), `validate.sh` (its brew-based tool lists),
  `README.md`, `CLAUDE.md`.
- **Needs the real machine:** yes.
- **Notes for the plan:**
  - Build every package for `aarch64-darwin` and run the checks that can run on macOS before anything
    is activated.
  - Home Manager refuses to replace files it does not own: `stow -D` each package before the first
    activation. `stow` is the way back; the plan writes down the exact commands for both directions.
  - The Darwin `tools` leaves out tuicr until nixpkgs carries 0.30.0 or later; it stays from Homebrew
    until then.
  - Ghostty is not in `tools`; the app stays installed as it is.
  - The herdr plugins and Claude Code stay as they are (see `herdr-nix-plugin-builds.md`).
  - Best after `homepc-tucker-on-nix.md`, so the module has run on one real home first.

## Needs decision
Should the Mac's home be managed by standalone Home Manager (user files and packages only), or by
nix-darwin with Home Manager (which also manages macOS system settings and can take over Homebrew)?
