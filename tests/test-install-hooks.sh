#!/usr/bin/env bash
# Exercise install-hook instance detection without touching system paths.
set -Eeuo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed "s|/etc/astrbot|$tmp_dir/etc|g" "$repo_dir/astrbot-git.install" >"$tmp_dir/hooks"
# shellcheck disable=SC1091
. "$tmp_dir/hooks"
# shellcheck disable=SC2329 # Called indirectly by the install hook.
astrbotctl() { printf '%s\n' "$*" >>"$tmp_dir/sync-calls"; }
_sync_instances_best_effort
[[ ! -e "$tmp_dir/sync-calls" ]] || fail 'missing configuration directory triggered sync'
mkdir "$tmp_dir/etc"
: >"$tmp_dir/etc/tmpl.conf"
_sync_instances_best_effort
[[ ! -e "$tmp_dir/sync-calls" ]] || fail 'template-only installation triggered sync'
mkdir "$tmp_dir/etc/directory.conf"
ln -s tmpl.conf "$tmp_dir/etc/link.conf"
_sync_instances_best_effort
[[ ! -e "$tmp_dir/sync-calls" ]] || fail 'non-regular configuration triggered sync'
: >"$tmp_dir/etc/bot1.conf"
_sync_instances_best_effort
[[ $(cat "$tmp_dir/sync-calls") == 'sync --all' ]] || fail 'existing instance did not trigger exactly one sync'
printf 'PASS: install hooks sync actual instances and skip the configuration template.\n'
