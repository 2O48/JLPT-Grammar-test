import Foundation
import SwiftData

enum AnswerVerdict: String, Codable {
    case correct
    case incorrect
    case pending

    var label: String {
        switch self {
        case .correct: "合理"
        case .incorrect: "需复习"
        case .pending: "待评判"
        }
    }
}

struct PracticeItem: Codable, Identifiable {
    var id = UUID()
    let level: String
    let prompt: String
    let expected: String
    let answer: String
    let verdict: AnswerVerdict
    let feedback: String
}

@Model
final class PracticeRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String = ""
    var total: Int = 0
    var correct: Int = 0
    var itemsData: Data = Data()

    init(createdAt: Date = .now, title: String, items: [PracticeItem]) {
        self.id = UUID()
        self.createdAt = createdAt
        self.title = title
        self.total = items.count
        self.correct = items.filter { $0.verdict == .correct }.count
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
    }

    var items: [PracticeItem] {
        (try? JSONDecoder().decode([PracticeItem].self, from: itemsData)) ?? []
    }
}

@Model
final class GrammarFavorite {
    var id: UUID = UUID()
    var grammarID: String = ""
    var createdAt: Date = Date()

    init(grammarID: String, createdAt: Date = .now) {
        self.id = UUID()
        self.grammarID = grammarID
        self.createdAt = createdAt
    }
}

struct AISettingsBackup: Codable {
    let baseURL: String
    let model: String
    let instruction: String
    let token: String

    @MainActor
    init(settings: AISettingsStore) {
        baseURL = settings.baseURL
        model = settings.model
        instruction = settings.instruction
        token = settings.token
    }
}

struct WenfaCeBackup: Codable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let settings: AISettingsBackup
    let records: [PracticeRecordBackup]
    let favorites: [GrammarFavoriteBackup]

    @MainActor
    init(settings: AISettingsStore, records: [PracticeRecord], favorites: [GrammarFavorite]) {
        version = Self.currentVersion
        exportedAt = .now
        self.settings = AISettingsBackup(settings: settings)
        self.records = records.map(PracticeRecordBackup.init)
        self.favorites = favorites.map(GrammarFavoriteBackup.init)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> WenfaCeBackup {
        let backup = try JSONDecoder().decode(WenfaCeBackup.self, from: data)
        guard backup.version == currentVersion else {
            throw WenfaCeBackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    @MainActor
    func apply(to modelContext: ModelContext, settingsStore: AISettingsStore) throws -> BackupImportSummary {
        try settingsStore.restore(from: settings)

        let existingRecords = try modelContext.fetch(FetchDescriptor<PracticeRecord>())
        let existingRecordIDs = Set(existingRecords.map(\.id))
        let existingFavorites = try modelContext.fetch(FetchDescriptor<GrammarFavorite>())
        let existingGrammarIDs = Set(existingFavorites.map(\.grammarID))

        let newRecords = records.filter { !existingRecordIDs.contains($0.id) }
        let newFavorites = favorites.filter { !existingGrammarIDs.contains($0.grammarID) }
        newRecords.forEach { modelContext.insert($0.model) }
        newFavorites.forEach { modelContext.insert($0.model) }
        try modelContext.save()

        return BackupImportSummary(records: newRecords.count, favorites: newFavorites.count)
    }
}

struct PracticeRecordBackup: Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let total: Int
    let correct: Int
    let itemsData: Data

    init(_ record: PracticeRecord) {
        id = record.id
        createdAt = record.createdAt
        title = record.title
        total = record.total
        correct = record.correct
        itemsData = record.itemsData
    }

    var model: PracticeRecord {
        let record = PracticeRecord(title: title, items: [])
        record.id = id
        record.createdAt = createdAt
        record.total = total
        record.correct = correct
        record.itemsData = itemsData
        return record
    }
}

struct GrammarFavoriteBackup: Codable {
    let id: UUID
    let grammarID: String
    let createdAt: Date

    init(_ favorite: GrammarFavorite) {
        id = favorite.id
        grammarID = favorite.grammarID
        createdAt = favorite.createdAt
    }

    var model: GrammarFavorite {
        let favorite = GrammarFavorite(grammarID: grammarID, createdAt: createdAt)
        favorite.id = id
        return favorite
    }
}

struct BackupImportSummary {
    let records: Int
    let favorites: Int
}

enum WenfaCeBackupError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "不支持备份文件版本 \(version)。"
        }
    }
}
