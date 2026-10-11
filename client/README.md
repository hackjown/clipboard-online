# 剪贴板 · Flutter 客户端（macOS + iOS）

对接 Clipboard Online 服务端 API（Bearer）。Android 目录仅为占位，本版不维护。

## 环境

- Flutter 3.x stable、Xcode 15+（Mac）
- 本机可先起服务端：`cd ../server && ./run.sh`（默认 `http://127.0.0.1:8099`）

```bash
flutter pub get
flutter analyze
flutter run -d macos
flutter run -d <ios-simulator-or-device>
```

登录页可改「服务器地址」（例如局域网 `http://192.168.x.x:8099` 或公网 HTTPS）。演示账号 `demo1` / `demo123`。

## 功能对照

| 功能 | 说明 |
| --- | --- |
| 登录/注册 | 存 Bearer 于 Keychain（secure storage） |
| 公共 / 我的私有 | Tab + 下拉刷新 + 搜索 |
| 添加文本 | 可见性 + 过期；公开前敏感检测 |
| 上传 | 文件选择 / 相册图片 |
| 剪贴板 | **Mac** 可选监听；**iOS** 仅手动「从剪贴板导入」 |
| 快传 | 拖放/选文件 → 私有上传；对端 WS 同步；系统「分享」+ Mac「在访达中显示」 |
| 分享 | 生成链接 + 二维码；可撤销 |
| 收藏 / 置顶 | 调对应 API |
| 实时 | WebSocket，失败则 5s 轮询 |
| Deep link | `clipboard://s/<token>` → 分享预览页 |


## 快传（双向）

同一账号下，Mac ↔ 手机通过 **私有区 + WebSocket** 互传文件：

1. **Mac → 手机**  
   - 主页顶部「快传」区：把文件 **拖进虚线框**，或点「选文件 / 选图片 / 粘贴」  
   - 点 **「发送到我的设备」** → 上传为 **私有**（不过期）  
   - Toast：`已发送，其他设备将同步`  
   - 手机端列表经 WebSocket（或轮询）刷新；点条目 **「分享」** 可走系统分享面板（微信等）

2. **手机 → Mac**  
   - 同样在「快传」里选文件 / 选图片 / 从剪贴板导入，再点发送  
   - （完整「从微信分享到 App」需 iOS Share Extension，本版未内置；请先用选文件或粘贴）  
   - Mac 端实时出现后：可 **打开**、**在访达中显示**（下载到临时目录后 `open -R`）、或再 **分享**

快传路径 **始终私有**，与公共区无关。现有登录、列表、收藏/置顶、链接二维码分享不受影响。

## macOS 构建

```bash
flutter config --enable-macos-desktop
flutter build macos --release
# 产物：build/macos/Build/Products/Release/clipboard_client.app
```

首次访问剪贴板监听时，若系统拦截，请到 **系统设置 → 隐私与安全性** 中允许本 App（辅助功能 / 自动化等，视 macOS 版本而定）。

## iOS 构建与侧载

### 未签名（CI 同款）

```bash
flutter build ios --release --no-codesign
# build/ios/iphoneos/Runner.app
```

### 正式 IPA（需 Apple 开发者账号）

1. 用 Xcode 打开 `ios/Runner.xcworkspace`
2. Signing & Capabilities 选择你的 Team，改 Bundle ID
3. 构建：

```bash
flutter build ipa --release
# build/ios/ipa/*.ipa
```

### 侧载说明（简述）

- **AltStore / SideStore**：自签 7 天（免费 Apple ID）或配合开发者证书；需电脑刷新或配对。
- **TrollStore**（特定系统版本）：持久安装，仅限支持设备，风险自担。
- 企业签 / ad-hoc：需合法证书与设备 UDID 列表。

**请勿**把未签名包直接当作 App Store 替代方案宣传。iOS **无法**在后台持续读取剪贴板。

## 签名相关 CI Secrets（可选）

若要在 GitHub Actions 产出**已签名** IPA，需自行扩展 workflow 并配置例如：

- `APPLE_CERTIFICATE` / `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE`
- `APPLE_TEAM_ID`

当前 `flutter.yml` 只上传 **macOS zip** 与 **iOS 未签名 zip** 制品。

## Android

`android/` 由模板生成，**本版本不交付功能与文档**；见仓库根 README。
