#!/bin/bash
# Publish the reviewed master branch and a signed package snapshot to AUR.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR
readonly AUR_REPO_URL="ssh://aur@aur.archlinux.org/astrbot-git.git"
AUR_FILES=(
    ".SRCINFO"
    "PKGBUILD"
    "astrbot-git.install"
    "astrbotctl"
    "astrbotctl.functions"
    "astrbot@.service"
    "tmpl.conf"
    "no-dashboard-password-in-startup-log.patch"
)
readonly -a AUR_FILES

cd "$SCRIPT_DIR"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
    echo "Error: update.sh requires a non-detached master branch." >&2
    exit 1
}
[[ "$branch" == master ]] || {
    echo "Error: update.sh only publishes the existing master branch." >&2
    exit 1
}

[[ -z "$(git status --porcelain=v1 --untracked-files=normal)" ]] || {
    echo "Error: commit or remove all local changes before publishing." >&2
    exit 1
}

git remote get-url origin >/dev/null 2>&1 || {
    echo "Error: required GitHub remote 'origin' is not configured." >&2
    exit 1
}

for asset in "${AUR_FILES[@]}"; do
    source_path="$SCRIPT_DIR/$asset"
    [[ -f "$source_path" && ! -L "$source_path" ]] || {
        echo "Error: required AUR source file is missing or not regular: $asset" >&2
        exit 1
    }
done

publish_tmp_parent="$(realpath -e -- "${TMPDIR:-/tmp}")"
[[ -d "$publish_tmp_parent" ]] || {
    echo "Error: temporary directory parent is not a directory." >&2
    exit 1
}
readonly publish_tmp_parent
publish_tmp_dir=""

cleanup() {
    local tmp_dir="${publish_tmp_dir:-}"
    [[ -n "$tmp_dir" && -d "$tmp_dir" ]] || return 0
    [[ "$(dirname -- "$tmp_dir")" == "$publish_tmp_parent" ]] || return 0
    [[ "$(basename -- "$tmp_dir")" == astrbot-git-publish.???????? ]] || return 0
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

publish_tmp_dir="$(mktemp -d -- "$publish_tmp_parent/astrbot-git-publish.XXXXXXXX")"
readonly publish_tmp_dir
readonly aur_repo_dir="$publish_tmp_dir/aur"

# The AUR repository has its own history; publish a package snapshot in that
# history instead of pushing the GitHub branch to it.
git clone --branch master --single-branch -- "$AUR_REPO_URL" "$aur_repo_dir"
[[ "$(git -C "$aur_repo_dir" remote get-url origin)" == "$AUR_REPO_URL" ]] || {
    echo "Error: cloned AUR remote does not match the required SSH URL." >&2
    exit 1
}

for asset in "${AUR_FILES[@]}"; do
    cp --remove-destination --preserve=mode,timestamps -- \
        "$SCRIPT_DIR/$asset" "$aur_repo_dir/$asset"
done

if [[ -n "$(git -C "$aur_repo_dir" status --porcelain=v1 --untracked-files=normal -- "${AUR_FILES[@]}")" ]]; then
    git -C "$aur_repo_dir" add -- "${AUR_FILES[@]}"

    mapfile -d '' staged_files < <(
        git -C "$aur_repo_dir" diff --cached --name-only -z -- "${AUR_FILES[@]}"
    )
    ((${#staged_files[@]} > 0)) || {
        echo "Error: AUR snapshot changed but no manifest file was staged." >&2
        exit 1
    }
    for staged_file in "${staged_files[@]}"; do
        [[ " ${AUR_FILES[*]} " == *" $staged_file "* ]] || {
            echo "Error: refusing to commit an out-of-manifest file: $staged_file" >&2
            exit 1
        }
    done

    source_commit="$(git rev-parse --short=12 HEAD)"
    git -C "$aur_repo_dir" commit -S --signoff \
        -m "chore: publish astrbot-git from $source_commit" -- "${AUR_FILES[@]}"
fi

[[ -z "$(git -C "$aur_repo_dir" status --porcelain=v1 --untracked-files=normal)" ]] || {
    echo "Error: disposable AUR clone is not clean after snapshot preparation." >&2
    exit 1
}

# Complete every remote preflight before either publication becomes real.
git push --dry-run origin master:master
git -C "$aur_repo_dir" push --dry-run origin master:master

if ! git push origin master:master; then
    echo "Error: GitHub publication failed; AUR was not pushed." >&2
    exit 1
fi

if ! git -C "$aur_repo_dir" push origin master:master; then
    echo "PARTIAL PUBLICATION: origin/master was published, but AUR master failed." >&2
    echo "Cross-remote publication is not atomic; inspect the AUR remote and retry safely." >&2
    exit 1
fi

echo "Published master to GitHub and the signed package snapshot to AUR."
