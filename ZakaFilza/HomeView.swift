import SwiftUI

// 主界面：按钮全部由云端配置驱动
struct HomeView: View {
    @EnvironmentObject var config: ConfigManager
    @EnvironmentObject var exploit: ExploitManager
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var license: LicenseManager

    @State private var showFileManager = false
    @State private var showUpdateURL = false
    @State private var showAnnouncement = false
    @State private var toastMsg = ""
    @State private var showToast = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 头部卡片
                    headerCard

                    // 按钮网格
                    if let cfg = config.config {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(cfg.buttons) { btn in
                                cloudButton(btn)
                            }
                        }

                        // 会员按钮（未激活时显示为灰色）
                        if !cfg.memberButtons.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(cfg.memberButtons) { btn in
                                    cloudButton(btn, isMember: true)
                                }
                            }
                        }
                    }

                    // 底部信息
                    footerInfo

                    // 手动刷新云控配置 (加载不出按钮时可点此重试)
                    Button {
                        config.loadConfig()
                        toastMsg = "正在刷新配置…"
                        withAnimation { showToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showToast = false }
                        }
                    } label: {
                        Label("刷新配置", systemImage: "arrow.clockwise")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationDestination(isPresented: $showFileManager) {
                FileManagerView()
            }
            .alert("更新配置地址", isPresented: $showUpdateURL) {
                TextField("配置 URL", text: Binding(
                    get: { store.customConfigURL ?? "" },
                    set: { store.customConfigURL = $0 }
                ))
                Button("更新") {
                    if let url = store.customConfigURL, !url.isEmpty {
                        config.updateConfigURL(url)
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("公告", isPresented: $showAnnouncement) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(config.config?.announcement ?? "")
            }
            .overlay(
                Group {
                    if showToast {
                        Text(toastMsg)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .padding(.bottom, 40)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: showToast),
                alignment: .bottom
            )
        }
    }

    // MARK: - 头部卡片
    private var headerCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text(config.config?.appName ?? "Zaka文件管理")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary)
                Spacer()
                if !(config.config?.announcement.isEmpty ?? true) {
                    Button(action: { showAnnouncement = true }) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                    }
                }
            }

            if let cfg = config.config {
                Text("Q群: \(cfg.qqGroup)  公众号: \(cfg.wechatOfficial)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("系统: iOS \(store.systemVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("版本: \(cfg.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                // 卡密状态
                HStack(spacing: 6) {
                    Image(systemName: license.isActivated ? "checkmark.seal.fill" : "exclamationmark.seal")
                        .foregroundColor(license.isActivated ? .green : .orange)
                    Text("卡密: \(license.isActivated ? "有效至 \(license.expireText)" : "未激活")")
                        .font(.caption)
                        .foregroundColor(license.isActivated ? .green : .orange)
                }
                // 当前漏洞
                if let exploitName = exploit.availableExploits.first(where: { $0.id == exploit.selectedExploitId })?.name {
                    Text("漏洞: \(exploitName)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - 云端按钮
    private func cloudButton(_ btn: ConfigButton, isMember: Bool = false) -> some View {
        let locked = isMember && !store.memberActivated
        let color = btn.color.flatMap { Color(hex: $0) } ?? AppTheme.primary

        return Button(action: { handleButton(btn) }) {
            Text(btn.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(locked ? AppTheme.memberLocked : color)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    locked ?
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("会员")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    : nil,
                    alignment: .topTrailing
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(locked)
    }

    // MARK: - 按钮动作处理
    private func handleButton(_ btn: ConfigButton) {
        switch btn.action {
        case "open_file_manager":
            showFileManager = true

        case "download":
            if let url = btn.downloadURL {
                downloadFile(url: url, filename: btn.title)
            }

        case "update_url":
            showUpdateURL = true

        case "run_script":
            if let scriptPath = btn.scriptPath {
                runScript(scriptPath)
            }

        case "open_url":
            if let url = btn.openURL, let link = URL(string: url) {
                UIApplication.shared.open(link)
            }

        case "activate_member":
            store.memberActivated = true
            showToast("会员已激活")

        case "uninstall":
            uninstallBeautification()

        default:
            showToast("按钮: \(btn.title)")
        }
    }

    // MARK: - 下载文件
    private func downloadFile(url: String, filename: String) {
        showToast("开始下载: \(filename)")
        guard let link = URL(string: url) else {
            showToast("URL 无效")
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(filename)

        URLSession.shared.downloadTask(with: link) { tempURL, _, error in
            if let error = error {
                DispatchQueue.main.async { showToast("下载失败: \(error.localizedDescription)") }
                return
            }
            guard let tempURL = tempURL else { return }
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                DispatchQueue.main.async { showToast("下载完成: \(filename)") }
            } catch {
                DispatchQueue.main.async { showToast("保存失败: \(error.localizedDescription)") }
            }
        }.resume()
    }

    // MARK: - 运行脚本
    private func runScript(_ path: String) {
        showToast("执行脚本: \(path)")
        // 通过 ScriptRunner 执行
        // 此处可接入 JavaScriptCore 执行逻辑
    }

    // MARK: - 卸载美化
    private func uninstallBeautification() {
        showToast("卸载中...")
        // 实际逻辑：删除游戏目录下的美化文件
    }

    // MARK: - 底部
    private var footerInfo: some View {
        VStack(spacing: 8) {
            Text("UUID: \(store.deviceUUID)")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
            Text("当前漏洞: \(exploit.selectedExploitId ?? "未选择")")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
            // 注销卡密按钮
            Button(action: {
                license.logout()
            }) {
                Text("注销卡密")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.6))
            }
        }
        .padding(.top, 20)
    }

    private func showToast(_ msg: String) {
        toastMsg = msg
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }
}
