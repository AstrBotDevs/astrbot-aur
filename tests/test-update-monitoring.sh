#!/usr/bin/env bash
# Simulated services and clock: no privilege, network, or real systemd operations.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
cp "$repo_dir/astrbotctl" "$repo_dir/astrbotctl.functions" "$tmp_dir/"
cat >>"$tmp_dir/astrbotctl.functions" <<'STUBS'
require_root() { :; }
acquire_venv_maintenance_lock() { return "${TEST_LOCK_STATUS:-0}"; }
release_venv_maintenance_lock() { :; }
ensure_instance_env_synced() {
    printf 'sync %s\n' "$instance" >>"$TEST_EVENTS"
    [[ $instance != "${TEST_SYNC_FAILURE:-}" ]] || return 42
    mkdir -p "$(venv_dir)"
}
restore_venv_backup_atomically() { printf 'rollback %s\n' "$instance" >>"$TEST_EVENTS"; return 1; }
systemctl() {
    local unit="${*: -1}" name tick
    name="${unit#astrbot@}"
    tick=$(<"$TEST_TICK")
    printf '%s %s %s\n' "$1" "$name" "$tick" >>"$TEST_EVENTS"
    case "$1" in
    is-active)
        [[ $(<"$SYSTEM_ROOT/$name/state") == active ]] || return 1
        [[ $name != bot-one || $tick -lt 1 ]] || return 1
        [[ $name != one || $tick -lt 2 ]] || return 1
        ;;
    stop) printf 'inactive\n' >"$SYSTEM_ROOT/$name/state" ;;
    start) printf 'active\n' >"$SYSTEM_ROOT/$name/state" ;;
    *) return 1 ;;
    esac
}
sleep() { printf '%s\n' "$(( $(<"$TEST_TICK") + 1 ))" >"$TEST_TICK"; }
rm() {
    if [[ ${TEST_REMOVE_FAIL:-0} == 1 && ${*: -1} == "$SYSTEM_ROOT/one/.venv" ]]; then
        return 23
    fi
    command rm "$@"
}
STUBS
export SYSTEM_ROOT="$tmp_dir/data" CONFIG_DIR="$tmp_dir/etc" CACHE_DIR="$tmp_dir/cache" APP_DIR="$tmp_dir/app"
export TEST_EVENTS="$tmp_dir/events" TEST_TICK="$tmp_dir/tick" UPDATE_AUTO_ROLLBACK=0
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
controller="$tmp_dir/astrbotctl"

reset_case() {
    : >"$TEST_EVENTS"
    printf '0\n' >"$TEST_TICK"
    for name in bot-one one; do
        mkdir -p "$SYSTEM_ROOT/$name/.venv"
        printf 'active\n' >"$SYSTEM_ROOT/$name/state"
        : >"$CONFIG_DIR/$name.conf"
    done
}

for first_failure in rebuild stability; do
    reset_case
    export TEST_SYNC_FAILURE=""
    expected_status=1
    if [[ $first_failure == rebuild ]]; then
        TEST_SYNC_FAILURE=bot-one
        expected_status=42
    fi
    status=0
    bash "$controller" update --all --stability-secs 3 >"$tmp_dir/output" 2>&1 || status=$?
    [[ $status -eq $expected_status ]] || {
        cat "$tmp_dir/output"
        fail "$first_failure returned $status"
    }
    grep -Fq 'Instance one crashed at 2s.' "$tmp_dir/output" || {
        cat "$tmp_dir/output"
        fail 'a different failure truncated monitoring'
    }
    grep -qx 'rollback one' "$TEST_EVENTS" || fail 'failed to roll back the second instance'
    awk '/^stop one 2$/ { stopped=1 } /^rollback one$/ { exit !stopped }' "$TEST_EVENTS" || fail 'rollback did not cancel pending service restarts'
done

reset_case
for seconds in -1 garbage 1.5 1000000; do
    if bash "$controller" update one --stability-secs "$seconds" >"$tmp_dir/output" 2>&1; then
        fail "accepted invalid duration: $seconds"
    fi
done
for command in sync update; do
    if bash "$controller" "$command" one --all >"$tmp_dir/output" 2>&1; then
        fail "$command accepted both instance and --all"
    fi
done
[[ ! -s "$TEST_EVENTS" ]] || fail 'invalid options reached systemctl'

reset_case
printf 'inactive\n' >"$SYSTEM_ROOT/one/state"
bash "$controller" update one --stability-secs 08 >"$tmp_dir/output" 2>&1 || fail 'decimal duration with leading zero was rejected'
[[ $(<"$TEST_TICK") == 0 ]] || fail 'waited for an instance that was never active'

reset_case
if TEST_REMOVE_FAIL=1 bash "$controller" update one --stability-secs 0 >"$tmp_dir/output" 2>&1; then
    fail 'update ignored a failed virtualenv removal'
fi
if grep -qx 'sync one' "$TEST_EVENTS"; then
    fail 'update synced after virtualenv removal failed'
fi
for command in sync update; do
    : >"$CONFIG_DIR/missing.conf"
    if bash "$controller" "$command" missing >"$tmp_dir/output" 2>&1; then
        fail "$command reported success for missing instance data"
    fi
done
printf 'PASS: update monitors every instance independently and rejects invalid options.\n'
