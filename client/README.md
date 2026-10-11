# 剪贴板 · Flutter 客户端（macOS + iOS + Android）

对接 Clipboard Online 服务端 API（Bearer）。三端共用同一套 Dart 代码：登录、公共/私有、快传、系统分享、WebSocket。

## 环境

- Flutter 3.x stable  
- macOS / iOS：Xcode 15+  
- Android：Android Studio，JDK 17，SDK 21+

```bash
flutter pub get
flutter analyze
flutter run -d macos
flutter run -d <ios-device>
flutter run -d <android-device>
```

登录页可改「服务器地址」。

## 功能对照

| 功能 | 说明 |
| --- | --- |
| 登录/注册 | Bearer 存于 Keychain / Keystore |
| 公共 / 我的私有 | Tab + 下拉刷新 + 搜索 |
| 添加文本 | 可见性 + 过期；公开前敏感检测 |
| 上传 | 文件选择 / 相册图片 |
| 剪贴板 | **Mac** 可选监听；**iOS/Android** 手动「从剪贴板导入」 |
| 快传 | 拖放(Mac)/选文件 → **私有**上传；对端 WS 同步 |
| 系统分享出 | `share_plus` → 微信等（iOS/Android） |
| 系统分享入 | Android Intent + **iOS Share Extension**（见下） |
| 实时 | WebSocket，失败则 5s 轮询 |
| Deep link | `clipboard://s/<token>` |

## 局域网 HTTP 与本地通知

- **局域网 http://IP:端口**：iOS/macOS 的 `Info.plist` 已配置 ATS（`NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking`），iOS 另有 `NSLocalNetworkUsageDescription`（首次连接局域网会弹「本地网络」授权，请允许）；Android 已允许明文流量。WebSocket 会自动用 `ws://`（https 时用 `wss://`），不受 ATS 限制。
- **本地通知**（`flutter_local_notifications`，iOS/macOS/Android）：App 运行中或刚退到后台时，WebSocket 收到**其他设备**上传的新私有内容，会弹「收到新文件 / 收到新文本」，并在 iOS/macOS 设置未读角标；回到前台或打开「我的私有」即清零。本机自己上传的内容不会提醒（按上传返回的 uuid 过滤）。启动时会请求通知权限。
- **不包含后台推送**：真正的离线/杀进程后推送需要 APNs（以及开发者账号和服务端推送），侧载 IPA 做不到，本版**未提供**。App 被系统挂起后连接会断开，无法收到通知，回到前台后会自动补刷列表。

## 快传（双向）

同一账号下，Mac ↔ 手机通过 **私有区 + WebSocket** 互传：

1. **Mac → 手机**：拖放或选文件 →「发送到我的设备」→ 私有上传 → Toast「已发送，其他设备将同步」→ 手机点「分享」可转微信  
2. **手机 → Mac**：快传选文件 / 或从微信等 **系统分享到「剪贴板」** → 确认上传私有 → Mac 实时出现，可「在访达中显示」

快传路径 **始终私有**。

### 从微信分享到本 App（iOS）

微信走 **系统分享面板**，不需要非官方微信 SDK：

1. 在微信中点「…」→「分享」  
2. 面板中选择 **「剪贴板」**（Share Extension）  
3. 主 App 打开后确认「发送到我的设备」→ 私有上传  

Share Extension 目标已嵌入工程（IPA 内含 `.appex`）；真机使用需签名并启用 App Group，详见 [`ios/SHARE_EXTENSION.md`](ios/SHARE_EXTENSION.md)。

Android：其它 App「分享到」列表会出现「剪贴板」（已配置 `SEND` / `SEND_MULTIPLE` Intent）。

## Android 构建 APK

```bash
cd client
flutter pub get
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk

# 可选分架构更小包：
flutter build apk --release --split-per-abi
```

安装：`adb install -r build/app/outputs/flutter-apk/app-release.apk`  
局域网调试请把服务器地址设为电脑的 `http://192.168.x.x:8099`（Android 已允许 cleartext）。

App Bundle（上架）：

```bash
flutter build appbundle --release
```

> macOS 应用未签名：令牌回退保存到本地应用偏好设置（SharedPreferences），不使用 Keychain（避免 -34018）。iOS/Android 仍用 Keychain/Keystore。

## macOS 构建

```bash
flutter config --enable-macos-desktop
flutter build macos --release
# build/macos/Build/Products/Release/clipboard_client.app
```

## iOS 构建与 Share Extension 签名

### 未签名（CI）

```bash
flutter build ios --release --no-codesign
# 打包 IPA：
mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/ && zip -qry clipboard-ios-unsigned.ipa Payload
```

### 正式签名 + Share Extension

1. 按 [`ios/SHARE_EXTENSION.md`](ios/SHARE_EXTENSION.md) 给 Runner 与 Share Extension 设置同一 Team，并启用 App Group  
2. App Group 固定为：`group.com.clipboard.online.clipboardClient`  
3. 用户自定义 `CUSTOM_GROUP_ID`（Build Setting）与 Entitlements 保持一致  
4. 构建：

```bash
flutter build ipa --release
```

侧载可用 AltStore / 开发者证书；未签名包不能直接当商店替代方案。

