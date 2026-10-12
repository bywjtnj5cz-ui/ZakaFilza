import Foundation

// 本地持久化存储
final class AppStore: ObservableObject {
    static let shared = AppStore()

    private let defaults = UserDefaults.standard

    @Published var selectedExploitId: String? {
        didSet { defaults.set(selectedExploitId, forKey: "selectedExploitId") }
    }

    @Published var memberActivated: Bool {
        didSet { defaults.set(memberActivated, forKey: "memberActivated") }
    }

    @Published var customConfigURL: String? {
        didSet { defaults.set(customConfigURL, forKey: "customConfigURL") }
    }

    private init() {
        self.selectedExploitId = defaults.string(forKey: "selectedExploitId")
        self.memberActivated = defaults.bool(forKey: "memberActivated")
        self.customConfigURL = defaults.string(forKey: "customConfigURL")
    }

    // 设备 UUID（使用 Keychain 持久化，卸载不丢）
    var deviceUUID: String {
        DeviceManager.shared.uuid
    }

    // 系统版本
    var systemVersion: String {
        UIDevice.current.systemVersion
    }
}
