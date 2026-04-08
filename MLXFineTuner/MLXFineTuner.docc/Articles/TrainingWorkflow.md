# Training Workflow

A step-by-step guide through MLXFineTuner's four-tab workflow.

## Overview

MLXFineTuner organizes the fine-tuning process into four sequential tabs: **Setup**, **Training**, **Test**, and **Export**. Each tab corresponds to a stage of the workflow, and the app carries configuration forward between tabs automatically.

## Step 1: Setup

The Setup tab is where you configure everything before training begins.

### Select a Model

Use the built-in Hugging Face browser to find an MLX-compatible model. The search defaults to the `mlx-community` organization, which hosts pre-converted models optimized for Apple Silicon. Results show download counts and likes to help identify popular models.

### Prepare a Dataset

You have three options:
1. **Search Hugging Face** — Browse and download datasets directly from the Hub
2. **Point to a local folder** — If you already have `train.jsonl` and optional `valid.jsonl` files
3. **Convert from CSV/TXT/PDF** — The built-in converter transforms raw files into the JSONL format that `mlx_lm` expects

For CSV conversion, you map your prompt and response columns to one of three output formats:
- **Chat** — `{"messages": [{"role": "user", ...}, {"role": "assistant", ...}]}`
- **Completion** — `{"prompt": "...", "completion": "..."}`
- **Text** — `{"text": "..."}`

### Configure Hyperparameters

Key parameters with their defaults:
- **Iterations** (1000) — Total training steps
- **Batch Size** (4) — Samples per gradient update
- **Learning Rate** (1e-4) — Step size for optimization
- **LoRA Layers** (16) — Number of model layers to apply LoRA adapters
- **LoRA Rank** (8) — Rank of the low-rank adaptation matrices

Each parameter has a help tooltip explaining its effect. You can save configurations as named presets for reuse.

## Step 2: Training

Click **Start Training** to begin. The app launches `python -m mlx_lm lora` as a subprocess and monitors its output.

### What You See

- **Loss chart** — Plots training (and validation) loss over iterations. A decreasing curve means the model is learning.
- **System metrics** — Real-time CPU, RAM, and GPU utilization sampled every second via Mach kernel APIs and IOKit.
- **Streaming log** — Raw `mlx_lm` output in a monospaced log view.

### Stopping

Click **Stop Training** at any time. The adapter weights saved so far (at the last checkpoint) are usable.

## Step 3: Test

The Test tab provides an interactive chat interface for evaluating your fine-tuned model.

### Model Source

Choose between:
- **LoRA Adapter** — Uses the base model + adapter path (tests the adapter before fusing)
- **Fused Model** — Uses an already-exported standalone model

### Evaluation

Type a prompt and press Send. The app runs `python -m mlx_lm generate` and streams tokens in real time. After generation completes, you see:
- **Prompt tokens** and processing speed (tokens/sec)
- **Generated tokens** and generation speed
- **Total latency** in milliseconds

Each message is an independent generation — there is no multi-turn conversation context.

## Step 4: Export

The Export tab fuses your LoRA adapter weights into the base model to create a standalone model.

### Options

- **Model Path** — The base model used during training
- **Adapter Path** — Where the LoRA adapters were saved
- **Output Path** — Where to write the fused model (must be an absolute path)
- **De-quantize** — Optionally convert the model back to full precision before fusing

### After Export

On success, a banner appears with a button to reveal the fused model in Finder. The fused model is a self-contained directory that can be used for inference without the original adapter files.
