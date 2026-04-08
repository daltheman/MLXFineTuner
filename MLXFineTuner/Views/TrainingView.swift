import SwiftUI
import Charts

struct TrainingView: View {
    @ObservedObject var viewModel: TrainingViewModel

    var body: some View {
        VStack(spacing: 0) {
            lossChartSection
            Divider()
            metricsSection
            Divider()
            logSection
            Divider()
            toolbarSection
        }
    }

    // MARK: - Loss Chart

    @ViewBuilder
    private var lossChartSection: some View {
        if viewModel.lossHistory.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Loss chart will appear here during training")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .background(Color(NSColor.controlBackgroundColor))
        } else {
            Chart(viewModel.lossHistory) { point in
                LineMark(
                    x: .value("Iteration", point.iteration),
                    y: .value("Loss", point.loss)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Iteration", point.iteration),
                    y: .value("Loss", point.loss)
                )
                .foregroundStyle(.blue.opacity(0.08))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxisLabel("Iteration")
            .chartYAxisLabel("Loss")
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(height: 160)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - System Metrics

    private var metricsSection: some View {
        VStack(spacing: 0) {
            // Badges row
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Spacer()
                        metricBadge(
                            label: "CPU",
                            icon:  "cpu",
                            value: String(format: "%.1f%%", viewModel.currentMetrics.cpuPercent),
                            color: .cyan
                        )
                        metricBadge(
                            label: "RAM",
                            icon:  "memorychip",
                            value: String(format: "%.1f / %.0f GB",
                                          viewModel.currentMetrics.memUsedGB,
                                          viewModel.currentMetrics.memTotalGB),
                            color: .mint
                        )
                        if let gpu = viewModel.currentMetrics.gpuPercent {
                            metricBadge(label: "GPU", icon: "desktopcomputer",
                                        value: String(format: "%.1f%%", gpu), color: .purple)
                        } else {
                            metricBadge(label: "GPU", icon: "desktopcomputer", value: "N/A", color: .gray)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 12) {
                    Spacer()
                    metricBadge(
                        label: "CPU",
                        icon:  "cpu",
                        value: String(format: "%.1f%%", viewModel.currentMetrics.cpuPercent),
                        color: .cyan
                    )
                    metricBadge(
                        label: "RAM",
                        icon:  "memorychip",
                        value: String(format: "%.1f / %.0f GB",
                                      viewModel.currentMetrics.memUsedGB,
                                      viewModel.currentMetrics.memTotalGB),
                        color: .mint
                    )
                    if viewModel.currentMetrics.gpuPercent != nil {
                        metricBadge(
                            label: "GPU",
                            icon:  "desktopcomputer",
                            value: String(format: "%.1f%%", viewModel.currentMetrics.gpuPercent!),
                            color: .purple
                        )
                    } else {
                        metricBadge(label: "GPU", icon: "desktopcomputer", value: "N/A", color: .gray)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }

            // Combined usage chart
            if !viewModel.metricHistory.isEmpty {
                metricsChart
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(height: 150)
                    .background(Color(NSColor.controlBackgroundColor))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("CPU · RAM · GPU usage during training")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private var metricsChart: some View {
        // Keep last 120 samples (2 min at 1s interval)
        let recent = Array(viewModel.metricHistory.suffix(120))

        // Flatten into one array with a series label
        let samples: [MetricSample] = recent.flatMap { pt in
            var out = [
                MetricSample(elapsed: pt.elapsed, value: pt.cpu,        series: "CPU"),
                MetricSample(elapsed: pt.elapsed, value: pt.memPercent, series: "RAM"),
            ]
            if let g = pt.gpu {
                out.append(MetricSample(elapsed: pt.elapsed, value: g, series: "GPU"))
            }
            return out
        }

        return Chart(samples) { s in
            LineMark(
                x: .value("Time (s)", s.elapsed),
                y: .value("%", s.value)
            )
            .foregroundStyle(by: .value("Metric", s.series))
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartForegroundStyleScale([
            "CPU": Color.cyan,
            "RAM": Color.mint,
            "GPU": Color.purple,
        ])
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine()
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.caption2) }
            }
        }
        .chartXAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel {
                    if let t = v.as(Double.self) {
                        Text(formatElapsed(t)).font(.caption2)
                    }
                }
            }
        }
        .chartLegend(position: .topTrailing)
    }

    // MARK: - Log Output

    private var logSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(lineColor(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("logBottom")
                }
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: viewModel.logs.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if viewModel.isRunning {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 16, height: 16)
                    Text("Training…")
                        .foregroundColor(.secondary)
                }
                if #available(macOS 26, *) {
                    Button("Stop") { viewModel.stop() }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                } else {
                    Button("Stop") { viewModel.stop() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            } else {
                if #available(macOS 26, *) {
                    Button("Start Training") { viewModel.start() }
                        .buttonStyle(.glassProminent)
                        .disabled(viewModel.config.dataPath.isEmpty || viewModel.config.modelPath.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Start Training") { viewModel.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.config.dataPath.isEmpty || viewModel.config.modelPath.isEmpty)
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

    private func lineColor(for line: String) -> Color {
        if line.lowercased().contains("error") || line.lowercased().contains("traceback") {
            return .red
        } else if line.lowercased().contains("warning") {
            return Color(NSColor.systemOrange)
        } else if line.hasPrefix("Iter") {
            return Color(NSColor.labelColor)
        } else {
            return Color(NSColor.secondaryLabelColor)
        }
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m\(s % 60)s"
    }
}

// MARK: - Chart helper type

private struct MetricSample: Identifiable {
    let id = UUID()
    let elapsed: Double
    let value: Double
    let series: String
}
