import Foundation
import WebKit

// MARK: - 云端下载统一入口 (HomeView / FileBridge / 自动美化共用)
// 修复点:
//   - 文件名优先用配置里指定的 (原来 URL lastPathComponent 优先, 下载接口链接会把文件存成 verify.php)
//   - URL 容错 (含中文/空格自动百分号编码)
//   - 自己服务器的 download_upload 链接自动附加会话凭证 (链接里不再暴露 admin_token)
//   - 流式拷贝临时文件到目标, 不整包读进内存 (大 .pak 不再爆内存)
//   - 独立 URLSession, 大文件资源超时放宽到 10 分钟
enum DownloadOutcome {
    case success(String)
    case failure(String)
}

enum CloudDownloader {

    static func sanitizeFilename(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let cleaned = name.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : String(cleaned.prefix(120))
    }

    // 自己服务器的 download_upload 链接且未带凭证 → 自动附加 card_key/uuid/token
    static func authorize(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = comps.queryItems,
              query.contains(where: { $0.name == "action" && $0.value == "download_upload" }),
              !query.contains(where: { $0.name == "token" || $0.name == "admin_token" }) else {
            return url
        }
        var q = query
        let lm = LicenseManager.shared
        if let ck = lm.cardKey, !ck.isEmpty {
            q.append(URLQueryItem(name: "card_key", value: ck))
        }
        if let tk = lm.sessionToken, !tk.isEmpty {
            q.append(URLQueryItem(name: "token", value: tk))
        }
        q.append(URLQueryItem(name: "uuid", value: DeviceManager.shared.uuid))
        comps.queryItems = q
        return comps.url ?? url
    }

