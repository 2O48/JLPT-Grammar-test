import Foundation
import Security

struct AIConfiguration: Sendable {
    let baseURL: String
    let model: String
    let instruction: String
    let token: String

    var isConfigured: Bool {
        !baseURL.isEmpty && !model.isEmpty && !token.isEmpty
    }
}

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var baseURL: String
    @Published var model: String
    @Published var instruction: String
    @Published var token = ""
    @Published private(set) var tokenError: String?

    private let baseURLKey = "ai.baseURL"
    private let modelKey = "ai.model"
    private let instructionKey = "ai.instruction"
    private let defaults = UserDefaults.standard

    init() {
        baseURL = defaults.string(forKey: baseURLKey) ?? "https://api.openai.com/v1"
        model = defaults.string(forKey: modelKey) ?? "gpt-4.1-mini"
        instruction = defaults.string(forKey: instructionKey) ?? ""
        do {
            token = try KeychainTokenStore.read() ?? KeychainTokenStore.migrateLegacyToken() ?? ""
        } catch {
            tokenError = "无法读取钥匙串中的 Token。"
        }
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var configuration: AIConfiguration {
        AIConfiguration(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func save() throws {
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey)
        defaults.set(instruction.trimmingCharacters(in: .whitespacesAndNewlines), forKey: instructionKey)
        try KeychainTokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        tokenError = nil
    }

    func restore(from backup: AISettingsBackup) throws {
        baseURL = backup.baseURL
        model = backup.model
        instruction = backup.instruction
        token = backup.token
        try save()
    }
}

enum KeychainTokenStore {
    private static let account = "default"
    private static let service = "com.2o48.jlptgrammartest.ai-token"
    private static let legacyService = "com.2o48.jlptgrammartest.ai-token.local"

    static func read() throws -> String? {
        var query = synchronizableQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        guard !token.isEmpty else {
            try delete()
            return
        }

        let valueData = Data(token.utf8)
        let query = synchronizableQuery()
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: valueData] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = query
            attributes[kSecValueData as String] = valueData
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    static func delete() throws {
        let query = synchronizableQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func migrateLegacyToken() throws -> String? {
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }

        try save(token)
        let deleteStatus = SecItemDelete(legacyQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(deleteStatus)
        }
        return token
    }

    private static func synchronizableQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知的钥匙串状态"
                return "钥匙串操作失败（\(status)）：\(message)"
            }
        }
    }
}
