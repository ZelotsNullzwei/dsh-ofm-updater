<#
  dsh-ofm-updater  /  Our Free Model 一键更新脚本

  为什么需要这个脚本
  ------------------------------------------------------------------
  Our Free Model（OFM）自带「应用内升级」，但它长期不可靠：
    #237  升级检查失败：三个清单源全部被墙（raw.githubusercontent / jsdelivr）
    #85   client.js 改了没重签清单 → 1.4.4 用户全升不上去
    #120  升 2.0.0 必然失败（4 个文件与签名清单不符）
    #232  升级检查响应超 256KB 上限 → 所有版本失效
  所以国内用户实际上只能手动更新。

  这个脚本把那套手动流程固化成双击即可完成，并且处理了三个坑：

    坑 1  dsh 和 pnpm 不在系统 PATH 里
          DSH Desktop 只把它们注入自己派生的进程；双击打开的干净 cmd
          窗口两个都找不到，于是 `dsh plugin` 报
          「'pnpm' 不是内部或外部命令」。本脚本会自己找到它们并修好 PATH。

    坑 2  GitHub（codeload）在国内很慢
          实测 9 MB 的包只有 30~40 KB/s，要 4~5 分钟；pnpm 默认超时扛不住，
          而且它的日志只有一句「Command failed with exit code 1」不说明原因。
          本脚本会写入放宽的超时配置。

    坑 3  GitHub 的 archive/refs/heads/main.tar.gz 不能用
          它内容可变，pnpm 无法记录 integrity，会报
          ERR_PNPM_MISSING_TARBALL_INTEGRITY。
          必须用 codeload.github.com + 固定 commit sha。

  用法
  ------------------------------------------------------------------
    1. 完全退出 DSH Desktop（包含托盘图标；确认任务管理器里没有 DSH Desktop）
    2. 双击 更新-OurFreeModel.bat
    3. 重新启动 DSH Desktop

  命令行参数
  ------------------------------------------------------------------
    -English        用英文输出（默认中文）
    -DryRun         只检查，不改动任何东西
    -Rollback       回滚到上一次备份
    -TargetSha <sha> 安装指定的 commit（默认：main 最新）
    -Profile <name>  DSH profile 名（默认 desktop）

  编码说明
  ------------------------------------------------------------------
  本文件必须保存为 UTF-8 with BOM。
  Windows PowerShell 5.1 对无 BOM 的 UTF-8 文件按系统 ANSI 代码页
  （简体中文系统是 GB2312）解析，会把中文和特殊符号读坏、导致语法错误。
#>

