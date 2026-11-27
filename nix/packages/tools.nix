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
    git
    gh
    python3
    # nvim-treesitter compiles parsers.
    stdenv.cc
    # herdr builds two of its plugins.
    go
    cargo
    # The base commands Oh My Zsh, its wd plugin, TPM and the tmux plugins run, so the set
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
  # vim-tmux-navigator's pane check in .tmux.conf runs ps; macOS has its own.
  ++ lib.optional stdenv.hostPlatform.isLinux procps
  # The release binary is Linux-only; the Darwin set waits for nixpkgs to carry 0.30.0.
  ++ lib.optional stdenv.hostPlatform.isLinux tuicr
  ++ lib.optional stdenv.hostPlatform.isLinux wl-clipboard;
  pathsToLink = [
    "/bin"
    "/share"
  ];
}
