#!/usr/bin/env bash
# Rootless fixtures only: no sudo, service commands, package writes or network.
# shellcheck disable=SC2034 # Fixture globals are consumed by sourced helpers.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
# shellcheck source=../astrbotctl.functions
. "$repo_dir/astrbotctl.functions"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
expect_status() {
    local expected="$1" actual=0
    shift
    if "$@"; then actual=0; else actual=$?; fi
    [[ "$actual" == "$expected" ]] || fail "expected $expected, got $actual: $*"
}
assert_no_temps() {
    local path
    for path in "$1"/.*.??????; do
        [[ ! -e "$path" ]] || fail "temporary file leaked: $path"
    done
}
# Exercise the ordinary-user branch even when a CI container happens to be root.
id() {
    case "${1:-}" in
    -u) printf '1000\n' ;;
    astrbot) return 1 ;;
    *) command id "$@" ;;
    esac
}

(
    instance=environment
    ASTRBOT_ROOT="$tmp_dir/root with spaces"
    CACHE_DIR="$tmp_dir/cache"
    unset no_proxy
    http_proxy='http://user:p&a"ss\\$(printf WRONG)`printf WRONG`@proxy.invalid'
    https_proxy=$'https://proxy.invalid/line\nsecond'
    expected_proxy="$http_proxy"
    expected_https="$https_proxy"
    setup_runtime_env
    [[ -f "$ASTRBOT_ROOT/.env" && ! -L "$ASTRBOT_ROOT/.env" ]] || fail 'env was not created'
    [[ $(stat -c %a "$ASTRBOT_ROOT/.env") == 600 ]] || fail 'env credentials are not private'
    _runuser_with_env "$ASTRBOT_ROOT/.env" "$ASTRBOT_ROOT" bash -c \
        '[[ "$http_proxy" == "$1" && "$https_proxy" == "$2" && -z "$no_proxy" && "$HOME" == "$3" && "$ASTRBOT_HOME" == "$HOME" ]]' \
        bash "$expected_proxy" "$expected_https" "$ASTRBOT_ROOT"
    # Same assertion for an explicit empty final optional value.
    no_proxy=''
    setup_runtime_env
    before="$(<"$ASTRBOT_ROOT/.env")"
    (
        mv() { return 42; }
        expect_status 42 generate_env_file
    )
    [[ "$(<"$ASTRBOT_ROOT/.env")" == "$before" ]] || fail 'failed env publication destroyed original'
    assert_no_temps "$ASTRBOT_ROOT"
    rm -- "$ASTRBOT_ROOT/.env"
    printf 'PRESERVE\n' >"$tmp_dir/env-sentinel"
    ln -s "$tmp_dir/env-sentinel" "$ASTRBOT_ROOT/.env"
    expect_status 1 generate_env_file
    expect_status 1 setup_runtime_env
    _runuser_with_env() { fail 'command ran after setup failure'; }
    _ensure_app_dir() { fail 'sync ran after setup failure'; }
    expect_status 1 run_astrbot_env_cmd true
    expect_status 1 ensure_instance_env_synced
    expect_status 1 run_astrbot run
    [[ "$(<"$tmp_dir/env-sentinel")" == PRESERVE && -L "$ASTRBOT_ROOT/.env" ]] || fail 'env symlink target was overwritten'
    assert_no_temps "$ASTRBOT_ROOT"
)

(
    # The privilege-drop command itself is mocked; no user switch is performed.
    id() { if [[ ${1:-} == -u ]]; then printf '0\n'; else return 0; fi; }
    unset ASTRBOT_PRIVDROP_DONE
    runuser() { printf '%s\n' "$@" >"$tmp_dir/runuser-args"; }
    _runuser_with_env "$tmp_dir/unused-env" "$tmp_dir" true
    grep -qx bash "$tmp_dir/runuser-args" || fail 'privilege drop did not use Bash'
    ! grep -qx sh "$tmp_dir/runuser-args" || fail 'privilege drop still used sh'

    ASTRBOT_ROOT="$tmp_dir/root-writer"
    CACHE_DIR="$tmp_dir/cache"
    runuser() {
        printf '%s\n' "$@" >"$tmp_dir/writer-args"
        command cat >"$tmp_dir/writer-input"
    }
    _atomic_replace_file() { fail 'root opened output in a service-writable directory'; }
    setup_runtime_env
    grep -qx astrbot "$tmp_dir/writer-args" || fail 'env writer did not drop privileges'
    grep -qx "$repo_dir/astrbotctl.functions" "$tmp_dir/writer-args" || fail 'writer did not use the trusted library'
    bash -c '. "$1"; [[ "$ASTRBOT_ROOT" == "$2" ]]' bash "$tmp_dir/writer-input" "$ASTRBOT_ROOT" || fail 'worker received invalid runtime assignments'
    [[ ! -e "$ASTRBOT_ROOT/.env" ]] || fail 'parent wrote env before privilege drop'
    runuser() {
        command cat >"$tmp_dir/writer-input"
        return 42
    }
    expect_status 42 generate_env_file
)

