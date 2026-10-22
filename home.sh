#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Applying Home Manager configuration for cranky..."
home-manager switch --flake .#cranky -b backup

echo "Done!"
