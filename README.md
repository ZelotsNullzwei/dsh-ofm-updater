# dsh-ofm-updater

**给 DSH Desktop 的 Our Free Model 插件做一键更新 —— 双击就行，不用命令行。**

> 中文 | [English](#english)

---

## 下载

**最新版：[Releases → latest](https://github.com/ZelotsNullzwei/dsh-ofm-updater/releases/latest)**

下载 `dsh-ofm-updater-vX.Y.Z.zip`，解压，双击 `Update-OurFreeModel.bat` 即可。
压缩包内只有 4 个文件，不需要 git，不需要安装 Node。

> 也可以直接克隆仓库：`git clone https://github.com/ZelotsNullzwei/dsh-ofm-updater`

---

## 为什么需要它

先说清楚：**Our Free Model 本身是个很好的项目**，作者和贡献者一直在快速迭代。
本仓库不是它的替代品，也不替代它的任何功能 —— 只是在「应用内升级」这条路走不通时，
提供一个能用的备用通道。

OFM 自带「应用内升级」，但它长期不可靠，国内用户实际上只能手动更新。
上游仓库里相关 issue 一直开着：

| Issue | 问题 |
| --- | --- |
| [#237](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/237) | 升级检查失败：三个清单源全部被墙（raw.githubusercontent / jsdelivr） |
| [#85](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/85) | `client.js` 改了没重签清单 → 1.4.4 用户全升不上去 |
| [#120](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/120) | 升 2.0.0 必然失败（4 个文件与签名清单不符） |
| [#232](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/232) | 升级检查响应超 256KB 上限 → 所有版本失效 |

本脚本把「手动更新」这件事固化成双击一个 `.bat`，并处理掉实操中的三个坑。

> 这些坑都是实际踩出来的，Issue 编号只是引用公开记录，不是为了指责任何人。
> 如果上游之后修好了应用内升级，本仓库就可以退休了。

---

## 致谢

**这个工具是站在 [Our Free Model](https://github.com/Ebony-Vinyl/dsh-our-free-model) 的肩膀上的。**

没有上游那个项目，就没有这个脚本存在的理由 —— 它做的事（把十三个账号渠道、
免费车道、EAC 垫资、聚合路由、省 token、原生 Anthropic 网关都收进一个插件里，
且无需注册或填 API Key）本身就很了不起，而且迭代速度很快。

感谢作者 **[@Ebony-Vinyl](https://github.com/Ebony-Vinyl)** 以及贡献者们
（按上游发布说明整理）：

- **[@look-back-lysj](https://github.com/look-back-lysj)** — 桌面版 PR 整合、EAC 服务迁移与离线密封工具
- **[@zixin947](https://github.com/zixin947)** — 桌面启动与生命周期修复、发布签名、升级回退验证
- **流影似景** — 前端夜/昼主题与 Tauri 桌面版初始实现

本仓库与上游**没有任何隶属关系**，也没有得到官方背书。它只是一个用户侧的运维小工具：
上游负责把插件做好，这里只负责在「应用内升级走不通」时，让更新这件事还能完成。

如果上游哪天把升级通道修稳了，这个仓库就该退休了 —— 那才是更好的结局。

---

## 相关工具

如果你的需求更广（不只是 OFM 一个插件，还包括主程序或其它插件），
下面这些项目可能更适合：

- [dsh-launcher](https://github.com/loudMore/dsh-launcher) — 一键安装 / 更新 / 维护 dsh 与插件
- [dsh-update-checker](https://github.com/Airmetro/dsh-update-checker) — npm / GitHub 双源更新检查
- [dsh-our-free-model-installer](https://github.com/ImSusua/dsh-our-free-model-installer) — OFM 桌面端一键安装器

本工具只专注一件事：**OFM 在国内网络下的一键更新**（含 PATH 修复与慢网络处理）。

---

## 用法

1. **完全退出 DSH Desktop**
   不只是关窗口 —— 托盘图标也要退出。确认任务管理器里没有 `DSH Desktop`。

2. **双击 `Update-OurFreeModel.bat`**

3. **重新启动 DSH Desktop**

升级完成后，OFM 里确认版本号即可。

> 首次打开 OFM 若提示需要 GitHub 授权，属正常现象 —— 部分版本迁移了服务端，
> 旧授权需要重新确认。

---

## 它解决的三个坑

### 1. `dsh` 和 `pnpm` 不在系统 PATH 里

DSH Desktop 把自己的 `dsh` / `pnpm` / `node` 放在

```
%APPDATA%\DSH Desktop\host-commands\<profile>\generations\<hash>\bin
%APPDATA%\DSH Desktop\runtime-commands\generations\<hash>\bin
```

并且**只注入给它自己派生的进程**。双击打开的干净 cmd 窗口两个都看不到，于是
`dsh plugin` 报：

```
'pnpm' 不是内部或外部命令
```

因为 `dsh plugin` 内部是 `execa("pnpm", ...)` —— 它靠 PATH 找 pnpm。

本脚本会主动定位这几个目录并前置到 `PATH`，然后再动手。

### 2. GitHub（codeload）在国内很慢

实测 9 MB 的包只有 **30~40 KB/s**，需要 **4~5 分钟**。pnpm 默认超时扛不住，
而且它的日志只有一句

```
Command failed with exit code 1
```

**不说明原因** —— 这是最难排查的地方。

本脚本会在 profile 的 `pnpm-workspace.yaml` 里写入放宽的超时：

```yaml
fetchTimeout: 900000        # 15 分钟
fetchRetries: 5
fetchRetryFactor: 2
fetchRetryMintimeout: 10000
fetchRetryMaxtimeout: 120000
networkConcurrency: 4
```

> 开代理会快很多。脚本本身不配置代理，但会沿用系统代理设置。

### 3. GitHub 的 `archive/refs/heads/main.tar.gz` 不能用

它内容可变，pnpm 无法记录 integrity，会报：

```
ERR_PNPM_MISSING_TARBALL_INTEGRITY
```

必须用 `codeload.github.com` + **固定 commit sha**：

```
https://codeload.github.com/Ebony-Vinyl/dsh-our-free-model/tar.gz/<sha>
```

本脚本就是这么做的。

---

## 命令行参数

| 参数 | 说明 |
| --- | --- |
| `-English` | 用英文输出（默认中文） |
| `-DryRun` | 只检查，不改动任何东西 |
| `-Rollback` | 回滚到上一次备份 |
| `-TargetSha <sha>` | 安装指定的 commit（默认：main 最新） |
| `-Profile <name>` | DSH profile 名（默认 `desktop`） |

例子：

```bat
Update-OurFreeModel.bat -DryRun
Update-OurFreeModel.bat -Rollback
Update-OurFreeModel.bat -English
```

---

## 备份

每次更新前会自动备份到 `backups\<时间戳>\`：

```
package.json
pnpm-lock.yaml
pnpm-workspace.yaml
node_modules-plugin\     （当前插件完整目录）
user-data\               （设置 / 授权 / catalog）
update.log               （本次安装日志）
```

回滚：`Update-OurFreeModel.bat -Rollback`

> 注意：如果上游做了服务端迁移，回滚到旧版本不保证旧服务仍可用 ——
> 这一点上游发布说明里也提示过。

---

## 直接改配置也能用

如果你不想用脚本，手动流程等价于：

```powershell
# 1. 退出 DSH Desktop

# 2. 给 pnpm 放宽超时（写进 profile 的 pnpm-workspace.yaml）
#    fetchTimeout: 900000

# 3. 用 codeload + 固定 sha 安装
dsh plugin --profile desktop add "https://codeload.github.com/Ebony-Vinyl/dsh-our-free-model/tar.gz/<sha>"

# 4. 启动 DSH Desktop
```

脚本只是把这几步自动化了，并多做了一份备份。

---

## 已知限制

- **只针对 Windows + DSH Desktop**。路径布局按 DSH Desktop 的实际实现写
  （`host-commands` / `runtime-commands`），如果 DSH 改了这套布局，脚本需要跟进。
- **只更新 `dsh-our-free-model`**，不是通用插件更新器。
- 脚本会写入 profile 的 `pnpm-workspace.yaml`（追加超时配置），会先备份该文件。
- `ReadKey` 已做成智能暂停：有控制台才等按键，被管道/CI 调用时直接退出。

---

## 文件

| 文件 | 作用 |
| --- | --- |
| `Update-OurFreeModel.bat` | 双击入口（纯 ASCII —— cmd 按 GBK 解析 .bat，UTF-8 中文会被当命令执行） |
| `Update-OurFreeModel.ps1` | 实际逻辑（**UTF-8 with BOM** —— PS 5.1 对无 BOM 的 UTF-8 按 ANSI 读，中文会坏） |

---

## English

**One-click updater for the Our Free Model plugin in DSH Desktop.**

OFM's built-in updater has been unreliable for a long time (see issues
[#237](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/237),
[#85](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/85),
[#120](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/120),
[#232](https://github.com/Ebony-Vinyl/dsh-our-free-model/issues/232)).
Users in mainland China effectively have to update by hand. This script freezes
that manual flow into a double-clickable `.bat`.

### Usage

1. Fully exit DSH Desktop (including the tray icon).
2. Double-click `Update-OurFreeModel.bat`.
3. Start DSH Desktop again.

### What it handles

1. **`dsh` and `pnpm` are not on PATH.** DSH Desktop injects them only into the
   processes it spawns, so a plain cmd window fails with
   `'pnpm' is not recognized`. The script locates both and repairs PATH.
2. **GitHub (codeload) is slow.** Measured 30-40 KB/s for a 9 MB tarball (~5 min).
   pnpm's default timeout kills it, and its log says only
   "Command failed with exit code 1" with no reason. The script writes generous
   `fetchTimeout` / `fetchRetries` into the profile's `pnpm-workspace.yaml`.
3. **`archive/refs/heads/main.tar.gz` cannot be used** -- its content is mutable,
   so pnpm cannot record an integrity hash and fails with
   `ERR_PNPM_MISSING_TARBALL_INTEGRITY`. Always use `codeload.github.com` with a
   pinned commit sha.

### Options

`-English` (English output), `-DryRun`, `-Rollback`, `-TargetSha <sha>`,
`-Profile <name>`.

### Backup

Each run backs up `package.json`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, the
installed plugin directory, and OFM user data into `backups\<timestamp>\`.
Roll back with `-Rollback`.

### Credits

This tool stands on the shoulders of
[Our Free Model](https://github.com/Ebony-Vinyl/dsh-our-free-model) — without
that project there would be no reason for this script to exist. Thanks to
[@Ebony-Vinyl](https://github.com/Ebony-Vinyl) and the contributors
([@look-back-lysj](https://github.com/look-back-lysj),
[@zixin947](https://github.com/zixin947), and others).

This repository is **not affiliated with or endorsed by** the upstream project.
It is a user-side maintenance helper. If upstream ever makes the built-in
updater reliable, this repo should retire — that would be the better outcome.

### Related tools

If your needs are broader (not just OFM, but the DSH host or other plugins):

- [dsh-launcher](https://github.com/loudMore/dsh-launcher) — install / update / maintain dsh and plugins
- [dsh-update-checker](https://github.com/Airmetro/dsh-update-checker) — npm/GitHub dual-source update checks
- [dsh-our-free-model-installer](https://github.com/ImSusua/dsh-our-free-model-installer) — OFM desktop installer

---

## 许可 / License

MIT
