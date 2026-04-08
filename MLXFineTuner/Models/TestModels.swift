import Foundation

/// Whether the Test tab should load a LoRA adapter on top of a base model or use a standalone fused model.
enum TestModelSource: String, CaseIterable, Identifiable {
    case loraAdapter = "LoRA Adapter"
    case fusedModel  = "Fused Model"

    var id: String { rawValue }
}

/// A single message in the Test tab's chat interface.
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp = Date()

    enum Role {
        case user
        case assistant
    }
}

/// Performance metrics parsed from `mlx_lm.generate` stderr output after a generation completes.
struct TestMetrics {
    var promptTokens: Int = 0
    var promptTokensPerSecond: Double = 0
    var generationTokens: Int = 0
    var generationTokensPerSecond: Double = 0
    var totalLatencyMs: Double = 0
}
