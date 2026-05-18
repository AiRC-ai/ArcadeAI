import SwiftUI

/// Root view: left panel (controls + metrics) | right panel (game) | status bar.
struct ContentView: View {

    @StateObject private var bridge = TempestRuntimeController.shared
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // ---- Left Panel ----
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tempest AI")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text("Original Tempest ROM + learned policy")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    Divider().background(Color.white.opacity(0.06))

                    // Scrollable controls
                    ControlPanelView()
                        .frame(minWidth: 220)

                    Divider().background(Color.white.opacity(0.06))

                    // Diagnostics toggle
                    Button {
                        showLog.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showLog
                                  ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("Diagnostics")
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Circle()
                                .fill(bridge.isRuntimeReady
                                      ? Color.green : bridge.isRunning
                                      ? Color.yellow : Color.gray)
                                .frame(width: 6, height: 6)
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)

                    if showLog {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(bridge.logLines.enumerated()),
                                            id: \.offset)
                                    { _, line in
                                        Text(line)
                                            .font(.system(
                                                size: 10,
                                                design: .monospaced
                                            ))
                                            .foregroundColor(line.hasPrefix("ERROR")
                                                             ? .red
                                                             : line.hasPrefix("←")
                                                             ? .green.opacity(0.7)
                                                             : line.hasPrefix("→")
                                                             ? .blue.opacity(0.7)
                                                             : .secondary.opacity(0.8))
                                            .lineLimit(3)
                                    }
                                }
                                .padding(8)
                            }
                            .frame(maxHeight: 150)
                            .background(Color.black.opacity(0.3))
                            .onChange(of: bridge.logLines.count) { _, _ in
                                if let last = bridge.logLines.indices.last {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.06))

                    // Metrics
                    MetricsPanelView()
                }
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 340)
                .background(Color(white: 0.06))

                // ---- Right Panel: Game Display ----
                ZStack {
                    Color(white: 0.04)

                    if bridge.isRuntimeReady && bridge.isGameRunning {
                        GameGridView()
                    } else {
                        placeholderView
                    }
                }
                .layoutPriority(1)
            }

            Divider().background(Color.white.opacity(0.06))

            // ---- Bottom Status Bar ----
            StatusBarView()
        }
        .background(Color(white: 0.03))
        .onAppear { bridge.start() }
        .onDisappear { bridge.stop() }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 16) {
            if !bridge.isRuntimeReady {
                // Swift runtime is not ready yet.
                ProgressView()
                    .scaleEffect(1.2)
                Text(bridge.status)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
                Text("Starting Swift ROM runtime…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.25))
            } else if !bridge.isGameRunning {
                // Runtime is ready, but no game is running.
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.white.opacity(0.15))

                Text("Press **Start** to launch")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.35))

                Text("The Swift ROM runtime will appear here\ninside the app window")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.2))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
