# configs (docs/design/nix-dotfiles.md, section 7): every config parses or loads in the program
# that reads it, against a throwaway HOME filled from home-tree.
{ pkgs, checkLib }:
let
  d = pkgs.highwind;
  # Check-only: Ghostty's closure is large and only its config parser is needed here. nixpkgs
  # builds Ghostty from source on Linux only; on macOS it repackages the release app.
  ghostty = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
in
checkLib.mkCheck "configs" { } ''
  # ── zsh ──────────────────────────────────────────────────────────────────
  err=$(zsh -n "$HOME/.zshrc" 2>&1) || fail "zsh -n ~/.zshrc: $err"
  echo "zsh: ~/.zshrc parses"

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
