import SwiftUI

// MARK: - 卡密验证页
struct LicenseView: View {
    @EnvironmentObject var license: LicenseManager
    @EnvironmentObject var config: ConfigManager
    @State private var cardKey = ""
    @State private var showError = false
    @State private var errorMsg = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.primary)
                .padding(.bottom, 8)

            Text("卡密验证")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("请输入您的卡密以激活应用")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // 卡密输入框
            VStack(spacing: 12) {
                TextField("请输入卡密", text: $cardKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // 验证按钮
            Button(action: verify) {
                HStack {
                    if license.isVerifying {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text(license.isVerifying ? "验证中..." : "验证并激活")
                }
            }
            .buttonStyle(CloudButtonStyle(color: AppTheme.primary))
            .disabled(cardKey.isEmpty || license.isVerifying)
            .padding(.horizontal)

            // 设备信息
            VStack(spacing: 4) {
                Text("设备 UUID:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(DeviceManager.shared.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.top, 20)

            Spacer()

            // 底部信息
            if let cfg = config.config {
                Text("Q群: \(cfg.qqGroup)")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding()
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .alert("验证失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMsg)
        }
    }

    private func verify() {
        errorMsg = ""
        license.verify(cardKey: cardKey) { success, msg in
            if !success {
                errorMsg = msg ?? "验证失败"
                showError = true
            }
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
        .background(.white.opacity(0.9))
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
            .background(isSelected ? AppTheme.primary : Color.white.opacity(0.9))
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
