# iOS Share Extension（已嵌入工程）

`Runner.xcodeproj` 已包含 **Share Extension** 目标（`client/ios/Share Extension/`），并已加入 Runner 的
**Embed Foundation Extensions** 阶段与目标依赖。`flutter build ios --release --no-codesign` 产出的 IPA
内含 `Payload/Runner.app/PlugIns/ShareExtension.appex`（CI 会校验，缺失则失败）。

微信 / 相册 / 文件 / Safari 通过 **系统分享面板**调用该扩展，**不需要**微信 SDK。

## 结构

| 项 | 值 |
| --- | --- |
| 扩展 Bundle ID | `com.clipboard.online.clipboardClient.ShareExtension` |
| 宿主 Bundle ID | `com.clipboard.online.clipboardClient` |
| App Group | `group.com.clipboard.online.clipboardClient`（Runner 与扩展的 entitlements + Build Setting `CUSTOM_GROUP_ID`） |
| 激活规则 | 文本、网页 URL、图片(≤100)、视频(≤20)、文件(≤20) |
| 实现 | `ShareViewController` 继承 vendored 的 `RSIShareViewController`（来自 `receive_sharing_intent` 1.9.0，Apache-2.0，见 `LICENSE-receive_sharing_intent.txt`）；因此扩展**无需**再链接 SPM 包 |
| 行为 | 写入 App Group → 通过 `ShareMedia-<bundle id>://` 唤起主 App → 主 App 弹「发送到我的设备？」确认后 **私有上传** |

## 你需要做的（签名）

未签名 IPA 只是「结构完整」，要在真机使用还需重签：

1. 有 Apple Developer 账号，Xcode 打开 `ios/Runner.xcworkspace`，**Runner** 与 **Share Extension** 两个 Target 都选择同一 **Team**（在 Signing & Capabilities 设置 `DEVELOPMENT_TEAM`）。
2. 两个 Target 都启用 **App Groups**，勾选 `group.com.clipboard.online.clipboardClient`（需要创建该 Group ID；免费 Apple ID 不支持 App Groups）。
3. 如需改 Bundle ID：同时改两个 Target，并保持扩展 ID = 宿主 ID + `.ShareExtension`，并把 `CUSTOM_GROUP_ID` 改成你自己的 Group。
4. 真机运行一次宿主 App，再到微信等点分享，面板中应出现 **「剪贴板」**。

侧载工具（AltStore / Sideloadly）重签时一般会连同 `.appex` 一起重签并改写 Bundle ID / App Group；
若免费账号无法使用 App Group，扩展→主 App 的数据交接会失效（主 App 内的快传不受影响）。

## 重新生成工程目标（维护者）

目标由脚本一次性注入 `project.pbxproj`（幂等）。如不慎破坏，可用 Xcode 手动 Add Target：Share Extension，
把 `Share Extension/` 下的 4 个 `.swift` 加入其 Sources，Info.plist / entitlements 指向本目录，
并把 `.appex` 加到 Runner 的 Embed Foundation Extensions（放在 Thin Binary 之前，避免构建循环）。

## 排错

| 现象 | 处理 |
| --- | --- |
| 分享面板没有本 App | 未签名/未装到真机；或 Team / App Group 不一致 |
| 主 App 收不到分享 | 检查 URL Scheme `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` 与 `AppGroupId`、`CUSTOM_GROUP_ID` |
| 构建循环 (cycle) | Embed Foundation Extensions 必须在 Thin Binary 之前 |
