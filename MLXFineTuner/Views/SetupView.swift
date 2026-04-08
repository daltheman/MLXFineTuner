import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DatasetSource: String, CaseIterable {
    case local  = "Local JSONL"
    case txt    = "Text File"
    case pdf    = "PDF"
    case csv    = "CSV File"
    case hfHub  = "HuggingFace Hub"
}

struct SetupView: View {
    @ObservedObject var viewModel: TrainingViewModel

    @State private var showModelSearch   = false
    @State private var showDatasetSearch = false
    @State private var datasetSource: DatasetSource = .local

    @StateObject private var pyEnv = PythonEnvironmentViewModel()

    // Presets
    @State private var showSavePreset  = false
    @State private var newPresetName   = ""

    // CSV state
    @State private var csvFilePath    = ""
    @State private var csvHeaders: [String] = []
    @State private var csvPromptCol   = ""
    @State private var csvResponseCol = ""
    @State private var csvFormat: DatasetConverterService.OutputFormat = .chat
    @State private var csvOutputDir   = ""
    @State private var isConverting   = false
    @State private var conversionMsg: String?

    // TXT chunker state
    @State private var txtFilePath   = ""
    @State private var txtOutputDir  = ""
    @State private var txtChunkSize  = 512
    @State private var txtOverlap    = 64

    // PDF chunker state (reutiliza mesmos controles)
    @State private var pdfFilePath      = ""
    @State private var pdfOutputDir     = ""
    @State private var pdfChunkSize     = 512
    @State private var pdfOverlap       = 64
    @State private var isInstallingPDF  = false
    @State private var installMsg: String?

