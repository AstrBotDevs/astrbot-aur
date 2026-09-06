#!/usr/bin/env bash
# Execute the actual workflow scripts with offline command doubles. No Docker,
# package manager, privileged command, SSH, or real Git publication is invoked.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

for dependency in bash python3 env ln chmod grep cat cp diff dirname basename find install mkdir mktemp realpath rm; do
    command -v "$dependency" >/dev/null || fail "$dependency is required"
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
real_grep="$(type -P grep)"

# An allowlisted PATH prevents a missing double from falling through to a real
# network or privileged command. Child shells also receive a clean environment.
for utility in bash basename cat cp diff dirname find install mkdir mktemp realpath rm; do
    ln -s "$(type -P "$utility")" "$fake_bin/$utility"
done

python3 - "$repo_dir/.github/workflows/aur-publish.yml" "$tmp_dir" <<'PY'
import pathlib
import sys

workflow = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines(keepends=True)
outputs = {
    "Validate package metadata and source preparation": "validate.sh",
    "Publish independent AUR snapshot": "publish.sh",
}
found = set()
step = None
for index, line in enumerate(workflow):
    if line.startswith("      - name: "):
        step = line.strip().removeprefix("- name: ")
    if line.rstrip() != "        run: |" or step not in outputs:
        continue
    if step in found:
        raise SystemExit(f"duplicate workflow step: {step}")
    block = []
    for body_line in workflow[index + 1:]:
        if body_line.strip() and not body_line.startswith("          "):
            break
        block.append(body_line[10:] if body_line.strip() else "\n")
    if not block:
        raise SystemExit(f"empty workflow script: {step}")
    (pathlib.Path(sys.argv[2]) / outputs[step]).write_text("".join(block), encoding="utf-8")
    found.add(step)
if found != set(outputs):
    raise SystemExit("could not extract both expected workflow scripts")
PY

cat >"$tmp_dir/command-double" <<'SH'
#!/bin/bash
set -Eeuo pipefail
name="${0##*/}"
reject() {
    printf 'unexpected:%s\n' "$name" >>"$TRACE"
    printf 'Unexpected offline command-double invocation: %s\n' "$name" >&2
    exit 90
}

