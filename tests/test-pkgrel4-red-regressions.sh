#!/usr/bin/env bash
# Prove the installed pkgrel4 payload has the three regressions this pkgrel5
# repair must remove. All execution stays below one private temporary root.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

readonly controller=/usr/bin/astrbotctl
readonly unit=/usr/lib/systemd/system/astrbot@.service
tmp_dir="$(mktemp -d)"

cleanup() { rm -rf -- "$tmp_dir"; }
trap cleanup EXIT
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local label="$1"
    local root="$tmp_dir/$label/root" etc_dir="$tmp_dir/$label/etc" app_dir="$tmp_dir/$label/app"
    mkdir -p "$root/.venv/bin" "$etc_dir" "$tmp_dir/$label/cache" "$app_dir"
    : >"$root/.venv/bin/python"
    : >"$root/.venv/bin/astrbot"
    chmod +x "$root/.venv/bin/python" "$root/.venv/bin/astrbot"
    printf 'old-version\n' >"$root/.venv/.astrbot-app-version"
    : >"$app_dir/pyproject.toml"
    printf 'new-version\n' >"$app_dir/.version"
    printf 'ASTRBOT_ROOT=%q\n' "$root" >"$etc_dir/$label.conf"
}

test_delete_copy_restore_red() {
    local label=atomic-red root fake_bin status
    root="$tmp_dir/$label/root"
    fake_bin="$tmp_dir/$label/bin"
    make_fixture "$label"
    mkdir -p "$fake_bin"
    # shellcheck disable=SC2016 # $1 belongs to the emitted stub, not this test.
    printf '#!/usr/bin/env bash\ncase "$1" in is-active) exit 1 ;; *) exit 1 ;; esac\n' >"$fake_bin/systemctl"
    printf '#!/usr/bin/env bash\nexit 42\n' >"$fake_bin/uv"
    cat >"$fake_bin/cp" <<'EOF'
#!/usr/bin/env bash
last=${!#}
for arg in "$@"; do
    if [[ "$arg" == *-venv-backup ]] && [[ "$last" == */root/.venv ]]; then exit 96; fi
done
exec /usr/bin/cp "$@"
EOF
    chmod +x "$fake_bin/systemctl" "$fake_bin/uv" "$fake_bin/cp"
    set +e
    PATH="$fake_bin:$PATH" ASTRBOT_PRIVDROP_DONE=1 SYSTEM_ROOT="$tmp_dir/$label/unused" CONFIG_DIR="$tmp_dir/$label/etc" CACHE_DIR="$tmp_dir/$label/cache" APP_DIR="$tmp_dir/$label/app" bash "$controller" sync "$label" >/dev/null 2>&1
    status=$?
    set -e
    [[ "$status" -eq 42 ]] || fail "pkgrel4 atomic RED returned $status, expected 42"
    [[ ! -e "$root/.venv" ]] || fail "pkgrel4 unexpectedly preserved destination after restore-copy failure"
    printf 'RED atomic: pkgrel4 delete-then-copy loses destination on restore failure.\n'
}

test_marker_loop_red() {
    local label=marker-red root fake_bin status calls_file output_file
    root="$tmp_dir/$label/root"
    fake_bin="$tmp_dir/$label/bin"
    calls_file="$tmp_dir/$label/uv.calls"
    output_file="$tmp_dir/$label/output"
    make_fixture "$label"
    mkdir -p "$fake_bin"
    printf 'version=old-version\nreason=sync_failure\n' >"$root/.venv/.astrbot-rollback"
    cat >"$fake_bin/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${UV_CALLS_FILE:?}"
exit 42
EOF
    chmod +x "$fake_bin/uv"
    set +e
    PATH="$fake_bin:$PATH" ASTRBOT_PRIVDROP_DONE=1 UV_CALLS_FILE="$calls_file" no_proxy=fixture SYSTEM_ROOT="$tmp_dir/$label/unused" CONFIG_DIR="$tmp_dir/$label/etc" CACHE_DIR="$tmp_dir/$label/cache" APP_DIR="$tmp_dir/$label/app" bash -x "$controller" __run_astrbot "$label" >"$output_file" 2>&1
    status=$?
    set -e
    [[ "$status" -eq 1 ]] || fail "pkgrel4 marker RED returned $status, expected 1"
    grep -Fq 'uv pip install --reinstall' "$output_file" || {
        tail -80 "$output_file" >&2
        fail "pkgrel4 unexpectedly bypassed version-mismatch sync"
    }
    printf 'RED marker: pkgrel4 retries failed sync despite rollback marker.\n'
}

test_lock_contract_red() {
    grep -Fq '/usr/bin/flock' "$unit" && fail "pkgrel4 unexpectedly has flock service locking"
    pacman -Qi astrbot-git | grep -Eq 'Depends On.*(^|[[:space:]])util-linux([[:space:]]|$)' && fail "pkgrel4 unexpectedly declares util-linux"
    printf 'RED locking: pkgrel4 unit and package metadata have no flock contract.\n'
}

[[ -x "$controller" ]] || fail "installed astrbotctl is unavailable"
[[ -f "$unit" ]] || fail "installed AstrBot unit is unavailable"
test_delete_copy_restore_red
test_marker_loop_red
test_lock_contract_red
printf 'PASS: installed pkgrel4 regression baselines observed.\n'
