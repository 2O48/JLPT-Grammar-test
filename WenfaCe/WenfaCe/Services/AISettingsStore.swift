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
    @Published private(set) var lastSyncDate: Date?

    private let baseURLKey = "ai.baseURL"
    private let modelKey = "ai.model"
    private let instructionKey = "ai.instruction"
    private let lastSettingsUpdateKey = "ai.settings.updatedAt"
    private let cloudSettingsKey = "ai.settings.v1"
    private let defaults = UserDefaults.standard
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudStoreObserver: NSObjectProtocol?

    init() {
        baseURL = defaults.string(forKey: baseURLKey) ?? "https://api.openai.com/v1"
        model = defaults.string(forKey: modelKey) ?? "gpt-4.1-mini"
        instruction = defaults.string(forKey: instructionKey) ?? ""
        do {
            token = try KeychainTokenStore.read() ?? KeychainTokenStore.migrateLegacyToken() ?? ""
        } catch {
            tokenError = "无法读取钥匙串中的 Token。"
        }
        lastSyncDate = defaults.object(forKey: lastSettingsUpdateKey) as? Date
        cloudStoreObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFromICloud()
            }
        }
        refreshFromICloud()
    }

    deinit {
        if let cloudStoreObserver {
            NotificationCenter.default.removeObserver(cloudStoreObserver)
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
        let updatedAt = Date()
        let payload = SyncedAISettings(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: updatedAt
        )
        apply(payload)
        try KeychainTokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        cloudStore.set(try JSONEncoder().encode(payload), forKey: cloudSettingsKey)
        cloudStore.synchronize()
        tokenError = nil
    }

    func restore(from backup: AISettingsBackup) throws {
        baseURL = backup.baseURL
        model = backup.model
        instruction = backup.instruction
        token = backup.token
        try save()
    }

    func refreshFromICloud() {
        cloudStore.synchronize()
        if let data = cloudStore.data(forKey: cloudSettingsKey),
           let payload = try? JSONDecoder().decode(SyncedAISettings.self, from: data),
           payload.updatedAt > (lastSyncDate ?? .distantPast) {
            apply(payload)
        }

        do {
            if let syncedToken = try KeychainTokenStore.read(), !syncedToken.isEmpty {
                token = syncedToken
            }
            tokenError = nil
        } catch {
            tokenError = "无法读取钥匙串中的 Token。"
        }
    }

    private func apply(_ payload: SyncedAISettings) {
        baseURL = payload.baseURL
        model = payload.model
        instruction = payload.instruction
        lastSyncDate = payload.updatedAt
        defaults.set(payload.baseURL, forKey: baseURLKey)
        defaults.set(payload.model, forKey: modelKey)
        defaults.set(payload.instruction, forKey: instructionKey)
        defaults.set(payload.updatedAt, forKey: lastSettingsUpdateKey)
    }
}

private struct SyncedAISettings: Codable {
    let baseURL: String
    let model: String
    let instruction: String
    let updatedAt: Date
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
        let legacyIdentityQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account
        ]
        var legacyQuery = legacyIdentityQuery
        legacyQuery[kSecReturnData as String] = true
        legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }

        try save(token)
        let deleteStatus = SecItemDelete(legacyIdentityQuery as CFDictionary)
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
