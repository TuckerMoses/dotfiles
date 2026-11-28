# Mac cutover: from Stow and Homebrew to the Nix route

This runbook is for the owner to follow at the Mac, with an assistant watching. It moves the Mac's dotfiles
from Stow to `homeConfigurations."johnmoses@mac"`, a standalone Home Manager configuration activated with
`dotfiles-switch` (the same shape homepc runs). Homebrew stays, and so does everything this repo does not
manage. Plan for about an hour. **Keep one terminal window open from start to finish.** A shell that is already
running does not reread its startup files, so a bad config cannot lock you out of that window.

What CI proves first: the `darwin` job in `.github/workflows/nix.yml` builds this configuration and the Darwin
checks on GitHub's Apple Silicon runner, and activates `runner@mac-ci` there (a dry run, a switch, a clean login
zsh, herdr's config and plugins, a rollback). Before you start, check that the job is green on the commit
you are about to use.

## 1. Install Nix (the official installer, Nix 2.34.9)

Use the official installer at the version CI and homepc run, and check its hash against the one in
`nix.yml`. The two alternatives were rejected. The Determinate Systems installer now installs Determinate
Nix, not upstream Nix. Lix's installer installs Lix, a separate implementation. Both are better than the
official installer in two ways: macOS updates do not break them, and each has a one-command uninstaller.
The official installer has neither. Step 6 explains what to do when a macOS update removes Nix's shell
hook, and step 9 gives the uninstall steps.

```sh
curl -fsSL -o /tmp/nix-install https://releases.nixos.org/nix/nix-2.34.9/install
shasum -a 256 /tmp/nix-install
# must print a03ce2e9eaf4ea1560260b9a93e311dbaf589d28fb5c9318f8d9e768ee6339d8 (stop if not)
sh /tmp/nix-install --daemon
```

The installer first lists everything it will do, then asks "Ready to continue?", then asks for your password
(sudo) several times. It does the following:

- creates an APFS volume named "Nix Store", mounted at `/nix` (encrypted when FileVault is on), through
  `/etc/synthetic.conf` and `/etc/fstab`
- creates the `nixbld` group and the `_nixbld` build users
- adds two launchd daemons, `org.nixos.nix-daemon` and `org.nixos.darwin-store`
- appends a hook to `/etc/zshrc` and `/etc/bashrc`, keeping the originals as `*.backup-before-nix`

It does not touch your home. Open a **new** window and run `nix --version`. It should print 2.34.9.

## 2. Pre-flight: see what is in the way

This step and step 4 need a checkout that has the Nix files. After the pull request is merged, that is
`~/dotfiles` on `master`, and the commands below work as written. Before the merge, `~/dotfiles` does not have
them: point both commands at a checkout of the branch instead, replacing `.` and `~/dotfiles` with its path
and adding `--flake <that path>` after `--`. Step 3's `stow -D` always runs from `~/dotfiles`, where the
Stow links point.

```sh
cd ~/dotfiles && git pull
nix --extra-experimental-features 'nix-command flakes' run .#dotfiles-switch -- --dry-run
```

Run on this Mac on 2026-11-28 (macOS 27.2, from the branch): it built, listed 38 files to place, and listed
as collisions exactly the Stow-linked files and `.oh-my-zsh`.

This builds the configuration (the first time, it downloads a lot) and prints the files it would place. It
activates nothing. Under "Collisions" you will see every file Stow links today, plus `.oh-my-zsh`. Each
`~/.config/nvim/...` file is listed too, because `~/.config/nvim` is one directory link.

## 3. Clear the way (in this order)

```sh
cd ~/dotfiles
stow -d ~/dotfiles -t ~ -D zsh ghostty starship nvim atuin
stow -d ~/dotfiles -t ~ --no-folding -D herdr          # herdr was stowed --no-folding
readlink ~/.tmux.conf && rm ~/.tmux.conf               # the retired tmux package's leftover link
mv ~/.oh-my-zsh ~/.oh-my-zsh.pre-nix                   # moved aside, not deleted
```

After `stow -D`, `~/.zshrc` is gone, and so are the directory links `~/.config/nvim`, `~/.config/ghostty` and
`~/.config/atuin`. Home Manager recreates each of those as a real directory of per-file links. nvim's plugins
(`~/.local/share/nvim`) and atuin's history (`~/.local/share/atuin`) are not touched. Do not open a new shell
until step 5. Run the dry run from step 2 again. "Collisions" must now say `none`. Move anything still
listed aside the same way (`mv ~/X ~/X.pre-nix`).

## 4. Activate

```sh
nix --extra-experimental-features 'nix-command flakes' run ~/dotfiles#dotfiles-switch
```