    static func buildURL(_ urlString: String) -> URL? {
        if let u = URL(string: urlString) { return authorize(u) }
        if let enc = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: enc) {
            return authorize(u)
        }
        return nil
    }

    // 下载加速配置:
    //   - .default (而非 .ephemeral): 全局连接池复用, 跨下载会话复用同一 host 的 TCP 连接
    //   - httpMaximumConnectionsPerHost = 6: 单 host 并发连接数翻倍 (iOS 默认 4)
    //   - networkServiceType = .responsiveData: 告诉系统提升优先级, 减少后台节流
    //   - httpShouldUsePipelining = true: HTTP/1.1 流水线减少握手开销
    //   - allowsCellularAccess = true: 允许蜂窝网络
    //   - waitForConnectivity = true: 网络暂时断开时自动等待 (iOS 11+)
    static func makeSession(progress: Bool = false) -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.networkServiceType = .responsiveData
        cfg.httpShouldUsePipelining = true
        cfg.allowsCellularAccess = true
        if #available(iOS 11.0, *) {
            cfg.waitsForConnectivity = true
        }
        // 清空缓存: 下载的大文件只落临时文件, 不需要磁盘缓存
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        // 禁用 http/https cookie 持久化 (避免和下载 host 无关的 cookie 干扰)
        cfg.httpCookieStorage = nil
        if progress {
            return URLSession(configuration: cfg)
        }
        return URLSession(configuration: cfg)
    }

    // 下载并导入。targetDir 为 nil 或空 → 存 App 沙盒 Documents; "@game:key" → 游戏目录
    // unzip=true 时把下载的 zip 解压, 按包内相对结构导入所有文件 (美化配置包场景)
    // 防呆: 若文件头实际是 zip 但 unzip=false, 且目标为游戏目录, 自动启用解压
    // progress: 下载进度回调 (0.0~1.0, 主线程回调), 传 nil 时走简单闭包式下载
    static func downloadAndImport(urlString: String,
                                  filename: String,
                                  targetDir: String?,
                                  handle: FileAccessHandle?,
                                  unzip: Bool = false,
                                  progress: ((Double) -> Void)? = nil,
                                  completion: @escaping (DownloadOutcome) -> Void) {
        guard let link = buildURL(urlString) else {
            completion(.failure("URL 无效: \(urlString)"))
            return
        }
        let name = sanitizeFilename(filename.isEmpty ? link.lastPathComponent : filename)

        // 无进度回调 → 走闭包式下载 (简单路径)
        guard let progress = progress else {
            makeSession().downloadTask(with: link) { tempURL, _, error in
                processDownloaded(tempURL: tempURL, error: error, name: name,
                                  targetDir: targetDir, handle: handle, unzip: unzip,
                                  completion: completion)
            }.resume()
            return
        }

        // 有进度回调 → 委托式下载, 实时上报 0.0~1.0
        let delegate = ProgressDownloadDelegate()
        delegate.onProgress = progress
        delegate.onDownloaded = { stableURL in
            processDownloaded(tempURL: stableURL, error: nil, name: name,
                              targetDir: targetDir, handle: handle, unzip: unzip,
                              completion: completion)
            try? FileManager.default.removeItem(at: stableURL)
        }
        delegate.onFailed = { msg in
            completion(.failure(msg))
        }
        // 给进度委托单独构造配置 (和 makeSession 逻辑一致, 但需要带 delegate)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.networkServiceType = .responsiveData
        cfg.httpShouldUsePipelining = true
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpCookieStorage = nil
        if #available(iOS 11.0, *) { cfg.waitsForConnectivity = true }
        let sess = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        sess.downloadTask(with: link).resume()
    }

    // 统一处理下载完成的临时文件: 检测 zip → 解压/拷贝导入目标目录
    private static func processDownloaded(tempURL: URL?,
                                          error: Error?,
                                          name: String,
                                          targetDir: String?,
                                          handle: FileAccessHandle?,
                                          unzip: Bool,
                                          completion: @escaping (DownloadOutcome) -> Void) {
        if let error = error {
            completion(.failure("下载失败: \(error.localizedDescription)"))
            return
        }
        guard let tempURL = tempURL else {
            completion(.failure("下载失败: 服务器无返回文件"))
            return
        }
        let tmp = tempURL.path
        let size = ((try? FileManager.default.attributesOfItem(atPath: tmp))?[.size] as? NSNumber)?.int64Value ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        do {
            // 智能检测: 文件头是否为 zip (PK\x03\x04)
            let isActuallyZip = Self.isZipFile(atPath: tmp)
            // 若显式要求解压, 或文件实为 zip 且导入游戏目录, 自动解压
            let shouldUnzip = unzip || (isActuallyZip && targetDir?.hasPrefix("@game:") == true)

            if let td = targetDir, !td.isEmpty {
                guard let handle = handle else {
                    completion(.failure("尚未获得文件权限, 请先运行漏洞利用"))
                    return
                }
                guard let resolved = GameDirectoryResolver.resolve(td, fileHandle: handle) else {
                    completion(.failure("未定位到目标目录: \(td)"))
                    return
                }
                if shouldUnzip {
                    let count = try importUnzipped(zipPath: tmp, into: resolved, handle: handle)
                    completion(.success("\(count) 个文件 (解压导入) → \(resolved)"))
                } else {
                    try handle.createDirectory(at: resolved)
                    let dest = (resolved as NSString).appendingPathComponent(name)
                    if handle.fileExists(at: dest) { try? handle.deleteItem(at: dest) }
                    try handle.copyItem(at: tmp, to: dest)
                    completion(.success("\(name) (\(sizeText)) → \(resolved)"))
                }
            } else {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                if shouldUnzip {
                    let count = try importUnzipped(zipPath: tmp, into: docs.path, handle: nil)
                    completion(.success("\(count) 个文件 (解压导入) → \(docs.path)"))
                } else {
                    let dest = docs.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.removeItem(at: dest)
                    }
                    try FileManager.default.copyItem(atPath: tmp, toPath: dest.path)
                    completion(.success(dest.path))
                }
            }
        } catch {
            completion(.failure("保存失败: \(error.localizedDescription)"))
        }
    }

    /// 通过文件头魔数检测是否为 zip 格式 (支持 PK\x03\x04 / PK\x05\x06 / PK\x07\x08)
    private static func isZipFile(atPath path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        guard let header = try? fh.read(upToCount: 4), header.count >= 4 else { return false }
        let sig = UInt32(header[0]) | (UInt32(header[1]) << 8) | (UInt32(header[2]) << 16) | (UInt32(header[3]) << 24)
        return sig == 0x04034B50 || sig == 0x06054B50 || sig == 0x08064B50
    }

    // 解压 zip 并把包内文件按相对结构导入目标目录 (handle 为 nil 时走沙盒拷贝)
    private static func importUnzipped(zipPath: String,
                                       into dir: String,
                                       handle: FileAccessHandle?) throws -> Int {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unzip-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: extractDir) }

        let entries = try ZipExtractor.extract(zipPath: zipPath, toDirectory: extractDir)
        guard !entries.isEmpty else {
            throw ZipExtractor.ZipError.corrupt("压缩包内没有文件")
        }
        for rel in entries {
            let src = (extractDir as NSString).appendingPathComponent(rel)
            let dst = (dir as NSString).appendingPathComponent(rel)
            let parent = (dst as NSString).deletingLastPathComponent
            if handle != nil {
                if parent != dir { try handle?.createDirectory(at: parent) }
                if handle?.fileExists(at: dst) == true { try? handle?.deleteItem(at: dst) }
                try handle?.copyItem(at: src, to: dst)
            } else {
                if parent != dir {
                    try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                }
                if FileManager.default.fileExists(atPath: dst) {
                    try? FileManager.default.removeItem(atPath: dst)
                }
                try FileManager.default.copyItem(atPath: src, toPath: dst)
            }
        }
        return entries.count
    }
}

