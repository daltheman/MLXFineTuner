# Getting Started

Set up your environment and run your first fine-tuning experiment.

## Overview

MLXFineTuner runs entirely on your Mac. You need Apple Silicon hardware, a Python environment with `mlx-lm`, and Xcode to build the app.

## Requirements

| Requirement | Details |
|---|---|
| macOS | 15.0+ (macOS 26+ for Liquid Glass effects) |
| Hardware | Apple Silicon Mac (M1 or later) |
| Python | 3.10+ with `mlx-lm` installed |

## Install Dependencies

```bash
pip install mlx-lm
```

For PDF dataset conversion, also install PyMuPDF:

```bash
pip install pymupdf
```

## Build & Run

1. Open `MLXFineTuner.xcodeproj` in Xcode
2. Build and run (Cmd+R)

The app auto-detects your Python environment (conda, venv, or system).

## Quick Start

1. **Setup tab** — Select a model and dataset from Hugging Face, configure hyperparameters
2. **Training tab** — Click "Start Training" and monitor loss/metrics in real time
3. **Test tab** — Send prompts to your fine-tuned model and evaluate quality
4. **Export tab** — Fuse the LoRA adapter into a standalone model for deployment

Total time from zero to first fine-tuned model: **under 30 minutes** on a 3B parameter model.

## Features by Tab

### Setup
- Browse and select models from Hugging Face directly in the app
- Search and download datasets from Hugging Face Hub
- Convert CSV, TXT, and PDF files into training-ready JSONL format
- Configure all training hyperparameters with helpful tooltips
- Save and load named configuration presets

### Training
- Real-time loss chart with iteration tracking
- Live system metrics (CPU, RAM, GPU utilization)
- Streaming training log with color-coded output
- Start/stop training with one click

### Test
- Interactive chat interface to validate fine-tuned models
- Supports both LoRA adapter and fused model testing
- Real-time token streaming during generation
- Performance metrics: tokens/sec, latency, prompt/generation token counts

### Export
- Fuse LoRA adapters into standalone models
- Optional de-quantization before fusing
- One-click reveal in Finder after export
