#!/usr/bin/env bash
# Verify that an instance has one runtime root and that legacy home data is
# migrated without overwriting canonical paths.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

SYSTEM_ROOT="$tmp_dir/instances"
CONFIG_DIR="$tmp_dir/config"
APP_DIR="$tmp_dir/app"
CACHE_DIR="$tmp_dir/cache"
mkdir -p "$SYSTEM_ROOT" "$CONFIG_DIR" "$APP_DIR" "$CACHE_DIR"

. "$repo_dir/astrbotctl.functions"

assert_path() {
    local actual="$1" expected="$2" label="$3"
    [[ "$actual" == "$expected" ]] || {
        printf 'FAIL: %s: expected %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    }
}

instance=main
ASTRBOT_ROOT="$SYSTEM_ROOT/$instance"
mkdir -p "$ASTRBOT_ROOT/home/data"
printf 'legacy-data\n' >"$ASTRBOT_ROOT/home/data/legacy.txt"
printf 'ASTRBOT_ROOT=%q\n' "$ASTRBOT_ROOT" >"$CONFIG_DIR/$instance.conf"

load_instance_config
setup_runtime_env
ensure_runtime_dirs

assert_path "$HOME" "$ASTRBOT_ROOT" 'HOME'
assert_path "$runtime_root" "$ASTRBOT_ROOT" 'runtime root'
assert_path "$XDG_CACHE_HOME" "$ASTRBOT_ROOT/.cache" 'XDG cache'
assert_path "$XDG_CONFIG_HOME" "$ASTRBOT_ROOT/.config" 'XDG config'
assert_path "$XDG_DATA_HOME" "$ASTRBOT_ROOT/.local/share" 'XDG data'
assert_path "$XDG_STATE_HOME" "$ASTRBOT_ROOT/.local/state" 'XDG state'
[[ -f "$ASTRBOT_ROOT/data/legacy.txt" ]] || exit 1
[[ ! -e "$ASTRBOT_ROOT/home" ]] || exit 1
[[ "$(sed -n '1p' "$ASTRBOT_ROOT/.env")" == "HOME=$ASTRBOT_ROOT" ]] || exit 1

instance=conflict
ASTRBOT_ROOT="$SYSTEM_ROOT/$instance"
mkdir -p "$ASTRBOT_ROOT/home/data" "$ASTRBOT_ROOT/data"
printf 'canonical\n' >"$ASTRBOT_ROOT/data/canonical.txt"
printf 'legacy\n' >"$ASTRBOT_ROOT/home/data/legacy.txt"
setup_runtime_env

[[ "$(cat "$ASTRBOT_ROOT/data/canonical.txt")" == canonical ]] || exit 1
[[ -f "$ASTRBOT_ROOT/home/data/legacy.txt" ]] || exit 1

printf 'PASS: instance paths use one root and protect conflicting legacy data.\n'
