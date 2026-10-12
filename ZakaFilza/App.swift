import SwiftUI

@main
struct ZakaFilzaApp: App {
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
                .preferredColorScheme(.light)
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
