import SwiftUI

// 各类弹窗 Sheet
struct SheetsView: View {
    @Binding var isPresented: Bool
    let type: SheetType

    enum SheetType {
        case announcement(String)
        case about
        case settings
    }

    var body: some View {
        NavigationStack {
            Group {
                switch type {
                case .announcement(let text):
                    announcementView(text)
                case .about:
                    aboutView
                case .settings:
                    settingsView
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { isPresented = false }
                }
            }
        }
    }

    private var title: String {
        switch type {
        case .announcement: return "公告"
        case .about: return "关于"
        case .settings: return "设置"
        }
    }

    private func announcementView(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .padding()
        }
    }

    private var aboutView: some View {
        List {
            LabeledContent("App 名称", value: "实用")
            LabeledContent("版本", value: "1.0.0")
            LabeledContent("最低系统", value: "iOS 16.0")
            Section("支持的漏洞") {
                Text("FilzaJailedDS - iOS 17.0–26.0.1")
                Text("FilzaSlop - iOS 18, 26, 27 beta")
            }
        }
    }

    private var settingsView: some View {
        List {
            Section("配置") {
                NavigationLink("更新配置地址") {}
                Toggle("会员激活", isOn: .constant(false))
            }
            Section("文件管理") {
                NavigationLink("打开文件管理器") {}
                NavigationLink("管理下载目录") {}
            }
            Section("关于") {
                NavigationLink("关于本应用") {}
            }
        }
    }
}
