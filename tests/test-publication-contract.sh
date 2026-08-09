#!/usr/bin/env bash
# Verify the protected, independent-history GitHub-to-AUR publication contract.
# shellcheck disable=SC2016 # Literal workflow-source assertions are intentional.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_dir/update.sh"
workflow="$repo_dir/.github/workflows/aur-publish.yml"
readme="$repo_dir/README.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_literal() {
    grep -Fq -- "$1" "$2" || fail "$3"
}
forbid_regex() {
    local pattern="$1"
    shift
    local message="${*: -1}"
    local -a files=("${@:1:$#-1}")
    if rg -n -- "$pattern" "${files[@]}" >/dev/null; then
        fail "$message"
    fi
}

[[ -x "$script" ]] || fail 'update.sh must remain executable'
[[ -f "$workflow" && ! -L "$workflow" ]] || fail 'protected AUR workflow is missing or not a regular file'

expected_trigger='on:
  push:
    branches:
      - master
    paths:
      - .SRCINFO
      - PKGBUILD
      - astrbot-git.install
      - astrbotctl
      - astrbotctl.functions
      - astrbot@.service
      - tmpl.conf
      - no-dashboard-password-in-startup-log.patch
      - .github/workflows/aur-publish.yml
  workflow_dispatch:'
actual_trigger="$(sed -n '/^on:/,/^permissions:/p' "$workflow" | sed '${/^permissions:$/d;}' | sed '${/^$/d;}')"
[[ "$actual_trigger" == "$expected_trigger" ]] || fail 'workflow triggers are not restricted to master package assets and manual dispatch'

require_literal 'permissions:' "$workflow" 'workflow permissions block is missing'
require_literal '  contents: read' "$workflow" 'workflow repository permission is not read-only'
[[ "$(grep -Ec '^[[:space:]]+[a-z-]+:[[:space:]]+(read|write)$' "$workflow")" -eq 1 ]] || fail 'workflow grants permissions beyond contents: read'
require_literal 'concurrency:' "$workflow" 'workflow concurrency guard is missing'
require_literal '  group: aur-production' "$workflow" 'workflow concurrency is not serialized for AUR production'
require_literal '  cancel-in-progress: false' "$workflow" 'workflow may cancel an in-flight AUR publication'
require_literal '    environment: aur-production' "$workflow" 'AUR secrets are not protected by the aur-production Environment'
[[ "$(sed -n '/^jobs:/,$p' "$workflow" | grep -Ec '^  [a-zA-Z0-9_-]+:$')" -eq 1 ]] || fail 'workflow must have exactly one protected job'
require_literal "    if: \${{ github.ref == 'refs/heads/master' }}" "$workflow" 'publication job is not restricted to the master branch ref'
[[ "$(grep -Fxc "    if: \${{ github.ref == 'refs/heads/master' }}" "$workflow")" -eq 1 ]] || fail 'master-only publication guard must be an exact job-level condition'
publish_line="$(grep -Fn '  publish:' "$workflow" | cut -d: -f1)"
guard_line="$(grep -Fn "    if: \${{ github.ref == 'refs/heads/master' }}" "$workflow" | cut -d: -f1)"
environment_line="$(grep -Fn '    environment: aur-production' "$workflow" | cut -d: -f1)"
[[ "$publish_line" -lt "$guard_line" && "$guard_line" -lt "$environment_line" ]] || fail 'master-only guard must protect the Environment before secrets can be consumed'

if grep -Eq '^    env:' "$workflow"; then
    fail 'AUR secrets are exposed to the checkout step through job-level env'
fi
[[ "$(grep -Ec '^        env:$' "$workflow")" -eq 1 ]] || fail 'AUR secrets are not scoped to the publication step'
require_literal '          AUR_SSH_PRIVATE_KEY: ${{ secrets.AUR_SSH_PRIVATE_KEY }}' "$workflow" 'workflow does not obtain the private key from the exact GitHub Secret'
require_literal '          AUR_SSH_KNOWN_HOSTS: ${{ secrets.AUR_SSH_KNOWN_HOSTS }}' "$workflow" 'workflow does not obtain known_hosts from the exact GitHub Secret'
[[ "$(grep -Fc '${{ secrets.' "$workflow")" -eq 2 ]] || fail 'workflow uses secrets outside the two approved AUR values'
require_literal ': "${AUR_SSH_PRIVATE_KEY:?AUR_SSH_PRIVATE_KEY is required}"' "$workflow" 'missing AUR private-key Secret does not fail closed'
require_literal ': "${AUR_SSH_KNOWN_HOSTS:?AUR_SSH_KNOWN_HOSTS is required}"' "$workflow" 'missing AUR known-hosts Secret does not fail closed'
require_literal 'mktemp -d -- "$RUNNER_TEMP/astrbot-git-aur.XXXXXXXX"' "$workflow" 'workflow does not create its state under RUNNER_TEMP'
require_literal 'install -m 600 /dev/null "$ssh_key_path"' "$workflow" 'workflow does not create the private-key file with mode 600'
require_literal 'install -m 600 /dev/null "$known_hosts_path"' "$workflow" 'workflow does not create known_hosts with mode 600'
require_literal 'unset AUR_SSH_PRIVATE_KEY AUR_SSH_KNOWN_HOSTS' "$workflow" 'workflow retains secret environment values after writing protected files'
require_literal 'trap cleanup EXIT' "$workflow" 'workflow does not clean temporary secret files on exit'
require_literal 'rm -rf -- "$publish_tmp_dir"' "$workflow" 'workflow cleanup is not restricted to its mktemp directory'

