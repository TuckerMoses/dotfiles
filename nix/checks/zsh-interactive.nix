# zsh-interactive (docs/design/nix-dotfiles.md, section 7; step 7 of test/suite.sh): a real
# interactive zsh in a pty prints nothing on stderr and has zsh-vi-mode, the starship prompt
# hook, ^T bound to fzf, ^R bound to atuin and zoxide's cd. A throwaway tmux server is the pty:
# zsh-vi-mode runs zvm_after_init (fzf, atuin) at the first prompt, which `zsh -i -c` never shows.
{ pkgs, checkLib }:
let
  # Darwin builds run outside a sandbox, where nixpkgs' zsh would read the machine's /etc/zshrc
  # (macOS's own, plus the Nix installer's hook); the check is about the repo's files only.
  # The darwin job's activation step starts a zsh with them.
  zshFlags = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin " +o GLOBAL_RCS";
in
checkLib.mkCheck "zsh-interactive" { } ''
  probe="$TMPDIR/zsh-probe.zsh" res="$TMPDIR/zsh-probe.out" err="$TMPDIR/zsh-stderr.txt"
  # The probes are test/suite.sh's.
  cat > "$probe" <<'EOF'
  print -r -- "zvm=''${+functions[zvm_init]}"
  print -r -- "starship=''${+functions[prompt_starship_precmd]}"
  [[ "$(bindkey -M viins '^T')" == *fzf* ]] && print fzf=1 || print fzf=0
  [[ "$(bindkey -M viins '^R')" == *atuin* ]] && print atuin=1 || print atuin=0
  print -r -- "zoxide=''${+functions[__zoxide_z]}"
  print -r -- probe-done
  EOF
  tmux -L zsh -f /dev/null new-session -d -x 160 -y 40 "cd '$HOME' && exec '$SHELL'${zshFlags} -i 2>'$err'"
  prompt=0
  for _ in $(seq 1 120); do
    if [ -n "$(tmux -L zsh capture-pane -p 2>/dev/null | tr -d '[:space:]')" ]; then prompt=1; break; fi
    sleep 0.5
  done
  [ $prompt = 1 ] || { tmux -L zsh kill-server || true; fail "zsh showed no prompt within 60s; stderr: $(cat "$err" 2>/dev/null)"; }
  sleep 2
  tmux -L zsh send-keys "source '$probe' > '$res' 2>&1; exit" Enter
  for _ in $(seq 1 120); do grep -q probe-done "$res" 2>/dev/null && break; sleep 0.5; done
  screen=$(tmux -L zsh capture-pane -p 2>/dev/null || true)
  tmux -L zsh kill-server 2>/dev/null || true
  grep -q probe-done "$res" 2>/dev/null || fail "zsh never finished the probe within 60s; screen: $screen"
  sed 's/^/    | /' "$res"
  if [ -s "$err" ]; then fail "interactive zsh wrote to stderr (expected nothing): $(cat "$err")"; fi
  missing=""
  for i in zvm starship fzf atuin zoxide; do grep -qx "$i=1" "$res" || missing="$missing $i"; done
  [ -z "$missing" ] || fail "not loaded (expected zvm starship fzf atuin zoxide all =1):$missing"
  echo "zsh: stderr empty; zsh-vi-mode, starship, fzf, atuin and zoxide loaded"
''
