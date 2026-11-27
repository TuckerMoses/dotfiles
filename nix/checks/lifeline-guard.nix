# lifeline-guard (docs/design/nix-dotfiles.md, section 7): pure evaluation, no VM. Each config
# change the `guard` drill in nixos/test/drills.sh expects the lockout guard to refuse fails one
# of nixos/modules/lifeline.nix's assertions; the unmodified test host fails none.
{
  pkgs,
  self,
  system,
}:
let
  lib = pkgs.lib;
  # The test guest of this system; it runs the same modules as homepc.
  host = self.nixosConfigurations."vm-${lib.head (lib.splitString "-" system)}";

  # The drill's nine cases, as written there.
  cases = {
    "SSH disabled" = {
      services.openssh.enable = lib.mkForce false;
    };
    "SSH port closed in the firewall" = {
      services.openssh.openFirewall = lib.mkForce false;
    };
    "SSH port moved" = {
      services.openssh.ports = lib.mkForce [ 2022 ];
    };
    "Tailscale disabled" = {
      services.tailscale.enable = lib.mkForce false;
    };
    "no authorized keys" = {
      lifeline.authorizedKeys = lib.mkForce [ ];
    };
    "sudo asks for a password" = {
      security.sudo.wheelNeedsPassword = lib.mkForce true;
    };
    "suspend re-enabled" = {
      systemd.targets.suspend.enable = lib.mkForce true;
    };
    "automatic upgrades on" = {
      system.autoUpgrade.enable = lib.mkForce true;
    };
    "NetworkManager disabled" = {
      networking.networkmanager.enable = lib.mkForce false;
    };
  };

  failing = cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.config.assertions);
  guardFailures = cfg: lib.filter (lib.hasPrefix "lifeline:") (failing cfg);

  rows = lib.mapAttrsToList (name: change: {
    inherit name;
    refused = guardFailures (host.extendModules { modules = [ change ]; });
  }) cases;
  baseline = failing host;
in
pkgs.runCommand "check-lifeline-guard" { } ''
  fail() { echo "lifeline-guard: FAIL: $*" >&2; exit 1; }
  ${lib.optionalString (baseline != [ ]) ''
    fail ${lib.escapeShellArg "the unmodified ${host.config.networking.hostName} fails assertions: ${lib.concatStringsSep "; " baseline}"}
  ''}
  echo "unmodified host: no failing assertion"
  ${lib.concatMapStrings (r: ''
    ${
      if r.refused == [ ] then
        "fail ${lib.escapeShellArg "${r.name}: no lifeline assertion fails, so the guard would let this build through"}"
      else
        "echo ${lib.escapeShellArg "refused: ${r.name} (${lib.concatStringsSep "; " r.refused})"}"
    }
  '') rows}
  echo "lifeline-guard: all ${toString (lib.length rows)} drill cases refused"
  touch $out
''
