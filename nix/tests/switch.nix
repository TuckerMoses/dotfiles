# vm-switch (docs/design/nix-dotfiles.md, section 14): a user whose environment is a standalone
# Home Manager configuration, activated by that user with highwind-switch and no root, while the
# login shell stays bash. Generation A is homeConfigurations."test@vm"; B differs in .zshrc and
# one herdr config line. The test switches to A, then to B with a herdr server running (the
# onChange hook reloads it), reboots (B stays: nothing re-activates a user environment at boot),
# and rolls back to A with no server running. SSH logins land in bash throughout. A links herdr's
# three plugins from the build (the guest has no network to fetch them); B, with the same
# plugin builds, links nothing again. Last, it switches to an environment laid out as before the
# rename to highwind (genOld) and back to A, the move every machine activated before 2026-11-28
# makes once.
#
# The guest has no network, so nothing is built in it: the generations are built with the test
# and handed to highwind-switch with --activation-package.
{
  self,
  inputs,
  pkgs,
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  keys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
  mkHome = import ../lib/home-configuration.nix { inherit self inputs; };
  switch = "${self.packages.${system}.highwind-switch}/bin/highwind-switch";
  pluginIds = lib.attrNames self.packages.${system}.herdr-plugins.plugins;

  homeA = self.homeConfigurations."test@vm";
  genA = homeA.activationPackage;
  # A's placed file with one line appended.
  appended =
    rel: line:
    pkgs.runCommand "gen-b-${baseNameOf rel}" { } ''
      { cat ${homeA.config.home-files}/${rel}; echo ${lib.escapeShellArg line}; } > $out
    '';
  genB =
    (mkHome "test" system (
      { pkgs, ... }:
      {
        highwind.interactiveShell = pkgs.zsh;
        home.file.".zshrc".source = lib.mkForce (appended ".zshrc" "alias highwind_gen='echo b'");
        # Ends A's [terminal] table, so the line lands in it.
        home.file.".config/herdr/config.toml".source = lib.mkForce (
          appended ".config/herdr/config.toml" ''new_cwd = "/tmp"''
        );
      }
    )).activationPackage;

  # ── Before the rename ──────────────────────────────────────────────────────
  # An environment activated before the project was renamed highwind (2026-11-28) differs on disk
  # in two ways: its links sit under ~/.local/share/dotfiles, and its plugin builds carried
  # .dotfiles-pin, so their store paths differ from today's and herdr records those. genOld is A
  # with that state put back: the module places nothing under the new directory, the old links
  # hold copies of the plugin builds with the old pin file, and herdr links each from there.
  oldDir = ".local/share/dotfiles";
  newDir = ".local/share/highwind";
  herdrBin = "${self.packages.${system}.tools}/bin/herdr";
  oldPlugins = lib.mapAttrs (
    id: p:
    pkgs.runCommand "before-rename-${id}" { } ''
      cp -r ${p} $out
      chmod -R u+w $out
      mv $out/.highwind-pin $out/.dotfiles-pin
    ''
  ) self.packages.${system}.herdr-plugins.plugins;
  genOld =
    (mkHome "test" system (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        highwind.interactiveShell = pkgs.zsh;
        highwind.herdrPlugins.enable = false;
        home.file = {
          "${newDir}/herdr-summarizer-plugin".enable = lib.mkForce false;
          "${oldDir}/herdr-summarizer-plugin".source = self.packages.${system}.summarizer-plugin;
        }
        // lib.mapAttrs' (id: p: lib.nameValuePair "${oldDir}/herdr-plugins/${id}" { source = p; }) oldPlugins;
        home.activation.beforeRenameHerdrPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.concatMapStrings (id: ''
            run ${herdrBin} plugin link "$(readlink -f ${config.home.homeDirectory}/${oldDir}/herdr-plugins/${id})" >/dev/null
          '') (lib.attrNames oldPlugins)
        );
      }
    )).activationPackage;

  # step 7 of test/suite.sh, as in vm-home.
  probe = pkgs.writeText "zsh-probe.zsh" ''
    print -r -- "zvm=''${+functions[zvm_init]}"
    print -r -- "starship=''${+functions[prompt_starship_precmd]}"
    [[ "$(bindkey -M viins '^T')" == *fzf* ]] && print fzf=1 || print fzf=0
    [[ "$(bindkey -M viins '^R')" == *atuin* ]] && print atuin=1 || print atuin=0
    print -r -- "zoxide=''${+functions[__zoxide_z]}"
    print -r -- probe-done
  '';
