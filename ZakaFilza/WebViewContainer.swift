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

        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.bounces = true

        // 加载本地 HTML
        if let htmlPath = Bundle.main.path(forResource: "file_manager", ofType: "html"),
           let html = try? String(contentsOfFile: htmlPath) {
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

    class Coordinator: NSObject {
        var attachedBridge: FileBridge?
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.attachedBridge?.detach()
    }
}
