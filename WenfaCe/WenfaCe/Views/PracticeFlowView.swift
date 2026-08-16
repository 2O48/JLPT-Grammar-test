import SwiftData
import SwiftUI

enum QuizDirection: String, CaseIterable, Identifiable, Codable {
    case japaneseToChinese
    case chineseToJapanese
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .japaneseToChinese: "日 → 中"
        case .chineseToJapanese: "中 → 日"
        case .mixed: "混合"
        }
    }

    var detail: String {
        switch self {
        case .japaneseToChinese: "看日语语法，填写中文含义"
        case .chineseToJapanese: "看中文含义，填写对应语法"
        case .mixed: "每道题随机决定方向"
        }
    }
}

struct QuizConfiguration: Identifiable {
    let id = UUID()
    let levels: Set<String>
    let count: Int
    let direction: QuizDirection
}

private struct QuizQuestion: Identifiable {
    let id = UUID()
    let entry: GrammarEntry
    let direction: QuizDirection
}

@MainActor
private final class PracticeSession: ObservableObject {
    let questions: [QuizQuestion]
    @Published var index = 0
    @Published var answers: [String]
    @Published var isSubmitting = false

    init(configuration: QuizConfiguration, entries: [GrammarEntry]) {
        let pool = entries.filter { configuration.levels.contains($0.level) }
        questions = Array(pool.shuffled().prefix(configuration.count)).map { entry in
            let direction: QuizDirection
            if configuration.direction == .mixed {
                direction = Bool.random() ? .japaneseToChinese : .chineseToJapanese
            } else {
                direction = configuration.direction
            }
            return QuizQuestion(entry: entry, direction: direction)
        }
        answers = Array(repeating: "", count: questions.count)
    }

    var currentQuestion: QuizQuestion { questions[index] }
    var progress: Double { questions.isEmpty ? 0 : Double(index + 1) / Double(questions.count) }
    var isLastQuestion: Bool { index == questions.count - 1 }

    func next() {
        guard !isLastQuestion else { return }
        index += 1
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
    }

    func evaluatedItems(using configuration: AIConfiguration) async -> [PracticeItem] {
        isSubmitting = true
        defer { isSubmitting = false }

        var items: [PracticeItem] = []
        for (offset, question) in questions.enumerated() {
            let answer = answers[offset].trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = question.direction == .japaneseToChinese ? question.entry.grammar : question.entry.meaning
            let expected = question.direction == .japaneseToChinese ? question.entry.meaning : question.entry.grammar

            guard configuration.isConfigured else {
                items.append(PracticeItem(level: question.entry.level, prompt: prompt, expected: expected, answer: answer, verdict: .pending, feedback: "未配置 AI 接口，等待以后评判。"))
                continue
            }

            do {
                let evaluation = try await AIClient.evaluate(
                    entry: question.entry,
                    direction: question.direction,
                    answer: answer,
                    configuration: configuration
                )
                items.append(PracticeItem(level: question.entry.level, prompt: prompt, expected: expected, answer: answer, verdict: evaluation.verdict, feedback: evaluation.feedback))
            } catch {
                items.append(PracticeItem(level: question.entry.level, prompt: prompt, expected: expected, answer: answer, verdict: .pending, feedback: "AI 评判未完成：\(error.localizedDescription)"))
            }
        }
        return items
    }
}

struct PracticeSetupView: View {
    let entries: [GrammarEntry]
    let start: (QuizConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var levels: Set<String> = ["N5", "N4", "N3", "N2", "N1"]
    @State private var count = 10
    @State private var direction: QuizDirection = .japaneseToChinese

    private let allLevels = ["N5", "N4", "N3", "N2", "N1"]
    private var availableCount: Int { entries.filter { levels.contains($0.level) }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section("题目数量") {
                    Stepper("\(count) 题", value: $count, in: 5...min(30, max(5, availableCount)), step: 5)
                }
                Section("题目范围") {
                    ForEach(allLevels, id: \.self) { level in
                        Toggle(level, isOn: Binding(
                            get: { levels.contains(level) },
                            set: { selected in
                                if selected { levels.insert(level) } else { levels.remove(level) }
                                count = min(count, max(5, availableCount))
                            }
                        ))
                    }
                }
                Section("答题方式") {
                    Picker("方向", selection: $direction) {
                        ForEach(QuizDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(direction.detail).font(WenfaFont.textStyle(.footnote)).foregroundStyle(.secondary)
                }
            }
            .background(Color.wenfaGroupedBackground)
            .navigationTitle("设置练习")
            .wenfaInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        start(QuizConfiguration(levels: levels, count: count, direction: direction))
                    }
                    .disabled(levels.isEmpty || availableCount < 5)
                }
            }
        }
    }
}

