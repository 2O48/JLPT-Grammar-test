import SwiftData
import SwiftUI

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var practiceSync: PracticeDataSyncStore
    @Query(sort: \PracticeRecord.createdAt, order: .reverse) private var records: [PracticeRecord]
    @State private var isShowingClearAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "还没有练习记录",
                        systemImage: "checklist",
                        description: Text("完成一轮练习后会显示在这里。")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(record.title).font(WenfaFont.textStyle(.headline))
                                        Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                                            .font(WenfaFont.textStyle(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(record.correct)/\(record.total)")
                                        .font(WenfaFont.textStyle(.subheadline))
                                        .foregroundStyle(.teal)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("练习记录")
            .toolbar {
                if !records.isEmpty {
#if os(iOS)
                    ToolbarItem(placement: WenfaToolbar.leadingAction) { EditButton() }
#endif
                    ToolbarItem(placement: WenfaToolbar.primaryAction) {
                        Button("清除", role: .destructive) { isShowingClearAlert = true }
                    }
                }
            }
            .alert("清除全部记录？", isPresented: $isShowingClearAlert) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive, action: clearAll)
            } message: {
                Text("此操作只会删除当前设备上的本地记录。")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(records[index]) }
        persistAndSync()
    }

    private func clearAll() {
        for record in records { modelContext.delete(record) }
        persistAndSync()
    }

    private func persistAndSync() {
        try? modelContext.save()
        Task { @MainActor in
            try? await practiceSync.sync(using: modelContext)
        }
    }
}

struct RecordDetailView: View {
    let record: PracticeRecord

    var body: some View {
        List {
            Section {
                LabeledContent("完成时间", value: record.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("结果", value: "\(record.correct) / \(record.total) 合理")
            }
            Section("逐题评价") {
                ForEach(record.items) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(item.level).font(WenfaFont.textStyle(.caption, weight: .semibold)).foregroundStyle(.teal)
                            Text(item.verdict.label)
                                .font(WenfaFont.textStyle(.caption, weight: .semibold))
                                .foregroundStyle(item.verdict == .correct ? .green : item.verdict == .incorrect ? .orange : .secondary)
                        }
                        Text(item.prompt).font(WenfaFont.textStyle(.headline))
                        LabeledContent("你的答案", value: item.answer.isEmpty ? "未作答" : item.answer)
                            .font(WenfaFont.textStyle(.subheadline))
                        LabeledContent("参考", value: item.expected).font(WenfaFont.textStyle(.subheadline))
                        Text(item.feedback).font(WenfaFont.textStyle(.footnote)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle(record.title)
        .wenfaInlineNavigationTitle()
    }
}
