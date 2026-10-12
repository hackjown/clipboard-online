import UIKit
import UniformTypeIdentifiers
import Network

// 分享扩展 v2：不再依赖「App Group + 跳回主 App」。
// 扩展自己读取分享内容，并直接用 Bearer 令牌上传到服务器（私有区），界面里显示进度 / 结果 / 精确错误文本。
//
// 令牌来源（按顺序）：
//  1) App Group 容器里的 share_config.json（主 App 登录后写入；仅在 App Group 可用时存在 —— 付费开发者账号签名）；
//  2) 扩展自己沙盒里保存的登录信息（免费 Apple ID / 重签名导致 App Group 不可用时：首次在分享面板里登录一次即可）。
// 日志写入 share_log.txt（App Group 可用时主 App「设置」里可见；否则只留在扩展沙盒）。

private enum ShareLog {
    static var fileURL: URL? {
        if let g = ShareStore.groupContainer { return g.appendingPathComponent("share_log.txt") }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("share_log.txt")
    }

    static func write(_ s: String) {
        guard let url = fileURL else { return }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8) ?? Data())
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        // 日志过大时截断
        if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attr[.size] as? NSNumber, size.intValue > 64 * 1024 {
            try? "(log truncated)\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private enum ShareStore {
    static let groupId: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String) ?? "group.com.clipboard.online.clipboardClient"

    /// App Group 不可用（免费账号 / 重签）时返回 nil —— 绝不强制解包
    static var groupContainer: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    struct Config {
        var base: String
        var token: String
    }

    static func load() -> (Config, String)? {
        if let g = groupContainer,
           let data = try? Data(contentsOf: g.appendingPathComponent("share_config.json")),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let b = obj["base"] as? String, let t = obj["token"] as? String, !b.isEmpty, !t.isEmpty {
            return (Config(base: b, token: t), "App Group")
        }
        let d = UserDefaults.standard
        if let b = d.string(forKey: "ext_base"), let t = d.string(forKey: "ext_token"), !b.isEmpty, !t.isEmpty {
            return (Config(base: b, token: t), "扩展本地登录")
        }
        return nil
    }

    /// App 设置里选的「分享扩展默认有效期」（秒，0 = 永不过期）；App Group 不可用时为 0
    static var expiresIn: Int {
        guard let g = groupContainer,
              let data = try? Data(contentsOf: g.appendingPathComponent("share_prefs.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let n = obj["expires_in"] as? NSNumber else { return 0 }
        return max(0, n.intValue)
    }

    static func saveLocal(_ c: Config) {
        let d = UserDefaults.standard
        d.set(c.base, forKey: "ext_base")
        d.set(c.token, forKey: "ext_token")
    }

    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: "ext_token")
        if let g = groupContainer {
            try? FileManager.default.removeItem(at: g.appendingPathComponent("share_config.json"))
        }
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}


// MARK: - 极简 HTTP/1.1 客户端（Network.framework / NWConnection）
//
// 为什么不用 URLSession：URLSession / CFNetwork 会对明文 http 执行 ATS（App Transport Security）。
// 在 TrollStore / 侧载环境里，分享扩展进程的 ATS 配置是否生效无法在真机之外验证；
// NWConnection 是纯 TCP/TLS，不经过 CFNetwork，因此 ATS 根本不会介入。
// 功能：JSON / multipart 请求体（文件分块流式读取）、进度、取消、超时、Content-Length 与 chunked 响应、不跟随重定向。

private enum HTTPSegment {
    case data(Data)
    case file(URL)
}

private struct MiniHTTPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct MiniHTTPResponse {
    var status: Int
    var reason: String
    var headers: [String: String]   // 键小写
    var body: Data
}

private func describeNWError(_ e: NWError) -> String {
    switch e {
    case .posix(let c):
        return "系统错误 \(c.rawValue)（\(String(cString: strerror(c.rawValue)))）"
    case .dns(let c):
        return "DNS 解析失败（\(c)）"
    case .tls(let s):
        return "TLS 错误（OSStatus \(s)）"
    default:
        return "\(e)"
    }
}

