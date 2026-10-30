# Roadmap：从「素材包 + 补丁」到「一个插件」

当前交付形态是 **assets + patch + 安装脚本**，原因是：

- `dsh-dafeiyu` 没有暴露"注入状态/替换文案"的公开 API，只能改它的 JS；
- 而它的原生窗口能力（PySide6 Helper、透明置顶、点击穿透）自建成本很高。

要变成"装一个插件就完事"，有三条路径，按推荐度排序。

---

## 路径 A（推荐）：向上游提 PR，把定制做成官方配置项

把我们的四段逻辑变成 `dsh-dafeiyu` 的正式配置项，本仓库退化为纯素材包：

| 上游新增配置 | 我们从补丁里删掉的东西 |
| --- | --- |
| `copyOverrides` / `statusCopyPack` | `src/status-copy.js` 的改名 |
| `customName`（显示名） | `src/index.js`、`lib/client.js` 文案 |
| `idleKeepalive: true` | 空闲心跳 |
| `externalWatchers: [{ type: "wechat-db", path }]` | 微信库监视 |
| `balanceWarnBelow` | 余额阈值 |

**优点**：零维护、随上游升级、用户一条命令安装。
**缺点**：依赖作者意愿与排期；需要按上游代码风格写测试。

> 这条路一旦走通，本仓库只需保留 `assets/` + `tools/build_assets.py`。

---

## 路径 B（兜底）：发布自己的 fork

发布 `dsh-yueyuji-pet`，内部是 `dsh-dafeiyu` 的完整 fork + 我们的改动 + 我们的素材：

```
dsh-yueyuji-pet/
  src/…            # fork 自 dsh-dafeiyu 0.1.23
  lib/…
  runtime/         # 复用其 Helper 构建产物（需确认许可）
  assets/          # 月御姬素材
  cordis.patch.yml # id: yueyuji-pet
```

用户侧：

```powershell
dsh plugin --profile desktop add dsh-yueyuji-pet
```

**优点**：真正"一个插件"，可独立迭代。
**缺点**：要跟着上游持续 rebase；Helper 二进制体积 ~46MB；素材与代码许可要分别处理（见 NOTICE.md）。

**落地前置条件**：

1. 与上游作者确认 fork 命名与素材再分发许可
2. 建立 rebase 流程（每个上游版本打一个 tag）
3. 增加 CI：`node --check` + 一个"manifest 能被 Helper 接受"的冒烟测试

---

## 路径 C：自建 Helper（长期）

不依赖上游 Helper，自己写渲染器（Qt / WebView 透明窗）：

- 复用本仓库的 `pet-manifest.json` 约定
- 自己实现状态协议、拖动、穿透、托盘菜单
- 好处：完全掌控，能做分层动画、点击穿透更精细、支持多角色

成本最高（相当于重做 `dsh-dafeiyu` 的窗口层），只有在 A、B 都不通时才考虑。

---

## 近期任务清单

- [x] 素材管线（抠图 → 16 组动作 → manifest）
- [x] 名字与文案替换
- [x] 微信「有人找你」提醒（消息库写入监视）
- [x] 余额阈值联动
- [x] 空闲心跳（顶掉兜底文案）
- [x] 微信提示粘滞 20s + 到期自动恢复
- [ ] 微信提醒区分收发（需前台窗口判断）
- [ ] 分层素材支持（耳朵/尾巴独立动作）
- [ ] 向上游提交 PR（路径 A）
- [ ] 若 PR 不通，按路径 B 发布 fork
- [ ] 重编译 Helper 以改掉窗口标题与兜底文案

## 版本约定

- 补丁文件名带上游版本：`dsh-dafeiyu-<version>-yueyuji.patch`
- 上游升级时：先跑 `verify.ps1` 看哪些 PASS 变 FAIL，再决定重做补丁还是等 PR
