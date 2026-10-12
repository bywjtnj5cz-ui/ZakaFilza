import SwiftUI
import WebKit

// HTML 文件管理器的 SwiftUI 容器
struct FileManagerView: View {
    @EnvironmentObject var exploit: ExploitManager
    @State private var bridge: FileBridge?

    var body: some View {
        WebViewContainer(bridge: $bridge)
            .navigationTitle("文件管理")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let handle = exploit.fileHandle {
                    bridge = FileBridge(fileHandle: handle)
                }
            }
    }
}

struct WebViewContainer: UIViewRepresentable {
    @Binding var bridge: FileBridge?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        // 注入云端下载快捷键
        if let shortcuts = ConfigManager.shared.config?.downloadShortcuts,
           let jsonData = try? JSONEncoder().encode(shortcuts),
           let json = String(data: jsonData, encoding: .utf8) {
            let script = "window.__shortcuts = \(json);"
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        // 注入云端主题变量 (文件管理器配色跟随云端主题同步)
        if let theme = ConfigManager.shared.config?.theme,
           let json = Self.themeJSON(theme) {
            let script = "window.__theme = \(json);"
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.bounces = true

        // 加载内嵌 HTML (编译进二进制, IPA 内无明文文件)
        let html = BundledResources.fileManagerHTML
        if !html.isEmpty {
            let baseURL = URL(fileURLWithPath: Bundle.main.bundlePath)
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        // 附加桥接
        if let bridge = bridge {
            bridge.attach(to: webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 桥接可能在 onAppear 之后才设置
        if let bridge = bridge, context.coordinator.attachedBridge == nil {
            bridge.attach(to: webView)
            context.coordinator.attachedBridge = bridge
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // 把云端主题转成 JS 对象字符串, 供 file_manager.html 的 applyTheme() 读取
    private static func themeJSON(_ theme: ThemeConfig) -> String? {
        var obj: [String: Any] = [:]
        if let v = theme.primary, !v.isEmpty { obj["primary"] = v }
        if let v = theme.accent, !v.isEmpty { obj["accent"] = v }
        obj["background"] = theme.background ?? "aurora"
        if let v = theme.cornerRadius { obj["cornerRadius"] = v }
        if let v = theme.fontScale { obj["fontScale"] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    class Coordinator: NSObject {
        var attachedBridge: FileBridge?
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.attachedBridge?.detach()
    }
}
