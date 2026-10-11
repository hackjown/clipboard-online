# iOS Share Extension 签名与接入（必做一次）

本仓库已包含 `ios/Share Extension/` 源码（基于 `receive_sharing_intent` 的 `RSIShareViewController`）。
因 Linux CI / 无图形 Xcode 无法替你生成完整的 `.appex` Target，请在 **Mac + Xcode** 上按下列步骤把 Target 挂进工程（约 5 分钟）。

微信等 App **通过系统分享面板**调用 Share Extension，**不需要**微信 OpenSDK。

## 前置

1. Apple Developer 账号，记下 **Team ID**
2. 打开 `ios/Runner.xcworkspace`（或 `.xcodeproj`）
3. Flutter 已启用 SPM：`flutter config --enable-swift-package-manager`

## 步骤

1. **File → New → Target → Share Extension**  
   - Product Name: `Share Extension`  
   - Language: Swift  
   - 若 Xcode 生成了默认 `ShareViewController.swift`，**删掉**并用仓库里 `ios/Share Extension/` 目录覆盖

2. **两处 Signing & Capabilities**（Runner + Share Extension）  
   - 选择同一 **Team**  
   - 添加 **App Groups**，勾选容器：  
     `group.com.clipboard.online.clipboardClient`  
   - 若容器不存在，点 `+` 创建（需付费开发者账号）

3. **Build Settings → 自定义**（两个 Target 都要）  
   - `CUSTOM_GROUP_ID` = `group.com.clipboard.online.clipboardClient`

4. **Share Extension → General → Frameworks and Libraries**  
   - 添加 Swift Package 产品：`receive-sharing-intent`（来自 `receive_sharing_intent`）

5. **Runner Target**  
   - `CODE_SIGN_ENTITLEMENTS` = `Runner/Runner.entitlements`（仓库已写好）  
   - Info.plist 已含 `AppGroupId`、`ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` URL Scheme

6. **Embed**  
   - Runner → Build Phases → Embed Foundation Extensions：包含 `Share Extension.appex`  
   - 将该 Embed 阶段移到 **Thin Binary 之上**（插件 README 要求）

7. Bundle ID 建议  
   - Runner: `com.clipboard.online.clipboardClient`  
   - Share Extension: `com.clipboard.online.clipboardClient.ShareExtension`

8. 真机运行一次宿主 App，再到微信 / 照片 / 文件 / Safari 点「分享」，面板中应出现 **「剪贴板」**。

## 行为

Extension 默认 `shouldAutoRedirect() == true`：写入 App Group 后打开主 App；主 App 弹出「发送到我的设备？」确认后 **私有上传**。

## 排错

| 现象 | 处理 |
| --- | --- |
| No such module `receive_sharing_intent` | Share Extension 未链接 SPM 产品；或 Embed 顺序不对 |
| 分享面板没有本 App | App Group / 签名 Team 不一致，或未装到真机 |
| 主 App 收不到 | 检查 `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` 与 AppGroupId |
