# link-modes (docs/design/nix-dotfiles.md, section 7): the Home Manager module places exactly the
# Stow set, in both link modes, for a test user: all of it with the personal profile on, the Stow
# set minus the personal files with it off. No base file names the owner's directories, and
# highwind.interactiveShell appends one setting to herdr's and Ghostty's configs, both valid.
{
  pkgs,
  home-manager,
  nixpkgs,
  homeModule,
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  root = ../..;
  data = import ../lib/bootstrap-data.nix { inherit lib; };
  # As configs.nix: nixpkgs builds Ghostty on Linux and repackages the release app on macOS.
  ghostty = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;

  # ── Stow set ─────────────────────────────────────────────────────────────
  # The flake source holds tracked files only, so listing it equals `git ls-files -- <pkg>`
  # (there is no .git in the build). A name with no directory is skipped, as validate.sh does.
  stowPackages = lib.filter (p: lib.pathIsDirectory (root + "/${p}")) data.stowPackages;
  stowFiles = lib.concatMap (
    p:
    map (f: {
      pkg = p;
      rel = lib.removePrefix "./" (lib.path.removePrefix (root + "/${p}") f);
    }) (lib.filesystem.listFilesRecursive (root + "/${p}"))
  ) stowPackages;
  scriptNames = [
    "herdr-summarize"
    "herdr-recent"
    "herdr-login-warning"
    "herdr-plugins"
  ];
  nvimCopied = [
    ".config/nvim/lazy-lock.json"
    ".config/nvim/lazyvim.json"
  ];
  # Linked config files: everything but the scripts and the two copied nvim files.
  configFiles = lib.filter (
    f: !(lib.elem f.rel nvimCopied) && !(lib.elem f.rel (map (s: ".local/bin/${s}") scriptNames))
  ) stowFiles;

  # ── Profiles ─────────────────────────────────────────────────────────────
  # home-tree says which files are personal; the content rule in the script checks that it says
  # so of every file that names the owner's directories.
  tree = pkgs.highwind.home-tree;
  personalRels = map (f: f.rel) (lib.filter (f: f.profile == "personal") tree.files);
  baseFiles = lib.filter (f: !(lib.elem f.rel personalRels)) stowFiles;
  # Personal entries named file by file must exist, so a rename cannot leave one stale.
  stalePersonal = lib.filter (r: !(lib.elem r (map (f: f.rel) stowFiles))) tree.personal.files;

  # ── Placed set ───────────────────────────────────────────────────────────
  mkHome =
    extra:
    home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        homeModule
        {
          home.username = "test";
          home.homeDirectory = import ../lib/home-directory.nix { inherit lib; } system "test";
          home.stateVersion = "26.05";
          highwind.enable = true;
        }
        extra
      ];
    };
  checkout = "/test/checkout";
  zsh = lib.getExe pkgs.zsh;
  homes = {
    store = mkHome { highwind.linkMode = "store"; };
    checkout = mkHome {
      highwind.linkMode = "checkout";
      highwind.checkout = checkout;
    };
    personal = mkHome { highwind.profiles.personal.enable = true; };
    shell = mkHome { highwind.interactiveShell = pkgs.zsh; };
  };
  excluded =
    t:
    t == ".oh-my-zsh"
    || lib.hasPrefix ".local/share/highwind/" t
    || lib.elem t data.homeManagerTargets;
  placed =
    h: lib.filter (t: !excluded t) (map (f: f.target) (lib.attrValues h.config.home.file)) ++ nvimCopied;

  # Configurations that must not build.
  refuses = extra: !(builtins.tryEval homesBad.${extra}.activationPackage.drvPath).success;
  homesBad = {
    unset = mkHome { highwind.linkMode = "checkout"; };
    relative = mkHome {
      highwind.linkMode = "checkout";
      highwind.checkout = "test/checkout";
    };
    shell = mkHome {
      highwind.linkMode = "checkout";
      highwind.checkout = checkout;
      highwind.interactiveShell = pkgs.zsh;
    };
  };

  lines = l: pkgs.writeText "lines" (lib.concatLines l);
  stowList = lines (map (f: "${f.pkg}/${f.rel}") stowFiles);
  stowSet = lines (map (f: f.rel) stowFiles);
  baseSet = lines (map (f: f.rel) baseFiles);
  # The content rule reads configs; the scripts' own text (help, comments) may name the repo.
  baseList = lines (
    map (f: "${f.pkg}/${f.rel}") (
      lib.filter (f: !(lib.elem f.rel (map (s: ".local/bin/${s}") scriptNames))) baseFiles
    )
  );
  configList = lines (map (f: "${f.pkg} ${f.rel}") configFiles);
  stowSrc = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions (map (p: root + "/${p}") stowPackages);
  };
  expectedDir = {
    store = "${pkgs.highwind.bootstrap-dir}";
    inherit checkout;
  };
  herdrConfig = ".config/herdr/config.toml";
  ghosttyConfig = ".config/ghostty/config";

  # `name`: the home; `expect`: the set it must place (stow-set or base-set); `cmpSkip`: files
  # placed as edited copies, checked on their own below.
  homeScript =
    name:
    {
      expect,
      cmpSkip ? [ ],
    }:
    let
      h = homes.${name};
      mode = h.config.highwind.linkMode;
    in
    ''
      m=${name} mode=${mode}
      hf=${h.config.home-files}
      act=${h.activationPackage}
      LC_ALL=C sort ${lines (placed h)} > placed-$m
      diff -u ${expect} placed-$m > diff-$m || {
        cat diff-$m >&2
        fail "$m: the placed set differs from ${expect} (- expected only, + placed only)"
      }
      while read -r p rel; do
        grep -qxF "$rel" ${expect} || continue
        [ -e "$hf/$rel" ] || [ -L "$hf/$rel" ] || fail "$m: $rel is not placed"
        if [ $mode = store ]; then
          case " ${toString cmpSkip} " in *" $rel "*) continue ;; esac
          cmp -s "$hf/$rel" "${stowSrc}/$p/$rel" || fail "$m: $rel differs from $p/$rel"
        else
          got=$(readlink "$(readlink "$hf/$rel")")
          [ "$got" = "${checkout}/$p/$rel" ] || fail "$m: $rel links to '$got', not ${checkout}/$p/$rel"
        fi
      done < ${configList}
      for s in ${lib.escapeShellArgs scriptNames}; do
        case "$(readlink -f "$hf/.local/bin/$s")" in
          ${builtins.storeDir}/*-highwind-scripts-*/bin/*) ;;
          *) fail "$m: .local/bin/$s does not resolve into the scripts package" ;;
        esac
      done
      for n in ${lib.escapeShellArgs nvimCopied}; do
        [ ! -e "$hf/$n" ] || fail "$m: $n is linked; it must be copied in as a writable file"
        grep -qF "$n" "$act/activate" || fail "$m: the activation script does not copy $n"
      done
      grep -qF 'highwind: herdr reloaded its config' "$act/activate" \
        || fail "$m: the activation has no herdr reload hook for ${herdrConfig}"
      grep -qxE "export HIGHWIND_DIR='?${expectedDir.${mode}}'?" "$hf/.local/bin/herdr-plugins" \
        || fail "$m: herdr-plugins does not set HIGHWIND_DIR=${expectedDir.${mode}}"
      echo "$m ($mode mode): $(wc -l < placed-$m) files placed, matching ${expect}"
    '';
in
pkgs.runCommand "check-link-modes" { } ''
  fail() { echo "link-modes: FAIL: $*" >&2; exit 1; }
  [ -s ${stowList} ] || fail "the Stow set is empty (no package directories found)"
  LC_ALL=C sort ${stowSet} > stow-set
  LC_ALL=C sort ${baseSet} > base-set

  # ── Profiles ───────────────────────────────────────────────────────────
  ${lib.optionalString (
    stalePersonal != [ ]
  ) ''fail "home-tree.nix names personal files that do not exist: ${toString stalePersonal}"''}
  [ "$(wc -l < base-set)" -lt "$(wc -l < stow-set)" ] || fail "no file is in the personal profile"
  # A comment may name a directory; a setting may not.
  while read -r f; do
    hits=$(sed -E '/^[[:space:]]*(#|--)/d' "${stowSrc}/$f" | grep -E ${lib.escapeShellArg tree.personal.pattern} || true)
    [ -z "$hits" ] || fail "$f is in the base profile but names the owner's directories (list it as personal in nix/packages/home-tree.nix): $hits"
  done < ${baseList}
  echo "profiles: $(( $(wc -l < stow-set) - $(wc -l < base-set) )) personal files; no base file names the owner's directories"

  # ── Placed sets ────────────────────────────────────────────────────────
  ${homeScript "store" { expect = "base-set"; }}
  ${homeScript "checkout" { expect = "base-set"; }}
  ${homeScript "personal" { expect = "stow-set"; }}
  ${homeScript "shell" {
    expect = "base-set";
    cmpSkip = [
      herdrConfig
      ghosttyConfig
    ];
  }}

  # ── Interactive shell ──────────────────────────────────────────────────
  # Each edited copy is its source plus the one appended setting, and still valid.
  hf=${homes.shell.config.home-files}
  check_appended() {
    src=$1 dst=$2 line=$3
    cmp -s -n "$(stat -c %s "$src")" "$src" "$dst" || fail "shell: $dst does not start with $src"
    tail -1 "$dst" | grep -qxF "$line" || fail "shell: $dst does not end with '$line': $(tail -3 "$dst")"
  }
  check_appended ${stowSrc}/herdr/${herdrConfig} "$hf/${herdrConfig}" 'default_shell = "${zsh}"'
  check_appended ${stowSrc}/ghostty/${ghosttyConfig} "$hf/${ghosttyConfig}" 'command = ${zsh}'
  export HOME=$TMPDIR/shell-home
  mkdir -p $HOME/.config/herdr
  cp "$hf/${herdrConfig}" $HOME/${herdrConfig}
  res=$(${pkgs.highwind.tools}/bin/herdr config check 2>&1) || fail "shell: herdr config check: $res"
  grep -q 'config: ok' <<<"$res" || fail "shell: herdr config check: $res"
  res=$(${ghostty}/bin/ghostty +validate-config --config-file="$hf/${ghosttyConfig}" 2>&1) \
    || fail "shell: ghostty +validate-config: $res"
  echo "shell: herdr's and Ghostty's configs start ${zsh} and stay valid"

  ${lib.boolToString (refuses "unset")} || fail "checkout mode with highwind.checkout unset evaluates"
  ${lib.boolToString (refuses "relative")} || fail "checkout mode with a relative highwind.checkout evaluates"
  ${lib.boolToString (refuses "shell")} || fail "checkout mode with highwind.interactiveShell evaluates"
  touch $out
''
