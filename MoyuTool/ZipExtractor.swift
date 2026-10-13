import Foundation
import Compression

// 轻量 zip 解压器 (仅支持 store/deflate, 覆盖美化配置包场景)
// 不引入第三方依赖: 直接解析 zip 结构, 用系统 Compression framework 解 raw deflate
enum ZipExtractor {

    enum ZipError: Error, LocalizedError {
        case notAZip
        case unsupportedMethod(UInt16)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip:                       return "不是有效的 zip 文件"
            case .unsupportedMethod(let m):      return "不支持的压缩方式 (\(m)), 仅支持 store/deflate"
            case .corrupt(let why):              return "zip 损坏: \(why)"
            }
        }
    }

    // 解压 zip 到目标目录 (保持压缩包内的相对结构), 返回解压出的文件相对路径列表
    static func extract(zipPath: String, toDirectory destRoot: String) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(atPath: destRoot, withIntermediateDirectories: true)
        guard let fh = FileHandle(forReadingAtPath: zipPath) else {
            throw ZipError.notAZip
        }
        defer { try? fh.close() }
        let data = fh.readDataToEndOfFile()
        guard data.count > 22 else { throw ZipError.notAZip }

        // 1. 从尾部找 EOCD (0x06054b50), 向前扫描容忍 zip 注释
        var eocd = -1
        var i = data.count - 22
        while i >= 0 {
            if le32(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }
        let entryCount = Int(le16(data, eocd + 10))
        let cdOffset   = Int(le32(data, eocd + 16))

        // 2. 遍历 central directory (0x02014b50)
        var files: [String] = []
        var p = cdOffset
        for _ in 0..<entryCount {
            guard p + 46 <= data.count, le32(data, p) == 0x02014b50 else {
                throw ZipError.corrupt("中央目录条目异常")
            }
            let method     = le16(data, p + 10)
            let cSize      = Int(le32(data, p + 20))
            let uSize      = Int(le32(data, p + 24))
            let nameLen    = Int(le16(data, p + 28))
            let extraLen   = Int(le16(data, p + 30))
            let commentLen = Int(le16(data, p + 32))
            let lho        = Int(le32(data, p + 42))
            guard p + 46 + nameLen <= data.count else { throw ZipError.corrupt("文件名越界") }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8)
                  ?? String(data: nameData, encoding: .ascii)
                  ?? "entry_\(files.count)"

            let isDir = name.hasSuffix("/") || name.hasSuffix("\\")
            if !isDir {
                let rel = sanitizeEntryName(name)
                if !rel.isEmpty {
                    try extractEntry(data: data,
                                     localHeaderOffset: lho,
                                     method: method,
                                     compressedSize: cSize,
                                     uncompressedSize: uSize,
                                     relPath: rel,
                                     destRoot: destRoot)
                    files.append(rel)
                }
            }
            p += 46 + nameLen + extraLen + commentLen
        }
        return files
    }

    private static func extractEntry(data: Data,
                                     localHeaderOffset: Int,
                                     method: UInt16,
                                     compressedSize: Int,
                                     uncompressedSize: Int,
                                     relPath: String,
                                     destRoot: String) throws {
        // 3. 解析 local file header (0x04034b50) 拿数据真实起点 (local 的 name/extra 长度可能与 central 不同)
        let p = localHeaderOffset
        guard p + 30 <= data.count, le32(data, p) == 0x04034b50 else {
            throw ZipError.corrupt("本地头异常: \(relPath)")
        }
        let nameLen  = Int(le16(data, p + 26))
        let extraLen = Int(le16(data, p + 28))
        let dataStart = p + 30 + nameLen + extraLen
        guard dataStart + compressedSize <= data.count else {
            throw ZipError.corrupt("数据越界: \(relPath)")
        }
        let comp = data.subdata(in: dataStart..<(dataStart + compressedSize))

        let raw: Data
        switch method {
        case 0: // store
            raw = comp
        case 8: // deflate (raw deflate == COMPRESSION_ZLIB)
            if uncompressedSize == 0 {
                raw = Data()
            } else {
                var dst = Data(count: uncompressedSize)
                let written = dst.withUnsafeMutableBytes { (db: UnsafeMutableRawBufferPointer) -> Int in
                    comp.withUnsafeBytes { (cb: UnsafeRawBufferPointer) -> Int in
                        guard let dBase = db.baseAddress, let cBase = cb.baseAddress else { return 0 }
                        return compression_decode_buffer(
                            dBase.assumingMemoryBound(to: UInt8.self), uncompressedSize,
                            cBase.assumingMemoryBound(to: UInt8.self), compressedSize,
                            nil, COMPRESSION_ZLIB)
                    }
                }
                guard written == uncompressedSize else {
                    throw ZipError.corrupt("解压不完整 \(relPath) (\(written)/\(uncompressedSize))")
                }
                raw = dst
            }
        default:
            throw ZipError.unsupportedMethod(method)
        }

        // 4. 写入目标 (自动建子目录)
        let dstPath = (destRoot as NSString).appendingPathComponent(relPath)
        let dir = (dstPath as NSString).deletingLastPathComponent
        if !dir.isEmpty && dir != destRoot {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try raw.write(to: URL(fileURLWithPath: dstPath))
    }

    // 防路径穿越, 统一分隔符, 过滤 ../
    private static func sanitizeEntryName(_ name: String) -> String {
        var parts: [String] = []
        for seg in name.replacingOccurrences(of: "\\", with: "/").split(separator: "/") {
            if seg == ".." || seg == "." { continue }
            parts.append(String(seg))
        }
        return parts.joined(separator: "/")
    }

    private static func le16(_ d: Data, _ off: Int) -> UInt16 {
        UInt16(d[off]) | (UInt16(d[off + 1]) << 8)
    }

    private static func le32(_ d: Data, _ off: Int) -> UInt32 {
        UInt32(le16(d, off)) | (UInt32(le16(d, off + 2)) << 16)
    }
}
