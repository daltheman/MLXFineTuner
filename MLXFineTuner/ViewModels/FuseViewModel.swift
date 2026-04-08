import Foundation
import Combine

/// Manages the Export tab's fuse workflow, bridging ``FuseService`` to the UI.
@MainActor
class FuseViewModel: ObservableObject {
    static var defaultSavePath: String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return downloads?.appendingPathComponent("fused-model").path ?? ""
    }

    @Published var modelPath: String = ""
    @Published var adapterPath: String = ""
    @Published var savePath: String = FuseViewModel.defaultSavePath
    @Published var deQuantize: Bool = false
    @Published var logs: [String] = []
    @Published var isRunning: Bool = false
    @Published var errorMessage: String?
    @Published var didSucceed: Bool = false

    private let service = FuseService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        service.logSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in self?.logs.append(line) }
            .store(in: &cancellables)
    }

    /// Pre-fill from training config (called on tab appear).
    func syncFromConfig(modelPath: String, adapterPath: String) {
        if self.modelPath.isEmpty { self.modelPath = modelPath }
        if self.adapterPath.isEmpty { self.adapterPath = adapterPath }
    }

    /// Validates the output path and launches the fuse process.
    func start() {
        guard !isRunning else { return }

        guard savePath.hasPrefix("/") else {
            errorMessage = "Output Path must be an absolute path (e.g. /Users/…/fused-model). Relative paths are not allowed."
            return
        }

        logs.removeAll()
        errorMessage = nil
        didSucceed = false
        isRunning = true

        service.onTermination = { [weak self] in
            guard let self else { return }
            // Check last log line for errors
            let hasError = self.logs.last?.lowercased().contains("error") ?? false
            self.didSucceed = !hasError
            self.isRunning = false
        }

        do {
            try service.start(
                modelPath: modelPath,
                adapterPath: adapterPath,
                savePath: savePath,
                deQuantize: deQuantize
            )
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    /// Terminates the running fuse process.
    func stop() {
        service.stop()
        isRunning = false
    }
}
