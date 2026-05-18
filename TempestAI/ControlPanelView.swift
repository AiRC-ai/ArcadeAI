import SwiftUI

/// Left-panel controls: run mode, arcade integrity, and AI behavior.
struct ControlPanelView: View {

    @ObservedObject var bridge = TempestRuntimeController.shared
    @State private var showAdvanced = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {

                // ---- Run ----
                SectionHeader("Run")

                ModeCard(
                    icon: runMode.icon,
                    title: runMode.title,
                    detail: runMode.detail,
                    tint: runMode.tint,
                    trailing: bridge.isGameRunning
                    ? "\(bridge.metrics.gameCount) active"
                    : runtimeLabel
                )

                HStack(spacing: 10) {
                    Button(action: { bridge.sendCommand("start_training") }) {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!bridge.isRuntimeReady || bridge.isGameRunning)

                    Button(action: { bridge.sendCommand("stop_training") }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .red))
                    .disabled(!bridge.isRuntimeReady || !bridge.isGameRunning)
                }

                HStack(spacing: 10) {
                    Button(action: { bridge.sendCommand("save_model") }) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!bridge.isRuntimeReady)

                    Button(action: { bridge.sendCommand("load_old_model") }) {
                        Label("Load Old", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!bridge.isRuntimeReady || bridge.isGameRunning)
                }

