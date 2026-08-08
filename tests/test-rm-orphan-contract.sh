#!/usr/bin/env bash
# Verify public astrbotctl rm safely handles an exact configless orphan root.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
readonly tmp_dir
readonly system_root="$tmp_dir/data"
readonly config_dir="$tmp_dir/etc"
readonly cache_dir="$tmp_dir/cache"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_rm() {
    SYSTEM_ROOT="$system_root" CONFIG_DIR="$config_dir" CACHE_DIR="$cache_dir" \
        bash "$repo_dir/astrbotctl" rm "$@"
}

mkdir -p "$system_root/orphan" "$system_root/configured" "$config_dir"
printf 'sentinel\n' >"$system_root/keep"
printf 'ASTRBOT_ROOT="/unsafe/ignored"\n' >"$config_dir/configured.conf"

set +e
invalid_output="$(run_rm '../escape' 2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -eq 1 ]] || fail "invalid name exited $invalid_status instead of 1"
grep -Fq 'Invalid instance name' <<<"$invalid_output" ||
    fail "invalid name did not fail closed"
[[ -d "$system_root/orphan" && -f "$system_root/keep" ]] ||
    fail "invalid name mutated an isolated path"

run_rm orphan
[[ ! -e "$system_root/orphan" && -f "$system_root/keep" ]] ||
    fail "configless orphan removal touched an unsafe path"

run_rm configured
[[ ! -e "$system_root/configured" && ! -e "$config_dir/configured.conf" ]] ||
    fail "configured removal did not remove its exact paths"
[[ -f "$system_root/keep" ]] || fail "configured removal touched an adjacent instance"

printf 'PASS: astrbotctl rm validates names and removes only exact orphan/configured paths.\n'
