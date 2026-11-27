# herdr-headless (docs/design/nix-dotfiles.md, section 7; steps 2 and 6 of test/suite.sh): a
# herdr server starts in the throwaway HOME, the packaged summarizer plugin links, and creating
# a workspace produces hook runs that all succeed and a non-empty state file. No model calls:
# HERDR_SUMMARIZER_DRY=1 is exported before the server starts, so every hook run inherits it.
# Then herdr's three third-party plugins, the Nix builds, link as the Home Manager module links
# them: herdr lists each enabled, herdr-plugins check finds each at its bootstrap.sh pin, every
# plugin_action key binding names an action herdr lists, the built binaries run, and nvim finds
# the navigation plugin's editor file.
{ pkgs, checkLib }:
let
  lib = pkgs.lib;
  plugins = pkgs.dotfiles.herdr-plugins;
  ids = lib.attrNames plugins.plugins;
in
checkLib.mkCheck "herdr-headless" { } ''
  export HERDR_SUMMARIZER_DRY=1
  export HERDR_SUMMARIZER_STATE="$HOME/.local/state/herdr-summarizer"
  mkdir -p "$HERDR_SUMMARIZER_STATE"

  # ── Isolation guard ──────────────────────────────────────────────────────
  # As test/suite.sh: nothing from an outer herdr session in the environment, and the socket
  # herdr resolves is inside $HOME.
  # (env, not compgen: the build's bash has no completion builtins.)
  outer=$(env | grep -oE '^HERDR_[A-Za-z0-9_]*=' | grep -v '^HERDR_SUMMARIZER_' || true)
  [ -z "$outer" ] || fail "refusing: outer herdr variables are set: $outer"
  sock=$(herdr status server 2>/dev/null | sed -n 's/^ *socket: //p' | head -1 | tr -s /)
  [[ -n "$sock" && "$sock" == "$HOME"/* ]] || fail "refusing: herdr would use socket '$sock', not inside $HOME"

  # ── Server ───────────────────────────────────────────────────────────────
  herdr server > "$TMPDIR/herdr-server.log" 2>&1 < /dev/null &
  server=$!
  stop() {
    herdr server stop > /dev/null 2>&1 || true
    for _ in $(seq 1 50); do kill -0 "$server" 2>/dev/null || break; sleep 0.1; done
    kill "$server" 2>/dev/null || true
    wait "$server" 2>/dev/null || true
  }
  trap stop EXIT
  up=0
  for _ in $(seq 1 600); do
    if herdr workspace list > /dev/null 2>&1; then up=1; break; fi
    sleep 0.1
  done
  [ $up = 1 ] || fail "herdr server did not answer within 60s; log: $(tail -20 "$TMPDIR/herdr-server.log")"
  echo "herdr: server answering on $sock"

  # ── Summarizer plugin ────────────────────────────────────────────────────
  res=$(herdr plugin link "$HOME/.local/share/dotfiles/herdr-summarizer-plugin" 2>&1) \
    || fail "herdr plugin link of the summarizer failed: $res"
  herdr plugin list 2>/dev/null | grep -q '^- herdr-summarizer ' \
    || fail "herdr plugin list does not show herdr-summarizer after linking: $(herdr plugin list 2>&1)"
  echo "herdr: summarizer plugin linked"

  # Creating and focusing a workspace emits pane.focused, which the plugin subscribes to.
  res=$(herdr workspace create --cwd "$HOME" --label check --focus 2>&1) || fail "herdr workspace create failed: $res"
  verdict=wait
  for _ in $(seq 1 120); do
    logs=$(herdr plugin log list --plugin herdr-summarizer --limit 50 2>/dev/null || true)
    verdict=$(python3 -I -c 'import json, sys
  try: logs = json.load(sys.stdin)["result"]["logs"]
  except Exception: logs = []
  done = [l for l in logs if l.get("status") not in ("running", "pending", "queued")]
  bad = [l for l in done if l.get("status") != "succeeded"]
  if not logs or len(done) < len(logs): print("wait")
  elif bad: print("fail %d of %d hook runs failed: %s" % (len(bad), len(logs), (bad[0].get("stderr") or "")[:400].replace("\n", " ")))
  else: print("pass %d hook runs succeeded (%s)" % (len(logs), ",".join(sorted(set(l["event"] for l in logs)))))' <<<"$logs")
    [ "$verdict" != wait ] && break
    sleep 1
  done
  case "$verdict" in
    pass*) echo "summarizer: ''${verdict#pass }" ;;
    fail*) fail "summarizer: ''${verdict#fail }" ;;
    *) fail "summarizer: no finished hook run logged within 120s; server log: $(tail -20 "$TMPDIR/herdr-server.log")" ;;
  esac
  # The hook only marks the session dirty and starts a detached worker, which writes the state.
  for _ in $(seq 1 120); do [ -s "$HERDR_SUMMARIZER_STATE/state.json" ] && break; sleep 1; done
  [ -s "$HERDR_SUMMARIZER_STATE/state.json" ] \
    || fail "summarizer: hook ran but herdr-summarize wrote no state to $HERDR_SUMMARIZER_STATE/state.json within 120s"
  echo "summarizer: state file written ($(wc -c < "$HERDR_SUMMARIZER_STATE/state.json") bytes)"

  # ── Third-party plugins ──────────────────────────────────────────────────
  # The module's stable path, then one link each, as its activation step does.
  pdir="$HOME/.local/share/dotfiles/herdr-plugins"
  mkdir -p "$pdir"
  for p in ${plugins}/*; do ln -s "$(readlink -f "$p")" "$pdir/''${p##*/}"; done
  for p in "$pdir"/*; do
    res=$(herdr plugin link "$p" 2>&1) || fail "herdr plugin link $p failed: $res"
  done
  list=$(herdr plugin list 2>&1)
  for id in ${lib.escapeShellArgs ids}; do
    grep -qE "^- $id \(.*\) enabled \[local:/nix/store/" <<<"$list" \
      || fail "herdr plugin list does not show $id enabled and linked from the store: $list"
  done
  echo "plugins: ${toString (lib.length ids)} linked and enabled"

  # herdr lists a link with no commit; herdr-plugins reads the build's .dotfiles-pin.
  rc=0; out=$(herdr-plugins check 2>&1) || rc=$?
  [ "$rc" = 0 ] || fail "herdr-plugins check exited $rc: $out"
  n=$(grep -c '^ok .* at its pin ' <<<"$out" || true)
  [ "$n" = ${toString (lib.length ids)} ] && ! grep -qv '^ok ' <<<"$out" \
    || fail "herdr-plugins check does not find every plugin at its pin: $out"
  echo "plugins: herdr-plugins check: $(tr '\n' ';' <<<"$out")"

  # `herdr config check` accepts any action name, so the bindings are compared with the list.
  res=$(herdr config check 2>&1) || fail "herdr config check failed: $res"
  [ "$res" = "config: ok" ] || fail "herdr config check: $res"
  res=$(python3 -I - "$HOME/.config/herdr/config.toml" "$(herdr plugin action list)" <<'PY'
  import json, sys, tomllib
  with open(sys.argv[1], "rb") as f:
      cfg = tomllib.load(f)
  listed = {a["plugin_id"] + "." + a["action_id"] for a in json.loads(sys.argv[2])["result"]["actions"]}
  binds = [k.get("command") for k in cfg.get("keys", {}).get("command", []) if k.get("type") == "plugin_action"]
  bad = [b for b in binds if b not in listed]
  if not binds or bad:
      print("bound but not listed: %s" % (bad or "no plugin_action bindings at all"))
      sys.exit(1)
  print("%d plugin_action bindings, all listed" % len(binds))
  PY
  ) || fail "plugin_action bindings: $res"
  echo "plugins: $res"

  # The binaries the manifests run, at the paths they run them from.
  fingers="$pdir/nathan-poncet.herdr-fingers/target/release/herdr-fingers"
  res=$(echo "commit 2d9fc997ce1a95976b975da758dccc7b6e011336" | env -u HERDR_PLUGIN_CONFIG_DIR "$fingers" scan --width 80 2>&1) \
    || fail "herdr-fingers scan failed: $res"
  [[ "$res" == *2d9fc997ce1a* ]] || fail "herdr-fingers scan found no hint in a line holding a SHA: $res"
  res=$("$pdir/cloudmanic.herdr-plus/bin/herdr-plus" --version 2>&1) || fail "herdr-plus --version failed: $res"
  [[ "$res" == herdr-plus* ]] || fail "herdr-plus --version: $res"
  echo "plugins: herdr-fingers scans, $res runs"

  # The repo's nvim spec, without LazyVim (no network here): its init finds the editor file.
  res=$(nvim --headless -u NONE -i NONE \
    +"lua dofile(vim.fn.expand('~/.config/nvim/lua/plugins/herdr.lua'))[1].init(); io.stdout:write((vim.fn.maparg('<C-h>', 'n', false, true).desc or 'none') .. '\n')" \
    +qa 2>&1)
  [[ "$res" == *"Navigate left (vim/herdr)"* ]] || fail "nvim did not load vim-herdr-navigation's editor file: $res"
  echo "plugins: nvim maps <C-h> to vim-herdr-navigation"

  stop
  trap - EXIT
''
