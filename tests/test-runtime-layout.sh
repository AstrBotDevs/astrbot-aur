#!/usr/bin/env bash
# Verify the installed astrbot-git public init -> systemd runtime lifecycle.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

instance="codex-layout-$(date +%s)-$$"
readonly instance
readonly root="/var/lib/astrbot/${instance}"
readonly home_root="${root}/home"
readonly conf="/etc/astrbot/${instance}.conf"
readonly unit="astrbot@${instance}.service"
login_request=""
login_response=""
password_one=""
password_two=""
secrets_configured=0

print_test_journal() {
    journalctl -u "$unit" -n 100 --no-pager |
        sed -E 's/(Initial password: ).*/\1[REDACTED]/'
}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    [[ "$secrets_configured" -eq 1 ]] || print_test_journal >&2 || true
    exit 1
}

fail_without_journal() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_owner() {
    local expected_owner="$1"
    shift
    local path actual_owner

    for path in "$@"; do
        actual_owner="$(stat -c '%U:%G' "$path")"
        [[ "$actual_owner" = "$expected_owner" ]] ||
            fail "expected ${path} to be owned by ${expected_owner}, got ${actual_owner}"
    done
}

cleanup() {
    local status=$?
    trap - EXIT
    set +e

    systemctl stop "$unit" || true
    systemctl disable "$unit" || true
    if [[ -e "$root" || -e "$conf" ]]; then
        astrbotctl rm "$instance"
    fi
    systemctl reset-failed "$unit" || true
    [[ -z "$login_request" ]] || rm -f "$login_request"
    [[ -z "$login_response" ]] || rm -f "$login_response"

    if [[ -e "$root" || -e "$conf" ]]; then
        printf 'CLEANUP FAILURE: residual test instance: %s\n' "$instance" >&2
        status=1
    fi
    exit "$status"
}
trap cleanup EXIT

wait_for_stable_service() {
    local deadline=$((SECONDS + 120)) active_samples=0 main_pid

    while (( SECONDS < deadline )); do
        if systemctl is-failed --quiet "$unit"; then
            fail "service entered failed state"
        fi

        if systemctl is-active --quiet "$unit"; then
            main_pid="$(systemctl show "$unit" --property=MainPID --value)"
            if [[ "$main_pid" =~ ^[1-9][0-9]*$ ]]; then
                ((active_samples += 1))
                if (( active_samples >= 3 )); then
                    return 0
                fi
            fi
        else
            active_samples=0
        fi
        sleep 2
    done

    fail "service did not remain active with a main process for six seconds"
}

wait_for_dashboard_listener() {
    local port deadline
    port="$(awk -F= '/^ASTRBOT_PORT=/{gsub(/"/, "", $2); print $2; exit}' "$conf")"
    [[ "$port" =~ ^[0-9]+$ ]] || fail "generated config has no numeric dashboard port"
    deadline=$((SECONDS + 120))

    while (( SECONDS < deadline )); do
        if systemctl is-failed --quiet "$unit"; then
            fail "service failed before dashboard port ${port} became ready"
        fi
        if ss -lntH "( sport = :${port} )" | grep -q .; then
            return 0
        fi
        sleep 2
    done

    fail "dashboard port ${port} did not become ready"
}

wait_for_guard_failure() {
    local deadline=$((SECONDS + 30)) exit_status

    while (( SECONDS < deadline )); do
        if systemctl is-active --quiet "$unit"; then
            fail "service started without a configured dashboard password"
        fi
        exit_status="$(systemctl show "$unit" --property=ExecMainStatus --value)"
        if [[ "$exit_status" = 1 ]]; then
            systemctl stop "$unit" || true
            return 0
        fi
        sleep 1
    done

    fail "service did not fail closed while dashboard password was unset"
}

set_dashboard_password() {
    local password="$1"

    if ! printf '%s\n%s\n' "$password" "$password" |
        script -qefc "astrbotctl password --username astrbot $instance" /dev/null >/dev/null; then
        fail_without_journal "interactive dashboard password provisioning failed"
    fi
}

write_login_request() {
    local password="$1"

    login_request="$(mktemp /tmp/codex-astrbot-login.XXXXXX)"
    login_response="$(mktemp /tmp/codex-astrbot-response.XXXXXX)"
    chmod 600 "$login_request" "$login_response"
    printf '{"username":"astrbot","password":"%s"}' "$password" >"$login_request"
}

