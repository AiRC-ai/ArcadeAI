import SwiftUI

/// Bottom status bar: runtime health, run mode, and instance count.
struct StatusBarView: View {

    @ObservedObject var bridge = TempestRuntimeController.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(bridge.status)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Text(modeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(modeColor.opacity(0.85))
                .lineLimit(1)

            Divider()
                .frame(height: 12)
                .background(Color.white.opacity(0.12))

            Text(bridge.metrics.authenticGameplay ? "Original ROM" : "Unverified ROM")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.72))
                .lineLimit(1)

            Text("Games: \(bridge.metrics.gameCount)")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
    }

    private var isBestAIMode: Bool {
        bridge.isRuntimeReady
        && !bridge.metrics.trainingEnabled
        && bridge.metrics.epsilon <= 0.001
        && bridge.metrics.expertRatio <= 0.001
    }

    private var modeLabel: String {
        if !bridge.isRuntimeReady { return "Runtime" }
        if isBestAIMode { return "Best AI" }
        if bridge.metrics.trainingEnabled { return "Learning" }
        return "Policy paused"
    }

    private var modeColor: Color {
        if !bridge.isRuntimeReady { return .orange }
        if isBestAIMode { return .green }
        if bridge.metrics.trainingEnabled { return .cyan }
        return .yellow
    }

    private var statusColor: Color {
        if !bridge.isRunning { return .gray }
        if !bridge.isRuntimeReady { return .orange }
        if bridge.metrics.gameCount > 0 { return .green }
        return .yellow
    }
}
