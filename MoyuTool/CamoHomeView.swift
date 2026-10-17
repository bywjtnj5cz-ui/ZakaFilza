import SwiftUI

// MARK: - 伪装模式根视图
//
// 显示 iOS 原生风格 TabBar:
//   · 计算器  — SF Symbol calculator.fill  + label "计算器"
//   · 天气    — SF Symbol cloud.sun.fill   + label "天气"
//
// 外观和 iOS 自带 App 的 TabBar 一模一样（玻璃材质 / SF Symbols / 底部安全区）。
// 没有任何"隐藏入口"、"设置"、"关于"之类的可疑标签 —— 就两个 App。

struct CamoHomeView: View {
    @EnvironmentObject private var camo: CamouflageManager
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: 计算器
            CamoCalculatorView()
                .tabItem {
                    Label("计算器", systemImage: "calculator.fill")
                }
                .tag(0)

            // Tab 1: 天气
            if #available(iOS 16.0, *) {
                CamoWeatherView()
                    .tabItem {
                        Label("天气", systemImage: "cloud.sun.fill")
                    }
                    .tag(1)
            } else {
                Text("")
                    .tabItem {
                        Label("天气", systemImage: "cloud.sun.fill")
                    }
                    .tag(1)
            }
        }
        .tint(.orange) // iOS 原生 TabBar 强调色
        .onAppear {
            // 确保进入伪装模式时重置计算器的"秘密输入"缓冲区，避免用户
            // 在切 Tab 时残留上一轮的部分序列（虽然按 AC 也会清，但这里兜底）
            if camo.isToolMode { camo.resetInputBuffer() }
        }
    }
}

// MARK: - 预览
#Preview {
    CamoHomeView()
        .environmentObject(CamouflageManager.shared)
}
