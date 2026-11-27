# configs (docs/design/nix-dotfiles.md, section 7): every config parses or loads in the program
# that reads it, against a throwaway HOME filled from home-tree.
{ pkgs, checkLib }:
let
  d = pkgs.dotfiles;
  # Check-only: Ghostty's closure is large and only its config parser is needed here.
  ghostty = pkgs.ghostty;
in
checkLib.mkCheck "configs" { } ''
  # ── zsh ──────────────────────────────────────────────────────────────────
  err=$(zsh -n "$HOME/.zshrc" 2>&1) || fail "zsh -n ~/.zshrc: $err"
  echo "zsh: ~/.zshrc parses"

  # ── tmux ─────────────────────────────────────────────────────────────────
  # source-file reports each bad line on stderr; errors from -f only reach an attached client.
  # The config ends by running TPM, which sources each plugin before source-file returns.
  errs=$(tmux -L cfg -f /dev/null new-session -d 'sleep 60' \; source-file "$HOME/.tmux.conf" 2>&1) \
    || fail "tmux: the throwaway server did not start or source-file failed: $errs"
  [ -z "$errs" ] || fail "tmux: ~/.tmux.conf printed errors: $errs"
  keys=$(tmux -L cfg list-keys -T prefix)
  status_right=$(tmux -L cfg show -gv status-right)
  tmux -L cfg kill-server
  # One mark per plugin, each set only by that plugin's own *.tmux file.
  grep -q 'tpm/bindings/install_plugins' <<<"$keys" || fail "tmux: TPM not sourced (prefix I is not its install binding)"
  grep -qE '^bind-key +-T prefix +R +run-shell .*Sourced' <<<"$keys" || fail "tmux: tmux-sensible not sourced (no prefix R reload binding)"
  grep -q 'resurrect/scripts/save.sh' <<<"$keys" || fail "tmux: tmux-resurrect not sourced (prefix C-s is not its save binding)"
  grep -q 'continuum_save.sh' <<<"$status_right" || fail "tmux: tmux-continuum not sourced (status-right lacks its save interpolation): $status_right"
  echo "tmux: ~/.tmux.conf loads cleanly; tpm, tmux-sensible, tmux-resurrect and tmux-continuum sourced"

  # ── starship ─────────────────────────────────────────────────────────────
  # A TOML error is a warning on stderr with exit 0, so stderr must be empty.
  err=$(starship print-config 2>&1 >/dev/null) || fail "starship print-config exited non-zero: $err"
  [ -z "$err" ] || fail "starship print-config printed: $err"
  echo "starship: config parses"

  # ── atuin ────────────────────────────────────────────────────────────────
  got=$(atuin config get --resolved auto_sync 2>&1 | tail -1) || fail "atuin config get failed: $got"
  [ "$got" = false ] || fail "atuin: auto_sync resolves to '$got', expected 'false'"
  echo "atuin: auto_sync resolves to false"

  # ── herdr ────────────────────────────────────────────────────────────────
  res=$(herdr config check 2>&1) || fail "herdr config check exited non-zero: $res"
  grep -q 'config: ok' <<<"$res" || fail "herdr config check: expected 'config: ok', got: $res"
  echo "herdr: config.toml valid"

  # ── ghostty ──────────────────────────────────────────────────────────────
  res=$(${ghostty}/bin/ghostty +validate-config --config-file="$HOME/.config/ghostty/config" 2>&1) \
    || fail "ghostty +validate-config: $res"
  echo "ghostty: config valid"

  # ── nvim Lua ─────────────────────────────────────────────────────────────
  # Compiled by nvim's own LuaJIT, without running the files.
  mapfile -t lua < <(find ${d.home-tree}/.config/nvim -name '*.lua' | sort)
  [ "''${#lua[@]}" -gt 0 ] || fail "nvim: no Lua files found under .config/nvim"
  cat > "$TMPDIR/compile.lua" <<'EOF'
  local bad = 0
  for _, f in ipairs(arg) do
    local ok, err = loadfile(f)
    if not ok then io.stderr:write(err .. "\n"); bad = bad + 1 end
  end
  os.exit(bad == 0 and 0 or 1)
  EOF
  res=$(nvim --clean -l "$TMPDIR/compile.lua" "''${lua[@]}" 2>&1) || fail "nvim: Lua files do not compile: $res"
  echo "nvim: ''${#lua[@]} Lua files compile"

  # ── TOML ─────────────────────────────────────────────────────────────────
  mapfile -t toml < <(find ${d.home-tree} ${d.summarizer-plugin} -name '*.toml' | sort)
  [ "''${#toml[@]}" -gt 0 ] || fail "no TOML files found"
  res=$(python3 -I -c 'import sys, tomllib
  bad = 0
  for p in sys.argv[1:]:
      try:
          with open(p, "rb") as f:
              tomllib.load(f)
      except Exception as e:
          print("%s: %s" % (p, e)); bad += 1
  sys.exit(1 if bad else 0)' "''${toml[@]}" 2>&1) || fail "TOML files do not parse: $res"
  echo "toml: ''${#toml[@]} files parse"
''
