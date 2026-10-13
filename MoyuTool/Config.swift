import Foundation
import SwiftUI

// 云端配置数据模型
struct AppConfig: Codable {
    var appName: String
    var qqGroup: String
    var wechatOfficial: String
    var version: String
    var announcement: String
    var configURL: String              // 云端配置地址（可被「更新地址」覆盖）
    var verifyServerURL: String?       // 卡密验证服务器地址
    var minVersion: String?            // 最低可用版本 (版本封杀开关)
    var locked: Bool?                  // true = 服务端未授权 (无有效卡密/token)
    var lockedReason: String?          // 锁定原因 (服务端诊断用, 不泄露敏感数据)
    var theme: ThemeConfig?            // 外观主题 (云端控制)
    var killSwitch: Bool?              // 急停开关: true = 全体停用
    var killMessage: String?           // 急停文案
    var sources: [String]?             // 备用线路 (主线路挂了自动切换)
    var buttons: [ConfigButton]
    var memberButtons: [ConfigButton]  // 会员专属按钮
    var downloadShortcuts: [DownloadShortcut] // 一键下载直链
    var gameDirs: GameDirsConfig?      // 游戏目录定位 (和平精英等)
    var banners: [Banner]?             // 首页轮播图
    var autoBeautify: AutoBeautifyConfig? // 启动自动美化 (自动下载导入配置包)
    var categories: [ConfigCategory]?  // 配置分类树 (美化 / 画质 / 功能)

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case qqGroup = "qq_group"
        case wechatOfficial = "wechat_official"
        case version
        case announcement
        case configURL = "config_url"
        case verifyServerURL = "verify_server_url"
        case minVersion = "min_version"
        case locked
        case lockedReason = "locked_reason"
        case theme
        case killSwitch = "kill_switch"
        case killMessage = "kill_message"
        case sources
        case buttons
        case memberButtons = "member_buttons"
        case downloadShortcuts = "download_shortcuts"
        case gameDirs = "game_dirs"
        case banners
        case autoBeautify = "auto_beautify"
        case categories
    }
}

// 游戏目录定位配置 (云端控制, 客户端只按 bundle id 解析容器根路径)
struct GameDirsConfig: Codable {
    var bundleID: String          // 目标 App 包名, 如 com.tencent.tmgp.pubgmhd
    var savedRel: String?         // "Saved" 目录相对容器根的路径, 如 Documents/ShadowTrackerExtra/Saved
    var targets: [GameDirTarget]  // 可选子目录列表

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case savedRel = "saved_rel"
        case targets
    }
}

struct GameDirTarget: Codable, Identifiable {
    var id: String { key }
    var key: String     // 唯一标识, 供 @game:<key> 引用
    var label: String   // 显示名
    var rel: String     // 相对 savedRel 的子路径

    enum CodingKeys: String, CodingKey {
        case key
        case label
        case rel
    }
}

// 云端主题配置 (后台 🎨 外观主题)
struct ThemeConfig: Codable {
    var primary: String?       // 主色
    var accent: String?        // 强调色
    var background: String?    // 背景风格: "aurora" | "light" | "dark"
    var cornerRadius: Double?  // 圆角
    var buttonHeight: Double?  // 按钮高度
    var fontScale: Double?     // 字号缩放
    var cardOpacity: Double?   // 卡片透明度

    enum CodingKeys: String, CodingKey {
        case primary
        case accent
        case background
        case cornerRadius = "corner_radius"
        case buttonHeight = "button_height"
        case fontScale = "font_scale"
        case cardOpacity = "card_opacity"
    }
}

