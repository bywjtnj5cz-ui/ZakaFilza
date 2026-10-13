import Foundation
import WebKit

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

    // 一键下载直链并导入到应用目录
    private func handleDownload(body: [String: Any], callbackId: String) {
        guard let urlString = body["url"] as? String,
              let rawTargetDir = body["targetDir"] as? String,
              let url = URL(string: urlString) else {
            respond(callbackId: callbackId, error: "缺少 url 或 targetDir 参数")
            return
        }

        // 解析 @game:<key> 虚拟路径为设备绝对路径 (普通路径原样返回)
        guard let targetDir = GameDirectoryResolver.resolve(rawTargetDir, fileHandle: fileHandle) else {
            respond(callbackId: callbackId, error: "未定位到游戏目录，请确认游戏已安装，或先进入文件管理器获得文件系统权限")
            return
        }

        let autoImport = body["autoImport"] as? Bool ?? true
        var filename = body["filename"] as? String ?? ""
        if filename.isEmpty || filename == "undefined" {
            filename = url.lastPathComponent
        }
        if filename.isEmpty {
            filename = "download"
        }

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            if let error = error {
                self?.respond(callbackId: callbackId, error: "下载失败: \(error.localizedDescription)")
                return
            }
            guard let tempURL = tempURL else {
                self?.respond(callbackId: callbackId, error: "下载失败: 临时文件不存在")
                return
            }
            do {
                let data = try Data(contentsOf: tempURL)
                if autoImport {
                    if Self.isReadOnlySystemPath(targetDir) {
                        self?.respond(callbackId: callbackId, error: "目标目录是系统只读分区，无法写入。请切换到应用容器目录（如 /var/mobile/Containers/Data/Application）")
                        return
                    }
                    // 自动导入到目标目录
                    let targetPath = (targetDir as NSString).appendingPathComponent(filename)
                    try self?.fileHandle.createDirectory(at: targetDir)
                    try self?.fileHandle.writeFile(at: targetPath, data: data)
                    self?.respond(callbackId: callbackId, data: [
                        "success": true,
                        "path": targetPath,
                        "size": data.count
                    ])
                } else {
                    // 仅保存到 App 沙盒临时目录
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent(filename)
                    try data.write(to: dest)
                    self?.respond(callbackId: callbackId, data: [
                        "success": true,
                        "path": dest.path,
                        "size": data.count
                    ])
                }
            } catch {
                self?.respond(callbackId: callbackId, error: "保存失败: \(error.localizedDescription)")
            }
        }.resume()
    }

    // 系统只读分区（sealed volume）无法写入，下载前预检给出友好提示
    private static let readOnlySystemPrefixes = ["/System", "/bin", "/sbin", "/usr", "/Applications", "/Library", "/etc"]

    private static func isReadOnlySystemPath(_ path: String) -> Bool {
        var p = path
        if p.hasPrefix("/private") { p = String(p.dropFirst("/private".count)) }
        return readOnlySystemPrefixes.contains { p == $0 || p.hasPrefix($0 + "/") }
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
