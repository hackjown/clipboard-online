# Clipboard Online · 多端剪贴板（Monorepo）

跨设备在线剪贴板：**私有区 + 公共区**，Web 服务端 + Flutter 桌面/移动客户端。

```
clipboard_online/
  server/     FastAPI 后端（纸与墨 Web UI + API + WebSocket）
  client/     Flutter 客户端（macOS + iOS + Android）
  .github/    Docker / Flutter CI
```

## 服务端（Docker / 本地）

```bash
cd server
./run.sh                          # http://0.0.0.0:8099
# 或
docker build -t clipboard-online .
docker run -d -p 8099:8099 -e CLIP_PASSWORD=  -v clip-data:/data clipboard-online
```

- API / Swagger：`/docs` · `/openapi.json`
- 客户端对接文档：[`server/docs/CLIENT_API.md`](server/docs/CLIENT_API.md)
- 原生路线图：[`server/docs/CLIENT_ROADMAP.md`](server/docs/CLIENT_ROADMAP.md)

CI：推送 `main` / tag 时构建并推送到 `ghcr.io/<owner>/<repo>/clipboard-online`。

## 客户端（Flutter · Mac / iOS）

详见 [`client/README.md`](client/README.md)。

```bash
cd client
flutter pub get
flutter run -d macos
# 真机构建见 client/README（需在 Mac + Xcode 上签名）
```

- 认证：Bearer token（`flutter_secure_storage`）
- 功能：公共/私有列表、添加文本、上传文件/相册图、分享二维码、过期与敏感提醒、收藏/置顶、WebSocket 同步
- **Mac**：可选「监听剪贴板」轮询，变化时确认后上传为私有
- **iOS**：**不做**后台剪贴板监听；前台「从剪贴板导入」；Deep link `clipboard://s/<token>`
- **快传**：Mac 拖放 / 手机选文件 → 私有上传，对端 WebSocket 同步；系统分享 + 访达显示
- **通知**：App 运行/刚退后台时，其他设备发来新私有内容会本地通知 + 角标（无 APNs 后台推送，见 client/README）
- **Android**：完整客户端；`flutter build apk --release` 见 client/README
- **iOS 分享入**：Share Extension 源码在 `client/ios/Share Extension/`，签名步骤见 `client/ios/SHARE_EXTENSION.md`


## 下载（GitHub Releases）

推送 `v*` 标签（如 `v0.1.0`）后，CI 自动发布 Release，包含：

| 文件 | 说明 |
| --- | --- |
| `clipboard-android.apk` | Android 安装包（debug 签名，可直接侧载） |
| `clipboard-macos.zip` | macOS `.app`，**未签名、未公证**：右键 →「打开」，或 `xattr -cr clipboard_client.app` |
| `clipboard-ios-unsigned.ipa` | iOS **未签名** IPA，**不能直接安装**；用 AltStore / Sideloadly / TrollStore 或自有证书重签（见下） |

> **macOS 说明**：CI 产出的 macOS 应用未签名，没有 Keychain 权限（-34018），因此登录令牌回退保存到本地应用偏好设置（SharedPreferences）；iOS/Android 仍使用 Keychain/Keystore。

### iOS IPA 说明

- 该 IPA 由 `flutter build ios --no-codesign` 打包（`Payload/Runner.app`），**未签名**，须重签后才能安装：
  - **AltStore / SideStore / Sideloadly**：用你的 Apple ID 自动重签（免费账号 7 天过期）；
  - **TrollStore**（仅特定 iOS 版本）：可直接安装未签名 IPA；
  - 或用自己的开发者证书在 Xcode / `fastlane` / `zsign` 中重签。