struct ConfigButton: Codable, Identifiable {
    var id: String { title }
    var title: String
    var action: String          // "open_file_manager" | "download" | "run_script" | "open_url" | "custom"
    var color: String?          // 十六进制颜色，如 "#FF6B9D"
    var downloadURL: String?    // action=download 时的直链
    var scriptPath: String?     // action=run_script 时的远端脚本路径 (兼容旧配置)
    var script: String?         // action=run_script 时的内联脚本 (云端直发)
    var openURL: String?        // action=open_url 时的链接
    var memberOnly: Bool?       // 是否会员专属
    var minMemberLevel: Int?    // 最低会员等级: 不设=按 memberOnly; 1=会员及以上; 2=仅耳机
    var shortcut: String?       // 快捷键, 如 "cmd+1" / "shift+r" / "opt+space"
    var confirmText: String?    // 二次确认文案 (留空则不确认)
    var path: String?           // 点按钮直接跳到该目录
    var paths: [String]?        // 路径数组 (uninstall 等批量操作使用)
    var params: [String: String]? // 其它参数 (如 target_dir)
    var unzip: Bool?            // true = 下载后解压导入包内文件 (zip 用)

    // 实际所需等级: min_member_level 优先, 否则 member_only=true → 1, 否则 0
    var requiredLevel: Int {
        minMemberLevel ?? ((memberOnly ?? false) ? 1 : 0)
    }

    enum CodingKeys: String, CodingKey {
        case title
        case action
        case color
        case downloadURL = "download_url"
        case scriptPath = "script_path"
        case script
        case openURL = "open_url"
        case memberOnly = "member_only"
        case minMemberLevel = "min_member_level"
        case shortcut
        case confirmText = "confirm_text"
        case path
        case paths
        case params
        case unzip
    }
}

struct DownloadShortcut: Codable, Identifiable {
    var id: String { name }
    var name: String
    var url: String
    var targetDir: String       // 导入到应用目录的哪个子目录
    var autoImport: Bool        // 下载后是否自动导入

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case targetDir = "target_dir"
        case autoImport = "auto_import"
    }
}

// 首页轮播图 (image_url 图片直链, link_url 点击跳转, title 覆盖文字可留空)
struct Banner: Codable, Identifiable {
    var id: String { imageURL + (linkURL ?? "") + (title ?? "") }
    var imageURL: String
    var linkURL: String?
    var title: String?

    enum CodingKeys: String, CodingKey {
        case imageURL = "image_url"
        case linkURL = "link_url"
        case title
    }
}

// 启动自动美化配置
struct AutoBeautifyConfig: Codable {
    var enabled: Bool
    var categoryID: String?     // 为空则按 file_id 匹配
    var fileID: String?         // 配置包 id (对应 categories[].files[].id)

    enum CodingKeys: String, CodingKey {
        case enabled
        case categoryID = "category_id"
        case fileID = "file_id"
    }
}

// 配置分类 (树节点)
struct ConfigCategory: Codable, Identifiable {
    var id: String
    var title: String
    var type: String
    var icon: String?           // SF Symbol 名称, 可空
    var memberOnly: Bool        // 会员专属分类 (未解锁置灰)
    var minMemberLevel: Int?    // 最低会员等级: 不设=按 memberOnly; 1=会员及以上; 2=仅耳机
    var files: [ConfigFileItem]

    // 实际所需等级: min_member_level 优先, 否则 member_only=true → 1, 否则 0
    var requiredLevel: Int {
        minMemberLevel ?? (memberOnly ? 1 : 0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case icon
        case memberOnly = "member_only"
        case minMemberLevel = "min_member_level"
        case files
    }
}

// 分类下的配置包 (文件卡片)
struct ConfigFileItem: Codable, Identifiable {
    var id: String
    var name: String
    var desc: String?
    var downloadURL: String
    var targetDir: String       // 如 "@game:paks" 或绝对路径
    var size: String?
    var version: String?
    var icon: String?
    var unzip: Bool?            // true = 下载后解压, 导入包内文件 (zip 美化包用)

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case desc
        case downloadURL = "download_url"
        case targetDir = "target_dir"
        case size
        case version
        case icon
        case unzip
    }
}

