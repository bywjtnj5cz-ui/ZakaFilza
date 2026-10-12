import Foundation
import Security
import UIKit

// MARK: - Keychain 工具
// 用于持久化存储 UUID 和卡密，卸载重装不丢失
final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.zaka.filza.keychain"

    // 存储数据到 Keychain
    func save(_ data: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // 先删除旧的
        SecItemDelete(query as CFDictionary)

        // 添加新的
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // 从 Keychain 读取数据
    func read(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        return nil
    }

    // 删除 Keychain 中的数据
    func delete(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    // 便捷方法：存取字符串
    func saveString(_ string: String, for key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, for: key)
    }

    func readString(for key: String) -> String? {
        guard let data = read(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 设备 UUID 管理
// 使用 Keychain 持久化，卸载重装后 UUID 不变
final class DeviceManager {
    static let shared = DeviceManager()

    private let uuidKey = "device_uuid"

    // 获取设备 UUID（首次生成后永久存储在 Keychain）
    var uuid: String {
        if let saved = KeychainHelper.shared.readString(for: uuidKey) {
            return saved
        }
        // 生成新 UUID（优先用 identifierForVendor，否则随机）
        let newUUID = UIDevice.current.identifierForVendor?.uuidString
            ?? UUID().uuidString
        KeychainHelper.shared.saveString(newUUID, for: uuidKey)
        return newUUID
    }

    // 设备型号
    var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    // 系统版本
    var systemVersion: String {
        UIDevice.current.systemVersion
    }

    // 系统名称
    var systemName: String {
        UIDevice.current.systemName
    }

    // 是否越狱
    var isJailbroken: Bool {
        let indicators = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/private/var/lib/apt",
            "/private/var/stash",
            "/usr/sbin/sshd",
            "/bin/bash",
            "/usr/bin/ssh"
        ]
        return indicators.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // 设备指纹（用于服务器验证，包含 UUID + 型号 + 系统版本）
    var deviceFingerprint: [String: String] {
        [
            "uuid": uuid,
            "model": model,
            "system_version": systemVersion,
            "system_name": systemName,
            "jailbroken": isJailbroken ? "1" : "0"
        ]
    }
}