private final class MiniHTTPClient {
    private let url: URL
    private let method: String
    private let headers: [String: String]
    private let segments: [HTTPSegment]
    private let connectTimeout: TimeInterval
    private let idleTimeout: TimeInterval
    private let onProgress: ((Int64, Int64) -> Void)?
    private var completion: ((Result<MiniHTTPResponse, MiniHTTPError>) -> Void)?

    private let q = DispatchQueue(label: "clip.minihttp")
    private var conn: NWConnection?
    private var timer: DispatchWorkItem?
    private var finished = false
    private var connected = false
    private var lastWaiting: String?

    // 发送状态
    private var segIndex = 0
    private var segOffset = 0
    private var fileHandle: FileHandle?
    private var totalBody: Int64 = 0
    private var sentBody: Int64 = 0
    private var sendError: String?
    private var sendDone = false

    // 接收状态
    private var buf = Data()
    private var headParsed = false
    private var status = 0
    private var reason = ""
    private var respHeaders: [String: String] = [:]
    private var contentLength: Int?
    private var chunked = false
    private var bodyOut = Data()
    private let maxBody = 2 * 1024 * 1024

    init(url: URL, method: String, headers: [String: String], body: [HTTPSegment],
         connectTimeout: TimeInterval = 15, idleTimeout: TimeInterval = 60,
         onProgress: ((Int64, Int64) -> Void)? = nil,
         completion: @escaping (Result<MiniHTTPResponse, MiniHTTPError>) -> Void) {
        self.url = url
        self.method = method
        self.headers = headers
        self.segments = body
        self.connectTimeout = connectTimeout
        self.idleTimeout = idleTimeout
        self.onProgress = onProgress
        self.completion = completion
        var n: Int64 = 0
        for s in body {
            switch s {
            case .data(let d): n += Int64(d.count)
            case .file(let u):
                n += (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        self.totalBody = n
    }

    var transportName: String { url.scheme?.lowercased() == "https" ? "NWConnection(TCP+TLS)" : "NWConnection(TCP)" }

    func start() {
        q.async { self.begin() }
    }

    func cancel() {
        q.async { self.finish(.failure(MiniHTTPError(message: "已取消"))) }
    }

    private func begin() {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            finish(.failure(MiniHTTPError(message: "服务器地址无效：\(url.absoluteString)")))
            return
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port)), port > 0, port < 65536 else {
            finish(.failure(MiniHTTPError(message: "端口无效：\(port)")))
            return
        }
        let params: NWParameters = scheme == "https" ? .tls : .tcp
        let c = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        conn = c
        armTimer(connectTimeout, "连接超时（\(Int(connectTimeout)) 秒未能连上 \(host):\(port)）")
        c.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            switch st {
            case .ready:
                if !self.connected {
                    self.connected = true
                    self.armTimer(self.idleTimeout, "等待服务器响应超时（\(Int(self.idleTimeout)) 秒无数据）")
                    self.receiveLoop()
                    self.sendHead()
                }
            case .waiting(let err):
                // 无网络 / 路由不可达 / DNS 暂时失败：保持等待，由超时给出最终原因
                self.lastWaiting = describeNWError(err)
            case .failed(let err):
                self.finish(.failure(MiniHTTPError(message: "连接失败：\(describeNWError(err))（\(host):\(port)）")))
            case .cancelled:
                break
            default:
                break
            }
        }
        c.start(queue: q)
    }

