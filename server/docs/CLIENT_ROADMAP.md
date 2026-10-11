# 客户端路线图（iOS · Android · Mac）

> 规划文档，**不含**原生工程代码。服务端 API 已就绪（见 [CLIENT_API.md](./CLIENT_API.md)）。

## 目标

做三个「贴上去就能取」的轻客户端，共用同一后端：

1. **手机**：快速把剪贴板/截图送上云，或从公共/私有区取回  
2. **Mac**：菜单栏常驻，可选监视剪贴板变化并一键上传  
3. **统一账号**：用户名密码 + Bearer；实时用 WebSocket

**不做**：浏览器扩展（已明确取消）。

---

## 推荐技术栈

| 平台 | 建议 | 备选 |
| --- | --- | --- |
| iOS + Android +（可选）Mac | **Flutter** 一套 UI + `http`/`dio` + `web_socket_channel` | Kotlin Multiplatform / 原生分端 |
| Mac 菜单栏增强 | Flutter macOS **或** 小体积原生（Swift + `NSStatusItem`） | Electron（偏重，不优先） |

优先 Flutter 的理由：三端 UI 一致、对接现有 REST/WS 快、一人可维护。Mac 若需要更深的系统剪贴板钩子，可用 MethodChannel 调原生，或单独做菜单栏伴侣 App。

---

## 信息架构（三端共用）

- 登录 / 注册（Bearer 存 Keychain / Keystore / macOS Keychain）  
- Tab：**公共** | **我的私有** | **收藏**  
- 条目卡片：文本（Markdown 预览开关）、图片缩略图、过期倒计时、标签  
- 发布：文本 / 相册或截图 / 文件；可见性 + 过期；公开前敏感检测  
- 分享：生成链接 + 二维码；系统分享表  
- 设置：服务器地址、关闭注册时的提示、主题

Deep link：`https://{host}/s/{token}` → 打开分享落地页（未登录也可看公开分享）。

---

## 平台要点与限制

### iOS

- **剪贴板**：只能在前台（或用户明确操作时）读取；**不能**承诺后台持续监听剪贴板（隐私与审核）。  
- 产品文案写成：「打开 App / 点『上传剪贴板』时读取」。  
- 截图：分享扩展（Share Extension）或相册选图，比后台监听更稳妥。  
- 推送：可选；实时以 WebSocket 为主，进后台后改短轮询或下次冷启动刷新。  
- 分发：TestFlight；若用户提到「侧载 IPA」，仅作企业签/ad-hoc **内部**分发说明，需合规，不作为商店替代方案宣传。

### Android

- 后台读剪贴板：Android 10+ 限制严格，**仅默认输入法或有焦点的 App** 可靠读取。  
- 可行方案：前台服务 + 通知栏「点击上传」；或悬浮按钮；不要承诺静默后台偷读。  
- 电池与厂商杀进程：WS 需重连退避；可用 WorkManager 做偶尔同步。

### Mac

- 菜单栏 App：菜单内「上传当前剪贴板」「最近公共/私有」「偏好」。  
- 剪贴板监视：`NSPasteboard` 轮询 changeCount（前台/LaunchAgent 可做）；上传前去重，避免循环。  
- 快捷键：全局热键「上传文本/截图」。  
- 与手机同一账号，WS 同步列表。

---

## 与现有 API 的映射

| 客户端能力 | API |
| --- | --- |
| 登录 | `POST /api/login` → 存 `token` |
| 列表 | `GET /api/items?scope=` |
| 上传文本/图 | `POST /content` · `POST /upload_file` |
| 分享/二维码 | `POST /api/items/{id}/share` · `GET /api/share/{token}/qr` |
| 收藏置顶标签 | `favorite` / `pin` / `tags` |
| 实时 | `WS /ws?token=` |
| 打开分享 | App Link → 原生页或内嵌 `GET /api/share/{token}` |

敏感检测：客户端复刻 Web 启发规则，公开前弹确认。

---

## 里程碑建议

1. **M1**：Flutter 登录 + 公共/私有列表 + 添加文本 + Bearer（iOS/Android）  
2. **M2**：图片上传/缩略图、过期、分享链接与系统分享、Deep link  
3. **M3**：WebSocket 同步、收藏/标签、Markdown 预览  
4. **M4**：Mac 菜单栏 + 剪贴板热键；Android 前台「一键上传」；iOS Share Extension  
5. **M5**：多服务器地址、导出备份、无障碍与审核材料

---

## 风险与原则

- 不承诺任何平台的**后台静默剪贴板监控**。  
- 公共区与分享链接视为「知悉者可读」，产品内重复提示。  
- 自建服务器地址由用户填写，默认可指向官方演示实例。  
- 暂无 OAuth；先用户名密码，后续可加通行密钥。

本文随 API 变更更新；实现时以 `/openapi.json` 为合同。
