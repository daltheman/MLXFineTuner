import Foundation

@MainActor
class ModelSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [HFModelResult] = []
    @Published var isLoading = false
    @Published var mlxCommunityOnly = true
    @Published var error: String?

    private let service = HuggingFaceService()
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        isLoading = true
        error = nil

        searchTask = Task {
            do {
                let r = try await service.searchModels(query: query, mlxCommunityOnly: mlxCommunityOnly)
                guard !Task.isCancelled else { return }
                results = r
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
