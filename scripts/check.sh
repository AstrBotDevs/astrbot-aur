#!/usr/bin/env bash
# Safe default validation: explicit rootless test allowlist, never auto-sudo.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
# Keep fixture commits independent of personal signing keys and Git hooks.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
if [[ $EUID -eq 0 ]]; then
    printf 'Run this check as a regular user; privileged integration tests are excluded.\n' >&2
    exit 1
fi
for tool in bash shellcheck python git patch flock timeout envsubst rg bsdtar; do
    command -v "$tool" >/dev/null || {
        printf 'Missing test dependency: %s\n' "$tool" >&2
        exit 1
    }
done

shell_files=(astrbotctl astrbotctl.functions astrbot-git.install update.sh scripts/*.sh tests/*.sh)
printf '== Bash syntax and ShellCheck ==\n'
for file in PKGBUILD "${shell_files[@]}"; do
    bash -n "$file"
done
# makepkg consumes the PKGBUILD metadata variables outside the shell file.
shellcheck -s bash -S warning -e SC2034 PKGBUILD
shellcheck -x -P SCRIPTDIR -s bash -S warning "${shell_files[@]}"

if command -v makepkg >/dev/null; then
    printf '== Package metadata ==\n'
    makepkg --printsrcinfo | diff -u .SRCINFO -
else
    printf 'SKIP: .SRCINFO comparison requires makepkg (enforced in Arch CI).\n'
fi

# Do not replace this with tests/*.sh: some legacy tests operate on real
# services, automatically elevate privileges, or expect an old installed build.
rootless_tests=(
    test-cli-validation.sh
    test-clean-venvs.sh
    test-config-helpers.sh
    test-dashboard-config.sh
    test-runtime-file-safety.sh
    test-update-monitoring.sh
    test-sync-failure-propagation.sh
    test-runtime-path-contract.sh
    test-retired-backup-cli.sh
    test-venv-maintenance-lock.sh
    test-vcs-security-gate.sh
    test-local-source-integrity.sh
    test-package-contract-behavior.sh
    test-publication-contract.sh
    test-publication-behavior.sh
)
for test_file in "${rootless_tests[@]}"; do
    printf '\n== %s ==\n' "$test_file"
    timeout --kill-after=5s 120s bash "tests/$test_file"
done
printf '\nPASS: %s rootless suites. Privileged/installed-package integration tests were NOT run.\n' "${#rootless_tests[@]}"
