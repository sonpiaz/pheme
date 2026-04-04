import Foundation

/// Generates meeting title and structured summary via OpenAI Chat Completions.
/// Model: gpt-4o, Temperature: 0.3
actor SummaryGenerator {
    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public API

    /// Generate a concise title from the transcript.
    func generateTitle(transcript: String) async throws -> String {
        let truncated = String(transcript.prefix(2000))
        let response = try await chatCompletion(
            systemPrompt: SummaryPrompts.titleSystem,
            userContent: truncated,
            maxTokens: 50
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate a structured summary from the full transcript.
    func generateSummary(transcript: String) async throws -> String {
        let response = try await chatCompletion(
            systemPrompt: SummaryPrompts.summarySystem,
            userContent: transcript,
            maxTokens: 2048
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chat Completions

    private let maxRetries = 3

    private func chatCompletion(systemPrompt: String, userContent: String, maxTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.3,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = SummaryError.invalidResponse

        for attempt in 0..<maxRetries {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SummaryError.invalidResponse
            }

            // Rate limited — wait and retry with exponential backoff
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? pow(2.0, Double(attempt + 1))
                let delay = min(retryAfter, 60.0)
                NSLog("[Pheme] Rate limited, retrying in %.0fs (attempt %d/%d)", delay, attempt + 1, maxRetries)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                lastError = SummaryError.apiError(429, "Rate limited")
                continue
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SummaryError.apiError(httpResponse.statusCode, errorBody)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummaryError.parseError
            }

            return content
        }

        throw lastError
    }
}

enum SummaryError: LocalizedError {
    case invalidResponse
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from OpenAI"
        case .apiError(let code, let body): return "OpenAI API error (\(code)): \(body)"
        case .parseError: return "Failed to parse OpenAI response"
        }
    }
}
