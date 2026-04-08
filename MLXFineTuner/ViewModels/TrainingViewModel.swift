import Foundation
import Combine
import SwiftUI

private let kCurrentConfig = "MLXFineTuner.config"
private let kPresets       = "MLXFineTuner.presets"

@MainActor
class TrainingViewModel: ObservableObject {
    @Published var config: TrainingConfig
    @Published var logs: [String] = []
    @Published var lossHistory: [LossPoint] = []
    @Published var isRunning = false
    @Published var errorMessage: String?

    @Published var metricHistory: [MetricPoint] = []
    @Published var currentMetrics = SystemMetrics()

    // Named presets — persisted as JSON in UserDefaults
    @Published var presets: [String: TrainingConfig] = [:]

    private let service = TrainingService()
    private let metricsService = SystemMetricsService()
    private var metricsTimer: Timer?
    private var trainingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load last-used config (or fall back to defaults)
        if let data = UserDefaults.standard.data(forKey: kCurrentConfig),
           let saved = try? JSONDecoder().decode(TrainingConfig.self, from: data) {
            _config = Published(initialValue: saved)
        } else {
            _config = Published(initialValue: TrainingConfig())
        }

        // Load saved presets
        if let data = UserDefaults.standard.data(forKey: kPresets),
           let saved = try? JSONDecoder().decode([String: TrainingConfig].self, from: data) {
            _presets = Published(initialValue: saved)
        } else {
            _presets = Published(initialValue: [:])
        }

        // Wire up training service log/loss streams
        service.logSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in
                MainActor.assumeIsolated { self?.logs.append(line) }
            }
            .store(in: &cancellables)

        service.lossSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point in
                MainActor.assumeIsolated { self?.lossHistory.append(point) }
            }
            .store(in: &cancellables)

        // Auto-save config after every change (debounced 0.5 s)
        $config
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { config in
                if let data = try? JSONEncoder().encode(config) {
                    UserDefaults.standard.set(data, forKey: kCurrentConfig)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Presets

    func savePreset(name: String) {
        presets[name] = config
        persistPresets()
    }

    func loadPreset(name: String) {
        guard let preset = presets[name] else { return }
        config = preset
    }

    func deletePreset(name: String) {
        presets.removeValue(forKey: name)
        persistPresets()
    }

    var sortedPresetNames: [String] {
        presets.keys.sorted()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: kPresets)
        }
    }

    // MARK: - Training

    func start() {
        guard !isRunning else { return }

        // Pre-flight: validate dataset files so mlx_lm gets a clear error
        if let warning = validateDataset() {
            errorMessage = warning
            logs = [warning]
            return
        }

        logs.removeAll()
        lossHistory.removeAll()
        metricHistory.removeAll()
        errorMessage = nil
        isRunning = true
        trainingStartTime = Date()

        // Start sampling system metrics every second
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let m = self.metricsService.sample()
                let elapsed = Date().timeIntervalSince(self.trainingStartTime ?? Date())
                self.currentMetrics = m
                self.metricHistory.append(MetricPoint(
                    elapsed: elapsed,
                    cpu: m.cpuPercent,
                    memPercent: m.memPercent,
                    gpu: m.gpuPercent
                ))
            }
        }

        service.onTermination = { [weak self] in
            MainActor.assumeIsolated {
                self?.isRunning = false
                self?.metricsTimer?.invalidate()
                self?.metricsTimer = nil
            }
        }

        do {
            try service.start(config: config)
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }

    /// Returns an error string if the dataset looks broken, nil if OK.
    private func validateDataset() -> String? {
        let folder = URL(fileURLWithPath: config.dataPath)
        let trainURL = folder.appendingPathComponent("train.jsonl")

        guard FileManager.default.fileExists(atPath: trainURL.path) else {
            return "train.jsonl not found in \(config.dataPath)"
        }
        let trainLines = (try? countNonEmptyLines(at: trainURL)) ?? 0
        guard trainLines > 0 else {
            return "train.jsonl is empty — re-convert your dataset."
        }

        // Check valid.jsonl only if it exists (empty valid.jsonl crashes mlx_lm)
        let validURL = folder.appendingPathComponent("valid.jsonl")
        if FileManager.default.fileExists(atPath: validURL.path) {
            let validLines = (try? countNonEmptyLines(at: validURL)) ?? 0
            if validLines == 0 {
                // Remove the empty file so mlx_lm doesn't choke on it
                try? FileManager.default.removeItem(at: validURL)
            }
        }

        return nil
    }

    private func countNonEmptyLines(at url: URL) throws -> Int {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    func stop() {
        service.stop()
        isRunning = false
        metricsTimer?.invalidate()
        metricsTimer = nil
    }
}
