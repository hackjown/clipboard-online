import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 开机自启（macOS 13+ SMAppService；未签名 / 旧系统会返回错误，由 Dart 端提示）
    let ch = FlutterMethodChannel(
      name: "clipboard/login_item",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    ch.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(FlutterError(code: "unsupported", message: "需要 macOS 13 或更高版本", details: nil))
        return
      }
      switch call.method {
      case "isEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "setEnabled":
        let on = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        do {
          if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
          result(SMAppService.mainApp.status == .enabled)
        } catch {
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
