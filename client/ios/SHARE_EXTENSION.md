# iOS Share Extension（v0.1.6 重写：扩展直接上传）

`Runner.xcodeproj` 含 **Share Extension** 目标（`client/ios/Share Extension/`），已加入 Runner 的 *Embed Foundation Extensions* 与目标依赖。
IPA 内含 `Payload/Runner.app/PlugIns/ShareExtension.appex`（CI 校验，缺失则失败）。微信 / 相册 / 文件 / Safari 走**系统分享面板**，不需要微信 SDK。

## 为什么重写

旧版（v0.1.3–v0.1.5）沿用 `receive_sharing_intent` 的流程：扩展把文件写进 **App Group 容器**，再通过 `ShareMedia-<bundle id>://` 自定义 URL 跳回主 App。用户在 TrollStore 侧载后：分享面板里能看到「剪贴板」，点了却没反应。

**能从代码确认的根因**（没有真机，无法抓崩溃日志）：

1. 旧基类里有 `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)!`（强制解包）。App Group 不可用时返回 `nil` → 扩展**直接崩溃**，表现就是「点了没反应」。
2. **未签名 IPA 里的二进制不带任何 entitlements**。Xcode 的 `.entitlements` 文件只在**签名时**才被写进二进制；`--no-codesign` 构建不会。TrollStore 不会替我们补 entitlements，只会保留二进制里已有的 → Runner 和扩展都没有 `application-groups`，所以容器拿不到（上面的 nil）。
3. 旧的「跳回主 App」用的是向响应链发 `openURL:` 的私有写法，在较新的 iOS 上对扩展常常失效；且 URL scheme 里含 Bundle ID，重签改写 Bundle ID 后会对不上。
4. 扩展的 `Info.plist` 没有 ATS 设置：局域网 `http://` 服务器会被系统拒绝（与主 App 的 -1022 同类）。

**仅是推测、没有设备验证的**：iOS 版本差异导致的 `openURL:` 失效程度；免费账号重签后具体改写了哪些字段。

## 现在的做法

- 扩展自己读取分享内容（文件 / 图片 / 视频 / 文本 / 链接，含微信用的 `public.data`），**直接用 Bearer 令牌上传到服务器的私有区**，不再依赖「跳回主 App」。
- 扩展里有一个小面板：进度条、「已发送，其他设备将同步」，失败时显示**精确错误**（HTTP 状态码 + 服务器返回 + 请求 URL），可重试。
- 不会再强制解包 App Group：不可用时自动降级。
- 令牌来源（按顺序）：
  1. **App Group** 里的 `share_config.json`（主 App 登录 / 改服务器地址 / 退出时自动写入）；
  2. 扩展**自己沙盒**里保存的登录信息 —— App Group 不可用时，第一次分享会在面板里让你填「服务器地址 / 用户名 / 密码」登录一次，之后直接上传。
- 日志：`share_log.txt`。App Group 可用时，主 App「设置 → 分享扩展」能看到并清除；不可用时日志只在扩展沙盒里（看不到），错误会直接显示在分享面板上。
- 扩展 `Info.plist` 已加 `NSAppTransportSecurity`（允许 http 局域网）、`NSLocalNetworkUsageDescription`、`NSExtensionActivationSupportsAttachmentsWithMaxCount` 等规则。
- 旧的 vendored `RSI*.swift` 文件仍在目标里编译，但 `ShareViewController` 不再继承它们，运行时不会用到。

## 哪种安装方式能用什么

| 安装方式 | App Group | 分享扩展 |
| --- | --- | --- |
| **TrollStore + `clipboard-ios-trollstore.ipa`** | CI 里用 ldid 给 Runner 和扩展写入 `com.apple.security.application-groups`（CI 日志里会 `ldid -e` 打印并校验） | 可用；直接使用主 App 的登录信息；设置页可看日志 |
| AltStore / Sideloadly + `clipboard-ios-unsigned.ipa`（付费开发者账号） | 签名时带上 App Groups 能力，一般可用 | 同上 |
| AltStore / Sideloadly + 免费 Apple ID | **不可用**（免费账号不能用 App Groups，且重签会改写 Bundle ID） | 可用，但**首次要在分享面板里登录一次**；主 App 看不到扩展日志 |

> 以上「可用」均指在代码与 CI 层面做了对应处理；**没有真机验证**。TrollStore 的 `application-groups` 是否被系统实际授予，取决于你的 TrollStore / iOS 版本。

## 自己用 Xcode 签名

1. Xcode 打开 `ios/Runner.xcworkspace`，**Runner** 与 **Share Extension** 都选同一 Team（`DEVELOPMENT_TEAM`）。
2. 两个 Target 都启用 **App Groups**：`group.com.clipboard.online.clipboardClient`（需付费账号）。
3. 改 Bundle ID 时：扩展 ID = 宿主 ID + `.ShareExtension`；把 `CUSTOM_GROUP_ID`、扩展 `Info.plist` 的 `AppGroupId`、两份 entitlements、`AppDelegate.swift` 里的 `groupId` 一起改成你自己的 Group。

## 结构

| 项 | 值 |
| --- | --- |
| 扩展 Bundle ID | `com.clipboard.online.clipboardClient.ShareExtension` |
| 宿主 Bundle ID | `com.clipboard.online.clipboardClient` |
| App Group | `group.com.clipboard.online.clipboardClient` |
| 激活规则 | 文本、网页 URL、图片(≤100)、视频(≤20)、文件与通用附件(≤20) |
| 主类 | `ShareViewController`（`@objc(ShareViewController)`，纯 UIKit） |
| 主 App ↔ 扩展 | `AppDelegate.swift` 的 MethodChannel `clipboard/share_config`（`sync / status / readLog / clearLog`） |
