import SwiftUI
import AppKit

struct TestView: View {
    @ObservedObject var trainingViewModel: TrainingViewModel
    @StateObject private var vm = TestViewModel()

    var body: some View {
        VStack(spacing: 0) {
            configSection
            Divider()
            chatSection
            Divider()
            metricsSection
            Divider()
            inputSection
        }
        .onAppear {
            let defaultFused = FuseViewModel.defaultSavePath
            vm.syncFromConfig(
                modelPath: trainingViewModel.config.modelPath,
                adapterPath: trainingViewModel.config.savePath,
                fusedModelPath: defaultFused
            )
        }
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    row(label: "Source") {
                        Picker("", selection: $vm.modelSource) {
                            ForEach(TestModelSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                    }

                    if vm.modelSource == .loraAdapter {
                        row(label: "Base Model") {
                            TextField("HF model ID or local path", text: $vm.baseModelPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") { selectFolder { vm.baseModelPath = $0 } }
                        }
                        row(label: "Adapter Path") {
                            TextField("Path to adapter folder", text: $vm.adapterPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") { selectFolder { vm.adapterPath = $0 } }
                        }
                    } else {
                        row(label: "Fused Model") {
                            TextField("Path to fused model folder", text: $vm.fusedModelPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") { selectFolder { vm.fusedModelPath = $0 } }
                        }
                    }

                    row(label: "Max Tokens") {
                        TextField("256", value: $vm.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Spacer()
                        Button("Clear Chat") { vm.clearChat() }
                            .controlSize(.small)
                    }
                }
                .padding(8)
            } label: {
                Label("Test Model", systemImage: "text.bubble").font(.headline)
            }
        }
        .padding(16)
    }

    // MARK: - Chat

    private var chatSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if vm.messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Send a prompt to test your model")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.messages) { message in
                            chatBubble(for: message)
                        }
                        Color.clear.frame(height: 1).id("chatBottom")
                    }
                    .padding(16)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: vm.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func chatBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content.isEmpty && message.role == .assistant ? "…" : message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .modifier(ChatBubbleBackground(role: message.role))

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        Group {
            if let m = vm.lastMetrics {
                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Spacer()
                            metricBadge(label: "Speed", icon: "bolt.fill",
                                        value: String(format: "%.1f tok/s", m.generationTokensPerSecond), color: .green)
                            metricBadge(label: "Latency", icon: "clock",
                                        value: String(format: "%.0f ms", m.totalLatencyMs), color: .orange)
                            metricBadge(label: "Prompt", icon: "text.alignleft",
                                        value: "\(m.promptTokens) tok", color: .cyan)
                            metricBadge(label: "Generated", icon: "text.append",
                                        value: "\(m.generationTokens) tok", color: .purple)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else {
                    HStack(spacing: 12) {
                        Spacer()
                        metricBadge(label: "Speed", icon: "bolt.fill",
                                    value: String(format: "%.1f tok/s", m.generationTokensPerSecond), color: .green)
                        metricBadge(label: "Latency", icon: "clock",
                                    value: String(format: "%.0f ms", m.totalLatencyMs), color: .orange)
                        metricBadge(label: "Prompt", icon: "text.alignleft",
                                    value: "\(m.promptTokens) tok", color: .cyan)
                        metricBadge(label: "Generated", icon: "text.append",
                                    value: "\(m.generationTokens) tok", color: .purple)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .foregroundColor(.secondary)
                    Text("Metrics will appear after generation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        HStack(spacing: 12) {
            if let err = vm.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(err).foregroundColor(.red).lineLimit(1).truncationMode(.tail)
            }

            TextField("Type a prompt…", text: $vm.currentInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { vm.send() }

            if vm.isGenerating {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 16, height: 16)
                if #available(macOS 26, *) {
                    Button("Stop") { vm.stop() }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                } else {
                    Button("Stop") { vm.stop() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            } else {
                if #available(macOS 26, *) {
                    Button("Send") { vm.send() }
                        .buttonStyle(.glassProminent)
                        .disabled(vm.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Send") { vm.send() }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricBadge(label: String, icon: String, value: String, color: Color) -> some View {
        if #available(macOS 26, *) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            .frame(width: 110, height: 70)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        } else {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            .frame(width: 110, height: 70)
            .background(color.opacity(0.08))
            .cornerRadius(10)
        }
    }

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
        panel.canCreateDirectories = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { completion(url.path) }
    }
}

// MARK: - Chat Bubble Background Modifier

private struct ChatBubbleBackground: ViewModifier {
    let role: ChatMessage.Role

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            switch role {
            case .user:
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            case .assistant:
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        } else {
            switch role {
            case .user:
                content
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(12)
            case .assistant:
                content
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
            }
        }
    }
}
