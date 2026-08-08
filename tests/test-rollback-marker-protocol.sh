#!/usr/bin/env bash
# Exercise the real ensure decision with a controlled dependency seam.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# shellcheck source=../astrbotctl.functions
. "$repo_dir/astrbotctl.functions"
instance=marker
ASTRBOT_ROOT="$tmp_dir/root"
APP_DIR="$tmp_dir/app"
mkdir -p "$ASTRBOT_ROOT/.venv/bin" "$APP_DIR"
: >"$ASTRBOT_ROOT/.venv/bin/python"; : >"$ASTRBOT_ROOT/.venv/bin/astrbot"; : >"$ASTRBOT_ROOT/.venv/pyvenv.cfg"
chmod +x "$ASTRBOT_ROOT/.venv/bin/python" "$ASTRBOT_ROOT/.venv/bin/astrbot"
printf 'old-version\n' >"$ASTRBOT_ROOT/.venv/.astrbot-app-version"
printf 'version=old-version\nreason=sync_failure\n' >"$ASTRBOT_ROOT/.venv/.astrbot-rollback"
printf 'new-version\n' >"$APP_DIR/.version"
: >"$APP_DIR/pyproject.toml"
chown -R astrbot:astrbot "$ASTRBOT_ROOT/.venv"

calls=0
setup_runtime_env() { UV_PROJECT_ENVIRONMENT="$ASTRBOT_ROOT/.venv"; runtime_root="$ASTRBOT_ROOT"; }
_ensure_app_dir() { :; }
run_astrbot_env_cmd() { calls=$((calls + 1)); return "${RUNNER_STATUS:-0}"; }
_runuser_with_env() { return 0; }

RUNNER_STATUS=42
ensure_instance_env_synced || fail 'valid rollback marker did not bypass automatic sync'
[[ "$calls" -eq 0 ]] || fail 'automatic run invoked dependency sync despite rollback marker'

if ensure_instance_env_synced --force; then fail 'forced sync unexpectedly succeeded'; fi
[[ "$calls" -eq 1 && -f "$ASTRBOT_ROOT/.venv/.astrbot-rollback" ]] || fail 'failed forced sync did not retain rollback marker'

RUNNER_STATUS=0
ensure_instance_env_synced --force || fail 'successful forced sync failed'
[[ "$calls" -eq 2 && ! -e "$ASTRBOT_ROOT/.venv/.astrbot-rollback" ]] || fail 'successful forced sync did not clear marker'

ln -s /dev/null "$ASTRBOT_ROOT/.venv/.astrbot-rollback"
if ensure_instance_env_synced; then fail 'invalid marker was accepted'; fi
[[ "$calls" -eq 2 ]] || fail 'invalid marker reached dependency runner'
printf 'PASS: rollback marker bypasses only automatic sync and forced retry clears it on success.\n'
