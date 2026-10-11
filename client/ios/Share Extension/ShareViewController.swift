import receive_sharing_intent

/// 系统分享面板 → App Group → 打开宿主 App（剪贴板）
/// 微信 / 相册 / 文件 / Safari 均走系统 Share Sheet，无需微信 SDK。
class ShareViewController: RSIShareViewController {
  /// true：无 UI，直接写入 App Group 并跳回主 App，适合「快传」
  override func shouldAutoRedirect() -> Bool {
    return true
  }

  override var placeholder: String { "附加说明（可选）" }
  override var sendButtonTitle: String { "发送到剪贴板" }
}