- Bundle ID：`com.clipboard.online.clipboardClient`，侧载工具可能会改写它；App Group 为 `group.com.clipboard.online.clipboardClient`。
- IPA **已嵌入 Share Extension**（`Payload/Runner.app/PlugIns/ShareExtension.appex`，Bundle ID `com.clipboard.online.clipboardClient.ShareExtension`，CI 会校验）。重签后微信/相册/文件的分享面板里才会出现「剪贴板」；签名与 App Group 说明见 [`client/ios/SHARE_EXTENSION.md`](client/ios/SHARE_EXTENSION.md)。
- 免费 Apple ID 无法使用 App Groups；重签时若报 entitlement 错误，可去掉 App Group（主 App 的快传不依赖它，仅 Share Extension 需要）。

服务端 Docker 镜像：`ghcr.io/hackjown/clipboard-online/clipboard-online`（`v*` 标签同时推 `latest` 与版本号）。
私有仓库的镜像默认私有，拉取前先 `docker login ghcr.io`（用有 `read:packages` 的 PAT）。

## 推送到 GitHub

本仓库已在本地 `git init` 并完成初始提交。在你本机或 1:1 会话里登录 `gh` 后：

```bash
gh repo create clipboard_online --private --source=. --remote=origin --push
# 或先建空仓再：
git remote add origin git@github.com:<you>/clipboard_online.git
git push -u origin main
```

请勿提交 `.venv`、`data/*.json`、真实密钥。


## 本版新增（v0.1.8）

- **分享扩展不再使用 URLSession**：扩展里用 Network.framework 的 `NWConnection` 自己实现了一个极简 HTTP/1.1 客户端（登录 JSON、文本 JSON、文件 multipart 按 256KB 分块从磁盘流式发送；进度 / 取消 / 超时；支持 Content-Length 与 chunked 响应；不跟随重定向）。它是纯 TCP/TLS，不经过 CFNetwork，因此 ATS 无法介入。扩展 Info.plist 另外加了按域名的 `NSExceptionDomains`（与 `NSAllowsArbitraryLoads` 并存）。
- **分享面板错误里带诊断行**：`［诊断］扩展 v版本(build) · bundle · iOS 版本 · App Group 可用/不可用 · 传输=NWConnection · 运行时 ATS 配置=…`，同时写入扩展日志（设置里可见）。读法见 `client/ios/SHARE_EXTENSION.md`。
- **Bark 测试 “Not Found”**：这是 FastAPI 对「不存在的路由」的默认回复，不是我们的 502 文案——最可能是服务器还在旧 Docker 镜像（没有 `/api/settings/bark/test`）。现在 `GET /api/version` 与 `/api/config` 返回 `version` / `features`；客户端设置页显示「客户端版本 / 服务器版本」，遇到裸 404 会提示「服务器版本过旧（x.y.z），请更新 Docker 镜像」。Bark 推送先 `POST {host}/{key}`，404 时回退 `POST {host}/push`（带 `device_key`），并显示 Bark 自己的错误信息；`…/KEY`、`…/KEY/`、`…/KEY/内容`、自建服务器地址都能识别。
- **文本可编辑**：`PATCH /api/items/<uuid>`（仅所有者；`content` / `visibility` / `expires_in` / `tags`；更新 `updated`，分享令牌不变，WebSocket 广播 `update`）。Web 文本卡片「编辑」按钮（⌘/Ctrl+Enter 保存），Flutter 三端文本卡片「编辑」。同时修复了 Web 卡片缓存不随内容变化刷新的问题。

## 更早的版本（v0.1.7）

