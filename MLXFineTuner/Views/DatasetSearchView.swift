import SwiftUI
import AppKit

struct DatasetSearchView: View {
    @StateObject private var viewModel = DatasetSearchViewModel()
    @Binding var selectedPath: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if viewModel.isDownloading {
                downloadProgressView
            } else {
                resultsList
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search datasets… (e.g. alpaca, sharegpt, instruction)", text: $viewModel.query)
                .textFieldStyle(.plain)
                .onSubmit { viewModel.search() }
            Button("Search") { viewModel.search() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            if viewModel.isLoading { ProgressView().scaleEffect(0.7) }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding()
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if let error = viewModel.error {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundColor(.orange)
                Text(error).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
        } else if viewModel.results.isEmpty && !viewModel.isLoading {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark").font(.system(size: 40)).foregroundColor(.secondary)
                Text("Search for datasets on HuggingFace").foregroundColor(.secondary)
                Text("Tip: try \"alpaca\", \"sharegpt\", \"dolly\", \"openhermes\"")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.results) { dataset in
                datasetRow(dataset)
            }
        }
    }

    // MARK: - Download Progress

    private var downloadProgressView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgressView()
                Text("Downloading dataset…").font(.headline)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.downloadLog.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onChange(of: viewModel.downloadLog.count) { _, _ in
                    proxy.scrollTo("end")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dataset Row

    @ViewBuilder
    private func datasetRow(_ dataset: HFDatasetResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dataset.id)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach((dataset.tags ?? []).prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle").font(.caption).foregroundColor(.secondary)
                Text(dataset.formattedDownloads).font(.caption).foregroundColor(.secondary)
            }
            Button("Download…") { startDownload(dataset) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func startDownload(_ dataset: HFDatasetResult) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder to download \(dataset.id)"
        panel.prompt = "Download Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let safeName = dataset.id.replacingOccurrences(of: "/", with: "--")
        let toPath = url.appendingPathComponent(safeName).path

        Task {
            await viewModel.downloadDataset(dataset, toPath: toPath)
            if viewModel.error == nil {
                selectedPath = toPath
                dismiss()
            }
        }
    }
}
