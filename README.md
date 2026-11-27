# scripts

仓库: <https://github.com/ak1ra-komj/scripts>

自家用脚本集合. 无需特权的 Unix 脚本按用途拆分为顶层 GNU Stow packages, 符号链接到
`${HOME}/.local/{bin,lib}`, `git pull` 即可同步更新; 需要特权或宿主机环境的脚本放在
`admin/`, 按需安装到 `/usr/local/bin`; Windows PowerShell 脚本统一放在 `pwsh/`.

## Layout

### GNU Stow packages (Unix user-level)

可执行脚本位于 `<pkg>/.local/bin/`, 仅用于 `source` 的脚本位于 `<pkg>/.local/lib/`:

| Package | Target | Contents |
| --- | --- | --- |
| `k8s` | `~/.local/bin` | `kube-append-ingress-rule.sh`, `kube-check-tls-secret.sh`, `kube-deploy-history.sh`, `kube-dump.sh`, `kube-iperf3.sh` |
| `k8s` | `~/.local/lib` | `kube-config-selector.sh` (non-executable, sourced) |
| `docker` | `~/.local/bin` | `docker-rm.sh` |
| `net` | `~/.local/bin` | `curl-header.sh`, `curl-time.sh`, `x509-inspect.sh` |
| `vcs` | `~/.local/bin` | `git-clone`, `git-fetch` |
| `media` | `~/.local/bin` | `mktrans`, `mpv-grid.sh`, `video-frames-extractor.sh`, `video-streams-extractor.sh` |
| `misc` | `~/.local/bin` | `bash-history-archive.sh`, `install-ansible.sh`, `mul_table.py` |

### Non-Stow directories

| Directory | Purpose | Contents |
| --- | --- | --- |
| `admin/net` | 特权网络工具 | `conntrack-count.sh` |
| `admin/pve` | Proxmox VE 宿主机工具 | `pvehost-backup.sh` |
| `admin/storage` | 磁盘与 ZFS 管理工具 | `wwn-ata-mapping.sh`, `zfs-release.sh` |
| `pwsh` | Windows PowerShell 脚本 | `Invoke-Mpv-Grid.ps1`, `Invoke-Winget-Install.ps1` |
| `manifests` | 示例清单 | `winget-packages.json` |
| `install` | 仓库自身远程安装工具 | `install.sh` (不参与安装) |

## Install

### 1. Unix 本地安装: GNU Stow (推荐)

适用于所有无特权脚本. 不假设仓库位于 `${HOME}` 下, 统一显式指定 `-t "${HOME}"`
和 `--no-folding` (避免 `~/.local/bin` 目录本身被折叠为指向仓库的符号链接, 防止
`uv`/`pipx` 等其他工具写入 `~/.local/bin` 时污染仓库). `just stow` 会在执行前自动
清理同名悬空符号链接 (broken symlink), 同名普通文件或有效符号链接则保持 Stow 报错.

确认 `${HOME}/.local/bin` 已加入 `PATH`, 然后按需启用 package:

```sh
just list-packages
just stow k8s net vcs
just unstow k8s
```

也可以直接调用 `stow`:

```sh
stow --no-folding -R -t "${HOME}" k8s net vcs
stow -D -t "${HOME}" k8s
```

先在临时目录试运行检查:

```sh
TARGET=/tmp/stow-stage just stow k8s net
```

### 2. Unix 本地安装到 `/usr/local/bin` (可选)

主要用于 `admin/` 下需要特权或切换 `root` 后仍需调用的脚本, 也接受仓库内任意脚本的相对路径.
目标目录不可写时 (如默认 `/usr/local/bin`) 会自动调用 `sudo`:

```sh
just install admin/pve/pvehost-backup.sh
just install admin/net/conntrack-count.sh admin/storage/zfs-release.sh
```

先复制到临时目录检查 (可写目录不会触发 `sudo`):

```sh
DESTDIR=/tmp/scripts-stage just install admin/net/conntrack-count.sh
```

### 3. Unix 远程安装到 `/usr/local/bin`

`just install-remote` 是 `ansible.builtin.copy` 的薄封装 (Ansible ad-hoc, 需要 `ansible`
和 `~/.ansible/inventory`), 参数为目标主机与相对仓库根目录的脚本路径, 支持 `admin/` 与
Stow package 中的任意脚本, 并支持直接透传 `ansible` 选项 (如 `-K`、`-u`、`--check`;
也可通过 `--` 原样透传任意 `ansible` 参数):

```sh
just install-remote HOST admin/pve/pvehost-backup.sh
just install-remote HOST admin/net/conntrack-count.sh net/.local/bin/curl-time.sh
just install-remote HOST admin/pve/pvehost-backup.sh -K
just install-remote -K HOST admin/pve/pvehost-backup.sh -u deploy --check
just install-remote HOST admin/pve/pvehost-backup.sh -- -K -v --diff
```

`install/install.sh` 默认附带 `-b`, 逐文件复制到远端 `${DESTDIR:-/usr/local/bin}`,
按源文件可执行位设置权限 (`0755` 或 `0644`), owner/group 为 `root:root`.

### 4. Windows 安装

Windows 安装使用系统自带的 Windows PowerShell (`powershell.exe`), 不要求 PowerShell 7;
`just` 自身需要 Git for Windows / GitHub Desktop / Cygwin 提供的 `sh` 在 `PATH` 中:

```sh
just list-windows
just install-windows pwsh/Invoke-Mpv-Grid.ps1
just install-windows pwsh/Invoke-Mpv-Grid.ps1 pwsh/Invoke-Winget-Install.ps1
```

Windows 安装直接使用 `Copy-Item` 复制指定脚本到 `%USERPROFILE%\bin`, 不处理配置文件.

`Invoke-Winget-Install.ps1` 默认读取当前工作目录下的 `winget-packages.json`.
示例清单位于 `manifests/winget-packages.json`; 首次使用时可以下载到本地后按需增删:

```powershell
Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/ak1ra-komj/scripts/refs/heads/main/manifests/winget-packages.json' `
    -OutFile 'winget-packages.json'
notepad winget-packages.json
Invoke-Winget-Install.ps1
```

如果当前目录没有 `winget-packages.json`, 脚本只会打印示例链接并退出, 不会自动下载或
fallback. 也可以显式指定文件或 URL:

```powershell
Invoke-Winget-Install.ps1 -Source 'C:\path\to\winget-packages.json'
```

## Check

```sh
just check    # shellcheck + shfmt -d + Python 语法检查
just fmt      # shfmt -w
```

依赖: `just`, `stow`, `shellcheck`, `shfmt`, `python3`; 远程安装另需 `ansible`;
Windows 安装使用系统自带的 Windows PowerShell (`powershell.exe`).
Windows 脚本目前只做人工维护, 不包含在 `just check` 中.

## Notes

- `k8s/.local/lib/kube-config-selector.sh` 由 `kc` alias `source`, 不直接执行;
  `just stow k8s` 后 alias 指向 `${HOME}/.local/lib/kube-config-selector.sh`.
- `admin/net/conntrack-count.sh` 通常需要 root 或 `CAP_NET_ADMIN`.
- `admin/pve/pvehost-backup.sh` 需要 root 与 Proxmox VE 环境;
  `admin/storage/zfs-release.sh` 需要 ZFS.
