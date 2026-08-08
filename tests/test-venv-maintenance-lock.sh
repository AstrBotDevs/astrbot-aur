#!/usr/bin/env bash
# Verify the actual flock semantics used by the service and maintenance path.
set -Eeuo pipefail

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
lock="$tmp_dir/.venv-maintenance.lock"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

grep -Fq 'ExecStart=/usr/bin/flock --shared --nonblock --no-fork /var/lib/astrbot/%i/.venv-maintenance.lock /usr/bin/astrbotctl __run_astrbot %i' "$repo_dir/astrbot@.service" ||
    fail 'unit does not use exact nonblocking shared maintenance lock'
grep -Eq "depends=\([^)]*'util-linux'" "$repo_dir/PKGBUILD" || fail 'PKGBUILD lacks util-linux runtime dependency'

flock --shared --nonblock --no-fork "$lock" sleep 3 &
shared_pid=$!
sleep 1
if flock --exclusive --nonblock "$lock" true; then fail 'exclusive lock acquired while service lock held'; fi
wait "$shared_pid"
flock --exclusive --nonblock --no-fork "$lock" sleep 3 &
exclusive_pid=$!
sleep 1
if flock --shared --nonblock "$lock" true; then fail 'service lock acquired while maintenance lock held'; fi
wait "$exclusive_pid"
flock --shared --nonblock "$lock" true || fail 'lock did not release'
printf 'PASS: shared/exclusive maintenance lock is nonblocking and releases.\n'
