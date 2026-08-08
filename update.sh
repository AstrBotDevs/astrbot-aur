#!/bin/bash
# Publish the already-reviewed master branch.  GitHub Actions publishes AUR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

branch="$(git symbolic-ref --quiet --short HEAD)"
[ "$branch" = master ] || {
    echo "❌ update.sh only publishes the existing master branch." >&2
    exit 1
}

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "❌ Commit or discard local changes before publishing." >&2
    exit 1
fi

git push origin master
echo "✅ Pushed master to origin; GitHub Actions publishes the AUR package."
