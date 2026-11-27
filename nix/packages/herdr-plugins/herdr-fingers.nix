# herdr-fingers (trial) at its bootstrap.sh pin. Its [[build]] step is `cargo build --release
# --locked`, and its manifest runs ./target/release/herdr-fingers, so the binary is put there,
# in a copy of the repo, as herdr's own install leaves it.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pluginHashes ? import ./hashes.nix,
}:
let
  s = import ./source.nix { inherit lib fetchFromGitHub pluginHashes; } "nathan-poncet/herdr-fingers";
in
rustPlatform.buildRustPackage {
  pname = "herdr-plugin-herdr-fingers";
  inherit (s) version src;
  inherit (s.hashes) cargoHash;
  # Its tests run against a herdr and a terminal; the plugin checks run the built binary instead.
  doCheck = false;
  # A copy of the repo as herdr would hold it; herdr runs the binaries, not these scripts.
  dontPatchShebangs = true;
  postInstall = ''
    mkdir -p $out/target/release
    mv $out/bin/herdr-fingers $out/target/release/herdr-fingers
    rmdir $out/bin
    cp -r $src/. $out/
    chmod -R u+w $out
    ${s.marker}
  '';
  passthru = {
    pluginId = "nathan-poncet.herdr-fingers";
    inherit (s) repo rev;
  };
  meta = {
    description = "herdr plugin (trial): hint-copy paths, SHAs and URLs from the focused pane";
    homepage = "https://github.com/${s.repo}";
    platforms = lib.platforms.unix;
  };
}