require_literal 'BatchMode=yes' "$workflow" 'SSH is not non-interactive'
require_literal 'IdentitiesOnly=yes' "$workflow" 'SSH may use an unintended runner identity'
require_literal 'StrictHostKeyChecking=yes' "$workflow" 'SSH host-key verification is not strict'
require_literal 'UserKnownHostsFile=$known_hosts_path' "$workflow" 'SSH does not use the protected known_hosts file'
forbid_regex 'ssh-keyscan|accept-new|StrictHostKeyChecking=(no|off)|(^|[[:space:]])ssh[[:space:]]+-[^[:space:]]*v' "$workflow" 'workflow contains permissive or verbose SSH configuration'

require_literal 'readonly AUR_REPO_URL="ssh://aur@aur.archlinux.org/astrbot-git.git"' "$workflow" 'workflow does not use the exact astrbot-git SSH repository'
expected_manifest='          AUR_FILES=(
            ".SRCINFO"
            "PKGBUILD"
            "astrbot-git.install"
            "astrbotctl"
            "astrbotctl.functions"
            "astrbot@.service"
            "tmpl.conf"
            "no-dashboard-password-in-startup-log.patch"
          )'
actual_manifest="$(sed -n '/^[[:space:]]*AUR_FILES=(/,/^[[:space:]]*)/p' "$workflow")"
[[ "$actual_manifest" == "$expected_manifest" ]] || fail 'workflow publication manifest is not the exact eight-file root allowlist'
require_literal '[[ "$asset" != */* ]]' "$workflow" 'workflow does not reject manifest subpaths'
require_literal '[[ -f "$source_path" && ! -L "$source_path" ]]' "$workflow" 'workflow does not reject missing, symlinked, or non-regular source assets'
require_literal 'reject_clone_root_shape' "$workflow" 'workflow does not reject forbidden top-level AUR clone entries'
[[ "$(grep -Fc 'reject_clone_root_shape' "$workflow")" -eq 3 ]] || fail 'AUR clone shape must be checked exactly before and after synchronization'
require_literal 'find -P "$aur_repo_dir"' "$workflow" 'AUR clone inspection may follow top-level symlinks'
require_literal '\( -type l -o \( -type d ! -name .git \) \)' "$workflow" 'AUR clone inspection does not reject every top-level symlink and non-.git directory'
forbid_regex 'find[[:space:]]+-L[[:space:]]+"?\$aur_repo_dir' "$workflow" 'AUR clone inspection follows symlinks'
require_literal 'cp --remove-destination --preserve=mode,timestamps --' "$workflow" 'workflow does not safely copy the exact manifest'
[[ "$(grep -Ec '^[[:space:]]+cp[[:space:]]' "$workflow")" -eq 1 ]] || fail 'workflow contains a copy operation outside the manifest loop'
require_literal 'git -C "$aur_repo_dir" add -- "${AUR_FILES[@]}"' "$workflow" 'AUR staging is not restricted to the manifest'
[[ "$(grep -Fc 'git -C "$aur_repo_dir" add ' "$workflow")" -eq 1 ]] || fail 'workflow contains an additional AUR staging operation'
require_literal 'git -C "$aur_repo_dir" diff --cached --name-only -z' "$workflow" 'workflow does not inspect the complete staged path set'
require_literal '[[ "$staged_file" != */* ]]' "$workflow" 'workflow does not reject staged subpaths'
require_literal 'refusing to stage an out-of-manifest file' "$workflow" 'workflow does not reject out-of-manifest staged changes'
require_literal 'PRIVATE KEY' "$workflow" 'workflow does not scan staged blobs for private-key markers'
[[ "$(grep -Fc 'for asset in "${AUR_FILES[@]}"; do' "$workflow")" -eq 3 ]] || fail 'manifest validation, copy, and staged-source secret scan are not all enforced'
require_literal 'git -C "$aur_repo_dir" diff --cached --quiet' "$workflow" 'workflow does not exit cleanly when AUR already matches'
require_literal 'git -C "$aur_repo_dir" commit --signoff' "$workflow" 'AUR commit does not carry a Signed-off-by trailer'
require_literal 'git -C "$aur_repo_dir" push --dry-run origin HEAD:master' "$workflow" 'AUR non-force push is not dry-run first'
require_literal 'git -C "$aur_repo_dir" push origin HEAD:master' "$workflow" 'AUR independent master is not published'

