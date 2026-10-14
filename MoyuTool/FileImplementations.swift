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
