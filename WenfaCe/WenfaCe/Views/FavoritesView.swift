import SwiftData
import SwiftUI

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var library: GrammarLibrary
    @EnvironmentObject private var practiceSync: PracticeDataSyncStore
    @Query(sort: \GrammarFavorite.createdAt, order: .reverse) private var favorites: [GrammarFavorite]

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "star",
                        description: Text("在语法详情页点击右上角星标即可收藏。")
                    )
                } else {
                    List {
                        ForEach(favorites) { favorite in
                            if let entry = library.entries.first(where: { $0.id == favorite.grammarID }) {
                                NavigationLink(value: entry) {
                                    GrammarRow(entry: entry)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏")
            .navigationDestination(for: GrammarEntry.self) { GrammarDetailView(entry: $0) }
            .toolbar {
#if os(iOS)
                if !favorites.isEmpty {
                    ToolbarItem(placement: WenfaToolbar.primaryAction) { EditButton() }
                }
#endif
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(favorites[index])
        }
        try? modelContext.save()
        Task { @MainActor in
            try? await practiceSync.sync(using: modelContext)
        }
    }
}
