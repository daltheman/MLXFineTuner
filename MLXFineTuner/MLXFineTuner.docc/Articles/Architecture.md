# Architecture

How MLXFineTuner is structured and how data flows through the app.

## Overview

MLXFineTuner follows the **MVVM** (Model–View–ViewModel) architecture with **Combine** for reactive data flow. All ML operations run as external Python processes (`mlx_lm` CLI), keeping the Swift layer focused on UI and orchestration.

## Folder Structure

```
MLXFineTuner/
├── App/                    # App entry point (MLXFineTunerApp.swift)
├── Models/                 # Data models
│   ├── TrainingConfig      # Hyperparameter configuration (Codable)
│   ├── TestModels          # ChatMessage, TestMetrics, TestModelSource
│   └── HFSearchResult      # Hugging Face API response types
├── Views/                  # SwiftUI views
│   ├── ContentView         # Root TabView (Setup → Training → Test → Export)
│   ├── SetupView           # Model/dataset selection, hyperparameters
│   ├── TrainingView        # Loss chart, metrics, logs
│   ├── TestView            # Interactive chat evaluation
│   ├── FuseView            # Adapter export
│   ├── ModelSearchView     # HF model browser (sheet)
│   └── DatasetSearchView   # HF dataset browser (sheet)
├── ViewModels/             # ObservableObject view models
│   ├── TrainingViewModel   # Training orchestration + preset management
│   ├── TestViewModel       # Chat send/stop/clear
│   ├── FuseViewModel       # Export orchestration
│   ├── ModelSearchViewModel
│   ├── DatasetSearchViewModel
│   └── PythonEnvironmentViewModel
└── Services/               # Process management & external APIs
    ├── TrainingService     # Runs mlx_lm.lora via Process
    ├── TestService         # Runs mlx_lm.generate via Process
    ├── FuseService         # Runs mlx_lm.fuse via Process
    ├── HuggingFaceService  # Hugging Face Hub REST API
    ├── DatasetConverterService  # CSV/TXT/PDF → JSONL conversion
    ├── SystemMetricsService     # CPU/RAM/GPU sampling via Mach APIs
    └── PythonEnvironmentService # Python path detection
```

## Data Flow

The app uses a layered architecture where each layer has a single responsibility:

```
┌──────────┐     ┌──────────────┐     ┌──────────────┐
│   View   │ ←── │  ViewModel   │ ←── │   Service    │
│ (SwiftUI)│     │ (Observable) │     │  (Process)   │
└──────────┘     └──────────────┘     └──────────────┘
                        │                     │
                  @Published props     Combine subjects
                  User actions ──→     (PassthroughSubject)
```

### Service → ViewModel

Services run `mlx_lm` commands as child processes via Foundation's `Process` class. Output is captured through `Pipe` file handles and published via Combine `PassthroughSubject`:

- **TrainingService** publishes log lines and parsed loss points
- **TestService** publishes streamed tokens and post-run metrics
- **FuseService** publishes log lines

ViewModels subscribe to these subjects and update their `@Published` properties on the main actor.

### ViewModel → View

Views observe ViewModel `@Published` properties via `@StateObject` or `@ObservedObject`. SwiftUI automatically re-renders when properties change.

### View → ViewModel

User actions (button taps, text input) call ViewModel methods like `start()`, `stop()`, `send()`, which delegate to the appropriate Service.

## Process Management

All ML operations use the same pattern:

1. Create a `Process` pointing to `/usr/bin/env` with the user's Python path
2. Attach `Pipe` objects for stdout and stderr
3. Set `readabilityHandler` closures that dispatch output to the main thread
4. Set a `terminationHandler` to update running state
5. Call `process.run()`

The user's shell environment is inherited and enriched with common Python install paths (`/opt/homebrew/bin`, etc.) so conda and venv environments are found automatically.
