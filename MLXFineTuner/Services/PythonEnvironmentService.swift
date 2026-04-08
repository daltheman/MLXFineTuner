import Foundation

@MainActor
class PythonEnvironmentService {
    nonisolated static let shared = PythonEnvironmentService()

    private let key = "MLXFineTuner.pythonPath"

    nonisolated init() {}

    var pythonPath: String {
        get { UserDefaults.standard.string(forKey: key) ?? "python3" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Searches common conda/venv locations for a Python that has mlx_lm.
    /// Returns the first match, or nil if none found.
    nonisolated func autoDetect() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/Caskroom/miniconda/base/bin/python3",
            "/opt/homebrew/Caskroom/miniforge/base/bin/python3",
            "\(home)/miniconda3/bin/python3",
            "\(home)/miniforge3/bin/python3",
            "\(home)/opt/anaconda3/bin/python3",
            "\(home)/anaconda3/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]

        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-c", "import mlx_lm"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { continue }
            process.waitUntilExit()
            if process.terminationStatus == 0 { return path }
        }
        return nil
    }

    /// Checks which key packages are available in the given Python.
    /// Takes pythonPath explicitly to avoid accessing @MainActor state from background.
    nonisolated func checkPackages(_ packages: [String], pythonPath: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for pkg in packages {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [pythonPath, "-c", "import \(pkg)"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            result[pkg] = process.terminationStatus == 0
        }
        return result
    }
}