case "$name" in
    docker)
        [[ $# -eq 12 && "$1" == run && "$2" == --rm && "$3" == --volume &&
            "$4" == "$GITHUB_WORKSPACE:/workspace" && "$5" == --workdir &&
            "$6" == /workspace && "$7" == archlinux:base-devel ]] || reject
        shift 7
        [[ "$1" == bash && "$2" == -euo && "$3" == pipefail && "$4" == -c ]] || reject
        cd "$GITHUB_WORKSPACE"
        exec "$@"
        ;;
    pacman)
        [[ "$*" == '-Syu --noconfirm git python shellcheck gettext ripgrep libarchive' ]] || reject
        ;;
    useradd)
        [[ "$*" == '--create-home builder' ]] || reject
        ;;
    chown)
        [[ "$*" == '-R builder:builder /workspace' ]] || reject
        ;;
    su)
        [[ $# -eq 5 && "$1" == builder && "$2" == -s && "$3" == /bin/bash && "$4" == -c ]] || reject
        exec bash -c "$5"
        ;;
    makepkg)
        case "$*" in
            --printsrcinfo)
                printf 'metadata\n' >>"$TRACE"
                if [[ "$SCENARIO" == metadata-mismatch ]]; then
                    printf 'simulated invalid metadata\n'
                else
                    cat .SRCINFO
                fi
                # Output can be correct even when the producer fails.
                [[ "$SCENARIO" != metadata-error ]] || exit 42
                ;;
            '--nobuild --nodeps --force')
                printf 'prepare\n' >>"$TRACE"
                ;;
            *) reject ;;
        esac
        ;;
    grep)
        printf 'scan\n' >>"$TRACE"
        [[ "$SCENARIO" != scan-error ]] || exit 2
        exec "$REAL_GREP" "$@"
        ;;
    git)
        if [[ "${1:-}" == clone ]]; then
            [[ $# -eq 7 && "$2" == --branch && "$3" == master && "$4" == --single-branch &&
                "$5" == -- && "$6" == ssh://aur@aur.archlinux.org/astrbot-git.git ]] || reject
            case "$7" in
                "$RUNNER_TEMP"/astrbot-git-aur.????????/repository) ;;
                *) reject ;;
            esac
            mkdir -p "$7/.git"
            printf 'clone\n' >>"$TRACE"
            exit 0
        fi
        [[ $# -ge 3 && "$1" == -C ]] || reject
        directory="$2"
        case "$directory" in
            "$RUNNER_TEMP"/astrbot-git-aur.????????/repository) ;;
            *) reject ;;
        esac
        shift 2
        case "$*" in
            'status --porcelain=v1 --untracked-files=all')
                [[ "$SCENARIO" != status-error ]] || exit 42
                ;;
            'diff --cached --name-only -z')
                printf 'enumerate\n' >>"$TRACE"
                if [[ "$SCENARIO" == staged-path-outside ]]; then
                    printf 'unexpected-file\0'
                else
                    printf 'PKGBUILD\0'
                fi
                [[ "$SCENARIO" != staged-list-error ]] || exit 42
                ;;
            'diff --quiet') ;;
            'diff --cached --quiet')
                [[ "$SCENARIO" != staged-diff-error ]] || exit 42
                [[ "$SCENARIO" == already-current ]] || exit 1
                ;;
            'push --dry-run origin HEAD:master') printf 'push:dry-run\n' >>"$TRACE" ;;
            'push origin HEAD:master') printf 'push:publish\n' >>"$TRACE" ;;
            *)
                case "$1" in
                    add)
                        [[ $# -eq 10 && "$2" == -- ]] || reject
                        printf 'stage\n' >>"$TRACE"
                        ;;
                    show)
                        [[ $# -eq 2 && "$2" == :* && "$2" != */* ]] || reject
                        printf 'show\n' >>"$TRACE"
                        cat "$directory/${2#:}"
                        [[ "$SCENARIO" != blob-error ]] || exit 42
                        ;;
                    config)
                        [[ $# -eq 3 && ( "$2" == user.name || "$2" == user.email ) ]] || reject
                        ;;
                    commit)
                        [[ $# -eq 4 && "$2" == --signoff && "$3" == -m ]] || reject
                        printf 'commit\n' >>"$TRACE"
                        ;;
                    *) reject ;;
                esac
                ;;
        esac
        ;;
    *) reject ;;
esac
SH
chmod 755 "$tmp_dir/command-double"
for command_name in docker pacman useradd chown su makepkg git grep; do
    ln -s "$tmp_dir/command-double" "$fake_bin/$command_name"
done

assets=(.SRCINFO PKGBUILD astrbot-git.install astrbotctl astrbotctl.functions 'astrbot@.service' tmpl.conf no-dashboard-password-in-startup-log.patch)

run_workflow() {
    local scenario="$1" script_name="$2" asset
    case_dir="$tmp_dir/$scenario"
    workspace="$case_dir/workspace"
    runner_temp="$case_dir/runner"
    trace="$case_dir/trace"
    output="$case_dir/output"
    mkdir -p "$workspace/scripts" "$runner_temp" "$case_dir/home"
    : >"$trace"
    # The real entry point has its own tests. This double proves ordering and
    # failure propagation without recursively invoking this behavior suite.
    cat >"$workspace/scripts/check.sh" <<'CHECK'
#!/bin/bash
set -Eeuo pipefail
printf 'check\n' >>"$TRACE"
[[ "$SCENARIO" != check-error ]] || exit 42
CHECK
    for asset in "${assets[@]}"; do
        cp -- "$repo_dir/$asset" "$workspace/$asset"
    done
    if [[ "$scenario" == large-secret ]]; then
        python3 - "$workspace/.SRCINFO" <<'PY'
import pathlib
import sys

marker = "-----BEGIN " + "OPENSSH PRIVATE KEY-----\n"
pathlib.Path(sys.argv[1]).write_text(marker + "offline-secret-sentinel\n" + "x" * 1048576, encoding="utf-8")
PY
    fi

    if env -i PATH="$fake_bin" HOME="$case_dir/home" LC_ALL=C \
        GITHUB_WORKSPACE="$workspace" RUNNER_TEMP="$runner_temp" \
        GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 \
        AUR_SSH_PRIVATE_KEY=offline-placeholder AUR_SSH_KNOWN_HOSTS=offline-placeholder \
        TRACE="$trace" SCENARIO="$scenario" REAL_GREP="$real_grep" \
        bash "$tmp_dir/$script_name.sh" >"$output" 2>&1; then
        workflow_status=0
    else
        workflow_status=$?
    fi
    if grep -Fq 'unexpected:' "$trace"; then
        fail "$scenario invoked an unsupported command double"
    fi
    [[ -z "$(find "$runner_temp" -mindepth 1 -print -quit)" ]] || fail "$scenario left publication state behind"
}

assert_no_publication() {
    if grep -Eq '^(commit|push:)' "$trace"; then
        fail "$1 continued to commit or push"
    fi
}

assert_refused() {
    local scenario="$1" expected_message="$2"
    run_workflow "$scenario" publish
    [[ "$workflow_status" -ne 0 ]] || fail "$scenario did not fail closed"
    grep -Fq -- "$expected_message" "$output" || fail "$scenario failed for an unexpected reason"
    assert_no_publication "$scenario"
}

run_workflow validate-success validate
[[ "$workflow_status" -eq 0 ]] || fail 'matching metadata did not validate'
[[ "$(<"$trace")" == $'check\nmetadata\nprepare' ]] || fail 'validation did not run check, metadata, and prepare in order'

run_workflow check-error validate
[[ "$workflow_status" -ne 0 ]] || fail 'failed non-root checks did not stop validation'
[[ "$(<"$trace")" == check ]] || fail 'failed non-root checks continued to metadata or prepare'

for scenario in metadata-mismatch metadata-error; do
    run_workflow "$scenario" validate
    [[ "$workflow_status" -ne 0 ]] || fail "$scenario did not stop validation"
    [[ "$(<"$trace")" == $'check\nmetadata' ]] || fail "$scenario did not reach metadata after successful checks, or continued to prepare"
done

run_workflow publish-success publish
[[ "$workflow_status" -eq 0 ]] || fail 'clean staged blobs did not reach simulated publication'
[[ "$(grep -Fxc commit "$trace")" -eq 1 ]] || fail 'clean snapshot did not produce exactly one simulated commit'
[[ "$(grep -Ec '^push:' "$trace")" -eq 2 ]] || fail 'clean snapshot did not produce exactly two simulated pushes'
grep -Fxq push:dry-run "$trace" || fail 'simulated push skipped its dry run'
grep -Fxq push:publish "$trace" || fail 'simulated publication was missing'

run_workflow already-current publish
[[ "$workflow_status" -eq 0 ]] || fail 'unchanged AUR snapshot was rejected'
assert_no_publication already-current

assert_refused staged-list-error 'could not enumerate staged AUR paths'
if grep -Fxq show "$trace"; then
    fail 'staged path enumeration failure continued to blob reads'
fi
assert_refused staged-path-outside 'refusing to stage an out-of-manifest file'
assert_refused blob-error 'could not read staged asset'
if grep -Fxq scan "$trace"; then
    fail 'failed blob read continued to scanning'
fi
assert_refused scan-error 'could not scan staged asset'
assert_refused status-error 'could not inspect fresh AUR clone'
assert_refused staged-diff-error 'could not compare staged AUR snapshot'
assert_refused large-secret 'refusing to publish private-key material'
private_marker="$(printf '%s%s' '-----BEGIN ' 'OPENSSH PRIVATE KEY-----')"
if grep -F -e "$private_marker" -e offline-secret-sentinel "$output" >/dev/null; then
    fail 'private-key scan leaked matching content'
fi

printf 'PASS: offline workflow execution rejects metadata, Git, and scan failures without publication.\n'
