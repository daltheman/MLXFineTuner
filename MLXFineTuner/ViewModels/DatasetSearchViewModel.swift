import Foundation

@MainActor
class DatasetSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [HFDatasetResult] = []
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var downloadLog: [String] = []
    @Published var error: String?

    private let service = HuggingFaceService()
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        error = nil

        searchTask = Task {
            do {
                let r = try await service.searchDatasets(query: query)
                guard !Task.isCancelled else { return }
                results = r
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func downloadDataset(_ dataset: HFDatasetResult, toPath: String) async {
        isDownloading = true
        downloadLog = ["Downloading \(dataset.id)…"]
        error = nil

        let (stream, continuation) = AsyncStream<String>.makeStream()
        let pythonPath = PythonEnvironmentService.shared.pythonPath

        Task.detached(priority: .background) {
            do {
                let svc = HuggingFaceService()
                try svc.downloadDataset(id: dataset.id, toPath: toPath, pythonPath: pythonPath) { log in
                    continuation.yield(log)
                }
            } catch let err {
                continuation.yield("Error: \(err.localizedDescription)")
            }
            continuation.finish()
        }

        for await log in stream {
            downloadLog.append(log)
        }
        isDownloading = false
    }
}
