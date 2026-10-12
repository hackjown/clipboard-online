import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static let groupId = "group.com.clipboard.online.clipboardClient"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareConfigChannel") {
      setupShareConfigChannel(registrar.messenger())
    }
  }

  /// 把服务器地址 / 令牌写入 App Group 容器，供分享扩展直接上传；并读取扩展写的日志。
  /// App Group 不可用（免费账号重签 / 未带 entitlement）时返回 group=false，不会崩溃。
  private func setupShareConfigChannel(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "clipboard/share_config", binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppDelegate.groupId)
      switch call.method {
      case "status":
        result(["group": container != nil, "groupId": AppDelegate.groupId])
      case "sync":
        guard let c = container else { result(["group": false]); return }
        let args = call.arguments as? [String: Any] ?? [:]
        let base = args["base"] as? String ?? ""
        let token = args["token"] as? String ?? ""
        let url = c.appendingPathComponent("share_config.json")
        if base.isEmpty || token.isEmpty {
          try? FileManager.default.removeItem(at: url)
          result(["group": true, "written": false])
          return
        }
        do {
          let data = try JSONSerialization.data(withJSONObject: ["base": base, "token": token])
          try data.write(to: url, options: .atomic)
          result(["group": true, "written": true])
        } catch {
          result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
        }
      case "setExpiry":
        // 分享扩展上传时用的默认有效期（秒；0 = 永不过期），扩展 UI 里不另设选择器
        guard let c = container else { result(["group": false]); return }
        let args = call.arguments as? [String: Any] ?? [:]
        let sec = (args["expires_in"] as? NSNumber)?.intValue ?? 0
        do {
          let data = try JSONSerialization.data(withJSONObject: ["expires_in": sec])
          try data.write(to: c.appendingPathComponent("share_prefs.json"), options: .atomic)
          result(["group": true, "written": true])
        } catch {
          result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
        }
      case "readLog":
        guard let c = container else { result(""); return }
        result((try? String(contentsOf: c.appendingPathComponent("share_log.txt"), encoding: .utf8)) ?? "")
      case "clearLog":
        if let c = container { try? FileManager.default.removeItem(at: c.appendingPathComponent("share_log.txt")) }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