// MARK: - 带进度回调的下载委托
// URLSessionDownloadDelegate 实时上报下载进度; 下载完成后先把临时文件拷贝到稳定路径,
// 再交给处理逻辑 (didFinishDownloadingTo 的 location 仅在回调期间有效)
final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Double) -> Void)?     // 0.0~1.0, 主线程回调
    var onDownloaded: ((URL) -> Void)?      // 稳定临时文件路径 (后台线程)
    var onFailed: ((String) -> Void)?
    private var settled = false

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let clamped = min(max(p, 0.0), 1.0)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(clamped)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // location 仅在本回调执行期间有效 → 立即拷贝到稳定临时路径再处理
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("moyu-dl-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: location, to: stable)
            settled = true
            onDownloaded?(stable)
        } catch {
            settled = true
            onFailed?("保存下载文件失败: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error, !settled {
            settled = true
            onFailed?("下载失败: \(error.localizedDescription)")
        }
        // 释放 session 对 delegate 的强引用
        session.finishTasksAndInvalidate()
    }
}

// MARK: - JS <-> Native 文件操作桥接
// HTML 文件管理器通过 WKScriptMessageHandler 调用原生的文件操作 API
final class FileBridge: NSObject, WKScriptMessageHandler {
    private let fileHandle: FileAccessHandle
    private weak var webView: WKWebView?

    init(fileHandle: FileAccessHandle) {
        self.fileHandle = fileHandle
        super.init()
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        let controller = webView.configuration.userContentController
        controller.add(self, name: "fileBridge")
    }

