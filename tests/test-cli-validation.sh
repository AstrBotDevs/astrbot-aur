#!/usr/bin/env bash
# Rootless public-CLI tests. System operations are replaced in an isolated copy.
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
chown() { :; }
ss() { :; }
systemctl() { printf '%s\n' "$*" >>"$TEST_SYSTEM_CALLS"; return 1; }
STUBS
export SYSTEM_ROOT="$tmp_dir/data" CONFIG_DIR="$tmp_dir/etc" CACHE_DIR="$tmp_dir/cache"
export TEST_SYSTEM_CALLS="$tmp_dir/system-calls"
mkdir -p "$SYSTEM_ROOT" "$CONFIG_DIR" "$CACHE_DIR"
cp "$repo_dir/tmpl.conf" "$CONFIG_DIR/tmpl.conf"
controller="$tmp_dir/astrbotctl"

for command in init rm reset certbot run cli paths start stop restart enable disable status password sync update __run_astrbot; do
    if bash "$controller" "$command" '../escape' >"$tmp_dir/output" 2>&1; then
        fail "$command accepted a traversal name"
    fi
    grep -Fq 'Invalid instance name' "$tmp_dir/output" || fail "$command skipped validation"
done
if bash "$controller" __certbot-deploy valid '../escape' >"$tmp_dir/output" 2>&1; then
    fail 'deploy accepted a traversal certificate name'
fi
[[ ! -e "$TEST_SYSTEM_CALLS" ]] || fail 'invalid input reached systemctl'

mkdir -p "$SYSTEM_ROOT/source/.venv/bin"
printf 'source data\n' >"$SYSTEM_ROOT/source/payload"
printf 'absolute source entrypoint\n' >"$SYSTEM_ROOT/source/.venv/bin/astrbot"
: >"$SYSTEM_ROOT/source/.venv-maintenance.lock"
printf 'ASTRBOT_PORT="3000"\n' >"$CONFIG_DIR/source.conf"
bash "$controller" cp source destination >"$tmp_dir/output" 2>&1 || {
    cat "$tmp_dir/output"
    fail 'documented cp invocation failed'
}
cmp "$SYSTEM_ROOT/source/payload" "$SYSTEM_ROOT/destination/payload"
[[ ! -e "$SYSTEM_ROOT/destination/.venv" ]] || fail 'copied a non-relocatable venv'
[[ ! -e "$SYSTEM_ROOT/destination/.venv-maintenance.lock" ]] || fail 'copied a maintenance lock'
[[ -e "$SYSTEM_ROOT/source/.venv/bin/astrbot" ]] || fail 'modified the source venv'

for args in 'source' 'source destination extra' 'source ../escape' '../escape destination'; do
    read -r -a arguments <<<"$args"
    if bash "$controller" cp "${arguments[@]}" >"$tmp_dir/output" 2>&1; then
        fail "cp accepted invalid arguments: $args"
    fi
done
printf 'existing config\n' >"$CONFIG_DIR/orphan.conf"
if bash "$controller" init orphan >"$tmp_dir/output" 2>&1; then
    fail 'init overwrote orphan configuration'
fi
[[ $(<"$CONFIG_DIR/orphan.conf") == 'existing config' && ! -e "$SYSTEM_ROOT/orphan" ]] || fail 'init changed orphan paths'
mv "$CONFIG_DIR/tmpl.conf" "$tmp_dir/template"
if bash "$controller" init missing-template >"$tmp_dir/output" 2>&1; then
    fail 'init accepted a missing template'
fi
[[ ! -e "$SYSTEM_ROOT/missing-template" ]] || fail 'init left data behind on missing template'
printf 'PASS: public CLI validates paths, copies instances, and preserves existing configuration.\n'