It prints three lines of the form `dotfiles: herdr plugin <id> is installed by herdr itself (github); left
as it is`, explained in step 7. It also prints `dotfiles: herdr reloaded its config`, because the running
herdr server picks up the new `config.toml`. If it prints `did not apply` instead, reload by hand with
`herdr server reload-config` or `prefix+shift+r`. From now on, `dotfiles-switch` is on `PATH`.

## 5. Check, in a NEW window (keep the old one open)

```sh
which -a herdr starship nvim     # the first of each: ~/.nix-profile/bin/...
herdr config check               # config: ok
herdr-plugins check              # three "ok ... at its pin" lines
nvim                             # starts, LazyVim loads, :q
```

The new window must open with no error text, and the starship prompt must show. If anything is wrong, go
back to the old window and take the way back (step 9). Open a new Ghostty window too. Ghostty reads the
placed `~/.config/ghostty/config`. The Nerd Font is copied into `~/Library/Fonts/HomeManager`.
`./validate.sh` still reports the Stow checks as failures. That is expected on a Nix home.

From now on, do not run `./bootstrap.sh` or `stow`, except as part of the way back (step 9). Either one would
try to restow over Home Manager's links. A config change now goes: edit the file in `~/dotfiles`, then run
`dotfiles-switch`.

## 6. PATH order (read this once)

Startup order for a login shell: `~/.zshenv`, then `/etc/zprofile` (path_helper), then `~/.zprofile` (`brew
shellenv`, then `~/.local/bin` and the venv first), then `/etc/zshrc`, then `~/.zshrc`. The Nix hook lives in
`/etc/zshrc`, so it runs after `~/.zprofile` and puts `~/.nix-profile/bin` and
`/nix/var/nix/profiles/default/bin` **ahead of** `~/.local/bin`, the venv and `/opt/homebrew/bin`. The Nix
copies of herdr, nvim, starship, jj, fzf, atuin, zoxide, lazygit, lazyjj, tmux, gh and jq win. On macOS the
Nix profile deliberately has no python3, git, compilers or GNU base commands, so the venv's python3,
Xcode's git and cc, rustup's cargo and the BSD `sed`/`ls`/`find` are still the ones you get.

There is one exception. The hook runs only once per environment (it exports `__ETC_PROFILE_NIX_SOURCED`). A
login shell started from inside another shell (`zsh -l`, or a pane in a program that starts login shells)
skips the hook, while path_helper and `brew shellenv` still reorder `PATH`. In such a shell,
`which herdr` shows `/opt/homebrew/bin/herdr`. Check inside a herdr pane with `which -a herdr`. If Homebrew's
copy comes first there, add this line at the **end** of `~/.zprofile`:

```zsh
path=("$HOME/.nix-profile/bin" ${path:#$HOME/.nix-profile/bin})
```

Once the duplicated Homebrew formulae are uninstalled (step 8), the order stops mattering.

A macOS update can replace `/etc/zshrc` and with it the hook. You would then see `nix: command not found` and
Homebrew's tools again. Put these lines back at the end of `/etc/zshrc` (`sudo nano /etc/zshrc`):

```sh
# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix
```

## 7. herdr and its plugins

The running server is Homebrew's herdr (0.9.5, the same version Nix provides), and it keeps running. Its
three plugins were installed by herdr itself, so the activation leaves them alone and warns about each one.
They are at the pins, so `herdr-plugins check` passes. You can stay this way: `herdr-plugins update` still
reinstalls them through herdr and moves the pin in `~/dotfiles/bootstrap.sh`.

To switch to the Nix builds instead (the same commits, built by Nix), do this once:

```sh
herdr plugin uninstall vim-herdr-navigation
herdr plugin uninstall cloudmanic.herdr-plus
herdr plugin uninstall nathan-poncet.herdr-fingers
dotfiles-switch                  # prints "dotfiles: linked herdr plugin <id>" three times
herdr plugin list                # each: enabled [local:/nix/store/...]
herdr-plugins check
```

Uninstalling herdr-plus may delete its config directory. `dotfiles-switch` puts those links back. If a
plugin key (`prefix+t`, `prefix+f`, `ctrl+h`) stops responding, restart herdr when convenient. The server
then runs as the Nix herdr if your shell finds that one first. After this switch, moving a pin goes:
`herdr-plugins update <plugin>` (it edits `~/dotfiles/bootstrap.sh` and prints the next two commands),
then `nix run .#herdr-plugin-hashes ...`, then `dotfiles-switch`.

### Before you ever stop the server: prove the restore

The cutover leaves the running server alone. It is Homebrew's herdr, and it stays that until you stop it
yourself. After that, `herdr` starts the Nix build, which restores from the same files
(`~/.config/herdr/session.json`, `session-history.json`, `session-snapshots/`, `sessions/` and
`~/.local/state/herdr/`). Both builds are 0.9.5 and neither route touches those files, so it should restore.
Nobody has seen one build restore the other's session, so test it on a throwaway named session first. Your
real session is not involved:

