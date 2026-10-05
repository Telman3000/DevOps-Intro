#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/.config/nix
printf '%s\n' 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf
export NIX_CONFIG="experimental-features = nix-command flakes"
cd /repo
nix build .#docker --print-build-logs 2>&1 | tee /repo/submissions/lab11-artifacts/nix-build-docker.txt
sha256sum "$(readlink -f result)" | tee /repo/submissions/lab11-artifacts/docker-sha-env-a.txt
ls -lh result
