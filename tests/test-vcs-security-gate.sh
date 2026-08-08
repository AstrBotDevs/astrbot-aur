#!/usr/bin/env bash
# Exercise the dashboard credential patch gate against disposable Git fixtures.
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

legacy_commit_gate() {
    [[ "$1" == b3949f97bdd46a1ef4bf20c1093ccc49f02a2f1e ]]
}

make_fixture() {
    local name="$1" fixture target
    fixture="$tmp_dir/$name"
    target="$fixture/AstrBot/astrbot/dashboard/server.py"
    mkdir -p "$(dirname "$target")"
    cp "$repo_dir/no-dashboard-password-in-startup-log.patch" "$fixture/no-dashboard-password-in-startup-log.patch"
    for _ in $(seq 1 431); do
        printf '\n' >>"$target"
    done
    cat >>"$target" <<'PY'
class CredentialsDisplay:
    def __init__(self, config):
        self.config = config

    def _build_dashboard_credentials_display(self) -> str:
        username = self.config["dashboard"].get("username", "astrbot")
        generated_password = getattr(self.config, "_generated_dashboard_password", None)
        if not generated_password:
            return f"   ➜  Username: {username}\n ✨✨✨\n"

        credentials_display = (
            f"   ➜  Initial username: {username}\n"
            f"   ➜  Initial password: {generated_password}\n"
            "   ➜  Change it after logging in\n ✨✨✨\n"
        )
        object.__setattr__(self.config, "_generated_dashboard_password", None)
        return credentials_display

    @staticmethod
    def _resolve_dashboard_ssl_config(
        ssl_config: dict,
    ) -> tuple[bool, dict[str, str]]:
        return False, {}
PY
    git -C "$fixture/AstrBot" init -q
    git -C "$fixture/AstrBot" add astrbot/dashboard/server.py
    git -C "$fixture/AstrBot" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm baseline
    printf '%s\n' "$fixture"
}

run_prepare() {
    local fixture="$1"
    (
        # shellcheck disable=SC2034 # Consumed by the sourced PKGBUILD.
        srcdir="$fixture"
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced PKGBUILD.
        error() { printf '%s\n' "$*" >&2; }
        # shellcheck disable=SC1091
        . "$repo_dir/PKGBUILD"
        prepare
    )
}

fixture="$(make_fixture reviewed-preimage)"
if legacy_commit_gate 30e20318cbaaa2e1ba57f3e0eee265d9ee98115c; then
    fail 'legacy whole-commit gate accepted an unrelated current-master commit'
fi
run_prepare "$fixture" || fail 'reviewed preimage did not apply'
target="$fixture/AstrBot/astrbot/dashboard/server.py"
python - "$target" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("fixture_server", pathlib.Path(sys.argv[1]))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class Config(dict):
    pass
config = Config(dashboard={"username": "fixture-user"})
object.__setattr__(config, "_generated_dashboard_password", "sentinel-password")
display = module.CredentialsDisplay(config)._build_dashboard_credentials_display()
assert "sentinel-password" not in display
assert "Initial password:" not in display
assert getattr(config, "_generated_dashboard_password") is None
PY
run_prepare "$fixture" || fail 'dirty exact postimage was not idempotently accepted'

fixture="$(make_fixture unrelated-change)"
printf '%s\n' '# unrelated current-master change' >>"$fixture/AstrBot/astrbot/dashboard/server.py"
git -C "$fixture/AstrBot" add astrbot/dashboard/server.py
git -C "$fixture/AstrBot" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm unrelated
run_prepare "$fixture" || fail 'unrelated source change outside protected function was rejected'

fixture="$(make_fixture protected-change)"
target="$fixture/AstrBot/astrbot/dashboard/server.py"
sed -i '/def _build_dashboard_credentials_display/a\        "reviewed drift"' "$target"
if ! patch --dry-run --batch --forward --fuzz=0 -p1 -d "$fixture/AstrBot" -i "$fixture/no-dashboard-password-in-startup-log.patch" >/dev/null; then
    fail 'fixture did not prove a protected-function drift can retain an applicable hunk'
fi
if run_prepare "$fixture"; then
    fail 'protected-function drift was accepted'
fi

fixture="$(make_fixture hunk-context-change)"
target="$fixture/AstrBot/astrbot/dashboard/server.py"
sed -i 's/Initial username/Changed username/' "$target"
if patch --dry-run --batch --forward --fuzz=0 -p1 -d "$fixture/AstrBot" -i "$fixture/no-dashboard-password-in-startup-log.patch" >/dev/null 2>&1; then
    fail 'fuzz=0 accepted a changed patch hunk context'
fi
if run_prepare "$fixture"; then
    fail 'unknown protected-function preimage was accepted'
fi

fixture="$(make_fixture clean-postimage)"
run_prepare "$fixture" || fail 'could not create reviewed postimage fixture'
git -C "$fixture/AstrBot" add astrbot/dashboard/server.py
git -C "$fixture/AstrBot" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm upstream-postimage
if run_prepare "$fixture"; then
    fail 'clean exact postimage was accepted without review'
fi

printf 'PASS: VCS security gate accepts reviewed context and fails closed on credential drift.\n'