```sh
/opt/homebrew/bin/herdr --session restore-test     # make a tab and a split or two, then detach (prefix+d)
herdr session stop restore-test
~/.nix-profile/bin/herdr --session restore-test    # the layout should come back
herdr session delete restore-test                  # after detaching again
```

If the layout does not come back, keep starting herdr as `/opt/homebrew/bin/herdr` and do not uninstall
Homebrew's copy.

## 8. What stays on Homebrew

Everything this repo does not manage stays on Homebrew: about 50 formulae and casks, plus tuicr (nixpkgs
has 0.29.0, and the repo needs 0.30.0) and stow (the way back needs it). `herdr-summarize` looks in
`/opt/homebrew/bin` before `PATH`, so it uses Homebrew's herdr for as long as that is installed. A later,
optional step is to `brew uninstall` the formulae Nix now provides (herdr, jj, nvim, starship, atuin,
zoxide, fzf, lazygit, lazyjj, zsh-vi-mode, tmux, jq, gh, go). Run `brew uses --installed <formula>` first,
and uninstall herdr only after the restore test in step 7 has passed and the server has been restarted
from the Nix herdr. Until then Homebrew's copy is the way to start your session as it always has. While Homebrew has
zsh-vi-mode, `.zshrc` sources that copy rather than the one in the Nix Oh My Zsh bundle. Both work.

## 9. The way back

**One generation back.** `dotfiles-switch --rollback` activates the previous generation. It cannot go back
from the first generation: there is nothing before it.

**Back to Stow** (Nix stays installed). In the old window:

```sh
gen=$(readlink ~/.local/state/home-manager/gcroots/current-home)
(cd "$gen/home-files" && find . \( -type f -o -type l \) | sed 's|^\./||') | while read -r f; do
  [[ -L ~/$f && $(readlink ~/"$f") == /nix/store/* ]] && rm ~/"$f"
done
rm -f ~/.config/nvim/lazy-lock.json ~/.config/nvim/lazyvim.json      # copies, not links
find ~/.config/nvim ~/.config/ghostty ~/.config/atuin -depth -type d -empty -delete
nix-env -e home-manager-path     # the Nix profile's tools
rm -rf ~/.local/state/home-manager ~/.local/share/home-manager ~/.local/state/nix/profiles/home-manager*
mv ~/.oh-my-zsh.pre-nix ~/.oh-my-zsh                                  # and any other *.pre-nix
```

If you moved herdr to the Nix-built plugins (step 7), unregister each Nix-built plugin first so
`bootstrap.sh` reinstalls it. Linked plugins may use `unlink` instead of `uninstall`; `herdr plugin --help`
names the subcommand. Then restow and reinstall:

```sh
cd ~/dotfiles && ./bootstrap.sh     # restows zsh ghostty starship nvim atuin, herdr --no-folding; ends with validate.sh
```

**Removing Nix entirely** (optional, after "Back to Stow"):

```sh
sudo mv /etc/zshrc.backup-before-nix /etc/zshrc     # if macOS replaced /etc/zshrc since, delete the "# Nix" block instead
sudo mv /etc/bashrc.backup-before-nix /etc/bashrc
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo rm /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo launchctl unload /Library/LaunchDaemons/org.nixos.darwin-store.plist
sudo rm /Library/LaunchDaemons/org.nixos.darwin-store.plist
sudo dscl . -delete /Groups/nixbld
for u in $(sudo dscl . -list /Users | grep _nixbld); do sudo dscl . -delete "/Users/$u"; done
sudo vifs                            # delete the line that mounts /nix
sudo nano /etc/synthetic.conf        # delete the "nix" line (the file, if it was the only line)
sudo rm -rf /etc/nix /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels \
  ~/.nix-profile ~/.nix-defexpr ~/.nix-channels
sudo diskutil apfs deleteVolume /nix
```

Then reboot.

## What has and has not been tested

- **Tested in CI on the macOS runner:** step 4 and `--rollback`, and step 5's zsh, herdr and plugin checks,
  for a fresh user.
- **Tested on this Mac (macOS 27.2), 2026-11-28:** step 1 (the installer: Nix 2.34.9, daemon running, hook in
  `/etc/zshrc`) and step 2 (the dry run).
- **Not tested on this Mac or on macOS 27:**
  - the herdr reload against a running Homebrew server
  - whether herdr panes are login shells (step 6)
  - the plugin switch (step 7)
  - the Nix herdr restoring a session the Homebrew herdr saved (step 7 has the test)
  - everything in step 9
- If something differs, the step's own check is where you see it.
