#!/usr/bin/env bash
# Verify local package assets without downloading the floating upstream source.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
declare -a source=() sha256sums=()
# shellcheck source=../PKGBUILD
source "$repo_dir/PKGBUILD"
[[ ${#source[@]} -gt 0 ]] || fail 'package has no sources'
[[ ${#source[@]} -eq ${#sha256sums[@]} ]] || fail 'source/checksum array lengths differ'
for index in "${!source[@]}"; do
    asset="${source[$index]}"
    expected="${sha256sums[$index]}"
    if [[ $asset == git+https://* ]]; then
        [[ $expected == SKIP ]] || fail 'floating VCS source must use SKIP'
        continue
    fi
    [[ $asset != */* && -f $asset && ! -L $asset ]] || fail "invalid local source: $asset"
    [[ $expected =~ ^[a-f0-9]{64}$ ]] || fail "local source lacks a pinned SHA-256: $asset"
    observed="$(sha256sum -- "$asset")"
    [[ ${observed%% *} == "$expected" ]] || fail "checksum mismatch: $asset"
done
printf 'PASS: every local package source matches its pinned SHA-256.\n'
