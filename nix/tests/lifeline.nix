# vm-lifeline (docs/design/nix-dotfiles.md, section 7): a machine with the lifeline module boots
# with sshd answering on 22 and 2222, the firewall up with both open, and sleep targets masked.
# The ports are checked from a second machine, so the firewall is really in the way.
{ pkgs }:
let
  keys = import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs;
  # A port something listens on that the firewall must still refuse.
  closedPort = 8080;
in
pkgs.testers.runNixOSTest {
  name = "vm-lifeline";

  nodes.server =
    { lib, ... }:
    {
      imports = [ ../../nixos/modules/lifeline.nix ];

      lifeline = {
        user = "admin";
        authorizedKeys = [ keys.snakeOilPublicKey ];
        flakeAttr = "vm-lifeline";
      };

      # The guest has no Tailscale login and no default route, so the connectivity watchdog
      # would restart NetworkManager from about 7 minutes after boot and reboot at about 19.
      # The module has no option for it; the test turns its timer off.
      systemd.timers.lifeline-watchdog.enable = lib.mkForce false;

      environment.systemPackages = [ pkgs.python3 ];
    };

  nodes.client = {
    environment.systemPackages = [ pkgs.netcat ];
  };

  testScript = ''
    SSH = ("ssh -i /root/id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
           " -o BatchMode=yes -o ConnectTimeout=10")

    start_all()
    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("sshd.service")
    client.wait_for_unit("multi-user.target")

    with subtest("the firewall is up"):
        server.succeed("systemctl is-active firewall.service")

    with subtest("sshd answers on 22 and 2222 from another machine"):
        client.succeed("install -m 600 ${keys.snakeOilPrivateKey} /root/id")
        for port in [22, 2222]:
            client.wait_until_succeeds(f"nc -z -w 2 server {port}", timeout=60)
            client.succeed(f"timeout 30 {SSH} -p {port} admin@server true")

    with subtest("a port with a listener but no firewall hole stays closed"):
        server.succeed("systemd-run --unit closed-port-probe python3 -m http.server ${toString closedPort}")
        server.wait_for_open_port(${toString closedPort})
        client.fail("nc -z -w 3 server ${toString closedPort}")

    with subtest("sleep targets are masked"):
        for target in ["sleep.target", "suspend.target", "hibernate.target"]:
            _, state = server.execute(f"systemctl is-enabled {target}")
            assert state.strip() == "masked", f"{target} is {state.strip()!r}, not masked"
  '';
}
