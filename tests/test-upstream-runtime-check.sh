#!/usr/bin/env bash
# Validate the current runtime layout without installing AstrBot dependencies.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

make_fixture() {
    local fixture="$tmp_dir/$1" path name
    while read -r path name; do
        mkdir -p "$(dirname "$fixture/AstrBot/$path")"
        printf 'class %s:\n    pass\n' "$name" >"$fixture/AstrBot/$path"
    done <<'ENTRYPOINTS'
astrbot/dashboard/server.py AstrBotDashboard
astrbot/core/core_lifecycle.py AstrBotCoreLifecycle
astrbot/core/astr_agent_runtime/runtime.py AstrAgentRuntime
astrbot/core/astr_agent_runtime/tool_executor.py FunctionToolExecutor
ENTRYPOINTS
    printf '%s\n' "$fixture"
}

run_check() {
    (
        # shellcheck disable=SC2034 # Consumed by the sourced PKGBUILD.
        srcdir="$1"
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced PKGBUILD.
        error() { printf '%s\n' "$*" >&2; }
        # shellcheck source=../PKGBUILD
        source "$repo_dir/PKGBUILD"
        check
    )
}

fixture="$(make_fixture current-runtime)"
run_check "$fixture" || fail 'current runtime requires a deleted legacy module'
[[ -z "$(find "$fixture" -name __pycache__ -print -quit)" ]] || fail 'check generated packaged bytecode'

fixture="$(make_fixture syntax-error)"
printf 'def broken(:\n' >"$fixture/AstrBot/astrbot/core/unrelated.py"
if run_check "$fixture" >"$tmp_dir/output" 2>&1; then
    fail 'syntax error outside selected entrypoints passed validation'
fi

fixture="$(make_fixture missing-runtime)"
rm "$fixture/AstrBot/astrbot/core/astr_agent_runtime/runtime.py"
if run_check "$fixture" >"$tmp_dir/output" 2>&1; then
    fail 'missing runtime module passed validation'
fi

fixture="$(make_fixture missing-entrypoint)"
printf '# class AstrAgentRuntime:\n' >"$fixture/AstrBot/astrbot/core/astr_agent_runtime/runtime.py"
if run_check "$fixture" >"$tmp_dir/output" 2>&1; then
    fail 'commented-out entrypoint passed validation'
fi

fixture="$(make_fixture password-log)"
printf 'notice = f"Initial password: {generated_password}"\n' >>"$fixture/AstrBot/astrbot/dashboard/server.py"
if run_check "$fixture" >"$tmp_dir/output" 2>&1; then
    fail 'plaintext dashboard password logging passed validation'
fi

printf 'PASS: package checks support the current runtime and reject incomplete or invalid source.\n'
