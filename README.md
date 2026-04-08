# MLXFineTuner

A native macOS app for fine-tuning large language models on Apple Silicon. No terminal required.

MLXFineTuner provides a complete visual workflow for training, testing, and exporting fine-tuned models using [MLX](https://github.com/ml-explore/mlx) — Apple's machine learning framework optimized for M-series chips.

## Why MLXFineTuner?

Fine-tuning LLMs typically requires command-line expertise, cloud GPU rentals, and sending proprietary data to third-party servers. MLXFineTuner eliminates all three:

- **No CLI knowledge needed** — configure hyperparameters, monitor training, and test results through a native SwiftUI interface
- **Runs entirely on your Mac** — leverages Apple Silicon's unified memory architecture for efficient on-device training
- **Your data stays local** — no cloud uploads, no API calls, no third-party data processing

## Features

### Setup Tab
- Browse and select models from Hugging Face directly in the app
- Search and download datasets from Hugging Face Hub
- Configure all training hyperparameters with helpful tooltips
- Auto-detect Python environment (conda, venv, system)
- Save and load named configuration presets

### Training Tab
- Real-time loss chart with iteration tracking
- Live system metrics (CPU, RAM, GPU utilization)
- Streaming training log with color-coded output
- Start/stop training with one click

### Test Tab
- Interactive chat interface to validate fine-tuned models
- Supports both LoRA adapter and fused model testing
- Real-time token streaming during generation
- Performance metrics: tokens/sec, latency, prompt/generation token counts

### Export Tab
- Fuse LoRA adapters into standalone models
- Optional de-quantization before fusing
- One-click reveal in Finder after export

## Requirements

- macOS 15.0+ (macOS 26+ for Liquid Glass effects)
- Apple Silicon Mac (M1 or later)
- Python 3.10+ with `mlx-lm` installed

## Quick Start

1. **Install Python dependencies:**
   ```bash
   pip install mlx-lm
   ```

2. **Open `MLXFineTuner.xcodeproj`** in Xcode and build (Cmd+R)

3. **Setup tab:** Select a model and dataset, configure hyperparameters

4. **Training tab:** Click "Start Training" and monitor loss/metrics in real time

5. **Test tab:** Send prompts to your fine-tuned model and evaluate quality

6. **Export tab:** Fuse the adapter into a standalone model for deployment

## Architecture

```
MLXFineTuner/
├── App/                    # App entry point
├── Models/                 # Data models (TrainingConfig, ChatMessage, etc.)
├── Views/                  # SwiftUI views (Setup, Training, Test, Export)
├── ViewModels/             # ObservableObject view models (MVVM)
└── Services/               # Process management, metrics, HF API, etc.
```

The app follows MVVM architecture with Combine for reactive data flow. All ML operations run as external Python processes (`mlx_lm` CLI), keeping the Swift layer focused on UI and orchestration.

## Apple Silicon Advantage

MLX is purpose-built for Apple Silicon's unified memory architecture. This means:

- **No memory copies** between CPU and GPU — the model lives in shared memory
- **Larger models fit** than on traditional GPU VRAM (up to 192GB on Mac Studio M4 Ultra)
- **Silent operation** — no fans spinning up like a GPU server rack
- **Energy efficient** — fine-tune models at a fraction of the power consumption

See [PITCH.md](PITCH.md) for a detailed analysis of Apple Silicon economics vs. cloud GPU costs.

## License

MIT
