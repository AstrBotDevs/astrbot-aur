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

`cp` copies instance data and creates a new configuration with a free port.
It does not reuse the source virtualenv: Python entrypoints contain absolute
paths, so the destination builds its own environment on its next run.

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

Clean caches (virtualenv cleanup refuses active or maintenance-locked instances):

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
| `/var/lib/astrbot/<name>` | Single per-instance runtime root (`HOME`, XDG directories, `data/`, and virtualenv) |
| `/var/lib/astrbot/<name>/data` | AstrBot application data and configuration (`cmd_config.json`, plugins, backups, WebUI assets) |
| `/var/lib/astrbot/<name>/.cache` | Per-instance XDG/uv cache |
| `/var/cache/astrbot` | Shared package/runtime cache |

Older package versions could create an empty `/var/lib/astrbot/<name>/home`
directory. On the first runtime operation after this update, empty legacy
directories are removed and non-conflicting legacy entries are moved into the
instance root. Non-empty conflicts are preserved and reported rather than
overwritten.

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

### Development checks

Run the safe check entrypoint as a regular user:

```bash
bash scripts/check.sh
```

Install the test tools on Arch:

```bash
sudo pacman -S --needed base-devel shellcheck python git gettext ripgrep libarchive
```

The check runs Bash syntax validation, ShellCheck, local source checksums,
`.SRCINFO` comparison when `makepkg` is available, and an explicit list of
rootless regression suites. PR and master-branch CI run the same check
in an Arch container. These tests use temporary fixtures and mock service
commands; they do not publish packages or contact running instances.

Do not run `tests/*.sh` as a blanket loop. Other tests may invoke `sudo`, change
real services, or require a particular installed package. Run those only in a
disposable Arch VM. `test-pkgrel4-red-regressions.sh` documents a historical
broken release and is not a current-release acceptance test.

### Packaging

After changing a local package asset, update its `sha256sums` entry in `PKGBUILD`
and regenerate `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO` before running
the checks. Only the floating upstream Git source uses `SKIP`.

This repository is the GitHub source for the AUR package. `./update.sh` checks
and pushes the reviewed `master` branch to GitHub. The protected
`aur-production` GitHub Actions environment then publishes the package to
`ssh://aur@aur.archlinux.org/astrbot-git.git` in its independent history.

Create a dedicated, least-privilege SSH key for AUR publishing and add its
public key to the maintainer's AUR account. Store the private key and verified
AUR host-key lines as GitHub Environment Secrets, never repository files. The
workflow reads exactly `AUR_SSH_PRIVATE_KEY` and `AUR_SSH_KNOWN_HOSTS`; it does
not discover host keys at runtime.

Configure and verify the `aur-production` Environment with the GitHub CLI
without printing either value:

```bash
gh secret set --env aur-production AUR_SSH_PRIVATE_KEY < /path/to/dedicated-aur-key
gh secret set --env aur-production AUR_SSH_KNOWN_HOSTS < /path/to/verified-aur-known-hosts
gh secret list --env aur-production
```

The AUR snapshot contains exactly these files:

- `.SRCINFO`
- `PKGBUILD`
- `astrbot-git.install`
- `astrbotctl`
- `astrbotctl.functions`
- `astrbot@.service`
- `tmpl.conf`
- `no-dashboard-password-in-startup-log.patch`

Only these regular root files are copied and staged. The AUR has no subdirectories.
Existing unknown root files in the independent AUR repository are preserved
rather than deleted.

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

`cp` 会复制实例数据，并为新配置分配空闲端口。Python 入口脚本包含绝对路径，
因此新实例不会复用源实例的虚拟环境，而是在下次运行时重建。

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

清理缓存（虚拟环境清理会跳过正在运行或被维护锁占用的实例，并返回失败状态）：

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
| `/var/lib/astrbot/<实例名>` | 每个实例唯一的运行根目录（`HOME`、XDG 目录、`data/` 和虚拟环境） |
| `/var/lib/astrbot/<实例名>/data` | AstrBot 业务数据与配置（`cmd_config.json`、插件、备份和 WebUI 资源） |
| `/var/lib/astrbot/<实例名>/.cache` | 每个实例独立的 XDG/uv 缓存 |
| `/var/cache/astrbot` | 共享包缓存和运行时缓存 |

旧版本可能会创建空的 `/var/lib/astrbot/<实例名>/home` 目录。本次更新后，
实例第一次执行运行时操作时，会删除空的旧目录，并把没有路径冲突的旧内容
移动到实例根目录；如果目标路径已有非空内容，则保留旧内容并提示，不会覆盖。

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

### 开发检查

以普通用户运行安全检查入口：

```bash
bash scripts/check.sh
```

在 Arch 上安装测试工具：

```bash
sudo pacman -S --needed base-devel shellcheck python git gettext ripgrep libarchive
```

该入口检查 Bash 语法、ShellCheck、本地源文件校验和、有 `makepkg` 时的
`.SRCINFO` 一致性，并执行明确列出的非特权回归测试。PR 和 master 分支的 CI
在 Arch 容器中运行相同检查。测试只使用临时夹具和模拟服务命令，不发布软件包，
也不接触正在运行的实例。

不要循环执行全部 `tests/*.sh`：其他测试可能自动调用 `sudo`、修改真实服务，
或要求特定已安装版本。这些测试只能在一次性 Arch 虚拟机中运行。
`test-pkgrel4-red-regressions.sh` 用于复现历史版本缺陷，不是当前版本的验收测试。

### 打包维护

修改本地打包文件后，先更新 `PKGBUILD` 中对应的 `sha256sums`，再执行
`makepkg --printsrcinfo > .SRCINFO` 更新元数据，最后运行检查。只有浮动的上游
Git 源使用 `SKIP`。

这个仓库是 AUR 软件包的 GitHub 源仓库。`./update.sh` 会检查并推送已审核的
`master` 分支；受保护的 GitHub Actions `aur-production` Environment 随后把
软件包发布到 `ssh://aur@aur.archlinux.org/astrbot-git.git` 的独立历史。

请创建一把权限最小化的 AUR 发布专用 SSH 密钥，并把公钥添加到维护者的 AUR
账户。私钥和已核验的 AUR 主机密钥行必须保存为 GitHub Environment Secrets，
绝不能写入仓库文件。工作流只读取 `AUR_SSH_PRIVATE_KEY` 和
`AUR_SSH_KNOWN_HOSTS`，不会在运行时自动探测主机密钥。

可用 GitHub CLI 配置并核验 `aur-production` Environment，命令不会打印
Secret 的值：

```bash
gh secret set --env aur-production AUR_SSH_PRIVATE_KEY < /path/to/dedicated-aur-key
gh secret set --env aur-production AUR_SSH_KNOWN_HOSTS < /path/to/verified-aur-known-hosts
gh secret list --env aur-production
```

AUR 快照严格包含以下文件：

- `.SRCINFO`
- `PKGBUILD`
- `astrbot-git.install`
- `astrbotctl`
- `astrbotctl.functions`
- `astrbot@.service`
- `tmpl.conf`
- `no-dashboard-password-in-startup-log.patch`

工作流只复制和暂存这些根目录普通文件。AUR 快照不包含子目录；AUR 独立仓库
中已有的未知根目录文件会被保留，不会被删除。

如需手动发布，发布前重新生成 `.SRCINFO`：

```bash
makepkg --printsrcinfo > .SRCINFO
```
