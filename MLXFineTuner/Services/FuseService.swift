import Foundation
import Combine

@MainActor
class FuseService {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    let logSubject = PassthroughSubject<String, Never>()
    var onTermination: (() -> Void)?

    func start(modelPath: String, adapterPath: String, savePath: String, deQuantize: Bool) throws {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        var args: [String] = [
            PythonEnvironmentService.shared.pythonPath, "-m", "mlx_lm", "fuse",
            "--model", modelPath,
            "--adapter-path", adapterPath,
            "--save-path", savePath,
        ]
        if deQuantize { args.append("--de-quantize") }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.environment = enrichedEnv()

        for pipe in [outPipe, errPipe] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                DispatchQueue.main.async {
                    for line in lines {
                        self?.logSubject.send(line)
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.onTermination?() }
        }

        self.process = process
        self.outputPipe = outPipe
        self.errorPipe = errPipe
        try process.run()
    }

    func stop() {
        process?.terminate()
        cleanup()
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil; outputPipe = nil; errorPipe = nil
    }

    private func enrichedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}
