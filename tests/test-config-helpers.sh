#!/usr/bin/env bash
# Rootless: only temporary fixtures, no services, certificates or network calls.
# shellcheck disable=SC2034 # Fixture globals are consumed by the sourced helpers.
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

(
    config="$tmp_dir/upsert.conf"
    value='a\\b"c$HOME$(printf WRONG)`printf WRONG`&/end'
    printf '# keep this comment\nOTHER="untouched"\n' >"$config"
    chmod 640 "$config"
    for phase in insert update; do
        upsert_conf_var "$config" VALUE "$value"
        bash -n "$config"
        bash -c '. "$1"; [[ "$VALUE" == "$2" && "$OTHER" == untouched ]]' bash "$config" "$value"
        [[ "$(stat -c %a "$config")" == 640 ]] || fail "$phase changed permissions"
        [[ "$(stat -c %u:%g "$config")" == "$(id -u):$(id -g)" ]] || fail 'upsert changed ownership'
        value='updated\\"$()`printf WRONG`/ &'
    done
    original="$(<"$config")"
    expect_status 2 upsert_conf_var "$config" 'BAD;KEY' x
    expect_status 2 upsert_conf_var "$config" VALUE $'bad\nline'
    expect_status 2 upsert_conf_var "$config" VALUE $'bad\rline'
    [[ "$(<"$config")" == "$original" ]] || fail 'invalid input changed config'
    (
        mv() { return 42; }
        expect_status 42 upsert_conf_var "$config" VALUE replacement
    )
    [[ "$(<"$config")" == "$original" ]] || fail 'failed upsert destroyed config'
    assert_no_temps "$tmp_dir"
)

