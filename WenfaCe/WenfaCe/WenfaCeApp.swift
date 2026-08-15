import SwiftData
import SwiftUI

@main
struct WenfaCeApp: App {
    private let modelContainer: ModelContainer

    init() {
        WenfaTypography.configure()
        let schema = Schema([PracticeRecord.self, GrammarFavorite.self])
        let configuration = ModelConfiguration(
            "PracticeHistory",
            schema: schema,
            cloudKitDatabase: .none
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create the practice history store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
