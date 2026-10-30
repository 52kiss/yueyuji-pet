# 排障

## 角色没变 / 还是鲸鱼娘

按顺序查：

1. **素材是否部署到了对的地方**

   ```powershell
   Get-Content "$env:LOCALAPPDATA\dsh-dafeiyu\0.1.23\assets\pet-manifest.json" -Raw | Select-String characterId
   ```

   期望 `"characterId": "yueyuji"`。若是 `whaletail-maid`，说明还在读上游素材。

2. **是否重启过**：Helper 只在启动时读清单。改完必须完全退出 DSH 再打开。

3. **是不是另一个 profile**：桌面端用 `profile=desktop`。若你同时开了 WebUI（`profile=web`），
   它有自己的 node_modules 与缓存，需要单独安装。

## 文案还是「大肥鱼」

分两类：

| 位置 | 能否改 | 说明 |
| --- | --- | --- |
| 气泡状态文案 | ✅ 已改 | 心跳 + `status-copy.js` |
| 设置页标题/开关 | ✅ 已改 | `lib/client.js` |
| **窗口标题** | ❌ | `helper.py` 里 `setWindowTitle("DSH 大肥鱼")`，已编译进 exe |
| **空闲兜底卡** | ⚠️ 已绕过 | `helper.py:854` 写死；靠心跳避免命中，20 秒空窗除外 |

要彻底改这两处只能重编译 Helper（需要 `PySide6>=6.7,<7` + PyInstaller），代价大且可能弄坏现有 exe。

## 微信提示不出现

1. **确认监视已武装**

   ```powershell
   Select-String -Path "$env:LOCALAPPDATA\dsh-dafeiyu\logs\helper.log" -Pattern "wechat watch armed"
   ```

   没有这行 → Helper 没重启，或 `D:\xwechat_files` 不存在。

2. **确认微信数据在默认路径**。默认 `D:/xwechat_files`，可用环境变量覆盖：

   ```powershell
   $env:DSH_YUEYJI_WECHAT_DB = "E:/xwechat_files"   # 然后在同一环境里启动 DSH
   ```

3. **确认微信是登录状态且收到过消息**（看 `message_*.db-wal` 的 mtime 是否在变）：

   ```powershell
   Get-ChildItem "D:\xwechat_files\*\db_storage\message\message_*.db*" |
     Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name,LastWriteTime
   ```

## 微信提示不消失

已修（恢复逻辑放在活跃判断之前）。若仍出现，检查 `helper.log` 里是否有
`settings.update failed` 之类的异常，并把最近 20 行发到 issue。

## 你自己发消息也弹「有人找你」

这是已知限制：判定依据是"消息库有写入"，分不清收发。缓解方式：

- 45 秒静默期（`WECHAT_QUIET_MS`）
- 想更准可以做"微信窗口是否前台"的判断，但每 4 秒调一次 Win32 开销偏大，暂未实现

## 提示一闪而过 / 停留太久

`src/plugin.js` 里 `WECHAT_STICKY_MS`（默认 `20000`）控制停留时长，改完重启。

## 打补丁失败 / 锚点未匹配

安装器是**锚点字符串替换**，不是 `git apply`。它会打印类似：

```
补丁：应用 14 步，跳过 0 步（已打过）
WARNING: 以下锚点未匹配（可能是上游版本不同）：
  - src\plugin.js → 挂钩:会话事件
```

常见原因：

- **版本不同**：`dsh-dafeiyu` 不是 0.1.23。降级到 0.1.23，或按 [ARCHITECTURE.md](ARCHITECTURE.md) 调整 `tools/apply.ps1` 里的 `$steps`。
- **已经打过**：会显示 `应用 0 步，跳过 16 步`，属正常。
- **文件被改坏（中文乱码/半截）**：`apply.ps1` 自己会以 UTF-8 无 BOM 读写，不会破坏编码；若外部工具（编辑器）改过换行或编码，用最近的 `.yueyuji-backup-*` 恢复后重跑。
- **脚本无法运行**：报"未对文件进行数字签名"时，用 `powershell -ExecutionPolicy Bypass -File .\tools\apply.ps1` 方式调用。

## 桌面端 EPERM

如果 `dsh plugin` 类命令报 `EPERM … package.json.lock`，说明 Host 正在运行、profile 被占用。
先完全退出应用再操作（本仓库的安装脚本不需要 pnpm，不受影响）。

## 想临时关掉角色

右键角色 → 「本次隐藏」/「关闭角色」；或在插件设置里关闭「启用小月姬」（会退出 Helper）。