    private func armTimer(_ secs: TimeInterval, _ msg: String) {
        timer?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, !self.finished else { return }
            var m = msg
            if !self.connected, let w = self.lastWaiting { m += "；最近状态：\(w)" }
            self.finish(.failure(MiniHTTPError(message: m)))
        }
        timer = w
        q.asyncAfter(deadline: .now() + secs, execute: w)
    }

    private func touch() {
        if connected && !finished { armTimer(idleTimeout, "等待服务器响应超时（\(Int(idleTimeout)) 秒无数据）") }
    }

    // MARK: 发送
    private func sendHead() {
        var path = url.path.isEmpty ? "/" : url.path
        if let qs = url.query { path += "?" + qs }
        let scheme = url.scheme?.lowercased() ?? "http"
        let defPort = scheme == "https" ? 443 : 80
        var hostHeader = url.host ?? ""
        if hostHeader.contains(":") { hostHeader = "[" + hostHeader + "]" }
        if let p = url.port, p != defPort { hostHeader += ":\(p)" }
        var h = "\(method) \(path) HTTP/1.1\r\nHost: \(hostHeader)\r\nConnection: close\r\nAccept: application/json\r\nUser-Agent: ClipboardShareExt\r\n"
        for (k, v) in headers { h += "\(k): \(v)\r\n" }
        h += "Content-Length: \(totalBody)\r\n\r\n"
        conn?.send(content: h.data(using: .utf8), completion: .contentProcessed { [weak self] err in
            guard let self = self else { return }
            if let err = err {
                self.sendError = "发送请求头失败：\(describeNWError(err))"
                return
            }
            self.pump()
        })
    }

    private func nextChunk() -> Data? {
        let maxLen = 256 * 1024
        while segIndex < segments.count {
            switch segments[segIndex] {
            case .data(let d):
                if segOffset >= d.count { segIndex += 1; segOffset = 0; continue }
                let end = min(d.count, segOffset + maxLen)
                let out = d.subdata(in: segOffset..<end)
                segOffset = end
                return out
            case .file(let u):
                if fileHandle == nil { fileHandle = try? FileHandle(forReadingFrom: u) }
                guard let h = fileHandle else {
                    sendError = "无法读取文件：\(u.lastPathComponent)"
                    return nil
                }
                let d = h.readData(ofLength: maxLen)
                if d.isEmpty {
                    try? h.close(); fileHandle = nil
                    segIndex += 1; segOffset = 0
                    continue
                }
                return d
            }
        }
        return nil
    }

    private func pump() {
        if finished || sendError != nil { return }
        guard let chunk = nextChunk() else {
            sendDone = true
            return
        }
        conn?.send(content: chunk, completion: .contentProcessed { [weak self] err in
            guard let self = self, !self.finished else { return }
            if let err = err {
                // 服务器可能已提前回复并关闭（如 413）：先记下，等接收端给出真正的响应
                self.sendError = "上传中断：\(describeNWError(err))"
                return
            }
            self.sentBody += Int64(chunk.count)
            self.touch()
            if let cb = self.onProgress, self.totalBody > 0 {
                let s = self.sentBody, t = self.totalBody
                DispatchQueue.main.async { cb(s, t) }
            }
            self.pump()
        })
    }

    // MARK: 接收
    private func receiveLoop() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, err in
            guard let self = self, !self.finished else { return }
            if let d = data, !d.isEmpty {
                self.buf.append(d)
                self.touch()
                if let r = self.parse() {
                    self.finish(.success(r))
                    return
                }
            }
            if let err = err {
                if let r = self.parseAtEOF() { self.finish(.success(r)); return }
                let extra = self.sendError.map { "；\($0)" } ?? ""
                self.finish(.failure(MiniHTTPError(message: "读取响应失败：\(describeNWError(err))\(extra)")))
                return
            }
            if isComplete {
                if let r = self.parseAtEOF() { self.finish(.success(r)); return }
                let extra = self.sendError.map { "；\($0)" } ?? ""
                let why = self.headParsed ? "响应不完整" : "服务器未返回任何 HTTP 响应"
                self.finish(.failure(MiniHTTPError(message: "连接被服务器关闭：\(why)\(extra)")))
                return
            }
            self.receiveLoop()
        }
    }

    /// 解析缓冲区；响应完整时返回
    private func parse() -> MiniHTTPResponse? {
        while true {
            if !headParsed {
                guard let r = buf.range(of: Data("\r\n\r\n".utf8)) else {
                    if buf.count > 64 * 1024 { return MiniHTTPResponse(status: 0, reason: "响应头过大", headers: [:], body: Data()) }
                    return nil
                }
                let head = String(data: buf.subdata(in: 0..<r.lowerBound), encoding: .isoLatin1) ?? ""
                buf.removeSubrange(0..<r.upperBound)
                var lines = head.components(separatedBy: "\r\n")
                let first = lines.removeFirst()
                let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]) else {
                    return MiniHTTPResponse(status: 0, reason: "非法状态行：\(first.prefix(80))", headers: [:], body: Data())
                }
                status = code
                reason = parts.count > 2 ? String(parts[2]) : ""
                respHeaders = [:]
                for l in lines {
                    guard let i = l.firstIndex(of: ":") else { continue }
                    let k = l[l.startIndex..<i].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    respHeaders[k] = v
                }
                if code >= 100 && code < 200 { continue }   // 1xx 临时响应：忽略，继续读真正的响应头
                headParsed = true
                chunked = (respHeaders["transfer-encoding"] ?? "").lowercased().contains("chunked")
                contentLength = respHeaders["content-length"].flatMap { Int($0) }
                if method == "HEAD" || code == 204 || code == 304 { contentLength = 0; chunked = false }
            }
            break
        }
        if chunked {
            while true {
                guard let le = buf.range(of: Data("\r\n".utf8)) else { return nil }
                let line = String(data: buf.subdata(in: 0..<le.lowerBound), encoding: .isoLatin1) ?? ""
                let hex = line.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard let size = Int(hex, radix: 16), size >= 0 else {
                    return MiniHTTPResponse(status: 0, reason: "非法 chunk 长度：\(hex.prefix(20))", headers: [:], body: Data())
                }
                if size == 0 { return makeResponse() }
                let need = le.upperBound + size + 2
                if buf.count < need { return nil }
                bodyOut.append(buf.subdata(in: le.upperBound..<(le.upperBound + size)))
                buf.removeSubrange(0..<need)
                if bodyOut.count > maxBody { return makeResponse() }
            }
        }
        if let cl = contentLength {
            if buf.count >= cl || cl > maxBody && buf.count >= maxBody {
                bodyOut = buf.prefix(min(cl, maxBody))
                return makeResponse()
            }
            return nil
        }
        return nil   // 无长度：读到连接关闭
    }

    private func parseAtEOF() -> MiniHTTPResponse? {
        guard headParsed else { return nil }
        if chunked { return nil }
        if contentLength == nil {
            bodyOut = buf.prefix(maxBody)
            return makeResponse()
        }
        return nil
    }

    private func makeResponse() -> MiniHTTPResponse {
        return MiniHTTPResponse(status: status, reason: reason, headers: respHeaders, body: bodyOut)
    }

    private func finish(_ r: Result<MiniHTTPResponse, MiniHTTPError>) {
        if finished { return }
        finished = true
        timer?.cancel()
        timer = nil
        conn?.stateUpdateHandler = nil
        conn?.cancel()
        conn = nil
        try? fileHandle?.close()
        fileHandle = nil
        let cb = completion
        completion = nil
        DispatchQueue.main.async { cb?(r) }
    }
}

