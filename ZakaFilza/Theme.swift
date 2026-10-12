import SwiftUI

// 主题色与样式统一管理
struct AppTheme {
    // 主色
    static let primary = Color(red: 0.98, green: 0.36, blue: 0.59)       // 粉红
    static let secondary = Color(red: 0.38, green: 0.56, blue: 0.95)     // 蓝
    static let success = Color(red: 0.36, green: 0.78, blue: 0.45)       // 绿
    static let warning = Color(red: 0.95, green: 0.75, blue: 0.20)       // 黄
    static let danger = Color(red: 0.93, green: 0.33, blue: 0.33)        // 红
    static let memberLocked = Color(red: 0.62, green: 0.62, blue: 0.62)  // 灰（未解锁）

    // 背景渐变
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.92, blue: 0.95),
            Color(red: 0.92, green: 0.95, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 按钮圆角
    static let cornerRadius: CGFloat = 16

    // 卡片
    static func cardBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.white.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// 按钮样式
struct CloudButtonStyle: ButtonStyle {
    var color: Color
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(disabled ? AppTheme.memberLocked : color)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
