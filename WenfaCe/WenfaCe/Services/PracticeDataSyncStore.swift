import CloudKit
import Combine
import Foundation
import SwiftData

@MainActor
final class PracticeDataSyncStore: ObservableObject {
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isSyncing = false

    private let database = CKContainer(identifier: "iCloud.com.2o48.jlptgrammartest").privateCloudDatabase
    private let defaults = UserDefaults.standard
    private let lastSyncDateKey = "practice-data.lastSyncDate"

    init() {
        lastSyncDate = defaults.object(forKey: lastSyncDateKey) as? Date
    }

    func sync(using modelContext: ModelContext) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        try modelContext.save()
        let remote = try await fetchRemoteSnapshot()
        try merge(remote, into: modelContext)
        try modelContext.save()

        let local = try localSnapshot(from: modelContext)
        try await replaceRemote(with: local, remote: remote)
        let now = Date()
        lastSyncDate = now
        defaults.set(now, forKey: lastSyncDateKey)
    }

    func refreshFromICloud(using modelContext: ModelContext) async {
        guard !isSyncing else { return }
        do {
            isSyncing = true
            let remote = try await fetchRemoteSnapshot()
            try merge(remote, into: modelContext)
            try modelContext.save()
            let now = Date()
            lastSyncDate = now
            defaults.set(now, forKey: lastSyncDateKey)
        } catch {
            // The manual sync button retries transient CloudKit failures.
        }
        isSyncing = false
    }

    private func localSnapshot(from modelContext: ModelContext) throws -> PracticeSnapshot {
        PracticeSnapshot(
            records: try modelContext.fetch(FetchDescriptor<PracticeRecord>()),
            favorites: try modelContext.fetch(FetchDescriptor<GrammarFavorite>())
        )
    }

    private func merge(_ remote: PracticeSnapshot, into modelContext: ModelContext) throws {
        let localRecords = try modelContext.fetch(FetchDescriptor<PracticeRecord>())
        let localRecordIDs = Set(localRecords.map(\.id))
        for record in remote.records.compactMap(\.practiceModel) where !localRecordIDs.contains(record.id) {
            modelContext.insert(record)
        }

        let localFavorites = try modelContext.fetch(FetchDescriptor<GrammarFavorite>())
        let localGrammarIDs = Set(localFavorites.map(\.grammarID))
        for favorite in remote.favorites.compactMap(\.favoriteModel) where !localGrammarIDs.contains(favorite.grammarID) {
            modelContext.insert(favorite)
        }
    }

    private func fetchRemoteSnapshot() async throws -> PracticeSnapshot {
        async let records = fetchRecords(ofType: RecordType.practiceRecord)
        async let favorites = fetchRecords(ofType: RecordType.grammarFavorite)
        return PracticeSnapshot(records: try await records, favorites: try await favorites)
    }

    private func fetchRecords(ofType recordType: String) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKQueryOperation(query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)))
            var records: [CKRecord] = []
            operation.recordFetchedBlock = { records.append($0) }
            operation.queryCompletionBlock = { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records)
                }
            }
            database.add(operation)
        }
    }

    private func replaceRemote(with local: PracticeSnapshot, remote: PracticeSnapshot) async throws {
        let recordsToSave = local.records + local.favorites
        let localIDs = Set(recordsToSave.map(\.recordID))
        let recordsToDelete = (remote.records + remote.favorites)
            .map(\.recordID)
            .filter { !localIDs.contains($0) }

        guard !recordsToSave.isEmpty || !recordsToDelete.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: recordsToDelete
            )
            operation.savePolicy = .changedKeys
            operation.modifyRecordsCompletionBlock = { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            database.add(operation)
        }
    }
}

private enum RecordType {
    static let practiceRecord = "PracticeRecord"
    static let grammarFavorite = "GrammarFavorite"
}

private struct PracticeSnapshot {
    let records: [CKRecord]
    let favorites: [CKRecord]

    init(records: [PracticeRecord], favorites: [GrammarFavorite]) {
        self.records = records.map(CloudKitRecord.init).map(\.record)
        self.favorites = favorites.map(CloudKitRecord.init).map(\.record)
    }

    init(records: [CKRecord], favorites: [CKRecord]) {
        self.records = records
        self.favorites = favorites
    }
}

private struct CloudKitRecord {
    let record: CKRecord

    var recordID: CKRecord.ID { record.recordID }

    init(_ model: PracticeRecord) {
        let record = CKRecord(recordType: RecordType.practiceRecord, recordID: CKRecord.ID(recordName: model.id.uuidString))
        record["createdAt"] = model.createdAt as NSDate
        record["title"] = model.title as NSString
        record["total"] = model.total as NSNumber
        record["correct"] = model.correct as NSNumber
        record["itemsData"] = model.itemsData as NSData
        self.record = record
    }

    init(_ model: GrammarFavorite) {
        let record = CKRecord(recordType: RecordType.grammarFavorite, recordID: CKRecord.ID(recordName: model.id.uuidString))
        record["createdAt"] = model.createdAt as NSDate
        record["grammarID"] = model.grammarID as NSString
        self.record = record
    }
}

private extension CKRecord {
    var practiceModel: PracticeRecord? {
        guard let title = self["title"] as? String,
              let createdAt = self["createdAt"] as? Date,
              let total = self["total"] as? Int,
              let correct = self["correct"] as? Int,
              let itemsData = self["itemsData"] as? Data,
              let id = UUID(uuidString: recordID.recordName) else { return nil }
        let model = PracticeRecord(title: title, items: [])
        model.id = id
        model.createdAt = createdAt
        model.total = total
        model.correct = correct
        model.itemsData = itemsData
        return model
    }

    var favoriteModel: GrammarFavorite? {
        guard let grammarID = self["grammarID"] as? String,
              let createdAt = self["createdAt"] as? Date,
              let id = UUID(uuidString: recordID.recordName) else { return nil }
        let model = GrammarFavorite(grammarID: grammarID, createdAt: createdAt)
        model.id = id
        return model
    }
}