    func detach() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "fileBridge")
    }

    // 处理来自 JS 的消息
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "fileBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let callbackId = body["callbackId"] as? String else {
            return
        }

        switch action {
        case "list":
            handleList(body: body, callbackId: callbackId)
        case "read":
            handleRead(body: body, callbackId: callbackId)
        case "write":
            handleWrite(body: body, callbackId: callbackId)
        case "copy":
            handleCopy(body: body, callbackId: callbackId)
        case "move":
            handleMove(body: body, callbackId: callbackId)
        case "delete":
            handleDelete(body: body, callbackId: callbackId)
        case "mkdir":
            handleMkdir(body: body, callbackId: callbackId)
        case "exists":
            handleExists(body: body, callbackId: callbackId)
        case "download":
            handleDownload(body: body, callbackId: callbackId)
        case "appInfo":
            handleAppInfo(callbackId: callbackId)
        default:
            respond(callbackId: callbackId, error: "未知操作: \(action)")
        }
    }

    // MARK: - 文件操作实现
    private func handleList(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 参数")
            return
        }
        do {
            let entries = try fileHandle.listDirectory(at: path)
            let data = entries.map { entry in
                [
                    "name": entry.name,
                    "path": entry.path,
                    "isDirectory": entry.isDirectory,
                    "size": entry.size,
                    "modificationDate": entry.modificationDate?.timeIntervalSince1970 ?? 0
                ] as [String: Any]
            }
            respond(callbackId: callbackId, data: ["items": data])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleRead(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 参数")
            return
        }
        do {
            let data = try fileHandle.readFile(at: path)
            // 返回 base64
            respond(callbackId: callbackId, data: ["content": data.base64EncodedString()])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleWrite(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String,
              let content = body["content"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 或 content 参数")
            return
        }
        do {
            let data: Data
            if body["base64"] as? Bool == true {
                guard let decoded = Data(base64Encoded: content) else {
                    respond(callbackId: callbackId, error: "base64 解码失败")
                    return
                }
                data = decoded
            } else {
                data = Data(content.utf8)
            }
            try fileHandle.writeFile(at: path, data: data)
            respond(callbackId: callbackId, data: ["success": true])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleCopy(body: [String: Any], callbackId: String) {
        guard let src = body["src"] as? String,
              let dst = body["dst"] as? String else {
            respond(callbackId: callbackId, error: "缺少 src 或 dst 参数")
            return
        }
        do {
            try fileHandle.copyItem(at: src, to: dst)
            respond(callbackId: callbackId, data: ["success": true])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleMove(body: [String: Any], callbackId: String) {
        guard let src = body["src"] as? String,
              let dst = body["dst"] as? String else {
            respond(callbackId: callbackId, error: "缺少 src 或 dst 参数")
            return
        }
        do {
            try fileHandle.moveItem(at: src, to: dst)
            respond(callbackId: callbackId, data: ["success": true])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleDelete(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 参数")
            return
        }
        do {
            try fileHandle.deleteItem(at: path)
            respond(callbackId: callbackId, data: ["success": true])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleMkdir(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 参数")
            return
        }
        do {
            try fileHandle.createDirectory(at: path)
            respond(callbackId: callbackId, data: ["success": true])
        } catch {
            respond(callbackId: callbackId, error: error.localizedDescription)
        }
    }

    private func handleExists(body: [String: Any], callbackId: String) {
        guard let path = body["path"] as? String else {
            respond(callbackId: callbackId, error: "缺少 path 参数")
            return
        }
        let exists = fileHandle.fileExists(at: path)
        respond(callbackId: callbackId, data: ["exists": exists])
    }

    // 一键下载直链并导入到应用目录 (统一走 CloudDownloader)
    private func handleDownload(body: [String: Any], callbackId: String) {
        guard let urlString = body["url"] as? String else {
            respond(callbackId: callbackId, error: "缺少 url 参数")
            return
        }
        let rawTargetDir = body["targetDir"] as? String
        let autoImport = body["autoImport"] as? Bool ?? true
        let unzip = body["unzip"] as? Bool ?? false
        var filename = body["filename"] as? String ?? ""
        if filename.isEmpty || filename == "undefined" {
            filename = URL(string: urlString)?.lastPathComponent ?? ""
        }
        // autoImport=false 或未指定目标目录 → 存 App 沙盒 Documents
        let targetDir = (autoImport && rawTargetDir?.isEmpty == false) ? rawTargetDir : nil

        CloudDownloader.downloadAndImport(
            urlString: urlString,
            filename: filename,
            targetDir: targetDir,
            handle: fileHandle,
            unzip: unzip
        ) { result in
            switch result {
            case .success(let path):
                self.respond(callbackId: callbackId, data: ["success": true, "path": path])
            case .failure(let message):
                self.respond(callbackId: callbackId, error: message)
            }
        }
    }

    private func handleAppInfo(callbackId: String) {
        let homeDir = NSHomeDirectory()
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? homeDir
        var info: [String: Any] = [
            "homeDir": homeDir,
            "documentsDir": docsDir,
            "exploitId": fileHandle.exploitId,
            "systemVersion": UIDevice.current.systemVersion
        ]
        // 点云控按钮直接跳到指定目录 (HomeView 通过 UserDefaults 透传起始路径, 支持 @game:<key>)
        if let rawStart = UserDefaults.standard.string(forKey: "filemanager_start_path"), !rawStart.isEmpty {
            if let resolved = GameDirectoryResolver.resolve(rawStart, fileHandle: fileHandle) {
                info["startPath"] = resolved
            }
        }
        respond(callbackId: callbackId, data: info)
    }

    // MARK: - 回调
    private func respond(callbackId: String, data: [String: Any]? = nil, error: String? = nil) {
        var response: [String: Any] = ["callbackId": callbackId]
        if let error = error {
            response["error"] = error
        } else {
            response["data"] = data ?? [:]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__bridgeCallback(\(jsonString))")
        }
    }
}
