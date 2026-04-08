import Foundation

struct TrainingConfig: Codable {
    var modelPath: String = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    var dataPath: String = ""
    var iters: Int = 1000
    var batchSize: Int = 4
    var learningRate: Double = 1e-4
    var loraLayers: Int = 16
    var loraRank: Int = 8
    var savePath: String = "./adapters"
    var disableValidation: Bool = false
}

struct LossPoint: Identifiable {
    let id = UUID()
    let iteration: Int
    let loss: Double
}

struct MetricPoint: Identifiable {
    let id = UUID()
    let elapsed: Double      // seconds since training started
    let cpu: Double          // 0–100
    let memPercent: Double   // 0–100
    let gpu: Double?         // 0–100 or nil
}
