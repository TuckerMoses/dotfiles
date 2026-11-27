# Every program the configs call, as one environment. herdr and jujutsu come from
# nixpkgs-unstable and tuicr from its release binary (see nix/overlay.nix); the rest from 26.05.
{
  lib,
  stdenv,
  buildEnv,
  zsh,
  tmux,
  neovim,
  starship,
  fzf,
  zoxide,
  atuin,
  jq,
  lazygit,
  lazyjj,
  jujutsu,
  tuicr,
  herdr,
  git,
  gh,
  python3,
  go,
  cargo,
  bashInteractive,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  getopt,
  less,
  procps,
  wl-clipboard,
  # true: the set works with nothing else on PATH (the checks, the sandboxes, Linux homes).
  # false: leaves out the compilers, git, python3 and the base commands, for a macOS home, where
  # Xcode's cc and git, rustup's cargo, a venv's python3 and the BSD commands are the user's own
  # and must not be shadowed (the Home Manager module sets it there).
  standalone ? true,
}:
buildEnv {
  name = "dotfiles-tools";
  paths = [
    zsh
    tmux
    neovim
    starship
    fzf
    zoxide
    atuin
    jq
    lazygit
    lazyjj
    jujutsu
    herdr
  ]
  ++ lib.optional standalone git
  ++ [ gh ]
  ++ lib.optionals standalone [
    python3
    # nvim-treesitter compiles parsers.
    stdenv.cc
    # herdr builds two of its plugins.
    go
    cargo
    # The base commands Oh My Zsh and its wd plugin run, so the set
    # works with nothing else on PATH (as in the sandbox).
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    getopt
    less
  ]
  # validate.sh's running-process checks run ps and pgrep; macOS has its own.
  ++ lib.optional stdenv.hostPlatform.isLinux procps
  # The release binary is Linux-only and nixpkgs' tuicr (0.29.0 in unstable) is below the floor,
  # so the Mac keeps Homebrew's until nixpkgs carries 0.30.0.
  ++ lib.optional stdenv.hostPlatform.isLinux tuicr
  ++ lib.optional stdenv.hostPlatform.isLinux wl-clipboard;
  pathsToLink = [
    "/bin"
    "/share"
  ];
}
