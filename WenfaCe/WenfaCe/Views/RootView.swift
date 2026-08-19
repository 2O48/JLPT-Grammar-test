import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @StateObject private var library = GrammarLibrary()
    @StateObject private var settings = AISettingsStore()
    @StateObject private var practiceSync = PracticeDataSyncStore()

    var body: some View {
        Group {
#if os(macOS)
            MacRootView()
#else
            TabView {
                LibraryView()
                    .tabItem { Label("题库", systemImage: "books.vertical") }
                FavoritesView()
                    .tabItem { Label("收藏", systemImage: "star") }
                RecordsView()
                    .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
                AISettingsView()
                    .tabItem { Label("AI 设置", systemImage: "gearshape") }
            }
            .tint(.teal)
#endif
        }
        .font(WenfaFont.regular(17))
        .environmentObject(library)
        .environmentObject(settings)
        .environmentObject(practiceSync)
        .task {
            await practiceSync.refreshFromICloud(using: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                settings.refreshFromICloud()
                Task { await practiceSync.refreshFromICloud(using: modelContext) }
            }
        }
    }
}
