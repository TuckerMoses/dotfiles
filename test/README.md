# test/

One suite, four places to run it. Not a stow package; `bootstrap.sh` never touches it.

```bash
test/suite.sh local         # throwaway $HOME on this machine (isolated from your herdr, tmux, env)
test/suite.sh vm-native     # fresh Ubuntu 26.04 guest, this machine's arch (HVF on macOS, KVM on Linux)
test/suite.sh vm-emulated   # fresh Ubuntu 26.04 guest, the other arch (TCG; an hour or more)
DOTFILES_TEST_DISPOSABLE=1 test/suite.sh here   # this Linux machine's real $HOME (guests, CI)
test/suite.sh report test/.runs/<run-dir>...    # side-by-side table for a PR
```

Each run tests the committed `HEAD` (copied as a git bundle; uncommitted changes are not
included) and runs the same core: `bootstrap.sh` three times (the third must install nothing),
a headless `herdr server`, nvim plugins from `lazy-lock.json`, one herdr-summarizer hook run
(`HERDR_SUMMARIZER_DRY=1`: no model calls), an interactive zsh in a pty, then `validate.sh`,
which must exit 0.

Exit codes: `0` passed, `1` the suite failed, `3` the environment could not be started
(download, checksum, QEMU, guest never reachable).

Results go to `test/.runs/<env>-<timestamp>/` (gitignored): `log`, `result` (one line per step),
`validate.txt`, `meta`; for guests also `console.log` and `guest/` (everything the guest wrote).

- `local` refuses to run if anything `bootstrap.sh` would install system-wide (brew, apt) is
  missing, and refuses if `HOME` resolves to your real home or any herdr socket outside it.
- Guests need `qemu-system-aarch64`/`qemu-system-x86_64`, `qemu-img` and UEFI firmware (Homebrew's
  `qemu` has all of them). Images are cached, checksum-verified, in
  `${DOTFILES_TEST_CACHE:-~/.cache/dotfiles-test}` (about 900 MB each); every run boots a fresh overlay.
- `--keep` leaves the throwaway HOME or the guest; `--resume <run-dir>` reboots a kept guest and
  continues from the first step that has not passed. Tunables: `--boot-timeout`, `--timeout`,
  `DOTFILES_TEST_CPUS`, `DOTFILES_TEST_MEM`.
