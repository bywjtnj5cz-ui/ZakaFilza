import Foundation
import SwiftUI

// MARK: - 卡密验证系统
// 协议设计：
// POST {server}/api/verify
// Body: { "card_key": "xxx", "uuid": "xxx", "model": "xxx", "system_version": "xxx" }
// Response: { "success": true/false, "message": "...", "expire_at": "2026-12-31", "member_level": 1 }
//
// 验证成功后缓存到本地，每次启动先检查本地缓存是否过期，过期再联网验证

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published var isActivated: Bool = false
    @Published var expireDate: Date?
    @Published var memberLevel: Int = 0
    @Published var cardKey: String?
    @Published var isVerifying: Bool = false
    @Published var lastError: String?

    // 验证服务器地址（可在云端配置中覆盖）
    var verifyServerURL: String = "http://156.238.232.172/api/verify.php?action=verify"

    private let cacheKey = "license_cache"
    private let cardKeyKey = "card_key"

    private init() {
        loadCache()
    }

    // MARK: - 本地缓存
    private struct LicenseCache: Codable {
        let cardKey: String
        let expireAt: Date
        let memberLevel: Int
        let uuid: String
        let verifiedAt: Date
    }

    private func loadCache() {
        // 从 UserDefaults 读取卡密
        self.cardKey = UserDefaults.standard.string(forKey: cardKeyKey)

        // 从 Keychain 读取验证缓存
        guard let data = KeychainHelper.shared.read(for: cacheKey),
              let cache = try? JSONDecoder().decode(LicenseCache.self, from: data) else {
            self.isActivated = false
            return
        }

        // 检查 UUID 是否匹配（防止卡密被复制到其他设备）
        guard cache.uuid == DeviceManager.shared.uuid else {
            self.isActivated = false
            self.lastError = "卡密绑定的设备不匹配"
            return
        }

        // 检查是否过期
        if cache.expireAt > Date() {
            self.isActivated = true
            self.expireDate = cache.expireAt
            self.memberLevel = cache.memberLevel
        } else {
            self.isActivated = false
            self.lastError = "卡密已过期"
        }
    }

    private func saveCache(_ cache: LicenseCache) {
        if let data = try? JSONEncoder().encode(cache) {
            KeychainHelper.shared.save(data, for: cacheKey)
        }
        UserDefaults.standard.set(cache.cardKey, forKey: cardKeyKey)
    }

    // MARK: - 卡密验证
    func verify(cardKey: String, completion: @escaping (Bool, String?) -> Void) {
        isVerifying = true
        lastError = nil

        let device = DeviceManager.shared
        let body: [String: Any] = [
            "card_key": cardKey,
            "uuid": device.uuid,
            "model": device.model,
            "system_version": device.systemVersion,
            "system_name": device.systemName
        ]

        guard let url = URL(string: verifyServerURL),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            isVerifying = false
            completion(false, "服务器地址无效")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isVerifying = false

                if let error = error {
                    self?.lastError = "网络错误: \(error.localizedDescription)"
                    completion(false, self?.lastError)
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self?.lastError = "服务器返回数据无效"
                    completion(false, self?.lastError)
                    return
                }

                let success = json["success"] as? Bool ?? false
                let message = json["message"] as? String ?? ""

                if success {
                    // 解析过期时间
                    var expireAt = Date().addingTimeInterval(30 * 24 * 3600) // 默认30天
                    if let expireStr = json["expire_at"] as? String {
                        let formatter = ISO8601DateFormatter()
                        if let date = formatter.date(from: expireStr) {
                            expireAt = date
                        }
                    }
                    let memberLevel = json["member_level"] as? Int ?? 1

                    // 保存缓存
                    let cache = LicenseCache(
                        cardKey: cardKey,
                        expireAt: expireAt,
                        memberLevel: memberLevel,
                        uuid: device.uuid,
                        verifiedAt: Date()
                    )
                    self?.saveCache(cache)

                    self?.isActivated = true
                    self?.expireDate = expireAt
                    self?.memberLevel = memberLevel
                    self?.cardKey = cardKey

                    completion(true, nil)
                } else {
                    self?.lastError = message
                    completion(false, message)
                }
            }
        }.resume()
    }

    // MARK: - 解绑/注销
    func logout() {
        KeychainHelper.shared.delete(for: cacheKey)
        UserDefaults.standard.removeObject(forKey: cardKeyKey)
        isActivated = false
        expireDate = nil
        memberLevel = 0
        cardKey = nil
    }

    // 检查是否需要重新验证（缓存过期后静默刷新）
    func refreshIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard isActivated, let cardKey = cardKey else {
            completion?(false)
            return
        }

        // 如果过期时间小于7天，重新验证
        if let expire = expireDate, expire.timeIntervalSinceNow < 7 * 24 * 3600 {
            verify(cardKey: cardKey) { success, _ in
                completion?(success)
            }
        } else {
            completion?(true)
        }
    }

    // 格式化过期时间
    var expireText: String {
        guard let date = expireDate else { return "未激活" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
