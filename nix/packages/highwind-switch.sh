# highwind-switch: build this user's standalone Home Manager configuration from the flake and
# activate it, as the user, without root. The system (safe-switch) is never involved.
# Packaged by highwind-switch.nix (writeShellApplication adds the strict mode and PATH).

usage() {
  cat <<'EOF'
Usage: highwind-switch [--flake DIR] [--config USER@HOST] [--dry-run | --rollback]
                       [--activation-package PATH]

Builds homeConfigurations."USER@HOST".activationPackage from the flake and activates it.
Programs that can reload do so through the activation's onChange hooks (herdr reloads its
config.toml when its server is running); others pick the change up when they next start.

  --flake DIR      The checkout to build from (default: $HIGHWIND_FLAKE, else ~/dotfiles).
  --config NAME    The configuration (default: <user>@<short hostname>, or <user>@mac on macOS).
  --dry-run        Build and print what would change; activate nothing.
  --rollback       Activate the previous Home Manager generation (each run goes one further
                   back, as home-manager switch --rollback does).
  --activation-package PATH
                   Use an activation package built elsewhere instead of building one, for
                   machines that cannot build (the vm-switch test uses this).
EOF
}

die() {
  echo "highwind-switch: $*" >&2
  exit 1
}

# The checkout keeps the directory name dotfiles on purpose: Claude Code keys its project memory
# and session history on that path.
flake=${HIGHWIND_FLAKE:-$HOME/dotfiles}
config=""
action=switch
gen=""
while (($#)); do
  case $1 in
    --flake) flake=${2:?--flake needs a directory}; shift 2 ;;
    --config) config=${2:?--config needs a name}; shift 2 ;;
    --dry-run) action=dry-run; shift ;;
    --rollback) action=rollback; shift ;;
    --activation-package) gen=${2:?--activation-package needs a path}; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
[[ $action != rollback || -z $gen ]] || die "--rollback takes no --activation-package"

# A shell that was already open when Nix was installed has no nix on PATH (the installer's hook
# runs when a shell starts). Fall back to where a multi-user install and the user profile put it.
if ! command -v nix > /dev/null 2>&1; then
  PATH="$PATH:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin"
fi
command -v nix > /dev/null 2>&1 || die "nix is not on PATH and not in /nix/var/nix/profiles/default/bin"

# Whatever the machine's nix.conf enables.
nixFlags=(--extra-experimental-features "nix-command flakes")
user=$(id -un)
# A Mac's network name follows its Sharing settings and the network it is on (a .local name,
# renumbered on a clash), so the flake calls every Mac "mac".
if [[ $(uname -s) == Darwin ]]; then host=mac; else host=$(uname -n); fi
config=${config:-$user@${host%%.*}}
state=${XDG_STATE_HOME:-$HOME/.local/state}
current=$(readlink -e "$state/home-manager/gcroots/current-home" || true)

# ── Profile ──────────────────────────────────────────────────────────────────
# Where Home Manager's own driver (home-manager switch) keeps the generations.
profiles_dir() {
  if [[ -d $state/nix/profiles ]]; then
    echo "$state/nix/profiles"
  elif [[ -d /nix/var/nix/profiles/per-user/$user ]]; then
    echo "/nix/var/nix/profiles/per-user/$user"
  else
    die "no Nix profile directory ($state/nix/profiles or /nix/var/nix/profiles/per-user/$user)"
  fi
}

# ── Rollback ─────────────────────────────────────────────────────────────────
if [[ $action == rollback ]]; then
  nix-env -q > /dev/null 2>&1 || true
  profile="$(profiles_dir)/home-manager"
  [[ -e $profile ]] || die "no Home Manager generation to roll back from ($profile)"
  nix-env --profile "$profile" --rollback
  exec "$profile/activate" --driver-version 1
fi

# ── Build ────────────────────────────────────────────────────────────────────
if [[ -z $gen ]]; then
  [[ -e $flake/flake.nix ]] || die "no flake.nix in $flake (use --flake DIR)"
  echo "highwind-switch: building $config from $flake" >&2
  gen=$(nix "${nixFlags[@]}" build --no-link --print-out-paths \
    "$flake#homeConfigurations.\"$config\".activationPackage") \
    || die "could not build homeConfigurations.\"$config\" from $flake"
fi
gen=$(readlink -e "$gen") || die "no such activation package: $gen"
[[ -x $gen/activate && -d $gen/home-files ]] || die "$gen is not a Home Manager activation package"

# ── Dry run ──────────────────────────────────────────────────────────────────
# Read-only: nothing is activated and no profile is touched.
if [[ $action == dry-run ]]; then
  echo "highwind-switch: built $gen"
  list() { (cd "$1" && find . \( -type f -o -type l \) -print | sed 's|^\./||' | LC_ALL=C sort); }
  if [[ -n $current ]]; then
    echo "Files, relative to $HOME (+ placed, - removed, ~ changed), against $current:"
    LC_ALL=C comm -3 <(list "$current/home-files") <(list "$gen/home-files") \
      | sed -e 's/^\t/+ /' -e 't' -e 's/^/- /'
    LC_ALL=C comm -12 <(list "$current/home-files") <(list "$gen/home-files") | while read -r f; do
      cmp -s "$current/home-files/$f" "$gen/home-files/$f" || echo "~ $f"
    done
    echo "Packages:"
    nix "${nixFlags[@]}" store diff-closures "$current" "$gen" || true
  else
    echo "No Home Manager generation yet. Files it would place, relative to $HOME:"
    list "$gen/home-files" | sed 's/^/+ /'
  fi
  # As Home Manager's checkLinkTargets: an existing path that is not a link into the current
  # generation stops the activation.
  echo "Collisions (existing paths that are not Home Manager links):"
  cur_files=""
  [[ -z $current ]] || cur_files=$(readlink -e "$current/home-files")
  n=0
  while read -r f; do
    t="$HOME/$f"
    [[ -e $t || -L $t ]] || continue
    if [[ -n $cur_files && -L $t && $(readlink "$t") == "$cur_files/"* ]]; then
      continue
    fi
    echo "  $f"
    n=$((n + 1))
  done < <(list "$gen/home-files")
  ((n == 0)) && echo "  none"
  exit 0
fi

# ── Switch ───────────────────────────────────────────────────────────────────
# As home-manager switch does it: record the generation, then activate it with driver
# version 1 (the activation then leaves the profile alone).
nix-env -q > /dev/null 2>&1 || true
profile="$(profiles_dir)/home-manager"
if [[ $gen != "$(readlink -e "$profile" || true)" ]]; then
  nix-env --profile "$profile" --set "$gen"
fi
exec "$gen/activate" --driver-version 1
