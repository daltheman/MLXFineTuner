import Foundation
import Combine

/// Manages an `mlx_lm.lora` subprocess for LoRA fine-tuning.
///
/// Publishes log lines and parsed loss points via Combine subjects so the
/// view model can update the UI in real time.
@MainActor
class TrainingService {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    let logSubject = PassthroughSubject<String, Never>()
    let lossSubject = PassthroughSubject<LossPoint, Never>()

    var onTermination: (() -> Void)?

    // Matches lines like: "Iter 100: Train loss 2.345" or "Iter 100: Val loss 1.234"
    private let lossPattern = try! NSRegularExpression(
        pattern: #"Iter\s+(\d+):\s+(?:Train|Val)\s+loss\s+([\d.]+)"#,
        options: .caseInsensitive
    )

    /// Launches the training process with the given configuration.
    func start(config: TrainingConfig) throws {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Use /usr/bin/env to find python3 on the user's PATH
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = try buildArguments(config: config)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Inherit the user's shell environment so conda/venv python is found
        var env = ProcessInfo.processInfo.environment
        // Ensure common Python install locations are in PATH
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.onTermination?()
            }
        }

        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        try process.run()
    }

    /// Terminates the running training process and cleans up pipes.
    func stop() {
        process?.terminate()
        cleanup()
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func handleOutput(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            logSubject.send(trimmed)
            parseLoss(from: trimmed)
        }
    }

    private func buildArguments(config: TrainingConfig) throws -> [String] {
        // Write a temporary YAML config for LoRA-specific params not exposed as CLI flags
        let yamlContent = """
lora_parameters:
  rank: \(config.loraRank)
  alpha: \(config.loraRank)
  dropout: 0.0
  scale: 10.0
"""
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mlx_lora_config.yaml")
        try yamlContent.write(to: tmpURL, atomically: true, encoding: .utf8)

        var args = [
            PythonEnvironmentService.shared.pythonPath, "-m", "mlx_lm", "lora",
            "--model", config.modelPath,
            "--train",
            "--data", config.dataPath,
            "--iters", "\(config.iters)",
            "--batch-size", "\(config.batchSize)",
            "--learning-rate", "\(config.learningRate)",
            "--num-layers", "\(config.loraLayers)",
            "--adapter-path", config.savePath,
            "-c", tmpURL.path
        ]
        if config.disableValidation {
            args.append(contentsOf: ["--val-batches", "0"])
        }
        return args
    }

    private func parseLoss(from line: String) {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = lossPattern.firstMatch(in: line, range: range) else { return }
        guard
            let iterRange = Range(match.range(at: 1), in: line),
            let lossRange = Range(match.range(at: 2), in: line),
            let iteration = Int(line[iterRange]),
            let loss = Double(line[lossRange])
        else { return }

        lossSubject.send(LossPoint(iteration: iteration, loss: loss))
    }
}
