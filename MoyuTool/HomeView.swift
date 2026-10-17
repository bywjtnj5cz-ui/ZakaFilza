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
    @State private var downloadProgress: Double? = nil   // nil = 未在下载; 0.0~1.0 = 下载进度

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

                        // 耳机按钮（一机一码专属，仅 member_level >= 2 解锁）
                        if let earphones = cfg.earphoneButtons, !earphones.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(earphones) { btn in
                                    cloudButton(btn, isEarphone: true)
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
                case .logoutConfirm:
                    return Alert(
                        title: Text("注销卡密"),
                        message: Text("确定要解绑当前设备吗？解绑后卡密可在其他设备重新激活。"),
                        primaryButton: .destructive(Text("注销")) { license.logout() },
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
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(toastMsg)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .foregroundColor(AppTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                        )
                        .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 4)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast),
                alignment: .bottom
            )
            // 下载/导入进度遮罩
            .overlay(
                Group {
                    if let p = downloadProgress {
                        ZStack {
                            Color.black.opacity(0.35).ignoresSafeArea()
                            downloadProgressCard(progress: p)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: downloadProgress)
            )
        }
    }

    // MARK: - 下载进度卡片
    private func downloadProgressCard(progress: Double) -> some View {
        let percent = Int((progress * 100).rounded())
        return VStack(spacing: 16) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primary))
                    .scaleEffect(0.9)
                Text("正在下载…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.primary)
            }

            // 渐变进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.primary.opacity(0.14))
                    Capsule()
                        .fill(AppTheme.primaryGradient())
                        .frame(width: max(geo.size.width * progress, 8))
                }
            }
            .frame(height: 8)

            Text("请勿关闭 App，完成后自动导入")
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 270)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: AppTheme.cardShadow, radius: 24, x: 0, y: 10)
    }

    // 读取本 App 的图标: 先按名称取, 再从 Info.plist 的 CFBundleIconFiles 兜底
    private var appIconImage: UIImage? {
        if let img = UIImage(named: "AppIcon") { return img }
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let img = UIImage(named: name) { return img }
            }
        }
        return nil
    }

    // MARK: - 应用图标视图 (优先用 App Icon, 取不到回退渐变圆底 + SF Symbol)
    @ViewBuilder
    private var appIconView: some View {
        if let uiIcon = appIconImage {
            Image(uiImage: uiIcon)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                )
                .shadow(color: AppTheme.cardShadow, radius: 5, x: 0, y: 2)
        } else {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryGradient())
                    .frame(width: 46, height: 46)
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - 头部卡片（含状态条，长按打开诊断）
    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                // 应用图标 (读取 App Icon, 取不到时回退渐变圆底)
                appIconView

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.config?.appName ?? "实用")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("iOS 文件管理工具")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                if !(config.config?.announcement.isEmpty ?? true) {
                    Button(action: { activeAlert = .announcement }) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.glassBackground)
                                .frame(width: 38, height: 38)
                            Image(systemName: "bell.fill")
                                .foregroundColor(AppTheme.warning)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }

            if let cfg = config.config {
                // 状态条：卡密状态 + 当前漏洞链
                statusBar
                HStack(alignment: .center) {
                    Text("版本 \(cfg.version)")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary)
                        .tracking(0.5)
                    Spacer()
                    Button(action: { activeAlert = .logoutConfirm }) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("注销卡密")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                AppTheme.cardColor
                // 顶部微妙高光线条
                VStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(AppTheme.primary.opacity(0.25))
                        .frame(height: 2)
                    Spacer()
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 4)
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
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 3)
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
            .frame(height: 160)
            .clipped()

            // 底部渐变遮罩，让文字更清晰
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.6)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 80)
            .frame(maxWidth: .infinity, alignment: .bottom)

            if let title = banner.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
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
            Rectangle().fill(AppTheme.cardColor)
            Image(systemName: "photo")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AppTheme.textSecondary)
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
        let requiredLevel = cat.requiredLevel
        let locked = requiredLevel > 0 && license.memberLevel < requiredLevel
        let lockLabel = requiredLevel >= 2 ? "耳机" : "会员"
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon = cat.icon, !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text(cat.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                if cat.requiredLevel > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text(lockLabel)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.warning.opacity(0.12))
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
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AppTheme.cardColor
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 4)
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
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((locked ? Color.gray : AppTheme.accent).opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(locked ? .secondary : AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(locked ? AppTheme.textSecondary : AppTheme.textPrimary)
                    if let desc = file.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        if let size = file.size, !size.isEmpty {
                            Label(size, systemImage: "externaldrive")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        if let v = file.version, !v.isEmpty {
                            Label("v\(v)", systemImage: "number")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill((locked ? Color.gray : AppTheme.primary).opacity(0.10))
                        .frame(width: 32, height: 32)
                    Image(systemName: locked ? "lock.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(locked ? .secondary : AppTheme.primary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((locked ? Color.gray : AppTheme.primary).opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke((locked ? Color.gray : AppTheme.primary).opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(locked ? 0.7 : 1.0)
    }

    // 状态条：卡密状态 + 当前漏洞链
    private var statusBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: license.isActivated ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(license.isActivated ? AppTheme.success : AppTheme.warning)
                Text(license.isActivated ? "已激活 · \(license.expireText)" : "卡密未激活")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(license.isActivated ? AppTheme.success : AppTheme.warning)
            }

            Spacer()

            if let name = exploit.availableExploits.first(where: { $0.id == exploit.selectedExploitId })?.name {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.primary)
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            Capsule()
                .fill(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
        .overlay(
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - 云端按钮
    private func cloudButton(_ btn: ConfigButton, isMember: Bool = false, isEarphone: Bool = false) -> some View {
        // member_buttons 区默认等级1, earphone_buttons 区默认等级2, 可用 min_member_level 覆盖
        let baseLevel = btn.requiredLevel
        let requiredLevel = isEarphone ? max(baseLevel, 2) : (isMember ? max(baseLevel, 1) : baseLevel)
        let locked = requiredLevel > 0 && license.memberLevel < requiredLevel
        let lockLabel = requiredLevel >= 2 ? "耳机" : "会员"
        let color = btn.color.flatMap { Color(hex: $0) } ?? AppTheme.primary

        return Button(action: {
            if locked {
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
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                // 快捷键小标签
                if let sc = shortcutLabel(btn.shortcut) {
                    Text(sc)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .background(
                ZStack {
                    if locked {
                        AppTheme.memberLocked
                    } else {
                        AppTheme.primaryGradient(from: color)
                        // 顶部高光
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(locked ? 0 : 0.12), lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if locked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                        Text(lockLabel)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .padding(.trailing, 8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(locked ? 0.85 : 1.0)
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
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.primary)
                        Text("联系方式")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Spacer()
                    }

                    VStack(spacing: 8) {
                        if !qq.isEmpty {
                            contactRow(icon: "person.2.fill", label: "QQ 群", value: qq)
                        }
                        if !wechat.isEmpty {
                            contactRow(icon: "message.fill", label: "微信公众号", value: wechat)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ZStack {
                        AppTheme.cardColor
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius + 4, style: .continuous))
                .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 4)
            }
        }
    }

    private func contactRow(icon: String, label: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            showToast("已复制 \(label)")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.primary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            )
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
            if let url = btn.downloadURL, !url.isEmpty {
                // 下载目标目录：优先按钮配置的 target_dir，默认导入和平精英 Paks
                let targetDir = btn.params?["target_dir"] ?? "@game:paks"
                // 若 unzip 未显式配置，且 URL/文件名明显是 zip，默认启用解压（防呆）
                let isZipHint = url.lowercased().hasSuffix(".zip") ||
                                url.lowercased().contains(".zip?") ||
                                url.lowercased().contains(".zip&") ||
                                btn.title.lowercased().contains("美化") ||
                                btn.title.lowercased().contains("配置")
                let effectiveUnzip = btn.unzip ?? isZipHint
                downloadFile(url: url, filename: btn.title, targetDir: targetDir, unzip: effectiveUnzip)
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

    // MARK: - 下载文件 (导入到指定目录, 默认和平精英 Paks; unzip=true 解压导入包内文件)
    private func downloadFile(url: String, filename: String, targetDir: String? = nil, unzip: Bool = false) {
        showToast(unzip ? "开始下载并解压: \(filename)" : "开始下载: \(filename)")
        downloadProgress = 0
        CloudDownloader.downloadAndImport(
            urlString: url,
            filename: filename,
            targetDir: targetDir,
            handle: exploit.fileHandle,
            unzip: unzip,
            progress: { p in
                // 委托已在主线程回调, 直接更新进度
                self.downloadProgress = p
            }
        ) { result in
            DispatchQueue.main.async {
                self.downloadProgress = nil
                switch result {
                case .success(let detail):
                    self.showToast("已导入: \(detail)")
                case .failure(let message):
                    self.showToast(message)
                }
            }
        }
    }

    // MARK: - 应用配置包 (分类卡片点击下载导入, 默认导入和平精英 Paks)
    private func applyConfigFile(_ file: ConfigFileItem) {
        let target = file.targetDir.isEmpty ? "@game:paks" : file.targetDir
        downloadFile(url: file.downloadURL, filename: file.name, targetDir: target, unzip: file.unzip ?? false)
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
        downloadFile(url: file.downloadURL, filename: file.name,
                     targetDir: file.targetDir.isEmpty ? "@game:paks" : file.targetDir,
                     unzip: file.unzip ?? false)
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

        // 1. 定位容器根 (bundle id 直查 → MCM 枚举 → 句柄扫描, 带完整诊断)
        let report = GameDirectoryResolver.lookup(bundleID: gd.bundleID, fileHandle: handle)
        guard let root = report.root else {
            // 签名身份是 MHA 旁路的开关 — 不是它则一切 MCM 调用被拒
            let identity = MCMFileManager.shared.signedCodeIdentifier
            let isMHA = MCMFileManager.shared.isMHAIdentity

            // LS 发现渠道: 本机实际安装的腾讯系应用 (iOS 26 上唯一可靠的发现方式)
            let lsTencent = MCMFileManager.shared.installedApplicationIdentifiers()
                .filter { $0.lowercased().contains("tencent") }

            lines.append("❌ 未定位到应用容器")
            lines.append("")
            lines.append("—— 签名身份 (关键) ——")
            lines.append("当前: \(identity.isEmpty ? "(读取失败)" : identity)")
            if isMHA {
                lines.append("✅ 是 com.apple.mobile.MobileHouseArrest")
            } else {
                lines.append("❌ 不是 com.apple.mobile.MobileHouseArrest")
                lines.append("→ 没有该签名身份, 系统会拒绝所有 MCM 容器访问 (FilzaSlop 旁路失效)")
                lines.append("→ 重签 IPA 时必须保持包名 com.apple.mobile.MobileHouseArrest 不变")
            }
            lines.append("")
            lines.append("—— 诊断详情 ——")
            for n in report.notes {
                lines.append("· \(n)")
            }
            lines.append("MCM bridge: \(report.mcmAvailable ? "可用" : "不可用")")
            if report.mcmAvailable {
                lines.append("MCM 枚举容器数: \(report.mcmEnumCount)")
                lines.append("MCM 租约成功数: \(report.mcmLeaseOk)")
            }
            if report.scanTried {
                if report.scanFailed {
                    lines.append("句柄扫描: 失败 (\(report.scanError))")
                } else {
                    lines.append("句柄扫描: 共扫 \(report.scanEntryCount) 个容器")
                }
            }
            lines.append("")
            if lsTencent.isEmpty && report.tencentBundles.isEmpty {
                lines.append("⚠️ 未发现任何腾讯系应用")
                lines.append("→ 本机很可能没有安装和平精英")
            } else {
                lines.append("本机检测到的腾讯系应用:")
                var seen = Set<String>()
                for b in lsTencent + report.tencentBundles where seen.insert(b).inserted {
                    lines.append("   \(b)")
                }
                lines.append("→ 上面没有 com.tencent.tmgp.pubgmhd 说明装的版本不对")
                lines.append("  (国际服 com.tencent.ig / 体验服 bundle 不同)")
            }
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
        VStack(spacing: 12) {
            Divider()
                .background(AppTheme.cardBorder)
                .padding(.horizontal, 40)

            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                Text("iOS \(store.systemVersion)")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(AppTheme.textSecondary.opacity(0.7))

            Button {
                config.loadConfig()
                showToast("正在刷新配置…")
            } label: {
                Label("刷新配置", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
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
    case logoutConfirm
    var id: String {
        switch self {
        case .announcement: return "announcement"
        case .confirm: return "confirm"
        case .logoutConfirm: return "logoutConfirm"
        }
    }
}

// MARK: - 会员卡激活 (免费用户升级会员, 现代优雅风)
struct MemberActivateView: View {
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var cardKey = ""
    @State private var errorMsg = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部装饰
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(AppTheme.primaryGradient())
                            .frame(width: 64, height: 64)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.top, 12)

                Text("激活会员")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 20)

                Text("解锁全部高级功能，一卡一机永久绑定")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    TextField("输入会员卡密", text: $cardKey)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("粘贴") {
                        if let s = UIPasteboard.general.string {
                            cardKey = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                )
                .padding(.top, 28)

                if !errorMsg.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                        Text(errorMsg)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppTheme.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.danger.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 14)
                }

                Button(action: activate) {
                    HStack(spacing: 8) {
                        if license.isVerifying {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(license.isVerifying ? "激活中…" : "立即激活")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(CloudButtonStyle(color: AppTheme.primary,
                                              disabled: cardKey.isEmpty || license.isVerifying))
                .padding(.top, 20)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .preferredColorScheme(AppTheme.isDark ? .dark : .light)
    }

    private func activate() {
        errorMsg = ""
        let key = cardKey.trimmingCharacters(in: .whitespacesAndNewlines)
        license.verify(cardKey: key) { success, msg in
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