private enum Payload {
    case file(url: URL, name: String, mime: String)
    case text(String)

    var label: String {
        switch self {
        case .file(_, let n, _): return n
        case .text(let t): return "文本（\(t.count) 字）"
        }
    }
}

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    // UI
    private let card = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let form = UIStackView()
    private let baseField = UITextField()
    private let userField = UITextField()
    private let passField = UITextField()
    private let primary = UIButton(type: .system)
    private let secondary = UIButton(type: .system)

    private var payloads: [Payload] = []
    private var config: ShareStore.Config?
    private var currentClient: MiniHTTPClient?   // 传输层：NWConnection（不经过 URLSession / ATS）
    private var totalBytes: Int64 = 0
    private var doneBytes: Int64 = 0
    private var finished = false
    private let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("share_" + UUID().uuidString, isDirectory: true)

    // MARK: 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        buildUI()
        ShareLog.write("启动 " + diagnostics())
        setStatus("正在读取分享内容…", busy: true)
        collect { [weak self] items in
            guard let self = self else { return }
            self.payloads = items
            ShareLog.write("读取到 \(items.count) 项: " + items.map { $0.label }.joined(separator: ", "))
            if items.isEmpty {
                self.fail("没有读取到可发送的内容（该应用分享的类型暂不支持，或读取失败）。")
                return
            }
            self.proceed()
        }
    }

    deinit { try? FileManager.default.removeItem(at: workDir) }

    // MARK: UI
    private func buildUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        card.backgroundColor = UIColor(red: 0.98, green: 0.965, blue: 0.925, alpha: 1)
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 2
        card.layer.borderColor = UIColor(red: 0.09, green: 0.08, blue: 0.06, alpha: 1).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let ink = UIColor(red: 0.09, green: 0.08, blue: 0.06, alpha: 1)
        titleLabel.text = "发送到剪贴板（私有）"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = ink
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = ink
        statusLabel.numberOfLines = 0
        progress.progressTintColor = UIColor(red: 1, green: 0.31, blue: 0.17, alpha: 1)
        progress.isHidden = true
        spinner.hidesWhenStopped = true

        for (f, ph) in [(baseField, "服务器地址，如 http://192.168.1.8:8100"), (userField, "用户名"), (passField, "密码")] {
            f.placeholder = ph
            f.borderStyle = .roundedRect
            f.autocorrectionType = .no
            f.autocapitalizationType = .none
            f.spellCheckingType = .no
            f.delegate = nil
        }
        baseField.keyboardType = .URL
        passField.isSecureTextEntry = true
        form.axis = .vertical
        form.spacing = 8
        [baseField, userField, passField].forEach { form.addArrangedSubview($0) }
        form.isHidden = true

        primary.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        primary.backgroundColor = UIColor(red: 1, green: 0.31, blue: 0.17, alpha: 1)
        primary.setTitleColor(ink, for: .normal)
        primary.layer.cornerRadius = 11
        primary.layer.borderWidth = 2
        primary.layer.borderColor = ink.cgColor
        primary.heightAnchor.constraint(equalToConstant: 44).isActive = true
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primary.isHidden = true
        secondary.setTitle("关闭", for: .normal)
        secondary.setTitleColor(ink, for: .normal)
        secondary.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let head = UIStackView(arrangedSubviews: [titleLabel, spinner])
        head.axis = .horizontal
        head.spacing = 8
        head.alignment = .center

        let stack = UIStackView(arrangedSubviews: [head, statusLabel, progress, form, primary, secondary])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            card.topAnchor.constraint(greaterThanOrEqualTo: g.topAnchor, constant: 16),
            card.centerYAnchor.constraint(equalTo: g.centerYAnchor, constant: -40),
            card.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func setStatus(_ s: String, busy: Bool = false, error: Bool = false) {
        statusLabel.text = s
        statusLabel.textColor = error
            ? UIColor(red: 0.83, green: 0.16, blue: 0.10, alpha: 1)
            : UIColor(red: 0.09, green: 0.08, blue: 0.06, alpha: 1)
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    private var primaryMode = "retry"

    private func showPrimary(_ title: String, mode: String) {
        primary.setTitle(title, for: .normal)
        primaryMode = mode
        primary.isHidden = false
    }

    @objc private func closeTapped() {
        currentClient?.cancel()
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @objc private func primaryTapped() {
        view.endEditing(true)
        switch primaryMode {
        case "login": doLogin()
        default: proceed()
        }
    }

    // MARK: 读取分享内容
    private func collect(_ done: @escaping ([Payload]) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var providers: [NSItemProvider] = []
        var fallbackText: [String] = []
        for it in items {
            providers.append(contentsOf: it.attachments ?? [])
            if let t = it.attributedContentText?.string, !t.isEmpty { fallbackText.append(t) }
        }
        ShareLog.write("providers=\(providers.count) types=" + providers.map { $0.registeredTypeIdentifiers.joined(separator: "|") }.joined(separator: " ; "))

        let lock = NSLock()
        var out: [(Int, Payload)] = []
        let group = DispatchGroup()
        func add(_ i: Int, _ p: Payload) { lock.lock(); out.append((i, p)); lock.unlock() }

        for (idx, p) in providers.enumerated() {
            let isFileURL = p.hasItemConformingToTypeIdentifier("public.file-url")
            let isWebURL = p.hasItemConformingToTypeIdentifier("public.url") && !isFileURL
            if isWebURL {
                group.enter()
                p.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
                    if let u = item as? URL { add(idx, .text(u.absoluteString)) }
                    else if let s = item as? String { add(idx, .text(s)) }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier("public.data") || p.hasItemConformingToTypeIdentifier("public.item") || isFileURL {
                let typeId = p.hasItemConformingToTypeIdentifier("public.data") ? "public.data" : (isFileURL ? "public.file-url" : "public.item")
                group.enter()
                p.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, err in
                    defer { group.leave() }
                    guard let self = self else { return }
                    guard let url = url else {
                        ShareLog.write("loadFileRepresentation 失败: \(err?.localizedDescription ?? "nil")")
                        return
                    }
                    var name = url.lastPathComponent
                    if name.isEmpty { name = p.suggestedName ?? "shared" }
                    if (name as NSString).pathExtension.isEmpty,
                       let ut = UTType(typeId == "public.file-url" ? "public.data" : typeId),
                       let ext = (p.registeredTypeIdentifiers.compactMap { UTType($0)?.preferredFilenameExtension }.first ?? ut.preferredFilenameExtension) {
                        name += "." + ext
                    }
                    let dst = self.workDir.appendingPathComponent(UUID().uuidString + "_" + name)
                    do {
                        try FileManager.default.copyItem(at: url, to: dst)
                        let mime = UTType(filenameExtension: dst.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        add(idx, .file(url: dst, name: name, mime: mime))
                    } catch {
                        ShareLog.write("复制文件失败: \(error.localizedDescription)")
                    }
                }
            } else if p.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                _ = p.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                    defer { group.leave() }
                    guard let self = self, let img = obj as? UIImage, let data = img.pngData() else { return }
                    let name = "image-\(Int(Date().timeIntervalSince1970)).png"
                    let dst = self.workDir.appendingPathComponent(UUID().uuidString + "_" + name)
                    if (try? data.write(to: dst)) != nil { add(idx, .file(url: dst, name: name, mime: "image/png")) }
                }
            } else if p.hasItemConformingToTypeIdentifier("public.plain-text") || p.hasItemConformingToTypeIdentifier("public.text") {
                group.enter()
                p.loadItem(forTypeIdentifier: p.hasItemConformingToTypeIdentifier("public.plain-text") ? "public.plain-text" : "public.text", options: nil) { item, _ in
                    if let s = item as? String { add(idx, .text(s)) }
                    else if let a = item as? NSAttributedString { add(idx, .text(a.string)) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            var res = out.sorted { $0.0 < $1.0 }.map { $0.1 }
            if res.isEmpty, !fallbackText.isEmpty { res = fallbackText.map { .text($0) } }
            done(res)
        }
    }

    // MARK: 流程
    private func proceed() {
        primary.isHidden = true
        form.isHidden = true
        if let (c, src) = ShareStore.load() {
            config = c
            ShareLog.write("使用 \(src) 的登录信息 → \(c.base)")
            upload()
        } else {
            ShareLog.write("没有可用登录信息，显示登录表单")
            showLogin(message: "首次使用：请登录一次（保存在分享扩展自己的沙盒里）。\n将发送：" + payloads.map { $0.label }.joined(separator: "、"))
        }
    }

    private func showLogin(message: String) {
        setStatus(message)
        let d = UserDefaults.standard
        if baseField.text?.isEmpty ?? true { baseField.text = d.string(forKey: "ext_base") ?? "http://" }
        if userField.text?.isEmpty ?? true { userField.text = d.string(forKey: "ext_user") ?? "" }
        form.isHidden = false
        showPrimary("登录并发送", mode: "login")
        progress.isHidden = true
    }

    private func doLogin() {
        let base = ShareStore.normalize(baseField.text ?? "")
        let user = (userField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = (passField.text ?? "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        guard !base.isEmpty, !user.isEmpty, !pass.isEmpty, let url = URL(string: base + "/api/login") else {
            setStatus("请填写服务器地址、用户名和密码。", error: true)
            return
        }
        setStatus("正在登录 \(base) …", busy: true)
        primary.isHidden = true
        let body = (try? JSONSerialization.data(withJSONObject: ["username": user, "password": pass])) ?? Data()
        let client = MiniHTTPClient(url: url, method: "POST",
                                    headers: ["Content-Type": "application/json; charset=utf-8"],
                                    body: [.data(body)], connectTimeout: 15, idleTimeout: 30) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                ShareLog.write("登录失败: \(err.message)")
                self.showLogin(message: "")
                self.setStatus("无法连接 \(base)：\(err.message)\n\(self.diagnostics())", error: true)
            case .success(let resp):
                let code = resp.status
                let obj = (try? JSONSerialization.jsonObject(with: resp.body)) as? [String: Any]
                guard code == 200, let token = obj?["token"] as? String else {
                    let msg = (obj?["error"] as? String) ?? (obj?["detail"] as? String) ?? String(data: resp.body.prefix(300), encoding: .utf8) ?? ""
                    ShareLog.write("登录被拒 HTTP \(code): \(msg)")
                    self.showLogin(message: "")
                    self.setStatus("登录失败（HTTP \(code)）：\(msg)\nPOST \(base)/api/login\n\(self.diagnostics())", error: true)
                    return
                }
                UserDefaults.standard.set(user, forKey: "ext_user")
                let c = ShareStore.Config(base: base, token: token)
                ShareStore.saveLocal(c)
                self.config = c
                ShareLog.write("登录成功 \(base) 用户 \(user)")
                self.form.isHidden = true
                self.upload()
            }
        }
        currentClient = client
        client.start()
    }

    // MARK: 上传
    private func upload() {
        guard let cfg = config else { return }
        finished = false
        totalBytes = payloads.reduce(Int64(0)) { acc, p in
            if case .file(let u, _, _) = p {
                let n = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.int64Value ?? 0
                return acc + n
            }
            return acc + 1
        }
        doneBytes = 0
        progress.progress = 0
        progress.isHidden = false
        primary.isHidden = true
        setStatus("正在发送 0/\(payloads.count)…", busy: true)
        sendNext(index: 0, cfg: cfg)
    }

    private func sendNext(index: Int, cfg: ShareStore.Config) {
        if index >= payloads.count {
            finished = true
            progress.progress = 1
            setStatus("已发送，其他设备将同步（\(payloads.count) 项）", busy: false)
            ShareLog.write("全部发送成功")
            secondary.setTitle("完成", for: .normal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
            return
        }
        setStatus("正在发送 \(index + 1)/\(payloads.count)：\(payloads[index].label)", busy: true)
        let next: (Result<Void, Error>) -> Void = { [weak self] r in
            guard let self = self else { return }
            switch r {
            case .success: self.sendNext(index: index + 1, cfg: cfg)
            case .failure(let e): self.handleFailure(e)
            }
        }
        switch payloads[index] {
        case .text(let t): sendText(t, cfg: cfg, done: next)
        case .file(let url, let name, let mime): sendFile(url: url, name: name, mime: mime, cfg: cfg, done: next)
        }
    }

    private struct UploadError: LocalizedError {
        let message: String
        let status: Int
        var errorDescription: String? { message }
    }

    private func finish(_ result: Result<MiniHTTPResponse, MiniHTTPError>, _ what: String, _ url: URL, _ done: @escaping (Result<Void, Error>) -> Void) {
        switch result {
        case .failure(let err):
            done(.failure(UploadError(message: "网络错误：\(err.message)\n\(what) \(url.absoluteString)", status: 0)))
        case .success(let resp):
            let code = resp.status
            let body = String(data: resp.body, encoding: .utf8) ?? ""
            let obj = (try? JSONSerialization.jsonObject(with: resp.body)) as? [String: Any]
            if (200..<300).contains(code), (obj?["ok"] as? Bool) != false {
                done(.success(()))
            } else {
                var msg = (obj?["error"] as? String) ?? (obj?["detail"] as? String) ?? String(body.prefix(300))
                if code == 404 && (obj?["detail"] as? String) == "Not Found" {
                    msg = "服务器版本过旧或地址有误（该接口不存在）。请更新服务器 Docker 镜像。"
                }
                done(.failure(UploadError(message: "服务器返回 HTTP \(code)：\(msg)\n\(what) \(url.absoluteString)", status: code)))
            }
        }
    }

    private func sendText(_ text: String, cfg: ShareStore.Config, done: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: cfg.base + "/content") else {
            done(.failure(UploadError(message: "服务器地址无效：\(cfg.base)", status: 0)))
            return
        }
        let body = (try? JSONSerialization.data(withJSONObject: ["content": text, "visibility": "private", "expires_in": ShareStore.expiresIn])) ?? Data()
        let client = MiniHTTPClient(url: url, method: "POST",
                                    headers: ["Authorization": "Bearer \(cfg.token)",
                                              "Content-Type": "application/json; charset=utf-8",
                                              "X-Device-Id": deviceId()],
                                    body: [.data(body)], connectTimeout: 15, idleTimeout: 30) { [weak self] r in
            self?.finish(r, "POST", url, done)
        }
        currentClient = client
        client.start()
    }

    private func sendFile(url src: URL, name: String, mime: String, cfg: ShareStore.Config, done: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: cfg.base + "/upload_file") else {
            done(.failure(UploadError(message: "服务器地址无效：\(cfg.base)", status: 0)))
            return
        }
        let boundary = "ClipBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        func s(_ x: String) -> Data { return x.data(using: .utf8) ?? Data() }
        let safeName = name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var pre = Data()
        pre.append(s("--\(boundary)\r\nContent-Disposition: form-data; name=\"visibility\"\r\n\r\nprivate\r\n"))
        pre.append(s("--\(boundary)\r\nContent-Disposition: form-data; name=\"expires_in\"\r\n\r\n\(ShareStore.expiresIn)\r\n"))
        pre.append(s("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n"))
        let post = s("\r\n--\(boundary)--\r\n")
        // 文件按 256KB 分块从磁盘流式发送，不会整体读入内存
        let client = MiniHTTPClient(url: url, method: "POST",
                                    headers: ["Authorization": "Bearer \(cfg.token)",
                                              "Content-Type": "multipart/form-data; boundary=\(boundary)",
                                              "X-Device-Id": deviceId()],
                                    body: [.data(pre), .file(src), .data(post)],
                                    connectTimeout: 15, idleTimeout: 120,
                                    onProgress: { [weak self] sent, total in
                                        guard total > 0 else { return }
                                        self?.progress.progress = Float(sent) / Float(total)
                                    }) { [weak self] r in
            self?.finish(r, "POST", url, done)
        }
        currentClient = client
        client.start()
    }

    // MARK: 诊断信息（出现在错误对话框与日志里）
    private func deviceId() -> String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "ext_device_id"), !v.isEmpty { return v }
        let v = "ext-" + UUID().uuidString.lowercased()
        d.set(v, forKey: "ext_device_id")
        return v
    }

    private func diagnostics() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let ver = (info["CFBundleShortVersionString"] as? String ?? "?") + "(" + (info["CFBundleVersion"] as? String ?? "?") + ")"
        let ats: String
        if let a = info["NSAppTransportSecurity"] as? [String: Any] {
            ats = a.keys.sorted().map { "\($0)=\(a[$0] ?? "")" }.joined(separator: ",")
        } else {
            ats = "无"
        }
        let group = ShareStore.groupContainer != nil ? "可用" : "不可用"
        return "［诊断］扩展 v\(ver) · bundle=\(Bundle.main.bundleIdentifier ?? "?") · iOS \(UIDevice.current.systemVersion) · App Group \(group) · 传输=NWConnection(TCP，不经过 URLSession/ATS) · 运行时 ATS 配置=\(ats)"
    }

    private func handleFailure(_ e: Error) {
        let msg = e.localizedDescription
        ShareLog.write("发送失败: \(msg.replacingOccurrences(of: "\n", with: " | "))")
        if let u = e as? UploadError, u.status == 401 {
            ShareStore.clearToken()
            config = nil
            progress.isHidden = true
            showLogin(message: "")
            setStatus("登录已失效，请重新登录。\n\(msg)", error: true)
            return
        }
        fail(msg)
    }

    private func fail(_ message: String) {
        progress.isHidden = true
        let diag = diagnostics()
        ShareLog.write("失败诊断 " + diag)
        setStatus("发送失败：\(message)\n\(diag)", busy: false, error: true)
        if !payloads.isEmpty { showPrimary("重试", mode: "retry") }
        secondary.setTitle("关闭", for: .normal)
    }
}
