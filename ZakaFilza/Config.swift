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
    var buttons: [ConfigButton]
    var memberButtons: [ConfigButton]  // 会员专属按钮
    var downloadShortcuts: [DownloadShortcut] // 一键下载直链

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
        case buttons
        case memberButtons = "member_buttons"
        case downloadShortcuts = "download_shortcuts"
    }
}

struct ConfigButton: Codable, Identifiable {
    var id: String { title }
    var title: String
    var action: String          // "open_file_manager" | "download" | "run_script" | "open_url" | "custom"
    var color: String?          // 十六进制颜色，如 "#FF6B9D"
    var downloadURL: String?    // action=download 时的直链
    var scriptPath: String?     // action=run_script 时的脚本路径
    var openURL: String?        // action=open_url 时的链接
    var memberOnly: Bool?       // 是否会员专属
    var params: [String: String]?
}

struct DownloadShortcut: Codable, Identifiable {
    var id: String { name }
    var name: String
    var url: String
    var targetDir: String       // 导入到应用目录的哪个子目录
    var autoImport: Bool        // 下载后是否自动导入
}

// 配置管理器
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: AppConfig?
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var updateRequired = false      // 版本封杀: 当前版本低于服务器 min_version
    @Published var requiredVersion: String?    // 要求的最低版本

    // App 启动时从此地址拉取云端配置 (按钮、下载直链、公告等)
    // 该地址由 verify.php 的 action=config 提供, 可在管理后台修改内容
    private let fallbackURL = "http://156.238.232.172/api/verify.php?action=config"

    private init() {}

    func loadConfig() {
        isLoading = true
        loadError = nil

        // 优先用用户自定义的地址
        let urlString = AppStore.shared.customConfigURL ?? fallbackURL

        // 携带身份参数: 服务端校验 session_token 才下发完整云控配置
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

        guard let url = components?.url else {
            loadFallback()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.loadError = "网络错误: \(error.localizedDescription)"
                    self?.loadFallback()
                    return
                }
                if let data = data, let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
                    self?.config = config
                    // 更新卡密验证服务器地址
                    if let verifyURL = config.verifyServerURL, !verifyURL.isEmpty {
                        LicenseManager.shared.verifyServerURL = verifyURL
                    }
                    self?.applyServerPolicy(config)
                    self?.isLoading = false
                } else {
                    self?.loadError = "响应解析失败"
                    self?.loadFallback()
                }
            }
        }.resume()
    }

    // 服务端管控策略: 版本封杀检查 + 锁定态自愈
    private var lastSelfHealAt: Date = .distantPast

    private func applyServerPolicy(_ c: AppConfig) {
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
