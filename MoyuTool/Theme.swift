import SwiftUI

// 主题色与样式统一管理（默认深空极光配色，可由云端 theme 字段覆盖）
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
        return Color(red: 0.22, green: 0.24, blue: 0.29)
    }

    static var secondary: Color { accent }
    static var success = Color(red: 0.36, green: 0.78, blue: 0.45)  // 绿
    static var warning = Color(red: 1.00, green: 0.70, blue: 0.15)  // 橙
    static var danger  = Color(red: 0.96, green: 0.33, blue: 0.36)  // 红
    static var memberLocked = Color(red: 0.45, green: 0.45, blue: 0.52) // 灰（未解锁）

    // 圆角
    static var cornerRadius: CGFloat {
        CGFloat(theme?.cornerRadius ?? 16)
    }

    // 按钮高度
    static var buttonHeight: CGFloat {
        CGFloat(theme?.buttonHeight ?? 54)
    }

    // 字号缩放
    static var fontScale: CGFloat {
        CGFloat(theme?.fontScale ?? 1.0)
    }

    // 卡片透明度
    static var cardOpacity: Double {
        theme?.cardOpacity ?? 0.85
    }

    // 是否深色主题
    static var isDark: Bool {
        theme?.background != "light"
    }

    // 背景渐变（三种风格：深灰 / 明亮 / 纯黑；默认深灰近纯色, 不抢内容）
    static var backgroundGradient: LinearGradient {
        switch theme?.background ?? "dark" {
        case "light":
            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.96, blue: 0.97),
                    Color(red: 0.93, green: 0.93, blue: 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case "aurora":
            // 兼容旧配置: 极光渐变收敛为更暗的同色系, 去掉紫
            return LinearGradient(
                colors: [
                    Color(red: 0.043, green: 0.051, blue: 0.071),
                    Color(red: 0.063, green: 0.075, blue: 0.106),
                    Color(red: 0.043, green: 0.051, blue: 0.071)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default: // dark（默认深灰）
            return LinearGradient(
                colors: [
                    Color(red: 0.043, green: 0.051, blue: 0.071),
                    Color(red: 0.063, green: 0.075, blue: 0.106),
                    Color(red: 0.043, green: 0.051, blue: 0.071)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // 卡片背景色（配合深色/明亮主题）
    static var cardColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.90)
    }

    // 卡片（主题化圆角与透明度）
    static func cardBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(cardColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.06), radius: 8, y: 2)
    }
}

// 按钮样式（主题化：颜色 / 高度 / 圆角 / 字号缩放）
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
            .background(disabled ? AppTheme.memberLocked : color)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}