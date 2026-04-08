import SwiftUI
import AppKit

struct FuseView: View {
    @ObservedObject var trainingViewModel: TrainingViewModel
    @StateObject private var vm = FuseViewModel()

    var body: some View {
        VStack(spacing: 0) {
            configSection
            Divider()
            logSection
            Divider()
            toolbarSection
        }
        .onAppear {
            vm.syncFromConfig(
                modelPath: trainingViewModel.config.modelPath,
                adapterPath: trainingViewModel.config.savePath
            )
        }
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    row(label: "Base Model") {
                        TextField("HF model ID or local path", text: $vm.modelPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { selectFolder { vm.modelPath = $0 } }
                    }
                    row(label: "Adapter Path") {
                        TextField("Path to adapter folder (contains *.safetensors)", text: $vm.adapterPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { selectFolder { vm.adapterPath = $0 } }
                    }
                    row(label: "Output Path") {
                        TextField("./fused-model", text: $vm.savePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { selectFolder { vm.savePath = $0 } }
                    }
                    row(label: "Options") {
                        Toggle("De-quantize before fusing", isOn: $vm.deQuantize)
                        Text("Merges adapters into full-precision weights")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(8)
            } label: {
                Label("Fuse / Export", systemImage: "arrow.triangle.merge").font(.headline)
            }

            if vm.didSucceed {
                if #available(macOS 26, *) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Model exported to \(vm.savePath)")
                            .foregroundColor(.green)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.savePath)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 8))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Model exported to \(vm.savePath)")
                            .foregroundColor(.green)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.savePath)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding(24)
    }

    // MARK: - Log

    private var logSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if vm.logs.isEmpty {
                        Text("Fuse log will appear here…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                            .padding(12)
                    } else {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(lineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1)
                        }
                        Color.clear.frame(height: 1).id("fuseBottom")
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: vm.logs.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("fuseBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            if let err = vm.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(err).foregroundColor(.red).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            if vm.isRunning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).frame(width: 16, height: 16)
                    Text("Fusing…").foregroundColor(.secondary)
                }
                if #available(macOS 26, *) {
                    Button("Stop") { vm.stop() }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                } else {
                    Button("Stop") { vm.stop() }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
            } else {
                if #available(macOS 26, *) {
                    Button("Fuse & Export") { vm.start() }
                        .buttonStyle(.glassProminent)
                        .disabled(vm.modelPath.isEmpty || vm.adapterPath.isEmpty || vm.savePath.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Fuse & Export") { vm.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.modelPath.isEmpty || vm.adapterPath.isEmpty || vm.savePath.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).frame(width: 150, alignment: .leading)
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

    private func lineColor(_ line: String) -> Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("traceback") { return .red }
        if l.contains("warning") { return Color(NSColor.systemOrange) }
        return Color(NSColor.labelColor)
    }
}
