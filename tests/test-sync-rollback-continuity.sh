#!/usr/bin/env bash
# Exercise the public sync lifecycle with fake systemctl/uv seams.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_case() {
    local label="$1" initially_active="$2" uv_status="$3" start_status="$4" expected_status="$5" expected_starts="$6"
    local case_dir="$tmp_dir/$label" root="$tmp_dir/$label/root" config_dir="$tmp_dir/$label/etc" cache_dir="$tmp_dir/$label/cache" app_dir="$tmp_dir/$label/app" fake_bin="$tmp_dir/$label/bin"
    local instance="sync-$label" state_file="$case_dir/state" calls_file="$case_dir/calls" output_file="$case_dir/output"

    mkdir -p "$root" "$config_dir" "$cache_dir" "$app_dir" "$fake_bin"
    if [[ "$label" != active_no_backup ]]; then
        mkdir -p "$root/.venv/bin"
        : >"$root/.venv/bin/python"
        : >"$root/.venv/bin/astrbot"
        : >"$root/.venv/pyvenv.cfg"
        chmod +x "$root/.venv/bin/python" "$root/.venv/bin/astrbot"
    fi
    if [[ "$label" != active_no_backup ]]; then
        printf 'old-version\n' >"$root/.venv/.astrbot-app-version"
        chown -R astrbot:astrbot "$root/.venv"
    fi
    printf 'new-version\n' >"$app_dir/.version"
    : >"$app_dir/pyproject.toml"
    printf 'ASTRBOT_ROOT=%q\n' "$root" >"$config_dir/$instance.conf"
    printf '%s\n' "$initially_active" >"$state_file"

    cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state_file=${FAKE_STATE_FILE:?}
calls_file=${FAKE_CALLS_FILE:?}
printf '%s %s\n' "$1" "${*: -1}" >>"$calls_file"
case "$1" in
is-active)
    [[ $(cat "$state_file") == active ]]
    ;;
stop)
    printf 'inactive\n' >"$state_file"
    ;;
start)
    if [[ ${FAKE_START_STATUS:?} -eq 0 ]]; then printf 'active\n' >"$state_file"; fi
    exit "$FAKE_START_STATUS"
    ;;
*) exit 1 ;;
esac
EOF
    cat >"$fake_bin/uv" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_UV_STATUS:?}"
EOF
    chmod +x "$fake_bin/systemctl" "$fake_bin/uv"

    set +e
    PATH="$fake_bin:$PATH" \
        ASTRBOT_PRIVDROP_DONE=1 \
        SYSTEM_ROOT="$tmp_dir/unused-root" CONFIG_DIR="$config_dir" CACHE_DIR="$cache_dir" APP_DIR="$app_dir" \
        ROLLBACK_HEALTH_SECS=0 FAKE_STATE_FILE="$state_file" FAKE_CALLS_FILE="$calls_file" FAKE_UV_STATUS="$uv_status" FAKE_START_STATUS="$start_status" \
        bash "$repo_dir/astrbotctl" sync "$instance" >"$output_file" 2>&1
    observed_status=$?
    set -e

    if [[ "$observed_status" -ne "$expected_status" ]]; then
        cat "$output_file" >&2
        fail "$label returned $observed_status, expected $expected_status"
    fi
    [[ $(grep -c '^start astrbot@' "$calls_file" || true) -eq "$expected_starts" ]] || fail "$label start count mismatch"
    if [[ "$expected_starts" -eq 1 && "$uv_status" -ne 0 && "$label" != active_no_backup ]]; then
        [[ -f "$root/.venv/.astrbot-rollback" ]] || fail "$label did not atomically publish rollback marker"
    fi
    if [[ "$expected_starts" -eq 1 && "$start_status" -ne 0 ]]; then
        grep -Fq 'Failed to restart' "$output_file" || fail "$label did not report restart failure"
        [[ -d "$cache_dir/update-snapshots/${instance}-venv-backup" ]] || fail "$label removed backup after restored-service start failure"
        find "$root" -maxdepth 1 -type d -name '.venv.rollback.*' -print -quit | grep -q . || fail "$label removed exchanged venv after start failure"
    fi
    flock -n "$root/.venv-maintenance.lock" true || fail "$label leaked maintenance lock"
}

# The observed pkgrel2->3 outage is the first case: a rollback must restore a
# previously active exact unit but must still report the original sync failure.
run_case active_rollback_ok active 42 0 42 1
run_case inactive_rollback_ok inactive 42 0 42 0
run_case active_no_backup active 42 0 42 0
run_case active_restart_fails active 42 9 42 1
run_case active_sync_success active 0 0 0 1

printf 'PASS: sync rollback preserves active-service continuity and original failures.\n'
