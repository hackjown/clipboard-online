import UIKit
import UniformTypeIdentifiers

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
final class ShareViewController: UIViewController, URLSessionTaskDelegate {
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
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    private var currentTask: URLSessionTask?
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
        ShareLog.write("启动 bundle=\(Bundle.main.bundleIdentifier ?? "?") group=\(ShareStore.groupContainer != nil ? "可用" : "不可用") ")
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
        currentTask?.cancel()
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
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": user, "password": pass])
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let err = err {
                ShareLog.write("登录失败: \(err.localizedDescription)")
                self.showLogin(message: "无法连接 \(base)：\(err.localizedDescription)")
                self.setStatus("无法连接 \(base)：\(err.localizedDescription)", error: true)
                return
            }
            let obj = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
            guard code == 200, let token = obj?["token"] as? String else {
                let msg = (obj?["error"] as? String) ?? (obj?["detail"] as? String) ?? String(data: data ?? Data(), encoding: .utf8) ?? ""
                ShareLog.write("登录被拒 HTTP \(code): \(msg)")
                self.showLogin(message: "")
                self.setStatus("登录失败（HTTP \(code)）：\(msg)\nPOST \(base)/api/login", error: true)
                return
            }
            UserDefaults.standard.set(user, forKey: "ext_user")
            let c = ShareStore.Config(base: base, token: token)
            ShareStore.saveLocal(c)
            self.config = c
            ShareLog.write("登录成功 \(base) 用户 \(user)")
            self.form.isHidden = true
            self.upload()
        }.resume()
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

    private func finish(_ data: Data?, _ resp: URLResponse?, _ err: Error?, _ what: String, _ url: URL, _ done: @escaping (Result<Void, Error>) -> Void) {
        if let err = err {
            done(.failure(UploadError(message: "网络错误：\(err.localizedDescription)\n\(what) \(url.absoluteString)", status: 0)))
            return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
        let obj = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
        if (200..<300).contains(code), (obj?["ok"] as? Bool) != false {
            done(.success(()))
        } else {
            let msg = (obj?["error"] as? String) ?? (obj?["detail"] as? String) ?? String(body.prefix(300))
            done(.failure(UploadError(message: "服务器返回 HTTP \(code)：\(msg)\n\(what) \(url.absoluteString)", status: code)))
        }
    }

    private func sendText(_ text: String, cfg: ShareStore.Config, done: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: cfg.base + "/content") else {
            done(.failure(UploadError(message: "服务器地址无效：\(cfg.base)", status: 0)))
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": text, "visibility": "private", "expires_in": 0])
        currentTask = session.dataTask(with: req) { [weak self] d, r, e in
            self?.finish(d, r, e, "POST", url, done)
        }
        currentTask?.resume()
    }

    private func sendFile(url src: URL, name: String, mime: String, cfg: ShareStore.Config, done: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: cfg.base + "/upload_file") else {
            done(.failure(UploadError(message: "服务器地址无效：\(cfg.base)", status: 0)))
            return
        }
        let boundary = "ClipBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let bodyURL = workDir.appendingPathComponent("body_" + UUID().uuidString)
        do {
            FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: bodyURL)
            func w(_ s: String) { out.write(s.data(using: .utf8) ?? Data()) }
            w("--\(boundary)\r\nContent-Disposition: form-data; name=\"visibility\"\r\n\r\nprivate\r\n")
            w("--\(boundary)\r\nContent-Disposition: form-data; name=\"expires_in\"\r\n\r\n0\r\n")
            let safeName = name.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
            w("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n")
            let inp = try FileHandle(forReadingFrom: src)
            while true {
                let chunk = inp.readData(ofLength: 1 << 20)
                if chunk.isEmpty { break }
                out.write(chunk)
            }
            try? inp.close()
            w("\r\n--\(boundary)--\r\n")
            try? out.close()
        } catch {
            done(.failure(UploadError(message: "准备上传数据失败：\(error.localizedDescription)", status: 0)))
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 600)
        req.httpMethod = "POST"
        req.setValue("Bearer \(cfg.token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        currentTask = session.uploadTask(with: req, fromFile: bodyURL) { [weak self] d, r, e in
            try? FileManager.default.removeItem(at: bodyURL)
            self?.finish(d, r, e, "POST", url, done)
        }
        currentTask?.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress.progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
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
        setStatus("发送失败：\(message)", busy: false, error: true)
        if !payloads.isEmpty { showPrimary("重试", mode: "retry") }
        secondary.setTitle("关闭", for: .normal)
    }
}
