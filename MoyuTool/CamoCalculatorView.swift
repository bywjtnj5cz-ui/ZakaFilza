import SwiftUI

// MARK: - 伪装计算器页
//
// 几乎像素级复刻 iOS 原生 Calculator:
//   - 深色背景 + 黑色按钮 + 灰色功能键 + 橙色 = 键
//   - 5 行 × 4 列布局，比例 1:1 正方形（根据屏幕宽自适应）
//   - 真实的四则运算 / 正负号 / 百分号功能
//   - 顶部大字体显示当前输入
//   - 额外逻辑：每次按数字键把数字喂给 CamouflageManager，秘密序列命中就切工具页
//
// 注意: 伪装页对用户来说是一个真计算器。不会显示 "触发成功" / "切换中" 之类的提示。

struct CamoCalculatorView: View {
    @EnvironmentObject var camo: CamouflageManager

    // 计算器状态 —— 完全标准 iOS Calculator 行为
    @State private var display: String = "0"
    @State private var previousValue: Double = 0
    @State private var pendingOperator: String? = nil
    @State private var isTypingNewNumber: Bool = true
    @State private var hasError: Bool = false

    private let buttonTitles: [[String]] = [
        ["AC", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", "", ".", "="]
    ]

    var body: some View {
        GeometryReader { geo in
            let columnSpacing: CGFloat = 10
            let rowSpacing: CGFloat = 12
            let sidePadding: CGFloat = 14
            let usableWidth = geo.size.width - sidePadding * 2
            let buttonSize = (usableWidth - columnSpacing * 3) / 4
            let zeroWidth = buttonSize * 2 + columnSpacing

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .trailing, spacing: 0) {
                    // 显示区
                    Spacer(minLength: 20)
                    displayText
                        .padding(.horizontal, sidePadding + 4)
                        .padding(.bottom, 12)

                    // 按钮区
                    ForEach(Array(buttonTitles.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: columnSpacing) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, title in
                                let isZero = (rowIndex == 4 && colIndex == 0)
                                let width = isZero ? zeroWidth : buttonSize

                                // 占位空
                                if title.isEmpty {
                                    Spacer().frame(width: width, height: buttonSize)
                                } else {
                                    calcButton(title: title, width: width, height: buttonSize)
                                }
                            }
                        }
                        .padding(.bottom, rowIndex == buttonTitles.count - 1 ? 0 : rowSpacing)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, sidePadding)
            }
        }
    }

    // MARK: - 显示文字

    private var displayText: some View {
        Text(display)
            .font(.system(size: fontSizeForDisplay(), weight: .regular, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }

    private func fontSizeForDisplay() -> CGFloat {
        let count = display.count
        if count <= 6 { return 96 }
        if count <= 8 { return 80 }
        if count <= 10 { return 68 }
        if count <= 12 { return 56 }
        return 44
    }

    // MARK: - 按钮

    private func calcButton(title: String, width: CGFloat, height: CGFloat) -> some View {
        let isOperator = ["÷", "×", "−", "+", "="].contains(title)
        let isFunction = ["AC", "±", "%"].contains(title)

        let bgColor: Color = isOperator ? .orange
            : isFunction ? Color(white: 0.55)
            : Color(white: 0.20)
        let fgColor: Color = isFunction ? .black : .white

        return Button(action: {
            handlePress(title: title, isOperator: isOperator, isFunction: isFunction)
        }) {
            Text(title)
                .font(.system(size: title == "0" ? 36 : 32, weight: .regular, design: .rounded))
                .foregroundColor(fgColor)
                .frame(width: width, height: height)
                .background(bgColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 处理

    private func handlePress(title: String, isOperator: Bool, isFunction: Bool) {
        if isFunction {
            handleFunction(title)
            return
        }
        if isOperator {
            handleOperator(title)
            return
        }
        // 数字 / 小数点
        let input = title
        // 先喂给伪装管理器（命中即解锁）
        if input != "." {
            _ = camo.appendCalculatorDigit(input)
        }
        handleDigit(input)
    }

    private func handleFunction(_ fn: String) {
        switch fn {
        case "AC":
            display = "0"
            previousValue = 0
            pendingOperator = nil
            isTypingNewNumber = true
            hasError = false
            camo.resetInputBuffer()
        case "±":
            if hasError { return }
            if display != "0", let v = Double(display) {
                display = format(-v)
            }
        case "%":
            if hasError { return }
            if let v = Double(display) {
                display = format(v / 100.0)
            }
        default: break
        }
    }

    private func handleOperator(_ op: String) {
        if hasError { return }
        if op == "=" {
            // 执行之前 pending 算符
            if let pending = pendingOperator, let cur = Double(display) {
                let result = compute(left: previousValue, right: cur, op: pending)
                if result.isNaN || result.isInfinite {
                    display = "错误"
                    hasError = true
                } else {
                    display = format(result)
                    previousValue = result
                }
            }
            pendingOperator = nil
            isTypingNewNumber = true
            return
        }
        // + - × ÷
        if let cur = Double(display) {
            if pendingOperator == nil {
                previousValue = cur
            } else if !isTypingNewNumber, let pending = pendingOperator {
                let result = compute(left: previousValue, right: cur, op: pending)
                if result.isNaN || result.isInfinite {
                    display = "错误"
                    hasError = true
                } else {
                    previousValue = result
                    display = format(result)
                }
            }
        }
        pendingOperator = op
        isTypingNewNumber = true
    }

    private func handleDigit(_ d: String) {
        if hasError {
            // 错误态 → 先按 AC 才能继续
            return
        }
        if d == "." {
            if isTypingNewNumber {
                display = "0."
                isTypingNewNumber = false
            } else if !display.contains(".") {
                display += "."
            }
            return
        }
        if isTypingNewNumber {
            display = d
            isTypingNewNumber = false
        } else {
            // 原生计算器不会限制位数，这里简单限制总长度 12
            if display.count < 12 {
                if display == "0" {
                    display = d
                } else {
                    display += d
                }
            }
        }
    }

    // MARK: - 计算 & 格式化

    private func compute(left: Double, right: Double, op: String) -> Double {
        switch op {
        case "+": return left + right
        case "−": return left - right
        case "×": return left * right
        case "÷": return right == 0 ? Double.nan : left / right
        default: return right
        }
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "错误" }
        // 如果是整数则不带小数点
        if floor(v) == v, abs(v) < 1e16 {
            return String(Int(v))
        }
        // 否则保留最多 10 位小数，并截断尾随零
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: v)) ?? String(v)
    }
}

// MARK: - 预览
#Preview {
    CamoCalculatorView()
        .environmentObject(CamouflageManager.shared)
}
