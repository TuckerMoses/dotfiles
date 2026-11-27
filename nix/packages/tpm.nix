# TPM, the tmux plugin manager, is not in nixpkgs. Pinned to a fixed commit of master.
{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "tmux-plugins";
  repo = "tpm";
  rev = "e261deb1b47614eed3400089ce7197dc68acc4eb";
  hash = "sha256-oRKUZNyJYQXlkeQfbEYiltUEBpvdwn2SoEBWHVUNmrA=";
}
