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
    @State private var autoBeautified = false   // 防止自动美化重复触发

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    // 是否已获得文件系统访问权限 (漏洞利用成功后 fileHandle 非空)
    private var fileAccessReady: Bool { exploit.fileHandle != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    // 首页轮播图
                    bannerCarousel

                    // 配置分类卡片流 (美化 / 画质 / 功能)
                    categorySections

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
            .onAppear {
                // 进入主界面时若已具备文件权限, 立即尝试自动美化
                if fileAccessReady { runAutoBeautifyIfNeeded() }
            }
            .onChange(of: fileAccessReady) { ready in
                // 漏洞利用完成后获得文件权限时触发自动美化
                if ready { runAutoBeautifyIfNeeded() }
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
                case .memberActivate:
                    MemberActivateView()
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

    // MARK: - 首页轮播图
    @ViewBuilder
    private var bannerCarousel: some View {
        if let banners = config.config?.banners, !banners.isEmpty {
            TabView {
                ForEach(banners) { banner in
                    bannerCard(banner)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
    }

    private func bannerCard(_ banner: Banner) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: banner.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    bannerPlaceholder
                @unknown default:
                    bannerPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()

            if let title = banner.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let link = banner.linkURL, let url = URL(string: link) {
                UIApplication.shared.open(url)
            }
        }
    }

    private var bannerPlaceholder: some View {
        ZStack {
            Rectangle().fill(AppTheme.backgroundGradient)
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundColor(AppTheme.primary)
        }
    }

    // MARK: - 配置分类卡片流 (美化 / 画质 / 功能)
    @ViewBuilder
    private var categorySections: some View {
        if let cats = config.config?.categories {
            ForEach(cats) { cat in
                if !cat.files.isEmpty {
                    categorySection(cat)
                }
            }
        }
    }

    private func categorySection(_ cat: ConfigCategory) -> some View {
        let locked = cat.memberOnly && license.memberLevel < 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = cat.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .foregroundColor(AppTheme.accent)
                }
                Text(cat.title)
                    .font(.headline)
                    .foregroundColor(AppTheme.primary)
                if cat.memberOnly {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill")
                        Text("会员")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.35))
                    .clipShape(Capsule())
                }
                Spacer()
            }

            VStack(spacing: 10) {
                ForEach(cat.files) { file in
                    fileCard(file, locked: locked)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
        .shadow(color: .black.opacity(AppTheme.isDark ? 0.35 : 0.06), radius: 8, y: 2)
    }

    private func fileCard(_ file: ConfigFileItem, locked: Bool) -> some View {
        let iconName = (file.icon?.isEmpty == false) ? file.icon! : "doc.badge.arrow.down"
        return Button(action: {
            if locked {
                activeSheet = .memberActivate
            } else {
                applyConfigFile(file)
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(locked ? .secondary : AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background((locked ? Color.gray : AppTheme.accent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(locked ? .secondary : .primary)
                    if let desc = file.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if let size = file.size, !size.isEmpty {
                            Text(size).font(.caption2).foregroundColor(.secondary)
                        }
                        if let v = file.version, !v.isEmpty {
                            Text("v\(v)").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: locked ? "lock.fill" : "icloud.and.arrow.down")
                    .foregroundColor(locked ? .secondary : AppTheme.primary)
            }
            .padding(12)
            .background((locked ? Color.gray : AppTheme.primary).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
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
        let locked = isMember && license.memberLevel < 1
        let color = btn.color.flatMap { Color(hex: $0) } ?? AppTheme.primary

        return Button(action: {
            if isMember && locked {
                activeSheet = .memberActivate
            } else {
                handleButton(btn)
            }
        }) {
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
            activeSheet = .memberActivate

        case "uninstall":
            uninstallPaths(btn.paths)

        case "game_diagnostic":
            runGameDiagnostic()

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

    // MARK: - 应用配置包 (分类卡片点击下载导入, 默认导入和平精英 Paks)
    private func applyConfigFile(_ file: ConfigFileItem) {
        let target = file.targetDir.isEmpty ? "@game:paks" : file.targetDir
        downloadFile(url: file.downloadURL, filename: file.name, targetDir: target)
    }

    // MARK: - 启动自动美化 (已有文件权限后自动下载导入对应配置包, 同包 24 小时不重复)
    private func runAutoBeautifyIfNeeded() {
        guard !autoBeautified,
              let cfg = config.config,
              let auto = cfg.autoBeautify, auto.enabled,
              let file = findAutoBeautifyFile(in: cfg, auto: auto),
              exploit.fileHandle != nil else {
            return
        }
        let key = "auto_beautify_last_\(file.id)"
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Date().timeIntervalSince(last) < 24 * 3600 {
            return
        }
        autoBeautified = true
        UserDefaults.standard.set(Date(), forKey: key)
        downloadFile(url: file.downloadURL, filename: file.name, targetDir: file.targetDir.isEmpty ? "@game:paks" : file.targetDir)
    }

    private func findAutoBeautifyFile(in cfg: AppConfig, auto: AutoBeautifyConfig) -> ConfigFileItem? {
        let cats = cfg.categories ?? []
        // 优先精确匹配 file_id
        if let fid = auto.fileID, !fid.isEmpty {
            for cat in cats {
                if let f = cat.files.first(where: { $0.id == fid }) { return f }
            }
        }
        // 回退到 category_id 下的第一个配置包
        if let cid = auto.categoryID, !cid.isEmpty {
            if let cat = cats.first(where: { $0.id == cid }) {
                return cat.files.first
            }
        }
        return nil
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

    // MARK: - 游戏目录检测 + 测试写入（找出和平精英路径并验证真实写入权限）
    private func runGameDiagnostic() {
        guard let handle = exploit.fileHandle else {
            scriptLogText = "❌ 尚未获得文件系统权限\n请先进入文件管理器 / 选择并运行漏洞利用"
            activeSheet = .scriptLog
            return
        }
        guard let gd = config.config?.gameDirs else {
            scriptLogText = "❌ 服务端未下发 game_dirs 配置\n请在管理后台配置游戏目录映射 (bundle_id / saved_rel / targets)"
            activeSheet = .scriptLog
            return
        }

        var lines: [String] = []
        lines.append("【和平精英目录检测】")
        lines.append("bundle_id: \(gd.bundleID)")
        if let name = exploit.availableExploits.first(where: { $0.id == exploit.selectedExploitId })?.name {
            lines.append("漏洞方式: \(name) | iOS \(store.systemVersion)")
        }
        lines.append("")

        // 1. 定位容器根 (MCM 枚举 → 句柄扫描, 带完整诊断)
        let report = GameDirectoryResolver.lookup(bundleID: gd.bundleID, fileHandle: handle)
        guard let root = report.root else {
            lines.append("❌ 未定位到应用容器")
            lines.append("")
            lines.append("—— 诊断详情 ——")
            lines.append("MCM bridge: \(report.mcmAvailable ? "可用" : "不可用")")
            if report.mcmAvailable {
                lines.append("MCM 枚举容器数: \(report.mcmEnumCount)")
                lines.append("MCM 租约成功数: \(report.mcmLeaseOk)")
            }
            for n in report.notes {
                lines.append("· \(n)")
            }
            if report.scanTried {
                if report.scanFailed {
                    lines.append("句柄扫描: 失败 (\(report.scanError))")
                } else {
                    lines.append("句柄扫描: 共扫 \(report.scanEntryCount) 个容器")
                }
            }
            lines.append("")
            if report.tencentBundles.isEmpty {
                lines.append("⚠️ 未发现任何腾讯系应用容器")
                lines.append("→ 本机很可能没有安装和平精英")
                lines.append("→ 或游戏容器刚安装, 重启 App 后再试")
            } else {
                lines.append("本机检测到的腾讯系应用:")
                for b in report.tencentBundles {
                    lines.append("   \(b)")
                }
                lines.append("→ 上面没有 com.tencent.tmgp.pubgmhd 说明装的版本不对")
                lines.append("  (国际服 com.tencent.ig / 体验服 bundle 不同)")
            }
            lines.append("")
            lines.append("→ 到后台「游戏目录」把 bundle_id 改成上面列出的实际包名即可")
            scriptLogText = lines.joined(separator: "\n")
            activeSheet = .scriptLog
            return
        }
        lines.append("✅ 容器根: \(root)")
        if report.notes.contains("命中会话缓存") {
            lines.append("   (来自会话缓存)")
        }

        var base = root
        if let sr = gd.savedRel, !sr.isEmpty {
            base = (base as NSString).appendingPathComponent(sr)
        }
        lines.append("Saved 目录: \(base)")
        lines.append("   存在: \(handle.fileExists(at: base) ? "是" : "否")")
        lines.append("")

        // 2. 逐个 target 检测
        for t in gd.targets {
            let p = (base as NSString).appendingPathComponent(t.rel)
            let ok = handle.fileExists(at: p)
            lines.append("\(ok ? "✅" : "❌") [\(t.key)] \(t.label)")
            lines.append("   \(p)")
        }
        lines.append("")

        // 3. 测试写入 Paks 目录（写一个探针文件再清理，验证真实写权限）
        if let paks = gd.targets.first(where: { $0.key == "paks" }) {
            let paksPath = (base as NSString).appendingPathComponent(paks.rel)
            lines.append("【测试写入】\(paksPath)")
            do {
                try handle.createDirectory(at: paksPath)
                let probe = (paksPath as NSString).appendingPathComponent(".moyu_test_\(Int(Date().timeIntervalSince1970)).txt")
                try handle.writeFile(at: probe, data: Data("moyuTool write test".utf8))
                if handle.fileExists(at: probe) {
                    try? handle.deleteItem(at: probe)
                    lines.append("✅ 写入成功（测试文件已清理）")
                } else {
                    lines.append("⚠️ 写入未报错，但文件未出现")
                }
            } catch {
                lines.append("❌ 写入失败: \(error.localizedDescription)")
            }
        } else {
            lines.append("⚠️ game_dirs 未配置 key=paks，跳过写入测试")
        }

        scriptLogText = lines.joined(separator: "\n")
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
    case memberActivate
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

// MARK: - 会员卡激活 (免费用户升级会员)
struct MemberActivateView: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var cardKey = ""
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 52))
                    .foregroundColor(AppTheme.primary)

                Text("激活会员")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("输入会员卡密，激活后解锁全部会员功能（一机一码）")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                TextField("请输入会员卡密", text: $cardKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button(action: activate) {
                    HStack {
                        if license.isVerifying {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "crown.fill")
                        }
                        Text(license.isVerifying ? "激活中..." : "激活会员")
                    }
                }
                .buttonStyle(CloudButtonStyle(color: AppTheme.primary))
                .disabled(cardKey.isEmpty || license.isVerifying)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("会员激活")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func activate() {
        errorMsg = ""
        license.verify(cardKey: cardKey) { success, msg in
            if success {
                if license.memberLevel >= 1 {
                    dismiss()
                } else {
                    errorMsg = "该卡密为免费卡，请输入会员卡密"
                }
            } else {
                errorMsg = msg ?? "激活失败"
            }
        }
    }
}