make_venv() {
    mkdir -p "$1/bin"
    printf 'fixture\n' >"$1/pyvenv.cfg"
    printf '#!/bin/bash\nexit 0\n' >"$1/bin/python"
    cp "$1/bin/python" "$1/bin/astrbot"
    chmod +x "$1/bin/python" "$1/bin/astrbot"
    printf '%s\n' "$2" >"$1/.astrbot-app-version"
}
(
    instance=rollback
    ASTRBOT_ROOT="$tmp_dir/rollback"
    mkdir -p "$ASTRBOT_ROOT"
    chown() { return 0; } # Only ownership changes are mocked.
    make_venv "$ASTRBOT_ROOT/.venv" current
    make_venv "$ASTRBOT_ROOT/backup" old
    printf 'PRESERVE\n' >"$tmp_dir/marker-sentinel"
    marker="$ASTRBOT_ROOT/backup/.astrbot-rollback"
    ln -s "$tmp_dir/marker-sentinel" "$marker"
    expect_status 1 write_venv_rollback_marker "$ASTRBOT_ROOT/backup" sync_failure
    expect_status 1 create_venv_backup "$ASTRBOT_ROOT/backup" "$ASTRBOT_ROOT/copy"
    expect_status 1 restore_venv_backup_atomically "$ASTRBOT_ROOT/.venv" "$ASTRBOT_ROOT/backup" sync_failure
    [[ "$(<"$tmp_dir/marker-sentinel")" == PRESERVE ]] || fail 'marker followed symlink'
    [[ "$(<"$ASTRBOT_ROOT/.venv/.astrbot-app-version")" == current ]] || fail 'invalid backup was published'
    rm -- "$marker"
    mkdir "$marker"
    expect_status 1 write_venv_rollback_marker "$ASTRBOT_ROOT/backup" sync_failure
    rmdir "$marker"
    (
        # A marker introduced during the copy must also be rejected in stage.
        cp() {
            local target="${!#}"
            command cp "$@" || return $?
            ln -s "$tmp_dir/marker-sentinel" "$target/.astrbot-rollback"
        }
        expect_status 1 restore_venv_backup_atomically "$ASTRBOT_ROOT/.venv" "$ASTRBOT_ROOT/backup" sync_failure
    )
    [[ "$(<"$tmp_dir/marker-sentinel")" == PRESERVE ]] || fail 'stage marker followed symlink'
    [[ "$(<"$ASTRBOT_ROOT/.venv/.astrbot-app-version")" == current ]] || fail 'invalid stage was published'
    umask 077
    original_umask="$(umask)"
    write_venv_rollback_marker "$ASTRBOT_ROOT/backup" sync_failure
    [[ "$(umask)" == "$original_umask" ]] || fail 'marker writer changed caller umask'
    [[ "$(stat -c %a "$marker")" == 644 ]] || fail 'marker permissions wrong'
    venv_rollback_marker_is_valid "$ASTRBOT_ROOT/backup"
    before="$(<"$marker")"
    (
        chown() { return 42; }
        expect_status 42 write_venv_rollback_marker "$ASTRBOT_ROOT/backup" update_failure
    )
    [[ "$(<"$marker")" == "$before" ]] || fail 'failed marker write destroyed original'
    assert_no_temps "$ASTRBOT_ROOT/backup"
    assert_no_temps "$ASTRBOT_ROOT"
)

(
    instance=firstlock
    ASTRBOT_ROOT="$tmp_dir/firstlock"
    mkdir -p "$ASTRBOT_ROOT"
    lock_file="$(venv_maintenance_lock_file)"
    # Deterministically win creation between the absence check and O_EXCL open.
    # Python then executes the real creation protocol against this held inode.
    python() {
        [[ "$2" == "$lock_file" ]] || fail 'unexpected Python invocation'
        printf 'existing-lock\n' >"$lock_file"
        exec {holder_fd}<"$lock_file"
        flock -s -n "$holder_fd"
        held_inode="$(stat -c %i "$lock_file")"
        command python "$@"
    }
    ensure_venv_maintenance_lock_file
    [[ "$(stat -c %i "$lock_file")" == "$held_inode" ]] || fail 'creation replaced held inode'
    [[ "$(<"$lock_file")" == existing-lock ]] || fail 'creation truncated existing lock'
    expect_status 75 acquire_venv_maintenance_lock
    [[ "$(stat -c %i "$lock_file")" == "$held_inode" ]] || fail 'acquire replaced held inode'
    exec {holder_fd}<&-
    acquire_venv_maintenance_lock
    release_venv_maintenance_lock
    unset -f python
    rm -- "$lock_file"
    ensure_venv_maintenance_lock_file
    [[ -f "$lock_file" && ! -L "$lock_file" ]] || fail 'first creation failed'
    rm -- "$lock_file"
    ln -s "$tmp_dir/marker-sentinel" "$lock_file"
    expect_status 1 ensure_venv_maintenance_lock_file
    rm -- "$lock_file"
    mkfifo "$lock_file"
    expect_status 1 ensure_venv_maintenance_lock_file
    rm -- "$lock_file"
    _create_venv_maintenance_lock_file() { return 42; }
    expect_status 42 acquire_venv_maintenance_lock
)
printf 'PASS: runtime quoting, setup failures, symlink refusal, marker staging and first-lock safety.\n'
