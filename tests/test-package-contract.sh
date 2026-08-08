#!/usr/bin/env bash
# Verify the public archive and installed payload never ship VCS workspace state.
set -Eeuo pipefail

archive="${1:?usage: $0 <package-archive> [installed-app-dir]}"
app_dir="${2:-/opt/astrbot}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

command -v bsdtar >/dev/null || fail "bsdtar is required"
[[ -f "$archive" ]] || fail "package archive not found: $archive"
[[ -d "$app_dir" ]] || fail "installed app directory not found: $app_dir"

archive_entries="$(bsdtar -tf "$archive")"
if grep -Eq '^opt/astrbot/\.git(/|$)' <<<"$archive_entries"; then
    fail "package archive ships /opt/astrbot/.git"
fi

if [[ -e "$app_dir/.git" ]]; then
    fail "installed payload contains /opt/astrbot/.git"
fi

if grep -Fq '/home/lightjunction/Documents/GITHUB/AstrBot-aur' <<<"$archive_entries"; then
    fail "package archive entry contains a workspace path"
fi

if grep -Fq 'Initial password: {generated_password}' \
    "$app_dir/astrbot/dashboard/server.py"; then
    fail "installed dashboard source still interpolates an initial password"
fi

printf 'PASS: package archive contains no VCS workspace state or password-log source.\n'
