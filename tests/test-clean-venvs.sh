#!/usr/bin/env bash
# Real flock coverage in temporary paths; never contact the system service bus.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
export SYSTEM_ROOT="$tmp_dir/data" CONFIG_DIR="$tmp_dir/etc" CACHE_DIR="$tmp_dir/cache"
# shellcheck source=../astrbotctl.functions
source "$repo_dir/astrbotctl.functions"
systemctl() { [[ ${*: -1} == astrbot@active ]]; }

for name in active idle busy; do
    mkdir -p "$SYSTEM_ROOT/$name/.venv"
    : >"$SYSTEM_ROOT/$name/.venv/sentinel"
    : >"$SYSTEM_ROOT/$name/.venv-maintenance.lock"
done
mkdir -p "$tmp_dir/outside/.venv"
ln -s "$tmp_dir/outside" "$SYSTEM_ROOT/symlink"
exec {held_lock}>"$SYSTEM_ROOT/busy/.venv-maintenance.lock"
flock -n "$held_lock"
if clean_instance_venvs >"$tmp_dir/output" 2>&1; then
    fail 'cleanup reported success despite busy/active instances'
fi
[[ ! -e "$SYSTEM_ROOT/idle/.venv" ]] || fail 'idle venv was not cleaned'
[[ -f "$SYSTEM_ROOT/active/.venv/sentinel" ]] || fail 'active venv was deleted'
[[ -f "$SYSTEM_ROOT/busy/.venv/sentinel" ]] || fail 'locked venv was deleted'
[[ -d "$tmp_dir/outside/.venv" ]] || fail 'cleanup followed a root symlink'
[[ -f "$SYSTEM_ROOT/idle/.venv-maintenance.lock" ]] || fail 'cleanup unlinked a maintenance lock'
flock -u "$held_lock"
exec {held_lock}>&-
systemctl() { return 1; }
clean_instance_venvs
[[ ! -e "$SYSTEM_ROOT/active/.venv" && ! -e "$SYSTEM_ROOT/busy/.venv" ]] || fail 'unlocked idle venvs were not cleaned'
printf 'PASS: cleanup preserves active/locked venvs and does not traverse root symlinks.\n'
