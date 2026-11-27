# vm-home (docs/design/nix-dotfiles.md, section 7): one machine with a user in each link mode.
# Both Home Manager units succeed, each user logs in over SSH with a key into a clean
# interactive zsh, a checkout edit is live without a rebuild, an interactive login survives a
# broken .zshrc, and herdr-sandbox leaves the real home untouched.
#
# The guest has no network: everything the users need is in its store closure (Home Manager's
# packages, and the flake source copied in for the checkout user).
{
  self,
  inputs,
  pkgs,
}:
let
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;

  # Test users, not the owner's: fixed names and homes are fine here.
  checkoutHome = "/home/bob";
  checkoutDir = "${checkoutHome}/dotfiles";

  # step 7 of test/suite.sh: what a working interactive zsh has loaded by its first prompt.
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
  name = "vm-home";

  # dotfiles-user.nix reads inputs.home-manager and inputs.self, as it does on a real host.
  node.specialArgs = { inherit inputs; };

  nodes.machine =
    { pkgs, ... }:
    {
      # Only the module under test; it brings the Home Manager NixOS module with it.
      imports = [ ../../nixos/modules/dotfiles-user.nix ];

      virtualisation.memorySize = 3072;
      virtualisation.cores = 2;

      services.openssh.enable = true;

      # dotfiles-user.nix does not enable zsh; the global prompt and compinit would run before
      # the user's own .zshrc and make the "clean shell" check about NixOS, not the dotfiles.
      programs.zsh = {
        enable = true;
        promptInit = "";
        enableGlobalCompInit = false;
      };

      users.users =
        let
          user = {
            isNormalUser = true;
            shell = pkgs.zsh;
            openssh.authorizedKeys.keys = [ keys.snakeOilPublicKey ];
          };
        in
        {
          alice = user;
          bob = user // {
            home = checkoutHome;
          };
        };

      dotfiles.users = {
        alice = { };
        bob = {
          linkMode = "checkout";
          checkout = checkoutDir;
        };
      };

      # For the leak check: herdr-sandbox run as alice must leave her home as it was.
      home-manager.users.alice.home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-sandbox ];

      # The checkout user's repo: a writable copy of the flake source, made before Home Manager
      # links into it. Referencing self here also puts the source in the guest's closure.
      systemd.services.dotfiles-checkout-bob = {
        description = "Copy the dotfiles flake source into bob's checkout";
        wantedBy = [ "multi-user.target" ];
        before = [ "home-manager-bob.service" ];
        requiredBy = [ "home-manager-bob.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "bob";
        };
        script = ''
          if [ ! -e ${checkoutDir} ]; then
            cp -R ${self} ${checkoutDir}
            chmod -R u+w ${checkoutDir}
          fi
        '';
      };
    };

  testScript = ''
    import shlex

    SSH = ("env TERM=xterm-256color ssh -i /root/id -o StrictHostKeyChecking=no"
           " -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10")
    USERS = ["alice", "bob"]

    def ssh(user, cmd, timeout=60):
        """A non-interactive command over SSH, run by the user's login shell (zsh -c)."""
        return f"timeout {timeout} {SSH} {user}@localhost {shlex.quote(cmd)}"

    def ssh_tty(user, typed, cmd="", delay=8, timeout=90):
        """ssh -tt with `typed` sent to the pty after `delay` seconds. stdin stays open a while
        after, so an EOF never races the typed line."""
        remote = f" {shlex.quote(cmd)}" if cmd else ""
        feed = f"(sleep {delay}; printf '%s\\n' {shlex.quote(typed)}; sleep 15)"
        return f"{feed} | timeout {timeout} {SSH} -tt {user}@localhost{remote}"

    start_all()

    with subtest("both Home Manager units succeed"):
        machine.wait_for_unit("multi-user.target")
        for u in USERS:
            machine.wait_for_unit(f"home-manager-{u}.service")
        machine.succeed("systemctl is-active home-manager-alice.service home-manager-bob.service")
        machine.wait_for_open_port(22)
        machine.succeed("install -m 600 ${keys.snakeOilPrivateKey} /root/id")

    with subtest("each user logs in over SSH with a key, into zsh"):
        for u in USERS:
            shell = machine.succeed(ssh(u, "echo $ZSH_NAME")).strip()
            assert shell == "zsh", f"{u}: login shell is {shell!r}, not zsh"

    with subtest("configs link to the store for alice and to the checkout for bob"):
        target = machine.succeed(ssh("alice", "readlink -f ~/.zshrc")).strip()
        assert target.startswith("/nix/store/"), f"alice's .zshrc resolves to {target}"
        target = machine.succeed(ssh("bob", "readlink -f ~/.zshrc")).strip()
        assert target == "${checkoutDir}/zsh/.zshrc", f"bob's .zshrc resolves to {target}"

    with subtest("the interactive shell is clean"):
        for u in USERS:
            err, out = f"/tmp/zsh-stderr-{u}", f"/tmp/zsh-probe-{u}.out"
            # A login zsh as sshd starts one, with stderr kept apart from the pty.
            machine.succeed(ssh_tty(u, f"source ${probe} > {out} 2>&1; exit",
                                    cmd=f"exec zsh -il 2>{err}"))
            res = machine.succeed(f"cat {out}")
            print(f"{u} probe:\n{res}")
            assert "probe-done" in res, f"{u}: zsh never ran the probe"
            missing = [k for k in ["zvm", "starship", "fzf", "atuin", "zoxide"]
                       if f"{k}=1" not in res.split()]
            assert not missing, f"{u}: not loaded: {missing}"
            stderr = machine.succeed(f"cat {err}")
            assert stderr == "", f"{u}: startup files wrote to stderr: {stderr!r}"

    with subtest("herdr-sandbox leaves the real home untouched"):
        # The first login of a session starts the user manager; get that out of the way.
        machine.succeed(ssh("alice", "true"))
        changed = machine.succeed(ssh("alice",
            "stamp=$(mktemp); sleep 1; herdr-sandbox --no-attach -- true || exit 1;"
            " find ~ -newer $stamp; rm -f $stamp", timeout=180))
        assert changed.strip() == "", f"herdr-sandbox changed the real home:\n{changed}"

    with subtest("a checkout edit is live without a rebuild"):
        machine.succeed(ssh("bob",
            "echo \"alias dotfiles_live_probe='echo live'\" >> ~/dotfiles/zsh/.zshrc"))
        out = machine.succeed(ssh_tty("bob", "alias dotfiles_live_probe; exit"))
        assert "dotfiles_live_probe=" in out, f"the edit is not live:\n{out}"
        machine.succeed(ssh("bob", "sed -i '/dotfiles_live_probe/d' ~/dotfiles/zsh/.zshrc"))

    with subtest("SSH logins with a broken .zshrc"):
        # The row asserts the syntax error case; the rest is recorded for the lockout question.
        machine.succeed(ssh("bob", "cp ~/dotfiles/zsh/.zshrc /tmp/zshrc.good"))
        breaks = {"syntax error": ")", "exit 1": "exit 1"}
        table = []
        for name, line in breaks.items():
            machine.succeed(ssh("bob",
                f"{{ echo {shlex.quote(line)}; cat /tmp/zshrc.good; }} > ~/dotfiles/zsh/.zshrc"))
            rc_plain, _ = machine.execute(ssh("bob", "true"))
            # The pty echoes what is typed, so only a shell that ran the line prints 42.
            rc_tty, out = machine.execute(ssh_tty("bob", "echo ran-$((6*7)); exit 0", delay=5))
            ran = "ran-42" in out
            table.append((name, rc_plain, rc_tty, ran))
            print(f"--- {name}: ssh -tt output (tail) ---\n{out[-600:]!r}")
        machine.succeed(ssh("bob", "cp /tmp/zshrc.good ~/dotfiles/zsh/.zshrc"))
        print("broken .zshrc | ssh bob true | ssh -tt bob: exit code | ssh -tt bob: shell ran input")
        for row in table:
            print(" | ".join(map(str, row)))
        _, _, rc_tty, ran = table[0]
        assert rc_tty == 0 and ran, f"interactive login with a syntax error in .zshrc: exit {rc_tty}, ran input: {ran}"
  '';
}
