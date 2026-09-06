#!/usr/bin/env bash
# Package-contract negative tests use only disposable archives and payloads.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
app_dir="$tmp_dir/payload/opt/astrbot"
server="$app_dir/astrbot/dashboard/server.py"
archive="$tmp_dir/package.tar"
mkdir -p "$(dirname "$server")"
printf '# reviewed dashboard source\n' >"$server"
bsdtar -cf "$archive" -C "$tmp_dir/payload" opt
check() { bash "$repo_dir/tests/test-package-contract.sh" "$archive" "$app_dir"; }
expect_failure() {
    if check >"$tmp_dir/output" 2>&1; then
        fail "$1"
    fi
}
check
mv "$server" "$tmp_dir/server.py"
expect_failure 'missing dashboard source passed validation'
mv "$tmp_dir/server.py" "$server"
ln -s "$tmp_dir/absent" "$app_dir/.git"
expect_failure 'dangling VCS symlink passed validation'
rm "$app_dir/.git"
printf 'Initial password: {generated_password}\n' >"$server"
expect_failure 'password logging source passed validation'
printf '# reviewed dashboard source\n' >"$server"
mkdir -p "$app_dir/.git"
: >"$app_dir/.git/config"
bsdtar -cf "$archive" -C "$tmp_dir/payload" opt
rm -rf "$app_dir/.git"
expect_failure 'archive VCS state passed validation'
printf 'not an archive\n' >"$archive"
expect_failure 'invalid archive passed validation'
printf 'PASS: package validation rejects missing source, VCS links/state and password logging.\n'
