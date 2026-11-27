# herdr-plugin-hashes: print nix/packages/herdr-plugins/hashes.nix for the pins in bootstrap.sh.
# Run it in a checkout of this repo, on a machine with Nix and the network, after a pin moved:
#   nix run .#herdr-plugin-hashes > /tmp/hashes.nix && mv /tmp/hashes.nix nix/packages/herdr-plugins/hashes.nix
# It reads the pins with herdr-plugins' own pattern, takes each source hash from `nix flake
# prefetch`, and gets a Go or Rust dependency hash by building the plugin with that hash empty
# (Nix then prints the right one). It changes no file. Packaged in nix/overlay.nix
# (writeShellApplication adds the strict mode and PATH).

flake=$(pwd -P)
[[ -f $flake/bootstrap.sh && -f $flake/nix/packages/herdr-plugins/hashes.nix ]] \
  || { echo "herdr-plugin-hashes: run it at the top of the dotfiles checkout" >&2; exit 2; }
nixFlags=(--extra-experimental-features "nix-command flakes")
system=$(nix "${nixFlags[@]}" eval --impure --raw --expr builtins.currentSystem)
pins=$(sed -n 's/^[[:space:]]*herdr plugin install \([^ ]*\) --ref \([0-9a-f]\{7,40\}\).*/\1 \2/p' "$flake/bootstrap.sh")
[[ -n $pins ]] || { echo "herdr-plugin-hashes: no pinned herdr plugin install line in bootstrap.sh" >&2; exit 1; }

cat <<'EOF'
# The hashes the herdr plugin builds need, keyed by plugin and by the commit bootstrap.sh pins.
# bootstrap.sh stays the one place a pin is written; this file only holds what Nix cannot read
# from it. When a pin moves there, the build stops with a message naming this file until the
# entry is replaced. Printed by `nix run .#herdr-plugin-hashes` (see source.nix); the
# tool-versions check fails on an entry whose commit is not the current pin.
EOF
echo "{"
while read -r repo rev <&3; do
  echo "herdr-plugin-hashes: $repo at $rev" >&2
  src=$(nix "${nixFlags[@]}" flake prefetch --json "github:$repo/$rev" | jq -r .hash)
  [[ $src == sha256-* ]] || { echo "herdr-plugin-hashes: could not fetch github:$repo/$rev" >&2; exit 1; }
  echo "  \"$repo\".\"$rev\" = {"
  echo "    src = \"$src\";"
  # The package is herdr-plugin-<repo name>. Both dependency hashes are given empty: a Go
  # plugin reads only vendorHash, a Rust one only cargoHash, and a plain copy neither.
  attr="herdr-plugin-${repo#*/}"
  expr="(builtins.getFlake \"git+file://$flake\").packages.$system.$attr.override {
    pluginHashes = { \"$repo\".\"$rev\" = { src = \"$src\"; vendorHash = \"\"; cargoHash = \"\"; }; };
  }"
  if out=$(nix "${nixFlags[@]}" build --no-link --impure --expr "$expr" 2>&1); then
    : # no dependency hash: the build needs none
  else
    got=$(sed -n 's/^[[:space:]]*got:[[:space:]]*//p' <<<"$out" | tail -1)
    if [[ $got != sha256-* ]]; then
      echo "herdr-plugin-hashes: building $attr failed without printing a hash:" >&2
      tail -20 <<<"$out" >&2
      exit 1
    fi
    # buildGoModule fetches into a *-go-modules derivation; anything else here is cargo's.
    if grep -q -- '-go-modules' <<<"$out"; then dep=vendorHash; else dep=cargoHash; fi
    echo "    $dep = \"$got\";"
  fi
  echo "  };"
done 3<<<"$pins"
echo "}"
