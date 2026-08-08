#!/usr/bin/env bash
# Exercise public hidden-PTY password provisioning without secret process args.
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
    exec sudo --preserve-env=PATH -- bash "$0" "$@"
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
controller="$repo_dir/astrbotctl"
expect_script="$repo_dir/tests/password-pty.exp"
instance="codex-pty-$(date +%s)-$$"
root="/var/lib/astrbot/$instance"
conf="/etc/astrbot/$instance.conf"
unit="astrbot@${instance}.service"
watchdog_pid=""

cleanup() {
    local status=$?
    trap - EXIT
    set +e
    [[ -z "$watchdog_pid" ]] || kill "$watchdog_pid" 2>/dev/null || true
    systemctl stop "$unit" >/dev/null 2>&1 || true
    systemctl disable "$unit" >/dev/null 2>&1 || true
    [[ ! -e "$root" && ! -e "$conf" ]] || bash "$controller" rm "$instance" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

command -v expect >/dev/null
test -f "$expect_script"

bash "$controller" init "$instance"
for path in "$root" "$root/home" "$root/data" "$root/data/config" "$root/.astrbot" "$root/.venv"; do
    test "$(stat -c '%U:%G' "$path")" = astrbot:astrbot
done

set +e
non_tty_output="$(printf '' | bash "$controller" password "$instance" 2>&1)"
non_tty_status=$?
set -e
[[ "$non_tty_status" -eq 1 ]] && grep -Fq 'controlling terminal' <<<"$non_tty_output"

setsid expect "$expect_script" "$controller" "$instance" >/dev/null 2>&1 &
expect_pid=$!
expect_pgid="$(ps -o pgid= -p "$expect_pid" | tr -d ' ')"
(
    sleep 30
    if kill -0 "$expect_pid" 2>/dev/null; then
        kill -TERM -- "-$expect_pgid" 2>/dev/null || true
        sleep 2
        kill -KILL -- "-$expect_pgid" 2>/dev/null || true
    fi
) &
watchdog_pid=$!
wait "$expect_pid"
expect_status=$?
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""
[[ "$expect_status" -eq 0 ]]
test "$(stat -c '%U:%G' "$root/data/cmd_config.json")" = astrbot:astrbot

printf 'PASS: non-TTY password fails fast and Expect PTY provisioning succeeds.\n'