(
    CONFIG_DIR="$tmp_dir/baseline"
    SYSTEM_ROOT="$tmp_dir/instances"
    mkdir -p "$CONFIG_DIR"
    unset ASTRBOT_SSL_ENABLE ASTRBOT_SSL_CERT ASTRBOT_SSL_KEY ASTRBOT_SSL_CA_CERTS
    unset DASHSCOPE_API_KEY COZE_API_KEY COZE_BOT_ID ASTRBOT_CERTBOT_EMAIL
    unset _ASTRBOT_CONFIG_BASELINE
    export http_proxy='http://external-default.invalid'
    printf '%s\n' 'ASTRBOT_SSL_ENABLE=true' 'ASTRBOT_SSL_CERT=/first.pem' \
        'DASHSCOPE_API_KEY=secret' 'ASTRBOT_CERTBOT_EMAIL=first@example.invalid' \
        'http_proxy=http://first.invalid' >"$CONFIG_DIR/first.conf"
    cp "$repo_dir/tmpl.conf" "$CONFIG_DIR/second.conf"
    # Resolve the identity placeholders without evaluating the template defaults.
    upsert_conf_var "$CONFIG_DIR/second.conf" INSTANCE_NAME second
    upsert_conf_var "$CONFIG_DIR/second.conf" ASTRBOT_ROOT "$SYSTEM_ROOT/second"
    upsert_conf_var "$CONFIG_DIR/second.conf" ASTRBOT_HOST 127.0.0.1
    upsert_conf_var "$CONFIG_DIR/second.conf" ASTRBOT_PORT 3001
    set +a
    instance=first
    load_instance_config
    [[ $- != *a* ]] || fail 'load enabled allexport'
    instance=second
    load_instance_config
    [[ "$ASTRBOT_SSL_ENABLE" == false && -z "$ASTRBOT_SSL_CERT" ]] || fail 'SSL leaked'
    [[ -z "$DASHSCOPE_API_KEY" && -z "${ASTRBOT_CERTBOT_EMAIL:-}" ]] || fail 'API/certbot value leaked'
    [[ "$http_proxy" == http://external-default.invalid ]] || fail 'external proxy default lost'
    [[ "$ASTRBOT_ROOT" == "$SYSTEM_ROOT/second" && "$ASTRBOT_HOME" == "$ASTRBOT_ROOT" ]] || fail 'root alias incorrect'
    bash -c '[[ "$ASTRBOT_HOME" == "$ASTRBOT_ROOT" ]]' || fail 'root alias not exported'
    printf 'return 42\n' >"$CONFIG_DIR/failing.conf"
    instance=failing
    expect_status 42 load_instance_config
    [[ $- != *a* ]] || fail 'failed load enabled allexport'
    set -a
    expect_status 42 load_instance_config
    [[ $- == *a* ]] || fail 'failed load disabled allexport'
    instance=second
    load_instance_config
    [[ $- == *a* ]] || fail 'successful load disabled allexport'
    set +a
)

(
    CONFIG_DIR="$tmp_dir/ports"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' 'ASTRBOT_PORT="3000"' >"$CONFIG_DIR/double.conf"
    printf '%s\n' "ASTRBOT_PORT='3001'" >"$CONFIG_DIR/single.conf"
    printf '%s\n' 'ASTRBOT_PORT=03002 # comment' 'ASTRBOT_PORT=$(exit 99)' >"$CONFIG_DIR/plain.conf"
    ss() { printf 'LISTEN 0 128 127.0.0.1:3003 0.0.0.0:*\n'; }
    find_free_port 3000
    [[ "$ASTRBOT_PORT" == 3004 ]] || fail 'quoted or listening port was reused'
    for invalid in 0 65536 -1 '1+2' invalid; do expect_status 2 find_free_port "$invalid"; done
    ss() { return 1; }
    find_free_port 3000
    [[ "$ASTRBOT_PORT" == 3003 ]] || fail 'empty ss failed under pipefail'
    printf 'ASTRBOT_PORT=65535\n' >"$CONFIG_DIR/last.conf"
    expect_status 1 find_free_port 65535
)

(
    CONFIG_DIR="$tmp_dir/render"
    SYSTEM_ROOT="$tmp_dir/render-roots"
    SCRIPT_DIR="$CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    cp "$repo_dir/tmpl.conf" "$CONFIG_DIR/tmpl.conf"
    instance=render
    printf 'ASTRBOT_PORT=3010\nASTRBOT_HOST=127.0.0.1\n' >"$CONFIG_DIR/render.conf"
    chmod 600 "$CONFIG_DIR/render.conf"
    original="$(<"$CONFIG_DIR/render.conf")"
    ss() { return 0; }
    envsubst() { printf 'ASTRBOT_PORT=3000\n'; }
    sync_cmd_config() { return 0; }
    saved_trap="$(trap -p EXIT)"
    for step in envsubst chmod mv sync_cmd_config mktemp; do
        (
            # Function-only fault injection; every real path remains temporary.
            case "$step" in
            envsubst) envsubst() { return 42; } ;;
            chmod) chmod() { return 42; } ;;
            mv) mv() { return 42; } ;;
            sync_cmd_config) sync_cmd_config() { return 42; } ;;
            mktemp) mktemp() { return 42; } ;;
            esac
            expect_status 42 render_config_from_template >"$tmp_dir/render-failure.log"
            [[ "$(<"$CONFIG_DIR/render.conf")" == "$original" ]] || fail "$step destroyed original config"
            [[ "$(stat -c %a "$CONFIG_DIR/render.conf")" == 600 ]] || fail "$step changed mode"
            assert_no_temps "$CONFIG_DIR"
            ! grep -q 'Config reset' "$tmp_dir/render-failure.log" || fail "$step reported success"
        )
    done
    (
        envsubst() { return 127; }
        expect_status 127 render_config_from_template
        assert_no_temps "$CONFIG_DIR"
    )
    (
        envsubst() { printf 'INVALID="\n'; }
        expect_status 2 render_config_from_template
        [[ "$(<"$CONFIG_DIR/render.conf")" == "$original" ]] || fail 'invalid syntax was published'
    )
    render_config_from_template
    [[ "$(<"$CONFIG_DIR/render.conf")" == ASTRBOT_PORT=3000 ]] || fail 'render did not publish'
    [[ "$(trap -p EXIT)" == "$saved_trap" ]] || fail 'render replaced caller EXIT trap'
    assert_no_temps "$CONFIG_DIR"
)

(
    instance=certificate
    CERTBOT_INSTANCE_CERTS_DIR="$tmp_dir/certs"
    # Redirect certificate discovery to fixtures; install is always mocked.
    mkdir -p "$tmp_dir/live"
    printf 'certificate\n' >"$tmp_dir/live/fullchain.pem"
    printf 'private key fixture\n' >"$tmp_dir/live/privkey.pem"
    certbot_live_dir() { printf '%s\n' "$tmp_dir/live"; }
    install() {
        printf '%s\0' "$@" >>"$tmp_dir/install-args"
        printf '\0' >>"$tmp_dir/install-args"
    }
    certbot_hook_path() { printf '%s\n' "$tmp_dir/deploy-hook"; }
    for present in yes no; do
        getent() { [[ "$present" == yes ]]; }
        : >"$tmp_dir/install-args"
        sync_certbot_cert_for_instance fixture
        install_certbot_deploy_hook fixture
        python - "$tmp_dir/install-args" "$present" <<'PY'
import sys
raw = open(sys.argv[1], 'rb').read()
records = [r.split(b'\0') for r in raw.split(b'\0\0') if r]
assert len(records) == 4, records
for args in records:
    assert b'' not in args and b'-g astrbot' not in args, args
    if sys.argv[2] == 'yes':
        assert args[args.index(b'-g') + 1] == b'astrbot', args
    else:
        assert b'-g' not in args, args
PY
    done
    install() { return 42; }
    expect_status 42 sync_certbot_cert_for_instance fixture
)
printf 'PASS: safe config serialization, isolated defaults, ports, rendering and certificate arguments.\n'
