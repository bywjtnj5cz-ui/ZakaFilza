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

    private let fallbackURL = "https://raw.githubusercontent.com/yourname/ZakaFilza/main/config.json"

    private init() {}

    func loadConfig() {
        isLoading = true
        loadError = nil

        // 优先用用户自定义的地址
        let urlString = AppStore.shared.customConfigURL ?? fallbackURL
        guard let url = URL(string: urlString) else {
            loadFallback()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if let data = data, let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
                    self?.config = config
                    // 更新卡密验证服务器地址
                    if let verifyURL = config.verifyServerURL, !verifyURL.isEmpty {
                        LicenseManager.shared.verifyServerURL = verifyURL
                    }
                    self?.isLoading = false
                } else {
                    self?.loadFallback()
                }
            }
        }.resume()
    }

    // 加载内置兜底配置
    private func loadFallback() {
        guard let path = Bundle.main.path(forResource: "default_config", ofType: "json"),
              let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            loadError = "配置加载失败"
            isLoading = false
            return
        }
        self.config = config
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