// 配置管理器
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig?
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var updateRequired = false      // 版本封杀: 当前版本低于服务器 min_version
    @Published var requiredVersion: String?    // 要求的最低版本
    @Published var isKilled = false            // 急停: 服务器一键停用全体用户
    @Published var killMessage: String = "服务已暂停"  // 急停文案

    // App 启动时从此地址拉取云端配置 (按钮、下载直链、公告等)
    // 该地址由 verify.php 的 action=config 提供, 可在管理后台修改内容
    private let fallbackURL = "http://156.238.232.172/api/verify.php?action=config"

    private init() {}

    func loadConfig() {
        isLoading = true
        loadError = nil

        // 主线路 + 备用线路 (sources), 主线路挂了自动切换到下一条
        var urls: [String] = [AppStore.shared.customConfigURL ?? fallbackURL]
        if let cached = config, let srcs = cached.sources {
            for s in srcs where !s.isEmpty && !urls.contains(s) {
                urls.append(s)
            }
        }
        fetchConfig(fromSources: urls, index: 0)
    }

    // 逐条尝试配置线路, 全部失败才落到内置兜底
    private func fetchConfig(fromSources urls: [String], index: Int) {
        guard index < urls.count else {
            loadFallback()
            return
        }
        guard let url = configRequestURL(urls[index]) else {
            fetchConfig(fromSources: urls, index: index + 1)
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.loadError = "网络错误: \(error.localizedDescription)"
                    self?.fetchConfig(fromSources: urls, index: index + 1)
                    return
                }
                if let data = data, let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
                    self?.apply(config)
                } else {
                    self?.loadError = "响应解析失败"
                    self?.fetchConfig(fromSources: urls, index: index + 1)
                }
            }
        }.resume()
    }

    // 携带身份参数构建请求地址: 服务端校验 session_token 才下发完整云控配置
    private func configRequestURL(_ urlString: String) -> URL? {
        var components = URLComponents(string: urlString)
        var query = components?.queryItems ?? []
        let lm = LicenseManager.shared
        if let ck = lm.cardKey, !ck.isEmpty {
            query.append(URLQueryItem(name: "card_key", value: ck))
        }
        if let tk = lm.sessionToken, !tk.isEmpty {
            query.append(URLQueryItem(name: "token", value: tk))
        }
        query.append(URLQueryItem(name: "uuid", value: DeviceManager.shared.uuid))
        components?.queryItems = query
        return components?.url
    }

    private func apply(_ config: AppConfig) {
        self.config = config
        // 更新卡密验证服务器地址
        if let verifyURL = config.verifyServerURL, !verifyURL.isEmpty {
            LicenseManager.shared.verifyServerURL = verifyURL
        }
        applyServerPolicy(config)
        isLoading = false
    }

    // 服务端管控策略: 版本封杀检查 + 锁定态自愈
    private var lastSelfHealAt: Date = .distantPast

    private func applyServerPolicy(_ c: AppConfig) {
        // 急停: 一键停用全体用户 (优先级最高)
        isKilled = (c.killSwitch == true)
        if isKilled {
            killMessage = c.killMessage ?? "服务已暂停"
        }

        // 锁定态自愈: 已激活但被服务器判定未授权
        //   (旧缓存缺 session_token / token 因服务器 secret 变更而失效)
        // → 静默重新验证拿新 token, 验证成功后 verify 内部会自动重拉配置
        // 60 秒内只自愈一次, 防止服务器持续拒绝时无限循环请求
        if c.locked == true,
           LicenseManager.shared.isActivated,
           Date().timeIntervalSince(lastSelfHealAt) > 60 {
            lastSelfHealAt = Date()
            LicenseManager.shared.refreshIfNeeded(force: true)
            return
        }
        if let minV = c.minVersion, !minV.isEmpty {
            let current = Version(currentAppVersion())
            if current < Version(minV) {
                updateRequired = true
                requiredVersion = minV
                return
            }
        }
        updateRequired = false
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // 加载内置兜底配置 (编译进二进制的字符串常量, IPA 内无明文 json)
    private func loadFallback() {
        guard let data = BundledResources.defaultConfigJSON.data(using: .utf8),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            loadError = "配置加载失败"
            isLoading = false
            return
        }
        self.config = config
        // 兜底路径同样要应用验证服务器地址
        if let verifyURL = config.verifyServerURL, !verifyURL.isEmpty {
            LicenseManager.shared.verifyServerURL = verifyURL
        }
        isLoading = false
    }

    // 更新配置地址
    func updateConfigURL(_ url: String) {
        AppStore.shared.customConfigURL = url
        loadConfig()
    }
}

// 颜色解析
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
