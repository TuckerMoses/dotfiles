# vm-switch (docs/design/nix-dotfiles.md, section 14): a user whose environment is a standalone
# Home Manager configuration, activated by that user with dotfiles-switch and no root, while the
# login shell stays bash. Generation A is homeConfigurations."test@vm"; B differs in .zshrc and
# one herdr config line. The test switches to A, then to B with a herdr server running (the
# onChange hook reloads it), reboots (B stays: nothing re-activates a user environment at boot),
# and rolls back to A with no server running. SSH logins land in bash throughout.
#
# The guest has no network, so nothing is built in it: both generations are built with the test
# and handed to dotfiles-switch with --activation-package.
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
  switch = "${self.packages.${system}.dotfiles-switch}/bin/dotfiles-switch";

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
        dotfiles.interactiveShell = pkgs.zsh;
        home.file.".zshrc".source = lib.mkForce (appended ".zshrc" "alias dotfiles_gen='echo b'");
        # Ends A's [terminal] table, so the line lands in it.
        home.file.".config/herdr/config.toml".source = lib.mkForce (
          appended ".config/herdr/config.toml" ''new_cwd = "/tmp"''
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
    import shlex

    SSH = ("env TERM=xterm-256color ssh -i /root/id -o StrictHostKeyChecking=no"
           " -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10")
    SWITCH = "${switch}"
    GEN_A, GEN_B = "${genA}", "${genB}"
    HERDR = "~/.nix-profile/bin/herdr"

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
        machine.succeed(ssh(f"{SWITCH} --activation-package {GEN_A}", timeout=300))
        assert current() == GEN_A, f"current generation is {current()}, not A"
        target = machine.succeed(ssh("readlink -f ~/.zshrc")).strip()
        assert target.startswith("/nix/store/"), f".zshrc resolves to {target}"
        machine.succeed(ssh("test -x ~/.nix-profile/bin/zsh && test -x ~/.nix-profile/bin/dotfiles-switch"))
        machine.fail(ssh("grep -q dotfiles_gen ~/.zshrc"))
        logins_ok("after A")

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
        assert "dotfiles: herdr reloaded its config" in out, f"the onChange hook did not reload herdr:\n{out}"
        assert current() == GEN_B, f"current generation is {current()}, not B"
        machine.succeed(ssh("grep -q dotfiles_gen ~/.zshrc"))
        alias = machine.succeed(ssh("~/.nix-profile/bin/zsh -ic 'alias dotfiles_gen' 2>/dev/null"))
        assert "dotfiles_gen=" in alias, f"a new zsh does not have B's alias: {alias}"
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
        machine.succeed(ssh("grep -q dotfiles_gen ~/.zshrc"))
        machine.succeed(ssh("grep -q 'new_cwd = \"/tmp\"' ~/.config/herdr/config.toml"))
        logins_ok("after the reboot")

    with subtest("rollback to A, with no herdr server running"):
        machine.fail(ssh(f"{HERDR} status server | grep -qx 'status: running'"))
        out = machine.succeed(ssh(f"{SWITCH} --rollback 2>&1", timeout=300))
        print(out)
        assert current() == GEN_A, f"after the rollback the generation is {current()}, not A"
        assert "dotfiles: no herdr server running; nothing to reload" in out, out
        machine.fail(ssh("grep -q dotfiles_gen ~/.zshrc"))
        machine.fail(ssh("grep -q new_cwd ~/.config/herdr/config.toml"))
        logins_ok("after the rollback")
  '';
}
