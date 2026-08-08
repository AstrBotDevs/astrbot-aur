#!/usr/bin/env bash
set -Eeuo pipefail
if [[ ${EUID} -ne 0 ]]; then exec sudo --preserve-env=PATH -- bash "$0" "$@"; fi
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
fail(){ echo "FAIL: $*" >&2; exit 1; }
make(){ mkdir -p "$1/bin"; : >"$1/bin/python"; : >"$1/bin/astrbot"; : >"$1/pyvenv.cfg"; chmod +x "$1/bin/python" "$1/bin/astrbot"; echo "$2" >"$1/.astrbot-app-version"; chown -R astrbot:astrbot "$1"; }
. "$repo_dir/astrbotctl.functions"; instance=x; ASTRBOT_ROOT="$tmp/root"; mkdir -p "$ASTRBOT_ROOT" "$tmp/cache"; make "$ASTRBOT_ROOT/.venv" current; make "$tmp/cache/backup" old
mkdir "$tmp/bin"; cat >"$tmp/bin/mv" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [[ $a == --exchange ]] && exit 95; done
exec /usr/bin/mv "$@"
EOF
chmod +x "$tmp/bin/mv"
if PATH="$tmp/bin:$PATH" restore_venv_backup_atomically "$ASTRBOT_ROOT/.venv" "$tmp/cache/backup" sync_failure; then fail 'forced exchange failure succeeded'; fi
[[ $(cat "$ASTRBOT_ROOT/.venv/.astrbot-app-version") == current ]] || fail 'exchange failure changed destination'
[[ -d "$tmp/cache/backup" ]] || fail 'exchange failure removed source backup'
find "$ASTRBOT_ROOT" -maxdepth 1 -type d -name '.venv.rollback.*' -print -quit | grep -q . && fail 'pre-exchange stage leaked'
printf 'PASS: exchange failure preserves live venv and backup.\n'
