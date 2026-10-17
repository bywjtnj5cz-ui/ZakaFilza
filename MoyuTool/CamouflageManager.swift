import Foundation
import SwiftUI
import Combine

// MARK: - 伪装/工具模式管理器
//
// App 有两种运行模式：
//   1. camouflage（默认冷启动） — 显示 iOS 原生风格伪装页（天气 + 计算器 TabBar），
//      对路人/监管/非授权用户看起来就是个普通 App
//   2. tool（秘密解锁后）       — 完全覆盖成原工具 UI，所有 exploit / 文件管理 /
//      卡密功能原样保留，一个字节都没改
//
// 秘密入口（计算器）:
//   伪装首页 → 切到计算器 Tab → 依次按下 1 3 1 3 7 8 7 8 → 解锁
//   全程计算器表现完全正常，不会闪一下或报错，用户只是"输对了一串数字"
//
// 反侦察设计:
//   - isToolMode 持久化到 UserDefaults；冷启动时若已解锁，直接进工具页
//     （对授权用户来说体验更顺，同时防止反复进伪装页又解锁）
//   - 伪装页的计算器是真计算器（加减乘除正常算），天气页是真动态数据
//   - 秘密口令只有一个硬编码常量，不在 Info.plist / 网络 / 日志里出现

final class CamouflageManager: ObservableObject {
    static let shared = CamouflageManager()

    /// 解锁后的常驻标记
    private let toolModeKey = "com.zaka.tool_mode_unlocked"

    /// 解锁口令
    static let secretCode = "13137878"

    /// 是否处于工具模式（true = 覆盖显示工具 UI）
    @Published var isToolMode: Bool

    /// 上一次用户在计算器里输入的数字序列（隐藏）
    @Published var calculatorInputBuffer: String = ""

    private init() {
        self.isToolMode = UserDefaults.standard.bool(forKey: toolModeKey)
    }

    // MARK: - 解锁 / 锁定

    /// 输入口令，返回是否命中
    @discardableResult
    func appendCalculatorDigit(_ digit: String) -> Bool {
        calculatorInputBuffer.append(digit)
        // 保留与 secretCode 等长的前缀，超过就整体右移（比如用户输多了 1 位，变成 "3137878X" 再对比）
        if calculatorInputBuffer.count > CamouflageManager.secretCode.count {
            calculatorInputBuffer = String(
                calculatorInputBuffer.suffix(CamouflageManager.secretCode.count)
            )
        }
        if calculatorInputBuffer == CamouflageManager.secretCode {
            unlock()
            return true
        }
        return false
    }

    func unlock() {
        withAnimation(.easeInOut(duration: 0.35)) {
            isToolMode = true
        }
        UserDefaults.standard.set(true, forKey: toolModeKey)
        calculatorInputBuffer = ""
    }

    /// 从工具页手动锁回伪装模式（调试/需要清场时用）
    func lockBack() {
        withAnimation(.easeInOut(duration: 0.35)) {
            isToolMode = false
        }
        UserDefaults.standard.set(false, forKey: toolModeKey)
    }

    /// 计算器按 AC/清空 时重置输入缓冲区
    func resetInputBuffer() {
        calculatorInputBuffer = ""
    }
}
