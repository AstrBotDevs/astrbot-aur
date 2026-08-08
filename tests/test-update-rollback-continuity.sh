#!/usr/bin/env bash
# Drive public update through fake systemctl/uv seams for rebuild and crash rollback.
set -Eeuo pipefail
if [[ ${EUID} -ne 0 ]]; then exec sudo --preserve-env=PATH -- bash "$0" "$@"; fi
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"; tmp_dir="$(mktemp -d)"; trap 'rm -rf -- "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

run_case() {
    local label="$1" initially_active="$2" pip_status="$3" crash="$4" expected="$5"
    local root="$tmp_dir/$label/root" etc="$tmp_dir/$label/etc" cache="$tmp_dir/$label/cache" app="$tmp_dir/$label/app" bin="$tmp_dir/$label/bin"
    local state="$tmp_dir/$label/state" calls="$tmp_dir/$label/calls" uv_calls="$tmp_dir/$label/uv-calls" output="$tmp_dir/$label/output" status
    mkdir -p "$root/.venv/bin" "$etc" "$cache" "$app" "$bin"
    : >"$root/.venv/bin/python"; : >"$root/.venv/bin/astrbot"; : >"$root/.venv/pyvenv.cfg"
    chmod +x "$root/.venv/bin/python" "$root/.venv/bin/astrbot"; printf 'old\n' >"$root/.venv/.astrbot-app-version"; chown -R astrbot:astrbot "$root/.venv"
    : >"$app/pyproject.toml"; printf 'new\n' >"$app/.version"; printf 'ASTRBOT_ROOT=%q\n' "$root" >"$etc/$label.conf"; printf '%s\n' "$initially_active" >"$state"
    cat >"$bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
state=$(<"$FAKE_STATE"); printf '%s\n' "$1" >>"$FAKE_CALLS"
case "$1" in
is-active)
    if [[ ${FAKE_CRASH:?} == 1 && -e "$FAKE_STARTED" && ! -e "$FAKE_CRASHED" ]]; then
        : >"$FAKE_CRASHED"; state=inactive
    fi
    printf '%s\n' "$state" >"$FAKE_STATE"; [[ $state == active ]]
    ;;
stop) printf 'inactive\n' >"$FAKE_STATE";;
start) : >"$FAKE_STARTED"; printf 'active\n' >"$FAKE_STATE";;
*) exit 1;; esac
EOF
    cat >"$bin/uv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FAKE_UV_CALLS"
case "$1" in
venv)
    target=$2
    mkdir -p "$target/bin"; : >"$target/bin/python"; : >"$target/bin/astrbot"; : >"$target/pyvenv.cfg"
    chmod +x "$target/bin/python" "$target/bin/astrbot"; chown -R astrbot:astrbot "$target"
    ;;
pip)
    target=${VIRTUAL_ENV:-}
    [[ -n $target && -x $target/bin/python && -x $target/bin/astrbot && -f $target/pyvenv.cfg ]] || exit 88
    exit "${FAKE_PIP_STATUS:?}"
    ;;
*) exit 64;; esac
EOF
    chmod +x "$bin/systemctl" "$bin/uv"
    set +e
    PATH="$bin:$PATH" ASTRBOT_PRIVDROP_DONE=1 ROLLBACK_HEALTH_SECS=0 FAKE_STATE="$state" FAKE_CALLS="$calls" FAKE_UV_CALLS="$uv_calls" FAKE_PIP_STATUS="$pip_status" FAKE_CRASH="$crash" FAKE_STARTED="$tmp_dir/$label/started" FAKE_CRASHED="$tmp_dir/$label/crashed" SYSTEM_ROOT="$tmp_dir/$label/unused" CONFIG_DIR="$etc" CACHE_DIR="$cache" APP_DIR="$app" bash "$repo_dir/astrbotctl" update "$label" --stability-secs 1 >"$output" 2>&1
    status=$?
    set -e
    [[ $status -eq $expected ]] || { cat "$output"; fail "$label status $status"; }
    [[ $(head -1 "$calls") == is-active ]] || fail "$label did not inspect active state first"
    grep -Fq "venv $root/.venv" "$uv_calls" || fail "$label did not create a physical venv"
    grep -Fq "pip install --reinstall $app" "$uv_calls" || fail "$label did not reach pip after a valid created target"
    [[ $(grep -n '^venv ' "$uv_calls" | cut -d: -f1) -lt $(grep -n '^pip ' "$uv_calls" | cut -d: -f1) ]] || fail "$label ran pip before venv"
    if [[ $initially_active == active ]]; then grep -qx stop "$calls" || fail "$label did not stop active service before rebuild"; fi
    case "$label" in
    stable_active)
        [[ $(<"$state") == active && ! -e "$root/.venv/.astrbot-rollback" ]] || fail 'stable update did not remain active and clean'
        ;;
    stability_failure | rebuild_failure)
        [[ $(<"$state") == active && -f "$root/.venv/.astrbot-rollback" ]] || fail "$label did not restore an active rollback venv"
        ;;
    inactive_stable)
        [[ $(<"$state") == inactive && ! -e "$root/.venv/.astrbot-rollback" ]] || fail 'inactive update changed service state or marker'
        ;;
    esac
}

run_case stable_active active 0 0 0
run_case stability_failure active 0 1 1
run_case rebuild_failure active 42 0 42
run_case inactive_stable inactive 0 0 0
printf 'PASS: update creates a venv before pip and preserves rebuild/stability outcomes.\n'
