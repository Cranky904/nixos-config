#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

echo "Applying Home Manager configuration for cranky..."
home-manager switch --flake .#cranky

echo "Done!"
