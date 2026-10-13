import Foundation

// 游戏目录解析器：把云控配置里的 "@game:<key>" 虚拟路径解析成设备上的绝对路径。
// 客户端只负责「按 bundle id 定位容器根」这一技术原语，具体的 Saved 前缀、子目录
// (Paks / avatarpaks / SaveGames 等) 全部由服务端 game_dirs 配置下发，不写死任何业务路径。
enum GameDirectoryResolver {

    // 定位过程的完整诊断信息 (目录检测页面展示用)
    struct LookupReport {
        var root: String? = nil
        var directTried = false        // 是否尝试过按 bundle id 直接租约
        var directError = ""           // 直查失败原因
        var mcmAvailable = false       // MCM bridge 是否可用 (FilzaSlop)
        var mcmEnumCount = 0           // MCM 枚举到的容器数量
        var mcmLeaseOk = 0             // MCM 租约成功的容器数量
        var scanTried = false          // 是否尝试了句柄扫描 (FilzaJailedDS)
        var scanEntryCount = 0         // 扫描到的容器数量
        var scanFailed = false         // 扫描是否失败
        var scanError = ""             // 扫描失败原因
        var tencentBundles: [String] = [] // 扫描中看到的腾讯系应用包名 (最多 10 个)
        var notes: [String] = []       // 附加说明
    }

    // 会话级缓存: bundleID -> 容器根目录。
    // MCM 定位需要逐个容器申请租约, 枚举几百个容器较慢, 缓存避免每次下载都重复枚举。
    // (线程安全: 下载回调线程与主线程都会访问)
    private static var cachedRoots: [String: String] = [:]
    private static let lock = NSLock()

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
    static func containerRoot(bundleID: String, fileHandle: FileAccessHandle?) -> String? {
        lookup(bundleID: bundleID, fileHandle: fileHandle).root
    }

    /// 成功定位后登记 UUID → bundle id 映射 (写入层申请租约用, metadata plist 常读不到)
    private static func registerMapping(root: String, bundleID: String) {
        let uuid = (root as NSString).lastPathComponent
        guard uuid.contains("-") else { return }
        lock.lock()
        MCMFileManager.registerUUID(uuid, identifier: bundleID)
        lock.unlock()
    }

    /// 完整定位 + 诊断信息。
    /// 0. 按 bundle id 直接租约 (FilzaSlop 正统用法, 需要 MHA 签名身份) — iOS 26 首选
    /// 1. MCM 枚举 (FilzaSlop)：枚举所有容器 UUID → 逐个租约激活 → 读 metadata plist 匹配包名
    /// 2. 句柄扫描 (FilzaJailedDS)：列 Application 目录 → 逐个读 metadata plist 匹配包名
    static func lookup(bundleID: String, fileHandle: FileAccessHandle?) -> LookupReport {
        var r = LookupReport()

        lock.lock()
        let cached = cachedRoots[bundleID]
        lock.unlock()
        if let hit = cached {
            r.root = hit
            r.notes.append("命中会话缓存")
            registerMapping(root: hit, bundleID: bundleID)
            return r
        }

        // ---- 0. 按 bundle id 直接租约 (FilzaSlop 正统用法, 需要 MHA 签名身份) ----
        // iOS 26 上 MCM 枚举近乎为空, 但按 bundle id 直查始终可用 — 这是原版的第一选择
        r.directTried = true
        let direct = MCMFileManager.shared.obtainLease(identifier: bundleID, containerClass: .appData)
        if let path = direct.path {
            r.root = path
            r.notes.append("bundle id 直查成功")
            lock.lock(); cachedRoots[bundleID] = path; lock.unlock()
            registerMapping(root: path, bundleID: bundleID)
            return r
        } else {
            r.directError = direct.error ?? "未知错误"
            r.notes.append("bundle id 直查失败: \(r.directError)")
        }

        // ---- 1. MCM 枚举路径 ----
        r.mcmAvailable = MCMFileManager.shared.isAvailable
        if r.mcmAvailable {
            let ids = MCMFileManager.shared.enumerateIdentifiers(forClass: .appData, limit: 800)
            r.mcmEnumCount = ids.count
            if ids.isEmpty {
                r.notes.append("MCM 枚举返回 0 个容器 (系统拒绝了枚举请求)")
            }
            for uuid in ids {
                let lease = MCMFileManager.shared.obtainLease(identifier: uuid, containerClass: .appData)
                guard let root = lease.path else { continue }
                r.mcmLeaseOk += 1
                let metadata = (root as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: metadata)),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dict = plist as? [String: Any],
                      let identifier = dict["MCMMetadataIdentifier"] as? String else {
                    continue
                }
                if identifier.hasPrefix("com.tencent"), r.tencentBundles.count < 10 {
                    r.tencentBundles.append(identifier)
                }
                if identifier == bundleID {
                    r.root = root
                    lock.lock(); cachedRoots[bundleID] = root; lock.unlock()
                    registerMapping(root: root, bundleID: bundleID)
                    return r
                }
            }
        } else {
            r.notes.append("MCM bridge 不可用 (当前漏洞方式可能不支持)")
        }

        // ---- 2. 句柄扫描路径 ----
        guard let handle = fileHandle else {
            r.notes.append("无文件句柄, 跳过扫描")
            return r
        }
        r.scanTried = true
        let base = "/var/mobile/Containers/Data/Application"
        do {
            let entries = try handle.listDirectory(at: base)
            r.scanEntryCount = entries.count
            for entry in entries where entry.isDirectory {
                let metadata = (entry.path as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
                guard let data = try? handle.readFile(at: metadata),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dict = plist as? [String: Any],
                      let identifier = dict["MCMMetadataIdentifier"] as? String else {
                    continue
                }
                if identifier.hasPrefix("com.tencent"), r.tencentBundles.count < 10 {
                    r.tencentBundles.append(identifier)
                }
                if identifier == bundleID {
                    r.root = entry.path
                    lock.lock(); cachedRoots[bundleID] = entry.path; lock.unlock()
                    registerMapping(root: entry.path, bundleID: bundleID)
                    return r
                }
            }
        } catch {
            r.scanFailed = true
            r.scanError = error.localizedDescription
        }
        return r
    }
}
