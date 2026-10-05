#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/.config/nix
printf '%s\n' 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf
export NIX_CONFIG="experimental-features = nix-command flakes"
cd /repo
# Independent env B: separate store volume; still uses flake.lock
nix build .#quicknotes
nix-store --query --hash "$(readlink -f result)" | tee /repo/submissions/lab11-artifacts/hash-env-b.txt
nix build .#docker
sha256sum "$(readlink -f result)" | tee /repo/submissions/lab11-artifacts/docker-sha-env-b.txt
