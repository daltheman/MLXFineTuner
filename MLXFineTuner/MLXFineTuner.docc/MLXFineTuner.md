# ``MLXFineTuner``

A native macOS app for fine-tuning large language models on Apple Silicon.

@Metadata {
    @DisplayName("MLXFineTuner")
}

## Overview

MLXFineTuner provides a complete visual workflow for training, testing, and exporting fine-tuned models using [MLX](https://github.com/ml-explore/mlx) — Apple's machine learning framework optimized for M-series chips.

Fine-tuning LLMs typically requires command-line expertise, cloud GPU rentals, and sending proprietary data to third-party servers. MLXFineTuner eliminates all three:

- **No CLI knowledge needed** — configure hyperparameters, monitor training, and test results through a native SwiftUI interface
- **Runs entirely on your Mac** — leverages Apple Silicon's unified memory architecture for efficient on-device training
- **Your data stays local** — no cloud uploads, no API calls, no third-party data processing

## Topics

### Getting Started

- <doc:GettingStarted>
- <doc:TrainingWorkflow>

### Architecture

- <doc:Architecture>

### Apple Silicon & Economics

- <doc:AppleSiliconAdvantage>

### Models

- ``TrainingConfig``
- ``LossPoint``
- ``MetricPoint``
- ``TestModelSource``
- ``ChatMessage``
- ``TestMetrics``
- ``HFModelResult``
- ``HFDatasetResult``

### Services

- ``TrainingService``
- ``TestService``
- ``FuseService``
- ``HuggingFaceService``
- ``DatasetConverterService``
- ``SystemMetricsService``
- ``SystemMetrics``

### View Models

- ``TrainingViewModel``
- ``TestViewModel``
- ``FuseViewModel``

### Views

- ``ContentView``
