# 安装与回滚

## 前提

| 项 | 要求 |
| --- | --- |
| 系统 | Windows 10 / 11 x64 |
| DSH | 官方桌面端（`profile = desktop`） |
| 底座 | `dsh-dafeiyu@0.1.23`，已在应用内安装并**启用** |
| 工具 | **无需 git、无需 Python**（装环境脚本用 Windows 自带 PowerShell 5.1 即可） |

检查底座是否就位：

```powershell
Test-Path "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-dafeiyu"
```

## 一键安装

下载本仓库（`git clone` 或直接下载 ZIP 解压），然后：

```powershell
cd yueyuji-pet
powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1
```

脚本会：

1. 备份将被修改的 4 个文件到 `dsh-dafeiyu\.yueyuji-backup-<时间戳>\`
2. 用**锚点字符串补丁**改写文案、注入代码（幂等：已打过会跳过）
3. 把 `assets/` 部署到 `%LOCALAPPDATA%\dsh-dafeiyu\0.1.23\assets\`，
   第一次部署时把上游鲸鱼娘素材改名为 `assets-whale-backup`
4. 提示重启

随后**完全退出并重新打开** DeepSeek Harness（关窗口不算，要退出进程）。

> 指定其他安装位置：`-PackageDir "D:\somewhere\node_modules\dsh-dafeiyu"`
> 只要素材不打补丁：`-SkipAssets`（反向同理可配合手工）

## 自检

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify.ps1
```

期望：`characterId = yueyuji`、`动作组 = 16`、`帧文件 > 100`，补丁各项 PASS。

## 为什么要"字符串补丁"而不是 git apply

上游 4 个文件的换行符并不统一：`plugin.js`、`index.js` 是 **CRLF**，`status-copy.js`、`client.js` 是 **LF**。
在 Windows 上生成/应用统一 diff 时，PowerShell 捕获外部输出会丢掉 CR，导致补丁永远只能匹配一半文件。

因此安装器改为：**按锚点字符串替换**，读文件时检测其换行风格（CRLF/LF），内部统一用 LF 处理，写回时还原。
好处是：换行无关、幂等、不依赖 git，且能明确报出"哪个锚点没匹配上"。

## 手动安装（脚本不可用时）

```powershell
$pkg = "$env:USERPROFILE\.dsh\profiles\desktop\node_modules\dsh-dafeiyu"
$cache = "$env:LOCALAPPDATA\dsh-dafeiyu\0.1.23"

# 1) 备份
"src\plugin.js","src\status-copy.js","src\index.js","lib\client.js" | ForEach-Object {
    Copy-Item "$pkg\$_" "$pkg\$_.bak" -Force
}

# 2) 仅部署素材（补丁请优先用 apply.ps1）
if (Test-Path "$cache\assets") { Rename-Item "$cache\assets" "assets-whale-backup" }
New-Item -ItemType Directory "$cache\assets" -Force | Out-Null
Copy-Item "<repo>\assets\*" "$cache\assets" -Recurse -Force
```

补丁部分如需手工完成，参考 `patches/inject-block.js`（注入的代码块）、
`patches/inject-heartbeat.js`（心跳块）与 `tools/apply.ps1` 中的 `$steps` 锚点表。

## 回滚

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1 -Revert
```

会从最近的 `.yueyuji-backup-*` 还原 4 个文件，并把 `assets-whale-backup` 改回 `assets`。

## 升级 dsh-dafeiyu 之后

重装会覆盖 `src/`、`lib/`，但**不会动** `%LOCALAPPDATA%` 缓存：角色还在，文案与联动失效。重跑 `apply.ps1` 即可。

若上游版本变化导致锚点不匹配，脚本会打印未匹配项（例如 `src\plugin.js → 挂钩:会话事件`），
此时需要按新版本调整 `tools/apply.ps1` 里的 `$steps` 锚点。
