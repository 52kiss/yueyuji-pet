# 实现原理

## 1. 为什么换角色不用重编译

`dsh-dafeiyu` 的原生角色是一个 PyInstaller 单文件 Helper（PySide6/Qt）。它对角色是**数据驱动**的：

```
%LOCALAPPDATA%\dsh-dafeiyu\<version>\
  dsh-dafeiyu-helper-<size>.exe     # 冻结的渲染器
  assets\
    pet-manifest.json               # 角色清单
    pet\<clip>\<clip>_NNN.webp      # 每帧一个文件
```

Helper 从**自己旁边的 `assets/`** 读取清单与帧（`helper.py` 里的 `bundle_root`）。
Host 侧在启动时的复制逻辑是：

```js
// src/helper-process.js:247-271
const cachedManifest = resolve(cacheDirectory, 'assets', 'pet-manifest.json')
if (!fileExists(cachedManifest)) copyTree(assetsSource, resolve(cacheDirectory, 'assets'), …)
```

**只有缓存缺 `pet-manifest.json` 时才复制**。因此我们只要把自定义 assets 放进缓存目录，
就能稳定覆盖角色，且不触碰二进制。

## 2. 清单结构

```jsonc
{
  "formatVersion": 1,
  "characterId": "yueyuji",
  "baseSize": 412,
  "maxFrameWidth": 412,
  "maxFrameHeight": 344,
  "clips": {
    "idle": { "frames": ["idle/idle_001.webp", …], "frameMs": 200, "loop": true },
    …16 组…
  },
  "stateMap": { "IDLE": "idle", "WORKING": "working", "SUCCESS": "success", "ERROR": "error", … },
  "workingActivityMap": { "searching": "working_search", … },
  "idleMicroClips": ["idle_stretch", "idle_yawn", "eat_token"],
  "idleMicroIntervalsMs": { "quiet": [45000, 90000], … },
  "interactionCooldownMs": 1200
}
```

`stateMap` 是"DSH 状态 → 播哪个 clip"的映射；`workingActivityMap` 决定工具调用时播哪个变体。
本仓库的素材组与上游同名（`idle/waiting/thinking/working/…`），所以映射表可以原样沿用。

## 3. 补丁做了什么

补丁只改 4 个 JS 文件，全部通过 **Host ↔ Helper 既有的 `state` / `tasks` 消息**生效，
没有改协议版本，也没有碰 Helper 二进制：

| 位置 | 作用 |
| --- | --- |
| `src/status-copy.js` | 2 处台词改名 |
| `src/index.js` | 1 处依赖加载失败提示 |
| `lib/client.js` | 4 处设置页文案 |
| `src/plugin.js` | 注入四段逻辑（见下） |

`src/plugin.js` 里注入的四段：

1. **空闲心跳** `heartbeatTimer`（3s 轮询，空闲 5s 后补发）
   Helper 的 `_current_card()` 在 `status_message` 过期（非持久状态 TTL 4200ms）后，
   会返回写死的 `("大肥鱼陪你待命", …)`。心跳定期补发 STATE，使该分支永不命中。

2. **微信消息库监视** `newestWechatDbMtime()`
   微信 4.x 每条消息提交都会写 `D:\xwechat_files\<wxid>\db_storage\message\message_*.db(-wal)`，
   监视其 `max(mtime)`；4s 轮询，45s 静默期节流。

3. **微信提示粘滞 + 恢复** `wechatStickyUntil` / `wechatRestorePending`
   `WAITING` 是 Helper 的持久态（`ttl=None`），若不主动恢复会一直挂着。
   做法：提示保持 20s → 恢复时优先重放 `lastReducerState`（reducer 最近一次真实状态），
   避免把正在跑的任务误清成 IDLE。恢复放在"活跃会话"判断之前，否则活跃时永不恢复。

4. **余额阈值** `announceLowBalance()`
   余额快照 `balances[].total` 低于阈值（默认 5 元，可用 `DSH_YUEYJI_LOW_BALANCE` 覆盖）
   时推 `ERROR` 状态（对应 `error` clip，即垂头），回升后恢复 IDLE。

### 为什么推送前要先清任务卡

Helper 的渲染优先级是 **任务卡 > 状态文案**。若 Helper 当前有任务卡，只发 `state` 会被任务卡盖住，
所以提示前先发一条 `tasks: []`，再发 `state`。

## 4. 素材如何生成

`tools/build_assets.py` 的处理链：

1. 背景判定：`min(R,G,B) >= 248` 视为白底，取**最大连通域**作为背景（避免白色蕾丝被误判）
2. 去背景：`doll = ~background` → 3px 开闭运算去毛刺 → 最大连通域 → **形态学重建填内部空洞**
3. 归一到 412×344 画布，底部留 7px
4. 用整体变换生成 16 组动作：呼吸（缩放）、摇摆（旋转）、跳跃（位移）、垂头（压扁+变暗）、挤压、拉伸、脉冲

> 单张静图只能做"整体变换类"动作。真正的耳朵/尾巴独立摆动需要**分层素材**（耳/身/裙分离），
> 这是本方案的物理上限。

## 5. 补丁器设计（为什么不用 git apply）

上游 4 个文件的换行符不统一：

| 文件 | 上游换行 |
| --- | --- |
| `src/plugin.js` | CRLF |
| `src/index.js` | CRLF |
| `src/status-copy.js` | LF |
| `lib/client.js` | LF |

在 Windows 上，PowerShell 捕获外部命令（`git diff`）输出时会丢弃 `CR`，
生成的统一 diff 只能匹配一半文件；即使手工保住 CR，补丁也会混入"整文件换行变更"的噪音
（实测 1535 行 → 精简后 349 行）。

因此 `tools/apply.ps1` 采用**锚点字符串补丁**：

```
读文件 → 检测换行风格(CRLF/LF) → 内部统一成 LF
      → 按序执行 $steps（每条是 Old → New 的字面替换）
      → 写回时还原原换行风格（UTF-8 无 BOM）
```

特性：

- **换行无关**：同一份 `$steps` 可作用于 CRLF 与 LF 文件
- **幂等**：若 `New` 已存在则跳过；重跑输出 `应用 0 步，跳过 16 步`
- **可诊断**：锚点没匹配会打印 `src\plugin.js → 挂钩:会话事件` 这样的具体项
- **可验证**：在干净的 0.1.23 副本上运行后，4 个文件与开发机上的最终状态**逐字节一致**

注入到 `plugin.js` 的两段较大代码独立成文件，便于审阅与 diff：

- `patches/inject-block.js` —— 余额阈值 + 微信库监视 + 通知粘滞/恢复（164 行）
- `patches/inject-heartbeat.js` —— 空闲心跳（39 行）

> 脚本文件必须以 **UTF-8 with BOM** 保存：Windows PowerShell 5.1 读取 `.ps1` 时若无 BOM 会按 ANSI 解码，中文锚点会变成乱码导致语法错误。