                HStack(spacing: 10) {
                    Button(action: { bridge.sendCommand("best_ai_mode") }) {
                        Label("Best AI", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: isBestAIMode ? .green : .white))
                    .disabled(!bridge.isRuntimeReady)

                    Button(action: { bridge.sendCommand("train_mode") }) {
                        Label("Learn", systemImage: "brain.head.profile")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: bridge.metrics.trainingEnabled ? .cyan : .white))
                    .disabled(!bridge.isRuntimeReady)
                }

                Button(action: { bridge.sendCommand("add_instance") }) {
                    Label("Add Game", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!bridge.isRuntimeReady || !bridge.isGameRunning)

                Divider().background(Color.white.opacity(0.1))

                // ---- Arcade Authenticity ----
                SectionHeader("Arcade")

                InfoPanel {
                    HStack(spacing: 8) {
                        StatusDot(color: bridge.metrics.authenticGameplay ? .green : .orange)
                        Text(arcadeTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    InfoLine("Game code", bridge.metrics.romName)
                    InfoLine("Score source", bridge.metrics.scoreSource)
                    InfoLine("High score", bridge.metrics.authenticGameplay ? "Counted" : "Not verified")
                    InfoLine("Display", rendererLabel)
                    InfoLine("Window", windowLabel)
                    Divider().background(Color.white.opacity(0.08))
                    InfoLine("Swift ROM", bridge.metrics.authenticGameplay ? "OK" : "Check")
                    InfoLine("Swift AVG", rendererLabel == "Swift AVG" ? "OK" : "Check")
                    InfoLine("Swift AI", bridge.isRuntimeReady ? aiRuntimeLabel : "Loading")
                    InfoLine("External processes", "None")
                }

                Divider().background(Color.white.opacity(0.1))

                // ---- AI Behavior ----
                SectionHeader("AI Behavior")

                BehaviorSlider(
                    title: "Explore",
                    value: Binding(
                        get: { bridge.metrics.epsilon },
                        set: { bridge.sendCommand("set_epsilon", params: ["value": $0]) }
                    ),
                    disabled: !bridge.isRuntimeReady,
                    caption: bridge.metrics.epsilon <= 0.001
                    ? "Off for watching the strongest learned play"
                    : "Lets the AI try risky moves so it can discover better play"
                )

                BehaviorSlider(
                    title: "Coach",
                    value: Binding(
                        get: { bridge.metrics.expertRatio },
                        set: { bridge.sendCommand("set_expert_ratio", params: ["value": $0]) }
                    ),
                    disabled: !bridge.isRuntimeReady,
                    caption: bridge.metrics.expertRatio <= 0.001
                    ? "Off means the neural policy is driving"
                    : "Blends in the safety coach while learning"
                )

                Divider().background(Color.white.opacity(0.1))

                Button {
                    showAdvanced.toggle()
                } label: {
                    HStack {
                        Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        SectionHeader("Advanced")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    Toggle("Learning updates", isOn: Binding(
                        get: { bridge.metrics.trainingEnabled },
                        set: { bridge.sendCommand("set_training", params: ["enabled": $0]) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .disabled(!bridge.isRuntimeReady)
                    .font(.callout)

                    HStack(spacing: 8) {
                        Button("Reset Explore") {
                            bridge.sendCommand("reset_epsilon")
                        }
                        .buttonStyle(CompactButtonStyle())
                        .disabled(!bridge.isRuntimeReady)

                        Button("Reset Coach") {
                            bridge.sendCommand("reset_expert")
                        }
                        .buttonStyle(CompactButtonStyle())
                        .disabled(!bridge.isRuntimeReady)
                    }

                    HStack(spacing: 8) {
                        Button("Explore Burst") {
                            bridge.sendCommand("epsilon_pulse")
                        }
                        .buttonStyle(CompactButtonStyle())

                        Button("Clear Examples") {
                            bridge.sendCommand("flush_buffer")
                        }
                        .buttonStyle(CompactButtonStyle(tint: .orange))
                    }
                    .disabled(!bridge.isRuntimeReady)
                }
            }
            .padding(16)
        }
    }

    private var isBestAIMode: Bool {
        bridge.isRuntimeReady
        && !bridge.metrics.trainingEnabled
        && bridge.metrics.epsilon <= 0.001
        && bridge.metrics.expertRatio <= 0.001
    }

    private var runMode: (icon: String, title: String, detail: String, tint: Color) {
        if !bridge.isRunning {
            return ("power", "Runtime stopped", "Start the runtime before launching games.", .gray)
        }
        if !bridge.isRuntimeReady {
            return ("bolt.horizontal", "Runtime starting", "Loading original ROM checks and Swift learner state.", .orange)
        }
        if isBestAIMode {
            return ("bolt.fill", "Best AI", "Greedy learned policy. Explore and Coach are off.", .green)
        }
        if bridge.metrics.trainingEnabled {
            return ("brain.head.profile", "Learning", "The AI is improving while games run.", .cyan)
        }
        return ("pause.fill", "Paused learning", "Policy is playing; training updates are paused.", .yellow)
    }

    private var runtimeLabel: String {
        if bridge.isRuntimeReady { return "ready" }
        if bridge.isRunning { return "starting" }
        return "stopped"
    }

    private var arcadeTitle: String {
        bridge.metrics.authenticGameplay
        ? "Original Tempest verified"
        : bridge.metrics.originalGameStatus
    }

    private var rendererLabel: String {
        if bridge.metrics.rendererRole.localizedCaseInsensitiveContains("swift") {
            return "Swift AVG"
        }
        return bridge.metrics.rendererRole.capitalized
    }

    private var windowLabel: String {
        if bridge.metrics.rendererRole.localizedCaseInsensitiveContains("swift") {
            return "Single window"
        }
        return bridge.metrics.runtimeHeadless ? "Single window" : "Debug window"
    }

    private var aiRuntimeLabel: String {
        let status = bridge.metrics.aiRuntimeStatus
        if status.localizedCaseInsensitiveContains("MLX Swift") {
            return "MLX Metal"
        }
        if status.localizedCaseInsensitiveContains("metallib missing") {
            return "CPU fallback"
        }
        return status
    }
}

// MARK: - Helpers

private struct SectionHeader: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary.opacity(0.7))
    }
}

private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

private struct ModeCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tint)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                Text(trailing.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(tint.opacity(0.9))
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.18), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct InfoPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct BehaviorSlider: View {
    let title: String
    @Binding var value: Double
    let disabled: Bool
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.74))
            }
            Slider(value: $value, in: 0...1)
                .disabled(disabled)
            Text(caption)
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.62))
                .lineLimit(2)
        }
    }
}

private struct InfoLine: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.65))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.6 : 0.8))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.vertical, 6)
            .background(tint.opacity(configuration.isPressed ? 0.14 : 0.08))
            .foregroundColor(tint.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct CompactButtonStyle: ButtonStyle {
    var tint: Color = .blue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(configuration.isPressed ? 0.3 : 0.2))
            .foregroundColor(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
