# The hashes the herdr plugin builds need, keyed by plugin and by the commit bootstrap.sh pins.
# bootstrap.sh stays the one place a pin is written; this file only holds what Nix cannot read
# from it. When a pin moves there, the build stops with a message naming this file until the
# entry is replaced. Printed by `nix run .#herdr-plugin-hashes` (see source.nix); the
# tool-versions check fails on an entry whose commit is not the current pin.
{
  "paulbkim-dev/vim-herdr-navigation"."7873100eb47212269005c693effb2a844986b30f" = {
    src = "sha256-clp3xPU7FfcfDookBI2SDSFQLygWke3gaG0RH2T7Jy0=";
  };
  "cloudmanic/herdr-plus"."f38df3570bea8f7ca71dc1ba11bce3b123d14402" = {
    src = "sha256-mveyFWjwkfhmj5z5Gyrkl+H29rpKJ54fKVHs3WuZ30Y=";
    vendorHash = "sha256-im2gPhLarMf1w/8rhxbOe9EhUdvseffukT9tqU4EEXI=";
  };
  "nathan-poncet/herdr-fingers"."2d9fc997ce1a95976b975da758dccc7b6e011336" = {
    src = "sha256-ZdBxL7KAsHOUNGIyJrM5e+j0c5/tZDRDdLvPAF8ad+Y=";
    cargoHash = "sha256-y9z5id48N2o2mRcq1LPUEh2nyrla7wf4CsBiAffwXF4=";
  };
}
