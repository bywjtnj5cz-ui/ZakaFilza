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
              let targetDir = body["targetDir"] as? String,
              let url = URL(string: urlString) else {
            respond(callbackId: callbackId, error: "缺少 url 或 targetDir 参数")
            return
        }

        let autoImport = body["autoImport"] as? Bool ?? true
        let filename = body["filename"] as? String ?? url.lastPathComponent

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

    private func handleAppInfo(callbackId: String) {
        let homeDir = NSHomeDirectory()
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? homeDir
        respond(callbackId: callbackId, data: [
            "homeDir": homeDir,
            "documentsDir": docsDir,
            "exploitId": fileHandle.exploitId,
            "systemVersion": UIDevice.current.systemVersion
        ])
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
