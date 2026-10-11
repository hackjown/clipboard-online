# Clipboard Online · 多端剪贴板（Monorepo）

跨设备在线剪贴板：**私有区 + 公共区**，Web 服务端 + Flutter 桌面/移动客户端。

```
clipboard_online/
  server/     FastAPI 后端（纸与墨 Web UI + API + WebSocket）
  client/     Flutter 客户端（macOS + iOS + Android）
  .github/    Docker / Flutter CI
```

## 演示账号

| 用户名 | 密码 |
| --- | --- |
| `demo1` | `demo123` |
| `demo2` | `demo123` |
| `alice` | `demo123` |

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


## 本版新增（v0.1.4）

- **Web 文件预览**：图片（缩放、上一张/下一张）、视频 / 音频（HTTP Range，206）、PDF（iframe）、文本 / 代码 / JSON（前 200KB，纯文本渲染）；分享页 `/s/<token>` 同样可预览。内联端点 `GET /download/<name>?inline=1`、`GET /s/<token>/file?inline=1` 仅对白名单类型内联，**html / svg / js 等一律强制下载**，并带 `nosniff` 与 CSP sandbox；私有 / 过期规则不变。
- **客户端**：「纸与墨」主题、媒体预览、新图标、macOS 菜单栏模式，详见 `client/README.md`。
