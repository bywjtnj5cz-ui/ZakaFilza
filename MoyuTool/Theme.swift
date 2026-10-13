import SwiftUI

// 主题色与样式统一管理（默认深空蓝灰配色，可由云端 theme 字段覆盖）
struct AppTheme {
    // 云端主题（若后台配置了则优先使用）
    static var theme: ThemeConfig? {
        ConfigManager.shared.config?.theme
    }

    // 主色 (默认 iOS 系统蓝, 克制不花哨)
    static var primary: Color {
        if let hex = theme?.primary, !hex.isEmpty { return Color(hex: hex) }
        return Color(red: 0.04, green: 0.52, blue: 1.00)
    }

    // 强调色 (默认石墨灰, 用于次要按钮)
    static var accent: Color {
        if let hex = theme?.accent, !hex.isEmpty { return Color(hex: hex) }
        return Color(red: 0.24, green: 0.26, blue: 0.31)
    }

    static var secondary: Color { accent }
    static var success = Color(red: 0.20, green: 0.78, blue: 0.55)   // 更清新的绿
    static var warning = Color(red: 1.00, green: 0.72, blue: 0.20)   // 温暖的橙
    static var danger  = Color(red: 1.00, green: 0.38, blue: 0.42)   // 柔和的红
    static var memberLocked = Color(red: 0.55, green: 0.55, blue: 0.62) // 更有质感的灰

    // 圆角
    static var cornerRadius: CGFloat {
        CGFloat(theme?.cornerRadius ?? 18)
    }

    // 按钮高度
    static var buttonHeight: CGFloat {
        CGFloat(theme?.buttonHeight ?? 52)
    }

    // 字号缩放
    static var fontScale: CGFloat {
        CGFloat(theme?.fontScale ?? 1.0)
    }

    // 卡片透明度
    static var cardOpacity: Double {
        theme?.cardOpacity ?? 0.82
    }

    // 是否深色主题
    static var isDark: Bool {
        theme?.background != "light"
    }

    // 背景渐变（深空蓝灰，高级不庸俗）
    static var backgroundGradient: LinearGradient {
        switch theme?.background ?? "dark" {
        case "light":
            return LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.97, blue: 0.98),
                    Color(red: 0.94, green: 0.94, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default: // dark（默认深空蓝灰）
            return LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.05, green: 0.06, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // 卡片背景色（配合深色/明亮主题）
    static var cardColor: Color {
        isDark ? Color.white.opacity(cardOpacity * 0.12) : Color.white.opacity(cardOpacity)
    }

    // 卡片边框色（增加精致感）
    static var cardBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    // 卡片内发光/阴影混合
    static var cardShadow: Color {
        isDark ? Color.black.opacity(0.45) : Color.black.opacity(0.06)
    }

    // 毛玻璃背景色
    static var glassBackground: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.75)
    }

    // 文字主色
    static var textPrimary: Color {
        isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    // 文字次色
    static var textSecondary: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
    }

    // 主色渐变（按钮用）
    static func primaryGradient(from: Color? = nil) -> LinearGradient {
        let base = from ?? primary
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // 卡片包装器（主题化圆角、背景、边框、阴影）
    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(
                ZStack {
                    cardColor
                    // 微妙的内发光边框
                    RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                        .stroke(cardBorder, lineWidth: 0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous))
            .shadow(color: cardShadow, radius: 12, x: 0, y: 4)
    }
}

// 按钮样式（主题化：渐变 / 高度 / 圆角 / 字号缩放 / 按压反馈）
struct CloudButtonStyle: ButtonStyle {
    var color: Color
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16 * AppTheme.fontScale, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.buttonHeight * 0.30)
            .frame(minHeight: AppTheme.buttonHeight)
            .background(
                ZStack {
                    if disabled {
                        AppTheme.memberLocked
                    } else {
                        AppTheme.primaryGradient(from: color)
                    }
                    // 顶部微妙高光
                    if !disabled {
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(disabled ? 0 : 0.12), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// 毛玻璃卡片样式
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                ZStack {
                    AppTheme.glassBackground
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 3)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
