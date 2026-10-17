import SwiftUI

@main
struct MoyuToolApp: App {
    @StateObject private var config = ConfigManager.shared
    @StateObject private var exploit = ExploitManager.shared
    @StateObject private var store = AppStore.shared
    @StateObject private var license = LicenseManager.shared
    @StateObject private var camo = CamouflageManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(config)
                .environmentObject(exploit)
                .environmentObject(store)
                .environmentObject(license)
                .environmentObject(camo)
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

// MARK: - 根视图：完整启动流程 + 伪装层覆盖
//
// 底层: 工具启动链 (加载配置 → 卡密 → 漏洞选择 → HomeView) —— 原逻辑一字未改
// 顶层: CamoHomeView（天气 + 计算器 TabBar），仅当 camo.isToolMode == false 时显示
//       解锁后用 opacity + transition 淡出工具模式，给用户瞬间切换的感觉
struct RootView: View {
    @EnvironmentObject var config: ConfigManager
    @EnvironmentObject var exploit: ExploitManager
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var camo: CamouflageManager

    var body: some View {
        ZStack {
            // 底层: 原工具启动链（永远完整挂载，保证配置/卡密/漏洞管理器在后台就绪）
            toolLaunchChain
                .environment(\.colorScheme, .dark)
                .opacity(camo.isToolMode ? 1 : 0)
                .allowsHitTesting(camo.isToolMode)
                .animation(.easeInOut(duration: 0.35), value: camo.isToolMode)

            // 顶层: 伪装 App（TabBar 天气 + 计算器）。未解锁时独占全屏
            if !camo.isToolMode {
                CamoHomeView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            config.loadConfig()
            license.refreshIfNeeded()
        }
    }

    // MARK: - 工具启动链（和以前一模一样，没改动）
    @ViewBuilder
    private var toolLaunchChain: some View {
        if config.isLoading {
            LoadingView(text: "加载配置中...")
        } else if config.updateRequired {
            UpdateRequiredView()
        } else if config.isKilled {
            KillSwitchView()
        } else if !license.isActivated {
            LicenseView()
        } else if exploit.availableExploits.isEmpty || exploit.testResults.isEmpty {
            SystemCheckView()
        } else if !exploit.hasSelectedExploit {
            ExploitSelectView()
        } else {
            HomeView()
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
