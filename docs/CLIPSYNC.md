# 多设备剪贴板同步（v0.1.12）

一台设备上复制，你的其他设备上直接粘贴。

## 致谢 / 许可

设计思路参考 [zlx2019/lanecho](https://github.com/zlx2019/lanecho)（MIT License，Copyright (c) 2026 Zero）。
本项目**没有复制 lanecho 的代码**（它是 Rust / Swift，本项目是 Python / Dart / JS），只借鉴了产品设计与同步语义，按本项目的技术栈独立重写。

## lanecho 的架构（调研结论）

| 方面 | lanecho | 本项目 |
|---|---|---|
| 拓扑 | 局域网 P2P，无服务端 | 经由本服务器中转（FastAPI + WebSocket），跨网络可用 |
| 发现 | mDNS 为主、UDP 组播兜底 | 不需要：设备登录同一账号即自动出现在「我的设备」 |
| 配对 / 身份 | 一次性配对，TLS 1.3 双向认证，证书 BLAKE3 指纹 | 账号登录（Bearer / Cookie）+ 每台设备随机 `X-Device-Id` |
| 协议 | 4 字节长度前缀 + JSON 帧，Hello→…→Bye 短连接事务 | `POST /api/clipsync` + WebSocket `{"type":"clip",…}` 推送 |
| 一次复制只传播一次 | 内容哈希 + 回声表（远端写入的哈希只吞一次） | 服务器 SHA-256 去重 + 客户端 `EchoGuard` 回声抑制 |
| 冲突 | LWW（最后写入者胜） | LWW，以服务器收到时间为准（避免设备时钟偏差）；客户端不让旧的覆盖新的 |
| 同步方向 | 双向 / 只发送 / 只接收 / 关闭 | 同样四种，按设备设置 |
| 敏感内容 | 识别密码管理器的 Concealed 标记 | Flutter 插件拿不到该标记 → 用本项目已有的「疑似密钥」启发式，默认跳过 |
| 历史 | 本地 JSON 历史 + 快捷键面板 | 同步内容可选记入「我的私有」（所有已有功能：搜索、收藏、预览…） |
| 加密 | TLS 1.3 mTLS 传输加密 | 依赖 HTTPS（请用 https 部署）；服务器可见内容，与本项目其他数据一致 |
| 类型 | 文本 512 KiB / 图片 16 MiB / 文件 64 个 | **仅文本**，上限 512 KiB（与 lanecho 一致） |

## 没有移植的部分及原因

- **局域网 P2P / mDNS / UDP 组播 / mTLS 配对**：本项目已有服务器和账号体系，中转模式跨网络、无需配对；在 iOS 上做 P2P 还需要后台网络权限，侧载环境不可行。
- **图片 / 文件自动同步**：已有「快传」覆盖手动传图传文件；自动同步大对象容易误传、费流量，先只做文本。
- **快捷键历史面板、选中后自动粘贴、按来源 App 的忽略规则**：依赖桌面系统辅助功能 / 前台 App 识别等原生能力，Flutter 跨平台层没有可靠实现。
- **端到端加密**：需要在所有端（含网页）共享密钥；当前以 HTTPS 传输加密为准，后续可选加。

## 平台限制

- **macOS**：每秒检查剪贴板，菜单栏常驻时也有效；收到即写入本机剪贴板。
- **iOS**：系统禁止后台读剪贴板。只在打开 / 回到 App 时同步一次（先发本机新复制，否则取服务器最新一条写入本机）；App 在前台时实时接收。iOS 16+ 读取会弹「允许粘贴」，可在系统设置里对本 App 选「允许」。另有「立即发送本机剪贴板」按钮。
- **Android 10+**：只有前台 App 能读剪贴板，同 iOS 的前台策略。
- **网页**：浏览器不能后台监听剪贴板；账号菜单 →「多设备剪贴板同步」可查看设备、复制当前同步内容、手动发送。

## API

- `GET /api/devices` → `{devices:[{device_id,name,platform,direction,online,current,last_seen}]}`
- `PUT /api/devices/{device_id}` `{name, platform, direction: both|send|recv|off}`（最多 50 台）
- `DELETE /api/devices/{device_id}`
- `GET /api/clipsync` → `{clip:{text,hash,ts,origin,origin_name}|null}`
- `POST /api/clipsync`（需 `X-Device-Id`）`{text, save_history?}` → `{duplicate, uuid, clip}`；方向为 recv/off 的设备 403；超过 512 KB 413
- WebSocket：`/ws?device=<id>`（在线状态）；事件 `clip`（只发给本人）、`devices`；同步产生的私有条目 `create` 事件带 `source:"clipsync"`（客户端不弹通知，服务器不发 Bark）
