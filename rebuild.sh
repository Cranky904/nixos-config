#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

branch=$(git symbolic-ref --short HEAD)

# Git-backed flakes only include known files, including newly added modules.
git add --all

echo "Rebuilding NixOS system..."
sudo nixos-rebuild switch --flake .#nixos

# set -e stops here on a failed rebuild, before any commit or push.
if ! git diff --cached --quiet; then
  iteration=$(
    git log --all --format=%s |
      awk -F '#' '
        BEGIN { max = 0 }
        /^Rebuild iteration #[0-9]+$/ {
          if ($2 + 0 > max) max = $2 + 0
        }
        END { printf "%.0f\n", max + 1 }
      '
  )
  git commit -m "Rebuild iteration #${iteration}"
else
  echo "No configuration changes to commit."
fi

echo "Pushing ${branch} to origin..."
git push --set-upstream origin "HEAD:refs/heads/${branch}"

echo "Done!"

