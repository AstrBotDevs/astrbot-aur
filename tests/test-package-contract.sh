#!/usr/bin/env bash
# Verify the public archive and installed payload never ship VCS workspace state.
set -Eeuo pipefail

archive="${1:?usage: $0 <package-archive> [installed-app-dir]}"
app_dir="${2:-/opt/astrbot}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_no_match() {
    local message="$1" status
    shift
    if grep "$@" >/dev/null; then
        fail "$message"
    else
        status=$?
        [[ "$status" -eq 1 ]] || fail "grep failed (exit $status): $message"
    fi
}

command -v bsdtar >/dev/null || fail "bsdtar is required"
command -v grep >/dev/null || fail "grep is required"
[[ -f "$archive" && -r "$archive" ]] || fail "package archive is missing or unreadable: $archive"
[[ -d "$app_dir" ]] || fail "installed app directory not found: $app_dir"
server_path="$app_dir/astrbot/dashboard/server.py"
[[ -f "$server_path" && -r "$server_path" ]] || fail "installed dashboard source is missing or unreadable: $server_path"

archive_entries="$(bsdtar -tf "$archive")" || fail "could not list package archive: $archive"
assert_no_match "package archive ships /opt/astrbot/.git" \
    -E -- '^(\./)?opt/astrbot/\.git(/|$)' <<<"$archive_entries"

if [[ -e "$app_dir/.git" || -L "$app_dir/.git" ]]; then
    fail "installed payload contains /opt/astrbot/.git"
fi

assert_no_match "package archive entry contains a workspace path" \
    -F -- '/home/lightjunction/Documents/GITHUB/AstrBot-aur' <<<"$archive_entries"
assert_no_match "installed dashboard source still interpolates an initial password" \
    -F -- 'Initial password: {generated_password}' "$server_path"

printf 'PASS: package archive contains no VCS workspace state or password-log source.\n'
