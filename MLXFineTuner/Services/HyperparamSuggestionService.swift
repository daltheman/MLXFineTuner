import Foundation

struct HyperparamSuggestion: Codable {
    var iters: Int
    var batchSize: Int
    var learningRate: Double
    var loraLayers: Int
    var loraRank: Int
    var explanation: String
}

class HyperparamSuggestionService {

    enum SuggestionError: Error, LocalizedError {
        case noApiKey
        case noDataset
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey:                return "Anthropic API key not configured."
            case .noDataset:               return "Dataset path is not set."
            case .invalidResponse(let s):  return "Invalid response: \(s)"
            }
        }
    }

    func suggest(config: TrainingConfig, apiKey: String) async throws -> HyperparamSuggestion {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SuggestionError.noApiKey
        }
        guard !config.dataPath.isEmpty else {
            throw SuggestionError.noDataset
        }

        let samples = readSamples(from: config.dataPath, max: 10)
        let prompt  = buildPrompt(config: config, samples: samples)
        return try await callClaude(prompt: prompt, apiKey: apiKey)
    }

    // MARK: - Private

    private func readSamples(from dataPath: String, max count: Int) -> [String] {
        let trainURL = URL(fileURLWithPath: dataPath).appendingPathComponent("train.jsonl")
        guard let content = try? String(contentsOf: trainURL, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(count))
    }

    private func buildPrompt(config: TrainingConfig, samples: [String]) -> String {
        let samplesText = samples.isEmpty
            ? "(no samples could be read from the dataset)"
            : samples.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")

        return """
        You are an expert in fine-tuning large language models with LoRA (Low-Rank Adaptation) \
        using Apple's MLX framework (mlx_lm).

        I need hyperparameter recommendations for fine-tuning this model:
        - Base model: \(config.modelPath)
        - Dataset samples from train.jsonl (\(samples.count) shown):
        \(samplesText)

        Current hyperparameters:
        - Iterations: \(config.iters)
        - Batch size: \(config.batchSize)
        - Learning rate: \(String(format: "%.2e", config.learningRate))
        - LoRA layers (num-layers): \(config.loraLayers)
        - LoRA rank: \(config.loraRank)

        Analyze the dataset and model, then suggest optimal hyperparameters considering:
        1. Dataset characteristics: format (chat/completion/text), content complexity, \
        estimated total size.
        2. Model size inferred from the name (3B, 7B, etc.) — larger models need fewer \
        iterations and lower LR.
        3. Risk of overfitting (small dataset → fewer iters, low LR) vs. underfitting.
        4. Apple Silicon memory constraints (keep batch size modest).

        Respond ONLY with a valid JSON object — no markdown code fences, no extra text:
        {
          "iters": <integer, multiple of 100>,
          "batchSize": <integer 1-16>,
          "learningRate": <float, e.g. 0.0001>,
          "loraLayers": <integer 4-32>,
          "loraRank": <integer 4-64>,
          "explanation": "<2-3 concise sentences explaining the key choices>"
        }
        """
    }

    private func callClaude(prompt: String, apiKey: String) async throws -> HyperparamSuggestion {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "claude-opus-4-6",
            "max_tokens": 1024,
            "thinking": ["type": "adaptive"],
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SuggestionError.invalidResponse("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw SuggestionError.invalidResponse("HTTP \(http.statusCode): \(body)")
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let textBlock = content.first(where: { $0["type"] as? String == "text" }),
            let text    = textBlock["text"] as? String
        else {
            throw SuggestionError.invalidResponse("Could not parse Claude response")
        }

        // Strip any accidental markdown code fences
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let jsonData = cleaned.data(using: .utf8),
            let suggestion = try? JSONDecoder().decode(HyperparamSuggestion.self, from: jsonData)
        else {
            throw SuggestionError.invalidResponse("Could not parse suggestion JSON:\n\(text)")
        }

        return suggestion
    }
}
