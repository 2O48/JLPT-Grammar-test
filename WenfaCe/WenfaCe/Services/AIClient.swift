import Foundation

struct AIEvaluation {
    let verdict: AnswerVerdict
    let feedback: String
}

enum AIClientError: LocalizedError {
    case invalidURL
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "AI 接口地址无效。"
        case let .server(status): "AI 接口返回 \(status)。"
        case .invalidResponse: "AI 接口没有返回可用的评价。"
        }
    }
}

struct AIClient {
    private struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
        let responseFormat: ResponseFormat

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case responseFormat = "response_format"
        }

        struct ResponseFormat: Encodable {
            let type = "json_object"
        }
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct EvaluationBody: Decodable {
        let verdict: String
        let feedback: String?
    }

    static func evaluate(
        entry: GrammarEntry,
        direction: QuizDirection,
        answer: String,
        configuration: AIConfiguration
    ) async throws -> AIEvaluation {
        let trimmedBaseURL = configuration.baseURL
        let endpoint = trimmedBaseURL.hasSuffix("/")
            ? "\(trimmedBaseURL)chat/completions"
            : "\(trimmedBaseURL)/chat/completions"
        guard let url = URL(string: endpoint) else { throw AIClientError.invalidURL }

        let prompt = direction == .japaneseToChinese ? entry.grammar : entry.meaning
        let expected = direction == .japaneseToChinese ? entry.meaning : entry.grammar
        let directionText = direction == .japaneseToChinese ? "日语语法到中文含义" : "中文含义到日语语法"
        let instruction = """
        你是一位严谨的 JLPT 日语语法教师。判断学生的开放式答案是否合理，不能只做字符串匹配。
        题目方向：\(directionText)。题目：\(prompt)。参考答案：\(expected)。学生答案：\(answer.isEmpty ? "（未作答）" : answer)。\(configuration.instruction)
        只返回 JSON，格式为 {"verdict":"correct" 或 "incorrect", "feedback":"不超过50字的中文说明"}。
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: configuration.model,
                messages: [.init(role: "user", content: instruction)],
                temperature: 0.15,
                responseFormat: .init()
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw AIClientError.server(httpResponse.statusCode) }
        let result = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = result.choices.first?.message.content,
              let jsonData = content.data(using: .utf8),
              let evaluation = try? JSONDecoder().decode(EvaluationBody.self, from: jsonData) else {
            throw AIClientError.invalidResponse
        }
        return AIEvaluation(
            verdict: evaluation.verdict == "correct" ? .correct : .incorrect,
            feedback: evaluation.feedback ?? "AI 未返回评价。"
        )
    }
}
