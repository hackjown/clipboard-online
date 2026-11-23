import Flutter
import UIKit
import Vision
import ImageIO

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionOcrChannel") {
      setupVisionOcrChannel(registrar.messenger())
    }
  }

  /// 注册 iOS 视觉文字识别通道（VisionKit，免额外依赖/本地离线/极速安全）
  private func setupVisionOcrChannel(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "clipboard/vision_ocr", binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        if #available(iOS 13.0, *) {
          result(true)
        } else {
          result(false)
        }
      case "recognizeText":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "invalid_args", message: "Missing image path", details: nil))
          return
        }
        if #available(iOS 13.0, *) {
          guard let image = UIImage(contentsOfFile: path),
                let cgImage = image.cgImage else {
            result(FlutterError(code: "load_failed", message: "Failed to load image from \(path)", details: nil))
            return
          }
          let orientation: CGImagePropertyOrientation
          switch image.imageOrientation {
          case .up: orientation = .up
          case .upMirrored: orientation = .upMirrored
          case .down: orientation = .down
          case .downMirrored: orientation = .downMirrored
          case .left: orientation = .left
          case .leftMirrored: orientation = .leftMirrored
          case .right: orientation = .right
          case .rightMirrored: orientation = .rightMirrored
          @unknown default: orientation = .up
          }
          let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
          let request = VNRecognizeTextRequest { req, err in
            if let err = err {
              DispatchQueue.main.async {
                result(FlutterError(code: "ocr_error", message: err.localizedDescription, details: nil))
              }
              return
            }
            guard let observations = req.results as? [VNRecognizedTextObservation] else {
              DispatchQueue.main.async {
                result(["text": "", "lines": []])
              }
              return
            }
            var lines: [String] = []
            for obs in observations {
              if let candidate = obs.topCandidates(1).first {
                lines.append(candidate.string)
              }
            }
            let fullText = lines.joined(separator: "\n")
            DispatchQueue.main.async {
              result(["text": fullText, "lines": lines])
            }
          }
          request.recognitionLevel = .accurate
          if #available(iOS 14.0, *) {
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
          }
          request.usesLanguageCorrection = true
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              try requestHandler.perform([request])
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "perform_error", message: error.localizedDescription, details: nil))
              }
            }
          }
        } else {
          result(FlutterError(code: "unsupported", message: "iOS 13.0+ required for Vision OCR", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
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
