# The pinned source of one herdr plugin: its repo and commit from bootstrap.sh's
# `herdr plugin install <owner/repo> --ref <sha>` line, its hashes from ./hashes.nix (or the
# `pluginHashes` a caller passes, as herdr-plugin-hashes does), and the marker file herdr-plugins reads
# to tell which commit a linked plugin was built from.
{
  lib,
  fetchFromGitHub,
  pluginHashes ? import ./hashes.nix,
}:
repo:
let
  pins = (import ../../lib/bootstrap-data.nix { inherit lib; }).herdrPlugins;
  pin = lib.findFirst (p: p.repo == repo) (throw
    "herdr plugin ${repo}: bootstrap.sh has no `herdr plugin install ${repo} --ref <sha>` line"
  ) pins;
  rev = pin.rev;
  known = pluginHashes.${repo} or { };
  h =
    known.${rev} or (throw ''
      herdr plugin ${repo}: bootstrap.sh pins ${rev}, but nix/packages/herdr-plugins/hashes.nix has hashes for ${
        if known == { } then "no commit of it" else lib.concatStringsSep ", " (lib.attrNames known)
      }.
      Replace its entry there with one for ${rev}. In the checkout, on a machine with Nix and the
      network: nix run .#herdr-plugin-hashes > /tmp/hashes.nix && mv /tmp/hashes.nix nix/packages/herdr-plugins/hashes.nix'');
  parts = lib.splitString "/" repo;
in
{
  inherit repo rev;
  hashes = h;
  version = "0-unstable-${builtins.substring 0 7 rev}";
  src = fetchFromGitHub {
    owner = lib.elemAt parts 0;
    repo = lib.elemAt parts 1;
    inherit rev;
    hash = h.src;
  };
  # herdr records a linked plugin as `local`, with no commit; herdr-plugins status and check read
  # this file in its root instead.
  marker = ''
    echo ${lib.escapeShellArg "${repo} ${rev}"} > "$out/.highwind-pin"
  '';
}
