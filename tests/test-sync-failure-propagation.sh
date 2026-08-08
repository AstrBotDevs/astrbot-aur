#!/usr/bin/env bash
# Exercise the real sync function under caller-style conditional errexit context.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
readonly tmp_dir
readonly failure_status=42
calls_file="$tmp_dir/calls"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# shellcheck disable=SC1091
. "$repo_dir/astrbotctl.functions"

# shellcheck disable=SC2034 # Consumed by the sourced sync function.
instance=sync-failure
ASTRBOT_ROOT="$tmp_dir/root"
UV_PROJECT_ENVIRONMENT="$ASTRBOT_ROOT/.venv"
APP_DIR="$tmp_dir/app"
mkdir -p "$ASTRBOT_ROOT" "$APP_DIR"

setup_runtime_env() {
    :
}

_ensure_app_dir() {
    :
}

current_app_version() {
    printf 'test-version\n'
}

run_astrbot_env_cmd() {
    printf '%s\n' "$*" >>"$calls_file"
    return "$failure_status"
}

# This is the production caller pattern: a function failure is tested in a
# conditional, where errexit alone would otherwise be suppressed.
if ensure_instance_env_synced; then
    fail 'sync unexpectedly succeeded'
else
    observed_status=$?
fi

[[ "$observed_status" -eq "$failure_status" ]] ||
    fail "sync returned $observed_status instead of $failure_status"
[[ "$(wc -l <"$calls_file")" -eq 1 ]] ||
    fail 'sync continued after the failing virtualenv command'
grep -Fq 'uv venv' "$calls_file" || fail 'test did not reach the virtualenv seam'
[[ ! -e "$UV_PROJECT_ENVIRONMENT/bin/astrbot" ]] ||
    fail 'sync fabricated a missing astrbot entrypoint after failure'

printf 'PASS: sync propagates the original dependency failure without later steps.\n'
