#!/usr/bin/env bash
# Verify the independent-history GitHub and AUR publication architecture.
# shellcheck disable=SC2016 # Literal script-source assertions are intentional.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_dir/update.sh"
readme="$repo_dir/README.md"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
require_literal() {
    grep -Fq -- "$1" "$2" || fail "$3"
}
line_of() {
    grep -Fn -- "$1" "$script" | head -n 1 | cut -d: -f1
}

expected_manifest='AUR_FILES=(
    ".SRCINFO"
    "PKGBUILD"
    "astrbot-git.install"
    "astrbotctl"
    "astrbotctl.functions"
    "astrbot@.service"
    "tmpl.conf"
    "no-dashboard-password-in-startup-log.patch"
)'
actual_manifest="$(sed -n '/^AUR_FILES=(/,/^)/p' "$script")"
[[ "$actual_manifest" == "$expected_manifest" ]] || fail 'AUR publication manifest is not the exact eight-file allowlist'

require_literal 'readonly AUR_REPO_URL="ssh://aur@aur.archlinux.org/astrbot-git.git"' "$script" 'AUR SSH URL is not exact'
require_literal 'git symbolic-ref --quiet --short HEAD' "$script" 'publisher does not reject detached HEAD'
require_literal '[[ "$branch" == master ]]' "$script" 'publisher does not require master'
require_literal 'git status --porcelain=v1 --untracked-files=normal' "$script" 'publisher does not require a clean source worktree'
require_literal 'git remote get-url origin' "$script" 'publisher does not preflight the GitHub origin remote'
require_literal '[[ -f "$source_path" && ! -L "$source_path" ]]' "$script" 'publisher does not validate regular manifest source files'

require_literal 'publish_tmp_parent="$(realpath -e -- "${TMPDIR:-/tmp}")"' "$script" 'publisher does not canonicalize the temporary parent'
require_literal 'mktemp -d -- "$publish_tmp_parent/astrbot-git-publish.XXXXXXXX"' "$script" 'publisher does not create a disposable directory with mktemp'
require_literal '[[ "$(dirname -- "$tmp_dir")" == "$publish_tmp_parent" ]]' "$script" 'cleanup is not restricted to the canonical temporary parent'
require_literal '[[ "$(basename -- "$tmp_dir")" == astrbot-git-publish.???????? ]]' "$script" 'cleanup is not restricted to the unique publication directory pattern'
require_literal 'rm -rf -- "$tmp_dir"' "$script" 'publisher does not clean only the validated mktemp directory'
require_literal 'trap cleanup EXIT' "$script" 'publisher cleanup is not trap-safe'
trap_line="$(line_of 'trap cleanup EXIT')"
mktemp_line="$(line_of 'publish_tmp_dir="$(mktemp -d --')"
((trap_line < mktemp_line)) || fail 'cleanup trap must be active before mktemp creates the directory'
require_literal 'git clone --branch master --single-branch -- "$AUR_REPO_URL" "$aur_repo_dir"' "$script" 'publisher does not clone the independent AUR master history over SSH'

[[ $(grep -Fc 'for asset in "${AUR_FILES[@]}"; do' "$script") -ge 2 ]] || fail 'manifest is not used for validation and copy'
require_literal 'cp --remove-destination --preserve=mode,timestamps --' "$script" 'publisher does not safely copy manifest files'
require_literal 'git -C "$aur_repo_dir" add -- "${AUR_FILES[@]}"' "$script" 'AUR staging is not limited to the manifest'
require_literal 'git -C "$aur_repo_dir" commit -S --signoff' "$script" 'AUR snapshot commit is not signed and signed off'
require_literal 'git -C "$aur_repo_dir" status --porcelain=v1 --untracked-files=normal -- "${AUR_FILES[@]}"' "$script" 'publisher does not detect new and modified manifest files'

origin_dry_line="$(line_of 'git push --dry-run origin master:master')"
aur_dry_line="$(line_of 'git -C "$aur_repo_dir" push --dry-run origin master:master')"
origin_real_line="$(line_of 'if ! git push origin master:master; then')"
aur_real_line="$(line_of 'if ! git -C "$aur_repo_dir" push origin master:master; then')"
[[ -n "$origin_dry_line" && -n "$aur_dry_line" && -n "$origin_real_line" && -n "$aur_real_line" ]] || fail 'publisher is missing dry-run or real push legs'
((origin_dry_line < aur_dry_line && aur_dry_line < origin_real_line && origin_real_line < aur_real_line)) || fail 'both dry runs must finish before origin-first real publication'

require_literal 'PARTIAL PUBLICATION: origin/master was published, but AUR master failed.' "$script" 'publisher does not identify second-leg partial publication'
require_literal 'Cross-remote publication is not atomic' "$script" 'publisher does not explain cross-remote non-atomicity'

if rg -n 'git[[:space:]]+push[[:space:]]+aur([[:space:]]|$)' "$script" >/dev/null; then
    fail 'publisher still pushes GitHub master directly to an AUR remote'
fi
if rg -qi 'github actions|aur-publish|workflow' "$script" "$readme"; then
    fail 'publication documentation still claims workflow publication'
fi

require_literal 'ssh://aur@aur.archlinux.org/astrbot-git.git' "$readme" 'README does not document direct SSH AUR publication'
for asset in .SRCINFO PKGBUILD astrbot-git.install astrbotctl astrbotctl.functions 'astrbot@.service' tmpl.conf no-dashboard-password-in-startup-log.patch; do
    [[ $(grep -Fc -- "\`$asset\`" "$readme") -ge 2 ]] || fail "README does not list $asset in both package asset lists"
done

printf 'PASS: publication uses independent GitHub and signed SSH AUR histories with full preflight.\n'
