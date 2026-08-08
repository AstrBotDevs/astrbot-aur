#!/usr/bin/env bash
# Ensure every local PKGBUILD publication asset is present and preflight-checked.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
workflow="$repo_dir/.github/workflows/aur-publish.yml"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for asset in \
    astrbot-git.install \
    astrbotctl \
    astrbotctl.functions \
    astrbot@.service \
    tmpl.conf \
    no-dashboard-password-in-startup-log.patch; do
    test -f "$repo_dir/$asset" || fail "missing local asset $asset"
    [[ $(grep -Fc "$asset" "$workflow") -ge 2 ]] || fail "workflow does not publish and preflight $asset"
done

grep -Fq 'git push origin master' "$repo_dir/update.sh" || fail 'update.sh does not push master to origin'
if grep -Fq 'github' "$repo_dir/update.sh"; then
    fail 'update.sh still has a direct GitHub publication path'
fi

printf 'PASS: publication workflow includes and preflights every local package asset.\n'
