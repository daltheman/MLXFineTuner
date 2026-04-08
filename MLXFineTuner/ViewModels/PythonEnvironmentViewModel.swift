import Foundation

@MainActor
class PythonEnvironmentViewModel: ObservableObject {
    @Published var pythonPath: String {
        didSet { PythonEnvironmentService.shared.pythonPath = pythonPath }
    }
    @Published var isDetecting = false
    @Published var packageStatus: [String: Bool] = [:]
    @Published var isCheckingPackages = false

    private let requiredPackages = ["mlx_lm", "fitz", "huggingface_hub"]

    init() {
        pythonPath = PythonEnvironmentService.shared.pythonPath
    }

    func autoDetect() {
        isDetecting = true
        Task {
            let found = await Task.detached(priority: .background) {
                PythonEnvironmentService.shared.autoDetect()
            }.value
            if let path = found { pythonPath = path }
            isDetecting = false
            await checkPackages()
        }
    }

    func checkPackages() async {
        isCheckingPackages = true
        let path = PythonEnvironmentService.shared.pythonPath
        let status = await Task.detached(priority: .background) {
            PythonEnvironmentService.shared.checkPackages(["mlx_lm", "fitz", "huggingface_hub"], pythonPath: path)
        }.value
        packageStatus = status
        isCheckingPackages = false
    }
}
