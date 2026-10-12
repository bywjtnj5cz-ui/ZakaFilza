import SwiftUI

// 主题色与样式统一管理（默认深空极光配色，可由云端 theme 字段覆盖）
struct AppTheme {
    // 云端主题（若后台配置了则优先使用）
    static var theme: ThemeConfig? {
        ConfigManager.shared.config?.theme
    }

    // 主色
    static var primary: Color {
        if let hex = theme?.primary, !hex.isEmpty { return Color(hex: hex) }
        return Color(red: 0.49, green: 0.30, blue: 1.00)       // 紫色
    }

    // 强调色
    static var accent: Color {
        if let hex = theme?.accent, !hex.isEmpty { return Color(hex: hex) }
        return Color(red: 0.00, green: 0.90, blue: 1.00)        // 霓虹青
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

    // 背景渐变（三种风格：极光 / 明亮 / 纯黑）
    static var backgroundGradient: LinearGradient {
        switch theme?.background ?? "aurora" {
        case "light":
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.92, blue: 0.95),
                    Color(red: 0.92, green: 0.95, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "dark":
            return LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.06),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default: // aurora（深空极光）
            return LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.16),
                    Color(red: 0.12, green: 0.07, blue: 0.28),
                    Color(red: 0.04, green: 0.10, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
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