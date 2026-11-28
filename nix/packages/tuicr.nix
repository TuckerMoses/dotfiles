# tuicr from its static musl release: nixpkgs carries 0.29.0, below the 0.30.0 the repo needs.
# The version and checksums are the ones bootstrap.sh pins; the tool-versions check compares them.
{
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.30.0";
  sha256 = {
    x86_64-linux = "bbd7a358c8450613177359bfbcc4bdbba68c98835311c5e424053a005610c9d2";
    aarch64-linux = "01ad73bfbfe957709c4e8d834d988f903159b94e0597cd14758110a0e3e89127";
  };
  system = stdenvNoCC.hostPlatform.system;
  # bootstrap.sh names the tarball after `uname -m`: x86_64 or aarch64.
  arch = stdenvNoCC.hostPlatform.parsed.cpu.name;
in
stdenvNoCC.mkDerivation {
  pname = "tuicr";
  inherit version;

  src = fetchurl {
    url = "https://github.com/agavra/tuicr/releases/download/v${version}/tuicr-${version}-${arch}-unknown-linux-musl.tar.gz";
    sha256 = sha256.${system} or (throw "tuicr: no release binary pinned for ${system}");
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # A static binary: nothing to patch.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 tuicr $out/bin/tuicr
    runHook postInstall
  '';

  passthru = { inherit sha256; };

  meta = {
    description = "Terminal diff review for git and jj";
    homepage = "https://github.com/agavra/tuicr";
    platforms = builtins.attrNames sha256;
    mainProgram = "tuicr";
  };
}