param(
  [switch]$English,
  [switch]$DryRun,
  [switch]$Rollback,
  [string]$TargetSha = '',
  [string]$Profile   = 'desktop'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

# ====================================================================
#  1. 常量 / Constants
# ====================================================================
$PKG_NAME    = 'dsh-our-free-model'
$REPO        = 'Ebony-Vinyl/dsh-our-free-model'
$BACKUP_ROOT = Join-Path $PSScriptRoot 'backups'

$DSH_HOME    = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$PROFILE_DIR = Join-Path $DSH_HOME "profiles\$Profile"

# 中英双语文本表 ------------------------------------------------------
$T = if ($English) {
  @{
    Title        = 'Our Free Model - updater'
    Step0        = 'Locating dsh / pnpm (PATH repair)'
    Step1        = 'Checking that DSH is closed'
    Step2        = 'Checking profile and dependency'
    Step3        = 'Looking up the latest upstream commit'
    Step4        = 'Backing up current state'
    Step5        = 'Running the update'
    Step6        = 'Result'
    Ok           = 'OK'
    Fail         = 'FAIL'
    Warn         = 'WARN'
    NotFound     = 'not found'
    DshRunning   = 'DSH Desktop is still running. Close it completely (including the tray icon), then run this again.'
    DshOk        = 'DSH is fully closed'
    ForceKill    = 'To force-kill: Get-Process -Name "DSH Desktop" | Stop-Process -Force'
    CurSpec      = 'current spec'
    CurCommit    = 'current commit'
    Latest       = 'latest upstream'
    UpToDate     = 'Already up to date'
    NoChange     = 'Nothing to do.'
    WouldRun     = 'would run'
    BackedUp     = 'backed up'
    BackupAt     = 'backup saved to'
    DshOkPath    = 'dsh found'
    PnpmOkPath   = 'pnpm found'
    NodeOkPath   = 'node found'
    NodeOptional = 'node not found (fine - dsh carries its own runtime)'
    PathFixed    = 'PATH repaired: dsh and pnpm are now callable'
    PathFail     = 'Could not locate the required command(s). Is DSH Desktop installed and started at least once?'
    Updating     = 'Installing'
    UpdateOk     = 'Update succeeded'
    UpdateFail   = 'Update FAILED'
    LogAt        = 'log'
    NextStart    = 'Next: start DSH Desktop again.'
    RollbackMode = 'ROLLBACK MODE'
    RollbackOk   = 'package.json restored from backup'
    RollbackNone = 'No backup found - nothing to roll back to.'
    Hint         = 'Common causes'
    Hint1        = 'pnpm could not be found  -> the PATH repair above should have fixed this; report it if it persists'
    Hint2        = 'ERR_PNPM_EPERM / directory in use -> DSH was not fully closed'
    Hint3        = 'Slow network / timeout -> the script widens pnpm timeouts; a proxy makes it much faster'
    Hint4        = 'ERR_PNPM_IGNORED_BUILDS -> add the package to allowBuilds in pnpm-workspace.yaml'
    PressKey     = 'Press any key to close...'
  }
} else {
  @{
    Title        = 'Our Free Model 更新工具'
    Step0        = '定位 dsh / pnpm（修复 PATH）'
    Step1        = '确认 DSH 已退出'
    Step2        = '检查 profile 与依赖'
    Step3        = '查询上游最新 commit'
    Step4        = '备份当前状态'
    Step5        = '执行更新'
    Step6        = '结果'
    Ok           = '成功'
    Fail         = '失败'
    Warn         = '警告'
    NotFound     = '未找到'
    DshRunning   = 'DSH Desktop 还在运行。请完全退出（包括托盘图标），再运行本脚本。'
    DshOk        = 'DSH 已完全退出'
    ForceKill    = '强制结束：Get-Process -Name "DSH Desktop" | Stop-Process -Force'
    CurSpec      = '当前 spec'
    CurCommit    = '当前 commit'
    Latest       = '上游最新'
    UpToDate     = '已是最新版本'
    NoChange     = '无需更新。'
    WouldRun     = '将执行'
    BackedUp     = '已备份'
    BackupAt     = '备份位置'
    DshOkPath    = '已找到 dsh'
    PnpmOkPath   = '已找到 pnpm'
    NodeOkPath   = '已找到 node'
    NodeOptional = '未找到 node（不影响，dsh 自带运行时）'
    PathFixed    = 'PATH 已修复：dsh 与 pnpm 都可调用'
    PathFail     = '找不到必需的命令。DSH Desktop 是否已安装并至少启动过一次？'
    Updating     = '正在安装'
    UpdateOk     = '更新成功'
    UpdateFail   = '更新失败'
    LogAt        = '日志'
    NextStart    = '下一步：重新启动 DSH Desktop。'
    RollbackMode = '回滚模式'
    RollbackOk   = 'package.json 已从备份恢复'
    RollbackNone = '没有找到备份，无法回滚。'
    Hint         = '常见原因'
    Hint1        = '找不到 pnpm -> 上面的 PATH 修复本应解决；若仍出现请反馈'
    Hint2        = 'ERR_PNPM_EPERM / 目录被占用 -> DSH 没退干净'
    Hint3        = '网络慢 / 超时 -> 本脚本已放宽超时；开代理会快很多'
    Hint4        = 'ERR_PNPM_IGNORED_BUILDS -> 把包名加进 pnpm-workspace.yaml 的 allowBuilds'
    PressKey     = '按任意键关闭窗口...'
  }
}

function Say($msg, $color = 'White') { Write-Host $msg -ForegroundColor $color }
function Line { Write-Host ('-' * 66) -ForegroundColor DarkGray }
function Head($n, $text) { Say ""; Say "[$n/6] $text..." }

# 智能暂停 / smart pause
#   双击运行时：等用户按键，好让他看清结果。
#   无控制台时（管道、CI、被其他脚本调用）：直接返回 —— 否则 ReadKey
#   会永久挂起。这是把脚本做成可自动化工具时的真实缺陷。
function Wait-Key {
  try {
    if ([Console]::IsInputRedirected) { return }
  } catch { return }
  try {
    if ($T.PressKey) { Say $T.PressKey DarkGray }
  Wait-Key
  } catch { }
}

# ====================================================================
#  2. 修复 PATH：找到 dsh / pnpm / node
# ====================================================================
#  DSH Desktop 把这些命令放在它自己的 generations 目录里，只注入给它派生的
#  进程。双击 .bat 得到的干净 cmd 看不到它们，于是 `dsh plugin` 调用 pnpm 时
#  会失败。这里主动找出来并前置到 PATH。
# ====================================================================
$HOST_ROOT = Join-Path $env:APPDATA 'DSH Desktop\host-commands'
$RUNT_ROOT = Join-Path $env:APPDATA 'DSH Desktop\runtime-commands'

function Get-NewestCmd {
  param([string]$Root, [string]$FileName, [string]$ProfileFilter)
  if (-not (Test-Path $Root)) { return $null }
  $all = @(Get-ChildItem -Path $Root -Filter $FileName -Recurse -File -ErrorAction SilentlyContinue)
  if ($all.Count -eq 0) { return $null }
  if ($ProfileFilter) {
    $m = @($all | Where-Object { $_.FullName -match ('\\' + [regex]::Escape($ProfileFilter) + '\\') })
    if ($m.Count -gt 0) { return ($m | Sort-Object LastWriteTime -Descending | Select-Object -First 1) }
  }
  return ($all | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

Line
Say $T.Title Cyan
Line

Head '0' $T.Step0

$dshCmdFile = $null
$c = Get-Command dsh -ErrorAction SilentlyContinue
if ($c) { $dshCmdFile = Get-Item $c.Source -ErrorAction SilentlyContinue }
if (-not $dshCmdFile) { $dshCmdFile = Get-NewestCmd $HOST_ROOT 'dsh.cmd' $Profile }
if (-not $dshCmdFile) { $dshCmdFile = Get-NewestCmd $HOST_ROOT 'dsh.cmd' }

$pnpmCmdFile = $null
$c = Get-Command pnpm -ErrorAction SilentlyContinue
if ($c) { $pnpmCmdFile = Get-Item $c.Source -ErrorAction SilentlyContinue }
if (-not $pnpmCmdFile) { $pnpmCmdFile = Get-NewestCmd $RUNT_ROOT 'pnpm.cmd' }

$nodeCmdFile = $null
$c = Get-Command node -ErrorAction SilentlyContinue
if ($c) { $nodeCmdFile = Get-Item $c.Source -ErrorAction SilentlyContinue }
if (-not $nodeCmdFile) { $nodeCmdFile = Get-NewestCmd $RUNT_ROOT 'node.cmd' }

if (-not $dshCmdFile -or -not $pnpmCmdFile) {
  Say "  $($T.Fail): $($T.PathFail)" Red
  if ($dshCmdFile) { Say "  dsh : $($dshCmdFile.FullName)" DarkGray }
  if ($pnpmCmdFile) { Say "  pnpm: $($pnpmCmdFile.FullName)" DarkGray }
  Say "  looked in: $HOST_ROOT" DarkGray
  Say "             $RUNT_ROOT" DarkGray
  Say ""
  Wait-Key
  exit 1
}

$addDirs = @($dshCmdFile.DirectoryName, $pnpmCmdFile.DirectoryName)
if ($nodeCmdFile) { $addDirs += $nodeCmdFile.DirectoryName }
$addDirs = $addDirs | Select-Object -Unique
$env:PATH = ($addDirs -join ';') + ';' + $env:PATH

Say "  $($T.DshOkPath)  : $($dshCmdFile.FullName)" Green
Say "  $($T.PnpmOkPath) : $($pnpmCmdFile.FullName)" Green
if ($nodeCmdFile) { Say "  $($T.NodeOkPath) : $($nodeCmdFile.FullName)" Green }
else { Say "  $($T.NodeOptional)" DarkGray }

if (-not (Get-Command dsh -ErrorAction SilentlyContinue) -or -not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  Say "  $($T.Fail): $($T.PathFail)" Red
  Say ""
  Wait-Key
  exit 1
}
Say "  $($T.PathFixed)" Green

# ====================================================================
#  3. 回滚分支 / Rollback
# ====================================================================
if ($Rollback) {
  Say ""
  Say "[$($T.RollbackMode)]"
  $latest = $null
  if (Test-Path $BACKUP_ROOT) {
    $latest = Get-ChildItem $BACKUP_ROOT -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
  if (-not $latest) {
    Say "  $($T.Fail): $($T.RollbackNone)" Red
    Say ""
  Wait-Key
    exit 1
  }
  $bkPkg = Join-Path $latest.FullName 'package.json'
  $pkgJson = Join-Path $PROFILE_DIR 'package.json'
  if (-not (Test-Path $bkPkg)) {
    Say "  $($T.Fail): backup has no package.json ($($latest.FullName))" Red
    Say ""
  Wait-Key
    exit 1
  }
  Copy-Item $bkPkg $pkgJson -Force
  Say "  $($T.RollbackOk)" Green
  Say "  from: $($latest.FullName)" DarkGray
  Say ""
  Say "  $($T.NextStart)" Cyan
  Say "  If node_modules is also broken, run: dsh plugin --profile $Profile install" DarkGray
  Say ""
  Wait-Key
  exit 0
}

# ====================================================================
#  4. DSH 必须已退出
# ====================================================================
Head '1' $T.Step1
$dshProcs = @(Get-Process -Name 'DSH Desktop' -ErrorAction SilentlyContinue)
if ($dshProcs.Count -gt 0) {
  Say "  $($T.Fail): $($T.DshRunning)" Red
  Say "  $($T.ForceKill)" DarkGray
  Say ""
  Wait-Key
  exit 1
}
Say "  $($T.DshOk)" Green

# ====================================================================
#  5. profile 与依赖
# ====================================================================
Head '2' $T.Step2
$pkgJson = Join-Path $PROFILE_DIR 'package.json'
if (-not (Test-Path $pkgJson)) {
  Say "  $($T.Fail): $($T.NotFound) $pkgJson" Red
  Say ""
  Wait-Key
  exit 1
}
$pkg = Get-Content $pkgJson -Raw | ConvertFrom-Json
$currentSpec = $pkg.dependencies.$PKG_NAME
if (-not $currentSpec) {
  Say "  $($T.Fail): '$PKG_NAME' is not a dependency of this profile." Red
  Say "  profile: $PROFILE_DIR" DarkGray
  Say ""
  Wait-Key
  exit 1
}
Say "  $($T.CurSpec): $currentSpec"

$currentSha = ''
if ($currentSpec -match '/tar\.gz/([0-9a-f]{40})') { $currentSha = $Matches[1] }
if ($currentSha) { Say "  $($T.CurCommit): $currentSha" }

# ====================================================================
#  6. 确定目标 commit
# ====================================================================
Head '3' $T.Step3
$targetShaResolved = $TargetSha
if (-not $targetShaResolved) {
  try {
    $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO/commits/main" `
      -Headers @{ 'User-Agent' = 'dsh-ofm-updater' } -TimeoutSec 40
    $targetShaResolved = $resp.sha
    Say "  $($T.Latest): $targetShaResolved"
    Say "  date    : $($resp.commit.author.date)" DarkGray
    Say "  message : $(($resp.commit.message -split "`n")[0])" DarkGray
  } catch {
    Say "  $($T.Fail): $($_.Exception.Message)" Red
    Say "  If GitHub is unreachable, pass a commit manually:" DarkGray
    Say "    -TargetSha <40-char-sha>" DarkGray
    Say ""
  Wait-Key
    exit 1
  }
} else {
  Say "  using specified commit: $targetShaResolved"
}

if ($currentSha -and $targetShaResolved -eq $currentSha) {
  Say ""
  Say "  $($T.UpToDate) ($targetShaResolved). $($T.NoChange)" Green
  Say ""
  Wait-Key
  exit 0
}

# codeload + 固定 sha。绝不要用 archive/refs/heads/main.tar.gz（内容可变，
# pnpm 记不了 integrity，会报 ERR_PNPM_MISSING_TARBALL_INTEGRITY）。
$spec = "https://codeload.github.com/$REPO/tar.gz/$targetShaResolved"

if ($DryRun) {
  Say ""
  Say "[DryRun] $($T.WouldRun):" Yellow
  Say "  dsh plugin --profile $Profile add `"$spec`"" Gray
  Say "  backup: package.json / pnpm-lock.yaml / node_modules\$PKG_NAME / user data" Gray
  Say ""
  Say "  (nothing was changed)" Yellow
  Say ""
  Wait-Key
  exit 0
}

# ====================================================================
#  7. 备份
# ====================================================================
Head '4' $T.Step4
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BACKUP_ROOT $stamp
New-Item -ItemType Directory -Force -Path $backup | Out-Null

foreach ($f in @('package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml')) {
  $src = Join-Path $PROFILE_DIR $f
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $backup $f) -Force
    Say "  $($T.BackedUp) $f" DarkGray
  }
}
$nm = Join-Path $PROFILE_DIR "node_modules\$PKG_NAME"
if (Test-Path $nm) {
  Copy-Item $nm (Join-Path $backup 'node_modules-plugin') -Recurse -Force -ErrorAction SilentlyContinue
  Say "  $($T.BackedUp) node_modules\$PKG_NAME" DarkGray
}
# 用户数据（设置 / 授权 / catalog）。官方升级说明要求先备份这份。
$dataDir = Join-Path $DSH_HOME 'our-free-model'
if (Test-Path $dataDir) {
  Copy-Item $dataDir (Join-Path $backup 'user-data') -Recurse -Force -ErrorAction SilentlyContinue
  Say "  $($T.BackedUp) user data" DarkGray
}
Say "  $($T.BackupAt): $backup" Cyan

# ====================================================================
#  8. 执行更新
# ====================================================================
Head '5' $T.Step5
Say "  $($T.Updating): $spec" DarkGray
Say ""

$logFile = Join-Path $backup 'update.log'
& dsh plugin --profile $Profile add $spec 2>&1 | Tee-Object -FilePath $logFile
$code = $LASTEXITCODE

# ====================================================================
#  9. 结果
# ====================================================================
Head '6' $T.Step6
Line
if ($code -eq 0) {
  $pkg2 = Get-Content $pkgJson -Raw | ConvertFrom-Json
  Say "  $($T.UpdateOk)" Green
  Say "  new spec: $($pkg2.dependencies.$PKG_NAME)"
  Say ""
  Say "  $($T.NextStart)" Cyan
  if (-not $English) {
    Say "  首次打开 OFM 若提示需要 GitHub 授权，属正常现象（本次更新迁移了服务端）。" Yellow
  } else {
    Say "  If OFM asks for GitHub authorization on first open, that is expected" Yellow
    Say "  (this release migrated the backend service)." Yellow
  }
} else {
  Say "  $($T.UpdateFail) (exit code $code)" Red
  Say "  $($T.LogAt): $logFile" Yellow
  Say ""
  Say "  $($T.Hint):" Yellow
  Say "    1. $($T.Hint1)" DarkGray
  Say "    2. $($T.Hint2)" DarkGray
  Say "    3. $($T.Hint3)" DarkGray
  Say "    4. $($T.Hint4)" DarkGray
  Say ""
  Say "  Rollback: run this script with -Rollback" Cyan
}
Line
  Wait-Key