assert_login_status() {
    local password="$1" expected_status="$2" actual_status

    [[ -z "$login_request" ]] || rm -f "$login_request"
    [[ -z "$login_response" ]] || rm -f "$login_response"
    write_login_request "$password"
    actual_status="$(curl --noproxy '*' --silent --show-error \
        --output "$login_response" --write-out '%{http_code}' \
        --header 'Content-Type: application/json' --data-binary "@$login_request" \
        "http://127.0.0.1:${dashboard_port}/api/auth/login")"
    [[ "$actual_status" = "$expected_status" ]] ||
        fail_without_journal "dashboard login returned $actual_status, expected $expected_status"
}

assert_journal_omits_secret() {
    local secret="$1"

    if ! journalctl -u "$unit" --no-pager -o cat |
        python3 -c 'import os, sys; secret = os.read(3, 8192); sys.exit(1 if secret in sys.stdin.buffer.read() else 0)' \
            3< <(printf '%s' "$secret"); then
        fail_without_journal "journal contains a test dashboard password"
    fi
}

command -v astrbotctl >/dev/null || fail "astrbotctl is not installed"
command -v systemctl >/dev/null || fail "systemctl is not installed"
command -v journalctl >/dev/null || fail "journalctl is not installed"
command -v ss >/dev/null || fail "ss is not installed"
command -v script >/dev/null || fail "script is not installed"
command -v curl >/dev/null || fail "curl is not installed"
command -v python3 >/dev/null || fail "python3 is not installed"

password_help="$(astrbotctl password --help 2>&1)" ||
    fail "astrbotctl password public interface is unavailable"
grep -Fq 'Usage: astrbotctl password' <<<"$password_help" ||
    fail "astrbotctl password help is incomplete"

[[ ! -e "$root" && ! -e "$conf" ]] || fail "unexpected collision for ${instance}"

printf 'Initializing %s via the public astrbotctl interface...\n' "$instance"
astrbotctl init "$instance"

[[ -f "${root}/.astrbot" ]] ||
    fail "init did not create the required root marker ${root}/.astrbot"
[[ ! -e "${home_root}/.astrbot" ]] ||
    fail "init incorrectly created the root marker below isolated HOME"
assert_owner astrbot:astrbot \
    "$root" "$home_root" "$root/data" "$root/data/config" \
    "$root/.astrbot" "$root/.venv"
assert_owner root:root "$conf"

printf 'Verifying start is blocked until a dashboard password is configured...\n'
systemctl start "$unit" >/dev/null 2>&1 || true
wait_for_guard_failure

password_one="Ab1_${instance}_${RANDOM}"
password_two="Cd2_${instance}_${RANDOM}"
secrets_configured=1
set_dashboard_password "$password_one"
[[ "$(stat -c '%U:%G' "${root}/data/cmd_config.json")" = 'astrbot:astrbot' ]] ||
    fail_without_journal "interactive provisioning did not create astrbot-owned config"

printf 'Starting %s...\n' "$unit"
systemctl start "$unit"
wait_for_stable_service
astrbotctl status "$instance"
wait_for_dashboard_listener
dashboard_port="$(awk -F= '/^ASTRBOT_PORT=/{gsub(/"/, "", $2); print $2; exit}' "$conf")"
[[ "$dashboard_port" =~ ^[0-9]+$ ]] || fail_without_journal "generated config has no numeric dashboard port"
assert_login_status "$password_one" 200

printf 'Restarting %s to verify repeatable service startup...\n' "$unit"
systemctl restart "$unit"
wait_for_stable_service
wait_for_dashboard_listener
assert_login_status "$password_one" 200

printf 'Verifying interactive password recovery...\n'
set_dashboard_password "$password_two"
systemctl restart "$unit"
wait_for_stable_service
wait_for_dashboard_listener
assert_login_status "$password_one" 401
assert_login_status "$password_two" 200
assert_journal_omits_secret "$password_one"
assert_journal_omits_secret "$password_two"
if journalctl -u "$unit" --no-pager -o cat | grep -Fq 'Initial password:'; then
    fail_without_journal "journal contains the dashboard initial-password marker"
fi

printf 'PASS: %s initialized and remained healthy across restart.\n' "$instance"
