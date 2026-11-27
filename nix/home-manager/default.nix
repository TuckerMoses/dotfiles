# Places the dotfiles and their tools for one user (docs/design/nix-dotfiles.md, section 5).
#
# Takes the flake's self: packages come from self.packages, never from an overlay set here,
# which errors under home-manager.useGlobalPkgs.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;
  d = self.packages.${pkgs.stdenv.hostPlatform.system};
  checkoutMode = cfg.linkMode == "checkout";

  # herdr-plugins reads its pins from the checkout, or from bootstrap.sh alone in store mode
  # (where `update` refuses, as it does in a worktree).
  scripts = if checkoutMode then d.scripts.override { dotfilesDir = cfg.checkout; } else d.scripts;
  scriptNames = [
    "herdr-summarize"
    "herdr-recent"
    "herdr-login-warning"
    "herdr-plugins"
  ];

  # lazy.nvim and LazyVim rewrite these, so they are copied in by the activation step below.
  nvimCopied = [
    ".config/nvim/lazy-lock.json"
    ".config/nvim/lazyvim.json"
  ];
  configFiles = lib.filter (f: !(lib.elem f.rel nvimCopied)) d.home-tree.files;
  configSource =
    f:
    if checkoutMode then
      config.lib.file.mkOutOfStoreSymlink "${cfg.checkout}/${f.pkg}/${f.rel}"
    else
      "${d.home-tree}/${f.rel}";
in
{
  options.dotfiles = {
    enable = lib.mkEnableOption "the dotfiles' configs and tools";
    linkMode = lib.mkOption {
      type = lib.types.enum [
        "store"
        "checkout"
      ];
      default = "store";
      description = ''
        "store": configs are linked from the build, so editing one means rebuilding.
        "checkout": configs are linked into dotfiles.checkout, so edits there are live at once,
        as with Stow.
      '';
    };
    checkout = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/alice/dotfiles";
      description = "Absolute path of a git checkout of this repo. Required in checkout mode.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !checkoutMode || (cfg.checkout != null && lib.hasPrefix "/" cfg.checkout);
        message = ''dotfiles.linkMode = "checkout" needs dotfiles.checkout set to an absolute path.'';
      }
    ];

    home.packages = [
      d.tools
      scripts
      pkgs.nerd-fonts.jetbrains-mono
    ];
    fonts.fontconfig.enable = true;

    # One link per file, so ~/.config/herdr and ~/.config/nvim stay real,
    # writable directories; only the store bundles are linked as directories.
    home.file =
      lib.listToAttrs (map (f: lib.nameValuePair f.rel { source = configSource f; }) configFiles)
      # herdr/config.toml calls the scripts by this path.
      // lib.listToAttrs (
        map (s: lib.nameValuePair ".local/bin/${s}" { source = "${scripts}/bin/${s}"; }) scriptNames
      )
      // {
        ".oh-my-zsh".source = d.oh-my-zsh-bundle;
        # A path that stays the same across rebuilds; linking it into herdr stays manual.
        ".local/share/dotfiles/herdr-summarizer-plugin".source = d.summarizer-plugin;
      };

    # The repo's pins win on each activation, and the files stay writable.
    home.activation.dotfilesNvimFiles = lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.concatMapStrings (rel: ''
        run rm -f $VERBOSE_ARG ${lib.escapeShellArg "${config.home.homeDirectory}/${rel}"}
        run install -D -m 644 $VERBOSE_ARG ${lib.escapeShellArg "${d.home-tree}/${rel}"} \
          ${lib.escapeShellArg "${config.home.homeDirectory}/${rel}"}
      '') nvimCopied
    );
  };
}
