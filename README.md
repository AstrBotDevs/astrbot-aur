# astrbot-git

<div align="center">
  <p>
    <a href="PKGBUILD"><img alt="AUR" src="https://img.shields.io/badge/AUR-git-1793d1?logo=archlinux&logoColor=white" /></a>
    <a href="PKGBUILD"><img alt="AGPL-3.0" src="https://img.shields.io/badge/License-AGPL--3.0-red.svg" /></a>
    <a href="astrbot@.service"><img alt="systemd" src="https://img.shields.io/badge/systemd-template-6a737d" /></a>
    <a href="astrbotctl"><img alt="CLI" src="https://img.shields.io/badge/CLI-astrbotctl-0ea5e9" /></a>
  </p>
</div>

<p align="center">
  <a href="#overview">Overview</a>
  · <a href="#install">Install</a>
  · <a href="#quick-start">Quick Start</a>
  · <a href="#简体中文速览">简体中文</a>
</p>

Arch Linux AUR package for [AstrBot](https://github.com/AstrBotDevs/AstrBot).

This package installs the upstream `master` branch under `/opt/astrbot` and provides
`astrbotctl` plus a systemd template unit for multi-instance deployments.

## Overview

`astrbot-git` packages AstrBot for Arch Linux in a way that is friendly to long-lived, multi-instance deployments.

- upstream source is installed in `/opt/astrbot`
- instance configs live under `/etc/astrbot`
- runtime state lives under `/var/lib/astrbot/<name>`
- `astrbotctl` manages init, service lifecycle, plugins, backups, and sync

## Install

```bash
paru -S astrbot-git
```

## 简体中文速览

这是 AstrBot 的 Arch Linux AUR 打包仓库。

- 安装后使用 `astrbotctl` 管理实例。
- 支持 systemd 模板服务 `astrbot@.service`。
- 适合单实例和多实例部署。

## Quick Start

```bash
sudo astrbotctl init bot1
sudo systemctl enable --now astrbot@bot1
astrbotctl status bot1
```

The instance config is written to `/etc/astrbot/bot1.conf`. Runtime data and the
instance virtualenv live under `/var/lib/astrbot/bot1`.

The dashboard port is allocated during `init` and stored in the instance config:

```bash
grep '^ASTRBOT_PORT=' /etc/astrbot/bot1.conf
```

Then open:

```text
http://localhost:<port>
```

## Common Commands

```bash
astrbotctl ls
sudo astrbotctl start bot1
sudo astrbotctl stop bot1
sudo astrbotctl restart bot1
astrbotctl paths bot1
```

Run AstrBot commands inside an instance:

```bash
astrbotctl cli bot1 plug list
astrbotctl cli bot1 plug install <plugin_repo>
```

Run an instance in the foreground for debugging:

```bash
sudo astrbotctl run bot1
```

This uses the instance environment and ultimately runs AstrBot's `astrbot run`
command from `/var/lib/astrbot/bot1/.venv`.

Manage dashboard credentials:

```bash
sudo astrbotctl admin -u admin -p 'new-password' bot1
```

Back up and restore:

```bash
astrbotctl export bot1
astrbotctl import bot1 /path/to/backup.zip
```

Refresh an instance virtualenv after a package upgrade:

```bash
sudo astrbotctl sync bot1
sudo astrbotctl sync --all
```

## HTTPS

`certbot` is optional. Install it before using the helper:

```bash
sudo pacman -S certbot
sudo astrbotctl certbot bot1
```

## Paths

| Path | Purpose |
| --- | --- |
| `/opt/astrbot` | Packaged upstream source |
| `/usr/bin/astrbotctl` | Management command |
| `/usr/lib/systemd/system/astrbot@.service` | Instance service template |
| `/etc/astrbot/<name>.conf` | Instance config |
| `/var/lib/astrbot/<name>` | Instance data and virtualenv |
| `/var/cache/astrbot` | Shared package/runtime cache |

## Troubleshooting

Follow logs:

```bash
journalctl -u astrbot@bot1 -f
```

Remove a stale runtime lock:

```bash
sudo rm -f /var/lib/astrbot/bot1/astrbot.lock
```

If a service fails with `权限不够` for files under `/var/lib/astrbot/<name>`,
fix ownership:

```bash
sudo chown -R astrbot:astrbot /var/lib/astrbot/bot1
```

If startup reports that the dashboard port is already in use, find and stop the
old foreground process before starting the systemd service:

```bash
sudo ss -lntp | grep ':<port>'
sudo kill <pid>
sudo systemctl restart astrbot@bot1
```

Force a virtualenv rebuild:

```bash
sudo rm -rf /var/lib/astrbot/bot1/.venv
sudo systemctl restart astrbot@bot1
```

## Packaging

Local package maintenance helper:

```bash
./update.sh
```

Before publishing, regenerate `.SRCINFO`:

```bash
makepkg --printsrcinfo > .SRCINFO
```