struct PracticeFlowView: View {
    let configuration: QuizConfiguration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AISettingsStore
    @StateObject private var session: PracticeSession
    @State private var isShowingQuitAlert = false
    @State private var isShowingCompletion = false

    init(configuration: QuizConfiguration, entries: [GrammarEntry]) {
        self.configuration = configuration
        _session = StateObject(wrappedValue: PracticeSession(configuration: configuration, entries: entries))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: session.progress)
                    .tint(.teal)
                    .padding(.horizontal)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("第 \(session.index + 1) / \(session.questions.count) 题")
                            .font(WenfaFont.textStyle(.subheadline))
                            .foregroundStyle(.secondary)
                        Text(session.currentQuestion.entry.level)
                            .font(WenfaFont.textStyle(.caption, weight: .semibold))
                            .foregroundStyle(.teal)
                        Text(session.currentQuestion.direction == .japaneseToChinese ? "写出这个语法的中文含义" : "写出对应的日语语法")
                            .font(WenfaFont.textStyle(.title3))
                        Text(session.currentQuestion.direction == .japaneseToChinese ? session.currentQuestion.entry.grammar : session.currentQuestion.entry.meaning)
                            .font(WenfaFont.textStyle(.largeTitle, weight: .semibold))
                            .textSelection(.enabled)
                        if !session.currentQuestion.entry.rule.isEmpty {
                            Text(session.currentQuestion.direction == .japaneseToChinese ? session.currentQuestion.entry.rule : "根据中文含义写出对应的日语语法。")
                                .font(WenfaFont.textStyle(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $session.answers[session.index])
                            .frame(minHeight: 140)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        if !session.currentQuestion.entry.example.isEmpty {
                            DisclosureGroup("查看例句") {
                                Text(session.currentQuestion.entry.example)
                                    .font(WenfaFont.textStyle(.subheadline))
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .padding(24)
                }
                HStack {
                    Button("上一题", systemImage: "chevron.left") { session.previous() }
                        .disabled(session.index == 0 || session.isSubmitting)
                    Spacer()
                    if session.isLastQuestion {
                        Button("提交并评判", systemImage: "checkmark") { submit() }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .disabled(session.isSubmitting)
                    } else {
                        Button("下一题", systemImage: "chevron.right") { session.next() }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .disabled(session.isSubmitting)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.wenfaBackground)
            .navigationTitle("练习")
            .wenfaInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: WenfaToolbar.primaryAction) {
                    Button("结束") { isShowingQuitAlert = true }
                        .disabled(session.isSubmitting)
                }
            }
            .overlay {
                if session.isSubmitting {
                    ProgressView("AI 正在评判…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("结束本次练习？", isPresented: $isShowingQuitAlert) {
                Button("继续答题", role: .cancel) {}
                Button("结束", role: .destructive) { dismiss() }
            } message: {
                Text("未提交的答案不会保存。")
            }
            .alert("练习已保存", isPresented: $isShowingCompletion) {
                Button("完成") { dismiss() }
            } message: {
                Text("可在练习记录中查看本次作答与 AI 评价。")
            }
        }
    }

    private func submit() {
        Task {
            let items = await session.evaluatedItems(using: settings.configuration)
            let selectedLevels = configuration.levels.sorted().joined(separator: " / ")
            modelContext.insert(PracticeRecord(title: "\(items.count) 题 · \(selectedLevels)", items: items))
            try? modelContext.save()
            isShowingCompletion = true
        }
    }
}
