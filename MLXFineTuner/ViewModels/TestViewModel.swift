import Foundation
import Combine

@MainActor
class TestViewModel: ObservableObject {
    @Published var modelSource: TestModelSource = .fusedModel
    @Published var baseModelPath: String = ""
    @Published var adapterPath: String = ""
    @Published var fusedModelPath: String = ""
    @Published var maxTokens: Int = 256
    @Published var messages: [ChatMessage] = []
    @Published var currentInput: String = ""
    @Published var isGenerating: Bool = false
    @Published var lastMetrics: TestMetrics?
    @Published var errorMessage: String?

    private let service = TestService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.tokenSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chunk in
                MainActor.assumeIsolated {
                    guard let self, !self.messages.isEmpty else { return }
                    let lastIndex = self.messages.count - 1
                    if self.messages[lastIndex].role == .assistant {
                        self.messages[lastIndex].content += chunk
                    }
                }
            }
            .store(in: &cancellables)

        service.metricsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metrics in
                MainActor.assumeIsolated {
                    self?.lastMetrics = metrics
                    self?.isGenerating = false
                }
            }
            .store(in: &cancellables)
    }

    /// Pre-fill paths from TrainingViewModel config.
    func syncFromConfig(modelPath: String, adapterPath: String, fusedModelPath: String) {
        if baseModelPath.isEmpty { baseModelPath = modelPath }
        if self.adapterPath.isEmpty { self.adapterPath = adapterPath }
        if self.fusedModelPath.isEmpty { self.fusedModelPath = fusedModelPath }
    }

    func send() {
        let text = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        let resolvedModelPath: String
        let resolvedAdapterPath: String?

        switch modelSource {
        case .loraAdapter:
            guard baseModelPath.hasPrefix("/") || !baseModelPath.isEmpty else {
                errorMessage = "Base model path is required for LoRA adapter mode."
                return
            }
            resolvedModelPath = baseModelPath
            resolvedAdapterPath = adapterPath.isEmpty ? nil : adapterPath
        case .fusedModel:
            guard !fusedModelPath.isEmpty else {
                errorMessage = "Fused model path is required."
                return
            }
            resolvedModelPath = fusedModelPath
            resolvedAdapterPath = nil
        }

        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text))
        messages.append(ChatMessage(role: .assistant, content: ""))
        currentInput = ""
        isGenerating = true

        service.onTermination = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // If still generating (no metrics received yet), mark done
                if self.isGenerating {
                    self.isGenerating = false
                }
            }
        }

        do {
            try service.generate(
                modelPath: resolvedModelPath,
                adapterPath: resolvedAdapterPath,
                prompt: text,
                maxTokens: maxTokens
            )
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
            // Remove the empty assistant message
            if let last = messages.last, last.role == .assistant, last.content.isEmpty {
                messages.removeLast()
            }
        }
    }

    func stop() {
        service.stop()
        isGenerating = false
    }

    func clearChat() {
        messages.removeAll()
        lastMetrics = nil
        errorMessage = nil
    }
}