    var body: some View {
        VStack(spacing: 0) {
            presetsBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modelSection
                    pythonSection
                    datasetSection
                    hyperparametersSection
                    saveSection
                }
                .padding(24)
            }
        }
        .alert("Save Preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { viewModel.savePreset(name: name) }
                newPresetName = ""
            }
            Button("Cancel", role: .cancel) { newPresetName = "" }
        } message: {
            Text("Enter a name for this configuration.")
        }
        .sheet(isPresented: $showModelSearch) {
            ModelSearchView(selectedPath: $viewModel.config.modelPath)
        }
        .sheet(isPresented: $showDatasetSearch) {
            DatasetSearchView(selectedPath: $viewModel.config.dataPath)
        }
    }

    // MARK: - Presets Bar

    private var presetsBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            Text("Presets")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if viewModel.presets.isEmpty {
                Text("No saved presets")
                    .font(.caption)
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            } else {
                Menu {
                    ForEach(viewModel.sortedPresetNames, id: \.self) { name in
                        Menu(name) {
                            Button("Load \"\(name)\"") { viewModel.loadPreset(name: name) }
                            Divider()
                            Button("Delete \"\(name)\"", role: .destructive) {
                                viewModel.deletePreset(name: name)
                            }
                        }
                    }
                } label: {
                    Text("Load…")
                        .font(.subheadline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            if #available(macOS 26, *) {
                Button {
                    newPresetName = ""
                    showSavePreset = true
                } label: {
                    Label("Save as Preset", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                Button {
                    newPresetName = ""
                    showSavePreset = true
                } label: {
                    Label("Save as Preset", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Python Environment

    private var pythonSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Python Executable") {
                    TextField("e.g. /opt/homebrew/Caskroom/miniconda/base/bin/python3",
                              text: $pyEnv.pythonPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: pyEnv.pythonPath) { _, _ in
                            PythonEnvironmentService.shared.pythonPath = pyEnv.pythonPath
                        }
                    Button("Auto-detect") { pyEnv.autoDetect() }
                        .disabled(pyEnv.isDetecting)
                    if pyEnv.isDetecting { ProgressView().scaleEffect(0.7) }
                }

                // Package status badges
                if !pyEnv.packageStatus.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(["mlx_lm", "fitz", "huggingface_hub"], id: \.self) { pkg in
                            let ok = pyEnv.packageStatus[pkg] ?? false
                            if #available(macOS 26, *) {
                                HStack(spacing: 4) {
                                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(ok ? .green : .red)
                                        .font(.caption)
                                    Text(pkg == "fitz" ? "pymupdf" : pkg)
                                        .font(.caption)
                                        .foregroundColor(ok ? .primary : .secondary)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .glassEffect(.regular, in: .rect(cornerRadius: 5))
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(ok ? .green : .red)
                                        .font(.caption)
                                    Text(pkg == "fitz" ? "pymupdf" : pkg)
                                        .font(.caption)
                                        .foregroundColor(ok ? .primary : .secondary)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(ok ? Color.green.opacity(0.1) : Color.red.opacity(0.08))
                                .cornerRadius(5)
                            }
                        }
                        if pyEnv.isCheckingPackages {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Button("Verificar") {
                                Task { await pyEnv.checkPackages() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                } else {
                    Button("Verificar pacotes") {
                        Task { await pyEnv.checkPackages() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(pyEnv.isCheckingPackages)
                }
            }
            .padding(8)
        } label: {
            Label("Python Environment", systemImage: "terminal").font(.headline)
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "HuggingFace ID / Path") {
                    TextField("e.g. mlx-community/Llama-3.2-3B-Instruct-4bit",
                              text: $viewModel.config.modelPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { showModelSearch = true }
                }
                Text("Accepts a HuggingFace model ID or a local path to an MLX-converted model.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        } label: {
            Label("Model", systemImage: "brain").font(.headline)
        }
    }

    // MARK: - Dataset

    private var datasetSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                row(label: "Source") {
                    Picker("", selection: $datasetSource) {
                        ForEach(DatasetSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                switch datasetSource {
                case .local:  localRows
                case .txt:    txtRows
                case .pdf:    pdfRows
                case .csv:    csvRows
                case .hfHub:  hfHubRows
                }
            }
            .padding(8)
        } label: {
            Label("Dataset", systemImage: "folder").font(.headline)
        }
    }

    // Local JSONL
    private var localRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "Data Folder") {
                TextField("Path to folder with train.jsonl / valid.jsonl",
                          text: $viewModel.config.dataPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { selectFolder { viewModel.config.dataPath = $0 } }
            }
            Text("Expected: train.jsonl and (optionally) valid.jsonl inside the folder.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // PDF chunker
    private var pdfRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "PDF File") {
                TextField("Select a .pdf file", text: $pdfFilePath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    selectFile(types: ["pdf"]) { pdfFilePath = $0 }
                }
            }
            row(label: "Output Folder") {
                TextField("Folder for train.jsonl / valid.jsonl", text: $pdfOutputDir)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { selectFolder { pdfOutputDir = $0 } }
            }
            row(label: "Chunk Size") {
                Stepper("\(pdfChunkSize) tokens", value: $pdfChunkSize,
                        in: 128...2048, step: 128)
                Text("≈ \(pdfChunkSize * 4) chars")
                    .font(.caption).foregroundColor(.secondary)
            }
            row(label: "Overlap") {
                Stepper("\(pdfOverlap) tokens", value: $pdfOverlap,
                        in: 0...256, step: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Extrai texto com PyMuPDF · Remove headers/footers repetidos · Soft split · Train/valid 90/10")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Text("Requer: pip install pymupdf")
                        .font(.caption).foregroundColor(.secondary).italic()
                    Button("Instalar agora") { installPyMuPDF() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isInstallingPDF)
                    if isInstallingPDF { ProgressView().scaleEffect(0.6) }
                    if let msg = installMsg {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Extrair & Chunkar") { convertPDF() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pdfFilePath.isEmpty || pdfOutputDir.isEmpty || isConverting)
                if isConverting { ProgressView().scaleEffect(0.7) }
                if let msg = conversionMsg {
                    Text(msg)
                        .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                        .lineLimit(2)
                }
            }
        }
    }

    // Text file chunker
    private var txtRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "Text File (.txt)") {
                TextField("Select a .txt file", text: $txtFilePath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    selectFile(types: ["txt", "text"]) { txtFilePath = $0 }
                }
            }
            row(label: "Output Folder") {
                TextField("Folder for train.jsonl / valid.jsonl", text: $txtOutputDir)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { selectFolder { txtOutputDir = $0 } }
            }
            row(label: "Chunk Size") {
                Stepper("\(txtChunkSize) tokens", value: $txtChunkSize,
                        in: 128...2048, step: 128)
                Text("≈ \(txtChunkSize * 4) chars")
                    .font(.caption).foregroundColor(.secondary)
            }
            row(label: "Overlap") {
                Stepper("\(txtOverlap) tokens", value: $txtOverlap,
                        in: 0...256, step: 32)
            }

            Text("Split: soft (parágrafo → frase → hard cut) · Train/valid: 90/10 automático")
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Chunk & Convert") { convertTXT() }
                    .buttonStyle(.borderedProminent)
                    .disabled(txtFilePath.isEmpty || txtOutputDir.isEmpty || isConverting)
                if isConverting { ProgressView().scaleEffect(0.7) }
                if let msg = conversionMsg {
                    Text(msg)
                        .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                        .lineLimit(2)
                }
            }
        }
    }

    // CSV converter
    private var csvRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "CSV File") {
                TextField("Select a .csv file", text: $csvFilePath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") {
                    selectFile(types: ["csv"]) { path in
                        csvFilePath = path
                        loadCSVHeaders(path: path)
                    }
                }
            }

            if !csvHeaders.isEmpty {
                row(label: "Prompt Column") {
                    Picker("", selection: $csvPromptCol) {
                        ForEach(csvHeaders, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 220)
                }
                row(label: "Response Column") {
                    Picker("", selection: $csvResponseCol) {
                        ForEach(csvHeaders, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(maxWidth: 220)
                }
                row(label: "Output Format") {
                    Picker("", selection: $csvFormat) {
                        ForEach(DatasetConverterService.OutputFormat.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .frame(maxWidth: 280)
                }
                row(label: "Output Folder") {
                    TextField("Folder for train.jsonl / valid.jsonl", text: $csvOutputDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { selectFolder { csvOutputDir = $0 } }
                }

                HStack(spacing: 12) {
                    Button("Convert to JSONL") { convertCSV() }
                        .buttonStyle(.borderedProminent)
                        .disabled(csvOutputDir.isEmpty || csvPromptCol.isEmpty ||
                                  csvResponseCol.isEmpty || isConverting)
                    if isConverting { ProgressView().scaleEffect(0.7) }
                    if let msg = conversionMsg {
                        Text(msg)
                            .foregroundColor(msg.hasPrefix("✓") ? .green : .red)
                            .lineLimit(2)
                    }
                }
            } else if !csvFilePath.isEmpty {
                Text("Could not read CSV headers — check the file format.")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    // HuggingFace Hub
    private var hfHubRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(label: "Data Folder") {
                TextField("Set after download", text: $viewModel.config.dataPath)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(viewModel.config.dataPath.isEmpty ? .secondary : .primary)
                Button("Search & Download…") { showDatasetSearch = true }
                    .buttonStyle(.borderedProminent)
            }
            Text("Browse HuggingFace Hub, download a dataset, and the folder is set automatically.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Hyperparameters

    private var hyperparametersSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                hrow(label: "Iterations", help: "Number of training steps. More iterations let the model learn more but take longer. Start with 100–500 for small datasets; increase if loss is still dropping.") {
                    Stepper("\(viewModel.config.iters)", value: $viewModel.config.iters,
                            in: 100...50_000, step: 100)
                }
                hrow(label: "Batch Size", help: "How many examples the model sees per step. Larger batches give more stable gradients but use more memory. Reduce if you get out-of-memory errors.") {
                    Stepper("\(viewModel.config.batchSize)", value: $viewModel.config.batchSize,
                            in: 1...64, step: 1)
                }
                hrow(label: "Learning Rate", help: "Controls how much the model adjusts its weights each step. Too high causes instability; too low makes training slow. Typical range: 1e-5 to 1e-4.") {
                    Slider(value: $viewModel.config.learningRate, in: 1e-6...1e-2) { _ in }
                        .frame(maxWidth: 200)
                    Text(String(format: "%.2e", viewModel.config.learningRate))
                        .monospacedDigit().frame(width: 75, alignment: .trailing)
                }
                hrow(label: "LoRA Layers", help: "How many transformer layers get LoRA adapters. More layers = more expressive fine-tuning but more memory. 16 is a good default for most models.") {
                    Stepper("\(viewModel.config.loraLayers)", value: $viewModel.config.loraLayers,
                            in: 1...64, step: 1)
                }
                hrow(label: "LoRA Rank", help: "Rank of the low-rank adapter matrices. Higher rank captures more detail but increases adapter size. 8 is a balanced default; try 16–32 for complex tasks.") {
                    Stepper("\(viewModel.config.loraRank)", value: $viewModel.config.loraRank,
                            in: 1...128, step: 1)
                }

                Toggle("Disable validation (--val-batches 0)", isOn: $viewModel.config.disableValidation)
                    .toggleStyle(.checkbox)
                    .help("Use when your dataset has too few examples for a validation split")

            }
            .padding(8)
        } label: {
            Label("Hyperparameters", systemImage: "slider.horizontal.3").font(.headline)
        }
    }

    // MARK: - Save

    private var saveSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Adapter Save Path") {
                    TextField("./adapters", text: $viewModel.config.savePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") { selectFolder { viewModel.config.savePath = $0 } }
                }
                Text("LoRA adapter weights (.safetensors) are written here after training.")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(8)
        } label: {
            Label("Output", systemImage: "square.and.arrow.down").font(.headline)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).frame(width: 150, alignment: .leading)
            content()
        }
    }

    /// Row with a help button that shows a popover with an explanation.
    @ViewBuilder
    private func hrow<C: View>(label: String, help: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                HelpButton(text: help)
            }
            .frame(width: 150, alignment: .leading)
            content()
        }
    }

    private func selectFolder(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }

    private func selectFile(types: [String], completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }

    private func loadCSVHeaders(path: String) {
        do {
            let headers = try DatasetConverterService().csvHeaders(at: URL(fileURLWithPath: path))
            csvHeaders = headers
            csvPromptCol   = headers.first ?? ""
            csvResponseCol = headers.dropFirst().first ?? headers.first ?? ""
        } catch {
            csvHeaders = []
        }
    }

    private func installPyMuPDF() {
        isInstallingPDF = true
        installMsg = nil
        let pythonPath = PythonEnvironmentService.shared.pythonPath

        Task {
            let result: Result<Void, Error> = await Task.detached(priority: .background) {
                let process = Process()
                let errPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [pythonPath, "-m", "pip", "install", "pymupdf"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errPipe

                var env = ProcessInfo.processInfo.environment
                let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
                env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
                process.environment = env

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                         encoding: .utf8) ?? "Unknown error"
                        throw NSError(domain: "pip", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success:
                installMsg = "✓ PyMuPDF instalado"
            case .failure(let error):
                installMsg = "Erro: \(error.localizedDescription)"
            }
            isInstallingPDF = false
        }
    }

    private func convertPDF() {
        let src    = pdfFilePath
        let outDir = pdfOutputDir
        let chunk  = pdfChunkSize
        let ovlap  = pdfOverlap
        let pythonPath = PythonEnvironmentService.shared.pythonPath

        isConverting = true
        conversionMsg = nil

        Task {
            let result: Result<String, Error> = await Task.detached(priority: .background) {
                do {
                    try DatasetConverterService().convertPDF(
                        at: URL(fileURLWithPath: src),
                        outputDir: URL(fileURLWithPath: outDir),
                        chunkTokens: chunk,
                        overlapTokens: ovlap,
                        pythonPath: pythonPath
                    )
                    return .success(outDir)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let path):
                conversionMsg = "✓ Chunks gerados em \(path)"
                viewModel.config.dataPath = path
            case .failure(let error):
                conversionMsg = "Error: \(error.localizedDescription)"
            }
            isConverting = false
        }
    }

    private func convertTXT() {
        let src    = txtFilePath
        let outDir = txtOutputDir
        let chunk  = txtChunkSize
        let ovlap  = txtOverlap
        let pythonPath = PythonEnvironmentService.shared.pythonPath

        isConverting = true
        conversionMsg = nil

        Task {
            let result: Result<String, Error> = await Task.detached(priority: .background) {
                do {
                    try DatasetConverterService().convertTXT(
                        at: URL(fileURLWithPath: src),
                        outputDir: URL(fileURLWithPath: outDir),
                        chunkTokens: chunk,
                        overlapTokens: ovlap,
                        pythonPath: pythonPath
                    )
                    return .success(outDir)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let path):
                conversionMsg = "✓ Chunks gerados em \(path)"
                viewModel.config.dataPath = path
            case .failure(let error):
                conversionMsg = "Error: \(error.localizedDescription)"
            }
            isConverting = false
        }
    }

    private func convertCSV() {
        let src    = csvFilePath
        let outDir = csvOutputDir
        let pCol   = csvPromptCol
        let rCol   = csvResponseCol
        let fmt    = csvFormat
        let pythonPath = PythonEnvironmentService.shared.pythonPath

        isConverting = true
        conversionMsg = nil

        Task {
            let result: Result<String, Error> = await Task.detached(priority: .background) {
                do {
                    try DatasetConverterService().convertCSV(
                        at: URL(fileURLWithPath: src),
                        outputDir: URL(fileURLWithPath: outDir),
                        promptColumn: pCol,
                        responseColumn: rCol,
                        format: fmt,
                        pythonPath: pythonPath
                    )
                    return .success(outDir)
                } catch {
                    return .failure(error)
                }
            }.value

            switch result {
            case .success(let path):
                conversionMsg = "✓ Converted — train.jsonl written to \(path)"
                viewModel.config.dataPath = path
            case .failure(let error):
                conversionMsg = "Error: \(error.localizedDescription)"
            }
            isConverting = false
        }
    }

}

// MARK: - Help Button

private struct HelpButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .padding(12)
                .frame(width: 260)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
