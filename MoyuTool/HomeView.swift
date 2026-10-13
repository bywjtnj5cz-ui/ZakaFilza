import SwiftUI
import UIKit

// 主界面：按钮、联系方式、状态、诊断全部由云端配置驱动
struct HomeView: View {
    @EnvironmentObject var config: ConfigManager
    @EnvironmentObject var exploit: ExploitManager
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var license: LicenseManager

    @State private var showFileManager = false
    @State private var toastMsg = ""
    @State private var showToast = false
    @State private var activeSheet: HomeSheet?
    @State private var activeAlert: HomeAlert?
    @State private var scriptLogText = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    // 按钮网格
                    if let cfg = config.config {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(cfg.buttons) { btn in
                                cloudButton(btn)
                            }
                        }

                        // 会员按钮（未解锁时显示为灰色）
                        if !cfg.memberButtons.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(cfg.memberButtons) { btn in
                                    cloudButton(btn, isMember: true)
                                }
                            }
                        }
                    }

                    // 联系方式卡片（QQ群 / 公众号，云端配置，留空自动隐藏）
                    contactCard

                    // 底部信息
                    footerInfo
                }
                .padding()
            }
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationDestination(isPresented: $showFileManager) {
                FileManagerView()
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .announcement:
                    return Alert(
                        title: Text("公告"),
                        message: Text(config.config?.announcement ?? ""),
                        dismissButton: .default(Text("知道了"))
                    )
                case .confirm(let btn):
                    return Alert(
                        title: Text(btn.title),
                        message: Text(btn.confirmText ?? ""),
                        primaryButton: .destructive(Text("确认")) { executeAction(btn) },
                        secondaryButton: .cancel(Text("取消"))
                    )
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .diagnostic:
                    diagnosticSheet
                case .scriptLog:
                    scriptLogSheet
                case .updateURL:
                    updateURLSheet
                }
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

    // MARK: - 头部卡片（含状态条，长按打开诊断）
    private var headerCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text(config.config?.appName ?? "墨鱼Tool")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary)
                Spacer()
                if !(config.config?.announcement.isEmpty ?? true) {
                    Button(action: { activeAlert = .announcement }) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                    }
                }
            }

            if let cfg = config.config {
                // 状态条：卡密状态 + 当前漏洞链
                statusBar
                Text("版本: \(cfg.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
        .shadow(color: .black.opacity(AppTheme.isDark ? 0.35 : 0.06), radius: 8, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
        .onLongPressGesture {
            activeSheet = .diagnostic
        }
    }

    // 状态条：卡密状态 + 当前漏洞链
    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: license.isActivated ? "checkmark.seal.fill" : "exclamationmark.seal")
                    .foregroundColor(license.isActivated ? .green : .orange)
                Text(license.isActivated ? "卡密有效至 \(license.expireText)" : "卡密未激活")
                    .foregroundColor(license.isActivated ? .green : .orange)
            }
            .font(.caption)

            Spacer()

            if let name = exploit.availableExploits.first(where: { $0.id == exploit.selectedExploitId })?.name {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .foregroundColor(AppTheme.accent)
                    Text(name)
                        .foregroundColor(AppTheme.accent)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.black.opacity(AppTheme.isDark ? 0.25 : 0.04))
        .clipShape(Capsule())
    }

    // MARK: - 云端按钮
    private func cloudButton(_ btn: ConfigButton, isMember: Bool = false) -> some View {
        let locked = isMember && !store.memberActivated
        let color = btn.color.flatMap { Color(hex: $0) } ?? AppTheme.primary

        return Button(action: { handleButton(btn) }) {
            ZStack(alignment: .bottomTrailing) {
                Text(btn.title)
                    .font(.system(size: 15 * AppTheme.fontScale, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.buttonHeight * 0.30)
                    .frame(minHeight: AppTheme.buttonHeight)

                // 快捷键小标签（接键盘设备起提示作用）
                if let sc = shortcutLabel(btn.shortcut) {
                    Text(sc)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.28))
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .background(locked ? AppTheme.memberLocked : color)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if locked {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                        Text("会员")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(locked)
    }

    // 把 "cmd+1" / "shift+r" / "opt+space" 转成可读小标签
    private func shortcutLabel(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
            .replacingOccurrences(of: "command", with: "⌘", options: .caseInsensitive)
            .replacingOccurrences(of: "cmd", with: "⌘", options: .caseInsensitive)
            .replacingOccurrences(of: "shift", with: "⇧", options: .caseInsensitive)
            .replacingOccurrences(of: "option", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "opt", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "alt", with: "⌥", options: .caseInsensitive)
            .replacingOccurrences(of: "control", with: "⌃", options: .caseInsensitive)
            .replacingOccurrences(of: "ctrl", with: "⌃", options: .caseInsensitive)
            .replacingOccurrences(of: "enter", with: "⏎", options: .caseInsensitive)
            .replacingOccurrences(of: "space", with: "␣", options: .caseInsensitive)
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    // MARK: - 联系方式卡片（点击复制，留空隐藏）
    @ViewBuilder
    private var contactCard: some View {
        if let cfg = config.config {
            let qq = cfg.qqGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            let wechat = cfg.wechatOfficial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !qq.isEmpty || !wechat.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("联系方式")
                        .font(.headline)
                        .foregroundColor(AppTheme.primary)
                    if !qq.isEmpty {
                        contactRow(icon: "person.2.fill", label: "QQ 群", value: qq)
                    }
                    if !wechat.isEmpty {
                        contactRow(icon: "message.fill", label: "微信公众号", value: wechat)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
                .shadow(color: .black.opacity(AppTheme.isDark ? 0.35 : 0.06), radius: 8, y: 2)
            }
        }
    }

    private func contactRow(icon: String, label: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            showToast("已复制 \(label)")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 22)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 按钮动作处理（先二次确认，再执行）
    private func handleButton(_ btn: ConfigButton) {
        if let confirm = btn.confirmText?.trimmingCharacters(in: .whitespacesAndNewlines), !confirm.isEmpty {
            activeAlert = .confirm(btn)
        } else {
            executeAction(btn)
        }
    }

    private func executeAction(_ btn: ConfigButton) {
        switch btn.action {
        case "open_file_manager":
            // 点按钮打开文件管理器 (配置了 path 则直接跳到该目录)
            openFileManager(at: btn.path)

        case "download":
            if let url = btn.downloadURL {
                // 下载目标目录：优先按钮配置的 target_dir，默认导入和平精英 Paks
                let targetDir = btn.params?["target_dir"] ?? "@game:paks"
                downloadFile(url: url, filename: btn.title, targetDir: targetDir)
            }

        case "update_url":
            activeSheet = .updateURL

        case "run_script":
            runCloudScript(btn)

        case "open_url":
            if let url = btn.openURL, let link = URL(string: url) {
                UIApplication.shared.open(link)
            }

        case "activate_member":
            store.memberActivated = true
            showToast("会员已激活")

        case "uninstall":
            uninstallPaths(btn.paths)

        default:
            showToast("按钮: \(btn.title)")
        }
    }

    // 打开文件管理器到指定目录（如果配置了 path）
    private func openFileManager(at path: String?) {
        // FileManagerView 使用 exploit.fileHandle；指定目录通过 UserDefaults 临时传递
        if let p = path, !p.isEmpty {
            UserDefaults.standard.set(p, forKey: "filemanager_start_path")
        } else {
            UserDefaults.standard.removeObject(forKey: "filemanager_start_path")
        }
        showFileManager = true
    }

    // MARK: - 下载文件 (导入到指定目录, 默认和平精英 Paks)
    private func downloadFile(url: String, filename: String, targetDir: String? = nil) {
        showToast("开始下载: \(filename)")
        guard let link = URL(string: url) else {
            showToast("URL 无效")
            return
        }

        URLSession.shared.downloadTask(with: link) { tempURL, _, error in
            if let error = error {
                DispatchQueue.main.async { showToast("下载失败: \(error.localizedDescription)") }
                return
            }
            guard let tempURL = tempURL else { return }
            do {
                let data = try Data(contentsOf: tempURL)
                let savedName = link.lastPathComponent.isEmpty ? filename : link.lastPathComponent

                if let td = targetDir, !td.isEmpty {
                    guard let handle = ExploitManager.shared.fileHandle else {
                        DispatchQueue.main.async { showToast("请先进入文件管理器获得文件系统权限") }
                        return
                    }
                    guard let resolved = GameDirectoryResolver.resolve(td, fileHandle: handle) else {
                        DispatchQueue.main.async { showToast("未定位到目标目录: \(td)") }
                        return
                    }
                    try handle.createDirectory(at: resolved)
                    let dest = (resolved as NSString).appendingPathComponent(savedName)
                    try handle.writeFile(at: dest, data: data)
                    DispatchQueue.main.async { showToast("已导入: \(savedName)") }
                } else {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let dest = docs.appendingPathComponent(savedName)
                    try data.write(to: dest)
                    DispatchQueue.main.async { showToast("下载完成: \(savedName)") }
                }
            } catch {
                DispatchQueue.main.async { showToast("保存失败: \(error.localizedDescription)") }
            }
        }.resume()
    }

    // MARK: - 运行云端脚本（JavaScriptCore 真执行）
    private func runCloudScript(_ btn: ConfigButton) {
        // 优先用后台内联脚本（云端直发）
        if let script = btn.script, !script.isEmpty {
            runScript(script)
            return
        }
        // 兼容旧配置：script_path 指向远端 JS 时先下载再执行
        if let path = btn.scriptPath, let url = URL(string: path), url.scheme != nil {
            showToast("下载脚本中…")
            URLSession.shared.dataTask(with: url) { data, _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.showToast("脚本下载失败: \(error.localizedDescription)")
                        return
                    }
                    if let data = data, let js = String(data: data, encoding: .utf8), !js.isEmpty {
                        self.runScript(js)
                    } else {
                        self.showToast("脚本内容无效")
                    }
                }
            }.resume()
            return
        }
        showToast("未配置脚本（请在后台填写 script 字段）")
    }

    private func runScript(_ script: String) {
        showToast("执行脚本中…")
        ScriptRunner.run(script: script, fileHandle: exploit.fileHandle) { log in
            var lines = log.lines
            lines.append(log.succeeded ? "✅ 执行成功" : "❌ 执行失败")
            scriptLogText = lines.joined(separator: "\n")
            activeSheet = .scriptLog
        }
    }

    // MARK: - 卸载美化（按 params.paths 逐条真实删除）
    private func uninstallPaths(_ paths: [String]?) {
        guard let handle = exploit.fileHandle else {
            showToast("无文件访问权限")
            return
        }
        let list = (paths ?? []).filter { !$0.isEmpty }
        if list.isEmpty {
            showToast("未配置删除路径")
            return
        }

        var logs: [String] = []
        for p in list {
            if handle.fileExists(at: p) {
                do {
                    try handle.deleteItem(at: p)
                    logs.append("✅ 已删除 \(p)")
                } catch {
                    logs.append("❌ 删除失败 \(p): \(error.localizedDescription)")
                }
            } else {
                logs.append("− 不存在 \(p)")
            }
        }
        logs.append("—")
        logs.append("共处理 \(list.count) 个路径")
        scriptLogText = logs.joined(separator: "\n")
        activeSheet = .scriptLog
    }

    // MARK: - 底部信息（设备 / 版本 / 云端地址 / 一键刷新）
    private var footerInfo: some View {
        VStack(spacing: 8) {
            Divider().opacity(AppTheme.isDark ? 0.25 : 0.4)

            HStack(spacing: 6) {
                Text("iOS \(store.systemVersion)")
            }
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.7))

            Button {
                config.loadConfig()
                showToast("正在刷新配置…")
            } label: {
                Label("刷新配置", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundColor(AppTheme.accent)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - 诊断面板（长按头部卡片打开）
    private var diagnosticSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    diagRow("加载错误", config.loadError ?? "无")
                    diagRow("配置状态", config.config == nil ? "未加载" : (config.config!.locked == true ? "锁定空壳" : "正常"))
                    diagRow("按钮数量", "\(config.config?.buttons.count ?? -1) 个")
                    if let reason = config.config?.lockedReason, !reason.isEmpty {
                        diagRow("锁定原因", reason)
                    }
                    diagRow("App 版本", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    diagRow("当前漏洞", exploit.selectedExploitId ?? "未选择")
                }
                .padding()

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        license.logout()
                        activeSheet = nil
                    } label: {
                        Text("注销卡密")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        config.loadConfig()
                        activeSheet = nil
                    } label: {
                        Text("强制刷新配置")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
            .navigationTitle("诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { activeSheet = nil }
                }
            }
        }
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundColor(.secondary)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }

    // MARK: - 脚本执行日志页
    private var scriptLogSheet: some View {
        NavigationStack {
            ScrollView {
                Text(scriptLogText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("执行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { activeSheet = nil }
                }
            }
        }
    }

    // MARK: - 更新配置地址
    private var updateURLSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("配置 URL", text: Binding(
                    get: { store.customConfigURL ?? "" },
                    set: { store.customConfigURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)

                Button {
                    if let url = store.customConfigURL, !url.isEmpty {
                        config.updateConfigURL(url)
                    }
                    activeSheet = nil
                } label: {
                    Text("更新并刷新")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("取消") { activeSheet = nil }
            }
            .padding()
            .navigationTitle("更新配置地址")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func showToast(_ msg: String) {
        toastMsg = msg
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }
}

// MARK: - 主界面弹层 / 弹窗标识
enum HomeSheet: String, Identifiable {
    case diagnostic
    case scriptLog
    case updateURL
    var id: String { rawValue }
}

enum HomeAlert: Identifiable {
    case announcement
    case confirm(ConfigButton)
    var id: String {
        switch self {
        case .announcement: return "announcement"
        case .confirm: return "confirm"
        }
    }
}