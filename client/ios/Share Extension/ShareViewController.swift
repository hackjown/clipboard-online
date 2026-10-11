import UIKit

/// 系统分享面板 → App Group → 打开宿主 App（剪贴板）。
/// 微信 / 相册 / 文件 / Safari 均走系统 Share Sheet，无需微信 SDK。
/// 基类 RSIShareViewController 为 receive_sharing_intent 的 vendored 副本（见同目录文件）。
class ShareViewController: RSIShareViewController {
  /// true：无 UI，写入 App Group 后直接跳回主 App，由主 App 确认「发送到我的设备」
  override func shouldAutoRedirect() -> Bool {
    return true
  }

  override var placeholder: String { "附加说明（可选）" }
  override var sendButtonTitle: String { "发送到剪贴板" }
}
