# Turns the highwind Home Manager module on for the users a host names
# (docs/design/nix-dotfiles.md, section 5). Empty by default: a host that names no user gets
# nothing from this file.
{
  config,
  lib,
  inputs,
  ...
}:
let
  users = config.highwind.users;
in
{
  # imports cannot depend on config, so the Home Manager NixOS module is always imported; with
  # no users it adds nothing to the system.
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  options.highwind.users = lib.mkOption {
    default = { };
    description = "Users whose home Home Manager fills with highwind's configs and tools.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          linkMode = lib.mkOption {
            type = lib.types.enum [
              "store"
              "checkout"
            ];
            default = "store";
            description = "See the Home Manager module's highwind.linkMode.";
          };
          checkout = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Absolute path of a checkout of this repo; required in checkout mode.";
          };
        };
      }
    );
  };

  config = lib.mkIf (users != { }) {
    home-manager.useGlobalPkgs = true;
    home-manager.users = lib.mapAttrs (_: u: {
      imports = [ inputs.self.homeManagerModules.default ];
      highwind = {
        enable = true;
        inherit (u) linkMode checkout;
      };
      home.stateVersion = "26.05";
    }) users;
  };
}