forbid_regex 'git[[:space:]]+push[^\n]*(--force|-f)([[:space:]]|$)' "$workflow" "$script" 'publication contains a force push'
forbid_regex 'git[[:space:]]+push[[:space:]]+aur([[:space:]]|$)|git[[:space:]]+push[^\n]*aur[^\n]*master' "$workflow" "$script" 'GitHub history is pushed directly to an AUR remote'
forbid_regex 'git[[:space:]]+clean|find[^\n]*-delete|rm[^\n]*aur_repo_dir' "$workflow" 'workflow may delete preserved unknown AUR root files'
forbid_regex 'AUR_SSH_PRIVATE_KEY|AUR_SSH_KNOWN_HOSTS|aur\.archlinux\.org|git[[:space:]]+clone' "$script" 'local publisher still handles AUR credentials or repositories'

require_literal 'git symbolic-ref --quiet --short HEAD' "$script" 'local publisher does not reject detached HEAD'
require_literal '[[ "$branch" == master ]]' "$script" 'local publisher does not require master'
require_literal 'git status --porcelain=v1 --untracked-files=normal' "$script" 'local publisher does not require a clean source worktree'
require_literal 'git remote get-url origin' "$script" 'local publisher does not require the GitHub origin'
require_literal 'git push --dry-run origin master:master' "$script" 'GitHub push is not dry-run first'
require_literal 'git push origin master:master' "$script" 'local publisher does not push the reviewed master branch'
[[ "$(grep -Ec '^git push ' "$script")" -eq 2 ]] || fail 'local publisher contains a push outside the origin master dry-run and publish pair'
require_literal 'aur-production' "$script" 'local publisher does not explain protected workflow publication'

for secret_name in AUR_SSH_PRIVATE_KEY AUR_SSH_KNOWN_HOSTS; do
    [[ "$(grep -Fc -- "\`$secret_name\`" "$readme")" -ge 2 ]] || fail "README does not document $secret_name in both languages"
done
[[ "$(grep -Fic 'dedicated' "$readme")" -ge 1 ]] || fail 'README does not require a dedicated AUR key'
[[ "$(grep -Fc '专用' "$readme")" -ge 1 ]] || fail 'Chinese README does not require a dedicated AUR key'
[[ "$(grep -Fic 'public key' "$readme")" -ge 1 ]] || fail 'README does not instruct adding the public key to the AUR account'
[[ "$(grep -Fc '公钥' "$readme")" -ge 1 ]] || fail 'Chinese README does not instruct adding the public key to the AUR account'
[[ "$(grep -Fic 'independent history' "$readme")" -ge 1 ]] || fail 'README does not explain independent AUR history'
[[ "$(grep -Fc '独立历史' "$readme")" -ge 1 ]] || fail 'Chinese README does not explain independent AUR history'
[[ "$(grep -Fic 'no subdirectories' "$readme")" -ge 1 ]] || fail 'README does not document the root-only AUR snapshot'
[[ "$(grep -Fc '不包含子目录' "$readme")" -ge 1 ]] || fail 'Chinese README does not document the root-only AUR snapshot'
require_literal 'never repository files' "$readme" 'README does not prohibit storing SSH secrets in repository files'
require_literal '绝不能写入仓库文件' "$readme" 'Chinese README does not prohibit storing SSH secrets in repository files'
require_literal 'gh secret set --env aur-production AUR_SSH_PRIVATE_KEY < /path/to/dedicated-aur-key' "$readme" 'README does not show private-key Secret setup with gh'
require_literal 'gh secret set --env aur-production AUR_SSH_KNOWN_HOSTS < /path/to/verified-aur-known-hosts' "$readme" 'README does not show known-hosts Secret setup with gh'
require_literal 'gh secret list --env aur-production' "$readme" 'README does not show non-secret Environment verification with gh'

for asset in .SRCINFO PKGBUILD astrbot-git.install astrbotctl astrbotctl.functions 'astrbot@.service' tmpl.conf no-dashboard-password-in-startup-log.patch; do
    [[ "$(grep -Fc -- "\`$asset\`" "$readme")" -ge 2 ]] || fail "README does not list $asset in both package asset lists"
done

if rg -n --hidden --glob '!.git/**' --glob '!tests/test-publication-contract.sh' -- \
    '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----|(^|[[:space:]])(ssh-rsa|ssh-ed25519|ecdsa-[^[:space:]]+)[[:space:]]+[A-Za-z0-9+/]{40,}' \
    "$repo_dir" >/dev/null; then
    fail 'repository contains private-key or AUR known-host key material'
fi

printf 'PASS: protected workflow publishes the exact root-only AUR snapshot without repository secrets.\n'
