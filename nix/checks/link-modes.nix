# link-modes (docs/design/nix-dotfiles.md, section 7): the Home Manager module places exactly the
# Stow set, in both link modes, for a test user.
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

  # ── Placed set ───────────────────────────────────────────────────────────
  mkHome =
    extra:
    home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [
        homeModule
        {
          home.username = "test";
          home.homeDirectory = "/home/test";
          home.stateVersion = "26.05";
          dotfiles.enable = true;
        }
        extra
      ];
    };
  checkout = "/test/checkout";
  homes = {
    store = mkHome { dotfiles.linkMode = "store"; };
    checkout = mkHome {
      dotfiles.linkMode = "checkout";
      dotfiles.checkout = checkout;
    };
  };
  excluded =
    t:
    t == ".oh-my-zsh"
    || lib.hasPrefix ".tmux/plugins/" t
    || lib.hasPrefix ".local/share/dotfiles/" t
    || lib.elem t data.homeManagerTargets;
  placed =
    h: lib.filter (t: !excluded t) (map (f: f.target) (lib.attrValues h.config.home.file)) ++ nvimCopied;

  # Checkout mode without an absolute checkout must not build.
  refuses = extra: !(builtins.tryEval homesBad.${extra}.activationPackage.drvPath).success;
  homesBad = {
    unset = mkHome { dotfiles.linkMode = "checkout"; };
    relative = mkHome {
      dotfiles.linkMode = "checkout";
      dotfiles.checkout = "test/checkout";
    };
  };

  lines = l: pkgs.writeText "lines" (lib.concatLines l);
  stowList = lines (map (f: "${f.pkg}/${f.rel}") stowFiles);
  stowSet = lines (map (f: f.rel) stowFiles);
  configList = lines (map (f: "${f.pkg} ${f.rel}") configFiles);
  stowSrc = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions (map (p: root + "/${p}") stowPackages);
  };
  expectedDir = {
    store = "${pkgs.dotfiles.bootstrap-dir}";
    inherit checkout;
  };

  modeScript = mode: ''
    m=${mode}
    hf=${homes.${mode}.config.home-files}
    act=${homes.${mode}.activationPackage}
    LC_ALL=C sort ${lines (placed homes.${mode})} > placed-$m
    diff -u stow-set placed-$m > diff-$m || {
      cat diff-$m >&2
      fail "$m mode: the placed set differs from the Stow set (- only in Stow, + only placed)"
    }
    while read -r p rel; do
      [ -e "$hf/$rel" ] || [ -L "$hf/$rel" ] || fail "$m mode: $rel is not placed"
      if [ $m = store ]; then
        cmp -s "$hf/$rel" "${stowSrc}/$p/$rel" || fail "store mode: $rel differs from $p/$rel"
      else
        got=$(readlink "$(readlink "$hf/$rel")")
        [ "$got" = "${checkout}/$p/$rel" ] || fail "checkout mode: $rel links to '$got', not ${checkout}/$p/$rel"
      fi
    done < ${configList}
    for s in ${lib.escapeShellArgs scriptNames}; do
      case "$(readlink -f "$hf/.local/bin/$s")" in
        ${builtins.storeDir}/*-dotfiles-scripts-*/bin/*) ;;
        *) fail "$m mode: .local/bin/$s does not resolve into the scripts package" ;;
      esac
    done
    for n in ${lib.escapeShellArgs nvimCopied}; do
      [ ! -e "$hf/$n" ] || fail "$m mode: $n is linked; it must be copied in as a writable file"
      grep -qF "$n" "$act/activate" || fail "$m mode: the activation script does not copy $n"
    done
    grep -qxE "export DOTFILES_DIR='?${expectedDir.${mode}}'?" "$hf/.local/bin/herdr-plugins" \
      || fail "$m mode: herdr-plugins does not set DOTFILES_DIR=${expectedDir.${mode}}"
    echo "$m mode: $(wc -l < placed-$m) files placed, matching the Stow set"
  '';
in
pkgs.runCommand "check-link-modes" { } ''
  fail() { echo "link-modes: FAIL: $*" >&2; exit 1; }
  [ -s ${stowList} ] || fail "the Stow set is empty (no package directories found)"
  LC_ALL=C sort ${stowSet} > stow-set
  ${modeScript "store"}
  ${modeScript "checkout"}
  ${lib.boolToString (refuses "unset")} || fail "checkout mode with dotfiles.checkout unset evaluates"
  ${lib.boolToString (refuses "relative")} || fail "checkout mode with a relative dotfiles.checkout evaluates"
  touch $out
''
