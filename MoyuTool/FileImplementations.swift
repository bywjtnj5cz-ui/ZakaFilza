import Foundation
import UIKit

// dlopen/dlsym 支持
#if canImport(Darwin)
import Darwin
#endif

// MARK: - 版本号比较辅助
struct Version: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ string: String) {
        let parts = string.split(separator: ".").map { Int($0) ?? 0 }
        self.major = parts.count > 0 ? parts[0] : 0
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    static func == (lhs: Version, rhs: Version) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
    }
}

// MARK: - 沙盒文件实现（exploit 未真正生效时的兜底，只能访问 App 自己的目录）
class SandboxFileImplementation: FileAccessImplementation {
    let rootPath: String

    init(rootPath: String) {
        self.rootPath = rootPath
    }

    private func resolve(_ path: String) -> String {
        // 安全限制：只能访问 rootPath 下的文件
        if path.hasPrefix(rootPath) {
            return path
        }
        // 如果是相对路径，拼接到 rootPath
        return (rootPath as NSString).appendingPathComponent(path)
    }

    func listDirectory(at path: String) throws -> [FileEntry] {
        let fullPath = resolve(path)
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: fullPath)
        return items.compactMap { name in
            let itemPath = (fullPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemPath, isDirectory: &isDir) else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            return FileEntry(
                name: name,
                path: itemPath,
                isDirectory: isDir.boolValue,
                size: (attrs?[.size] as? Int64) ?? 0,
                modificationDate: attrs?[.modificationDate] as? Date
            )
        }
    }

    func readFile(at path: String) throws -> Data {
        let fullPath = resolve(path)
        return try Data(contentsOf: URL(fileURLWithPath: fullPath))
    }

    func writeFile(at path: String, data: Data) throws {
        let fullPath = resolve(path)
        try data.write(to: URL(fileURLWithPath: fullPath))
    }

    func copyItem(at src: String, to dst: String) throws {
        try FileManager.default.copyItem(atPath: resolve(src), toPath: resolve(dst))
    }

    func moveItem(at src: String, to dst: String) throws {
        try FileManager.default.moveItem(atPath: resolve(src), toPath: resolve(dst))
    }

    func deleteItem(at path: String) throws {
        try FileManager.default.removeItem(atPath: resolve(path))
    }

    func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(atPath: resolve(path), withIntermediateDirectories: true)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: resolve(path))
    }
}

