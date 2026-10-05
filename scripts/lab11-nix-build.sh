#!/usr/bin/env bash
set -euo pipefail
mkdir -p ~/.config/nix
printf '%s\n' 'experimental-features = nix-command flakes' > ~/.config/nix/nix.conf
export NIX_CONFIG="experimental-features = nix-command flakes"
nix --version
cd /repo
nix build .#quicknotes --print-build-logs 2>&1 | tee /repo/submissions/lab11-artifacts/nix-build-quicknotes.txt
echo "RESULT=$(readlink -f result)"
nix-store --query --hash "$(readlink -f result)" | tee /repo/submissions/lab11-artifacts/hash-env-a.txt
