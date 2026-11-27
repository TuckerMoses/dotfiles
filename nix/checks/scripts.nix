# scripts (docs/design/nix-dotfiles.md, section 7): the packaged herdr scripts run, through the
# links in the throwaway HOME, in a build sandbox that has no /usr/bin at all.
{ pkgs, checkLib }:
let
  d = pkgs.dotfiles;
in
checkLib.mkCheck "scripts" { } ''
  bin="$HOME/.local/bin"
  t="$TMPDIR/scripts"
  mkdir -p "$t/fake"

  # ── Interpreters ─────────────────────────────────────────────────────────
  # NixOS has no /usr/bin/python3: no interpreter line or python call may name it. A
  # `/usr/bin/env python3` call is rewritten to the store python; the runs below prove it, as the
  # build sandbox has neither /usr/bin/env nor /usr/bin/python3.
  ${
    if pkgs.stdenv.hostPlatform.isLinux then
      ''[ ! -e /usr/bin/python3 ] || fail "the check namespace has /usr/bin/python3, so it cannot tell"''
    else
      # macOS builds have no sandbox and macOS has /usr/bin/python3, so there the text checks
      # below are the proof, not the runs.
      ":"
  }
  for f in ${d.scripts}/bin/* ${d.scripts}/bin/.*-wrapped; do
    line=$(head -1 "$f")
    [[ "$line" =~ ^\#!\ *(/[^ ]+) ]] || fail "$f: no interpreter line (got '$line')"
    interp=''${BASH_REMATCH[1]}
    [[ "$interp" == ${builtins.storeDir}/* ]] || fail "$f: interpreter $interp is not a store path"
    [ -x "$interp" ] || fail "$f: interpreter $interp does not exist"
    # A python path not inside a store path: /usr/bin/python3, /bin/python, ...
    hits=$(grep -nE '(^|[^-[:alnum:]._/])(/usr)?/bin/python' "$f" || true)
    [ -z "$hits" ] || fail "$f calls python outside the store: $hits"
  done
  echo "interpreters: every packaged script's interpreter is a store path and no python call names /usr/bin"

  # ── herdr-summarize ──────────────────────────────────────────────────────
  python3 -I -c 'import sys; p=sys.argv[1]; compile(open(p).read(), p, "exec")' \
    ${d.scripts}/bin/.herdr-summarize-wrapped || fail "herdr-summarize does not compile"
  res=$("$bin/herdr-summarize" help 2>&1) || fail "herdr-summarize help exited non-zero: $res"
  grep -q '^RECENT SESSIONS' <<<"$res" || fail "herdr-summarize help: expected a guide starting 'RECENT SESSIONS', got: $(head -3 <<<"$res")"
  echo "herdr-summarize: compiles and prints help"

  # $jj_status, as validate.sh checks it: nothing for a plain directory, '<change id>*' for a
  # repo with a change, the bookmark from a subdirectory once one is set.
  jt="$t/jj"
  mkdir -p "$jt"
  plain=$("$bin/herdr-summarize" jj-status "$jt") || fail "jj-status on a plain directory exited non-zero"
  [ -z "$plain" ] || fail "jj-status: a plain directory gave '$plain', expected nothing"
  (cd "$jt" && jj git init . && echo x > f && jj status) > "$t/jj.log" 2>&1 || fail "jj git init failed: $(cat "$t/jj.log")"
  dirty=$("$bin/herdr-summarize" jj-status "$jt") || fail "jj-status on a jj repo exited non-zero"
  [[ "$dirty" =~ ^[a-z]{8}\*$ ]] || fail "jj-status: got '$dirty' from a repo with a change, expected '<8-letter change id>*'"
  (cd "$jt" && jj bookmark create t -r @) >> "$t/jj.log" 2>&1 || fail "jj bookmark create failed: $(cat "$t/jj.log")"
  mkdir -p "$jt/sub"
  named=$("$bin/herdr-summarize" jj-status "$jt/sub") || fail "jj-status in a subdirectory exited non-zero"
  [ "$named" = 't*' ] || fail "jj-status: got '$named' from a subdirectory with bookmark t, expected 't*'"
  echo "herdr-summarize jj-status: nothing for a plain directory, '$dirty', then '$named'"

  # ── herdr-login-warning ──────────────────────────────────────────────────
  # A fake claude on PATH answers `claude auth status` with a login ending at a given time.
  fake_claude() {
    printf '#!${pkgs.runtimeShell}\necho %s\n' "$(printf '%q' "$1")" > "$t/fake/claude"
    chmod +x "$t/fake/claude"
  }
  at() { date -u -d "@$(( $(date +%s) + $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
  warn() { PATH="$PATH:$t/fake" "$bin/herdr-login-warning" 2>&1; }
  fake_claude "{\"loggedIn\": true, \"loginExpiresAt\": \"$(at 7200)\"}"
  res=$(warn) || fail "herdr-login-warning exited non-zero two hours from expiry: $res"
  [[ "$res" == *"claude login expires in 1h"* ]] || fail "two hours from expiry: expected 'claude login expires in 1h..', got '$res'"
  fake_claude "{\"loggedIn\": true, \"loginExpiresAt\": \"$(at 259200)\"}"
  res=$(warn) || fail "herdr-login-warning exited non-zero three days from expiry: $res"
  [ -z "$res" ] || fail "three days from expiry: expected no output, got '$res'"
  fake_claude "{\"loggedIn\": true, \"loginExpiresAt\": \"$(at -60)\"}"
  res=$(warn) || fail "herdr-login-warning exited non-zero after expiry: $res"
  [[ "$res" == *"claude login EXPIRED"* ]] || fail "after expiry: expected 'claude login EXPIRED', got '$res'"
  fake_claude '{"loggedIn": false}'
  res=$(warn) || fail "herdr-login-warning exited non-zero when signed out: $res"
  [[ "$res" == *"claude signed out"* ]] || fail "signed out: expected 'claude signed out', got '$res'"
  echo "herdr-login-warning: warns near expiry, after expiry and signed out; silent far from expiry"

  # ── herdr-recent ─────────────────────────────────────────────────────────
  # A fake herdr lists one agent and records what the picker focuses; fzf picks the only row
  # with --filter, so no tty is needed.
  cat > "$t/fake/herdr" <<EOF
  #!${pkgs.runtimeShell}
  case "\$1 \$2" in
    "agent list") echo '{"result": {"agents": [{"pane_id": "p-test", "workspace_id": "w1", "agent_session": {"value": "s1"}}]}}' ;;
    "workspace list") echo '{"result": {"workspaces": [{"workspace_id": "w1", "label": "picked"}]}}' ;;
    "agent focus") echo "\$3" > "$t/focused" ;;
    *) echo "fake herdr: unexpected \$*" >&2; exit 2 ;;
  esac
  EOF
  chmod +x "$t/fake/herdr"
  res=$(PATH="$t/fake:$PATH" FZF_DEFAULT_OPTS="--filter=picked" "$bin/herdr-recent" < /dev/null 2>&1) \
    || fail "herdr-recent exited non-zero: $res"
  [ "$(cat "$t/focused" 2>/dev/null)" = p-test ] || fail "herdr-recent did not focus the listed agent p-test: $res"
  echo "herdr-recent: lists agents through herdr-summarize and focuses the picked one"

  # ── herdr-plugins ────────────────────────────────────────────────────────
  res=$("$bin/herdr-plugins" help 2>&1) || fail "herdr-plugins help exited non-zero: $res"
  grep -qF 'Pins are read from ${d.scripts.dotfilesDir}/bootstrap.sh' <<<"$res" \
    || fail "herdr-plugins help: expected 'Pins are read from ${d.scripts.dotfilesDir}/bootstrap.sh', got: $(tail -2 <<<"$res")"
  echo "herdr-plugins: help runs and reads the packaged bootstrap.sh"
''
