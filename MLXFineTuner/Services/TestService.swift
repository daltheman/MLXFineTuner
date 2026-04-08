import Foundation
import Combine

@MainActor
class TestService {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    let tokenSubject = PassthroughSubject<String, Never>()
    let metricsSubject = PassthroughSubject<TestMetrics, Never>()
    var onTermination: (() -> Void)?

    func generate(modelPath: String, adapterPath: String?, prompt: String, maxTokens: Int) throws {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        var args: [String] = [
            PythonEnvironmentService.shared.pythonPath, "-m", "mlx_lm", "generate",
            "--model", modelPath,
        ]
        if let adapterPath, !adapterPath.isEmpty {
            args += ["--adapter-path", adapterPath]
        }
        args += ["--prompt", prompt, "--max-tokens", "\(maxTokens)"]

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.environment = enrichedEnv()

        let startTime = Date()
        let buffer = StderrBuffer()

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.tokenSubject.send(text)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [buffer] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            buffer.append(text)
        }

        process.terminationHandler = { [weak self, buffer] _ in
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            let stderr = buffer.contents
            let metrics = Self.parseMetrics(from: stderr, totalLatencyMs: elapsed)
            DispatchQueue.main.async {
                self?.metricsSubject.send(metrics)
                self?.onTermination?()
            }
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

    // Parse mlx_lm stderr metrics like:
    //   Prompt: 6 tokens, 123.456 tokens-per-sec
    //   Generation: 50 tokens, 45.678 tokens-per-sec
    private nonisolated static func parseMetrics(from stderr: String, totalLatencyMs: Double) -> TestMetrics {
        var metrics = TestMetrics(totalLatencyMs: totalLatencyMs)

        let promptPattern = /Prompt:\s+(\d+)\s+tokens?,\s+([\d.]+)\s+tokens-per-sec/
        if let match = stderr.firstMatch(of: promptPattern) {
            metrics.promptTokens = Int(match.1) ?? 0
            metrics.promptTokensPerSecond = Double(match.2) ?? 0
        }

        let genPattern = /Generation:\s+(\d+)\s+tokens?,\s+([\d.]+)\s+tokens-per-sec/
        if let match = stderr.firstMatch(of: genPattern) {
            metrics.generationTokens = Int(match.1) ?? 0
            metrics.generationTokensPerSecond = Double(match.2) ?? 0
        }

        return metrics
    }

    private func enrichedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }
}

/// Thread-safe buffer for accumulating stderr output.
private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }

    var contents: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
