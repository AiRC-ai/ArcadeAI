import SwiftUI

/// Human-readable progress cards, updated reactively from the Swift runtime.
struct MetricsPanelView: View {

    @ObservedObject var bridge = TempestRuntimeController.shared
    @State private var showAdvanced = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 11) {
                SectionTitle("AI Progress")

                LearningSummaryRow(
                    title: learningTitle,
                    detail: learningDetail,
                    tint: learningTint
                )
                .padding(.horizontal, 12)

                LazyVGrid(columns: columns, spacing: 8) {
                    MetricCard(label: "Best Score", value: scoreLabel())
                    MetricCard(label: "Best Level", value: "\(bridge.metrics.peakLevel)")
                    MetricCard(label: "MLX Updates", value: shortScale(bridge.metrics.mlxOptimizerSteps))
                    MetricCard(label: "Examples Saved", value: shortScale(bridge.metrics.memoryBufferSize))
                    MetricCard(label: "Games Played", value: "\(bridge.metrics.episodes)")
                    MetricCard(label: "Active Games", value: "\(bridge.metrics.gameCount)")
                }
                .padding(.horizontal, 12)

                Button {
                    showAdvanced.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("ADVANCED")
                            .font(.system(size: 10, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    SectionTitle("Performance")
                        .padding(.top, 2)
                    LazyVGrid(columns: columns, spacing: 8) {
                        MetricCard(label: "Sim Speed", value: fmt(bridge.metrics.simFramesPerSecond, digits: 0) + " f/s")
                        MetricCard(label: "UI Frames", value: fmt(bridge.metrics.renderPublishFPS, digits: 0) + " FPS")
                        MetricCard(label: "Runtime Tick", value: fmt(bridge.metrics.runtimeTickMS, digits: 2) + " ms")
                        MetricCard(label: "Emulator", value: fmt(bridge.metrics.emulatorStepMS, digits: 2) + " ms")
                        MetricCard(label: "MLX Infer", value: fmt(bridge.metrics.inferenceMS, digits: 2) + " ms")
                        MetricCard(label: "Dropped", value: "\(bridge.metrics.droppedFrames)")
                    }
                    .padding(.horizontal, 12)

                    SectionTitle("Learner")
                        .padding(.top, 2)
                    LazyVGrid(columns: columns, spacing: 8) {
                        MetricCard(label: "Frames Seen", value: shortScale(bridge.metrics.frameCount))
                        MetricCard(label: "Learning Loss", value: fmt(bridge.metrics.loss, digits: 4))
                        MetricCard(label: "Grad Norm", value: fmt(bridge.metrics.gradNorm, digits: 1))
                        MetricCard(label: "Updates / Sec", value: fmt(bridge.metrics.learnerUpdatesPerSecond, digits: 2))
                        MetricCard(label: "Replay Sample", value: fmt(bridge.metrics.replaySampleMS, digits: 2) + " ms")
                        MetricCard(label: "Batch Build", value: fmt(bridge.metrics.trainingBatchMS, digits: 2) + " ms")
                        MetricCard(label: "Optimizer", value: fmt(bridge.metrics.optimizerMS, digits: 2) + " ms")
                        MetricCard(label: "Learner Busy", value: bridge.metrics.trainingInFlight ? "Yes" : "No")
                        MetricCard(label: "Prior Updates", value: shortScale(bridge.metrics.totalTrainingSteps))
                        MetricCard(label: "Move Match", value: fmt(bridge.metrics.agreement * 100, digits: 0) + "%")
                        MetricCard(label: "AI Confidence", value: fmt(bridge.metrics.qMean, digits: 1))
                        MetricCard(label: "Avg Level", value: fmt(bridge.metrics.averageLevel, digits: 1))
                        MetricCard(label: "ROM High", value: highScoreLabel())
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private var isBestAIMode: Bool {
        bridge.isRuntimeReady
        && !bridge.metrics.trainingEnabled
        && bridge.metrics.epsilon <= 0.001
        && bridge.metrics.expertRatio <= 0.001
    }

    private var learningTitle: String {
        if isBestAIMode { return "Watching Best AI" }
        if bridge.metrics.trainingEnabled { return "Learning is on" }
        return "Learning paused"
    }

    private var learningDetail: String {
        if isBestAIMode {
            return "The saved policy is playing with Explore and Coach turned off."
        }
        if bridge.metrics.trainingEnabled {
            return "New gameplay feeds one shared MLX learner across all active games."
        }
        return "The policy can play, but new training updates are stopped."
    }

    private var learningTint: Color {
        if isBestAIMode { return .green }
        if bridge.metrics.trainingEnabled { return .cyan }
        return .yellow
    }

    private func scoreLabel() -> String {
        bridge.metrics.authenticGameplay
        ? shortScale(bridge.metrics.peakGameScore)
        : "Unverified"
    }

    private func highScoreLabel() -> String {
        bridge.metrics.authenticGameplay
        ? shortScale(bridge.metrics.romHighScore)
        : "Not verified"
    }
}

// MARK: - Metric Card

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.horizontal, 12)
    }
}

private struct LearningSummaryRow: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.16), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MetricCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Formatting Helpers

private func fmt(_ v: Double, digits: Int) -> String {
    let f = NumberFormatter()
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = digits
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private func shortScale(_ n: Int) -> String {
    if n >= 1_000_000 {
        return String(format: "%.1fM", Double(n) / 1_000_000)
    }
    if n >= 1_000 {
        return String(format: "%.1fK", Double(n) / 1_000)
    }
    return "\(n)"
}
