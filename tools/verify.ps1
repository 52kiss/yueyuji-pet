# 安装后自检
#
#   powershell -ExecutionPolicy Bypass -File .\tools\verify.ps1
#
# 检查：素材是否就位、补丁标记是否存在、Helper 是否启动、关键日志行。

[CmdletBinding()]
param(
    [string]$PackageDir = "",
    [string]$Version = "0.1.23"
)

$ErrorActionPreference = "Continue"
$script:ok = 0
$script:fail = 0

function Check([string]$name, [bool]$passed, [string]$detail = "") {
    if ($passed) { Write-Host ("  [PASS] {0} {1}" -f $name, $detail) -ForegroundColor Green; $script:ok++ }
    else { Write-Host ("  [FAIL] {0} {1}" -f $name, $detail) -ForegroundColor Red; $script:fail++ }
}

# 必须显式按 UTF-8 读取：Windows PowerShell 5.1 的 Get-Content -Raw 对无 BOM 的
# UTF-8 文件按 ANSI 解码，中文锚点会变乱码导致误判。
function Read-Utf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

Write-Host "== 1. 素材 =="
$cacheAssets = Join-Path $env:LOCALAPPDATA "dsh-dafeiyu\$Version\assets"
$manifest = Join-Path $cacheAssets "pet-manifest.json"
Check "manifest 存在" (Test-Path -LiteralPath $manifest) $manifest
if (Test-Path -LiteralPath $manifest) {
    $m = (Read-Utf8 $manifest) | ConvertFrom-Json
    Check "characterId = yueyuji" ($m.characterId -eq "yueyuji") ("当前: " + $m.characterId)
    $clipCount = @($m.clips.PSObject.Properties).Count
    Check "动作组 = 16" ($clipCount -eq 16) ("当前: $clipCount")
}
$petDir = Join-Path $cacheAssets "pet"
if (Test-Path -LiteralPath $petDir) {
    $n = @(Get-ChildItem -LiteralPath $petDir -Recurse -File).Count
    Check "帧文件 > 100" ($n -gt 100) ("当前: $n")
}

Write-Host "== 2. 补丁 =="
if (-not $PackageDir) {
    foreach ($c in @(
            (Join-Path $env:USERPROFILE ".dsh\profiles\desktop\node_modules\dsh-dafeiyu"),
            (Join-Path $env:USERPROFILE ".dsh\profiles\web\node_modules\dsh-dafeiyu"))) {
        if (Test-Path -LiteralPath $c) { $PackageDir = $c; break }
    }
}
if ($PackageDir) {
    $plugin = Join-Path $PackageDir "src\plugin.js"
    if (Test-Path -LiteralPath $plugin) {
        $text = Read-Utf8 $plugin
        Check "定制代码块"   ($text.Contains("小月姬定制补丁"))
        Check "空闲心跳"     ($text.Contains("heartbeatTimer"))
        Check "微信库监视"   ($text.Contains("newestWechatDbMtime"))
        Check "微信通知粘滞" ($text.Contains("wechatStickyUntil"))
        Check "余额阈值"     ($text.Contains("announceLowBalance"))
        Check "文案已改名"   ($text.Contains("小月姬") -and -not $text.Contains("大肥鱼"))
    }
    $client = Join-Path $PackageDir "lib\client.js"
    if (Test-Path -LiteralPath $client) {
        $ctext = Read-Utf8 $client
        Check "设置页文案已改名" ($ctext.Contains("小月姬") -and -not $ctext.Contains("大肥鱼"))
    }
    $copyFile = Join-Path $PackageDir "src\status-copy.js"
    if (Test-Path -LiteralPath $copyFile) {
        $stext = Read-Utf8 $copyFile
        Check "状态台词已改名" ($stext.Contains("小月姬") -and -not $stext.Contains("大肥鱼"))
    }
} else {
    Write-Host "  [SKIP] 未找到 dsh-dafeiyu 目录" -ForegroundColor Yellow
}

Write-Host "== 3. Helper 与日志 =="
$logPath = Join-Path $env:LOCALAPPDATA "dsh-dafeiyu\logs\helper.log"
if (Test-Path -LiteralPath $logPath) {
    $tail = Get-Content -LiteralPath $logPath -Tail 200
    Check "Helper 就绪"     (@($tail | Select-String -Pattern "ready after").Count -gt 0)
    Check "微信监视已武装" (@($tail | Select-String -Pattern "wechat watch armed").Count -gt 0) "(需重启后出现)"
} else {
    Write-Host "  [SKIP] 尚无 helper.log（Helper 还没启动过）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("通过 {0} 项，失败 {1} 项。" -f $script:ok, $script:fail)
if ($script:fail -gt 0) {
    Write-Host "若素材已就位但界面仍是旧文案，请确认已完全退出并重启 DSH。" -ForegroundColor Yellow
    exit 1
}
exit 0