- **iOS 分享扩展 ATS 根因已定位并修复**：苹果文档规定 iOS 10+/macOS 10.12+ 只要 Info.plist 里同时出现 `NSAllowsArbitraryLoadsForMedia` / `NSAllowsArbitraryLoadsInWebContent` / `NSAllowsLocalNetworking` 任意一个，系统就**忽略** `NSAllowsArbitraryLoads`。我们 v0.1.4–v0.1.6 恰好都带了这些键，所以明文 `http://` 被拦。现在 Runner（iOS / macOS）与分享扩展的 Info.plist 都**只保留** `NSAllowsArbitraryLoads=true`；CI 新增 `client/tool/verify_ats.sh`，逐个检查 IPA 内主 App 与 `.appex`（含 TrollStore IPA）以及 macOS app 的 Info.plist，出现冲突键会让构建失败。
- **首页布局**：「快传」不再内嵌在首页，标签栏旁新增「快传」按钮，点开独立页面（iOS / Android / macOS 主窗口；菜单栏浮窗仍保留紧凑投放区）。
- **主题设置**：三端客户端「设置 → 外观主题」：跟随系统 / 浅色 / 深色（持久化）；Web 账号菜单里也可直接选这三项。
- **Web 上传**：文件选择器去掉 `accept` 限制，任意类型、可多选（旧代码 `image/*,*/*` 在 iOS/部分浏览器只给相册）。
- **压缩包目录预览**（Web + Flutter 三端）：`GET /api/items/<uuid>/archive`、`GET /s/<token>/archive` 返回 `{entries:[{path,size,is_dir,modified,encrypted}], total, total_size, truncated}`。支持 **zip（含 jar/apk/ipa/aar/war）、tar、tar.gz/tgz、tar.bz2、tar.xz**；**不解压、不提供条目内容**；最多 2000 条（超出 `truncated`），>2 GB 的压缩包不检查，压缩 tar 流式读取有 8 秒时间预算；加密 zip 仅显示目录并标记；损坏返回 422；文件名中的 `../`、控制/bidi 字符只当纯文本显示。**7z / rar 暂不支持**（需额外依赖），接口返回 415 与说明。私有/公共/分享/过期规则与下载一致。

## 更早的版本（v0.1.5 / v0.1.6）

- **iOS 安装包怎么选**：
  - **TrollStore** → 用 `clipboard-ios-trollstore.ipa`（CI 用 ldid 伪签，并给主 App 与分享扩展写入 App Group entitlement）。
  - **AltStore / Sideloadly** → 用 `clipboard-ios-unsigned.ipa`，由工具重签（免费 Apple ID 没有 App Group，分享扩展会在分享面板里登录一次后直传，详见 `client/ios/SHARE_EXTENSION.md`）。
- **分享扩展重写**：扩展自己读取分享内容并直接上传到私有区，面板里显示进度与精确错误；不再依赖 App Group / 跳回主 App（旧版在 App Group 不可用时会崩溃）。
- **Bark 推送**：在 iPhone 安装 [Bark](https://github.com/Finb/Bark)，复制其中的设备地址（形如 `https://api.day.app/你的Key`），粘贴到 Web「账号菜单 → Bark 推送」或客户端「设置 → Bark 推送地址」，点「测试」。之后你的**私有**内容被创建时，服务端会异步推送「剪贴板：收到新内容」（文本前 60 字 / 文件名）。侧载或 TrollStore 的 iPhone 同样可用 —— Bark 走自己的 APNs，不依赖本 App 的推送能力。可勾选「不推送本设备发出的内容」（客户端随写入请求发送 `X-Device-Id`）。出于 SSRF 防护，只允许 http/https，且默认拒绝内网 / 回环地址；自建在内网的 Bark 需设置环境变量 `CLIP_BARK_ALLOW_PRIVATE=1`。

## 更早的版本（v0.1.4）

- **Web 文件预览**：图片（缩放、上一张/下一张）、视频 / 音频（HTTP Range，206）、PDF（iframe）、文本 / 代码 / JSON（前 200KB，纯文本渲染）；分享页 `/s/<token>` 同样可预览。内联端点 `GET /download/<name>?inline=1`、`GET /s/<token>/file?inline=1` 仅对白名单类型内联，**html / svg / js 等一律强制下载**，并带 `nosniff` 与 CSP sandbox；私有 / 过期规则不变。
- **客户端**：「纸与墨」主题、媒体预览、新图标、macOS 菜单栏模式，详见 `client/README.md`。
