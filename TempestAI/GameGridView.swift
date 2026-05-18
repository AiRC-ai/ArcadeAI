import SwiftUI

struct GameGridView: View {
    @ObservedObject private var bridge = TempestRuntimeController.shared
    @State private var now = Date()

    private let refreshTimer = Timer.publish(
        every: 1.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        let frames = bridge.gameFramesByClientID.values.sorted {
            $0.clientID < $1.clientID
        }

        ZStack {
            Color.black

            if frames.isEmpty {
                waitingView
            } else {
                GeometryReader { proxy in
                    grid(frames: frames, size: proxy.size)
                }
                .padding(1)
            }
        }
        .onReceive(refreshTimer) { date in
            now = date
            bridge.pruneStaleFrames(now: date)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for game frames...")
                .font(.callout)
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private func grid(frames: [GameFrameData], size: CGSize) -> some View {
        let dimensions = GameGridLayout.dimensions(for: frames.count)
        let tileWidth = max(1.0, size.width / CGFloat(max(1, dimensions.columns)))
        let tileHeight = max(1.0, size.height / CGFloat(max(1, dimensions.rows)))

        return VStack(spacing: 1) {
            ForEach(0..<dimensions.rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<dimensions.columns, id: \.self) { column in
                        let index = (row * dimensions.columns) + column
                        if index < frames.count {
                            GameTileView(
                                frame: frames[index],
                                scoreVerified: bridge.metrics.authenticGameplay,
                                receivedAt: bridge.receivedAt(
                                    for: frames[index].clientID
                                ),
                                now: now,
                                canRemove: frames.count > 1,
                                onRemove: {
                                    bridge.removeGame(clientID: frames[index].clientID)
                                }
                            )
                            .frame(width: tileWidth, height: tileHeight)
                        } else {
                            Color.black
                                .frame(width: tileWidth, height: tileHeight)
                        }
                    }
                }
            }
        }
    }
}

private struct GameTileView: View {
    let frame: GameFrameData
    let scoreVerified: Bool
    let receivedAt: Date?
    let now: Date
    let canRemove: Bool
    let onRemove: () -> Void
    @State private var isHovered = false

    private var age: TimeInterval {
        guard let receivedAt else { return 999.0 }
        return max(0.0, now.timeIntervalSince(receivedAt))
    }

    private var isStale: Bool {
        age > 1.5
    }

    var body: some View {
        ZStack {
            GameDisplayView(frame: frame, scoreVerified: scoreVerified)
                .opacity(isStale ? 0.45 : 1.0)

            VStack {
                HStack {
                    tileHUD
                    Spacer()
                    if canRemove && isHovered {
                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.88))
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.62))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Remove this game")
                        .padding(6)
                    }
                }
                Spacer()
            }

            if isStale {
                Text(freshnessText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private var tileHUD: some View {
        HStack(spacing: 8) {
            Text("G\(frame.clientID)")
            Text(scoreText)
            Text("L\(frame.displayLevel)")
            Text("♥\(max(0, frame.lives))")
            if let fps = frame.fps, fps > 0 {
                Text("\(Int(fps.rounded())) FPS")
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(.white.opacity(0.82))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(6)
    }

    private var scoreText: String {
        if frame.score >= 1_000_000 {
            return String(format: "%.1fM", Double(frame.score) / 1_000_000)
        }
        if frame.score >= 10_000 {
            return String(format: "%.1fK", Double(frame.score) / 1_000)
        }
        return "\(frame.score)"
    }

    private var freshnessText: String {
        if frame.gameOver {
            return "Game Over"
        }
        if frame.lifeLost {
            return "Life Lost"
        }
        if let fps = frame.fps, fps > 0 {
            return String(format: "%.0f FPS", fps)
        }
        if age < 1.0 {
            return "Live"
        }
        return String(format: "%.1fs", age)
    }
}