in
pkgs.testers.runNixOSTest {
  name = "vm-switch";

  nodes.machine = {
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
    # Both generations are registered in the guest's store; nothing is fetched or built there.
    virtualisation.additionalPaths = [
      genA
      genB
      genOld
    ];
    # The store paths an activation adds (the user's profile) must survive the reboot.
    virtualisation.writableStoreUseTmpfs = false;

    services.openssh.enable = true;

    # As on homepc: bash is the login shell and nothing enables zsh system-wide.
    users.users.test = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ keys.snakeOilPublicKey ];
    };
  };

  testScript = ''
    import json
    import shlex

    SSH = ("env TERM=xterm-256color ssh -i /root/id -o StrictHostKeyChecking=no"
           " -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10")
    SWITCH = "${switch}"
    GEN_A, GEN_B, GEN_OLD = "${genA}", "${genB}", "${genOld}"
    HERDR = "~/.nix-profile/bin/herdr"
    PLUGINS = ${builtins.toJSON pluginIds}
    # The repo's nvim spec without LazyVim (no network to install it): its init finds the editor file.
    NVIM_PROBE = ("lua dofile(vim.fn.expand('~/.config/nvim/lua/plugins/herdr.lua'))[1].init();"
                  " io.stdout:write(vim.fn.maparg('<C-h>', 'n', false, true).desc or 'none')")

    def ssh(cmd, timeout=60):
        """A non-interactive command over SSH as test, run by the login shell (bash -c)."""
        return f"timeout {timeout} {SSH} test@localhost {shlex.quote(cmd)}"

    def ssh_tty(typed, cmd="", delay=8, timeout=90):
        """ssh -tt with `typed` sent to the pty after `delay` seconds (as in vm-home)."""
        remote = f" {shlex.quote(cmd)}" if cmd else ""
        feed = f"(sleep {delay}; printf '%s\\n' {shlex.quote(typed)}; sleep 15)"
        return f"{feed} | timeout {timeout} {SSH} -tt test@localhost{remote}"

    def logins_ok(when):
        """ssh true works, and an interactive login runs bash, not zsh."""
        machine.succeed(ssh("true"))
        # The pty echoes the typed line; only a shell that ran it prints the expanded value.
        out = machine.succeed(ssh_tty("echo shell=''${ZSH_NAME:-none}-''${BASH_VERSION:+bash}; exit 0", delay=5))
        assert "shell=none-bash" in out, f"{when}: the interactive login is not bash:\n{out[-600:]}"

    def current():
        return machine.succeed(ssh("readlink -e ~/.local/state/home-manager/gcroots/current-home")).strip()

    def herdr_up():
        machine.wait_until_succeeds(ssh(f"{HERDR} workspace list"), timeout=60)

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_open_port(22)
    machine.succeed("install -m 600 ${keys.snakeOilPrivateKey} /root/id")

    with subtest("the login shell is bash"):
        shell = machine.succeed("getent passwd test | cut -d: -f7").strip()
        assert shell.endswith("/bash"), f"test's login shell is {shell}"
        logins_ok("before any switch")

    with subtest("a dry run places nothing"):
        out = machine.succeed(ssh(f"{SWITCH} --dry-run --activation-package {GEN_A}"))
        print(out)
        assert "No Home Manager generation yet" in out and "+ .zshrc" in out, out
        assert "Collisions" in out and "  none" in out, out
        machine.fail(ssh("test -e ~/.zshrc || test -e ~/.local/state/nix/profiles/home-manager"))

    with subtest("generation A: placed by the user, without root"):
        out = machine.succeed(ssh(f"{SWITCH} --activation-package {GEN_A} 2>&1", timeout=300))
        print(out)
        for p in PLUGINS:
            assert f"highwind: linked herdr plugin {p}" in out, f"A did not link {p}:\n{out}"
        assert current() == GEN_A, f"current generation is {current()}, not A"
        target = machine.succeed(ssh("readlink -f ~/.zshrc")).strip()
        assert target.startswith("/nix/store/"), f".zshrc resolves to {target}"
        machine.succeed(ssh("test -x ~/.nix-profile/bin/zsh && test -x ~/.nix-profile/bin/highwind-switch"))
        machine.fail(ssh("grep -q highwind_gen ~/.zshrc"))
        logins_ok("after A")

    with subtest("herdr's plugins are the builds, at their pins, and nvim finds its half"):
        lst = machine.succeed(ssh(f"{HERDR} plugin list"))
        print(lst)
        for p in PLUGINS:
            line = next((l for l in lst.splitlines() if l.startswith(f"- {p} (")), "")
            assert "enabled [local:/nix/store/" in line, f"{p} is not listed enabled from the store:\n{lst}"
        check = machine.succeed(ssh("~/.local/bin/herdr-plugins check"))
        print(check)
        assert check.count(" at its pin ") == len(PLUGINS) and "drift" not in check and "absent" not in check, check
        nav = machine.succeed(ssh("~/.nix-profile/bin/nvim --headless -u NONE -i NONE +" + shlex.quote(NVIM_PROBE) + " +qa 2>&1"))
        assert "Navigate left (vim/herdr)" in nav, f"nvim did not load vim-herdr-navigation: {nav!r}"

    with subtest("the interactive zsh is clean"):
        err, res = "/tmp/zsh-stderr", "/tmp/zsh-probe.out"
        machine.succeed(ssh_tty(f"source ${probe} > {res} 2>&1; exit", cmd=f"exec ~/.nix-profile/bin/zsh -il 2>{err}"))
        out = machine.succeed(f"cat {res}")
        print(f"probe:\n{out}")
        assert "probe-done" in out, "zsh never ran the probe"
        missing = [k for k in ["zvm", "starship", "fzf", "atuin", "zoxide"] if f"{k}=1" not in out.split()]
        assert not missing, f"not loaded: {missing}"
        stderr = machine.succeed(f"cat {err}")
        assert stderr == "", f"startup files wrote to stderr: {stderr!r}"

    with subtest("herdr panes start zsh while the login shell is bash"):
        machine.succeed(ssh(f"setsid -f {HERDR} server > /tmp/herdr-server.out 2>&1 < /dev/null"))
        herdr_up()
        machine.succeed(ssh(f"{HERDR} workspace create --cwd ~ --label t --focus"))
        machine.sleep(3)
        info = machine.succeed(ssh(f"{HERDR} pane process-info --pane w1:p1"))
        assert '"name":"zsh"' in info, f"the pane does not run zsh: {info}"
        tab = machine.succeed(ssh(f"{HERDR} tab create --workspace w1"))
        assert '"cwd":"/home/test"' in tab, f"before B a new tab should follow ~: {tab}"

    with subtest("a dry run of B lists the two changed files and changes nothing"):
        out = machine.succeed(ssh(f"{SWITCH} --dry-run --activation-package {GEN_B} 2>&1"))
        print(out)
        assert "~ .zshrc" in out and "~ .config/herdr/config.toml" in out, out
        assert "error:" not in out, out
        assert current() == GEN_A, "a dry run changed the generation"

    with subtest("generation B: the change is live and herdr reloaded"):
        out = machine.succeed(ssh(f"{SWITCH} --activation-package {GEN_B} 2>&1", timeout=300))
        print(out)
        assert "highwind: herdr reloaded its config" in out, f"the onChange hook did not reload herdr:\n{out}"
        assert "linked herdr plugin" not in out, f"B re-linked plugins whose builds did not change:\n{out}"
        lst = machine.succeed(ssh(f"{HERDR} plugin list"))
        listed = [l for l in lst.splitlines() if l.startswith("- ")]
        assert len(listed) == len(PLUGINS), f"after B the plugin list changed:\n{lst}"
        assert current() == GEN_B, f"current generation is {current()}, not B"
        machine.succeed(ssh("grep -q highwind_gen ~/.zshrc"))
        alias = machine.succeed(ssh("~/.nix-profile/bin/zsh -ic 'alias highwind_gen' 2>/dev/null"))
        assert "highwind_gen=" in alias, f"a new zsh does not have B's alias: {alias}"
        machine.succeed(ssh("grep -q 'method=\"server.reload_config\"' ~/.config/herdr/herdr-server.log"))
        # B's line (new_cwd = "/tmp") is in force in the running server.
        tab = machine.succeed(ssh(f"{HERDR} tab create --workspace w1"))
        assert '"cwd":"/tmp"' in tab, f"after B a new tab should start in /tmp: {tab}"
        machine.succeed(ssh(f"{HERDR} server stop"))
        logins_ok("after B")

    with subtest("after a reboot the user environment is still B"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_open_port(22)
        assert current() == GEN_B, f"after the reboot the generation is {current()}, not B"
        machine.succeed(ssh("grep -q highwind_gen ~/.zshrc"))
        machine.succeed(ssh("grep -q 'new_cwd = \"/tmp\"' ~/.config/herdr/config.toml"))
        logins_ok("after the reboot")

    with subtest("rollback to A, with no herdr server running"):
        machine.fail(ssh(f"{HERDR} status server | grep -qx 'status: running'"))
        out = machine.succeed(ssh(f"{SWITCH} --rollback 2>&1", timeout=300))
        print(out)
        assert current() == GEN_A, f"after the rollback the generation is {current()}, not A"
        assert "highwind: no herdr server running; nothing to reload" in out, out
        machine.fail(ssh("grep -q highwind_gen ~/.zshrc"))
        machine.fail(ssh("grep -q new_cwd ~/.config/herdr/config.toml"))
        logins_ok("after the rollback")

    def plugin_roots():
        """herdr's plugin list as (id, kind, root) for every entry."""
        lst = json.loads(machine.succeed(ssh(f"{HERDR} plugin list --json")))
        return [(p["plugin_id"], p["source"]["kind"], p["plugin_root"]) for p in lst["result"]["plugins"]]

    def linked_at(data):
        """Each plugin is listed once, as a local link to the build under ~/.local/share/<data>."""
        roots = plugin_roots()
        assert sorted(i for i, _, _ in roots) == sorted(PLUGINS), f"herdr lists {roots}, not each plugin once"
        for p, kind, root in roots:
            want = machine.succeed(ssh(f"readlink -e ~/.local/share/{data}/herdr-plugins/{p}")).strip()
            assert kind == "local" and root == want, f"{p} is linked at {kind}:{root}, not {want}"

    with subtest("an environment from before the rename: links under ~/.local/share/dotfiles"):
        out = machine.succeed(ssh(f"{SWITCH} --activation-package {GEN_OLD} 2>&1", timeout=300))
        print(out)
        machine.succeed(ssh("test -L ~/.local/share/dotfiles/herdr-summarizer-plugin"))
        machine.fail(ssh("test -e ~/.local/share/highwind"))
        linked_at("dotfiles")

    with subtest("the rename: the old links go, the new ones come, each plugin is re-linked once"):
        out = machine.succeed(ssh(f"{SWITCH} --activation-package {GEN_A} 2>&1", timeout=300))
        print(out)
        assert current() == GEN_A, f"current generation is {current()}, not A"
        for p in PLUGINS:
            assert f"highwind: linked herdr plugin {p}" in out, f"A did not re-link {p}:\n{out}"
            machine.fail(ssh(f"test -e ~/.local/share/dotfiles/herdr-plugins/{p} || test -L ~/.local/share/dotfiles/herdr-plugins/{p}"))
        machine.fail(ssh("test -e ~/.local/share/dotfiles/herdr-summarizer-plugin || test -L ~/.local/share/dotfiles/herdr-summarizer-plugin"))
        print(machine.succeed(ssh("ls -la ~/.local/share/dotfiles 2>&1 || true")))
        machine.succeed(ssh("test -L ~/.local/share/highwind/herdr-summarizer-plugin"))
        linked_at("highwind")
        check = machine.succeed(ssh("~/.local/bin/herdr-plugins check"))
        print(check)
        assert check.count(" at its pin ") == len(PLUGINS) and "drift" not in check and "absent" not in check, check
        logins_ok("after the rename")
  '';
}
