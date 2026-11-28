---
status: done
created: 2026-11-27
updated: 2026-11-27
proposal: "docs/proposals/herdr-nix-plugin-builds.md (session nixos-host, 2026-11-27), scoped by the user: pins stay in bootstrap.sh"
---

# Plan: herdr's third-party plugins as Nix builds

## Goal
A Nix-managed home has herdr's three pinned plugins (vim-herdr-navigation, herdr-plus, herdr-fingers) with no
imperative install: Nix builds each at its pin, the Home Manager module puts it in place and registers it with herdr.
The Stow route (the Mac) is unchanged.

## Context
Found on homepc (herdr 0.9.5) in the sandbox's throwaway HOME:
- `herdr plugin install` clones into `~/.config/herdr/plugins/github-installations/<id>-<hash>/<n>-0/checkout`,
  runs the manifest's `[[build]]` there, and records the plugin in `~/.config/herdr/plugins.json` (kind `github`,
  `resolved_commit`). Configs live apart, in `~/.config/herdr/plugins/config/<id>`.
- `herdr plugin link <path>` accepts a read-only directory that already holds the built artifacts. It does not run
  `[[build]]` and writes nothing there. It records kind `local` with `plugin_root` and no commit, and canonicalises
  the path (a symlink is recorded as the store path it resolves to). It works with no server running (it edits
  `plugins.json`); linking an id again at another path replaces the entry, with or without a server. `unlink` needs a
  server.
- A linked plugin's actions are listed and invoked exactly as an installed one's: the seven `plugin_action` bindings
  in `config.toml` resolve, and `herdr config check` says `config: ok`.
- The manifests run `bash navigate.sh` (vim-herdr-navigation, no build), `./bin/herdr-plus` (built by
  `scripts/build.sh`: `go build -o bin/herdr-plus .`) and `./target/release/herdr-fingers` (`cargo build --release
  --locked`). nixpkgs 26.05 has go 1.26.10 (herdr-plus needs 1.26.2) and rustc 1.95 (fingers needs 1.85).
- On herdr 0.9.5 the nvim lookup's first glob, `~/.config/herdr/plugins/github/vim-herdr-navigation-*`, matches
  nothing (the install layout above), on the Mac too. Left as it is: this change keeps the Mac's behaviour.

## As built
- `nix/lib/bootstrap-data.nix` reads every `herdr plugin install <owner/repo> --ref <sha>` line with herdr-plugins'
  pattern and fails on one without a pin. `nix/packages/herdr-plugins/source.nix` takes a plugin's pin from there
  and its hashes from `hashes.nix`, keyed by plugin and commit; a commit with no entry stops evaluation with a message
  naming the plugin, the new pin, the file and the command. Each build writes `.highwind-pin` (`<owner/repo>
  <commit>`) into its root.
- Packages (`pkgs.highwind` and `packages.<system>`): `herdr-plugin-vim-herdr-navigation` (a copy),
  `herdr-plugin-herdr-plus` (`buildGoModule`, binary in `bin/`), `herdr-plugin-herdr-fingers`
  (`buildRustPackage`, binary moved to `target/release/`), each the repo plus its artifacts; `herdr-plugins`, a
  link farm by plugin id with `.plugins`; `herdr-plugin-hashes` (also an app), which prints a new `hashes.nix`
  (source hash from `nix flake prefetch`, the Go or Rust hash from a build with that hash empty). All evaluate on
  aarch64-darwin.
- The module: `highwind.herdrPlugins.enable` (default: store mode) places each plugin at
  `~/.local/share/highwind/herdr-plugins/<id>`, and an activation step after `linkGeneration` runs `herdr plugin link`
  only when herdr's recorded root is not the current build. It skips a plugin herdr installed itself, says why, and
  never fails the activation.
- `herdr-plugins`: `installed()` also reports a `local` plugin whose root has `.highwind-pin`, so `status`, `check`
  and `sync` treat it as installed at that commit; `update` skips it with a message. The text contracts are unchanged.
- `nvim/.config/nvim/lua/plugins/herdr.lua`: a second lookup at the module's path, only when the first finds nothing.
- `herdr-sandbox` links the build's plugins after its server starts; `--with-plugins` stays, as the way to test
  herdr's own installer and `herdr-plugins sync` (it then installs instead of linking). The plain `sandbox` places the
  same links, for nvim.

## Validation
- `herdr-headless`: the three link from the store and are listed enabled; `herdr-plugins check` finds each at its
  pin; every `plugin_action` binding names a listed action and `herdr config check` is clean; herdr-fingers scans and
  herdr-plus runs; nvim, given the repo's spec without LazyVim, maps `<C-h>` to the plugin. Broken in turn (marker at
  another commit, a binding to `vim-herdr-navigation.leftward`, nvim's second path): each failed with its own line.
- `tool-versions`: each package builds the commit `bootstrap.sh` pins and `hashes.nix` has exactly that key; a stale
  extra key failed it.
- `vm-switch`: generation A links the three with no network; `herdr plugin list` and `herdr-plugins check` show them
  at their pins; nvim maps `<C-h>`; generation B links nothing again and the list still has three. With the "already
  linked" test removed from the activation, it failed at B.
- `validate.sh`: `check_herdr_plugins_nix` runs the checkout's `herdr-plugins check` against a fake herdr listing a
  linked plugin with `.highwind-pin` at the pin, then off it; with the marker read removed it failed.
- A pin moved in a throwaway copy (`cloudmanic/herdr-plus --ref 2222...`): `nix build` and `nix flake check
  --no-build` both stopped with the message above.

## Decided differently from the proposal
- The pins stay in `bootstrap.sh`, its one writer and the text `validate.sh` and `herdr-plugins` parse. There is no
  data file; Nix reads the pins through `bootstrap-data.nix`, and only the hashes Nix needs live beside the builds.
- Who refreshes the hashes: a pin moves on the Mac as before (`herdr-plugins update`, which installs and tests it
  there); on a machine with Nix the build then fails until `nix run .#herdr-plugin-hashes` has rewritten
  `hashes.nix`, which is committed with the pin (CI's eval job fails until then).
