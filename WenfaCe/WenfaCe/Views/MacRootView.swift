import SwiftUI

#if os(macOS)
struct MacRootView: View {
    @State private var selection: MacSection? = .library

    var body: some View {
        NavigationSplitView {
            List(MacSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("文法册")
        } detail: {
            switch selection ?? .library {
            case .library:
                LibraryView()
            case .favorites:
                FavoritesView()
            case .records:
                RecordsView()
            case .settings:
                AISettingsView()
            }
        }
        .frame(minWidth: 980, minHeight: 680)
    }
}

private enum MacSection: String, CaseIterable, Identifiable {
    case library
    case favorites
    case records
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "题库"
        case .favorites: "收藏"
        case .records: "练习记录"
        case .settings: "AI 设置"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .favorites: "star"
        case .records: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
#endif