// MARK: - Root 文件实现（越狱环境下，可访问整个文件系统）
class RootFileImplementation: FileAccessImplementation {
    func listDirectory(at path: String) throws -> [FileEntry] {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(atPath: path)
        return items.compactMap { name in
            let itemPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemPath, isDirectory: &isDir) else { return nil }
            let attrs = try? fm.attributesOfItem(atPath: itemPath)
            return FileEntry(
                name: name,
                path: itemPath,
                isDirectory: isDir.boolValue,
                size: (attrs?[.size] as? Int64) ?? 0,
                modificationDate: attrs?[.modificationDate] as? Date
            )
        }
    }

    func readFile(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func writeFile(at path: String, data: Data) throws {
        try data.write(to: URL(fileURLWithPath: path))
    }

    func copyItem(at src: String, to dst: String) throws {
        try FileManager.default.copyItem(atPath: src, toPath: dst)
    }

    func moveItem(at src: String, to dst: String) throws {
        try FileManager.default.moveItem(atPath: src, toPath: dst)
    }

    func deleteItem(at path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func createDirectory(at path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - 外部 App 文件实现（通过 URL Scheme 调用闭源 Filza App）
// 由于闭源 App 通常不暴露文件操作 API，此实现的策略是：
// 1. 文件列表/读取等操作尝试通过 URL Scheme 传递给外部 App
// 2. 如果外部 App 不支持，则提示用户在外部 App 中手动操作
// 3. 下载功能在本 App 沙盒完成，然后引导用户搬运
class ExternalAppFileImplementation: FileAccessImplementation {
    let scheme: String
    let appName: String

    init(scheme: String, appName: String) {
        self.scheme = scheme
        self.appName = appName
    }

    private func openInExternalApp(path: String) {
        // 尝试用 URL Scheme 打开外部 App 到指定路径
        // 不同 Filza 变种的 URL Scheme 格式不同，这里用通用格式
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let urlString = "\(scheme)\(encodedPath)"
        if let url = URL(string: urlString),
           UIApplication.shared.canOpenURL(url) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }

    func listDirectory(at path: String) throws -> [FileEntry] {
        // 外部 App 模式无法直接列出目录
        // 引导用户跳转到外部 App 查看
        openInExternalApp(path: path)
        throw ExploitError.exploitFailed("请在 \(appName) 中查看此目录")
    }

    func readFile(at path: String) throws -> Data {
        openInExternalApp(path: path)
        throw ExploitError.exploitFailed("请在 \(appName) 中打开此文件")
    }

    func writeFile(at path: String, data: Data) throws {
        // 本 App 沙盒内可写，先保存到临时目录，提示用户搬运
        let tempDir = NSTemporaryDirectory()
        let tempPath = (tempDir as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        try data.write(to: URL(fileURLWithPath: tempPath))
        openInExternalApp(path: path)
        throw ExploitError.exploitFailed(
            "文件已保存到临时目录: \(tempPath)，请在 \(appName) 中移动到目标位置: \(path)"
        )
    }

    func copyItem(at src: String, to dst: String) throws {
        openInExternalApp(path: dst)
        throw ExploitError.exploitFailed("请在 \(appName) 中完成复制操作")
    }

    func moveItem(at src: String, to dst: String) throws {
        openInExternalApp(path: dst)
        throw ExploitError.exploitFailed("请在 \(appName) 中完成移动操作")
    }

    func deleteItem(at path: String) throws {
        openInExternalApp(path: path)
        throw ExploitError.exploitFailed("请在 \(appName) 中删除此文件")
    }

    func createDirectory(at path: String) throws {
        openInExternalApp(path: path)
        throw ExploitError.exploitFailed("请在 \(appName) 中创建目录")
    }

    func fileExists(at path: String) -> Bool {
        // 无法检测外部路径，返回 false 让 UI 提示
        return false
    }
}

// MARK: - Framework 文件实现（通过 dlopen 加载闭源 exploit framework）
// 需要根据 framework 实际导出的 C 函数来调用
// 假设 framework 导出了以下函数（根据实际 API 调整）：
//   int filza_list(const char* path, void* callback)
//   int filza_read(const char* path, void** data, size_t* len)
//   int filza_write(const char* path, const void* data, size_t len)
//   ...
class FrameworkFileImplementation: FileAccessImplementation {
    private let handle: UnsafeMutableRawPointer

    // 函数指针类型
    typealias ListFn = @convention(c) (UnsafePointer<CChar>, @convention(block) (UnsafePointer<CChar>, Bool, Int64) -> Void) -> Int32
    typealias ReadFn = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutableRawPointer?>, UnsafeMutablePointer<Int>) -> Int32
    typealias WriteFn = @convention(c) (UnsafePointer<CChar>, UnsafeRawPointer, Int) -> Int32
    typealias CopyFn = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
    typealias DeleteFn = @convention(c) (UnsafePointer<CChar>) -> Int32
    typealias MkdirFn = @convention(c) (UnsafePointer<CChar>) -> Int32
    typealias ExistsFn = @convention(c) (UnsafePointer<CChar>) -> Bool

    init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }

    private func getSymbol<T>(_ name: String) -> T? {
        guard let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    func listDirectory(at path: String) throws -> [FileEntry] {
        guard let fn: ListFn = getSymbol("filza_list") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_list")
        }
        var entries: [FileEntry] = []
        let result = path.withCString { cPath in
            fn(cPath) { name, isDir, size in
                let nameStr = String(cString: name)
                entries.append(FileEntry(
                    name: nameStr,
                    path: (path as NSString).appendingPathComponent(nameStr),
                    isDirectory: isDir,
                    size: size,
                    modificationDate: nil
                ))
            }
        }
        if result != 0 {
            throw ExploitError.exploitFailed("list 失败 (code: \(result))")
        }
        return entries
    }

    func readFile(at path: String) throws -> Data {
        guard let fn: ReadFn = getSymbol("filza_read") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_read")
        }
        var dataPtr: UnsafeMutableRawPointer?
        var length: Int = 0
        let result = path.withCString { cPath in
            fn(cPath, &dataPtr, &length)
        }
        guard result == 0, let ptr = dataPtr else {
            throw ExploitError.exploitFailed("read 失败 (code: \(result))")
        }
        return Data(bytes: ptr, count: length)
    }

    func writeFile(at path: String, data: Data) throws {
        guard let fn: WriteFn = getSymbol("filza_write") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_write")
        }
        let result = data.withUnsafeBytes { buf in
            path.withCString { cPath in
                fn(cPath, buf.baseAddress!, data.count)
            }
        }
        if result != 0 {
            throw ExploitError.exploitFailed("write 失败 (code: \(result))")
        }
    }

    func copyItem(at src: String, to dst: String) throws {
        guard let fn: CopyFn = getSymbol("filza_copy") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_copy")
        }
        let result = src.withCString { cSrc in
            dst.withCString { cDst in
                fn(cSrc, cDst)
            }
        }
        if result != 0 {
            throw ExploitError.exploitFailed("copy 失败 (code: \(result))")
        }
    }

    func moveItem(at src: String, to dst: String) throws {
        guard let fn: CopyFn = getSymbol("filza_move") else {
            // 用 copy + delete 代替
            try copyItem(at: src, to: dst)
            try deleteItem(at: src)
            return
        }
        let result = src.withCString { cSrc in
            dst.withCString { cDst in
                fn(cSrc, cDst)
            }
        }
        if result != 0 {
            throw ExploitError.exploitFailed("move 失败 (code: \(result))")
        }
    }

    func deleteItem(at path: String) throws {
        guard let fn: DeleteFn = getSymbol("filza_delete") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_delete")
        }
        let result = path.withCString { cPath in
            fn(cPath)
        }
        if result != 0 {
            throw ExploitError.exploitFailed("delete 失败 (code: \(result))")
        }
    }

    func createDirectory(at path: String) throws {
        guard let fn: MkdirFn = getSymbol("filza_mkdir") else {
            throw ExploitError.exploitFailed("framework 未导出 filza_mkdir")
        }
        let result = path.withCString { cPath in
            fn(cPath)
        }
        if result != 0 {
            throw ExploitError.exploitFailed("mkdir 失败 (code: \(result))")
        }
    }

    func fileExists(at path: String) -> Bool {
        guard let fn: ExistsFn = getSymbol("filza_exists") else {
            return false
        }
        return path.withCString { cPath in
            fn(cPath)
        }
    }
}
