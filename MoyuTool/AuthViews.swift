import SwiftUI

// MARK: - 卡密验证页 (左对齐表单式, 无渐变无大图标)
struct LicenseView: View {
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var config: ConfigManager
    @State private var cardKey = ""
    @State private var errorMsg = ""
    @State private var copiedUUID = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            // 品牌行
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primary)
                Text(config.config?.appName ?? "实用")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 48)

            Text("输入卡密")
                .font(.system(size: 30, weight: .bold))
            Text("激活后立即生效，会员卡绑定一台设备")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            // 卡密输入 + 粘贴
            HStack(spacing: 8) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $cardKey)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("粘贴") {
                    if let s = UIPasteboard.general.string {
                        cardKey = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 28)

            if !errorMsg.isEmpty {
                Label(errorMsg, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.danger)
                    .padding(.top, 12)
            }

            Button(action: verify) {
                HStack {
                    if license.isVerifying { ProgressView().tint(.white) }
                    Text(license.isVerifying ? "验证中" : "激活")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CloudButtonStyle(color: AppTheme.primary,
                                          disabled: cardKey.isEmpty || license.isVerifying))
            .padding(.top, 16)

            Spacer(minLength: 32)

            // 设备码 (购买卡密时需要发给卖家)
            HStack(spacing: 6) {
                Text("设备码")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(DeviceManager.shared.uuid)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Button(copiedUUID ? "已复制" : "复制") {
                    UIPasteboard.general.string = DeviceManager.shared.uuid
                    copiedUUID = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedUUID = false }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.primary)
            }
            .padding(.top, 16)

            // 底部信息 (云端配置, 留空隐藏)
            if let cfg = config.config {
                let contact = [cfg.qqGroup, cfg.wechatOfficial].compactMap { $0.isEmpty ? nil : $0 }.joined(separator: "  ·  ")
                if !contact.isEmpty {
                    Text(contact)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 16)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(AppTheme.isDark ? .dark : .light)
    }

    private func verify() {
        errorMsg = ""
        let key = cardKey.trimmingCharacters(in: .whitespacesAndNewlines)
        license.verify(cardKey: key) { success, msg in
            if !success { errorMsg = msg ?? "验证失败" }
        }
    }
}

// MARK: - 系统检测 + 漏洞测试页
struct SystemCheckView: View {
    @EnvironmentObject var exploit: ExploitManager
    @EnvironmentObject var config: ConfigManager
    @State private var showExploitSelect = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 系统信息卡片
                systemInfoCard

                // 自动测试按钮
                autoTestButton

                // 可用漏洞列表
                VStack(alignment: .leading, spacing: 12) {
                    Text("可用漏洞（\(exploit.availableExploits.count)）")
                        .font(.headline)

                    if exploit.availableExploits.isEmpty {
                        Text("当前系统版本 \(DeviceManager.shared.systemVersion) 暂无可匹配的漏洞")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(exploit.availableExploits) { info in
                            exploitTestCard(info: info)
                        }
                    }
                }

                // 进入主界面
                if exploit.hasSelectedExploit {
                    Button(action: { showExploitSelect = true }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("进入文件管理")
                        }
                    }
                    .buttonStyle(CloudButtonStyle(color: AppTheme.success))
                    .padding(.horizontal)
                }
            }
            .padding()
        }
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("系统检测")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showExploitSelect) {
            ExploitSelectView()
        }
        .onAppear {
            // 自动测试所有漏洞
            if exploit.testResults.isEmpty {
                exploit.autoTestAllExploits {}
            }
        }
    }

    private var systemInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone.gen3")
                    .font(.title2)
                    .foregroundColor(AppTheme.primary)
                Text("设备信息")
                    .font(.headline)
                Spacer()
                if DeviceManager.shared.isJailbroken {
                    Text("越狱")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }

            Divider()

            infoRow("系统", "\(DeviceManager.shared.systemName) \(DeviceManager.shared.systemVersion)")
            infoRow("型号", DeviceManager.shared.model)
            infoRow("UUID", DeviceManager.shared.uuid)
            infoRow("最低支持", "iOS 15.0")
        }
        .padding(16)
        .background(AppTheme.cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var autoTestButton: some View {
        Button(action: { exploit.autoTestAllExploits {} }) {
            HStack {
                if exploit.isAutoTesting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "bolt.fill")
                }
                Text(exploit.isAutoTesting ? "测试中..." : "一键测试所有漏洞")
            }
        }
        .buttonStyle(CloudButtonStyle(color: AppTheme.secondary))
        .disabled(exploit.isAutoTesting)
    }

    private func exploitTestCard(info: ExploitInfo) -> some View {
        let result = exploit.testResults[info.id] ?? .notTested
        let isSelected = exploit.selectedExploitId == info.id

        return Button(action: {
            exploit.selectExploit(id: info.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: info.icon)
                        .foregroundColor(isSelected ? .white : AppTheme.primary)
                    Text(info.name)
                        .font(.headline)
                        .foregroundColor(isSelected ? .white : .primary)
                    Spacer()
                    testResultBadge(result)
                }

                Text(info.description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                Text(info.supportedVersions)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .gray)

                // 测试结果说明
                if case .unavailable(let msg) = result {
                    Text("⚠️ \(msg)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .orange)
                }
                if case .available(let msg) = result {
                    Text("✅ \(msg)")
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.9) : .green)
                }

                // 手动测试按钮
                HStack {
                    Button(action: {
                        exploit.testExploit(id: info.id) { _, _ in }
                    }) {
                        Text("测试")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                            .foregroundColor(isSelected ? .white : .blue)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(14)
            .background(isSelected ? AppTheme.primary : AppTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func testResultBadge(_ result: ExploitTestResult) -> some View {
        switch result {
        case .notTested:
            Text("未测试")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.gray)
                .clipShape(Capsule())
        case .testing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("测试中")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.yellow.opacity(0.2))
            .foregroundColor(.yellow)
            .clipShape(Capsule())
        case .available:
            Text("✓ 可用")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .clipShape(Capsule())
        case .unavailable:
            Text("✗ 不可用")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .clipShape(Capsule())
        }
    }
}
