# The four herdr scripts, kept together in bin/ (herdr-recent finds herdr-summarize beside
# itself), with interpreters rewritten to store paths and their helper commands on a wrapped PATH.
# The PATH is prefixed, not replaced: herdr, claude and jj still come from the user's own PATH.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  python3,
  fzf,
  git,
  gh,
  jq,
  coreutils,
  gawk,
  gnused,
  diffutils,
  findutils,
  getent,
  bootstrap-dir,
  # The repo herdr-plugins reads bootstrap.sh from: a checkout, or bootstrap.sh alone.
  dotfilesDir ? bootstrap-dir,
}:
let
  scripts = [
    "herdr-summarize"
    "herdr-recent"
    "herdr-login-warning"
    "herdr-plugins"
  ];
  runtimePath = lib.makeBinPath (
    [
      python3
      fzf
      git
      gh
      jq
      coreutils
      gawk
      gnused
      diffutils
      findutils
    ]
    # herdr-plugins sync compares $HOME with the passwd home.
    ++ lib.optional stdenvNoCC.hostPlatform.isLinux getent
  );
in
stdenvNoCC.mkDerivation {
  pname = "dotfiles-scripts";
  version = "0";

  src = lib.fileset.toSource {
    root = ../../herdr/.local/bin;
    fileset = lib.fileset.unions (map (s: ../../herdr/.local/bin + "/${s}") scripts);
  };

  nativeBuildInputs = [ makeWrapper ];
  # patchShebangs resolves `#!/usr/bin/env bash` and `#!/bin/sh` against these.
  buildInputs = [
    bash
    python3
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    for s in ${lib.escapeShellArgs scripts}; do
      install -m755 "$s" "$out/bin/$s"
      # NixOS has no /usr/bin/python3; every use of it, shebang or not, becomes the store one,
      # and so does `/usr/bin/env python3` in a script's body.
      substituteInPlace "$out/bin/$s" \
        --replace-quiet "/usr/bin/env python3" ${python3}/bin/python3 \
        --replace-quiet /usr/bin/python3 ${python3}/bin/python3
    done
    runHook postInstall
  '';

  postFixup = ''
    for s in herdr-summarize herdr-recent herdr-login-warning; do
      wrapProgram "$out/bin/$s" --prefix PATH : ${runtimePath}
    done
    wrapProgram "$out/bin/herdr-plugins" --prefix PATH : ${runtimePath} \
      --set DOTFILES_DIR ${lib.escapeShellArg "${dotfilesDir}"}
    makeWrapper "$out/bin/.herdr-plugins-wrapped" "$out/bin/dotfiles-herdr-plugins-sync" \
      --prefix PATH : ${runtimePath} \
      --set DOTFILES_DIR ${lib.escapeShellArg "${dotfilesDir}"} --add-flags sync

    if grep -rlE '/usr/bin/(env )?python3' $out; then
      echo "a packaged script still calls /usr/bin/python3 or /usr/bin/env python3" >&2
      exit 1
    fi
  '';

  passthru = { inherit dotfilesDir; };

  meta = {
    description = "The dotfiles' herdr scripts with store interpreters";
    platforms = lib.platforms.unix;
  };
}
