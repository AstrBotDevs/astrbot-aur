# Maintainer: lightjunction <lightjunction.me@gmail.com>

pkgname=astrbot-git
_pkgname=astrbot
pkgver=4.20.1.r128.ge8c234f0c
pkgrel=25
pkgdesc="Agentic IM Chatbot infrastructure (multi-instance, astrbotctl only)"
arch=('any')
url="https://github.com/AstrBotDevs/AstrBot"
license=('AGPL-3.0-only')

depends=('python' 'uv' 'iproute2')
makedepends=('git')

provides=("$_pkgname")
conflicts=("$_pkgname")

source=(
    "$pkgname::git+$url.git#branch=dev"
    "astrbotctl"
    "astrbot@.service"
    "config.template"
)

sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

install=astrbot-git.install

pkgver() {
    cd "$pkgname"
    git describe --long --tags 2>/dev/null |
        sed 's/\([^-]*-g\)/r\1/;s/-/./g' |
        sed 's/^v//g' ||
        echo "0.0.0.r$(git rev-list --count HEAD).g$(git rev-parse --short HEAD)"
}

package() {
    cd "$pkgname"

    local _appdir="/opt/$_pkgname"

    # 程序本体
    install -d "$pkgdir$_appdir"
    cp -r astrbot scripts pyproject.toml README.md LICENSE "$pkgdir$_appdir/"

    # 配置文件模板
    install -Dm644 "$srcdir/config.template" "$pkgdir$_appdir/config.template"

    # 控制工具（唯一入口）
    install -Dm755 "$srcdir/astrbotctl" \
        "$pkgdir/usr/bin/astrbotctl"

    # systemd
    install -Dm644 "$srcdir/astrbot@.service" \
        "$pkgdir/usr/lib/systemd/system/astrbot@.service"

    # license
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