可选 CI Secrets（已签名 IPA）：`APPLE_CERTIFICATE`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_PROVISIONING_PROFILE`、`APPLE_TEAM_ID`。

## 依赖说明

- `receive_sharing_intent`：Android 分享入 + iOS Share Extension 桥接（SPM）  
- `share_plus`：分享出  
- `desktop_drop`：仅桌面拖放  


## 界面主题 · 媒体预览 · 图标（v0.1.4）

- **主题「纸与墨」**：`lib/theme/ink_theme.dart`（`ThemeData` + `InkTokens` 令牌，颜色与 Web `app.css` 一致：纸色背景、墨色 2px 描边、硬偏移阴影、朱红强调；标题衬线、代码等宽；深色模式跟随系统）与 `lib/widgets/ink.dart`（`InkCard / InkButton / InkChip / InkSegment / showInkSheet` 等）。
- **媒体预览**：条目卡片与详情页 `MediaPreviewScreen`：图片（缩略图 + 全屏缩放，带 Bearer 请求头）、视频 / 音频（`video_player`，播放 / 暂停 / 拖动进度 / 时长）、文本文件（前 400KB）；PDF 及其它类型提供「分享 / 保存」交给系统打开。
- **默认标签**：登录后默认进「我的私有」，并按用户记住上次选择。
- **App 图标**：主图 `assets/icon/icon_master_1024.png`（iOS 全出血无透明，macOS 版 `icon_macos_1024.png` 带留白圆角，Android 前景 `icon_android_foreground_1024.png`）。由 `python3 tools/gen_icons.py`（需 Pillow）一次生成 iOS `AppIcon.appiconset`、macOS `AppIcon.appiconset`、Android `mipmap-*` 及 `mipmap-anydpi-v26`（自适应图标，背景色 `#ECE6D9`）。

## macOS 菜单栏模式（v0.1.4）

macOS 版是「菜单栏应用」（`tray_manager` + `window_manager`）：

- 菜单栏出现单色模板图标（`assets/tray/tray_icon.png` 18px / `tray_icon@2x.png` 36px，自动适配深浅色菜单栏）。
- **左键点击图标**：在图标下方弹出 360×520 小窗：快传拖放区（把文件拖进小窗即可发送为私有）、最新条目（默认「我的私有」，可切「公共」；点击文本=复制，点击文件=下载并在访达显示）、底部按钮：主窗口 / 监听剪贴板 / 设置 / 退出。失焦自动隐藏，右上角图钉可固定。
- **右键点击图标**：菜单「打开主窗口 / 快传 / 监听剪贴板 / 设置 / 退出」。
- **关闭窗口 = 隐藏**，App 继续运行（WebSocket 与本地通知照常工作；窗口隐藏时新内容一定会弹通知）。
- 设置页（仅 macOS）：「在 Dock 显示图标」开关（关闭后仅菜单栏，运行时切换，无需 LSUIElement）与「开机自启」（`SMAppService`，macOS 13+；**未签名 App 可能被系统拒绝**，失败时会提示，可到「系统设置 → 通用 → 登录项」手动添加）。
- 限制：`tray_manager` 不支持把文件直接拖到菜单栏图标上，请先点开小窗再拖入。

## v0.1.5 说明

- **视频 / 音频播放**：先用 App 自带的带认证 HTTP 客户端把文件下载到临时缓存（`clip_media/<uuid>_<文件名>`，显示进度、可取消、大小一致时复用缓存），再从本地文件播放。这样不受 macOS/iOS ATS（局域网 `http://` 报 -1022）和 AVPlayer 无法带 Bearer 头的限制；macOS / iOS / Android 均走此路径。
- **ATS**：`Info.plist` 使用 `NSAllowsArbitraryLoads` + `NSAllowsArbitraryLoadsForMedia` + `NSAllowsArbitraryLoadsInWebContent`；已移除可能与之冲突的 `NSAllowsLocalNetworking`。
- **外观**：三端均为 `ThemeMode.system`，跟随系统浅色 / 深色，没有单独的主题设置项。


## v0.1.7 说明

- **快传入口**：首页直接显示「我的私有」；标签栏旁的「快传」按钮打开独立快传页（菜单栏浮窗保留自己的投放区）。
- **主题**：设置 → 外观主题（跟随系统 / 浅色 / 深色），保存在本地偏好（`theme_mode`）。
- **压缩包预览**：zip/jar/apk/tar/tar.gz/tar.bz2/tar.xz 条目点「预览」显示目录树（文件夹可折叠、大小、解压后总大小），数据来自服务端 `/api/items/<uuid>/archive`，不下载也不解压；7z/rar 暂不支持（会提示）。
- **ATS**：Info.plist 只保留 `NSAllowsArbitraryLoads`，见根目录 README。


## v0.1.8 说明

- 设置页显示「客户端版本 / 服务器版本」；请求遇到裸 404 会提示服务器版本过旧。
- 文本卡片「编辑」（仅自己的文本）；其它设备经 WebSocket 同步。
- iOS 分享扩展传输层改为 NWConnection，见 `ios/SHARE_EXTENSION.md`。


## v0.1.9 说明

- PDF 预览：`pdfx`（iOS / Android / macOS 原生渲染）。PDF 先用带认证的客户端下载到缓存，再本地渲染；失败时仍可用「分享 / 保存」。
- 设置页：服务器版本低于 App 时显示红色横幅 + 可复制的更新命令，并显示当前使用的服务器地址。
