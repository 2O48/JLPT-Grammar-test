import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = GrammarLibrary()
    @StateObject private var settings = AISettingsStore()

    var body: some View {
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
        .font(WenfaFont.regular(17))
        .environmentObject(library)
        .environmentObject(settings)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                settings.refreshFromICloud()
            }
        }
    }
}
