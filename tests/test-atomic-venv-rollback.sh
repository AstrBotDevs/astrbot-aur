#!/usr/bin/env bash
# Exercise real atomic restore helpers entirely below a disposable directory.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
make_venv() {
    local path="$1" version="$2"
    mkdir -p "$path/bin"
    : >"$path/bin/python"
    : >"$path/bin/astrbot"
    : >"$path/pyvenv.cfg"
    chmod +x "$path/bin/python" "$path/bin/astrbot"
    printf '%s\n' "$version" >"$path/.astrbot-app-version"
    chown -R astrbot:astrbot "$path"
}

# Shared implementation is also checked by scripts/check.sh.
# shellcheck source=../astrbotctl.functions
. "$repo_dir/astrbotctl.functions"
ASTRBOT_ROOT="$tmp_dir/root"
mkdir -p "$ASTRBOT_ROOT" "$tmp_dir/cache"
destination="$ASTRBOT_ROOT/.venv"
backup="$tmp_dir/cache/backup"
make_venv "$destination" current
make_venv "$backup" old

restore_venv_backup_atomically "$destination" "$backup" sync_failure
[[ "$(cat "$destination/.astrbot-app-version")" = old ]] || fail 'exchange did not publish backup'
venv_rollback_marker_is_valid "$destination" || fail 'published rollback marker is invalid'
[[ -n "$ATOMIC_RESTORE_CONTAINER" && -d "$ATOMIC_RESTORE_CONTAINER" ]] || fail 'post-exchange recovery container was not preserved'
[[ "$(cat "$ATOMIC_RESTORE_EXCHANGED_PATH/.astrbot-app-version")" = current ]] || fail 'exchange did not preserve displaced current venv'
cleanup_atomic_restore_after_healthy "$backup"
[[ ! -e "$backup" && ! -e "$ATOMIC_RESTORE_CONTAINER" ]] || fail 'healthy cleanup did not remove exact recovery artifacts'

make_venv "$backup" old-again
rm -rf -- "$destination"
restore_venv_backup_atomically "$destination" "$backup" update_failure
[[ "$(cat "$destination/.astrbot-app-version")" = old-again ]] || fail 'absent destination publish failed'
cleanup_atomic_restore_after_healthy "$backup"

mkdir -p "$tmp_dir/invalid"
ln -s "$tmp_dir/invalid" "$tmp_dir/symlink-backup"
if restore_venv_backup_atomically "$destination" "$tmp_dir/symlink-backup" sync_failure; then
    fail 'symlink backup was accepted'
fi
[[ -d "$destination" && ! -L "$destination" ]] || fail 'invalid backup changed destination'

printf 'PASS: atomic restore exchanges same-filesystem venvs and fails closed.\n'
