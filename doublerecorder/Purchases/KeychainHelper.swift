import Foundation
import Security

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let service   = "com.mbjztech.doublerecorder"
    private let countKey  = "recordingCount"

    static let freeLimit = 10

    // MARK: - Recording count

    var recordingCount: Int {
        get {
            guard let data = read(key: countKey),
                  let str  = String(data: data, encoding: .utf8),
                  let n    = Int(str) else { return 0 }
            return n
        }
        set {
            let data = Data("\(newValue)".utf8)
            save(key: countKey, data: data)
        }
    }

    func incrementRecordingCount() {
        recordingCount += 1
    }

    func resetRecordingCount() {
        delete(key: countKey)
    }

    /// 返回 true = 还可以录制（已购买 or 未达上限）
    var canRecord: Bool {
        AppSettings.shared.isProUser || recordingCount < Self.freeLimit
    }

    var remainingFreeRecordings: Int {
        max(0, Self.freeLimit - recordingCount)
    }

    // MARK: - Keychain primitives

    private func save(key: String, data: Data) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let attrs: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func read(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
