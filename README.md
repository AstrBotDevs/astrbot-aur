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
  <a href="#english">English</a>
  ·
  <a href="#简体中文">简体中文</a>
</p>

## English

`astrbot-git` is the Arch Linux AUR package for
[AstrBot](https://github.com/AstrBotDevs/AstrBot).

It packages the upstream `master` branch under `/opt/astrbot` and provides
`astrbotctl`, a systemd template unit, and per-instance runtime isolation for
long-running multi-bot deployments.

### Features

- Installs upstream AstrBot source to `/opt/astrbot`
- Supports multiple isolated instances on one host
- Stores instance configuration under `/etc/astrbot`
- Stores instance data and Python virtualenvs under `/var/lib/astrbot/<name>`
- Uses `uv` to build and refresh per-instance Python environments
- Provides `astrbot@.service` for systemd-managed services
- Includes helpers for updates, HTTPS certificates, and cleanup; use the Dashboard for authenticated backup and restore

### Install

```bash
paru -S astrbot-git
```

Other AUR helpers work as long as they build standard Arch packages.

### Quick Start

Create an instance:

```bash
sudo astrbotctl init bot1
```

Start it with systemd:

```bash
sudo systemctl enable --now astrbot@bot1
```

Check status and inspect generated paths:

```bash
astrbotctl status bot1
astrbotctl paths bot1
```

The instance config is generated at `/etc/astrbot/bot1.conf`. The runtime data
and virtualenv are created under `/var/lib/astrbot/bot1`.

The dashboard port is allocated during `init` and written to the instance
config:

```bash
grep '^ASTRBOT_PORT=' /etc/astrbot/bot1.conf
```

Then open:

```text
http://localhost:<port>
```

### Instance Management

```bash
sudo astrbotctl init bot1
sudo astrbotctl cp bot1 bot3
sudo astrbotctl rm bot3
sudo astrbotctl reset bot1
```

Service commands:

```bash
sudo astrbotctl start bot1
sudo astrbotctl stop bot1
sudo astrbotctl restart bot1
astrbotctl status bot1
astrbotctl ls
```

Run AstrBot directly inside an instance environment:

```bash
sudo astrbotctl run bot1
astrbotctl cli bot1 plug list
astrbotctl cli bot1 plug install <plugin_repo>
```

Manage dashboard credentials:

```bash
sudo astrbotctl password bot1
```

The command prompts twice on the controlling terminal and must be run before
the first service start. To change the dashboard username at the same time:

```bash
sudo astrbotctl password --username admin bot1
```

Back up and restore through the authenticated Dashboard. Restore is destructive;
`astrbotctl init -f`, `astrbotctl export`, and `astrbotctl import` are retired
because current upstream AstrBot no longer provides the backup CLI.

Refresh instance environments after a package upgrade:

```bash
sudo astrbotctl sync bot1
sudo astrbotctl sync --all
sudo astrbotctl update bot1
sudo astrbotctl update --all
```

Clean caches:

```bash
sudo astrbotctl clean
```

### HTTPS

`certbot` is optional. Install it before using the helper:

```bash
sudo pacman -S certbot
sudo astrbotctl certbot bot1
```

The helper requests a Let's Encrypt certificate, copies the certificate files
into an instance-specific directory under `/etc/astrbot/certs`, updates the
instance config, installs a deploy hook, and restarts the systemd service.

### Paths

| Path | Purpose |
| --- | --- |
| `/opt/astrbot` | Packaged upstream AstrBot source |
| `/opt/astrbot/.version` | Packaged source version marker |
| `/usr/bin/astrbotctl` | Management command |
| `/usr/bin/astrbotctl.functions` | Shared helper library used by `astrbotctl` |
| `/usr/lib/systemd/system/astrbot@.service` | systemd template unit |
| `/etc/astrbot/tmpl.conf` | Template used by `astrbotctl init` and `reset` |
| `/etc/astrbot/<name>.conf` | Per-instance config |
| `/etc/astrbot/certs/<name>` | Per-instance certificate copies |
| `/var/lib/astrbot/<name>` | Per-instance data, home directory, and virtualenv |
| `/var/cache/astrbot` | Shared package/runtime cache |

### Troubleshooting

Follow logs:

```bash
journalctl -u astrbot@bot1 -f
```

Fix ownership if an instance reports permission errors under
`/var/lib/astrbot/<name>`:

```bash
sudo chown -R astrbot:astrbot /var/lib/astrbot/bot1
```

If the dashboard port is already in use, find and stop the old process before
restarting the service:

```bash
sudo ss -lntp | grep ':<port>'
sudo kill <pid>
sudo systemctl restart astrbot@bot1
```

Force an instance virtualenv rebuild:

```bash
sudo rm -rf /var/lib/astrbot/bot1/.venv
sudo astrbotctl sync bot1
```

### Packaging

This repository is the GitHub mirror for the AUR package. `./update.sh` pushes
the reviewed `master` branch to GitHub, clones
`ssh://aur@aur.archlinux.org/astrbot-git.git` into a disposable directory, and
creates a signed snapshot commit in the AUR repository's independent history.
Both non-force pushes are dry-run before GitHub is published, followed by AUR.

The AUR snapshot contains exactly these files:

- `.SRCINFO`
- `PKGBUILD`
- `astrbot-git.install`
- `astrbotctl`
- `astrbotctl.functions`
- `astrbot@.service`
- `tmpl.conf`
- `no-dashboard-password-in-startup-log.patch`

Before publishing manually, regenerate `.SRCINFO`:

```bash
makepkg --printsrcinfo > .SRCINFO
```

## 简体中文

`astrbot-git` 是 [AstrBot](https://github.com/AstrBotDevs/AstrBot) 的 Arch
Linux AUR 软件包。

它会把上游 `master` 分支安装到 `/opt/astrbot`，并提供 `astrbotctl`、
systemd 模板服务和按实例隔离的运行环境，适合在同一台机器上长期运行多个
机器人实例。

### 功能特性

- 将上游 AstrBot 源码安装到 `/opt/astrbot`
- 支持在同一台主机上运行多个相互隔离的实例
- 实例配置保存在 `/etc/astrbot`
- 实例数据和 Python 虚拟环境保存在 `/var/lib/astrbot/<实例名>`
- 使用 `uv` 创建和刷新每个实例的 Python 环境
- 提供 `astrbot@.service`，可用 systemd 管理实例
- 提供更新、HTTPS 证书和缓存清理辅助命令；经认证的备份和恢复请使用 Dashboard

### 安装

```bash
paru -S astrbot-git
```

其他 AUR helper 也可以使用，只要它能正常构建标准 Arch 软件包。

### 快速开始

创建实例：

```bash
sudo astrbotctl init bot1
```

用 systemd 启动：

```bash
sudo systemctl enable --now astrbot@bot1
```

查看状态和实例路径：

```bash
astrbotctl status bot1
astrbotctl paths bot1
```

实例配置会生成到 `/etc/astrbot/bot1.conf`。运行时数据和虚拟环境会创建在
`/var/lib/astrbot/bot1`。

控制台端口会在 `init` 时自动分配，并写入实例配置：

```bash
grep '^ASTRBOT_PORT=' /etc/astrbot/bot1.conf
```

然后打开：

```text
http://localhost:<端口>
```

### 实例管理

```bash
sudo astrbotctl init bot1
sudo astrbotctl cp bot1 bot3
sudo astrbotctl rm bot3
sudo astrbotctl reset bot1
```

服务命令：

```bash
sudo astrbotctl start bot1
sudo astrbotctl stop bot1
sudo astrbotctl restart bot1
astrbotctl status bot1
astrbotctl ls
```

在实例环境中直接运行 AstrBot：

```bash
sudo astrbotctl run bot1
astrbotctl cli bot1 plug list
astrbotctl cli bot1 plug install <插件仓库>
```

管理控制台账号密码：

```bash
sudo astrbotctl password bot1
```

该命令会在当前终端中隐藏输入并要求确认，必须在首次启动服务前执行。如需同时
修改控制台用户名：

```bash
sudo astrbotctl password --username admin bot1
```

请通过 Dashboard 中经认证的流程执行备份和恢复。恢复会覆盖现有数据；由于当前
上游 AstrBot 已移除备份 CLI，`astrbotctl init -f`、`astrbotctl export` 和
`astrbotctl import` 已退役。

软件包升级后刷新实例环境：

```bash
sudo astrbotctl sync bot1
sudo astrbotctl sync --all
sudo astrbotctl update bot1
sudo astrbotctl update --all
```

清理缓存：

```bash
sudo astrbotctl clean
```

### HTTPS

`certbot` 是可选依赖。使用 HTTPS 辅助命令前先安装：

```bash
sudo pacman -S certbot
sudo astrbotctl certbot bot1
```

该辅助命令会申请 Let's Encrypt 证书，把证书复制到 `/etc/astrbot/certs`
下的实例目录，更新实例配置，安装续期 deploy hook，并重启 systemd 服务。

### 路径说明

| 路径 | 用途 |
| --- | --- |
| `/opt/astrbot` | 打包安装的上游 AstrBot 源码 |
| `/opt/astrbot/.version` | 打包源码版本标记 |
| `/usr/bin/astrbotctl` | 管理命令 |
| `/usr/bin/astrbotctl.functions` | `astrbotctl` 使用的共享函数库 |
| `/usr/lib/systemd/system/astrbot@.service` | systemd 模板服务 |
| `/etc/astrbot/tmpl.conf` | `astrbotctl init` 和 `reset` 使用的配置模板 |
| `/etc/astrbot/<实例名>.conf` | 单个实例的配置文件 |
| `/etc/astrbot/certs/<实例名>` | 单个实例的证书副本 |
| `/var/lib/astrbot/<实例名>` | 单个实例的数据、HOME 目录和虚拟环境 |
| `/var/cache/astrbot` | 共享包缓存和运行时缓存 |

### 故障排除

查看日志：

```bash
journalctl -u astrbot@bot1 -f
```

如果实例提示 `/var/lib/astrbot/<实例名>` 下的权限错误，修复所有权：

```bash
sudo chown -R astrbot:astrbot /var/lib/astrbot/bot1
```

如果控制台端口已被占用，先找到并停止旧进程，再重启服务：

```bash
sudo ss -lntp | grep ':<端口>'
sudo kill <pid>
sudo systemctl restart astrbot@bot1
```

强制重建某个实例的虚拟环境：

```bash
sudo rm -rf /var/lib/astrbot/bot1/.venv
sudo astrbotctl sync bot1
```

### 打包维护

这个仓库是 AUR 软件包的 GitHub 镜像。`./update.sh` 会将已审核的
`master` 分支推送到 GitHub，并把
`ssh://aur@aur.archlinux.org/astrbot-git.git` 克隆到一次性目录，在 AUR
仓库的独立历史中创建签名快照提交。两个非强制推送都会提前 dry-run，
实际发布顺序为 GitHub、AUR。

AUR 快照严格包含以下文件：

- `.SRCINFO`
- `PKGBUILD`
- `astrbot-git.install`
- `astrbotctl`
- `astrbotctl.functions`
- `astrbot@.service`
- `tmpl.conf`
- `no-dashboard-password-in-startup-log.patch`

如需手动发布，发布前重新生成 `.SRCINFO`：

```bash
makepkg --printsrcinfo > .SRCINFO
```
