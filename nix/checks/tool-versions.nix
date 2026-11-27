# tool-versions (docs/design/nix-dotfiles.md, section 7): the tools are at or above the floors the
# repo depends on, the tuicr package pins the release bootstrap.sh pins, by its own literals, and
# the herdr plugin packages build the commits bootstrap.sh pins, with a hashes.nix entry for
# exactly those commits.
{ pkgs, nixpkgs }:
let
  lib = pkgs.lib;
  d = pkgs.dotfiles;
  root = ../..;
  data = import ../lib/bootstrap-data.nix { inherit lib; };

  # Section 4's floors. Each is run from the tools environment, the one users get.
  floors = {
    herdr = "0.9.0";
    jj = "0.47.1";
    nvim = "0.11";
    fzf = "0.67";
  }
  # The Darwin tools have no tuicr (nix/packages/tools.nix).
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { tuicr = "0.30.0"; };

  # The tuicr package as each Linux system builds it, evaluated only: its version and the
  # sha256 its fetchurl checks, normalised so hex and SRI compare equal.
  tuicrFor = system: nixpkgs.legacyPackages.${system}.callPackage ../packages/tuicr.nix { };
  hex =
    h:
    builtins.convertHash {
      hash = h;
      hashAlgo = "sha256";
      toHashFormat = "base16";
    };
  tuicrRows = lib.mapAttrsToList (system: want: {
    inherit system want;
    got = hex (tuicrFor system).src.outputHash;
    version = (tuicrFor system).version;
  }) data.tuicr.sha256;

  # ── herdr plugins ────────────────────────────────────────────────────────
  # What each package builds, against bootstrap.sh's pins as herdr-plugins reads them. hashes.nix
  # may hold only the pinned commits: an entry left for an old pin is a hash nothing checks.
  pluginPkgs = lib.attrValues d.herdr-plugins.plugins;
  pluginHashes = import ../packages/herdr-plugins/hashes.nix;
  pluginRows = map (pin: {
    inherit (pin) repo rev;
    built = map (p: p.rev) (lib.filter (p: p.repo == pin.repo) pluginPkgs);
    srcRev = map (p: p.src.rev) (lib.filter (p: p.repo == pin.repo) pluginPkgs);
    keys = lib.attrNames (pluginHashes.${pin.repo} or { });
  }) data.herdrPlugins;
  strayRepos = lib.subtractLists (map (p: p.repo) data.herdrPlugins) (lib.attrNames pluginHashes);

  # The Nix side minus the checks: none of it may read bootstrap-data.nix, except the herdr
  # plugin sources, which take their pins from bootstrap.sh by design (bootstrap.sh is where a pin
  # is written; the tuicr package instead hard-codes its pins and this check compares them).
  nixSide = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.difference (lib.fileset.unions [
      (root + "/flake.nix")
      (root + "/nix")
      (root + "/nixos")
    ]) (lib.fileset.unions [
      (root + "/nix/checks")
      (root + "/nix/tests")
      (root + "/nix/lib/bootstrap-data.nix")
      (root + "/nix/packages/herdr-plugins/source.nix")
    ]);
  };
in
pkgs.runCommand "check-tool-versions" { } ''
  fail() { echo "tool-versions: FAIL: $*" >&2; exit 1; }
  export PATH=${lib.makeBinPath [ d.tools ]}
  export HOME=$TMPDIR

  # ── Floors ───────────────────────────────────────────────────────────────
  ${lib.concatStrings (
    lib.mapAttrsToList (cmd: floor: ''
      v=$(${cmd} --version 2>&1) || fail "${cmd} --version exited non-zero: $v"
      got=$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$v" | head -1)
      [ -n "$got" ] || fail "${cmd} --version printed no version: $v"
      low=$(printf '%s\n' "${floor}" "$got" | sort -V | head -1)
      [ "$low" = "${floor}" ] || fail "${cmd} is $got, below the floor ${floor}"
      echo "${cmd}: $got (floor ${floor})"
    '') floors
  )}

  # ── tuicr against bootstrap.sh ───────────────────────────────────────────
  [ "${d.tuicr.version}" = "${data.tuicr.version}" ] \
    || fail "tuicr package is ${d.tuicr.version}, bootstrap.sh pins ${data.tuicr.version}"
  ${lib.concatMapStrings (r: ''
    [ "${r.version}" = "${data.tuicr.version}" ] \
      || fail "tuicr for ${r.system} is ${r.version}, bootstrap.sh pins ${data.tuicr.version}"
    [ "${r.got}" = "${r.want}" ] \
      || fail "tuicr for ${r.system}: fetchurl checks sha256 ${r.got}, bootstrap.sh pins ${r.want}"
    echo "tuicr ${r.system}: ${r.version}, sha256 ${r.got} as bootstrap.sh pins"
  '') tuicrRows}

  # The package states its own pins; bootstrap-data.nix is the checks' reader of bootstrap.sh.
  f=${../packages/tuicr.nix}
  grep -qF 'version = "${data.tuicr.version}";' $f || fail "nix/packages/tuicr.nix does not hard-code version = \"${data.tuicr.version}\""
  ${lib.concatMapStrings (s: ''
    grep -qF '"${s}"' $f || fail "nix/packages/tuicr.nix does not hard-code the sha256 ${s}"
  '') (lib.attrValues data.tuicr.sha256)}
  hits=$(grep -rln 'bootstrap-data' ${nixSide} || true)
  [ -z "$hits" ] || fail "bootstrap-data.nix is read outside the checks: $hits"
  echo "tuicr: nix/packages/tuicr.nix hard-codes its pins; only the checks and the herdr plugin sources read bootstrap-data.nix"

  # ── herdr plugins against bootstrap.sh ───────────────────────────────────
  [ ${toString (lib.length pluginPkgs)} = ${toString (lib.length data.herdrPlugins)} ] \
    || fail "${toString (lib.length pluginPkgs)} herdr plugin packages, but bootstrap.sh pins ${toString (lib.length data.herdrPlugins)} plugins"
  ${lib.concatMapStrings (r: ''
    [ "${toString r.built}" = "${r.rev}" ] && [ "${toString r.srcRev}" = "${r.rev}" ] \
      || fail "herdr plugin ${r.repo}: the package builds '${toString r.built}' (source '${toString r.srcRev}'), bootstrap.sh pins ${r.rev}"
    [ "${toString r.keys}" = "${r.rev}" ] \
      || fail "herdr plugin ${r.repo}: nix/packages/herdr-plugins/hashes.nix has entries for '${toString r.keys}', bootstrap.sh pins ${r.rev} (exactly that one)"
    echo "herdr plugin ${r.repo}: builds ${r.rev} as bootstrap.sh pins; hashes.nix keyed by it"
  '') pluginRows}
  [ -z "${toString strayRepos}" ] \
    || fail "nix/packages/herdr-plugins/hashes.nix has entries for plugins bootstrap.sh does not pin: ${toString strayRepos}"
  touch $out
''
