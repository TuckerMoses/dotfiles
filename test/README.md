# test/

One suite, four places to run it. Not a stow package; `bootstrap.sh` never touches it.

```bash
test/suite.sh local         # throwaway $HOME on this machine (isolated from your herdr, tmux, env)
test/suite.sh vm-native     # fresh Ubuntu 26.04 guest, this machine's arch (HVF on macOS, KVM on Linux)
test/suite.sh vm-emulated   # fresh Ubuntu 26.04 guest, the other arch (TCG; an hour or more)
DOTFILES_TEST_DISPOSABLE=1 test/suite.sh here   # real $HOME of a disposable Linux machine: the suite's guests and CI only
test/suite.sh report test/.runs/<run-dir>...    # side-by-side table for a PR
```

`local` and the guests test the committed `HEAD` (copied as a git bundle; uncommitted changes are not
included), `here` the checkout it runs in, and runs the same core: `bootstrap.sh` three times (the third must install nothing),
a headless `herdr server`, nvim plugins from `lazy-lock.json`, one herdr-summarizer hook run
(`HERDR_SUMMARIZER_DRY=1`: no model calls), an interactive zsh in a pty, then `validate.sh`,
which must exit 0.

Exit codes: `0` passed, `1` the suite failed, `3` the environment could not be started
(download, checksum, QEMU, guest never reachable).

Results go to `test/.runs/<env>-<timestamp>/` (gitignored, so removing the checkout's worktree deletes them): `log`, `result` (one line per step),
`validate.txt`, `meta`; for guests also `console.log` and `guest/` (everything the guest wrote).

- `local` refuses to run if anything `bootstrap.sh` would install system-wide (brew, apt) is
  missing, and refuses if `HOME` resolves to your real home or any herdr socket outside it.
- Guests need `qemu-system-aarch64`/`qemu-system-x86_64`, `qemu-img` and UEFI firmware (Homebrew's
  `qemu` has all of them). Images are cached, checksum-verified, in
  `${DOTFILES_TEST_CACHE:-${XDG_CACHE_HOME:-~/.cache}/dotfiles-test}` (about 900 MB each); every run boots a fresh overlay.
- `--keep` leaves the throwaway HOME or the guest (a failed `local` run keeps its HOME anyway; path in `meta` as `home`); `--resume <run-dir>` reboots a kept guest and
  continues an interrupted or timed-out run, re-running the steps that have not passed (server, validate and teardown always run); a finished run is re-reported, not re-run. Tunables: `--boot-timeout`, `--timeout`,
  `DOTFILES_TEST_CPUS`, `DOTFILES_TEST_MEM`.

## How the test harnesses relate

Nothing is shared between them; they test different things.

| Harness | Tests | Runs on |
|---|---|---|
| `test/suite.sh` | The Stow and `bootstrap.sh` route on Ubuntu | Mac, Linux, CI |
| `nix flake check` | The Nix route: packages, Home Manager module, VM login | homepc, CI |
| `nixos/test/` | Installing NixOS and the destructive lockout drills | Mac (QEMU), by hand |
| `validate.sh` | What is live on this machine | any machine |

`nix flake check`, run from a checkout on a machine with Nix (homepc today, not the Mac), builds every
check in `flake.nix`'s `checks` for that machine's system; there are checks for Linux only. One check alone:
`nix build .#checks.x86_64-linux.<name>`. CI (`.github/workflows/nix.yml`) builds the same checks on pull
requests. Build-sandbox checks (`nix/checks/`) run inside Nix's build sandbox, with no network and no real
`$HOME`; a check that runs programs copies the configs into a temporary `HOME`. NixOS VM tests (`nix/tests/`,
x86_64-linux only) boot whole machines under QEMU and need KVM.

- `configs`: every config parses or loads (zsh, starship, atuin, herdr, Ghostty, nvim's Lua, TOML files).
- `zsh-interactive`: an interactive zsh in a pty prints nothing on stderr and has zsh-vi-mode, the prompt, fzf, atuin and zoxide.
- `scripts`: the herdr scripts run, and none calls `/usr/bin/python3`.
- `herdr-headless`: a herdr server starts in the temporary `HOME` and the summarizer's hook runs succeed (dry: no model calls).
- `tool-versions`: each tool is at or above the version the repo depends on, and tuicr matches `bootstrap.sh`'s pin.
- `lifeline-guard`: each config change the lockout drills expect the guard to refuse fails to evaluate.
- `link-modes`: the Home Manager module places exactly the Stow set, in both link modes.
- `vm-home`: users in each link mode log in over SSH into a clean zsh, a `checkout` edit is live without a rebuild, and an SSH login is tried after the user's `.zshrc` is broken.
- `vm-lifeline`: sshd answers on ports 22 and 2222, the firewall is up with both open, and sleep is masked.
