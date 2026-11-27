---
created: 2026-11-27
source: session (nixos-host)
---

# herdr plugins as Nix builds, with the pins in a data file

- **What:** Build the three third-party herdr plugins (vim-herdr-navigation, herdr-plus, herdr-fingers)
  as Nix packages, and move their pins out of `bootstrap.sh` into one data file that `bootstrap.sh`,
  `validate.sh`, `herdr-plugins` and Nix all read.
- **Why here:** Each pin is the `--ref` on a `herdr plugin install` line in `bootstrap.sh`. `validate.sh`
  and `herdr-plugins` parse those lines with sed and awk, `herdr-plugins update` rewrites them, and on the
  Nix route `dotfiles-herdr-plugins-sync` installs from them through the same parser; a Nix build
  would be a fourth reader. herdr builds each plugin at install
  time with the network open; a Nix build fixes the source by hash and has no network while it builds.
- **Effort:** large.
- **Touches:** `bootstrap.sh`, `validate.sh`, `herdr/.local/bin/herdr-plugins`, a new data file,
  `nix/packages/`, `nix/home-manager/default.nix`, `nix/packages/sandbox.nix`, `docs/herdr.html`,
  `CLAUDE.md`.
- **Needs the real machine:** yes, to check that herdr loads a plugin built this way.
- **Notes for the plan:**
  - Check first how herdr can load a plugin from a read-only store path (`herdr plugin link`?), and
    where the plugin then keeps anything it writes.
  - herdr-plus builds with Go and herdr-fingers with cargo; their Nix builds need dependency hashes
    besides the source hash.
  - The data file must stay easy for bash to read without new tools.
  - Agents still never move a pin (`CLAUDE.md`); `herdr-plugins update` stays the owner's.
  - `herdr-plugins review` diffs a pin's code before it moves; keep that step.

## Needs decision
When a pin moves, who refreshes its Nix hashes? `herdr-plugins update` runs on the Mac, which has no Nix,
so it cannot compute them. Either the data file holds the hashes and a pin move is finished on a machine
with Nix before it merges (CI fails until then), or this proposal waits until the Mac has Nix
(`mac-on-nix.md`).
