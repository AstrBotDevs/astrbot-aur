#!/bin/bash
# Publish the reviewed master branch; the protected workflow publishes AUR.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

cd "$SCRIPT_DIR"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Error: update.sh requires a non-detached master branch." >&2
    exit 1
}
[[ "$branch" == master ]] || {
    echo "Error: update.sh only publishes the existing master branch." >&2
    exit 1
}

[[ -z "$(git status --porcelain=v1 --untracked-files=normal)" ]] || {
    echo "Error: commit or remove all local changes before publishing." >&2
    exit 1
}

git remote get-url origin >/dev/null 2>&1 || {
    echo "Error: required GitHub remote 'origin' is not configured." >&2
    exit 1
}

git push --dry-run origin master:master
git push origin master:master

echo "Published master to GitHub. The aur-production workflow publishes the root-only AUR snapshot."
