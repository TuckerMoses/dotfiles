---
created: 2026-11-25
source: session (nixos-host), agreed with the user after the homepc install
---

# homepc: separate agent user, narrower sudo, tailnet access rules, managed secrets

- **What:** Run Claude Code sessions on homepc as their own unprivileged user, cut `tucker`'s
  passwordless sudo down to what remote administration needs, restrict homepc's ports on the
  tailnet to named devices, and move the ad hoc secret files into `sops-nix`.
- **Why here:** One account does everything today. `tucker` has passwordless sudo
  (`security.sudo.wheelNeedsPassword = false` in `nixos/modules/lifeline.nix`) and every agent
  session runs as it, so an agent is root with every credential the user holds. The 54 deny rules
  in `~/.claude/settings.json` on homepc match command text and are not a boundary. The Wi-Fi and
  remote desktop passwords sit in root-only plain files outside the config. Each new credential
  (GitHub keys were the first) reopens the same question because of this.
- **Effort:** medium.
- **Touches:** `nixos/modules/lifeline.nix` (its guard asserts passwordless sudo),
  `nixos/modules/safe-rebuild.nix`, `nixos/modules/host-check.nix`, a new module for the agent
  user, `nixos/hosts/homepc/`, `nixos/wifi-profile.sh`, `nixos/README.md`, `CLAUDE.md`.
- **Needs the real machine:** yes.
- **Notes for the plan:**
  - `safe-confirm` must stay something only a person logging in from outside can do. The agent
    user may build and prepare a change; it must not be able to activate one unreviewed.
  - `safe-switch` activates a config as root for up to five minutes before confirmation. Decide
    whether the agent user may run it at all, or only hand a built system to the user.
  - SSH is key-only, so a sudo password is only typed by a person. `tucker` has an account
    password (set 2026-11-25).
  - The drills in `nixos/test/drills.sh` and the lockout drill on the real machine use sudo without
    a prompt. Re-run all of them after the change, in the VM first.
  - GitHub: the agent user keeps repo-scoped deploy keys. The user's own account may hold a wider
    key behind a passphrase or an SSH agent.
  - Tailscale access rules live in the Tailscale admin console, not in this repo. Keep a copy of
    the policy in the repo and say in the plan who applies it. Port 22 on the tailnet is Tailscale
    SSH in `check` mode; port 2222 is OpenSSH and is the path `safe-confirm` needs.
  - Leave disk encryption out; it is its own proposal (`homepc-disk-encryption.md`).

## Needs decision
Should `tucker` keep passwordless sudo for a fixed list of commands (the safe-rebuild helpers and
`host-check`) and need a password for everything else, or need a password for all sudo?
