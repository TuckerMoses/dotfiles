# The home directory of `user` on `system`, built from the name (macOS keeps homes under /Users,
# Linux under /home), so no file under nix/ names one literally.
{ lib }:
system: user:
(if lib.hasSuffix "-darwin" system then "/Users" else "/home") + "/${user}"
