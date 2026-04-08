import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TrainingViewModel()

    var body: some View {
        TabView {
            SetupView(viewModel: viewModel)
                .tabItem {
                    Label("Setup", systemImage: "gearshape")
                }

            TrainingView(viewModel: viewModel)
                .tabItem {
                    Label("Training", systemImage: "chart.line.uptrend.xyaxis")
                }

            TestView(trainingViewModel: viewModel)
                .tabItem {
                    Label("Test", systemImage: "text.bubble")
                }

            FuseView(trainingViewModel: viewModel)
                .tabItem {
                    Label("Export", systemImage: "arrow.triangle.merge")
                }
        }
        .frame(minWidth: 820, minHeight: 620)
    }
}
