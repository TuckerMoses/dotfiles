# herdr-plus at its bootstrap.sh pin. Its [[build]] step (scripts/build.sh) is `go build -o
# bin/herdr-plus .`, which this does with the modules fixed by vendorHash; the output is the
# repo with that binary in bin/, as herdr's own install leaves it.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  pluginHashes ? import ./hashes.nix,
}:
let
  s = import ./source.nix { inherit lib fetchFromGitHub pluginHashes; } "cloudmanic/herdr-plus";
in
buildGoModule {
  pname = "herdr-plugin-herdr-plus";
  inherit (s) version src;
  inherit (s.hashes) vendorHash;
  subPackages = [ "." ];
  # Its tests start herdr and git; the plugin checks run the built binary instead.
  doCheck = false;
  # A copy of the repo as herdr would hold it; herdr runs the binaries, not these scripts.
  dontPatchShebangs = true;
  postInstall = ''
    cp -r $src/. $out/
    chmod -R u+w $out
    ${s.marker}
  '';
  passthru = {
    pluginId = "cloudmanic.herdr-plus";
    inherit (s) repo rev;
  };
  meta = {
    description = "herdr plugin: project templates, worktree layouts and quick actions";
    homepage = "https://github.com/${s.repo}";
    platforms = lib.platforms.unix;
    mainProgram = "herdr-plus";
  };
}
