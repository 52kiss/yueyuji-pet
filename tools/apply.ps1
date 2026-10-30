# 安装 / 回滚 月御姬（Windows，无需 Python）
#
#   powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1 -Revert
#   powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1 -PackageDir "C:\path\to\dsh-dafeiyu"
#
# 做法：**字符串锚点补丁**（换行无关、幂等），不是 git apply。
# 原因：上游 4 个文件的换行符并不统一（两个 CRLF、两个 LF），
#       统一 diff 在 Windows 上极易因 CRLF 归一化而无法应用。
#
# 步骤：备份 → 改名文案 → 注入代码块 → 挂钩 → 部署素材 → 提示重启

[CmdletBinding()]
param(
    [string]$PackageDir = "",
    [switch]$Revert,
    [switch]$SkipAssets,
    [string]$Version = "0.1.23"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$assetsSrc = Join-Path $repoRoot "assets"
$blockPath = Join-Path $repoRoot "patches\inject-block.js"
$heartbeatPath = Join-Path $repoRoot "patches\inject-heartbeat.js"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$touched = @("src\plugin.js", "src\status-copy.js", "src\index.js", "lib\client.js")

function Find-PackageDir {
    foreach ($c in @(
            (Join-Path $env:USERPROFILE ".dsh\profiles\desktop\node_modules\dsh-dafeiyu"),
            (Join-Path $env:USERPROFILE ".dsh\profiles\web\node_modules\dsh-dafeiyu"))) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Read-Text([string]$path) {
    $raw = [System.IO.File]::ReadAllText($path)
    $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{
        Text = ($raw -replace "`r`n", "`n")
        Eol  = $eol
    }
}

function Write-Text([string]$path, [string]$text, [string]$eol) {
    $out = if ($eol -eq "`r`n") { $text -replace "`n", "`r`n" } else { $text }
    [System.IO.File]::WriteAllText($path, $out, $utf8NoBom)
}

if (-not $PackageDir) { $PackageDir = Find-PackageDir }
if (-not $PackageDir -or -not (Test-Path -LiteralPath $PackageDir)) {
    throw "找不到 dsh-dafeiyu 目录，请用 -PackageDir 指定（例如 $env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-dafeiyu）"
}
$PackageDir = (Resolve-Path -LiteralPath $PackageDir).Path
$pkgJsonPath = Join-Path $PackageDir "package.json"
if (Test-Path -LiteralPath $pkgJsonPath) {
    $ver = (Get-Content -LiteralPath $pkgJsonPath -Raw | ConvertFrom-Json).version
    Write-Host "目标包: $PackageDir (version $ver)"
    if ($ver -ne $Version) { Write-Warning "包版本 $ver 与基准 $Version 不同，锚点可能匹配失败。" }
} else {
    Write-Host "目标目录: $PackageDir (无 package.json，按测试目录处理)"
}

$cacheRoot   = Join-Path $env:LOCALAPPDATA "dsh-dafeiyu\$Version"
$cacheAssets = Join-Path $cacheRoot "assets"
$whaleBackup = Join-Path $cacheRoot "assets-whale-backup"

# ---------------- 回滚 ----------------
if ($Revert) {
    $backups = Get-ChildItem -LiteralPath $PackageDir -Directory -Filter ".yueyuji-backup-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if (-not $backups) { throw "找不到 .yueyuji-backup-* 备份目录" }
    $bk = $backups[0].FullName
    foreach ($rel in $touched) {
        $srcF = Join-Path $bk $rel
        if (Test-Path -LiteralPath $srcF) {
            Copy-Item -LiteralPath $srcF -Destination (Join-Path $PackageDir $rel) -Force
            Write-Host "已恢复 $rel"
        }
    }
    if (-not $SkipAssets -and (Test-Path -LiteralPath $whaleBackup)) {
        if (Test-Path -LiteralPath $cacheAssets) { Remove-Item -LiteralPath $cacheAssets -Recurse -Force }
        Rename-Item -LiteralPath $whaleBackup -NewName "assets"
        Write-Host "已恢复上游鲸鱼娘素材"
    }
    Write-Host "`n回滚完成。请完全退出并重新打开 DeepSeek Harness。" -ForegroundColor Yellow
    return
}

# ---------------- 备份 ----------------
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $PackageDir ".yueyuji-backup-$stamp"
foreach ($rel in $touched) {
    $srcPath = Join-Path $PackageDir $rel
    if (-not (Test-Path -LiteralPath $srcPath)) { throw "缺少文件: $srcPath" }
    $dstPath = Join-Path $backupDir $rel
    New-Item -ItemType Directory -Path (Split-Path $dstPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $srcPath -Destination $dstPath -Force
}
Write-Host "原文件已备份: $backupDir"

# ---------------- 补丁定义 ----------------
$injectBlock = [System.IO.File]::ReadAllText($blockPath)
$injectHeartbeat = [System.IO.File]::ReadAllText($heartbeatPath)
foreach ($s in @($injectBlock, $injectHeartbeat)) { }
$injectBlock = ($injectBlock -replace "`r`n", "`n")
$injectHeartbeat = ($injectHeartbeat -replace "`r`n", "`n")

$steps = @(
    # --- 文案改名 ---
    @{ File = "src\status-copy.js"; Old = "大肥鱼正在待命中~"; New = "小月姬正在待命中~"; Name = "文案:待命中" }
    @{ File = "src\status-copy.js"; Old = "大肥鱼还在认真干活呢"; New = "小月姬还在认真干活呢"; Name = "文案:干活中" }
    @{ File = "src\index.js"; Old = "插件依赖加载失败，大肥鱼本次启动已自动停用"; New = "插件依赖加载失败，小月姬本次启动已自动停用"; Name = "文案:加载失败" }
    @{ File = "src\plugin.js"; Old = "启用桌面大肥鱼"; New = "启用桌面小月姬"; Name = "文案:设置项" }
    @{ File = "src\plugin.js"; Old = "由 DeepSeek Harness 状态驱动的桌面大肥鱼伴侣"; New = "由 DeepSeek Harness 状态驱动的桌面小月姬伴侣"; Name = "文案:插件描述" }
    @{ File = "lib\client.js"; Old = "大肥鱼桌面伴侣"; New = "小月姬桌面伴侣"; Name = "文案:设置页标题" }
    @{ File = "lib\client.js"; Old = "大肥鱼设置尚未连接到 DSH Host。"; New = "小月姬设置尚未连接到 DSH Host。"; Name = "文案:未连接提示" }
    @{ File = "lib\client.js"; Old = "启用大肥鱼"; New = "启用小月姬"; Name = "文案:设置页开关" }
    @{ File = "lib\client.js"; Old = "label: () => '大肥鱼'"; New = "label: () => '小月姬'"; Name = "文案:标签" }

    # --- 依赖注入 ---
    @{ File = "src\plugin.js"; Old = "import { readFileSync } from 'node:fs'"; New = "import { readFileSync, readdirSync, statSync } from 'node:fs'"; Name = "导入 fs" }

    # --- 注入主代码块 ---
    @{ File = "src\plugin.js"; Old = "  const balance = createBalanceMonitor({"; New = $injectBlock + "  const balance = createBalanceMonitor({"; Name = "注入定制代码块" }

    # --- 挂钩：余额阈值 ---
    @{ File = "src\plugin.js"
       Old = "      if (bridge) bridge.send(message)`n      else eventStream.broadcast(message)`n    },"
       New = "      if (bridge) bridge.send(message)`n      else eventStream.broadcast(message)`n      announceLowBalance(snapshot)`n    },"
       Name = "挂钩:余额阈值" }

    # --- 挂钩：会话事件（记录真实状态 + 微信检测）---
    @{ File = "src\plugin.js"
       Old = "  const offEvent = eventCtx.on('session/event', (session, event) => {`n    if (!bridge || !reducer) return"
       New = "  const offEvent = eventCtx.on('session/event', (session, event) => {`n    lastHostEventAt = Date.now()`n    if (!bridge || !reducer) return"
       Name = "挂钩:事件时间戳" }
    @{ File = "src\plugin.js"
       Old = "      for (const message of reducer.handle(session, event)) bridge.send(message)"
       New = "      for (const message of reducer.handle(session, event)) {`n        if (message && message.kind === 'state') lastReducerState = message`n        bridge.send(message)`n      }`n      announceWechatMessage(session, event)"
       Name = "挂钩:会话事件" }

    # --- 挂钩：停止时清理定时器 ---
    @{ File = "src\plugin.js"
       Old = "  const stopRuntime = (reason = 'settings-change') => {`n    bridge?.stop(reason)"
       New = "  const stopRuntime = (reason = 'settings-change') => {`n    if (heartbeatTimer) {`n      clearInterval(heartbeatTimer)`n      heartbeatTimer = undefined`n    }`n    if (wechatWatchTimer) {`n      clearInterval(wechatWatchTimer)`n      wechatWatchTimer = undefined`n    }`n    bridge?.stop(reason)"
       Name = "挂钩:清理定时器" }

    # --- 挂钩：启动时开心跳与监视 ---
    @{ File = "src\plugin.js"
       Old = "    logger.info?.('dsh-dafeiyu companion bridge started')`n  }"
       New = "    logger.info?.('dsh-dafeiyu companion bridge started')`n" + $injectHeartbeat + "  }"
       Name = "挂钩:心跳与监视" }
)

# ---------------- 逐文件应用 ----------------
$cache = @{}
$applied = 0; $skipped = 0; $missing = @()
foreach ($step in $steps) {
    $path = Join-Path $PackageDir $step.File
    if (-not $cache.ContainsKey($path)) { $cache[$path] = Read-Text $path }
    $doc = $cache[$path]
    if ($doc.Text.Contains($step.New)) { $skipped++; continue }
    if (-not $doc.Text.Contains($step.Old)) {
        $missing += ("{0} → {1}" -f $step.File, $step.Name)
        continue
    }
    $doc.Text = $doc.Text.Replace($step.Old, $step.New)
    $applied++
}
foreach ($path in $cache.Keys) { Write-Text $path $cache[$path].Text $cache[$path].Eol }
Write-Host "补丁：应用 $applied 步，跳过 $skipped 步（已打过）"
if ($missing.Count -gt 0) {
    Write-Warning "以下锚点未匹配（可能是上游版本不同）："
    $missing | ForEach-Object { Write-Warning "  - $_" }
}

# ---------------- 部署素材 ----------------
if (-not $SkipAssets) {
    if (-not (Test-Path -LiteralPath $assetsSrc)) { throw "缺少素材目录: $assetsSrc" }
    New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
    if ((Test-Path -LiteralPath $cacheAssets) -and -not (Test-Path -LiteralPath $whaleBackup)) {
        Rename-Item -LiteralPath $cacheAssets -NewName "assets-whale-backup"
        Write-Host "上游素材已备份为 assets-whale-backup"
    }
    New-Item -ItemType Directory -Path $cacheAssets -Force | Out-Null
    Copy-Item -Path (Join-Path $assetsSrc "*") -Destination $cacheAssets -Recurse -Force
    $frames = (Get-ChildItem -Path (Join-Path $cacheAssets "pet") -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Host "素材已部署: $cacheAssets（$frames 帧）"
}

Write-Host "`n完成。请完全退出并重新打开 DeepSeek Harness，再运行 verify.ps1。" -ForegroundColor Green
