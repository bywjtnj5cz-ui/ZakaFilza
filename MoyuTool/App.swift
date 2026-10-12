import SwiftUI

@main
struct MoyuToolApp: App {
    @StateObject private var config = ConfigManager.shared
    @StateObject private var exploit = ExploitManager.shared
    @StateObject private var store = AppStore.shared
    @StateObject private var license = LicenseManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
                .environmentObject(exploit)
                .environmentObject(store)
                .environmentObject(license)
                .preferredColorScheme(colorScheme)
        }
    }

    // 颜色方案由云端主题控制 (默认深空极光 = 深色)
    private var colorScheme: ColorScheme? {
        switch config.config?.theme?.background {
        case "light": return .light
        default: return .dark
        }
    }
}

// MARK: - 根视图：完整启动流程
// 加载配置 → 卡密验证 → 系统检测 + 漏洞测试 → 漏洞选择 → 主界面
struct RootView: View {
    @EnvironmentObject var config: ConfigManager
    @EnvironmentObject var exploit: ExploitManager
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var license: LicenseManager

    var body: some View {
        Group {
            if config.isLoading {
                LoadingView(text: "加载配置中...")
            } else if config.updateRequired {
                // 版本封杀: 服务器要求最低版本高于当前版本
                UpdateRequiredView()
            } else if config.isKilled {
                // 急停: 服务器一键停用全体用户
                KillSwitchView()
            } else if !license.isActivated {
                // 卡密验证
                LicenseView()
            } else if exploit.availableExploits.isEmpty || exploit.testResults.isEmpty {
                // 系统检测 + 自动测试漏洞
                SystemCheckView()
            } else if !exploit.hasSelectedExploit {
                // 漏洞选择
                ExploitSelectView()
            } else {
                // 主界面
                HomeView()
            }
        }
        .onAppear {
            config.loadConfig()
            // 静默刷新卡密（快过期时重新验证）
            license.refreshIfNeeded()
        }
    }
}

struct LoadingView: View {
    var text: String = "加载中..."
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(text)
                .font(.headline)
                .foregroundColor(.pink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - 版本封杀锁定页 (服务器下发 min_version 高于当前版本时强制显示)
struct UpdateRequiredView: View {
    @EnvironmentObject var config: ConfigManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.trianglefigure")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("当前版本已停用")
                .font(.title2.bold())
            Text("服务器要求最低版本: v\(config.requiredVersion ?? "最新")\n请联系管理员获取最新版本")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if let qq = config.config?.qqGroup, !qq.isEmpty {
                Text("QQ群: \(qq)")
                    .font(.callout.bold())
                    .foregroundColor(.pink)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - 急停页 (服务器 kill_switch 打开时, 全体用户看到「服务已暂停」)
struct KillSwitchView: View {
    @EnvironmentObject var config: ConfigManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 64))
                .foregroundColor(AppTheme.danger)
            Text("服务已暂停")
                .font(.title.bold())
            Text(config.killMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }
}
