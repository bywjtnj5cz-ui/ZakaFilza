import Foundation

// 游戏目录解析器：把云控配置里的 "@game:<key>" 虚拟路径解析成设备上的绝对路径。
// 客户端只负责「按 bundle id 定位容器根」这一技术原语，具体的 Saved 前缀、子目录
// (Paks / avatarpaks / Savegame 等) 全部由服务端 game_dirs 配置下发，不写死任何业务路径。
enum GameDirectoryResolver {

    /// 解析路径。普通路径原样返回；"@game:<key>" 解析为容器内的绝对目录，失败返回 nil。
    static func resolve(_ raw: String, fileHandle: FileAccessHandle?) -> String? {
        guard raw.hasPrefix("@game:") else { return raw }
        let key = String(raw.dropFirst("@game:".count))
        guard let gd = ConfigManager.shared.config?.gameDirs,
              let target = gd.targets.first(where: { $0.key == key }) else {
            return nil
        }
        guard let root = containerRoot(bundleID: gd.bundleID, fileHandle: fileHandle) else {
            return nil
        }

        var base = root
        if let savedRel = gd.savedRel, !savedRel.isEmpty {
            base = (base as NSString).appendingPathComponent(savedRel)
        }
        return (base as NSString).appendingPathComponent(target.rel)
    }

    /// 按 bundle id 定位 App 数据容器根路径。
    /// 优先走 MCM 枚举 (FilzaSlop 的 sandbox extension)，失败则用句柄扫描容器目录读 metadata plist 兜底。
    static func containerRoot(bundleID: String, fileHandle: FileAccessHandle?) -> String? {
        // 1. MCM 枚举 + 租约 + metadata 匹配 (FilzaSlop 唯一可靠路径)
        //    注意: MCM 租约的 identifier 是容器 UUID 而非 bundle id,
        //    所以必须先枚举全部 UUID 再逐个读 metadata 匹配包名。
        if MCMFileManager.shared.isAvailable,
           let root = mcmContainerRoot(bundleID) {
            return root
        }

        // 2. 兜底：用文件句柄扫描 Application 目录，逐个读 metadata plist 匹配包名
        //    (FilzaJailedDS 内核漏洞有全盘权限, 这条路才走得通)
        let base = "/var/mobile/Containers/Data/Application"
        guard let handle = fileHandle,
              let entries = try? handle.listDirectory(at: base) else {
            return nil
        }
        for entry in entries where entry.isDirectory {
            let metadata = (entry.path as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? handle.readFile(at: metadata),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = plist as? [String: Any],
                  let identifier = dict["MCMMetadataIdentifier"] as? String,
                  identifier == bundleID else {
                continue
            }
            return entry.path
        }
        return nil
    }

    /// MCM 枚举定位：逐个容器申请租约并激活沙盒扩展，读 metadata plist 匹配 bundle id
    private static func mcmContainerRoot(_ bundleID: String) -> String? {
        let mcm = MCMFileManager.shared
        let ids = mcm.enumerateIdentifiers(forClass: .appData, limit: 800)
        guard !ids.isEmpty else { return nil }

        let fm = FileManager.default
        for uuid in ids {
            // 申请租约并激活, 之后该容器根目录才可读
            guard let (path, _) = mcm.obtainLease(identifier: uuid, containerClass: .appData),
                  let root = path else {
                continue
            }
            let metadata = (root as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadata)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = plist as? [String: Any],
                  let identifier = dict["MCMMetadataIdentifier"] as? String,
                  identifier == bundleID else {
                continue
            }
            return root
        }
        return nil
    }
}