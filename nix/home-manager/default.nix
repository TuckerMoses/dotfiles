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
  inProfile = f: f.profile == "base" || cfg.profiles.personal.enable;
  configFiles = lib.filter (f: inProfile f && !(lib.elem f.rel nvimCopied)) d.home-tree.files;

  # ── Interactive shell ──────────────────────────────────────────────────────
  # herdr starts new panes with [terminal] default_shell, else $SHELL; Ghostty starts
  # `command`, else the login shell. Store mode places copies of their configs with one setting
  # appended, so the login shell (and so SSH) can stay another shell. The repo files, which Stow
  # links on machines whose login shell is zsh already, are unchanged.
  herdrConfig = ".config/herdr/config.toml";
  ghosttyConfig = ".config/ghostty/config";
  shellPath = lib.getExe cfg.interactiveShell;
  withShell =
    rel:
    pkgs.runCommand "dotfiles-${baseNameOf rel}-shell" { } (
      if rel == herdrConfig then
        ''
          # A second [terminal] table would make the file invalid TOML.
          if grep -q '^[[:space:]]*\[terminal\]' ${d.home-tree}/${rel}; then
            echo "${rel} has a [terminal] table; set default_shell there instead" >&2; exit 1
          fi
          { cat ${d.home-tree}/${rel}; printf '\n# dotfiles.interactiveShell\n[terminal]\ndefault_shell = "%s"\n' ${shellPath}; } > $out
        ''
      else
        ''
          if grep -q '^[[:space:]]*command[[:space:]]*=' ${d.home-tree}/${rel}; then
            echo "${rel} sets command already" >&2; exit 1
          fi
          { cat ${d.home-tree}/${rel}; printf '\n# dotfiles.interactiveShell\ncommand = %s\n' ${shellPath}; } > $out
        ''
    );
  configSource =
    f:
    if checkoutMode then
      config.lib.file.mkOutOfStoreSymlink "${cfg.checkout}/${f.pkg}/${f.rel}"
    else if cfg.interactiveShell != null && lib.elem f.rel [ herdrConfig ghosttyConfig ] then
      "${withShell f.rel}"
    else
      "${d.home-tree}/${f.rel}";

  # ── Reloads ────────────────────────────────────────────────────────────────
  # Runs after the new files are linked, when herdr's config.toml changed. herdr reads the
  # other files under its config (herdr-plus's) fresh each time, so they need nothing. A
  # failure warns and never fails the activation.
  herdr = "${d.tools}/bin/herdr";
  herdrReload = ''
    dotfilesHerdr=$(${herdr} status server 2>/dev/null || true)
    if grep -qx 'status: running' <<<"$dotfilesHerdr"; then
      if dotfilesHerdr=$(${pkgs.coreutils}/bin/timeout 20 ${herdr} server reload-config 2>&1) \
        && [[ $dotfilesHerdr == *'"status":"applied"'* ]]; then
        echo "dotfiles: herdr reloaded its config"
      else
        echo "dotfiles: herdr server reload-config did not apply; reload by hand (prefix+shift+r): $dotfilesHerdr" >&2
      fi
    else
      echo "dotfiles: no herdr server running; nothing to reload"
    fi
  '';
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
    profiles.personal.enable = lib.mkEnableOption ''
      the files that name the owner's own directories and repos (herdr-plus projects and
      worktree layouts, the validate-dotfiles quick action). Off, only the portable base is placed
    '';
    interactiveShell = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.zsh";
      description = ''
        The shell herdr panes and Ghostty windows start, when it is not the login shell. null
        leaves both to their defaults (the login shell). Store mode only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !checkoutMode || (cfg.checkout != null && lib.hasPrefix "/" cfg.checkout);
        message = ''dotfiles.linkMode = "checkout" needs dotfiles.checkout set to an absolute path.'';
      }
      {
        assertion = !checkoutMode || cfg.interactiveShell == null;
        message = ''dotfiles.interactiveShell needs dotfiles.linkMode = "store": it places edited copies of herdr's and Ghostty's configs.'';
      }
    ];

    home.packages = [
      d.tools
      scripts
      d.dotfiles-switch
      pkgs.nerd-fonts.jetbrains-mono
    ];
    fonts.fontconfig.enable = true;

    # One link per file, so ~/.config/herdr and ~/.config/nvim stay real,
    # writable directories; only the store bundles are linked as directories.
    home.file =
      lib.listToAttrs (
        map (
          f:
          lib.nameValuePair f.rel (
            { source = configSource f; } // lib.optionalAttrs (f.rel == herdrConfig) { onChange = herdrReload; }
          )
        ) configFiles
      )
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
