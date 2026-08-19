import SwiftData
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: GrammarLibrary
    @State private var query = ""
    @State private var level = "全部"
    @State private var isShowingSetup = false
    @State private var pendingQuizConfiguration: QuizConfiguration?
    @State private var quizConfiguration: QuizConfiguration?

    private let levels = ["全部", "N5", "N4", "N3", "N2", "N1"]

    private var filteredEntries: [GrammarEntry] {
        library.entries.filter { entry in
            let matchesLevel = level == "全部" || entry.level == level
            let phrase = "\(entry.grammar) \(entry.meaning) \(entry.rule)".localizedCaseInsensitiveContains(query)
            return matchesLevel && (query.isEmpty || phrase)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError = library.loadError {
                    ContentUnavailableView("题库不可用", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    List {
                        Section {
                            Picker("级别", selection: $level) {
                                ForEach(levels, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            ForEach(filteredEntries) { entry in
                                NavigationLink(value: entry) {
                                    GrammarRow(entry: entry)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollBounceBehavior(.always)
                    .overlay {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
            }
            .navigationTitle("文法册")
            .navigationDestination(for: GrammarEntry.self) { GrammarDetailView(entry: $0) }
            .searchable(text: $query, prompt: "搜索语法、含义或用法")
            .toolbar {
                ToolbarItem(placement: WenfaToolbar.primaryAction) {
                    Button("开始练习", systemImage: "play.fill") { isShowingSetup = true }
                }
            }
        }
        .sheet(isPresented: $isShowingSetup, onDismiss: presentPendingQuiz) {
            PracticeSetupView(entries: library.entries) { configuration in
                pendingQuizConfiguration = configuration
                isShowingSetup = false
            }
        }
#if os(macOS)
        .sheet(item: $quizConfiguration) { configuration in
            PracticeFlowView(configuration: configuration, entries: library.entries)
        }
#else
        .fullScreenCover(item: $quizConfiguration) { configuration in
            PracticeFlowView(configuration: configuration, entries: library.entries)
        }
#endif
    }

    private func presentPendingQuiz() {
        quizConfiguration = pendingQuizConfiguration
        pendingQuizConfiguration = nil
    }
}

struct GrammarRow: View {
    let entry: GrammarEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.level)
                .font(WenfaFont.textStyle(.caption))
                .foregroundStyle(.teal)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.grammar).font(WenfaFont.textStyle(.headline))
                Text(entry.meaning).font(WenfaFont.textStyle(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct GrammarDetailView: View {
    let entry: GrammarEntry
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var practiceSync: PracticeDataSyncStore
    @Query private var favorites: [GrammarFavorite]

    private var favorite: GrammarFavorite? {
        favorites.first { $0.grammarID == entry.id }
    }

    var body: some View {
        List {
            Section {
                Text(entry.grammar).font(WenfaFont.textStyle(.title2, weight: .semibold))
                Text(entry.meaning).foregroundStyle(.secondary)
            }
            Section("接续") { Text(entry.rule.isEmpty ? "原始列表未提供接续规则。" : entry.rule) }
            if !entry.example.isEmpty {
                Section("例句") { Text(entry.example) }
            }
            if let related = entry.related, let url = URL(string: related.url) {
                Section { Link(related.label, destination: url) }
            }
        }
        .navigationTitle(entry.level)
        .wenfaInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: WenfaToolbar.primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: favorite == nil ? "star" : "star.fill")
                }
                .accessibilityLabel(favorite == nil ? "收藏此语法" : "取消收藏")
            }
        }
    }

    private func toggleFavorite() {
        if let favorite {
            modelContext.delete(favorite)
        } else {
            modelContext.insert(GrammarFavorite(grammarID: entry.id))
        }
        try? modelContext.save()
        Task { @MainActor in
            try? await practiceSync.sync(using: modelContext)
        }
    }
}
