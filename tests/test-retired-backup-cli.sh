#!/usr/bin/env bash
# Exercise the public compatibility tombstones without creating an instance.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
astrbotctl_bin="${ASTRBOTCTL_BIN:-$repo_dir/astrbotctl}"
tmp_dir="$(mktemp -d)"
readonly tmp_dir
readonly instance="codex-retired-${$}"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_expect_tombstone() {
    local label="$1"
    shift
    local output status
    set +e
    output="$(SYSTEM_ROOT="$tmp_dir/data" CONFIG_DIR="$tmp_dir/etc" CACHE_DIR="$tmp_dir/cache" \
        bash "$astrbotctl_bin" "$@" 2>&1)"
    status=$?
    set -e

    [[ "$status" -eq 2 ]] || fail "$label exited $status instead of 2"
    grep -Eq 'Dashboard backup|astrbotctl password' <<<"$output" ||
        fail "$label did not provide actionable migration guidance"
    [[ ! -e "$tmp_dir/data/$instance" && ! -e "$tmp_dir/etc/$instance.conf" ]] ||
        fail "$label mutated the isolated instance paths"
}

run_expect_tombstone 'init --backup' init --backup "$tmp_dir/missing.zip" "$instance"
run_expect_tombstone export export "$instance"
run_expect_tombstone import import "$instance" "$tmp_dir/missing.zip"
run_expect_tombstone admin admin "$instance"

printf 'PASS: retired backup and credential commands fail before mutating instance state.\n'
