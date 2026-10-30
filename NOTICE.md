# 第三方组件与授权说明

本仓库自身只包含：角色素材、一份补丁、安装脚本与文档。它**不包含** `dsh-dafeiyu` 的源码。

## dsh-dafeiyu

- 项目：https://github.com/QCYTSN/dsh-dafeiyu
- 版本基准：`0.1.23`
- 许可：见其仓库 `LICENSE` 与 `ASSET_LICENSE.md`（软件代码与角色素材分别授权）

本仓库提供的 `patches/dsh-dafeiyu-0.1.23-yueyuji.patch` 是对该包 4 个文件的修改补丁
（`src/plugin.js`、`src/status-copy.js`、`src/index.js`、`lib/client.js`）。
补丁以 diff 形式分发，使用者需自行安装上游包后再应用。
如果你要再分发修改后的完整文件，请自行确认符合上游许可。

### 补丁内容边界

| 文件 | 改动 |
| --- | --- |
| `src/status-copy.js` | 2 处文案把「大肥鱼」改为「小月姬」 |
| `src/index.js` | 1 处错误提示文案 |
| `lib/client.js` | 4 处设置页文案 |
| `src/plugin.js` | 注入「空闲心跳、微信消息库监视、余额阈值、微信通知粘滞与恢复」四段逻辑，并改 2 处描述文案 |

## 上游素材

`dsh-dafeiyu` 自带的鲸鱼娘素材来自 [PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet)。
本仓库**不包含**该素材；安装脚本会把它备份为 `assets-whale-backup` 以便回滚。

## 微信

本仓库的「有人找你」提醒仅读取**本机**微信桌面版消息数据库文件的修改时间，
不解析消息内容、不连接微信服务器、不绕过任何鉴权。
请自行确认这种本地提示方式符合你所在地区与腾讯的用户协议。
