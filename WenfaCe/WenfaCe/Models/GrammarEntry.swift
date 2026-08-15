import Foundation

struct GrammarEntry: Codable, Identifiable, Hashable {
    struct RelatedArticle: Codable, Hashable {
        let url: String
        let label: String
    }

    let id: String
    let level: String
    let grammar: String
    let meaning: String
    let rule: String
    let example: String
    let related: RelatedArticle?
}

@MainActor
final class GrammarLibrary: ObservableObject {
    @Published private(set) var entries: [GrammarEntry] = []
    @Published private(set) var loadError: String?

    init() {
        load()
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "Grammar", withExtension: "json") else {
            loadError = "未找到内置题库。"
            return
        }

        do {
            entries = try JSONDecoder().decode([GrammarEntry].self, from: Data(contentsOf: url))
        } catch {
            loadError = "题库无法读取：\(error.localizedDescription)"
        }
    }
}
