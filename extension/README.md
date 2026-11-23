# Clipboard Vault 浏览器扩展（Chrome / Edge）

基于 **Manifest V3**，同一套代码支持 **Google Chrome、Microsoft Edge、Brave、Arc、Vivaldi** 等 Chromium 浏览器，直接对接你的自建 Clipboard Online 密码保险箱（端到端加密，与 Web / Mac / iOS / Android 实时互通）。

## 功能

- **零知识端到端加密**：本地 `WebCrypto PBKDF2-HMAC-SHA256 + AES-256-GCM` 加解密，密钥仅保存在 `chrome.storage.session` 内存中（关闭浏览器即清除，15 分钟无操作自动锁定）。
- **智能自动填充（类 1Password）**：
  - 聚焦登录输入框时弹出悬浮 🔑 菜单（Shadow DOM 样式隔离），一键填入账号、密码与 2FA 验证码（兼容 React / Vue / Angular）。
  - 工具栏角标实时显示当前网站匹配的账号数；快捷键 `Alt+Shift+P`（Mac 为 `Command+Shift+P`）快速唤出。
- **自动检测新登录**：在网站提交新账号密码后，角标提示 `+`，点击即可一键加密保存到保险箱。
- **内置 2FA & 强密码生成器**：实时 30 秒倒计时 TOTP 验证码，随机字符 / 易记词组生成并直接填入页面密码框。
- **支持扫码配对码登录**：直接粘贴网页端「账号菜单 → 扫码配对客户端」的 `clipboard://pair?...` 链接即可完成连接。

## 安装步骤（30 秒）

1. 从 GitHub Releases 下载 `clipboard-vault-extension.zip` 并解压（或直接使用本仓库的 `extension/` 目录）。
2. 在浏览器地址栏打开：
   - **Edge**：`edge://extensions`
   - **Chrome**：`chrome://extensions`
3. 打开右上角「**开发人员模式**」→ 点击「**加载解压缩的扩展**」→ 选择解压后的 `extension` 文件夹即可使用。
