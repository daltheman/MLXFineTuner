import SwiftUI

struct ModelSearchView: View {
    @StateObject private var viewModel = ModelSearchViewModel()
    @Binding var selectedPath: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            resultsList
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { viewModel.search() }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search models…", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .onSubmit { viewModel.search() }
                    .onChange(of: viewModel.query) { _, _ in viewModel.search() }
                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else if !viewModel.query.isEmpty {
                    Button { viewModel.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Toggle("mlx-community only", isOn: $viewModel.mlxCommunityOnly)
                .toggleStyle(.checkbox)
                .onChange(of: viewModel.mlxCommunityOnly) { _, _ in viewModel.search() }
        }
        .padding()
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if let error = viewModel.error {
            errorPlaceholder(error)
        } else if viewModel.results.isEmpty && !viewModel.isLoading {
            emptyPlaceholder
        } else {
            List(viewModel.results) { model in
                modelRow(model)
            }
        }
    }

    private func errorPlaceholder(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundColor(.orange)
            Text(msg).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain").font(.system(size: 40)).foregroundColor(.secondary)
            Text("Type to search for MLX models").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func modelRow(_ model: HFModelResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.id)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if let tag = model.pipelineTag { badge(tag, .blue) }
                    ForEach((model.tags ?? []).prefix(2).filter { $0 != model.pipelineTag }, id: \.self) {
                        badge($0, .gray)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                stat("arrow.down.circle", model.formattedDownloads)
                stat("heart.fill", model.formattedLikes, color: .pink)
            }
            Button("Select") {
                selectedPath = model.id
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func stat(_ icon: String, _ value: String, color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            Text(value).font(.caption).foregroundColor(.secondary)
        }
    }
}
