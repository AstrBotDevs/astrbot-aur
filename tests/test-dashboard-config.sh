#!/usr/bin/env bash
# JSON updates must work without an activated venv and never write through links.
# shellcheck disable=SC2034 # Configuration globals are consumed by the library.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
# shellcheck source=../astrbotctl.functions
source "$repo_dir/astrbotctl.functions"
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
expect_status() {
    local expected="$1" status=0
    shift
    "$@" >"$tmp_dir/output" 2>&1 || status=$?
    [[ $status == "$expected" ]] || {
        cat "$tmp_dir/output"
        fail "expected $expected, got $status"
    }
}
id() { if [[ ${1:-} == -u ]]; then printf '1000\n'; else return 1; fi; }
instance=dashboard
ASTRBOT_ROOT="$tmp_dir/instance with spaces"
config="$ASTRBOT_ROOT/data/cmd_config.json"
mkdir -p "$(dirname "$config")"
unset UV_PROJECT_ENVIRONMENT VIRTUAL_ENV
ASTRBOT_PORT=03001 ASTRBOT_HOST=127.0.0.1 ASTRBOT_SSL_ENABLE=yes ASTRBOT_DASHBOARD_ENABLE=1
printf '\357\273\277{"dashboard":{"pbkdf2_password":"keep-existing-hash"},"plugins":["keep"]}\n' >"$config"
# Isolated system Python must not import a module from the instance directory.
printf 'raise RuntimeError("untrusted local module imported")\n' >"$ASTRBOT_ROOT/json.py"
(
    cd "$ASTRBOT_ROOT"
    sync_cmd_config
)
python -I - "$config" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    data = json.load(stream)
assert data["dashboard"]["port"] == 3001
assert data["dashboard"]["enable"] is True
assert data["dashboard"]["ssl"]["enable"] is True
assert data["dashboard"]["pbkdf2_password"] == "keep-existing-hash"
assert data["plugins"] == ["keep"]
PY
[[ $(stat -c %a "$config") == 600 ]] || fail 'dashboard credentials are not private'
printf 'PRESERVE\n' >"$tmp_dir/sentinel"
ln -s "$tmp_dir/sentinel" "$config.tmp"
sync_cmd_config
[[ $(<"$tmp_dir/sentinel") == PRESERVE && -L "$config.tmp" ]] || fail 'used an unsafe fixed temporary path'
cp "$config" "$tmp_dir/valid.json"
(
    mv() { return 42; }
    expect_status 42 sync_cmd_config
)
cmp "$config" "$tmp_dir/valid.json"
ASTRBOT_PORT=bad
expect_status 2 sync_cmd_config
cmp "$config" "$tmp_dir/valid.json"
ASTRBOT_PORT=3001
printf '{invalid JSON\n' >"$config"
expect_status 1 sync_cmd_config
[[ $(<"$config") == '{invalid JSON' ]] || fail 'parse failure truncated config'
rm "$config"
ln -s "$tmp_dir/sentinel" "$config"
expect_status 1 sync_cmd_config
[[ $(<"$tmp_dir/sentinel") == PRESERVE ]] || fail 'followed config symlink'
rm "$config"
cp "$tmp_dir/valid.json" "$config"
(
    id() { if [[ ${1:-} == -u ]]; then printf '0\n'; else return 0; fi; }
    runuser() { printf '%s\n' "$@" >"$tmp_dir/worker-args"; }
    _write_dashboard_config() { fail 'root ran the JSON transformer'; }
    sync_cmd_config
    grep -qx astrbot "$tmp_dir/worker-args" || fail 'writer did not drop privileges'
    grep -qx _write_dashboard_config "$tmp_dir/worker-args" || fail 'transformer was not delegated to the service user'
)
for temporary in "$ASTRBOT_ROOT/data"/.cmd_config.json.??????; do
    [[ ! -e "$temporary" ]] || fail 'temporary file leaked'
done
printf 'PASS: dashboard JSON preserves credentials, uses atomic writes, and does not require a venv.\n'
