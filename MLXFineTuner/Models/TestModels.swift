import Foundation

enum TestModelSource: String, CaseIterable, Identifiable {
    case loraAdapter = "LoRA Adapter"
    case fusedModel  = "Fused Model"

    var id: String { rawValue }
}

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

struct TestMetrics {
    var promptTokens: Int = 0
    var promptTokensPerSecond: Double = 0
    var generationTokens: Int = 0
    var generationTokensPerSecond: Double = 0
    var totalLatencyMs: Double = 0
}
