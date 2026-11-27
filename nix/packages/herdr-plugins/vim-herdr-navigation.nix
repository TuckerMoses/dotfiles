# vim-herdr-navigation at its bootstrap.sh pin: shell and editor files, no build step. herdr runs
# `bash navigate.sh`, which needs jq and herdr on the server's PATH (both in tools).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  pluginHashes ? import ./hashes.nix,
}:
let
  s = import ./source.nix { inherit lib fetchFromGitHub pluginHashes; } "paulbkim-dev/vim-herdr-navigation";
in
stdenvNoCC.mkDerivation {
  pname = "herdr-plugin-vim-herdr-navigation";
  inherit (s) version src;
  dontConfigure = true;
  dontBuild = true;
  # The scripts run as `bash navigate.sh`; nothing to patch.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    cp -r . $out
    ${s.marker}
    runHook postInstall
  '';
  passthru = {
    pluginId = "vim-herdr-navigation";
    inherit (s) repo rev;
  };
  meta = {
    description = "herdr plugin: ctrl+h/j/k/l across herdr panes and Vim splits";
    homepage = "https://github.com/${s.repo}";
    platforms = lib.platforms.unix;
  };
}
