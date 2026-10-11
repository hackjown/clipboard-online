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

登录页可改「服务器地址」。演示账号 `demo1` / `demo123`。

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

首次需在 Xcode 完成 Share Extension 签名，详见 [`ios/SHARE_EXTENSION.md`](ios/SHARE_EXTENSION.md)。

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
```

### 正式签名 + Share Extension

1. 按 [`ios/SHARE_EXTENSION.md`](ios/SHARE_EXTENSION.md) 添加 Share Extension Target、App Group、Team  
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
