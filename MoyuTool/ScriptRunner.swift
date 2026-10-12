import Foundation
import JavaScriptCore

// MARK: - 云端脚本执行器 (JavaScriptCore)
// run_script 按钮真正执行 JS 脚本, 并暴露一整套原生文件 API 给脚本调用
final class ScriptRunner {

    struct ScriptLog {
        let lines: [String]
        let succeeded: Bool
    }

    // 在后台线程执行脚本, 完成后在主线程回调日志
    static func run(script: String, fileHandle: FileAccessHandle?, completion: @escaping (ScriptLog) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = execute(script: script, fileHandle: fileHandle)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func execute(script: String, fileHandle: FileAccessHandle?) -> ScriptLog {
        var logs: [String] = []
        let succeeded = true

        func appendLog(_ msg: String) {
            logs.append(msg)
            print("[Script] \(msg)")
        }

        guard let context = JSContext() else {
            return ScriptLog(lines: ["❌ 无法创建 JS 执行环境"], succeeded: false)
        }

        context.exceptionHandler = { _, exception in
            if let e = exception {
                appendLog("⚠️ 脚本异常: \(e)")
            }
        }

        // console.log / log
        let logBlock: @convention(block) (String) -> Void = { appendLog($0) }
        context.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        if let console = JSValue(newObjectIn: context) {
            console.setObject(logBlock, forKeyedSubscript: "log" as NSString)
            context.setObject(console, forKeyedSubscript: "console" as NSString)
        }

        // 文件句柄为空时, 所有文件操作直接失败并打印
        let handle = fileHandle

        // 原生文件 API
        let writeBlock: @convention(block) (String, String, Bool) -> Bool = { path, content, isBase64 in
            guard let h = handle else { appendLog("❌ write \(path): 无文件访问权限"); return false }
            do {
                let data: Data = isBase64 ? (Data(base64Encoded: content) ?? Data()) : Data(content.utf8)
                try h.writeFile(at: path, data: data)
                appendLog("✓ write \(path) (\(data.count) 字节)")
                return true
            } catch { appendLog("❌ write \(path): \(error.localizedDescription)"); return false }
        }

        let readBase64Block: @convention(block) (String) -> String = { path in
            guard let h = handle else { appendLog("❌ readBase64 \(path): 无文件访问权限"); return "" }
            do {
                let data = try h.readFile(at: path)
                appendLog("✓ readBase64 \(path) (\(data.count) 字节)")
                return data.base64EncodedString()
            } catch { appendLog("❌ readBase64 \(path): \(error.localizedDescription)"); return "" }
        }

        let readBlock: @convention(block) (String) -> String = { path in
            guard let h = handle else { appendLog("❌ read \(path): 无文件访问权限"); return "" }
            do {
                let data = try h.readFile(at: path)
                return String(data: data, encoding: .utf8) ?? ""
            } catch { appendLog("❌ read \(path): \(error.localizedDescription)"); return "" }
        }

        let copyBlock: @convention(block) (String, String) -> Bool = { src, dst in
            guard let h = handle else { appendLog("❌ copy: 无文件访问权限"); return false }
            do { try h.copyItem(at: src, to: dst); appendLog("✓ copy \(src) → \(dst)"); return true }
            catch { appendLog("❌ copy: \(error.localizedDescription)"); return false }
        }

        let moveBlock: @convention(block) (String, String) -> Bool = { src, dst in
            guard let h = handle else { appendLog("❌ move: 无文件访问权限"); return false }
            do { try h.moveItem(at: src, to: dst); appendLog("✓ move \(src) → \(dst)"); return true }
            catch { appendLog("❌ move: \(error.localizedDescription)"); return false }
        }

        let removeBlock: @convention(block) (String) -> Bool = { path in
            guard let h = handle else { appendLog("❌ remove \(path): 无文件访问权限"); return false }
            do { try h.deleteItem(at: path); appendLog("✓ remove \(path)"); return true }
            catch { appendLog("❌ remove \(path): \(error.localizedDescription)"); return false }
        }

        let mkdirBlock: @convention(block) (String) -> Bool = { path in
            guard let h = handle else { appendLog("❌ mkdir \(path): 无文件访问权限"); return false }
            do { try h.createDirectory(at: path); appendLog("✓ mkdir \(path)"); return true }
            catch { appendLog("❌ mkdir \(path): \(error.localizedDescription)"); return false }
        }

        let existsBlock: @convention(block) (String) -> Bool = { path in
            let exists = handle?.fileExists(at: path) ?? false
            appendLog("exists \(path) → \(exists)")
            return exists
        }

        let listBlock: @convention(block) (String) -> String = { path in
            guard let h = handle else { appendLog("❌ list \(path): 无文件访问权限"); return "[]" }
            do {
                let entries = try h.listDirectory(at: path)
                let names = entries.map { $0.name }
                if let data = try? JSONSerialization.data(withJSONObject: names),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "[]"
            } catch { appendLog("❌ list \(path): \(error.localizedDescription)"); return "[]" }
        }

        // replaceInFile(path, find, replace) — 文本替换
        let replaceInFileBlock: @convention(block) (String, String, String) -> Bool = { path, find, replace in
            guard let h = handle else { appendLog("❌ replaceInFile \(path): 无文件访问权限"); return false }
            do {
                let data = try h.readFile(at: path)
                guard var text = String(data: data, encoding: .utf8) else {
                    appendLog("❌ replaceInFile \(path): 非文本文件"); return false
                }
                text = text.replacingOccurrences(of: find, with: replace)
                try h.writeFile(at: path, data: Data(text.utf8))
                appendLog("✓ replaceInFile \(path)")
                return true
            } catch { appendLog("❌ replaceInFile \(path): \(error.localizedDescription)"); return false }
        }

        context.setObject(writeBlock, forKeyedSubscript: "write" as NSString)
        context.setObject(readBase64Block, forKeyedSubscript: "readBase64" as NSString)
        context.setObject(readBlock, forKeyedSubscript: "read" as NSString)
        context.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        context.setObject(moveBlock, forKeyedSubscript: "move" as NSString)
        context.setObject(removeBlock, forKeyedSubscript: "remove" as NSString)
        context.setObject(mkdirBlock, forKeyedSubscript: "mkdir" as NSString)
        context.setObject(existsBlock, forKeyedSubscript: "exists" as NSString)
        context.setObject(listBlock, forKeyedSubscript: "list" as NSString)
        context.setObject(replaceInFileBlock, forKeyedSubscript: "replaceInFile" as NSString)

        appendLog("▶ 开始执行脚本")
        context.evaluateScript(script)
        if context.exception != nil {
            appendLog("❌ 脚本执行失败")
            appendLog("■ 执行结束 (失败)")
            return ScriptLog(lines: logs, succeeded: false)
        }
        appendLog("■ 执行结束 (成功)")
        return ScriptLog(lines: logs, succeeded: succeeded)
    }
}