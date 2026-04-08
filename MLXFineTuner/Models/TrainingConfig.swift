import Foundation

/// All hyperparameters and paths needed to launch an `mlx_lm.lora` training run.
///
/// Persisted to `UserDefaults` as JSON so the last-used configuration survives app restarts.
struct TrainingConfig: Codable {
    /// Hugging Face model ID or local path to the base model.
    var modelPath: String = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    /// Local directory containing `train.jsonl` (and optionally `valid.jsonl`).
    var dataPath: String = ""
    /// Total number of training iterations.
    var iters: Int = 1000
    /// Number of samples per gradient update.
    var batchSize: Int = 4
    /// Optimizer step size.
    var learningRate: Double = 1e-4
    /// Number of model layers that receive LoRA adapters.
    var loraLayers: Int = 16
    /// Rank of the low-rank adaptation matrices.
    var loraRank: Int = 8
    /// Directory where adapter weights are saved.
    var savePath: String = "./adapters"
    /// When `true`, skips validation batches during training.
    var disableValidation: Bool = false
}

/// A single training or validation loss value at a given iteration, used for charting.
struct LossPoint: Identifiable {
    let id = UUID()
    let iteration: Int
    let loss: Double
}

/// A system-metrics sample taken at a point in time during training.
struct MetricPoint: Identifiable {
    let id = UUID()
    /// Seconds since training started.
    let elapsed: Double
    /// CPU usage percentage (0–100).
    let cpu: Double
    /// Memory usage percentage (0–100).
    let memPercent: Double
    /// GPU usage percentage (0–100), or `nil` when unavailable.
    let gpu: Double?
}
