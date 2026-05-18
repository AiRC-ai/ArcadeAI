import SwiftUI

/// Native Tempest display. Normal app play runs the original Tempest ROM in
/// the Swift emulator and renders AVG vector lines from that emulator.
struct GameDisplayView: View {

    let frame: GameFrameData
    let scoreVerified: Bool
    private let useMetalRenderer: Bool

    init(frame: GameFrameData, scoreVerified: Bool = true) {
        self.frame = frame
        self.scoreVerified = scoreVerified
        self.useMetalRenderer = ProcessInfo
            .processInfo
            .environment["TEMPEST_CANVAS_FALLBACK"] != "1"
    }

    var body: some View {
        ZStack {
            Color.black

            if useMetalRenderer && !frame.vectorLines.isEmpty {
                MetalVectorDisplayView(frame: frame)
            } else {
                Canvas(
                    opaque: true,
                    colorMode: .linear,
                    rendersAsynchronously: true
                ) { context, size in
                    if frame.vectorLines.isEmpty {
                    drawSyntheticFallback(in: &context, size: size, frame: frame)
                    } else {
                        drawROMVectors(in: &context, size: size, frame: frame)
                    }
                }
            }
        }
    }

    // MARK: - Draw Passes

    private func drawROMVectors(
        in context: inout GraphicsContext,
        size: CGSize,
        frame: GameFrameData
    ) {
        let viewport = ROMVectorViewport(
            rawWidth: max(1.0, frame.vectorWidth),
            rawHeight: max(1.0, frame.vectorHeight),
            targetSize: size,
            lines: frame.vectorLines,
            renderer: frame.renderer
        )
        let lineWidth = max(0.40, min(0.70, min(size.width, size.height) * 0.00055))
        let useGlowStroke = ProcessInfo
            .processInfo
            .environment["TEMPEST_CANVAS_VECTOR_GLOW"] == "1"
        var strokeGroups: [UInt64: Path] = [:]
        var strokeColors: [UInt64: Color] = [:]
        var pointDots: [(point: CGPoint, color: Color)] = []

        for line in frame.vectorLines {
            let start = viewport.point(x: line.x0, y: line.y0)
            let end = viewport.point(x: line.x1, y: line.y1)
            let color = vectorColor(argb: line.argb, intensity: line.intensity)
            let rawLength = hypot(line.x1 - line.x0, line.y1 - line.y0)
            let isPointVector = rawLength < 0.01
            if isPointVector {
                pointDots.append((start, color))
                continue
            }

            let key = colorKey(argb: line.argb, intensity: line.intensity)
            var path = strokeGroups[key] ?? Path()
            path.move(to: start)
            path.addLine(to: end)
            strokeGroups[key] = path
            strokeColors[key] = color
        }

        for key in strokeGroups.keys.sorted() {
            guard let path = strokeGroups[key], let color = strokeColors[key] else {
                continue
            }
            if useGlowStroke {
                context.stroke(
                    path,
                    with: .color(color.opacity(0.18)),
                    lineWidth: max(0.55, lineWidth * 1.35)
                )
            }
            context.stroke(
                path,
                with: .color(color),
                lineWidth: max(0.45, lineWidth)
            )
        }

        let radius = max(0.50, lineWidth * 0.95)
        for dot in pointDots {
            let rect = CGRect(
                x: dot.point.x - radius,
                y: dot.point.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -radius * 0.22, dy: -radius * 0.22)),
                with: .color(dot.color.opacity(0.10))
            )
            context.fill(Path(ellipseIn: rect), with: .color(dot.color))
        }
    }

    private func drawSyntheticFallback(
        in context: inout GraphicsContext,
        size: CGSize,
        frame: GameFrameData
    ) {
        let geometry = TubeGeometry(size: size, frame: frame)
        drawTube(in: &context, geometry: geometry, frame: frame)
        drawSpikes(in: &context, geometry: geometry, frame: frame)
        drawShots(in: &context, geometry: geometry, frame: frame)
        drawEnemies(in: &context, geometry: geometry, frame: frame)
        drawPlayer(in: &context, geometry: geometry, frame: frame)
        drawHUD(in: &context, size: size, frame: frame)
    }

    private func drawTube(
        in context: inout GraphicsContext,
        geometry: TubeGeometry,
        frame: GameFrameData
    ) {
        var tube = Path()

        for lane in 0..<geometry.laneCount {
            tube.move(to: geometry.point(lane: Double(lane), depth: 0.0))
            tube.addLine(to: geometry.point(lane: Double(lane), depth: 1.0))
        }

        for depth in geometry.ringDepths {
            let ring = geometry.ringPoints(depth: depth)
            for lane in 0..<geometry.edgeCount {
                let next = geometry.nextLane(after: lane)
                tube.move(to: ring[lane])
                tube.addLine(to: ring[next])
            }
        }

        context.stroke(
            tube,
            with: .color(Color(red: 0.0, green: 0.10, blue: 1.0)),
            lineWidth: max(1.0, geometry.scale * 0.003)
        )
    }

    private func drawSpikes(
        in context: inout GraphicsContext,
        geometry: TubeGeometry,
        frame: GameFrameData
    ) {
        var spikesPath = Path()
        for lane in 0..<min(16, frame.spikes.count) {
            let height = max(0.0, min(1.0, frame.spikes[lane]))
            guard height > 0.02 else { continue }
            let start = geometry.point(lane: Double(lane), depth: 0.0)
            let end = geometry.point(lane: Double(lane), depth: height * 0.72)
            spikesPath.move(to: start)
            spikesPath.addLine(to: end)
        }
        context.stroke(
            spikesPath,
            with: .color(Color(red: 0.0, green: 0.7, blue: 1.0).opacity(0.9)),
            lineWidth: max(1.0, geometry.scale * 0.004)
        )
    }

    private func drawShots(
        in context: inout GraphicsContext,
        geometry: TubeGeometry,
        frame: GameFrameData
    ) {
        for shot in frame.playerShots {
            let point = geometry.point(lane: shot.lane, depth: 1.0 - shot.depth)
            drawDiamond(
                in: &context,
                center: point,
                radius: max(2.0, geometry.scale * 0.008),
                color: .white,
                lineWidth: max(1.0, geometry.scale * 0.003)
            )
        }

        for shot in frame.enemyShots {
            let point = geometry.point(lane: shot.lane, depth: 1.0 - shot.depth)
            drawDiamond(
                in: &context,
                center: point,
                radius: max(2.0, geometry.scale * 0.009),
                color: .red,
                lineWidth: max(1.0, geometry.scale * 0.003)
            )
        }
    }

    private func drawEnemies(
        in context: inout GraphicsContext,
        geometry: TubeGeometry,
        frame: GameFrameData
    ) {
        for enemy in frame.enemies {
            let point = geometry.point(lane: enemy.lane, depth: 1.0 - enemy.depth)
            let radius = max(5.0, geometry.scale * (enemy.topRail ? 0.024 : 0.018))
            drawEnemy(
                in: &context,
                center: point,
                laneAngle: geometry.angle(for: enemy.lane),
                radius: radius,
                color: color(forEnemyType: enemy.type),
                lineWidth: max(1.0, geometry.scale * 0.004)
            )
        }
    }

    private func drawPlayer(
        in context: inout GraphicsContext,
        geometry: TubeGeometry,
        frame: GameFrameData
    ) {
        let center = geometry.point(lane: frame.playerLane, depth: 0.0)
        let angle = geometry.angle(for: frame.playerLane)
        let tangent = CGVector(dx: CGFloat(-sin(angle)), dy: CGFloat(cos(angle)))
        let radial = CGVector(dx: CGFloat(cos(angle)), dy: CGFloat(sin(angle)))
        let width = max(10.0, geometry.scale * 0.036)
        let height = max(12.0, geometry.scale * 0.045)

        var ship = Path()
        ship.move(to: CGPoint(
            x: center.x + radial.dx * height,
            y: center.y + radial.dy * height
        ))
        ship.addLine(to: CGPoint(
            x: center.x + tangent.dx * width - radial.dx * height * 0.35,
            y: center.y + tangent.dy * width - radial.dy * height * 0.35
        ))
        ship.addLine(to: CGPoint(
            x: center.x - tangent.dx * width - radial.dx * height * 0.35,
            y: center.y - tangent.dy * width - radial.dy * height * 0.35
        ))
        ship.closeSubpath()

        let color = frame.playerAlive ? Color.green : Color.red
        context.stroke(ship, with: .color(color), lineWidth: max(1.5, geometry.scale * 0.005))
    }

    private func drawHUD(
        in context: inout GraphicsContext,
        size: CGSize,
        frame: GameFrameData
    ) {
        let scoreText = Text(String(format: "%06d", frame.score))
            .font(.system(size: max(16, size.height * 0.035), weight: .regular, design: .monospaced))
            .foregroundColor(.green)
        context.draw(scoreText, at: CGPoint(x: size.width * 0.50, y: size.height * 0.10), anchor: .center)

        if frame.highScore > 0 {
            let label = scoreVerified
                ? "HI \(String(format: "%06d", frame.highScore))"
                : "HI NOT VERIFIED"
            let highText = Text(label)
                .font(.system(size: max(9, size.height * 0.017), weight: .regular, design: .monospaced))
                .foregroundColor(.green.opacity(0.78))
            context.draw(highText, at: CGPoint(x: size.width * 0.84, y: size.height * 0.10), anchor: .center)
        }

        if frame.gamestate == 0 || frame.score == 0 {
            let startText = Text("PRESS START")
                .font(.system(size: max(14, size.height * 0.028), weight: .regular, design: .monospaced))
                .foregroundColor(.red)
            context.draw(startText, at: CGPoint(x: size.width * 0.50, y: size.height * 0.16), anchor: .center)
        }

        let lower = Text("LEVEL \(frame.level)   LIVES \(frame.lives)   SHOTS \(frame.remainingShots)")
            .font(.system(size: max(11, size.height * 0.020), weight: .regular, design: .monospaced))
            .foregroundColor(.cyan)
        context.draw(lower, at: CGPoint(x: size.width * 0.50, y: size.height * 0.93), anchor: .center)
    }

    // MARK: - Shape Helpers

    private func drawDiamond(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawEnemy(
        in context: inout GraphicsContext,
        center: CGPoint,
        laneAngle: Double,
        radius: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        let tangent = CGVector(dx: CGFloat(-sin(laneAngle)), dy: CGFloat(cos(laneAngle)))
        let radial = CGVector(dx: CGFloat(cos(laneAngle)), dy: CGFloat(sin(laneAngle)))

        var path = Path()
        path.move(to: CGPoint(
            x: center.x + radial.dx * radius,
            y: center.y + radial.dy * radius
        ))
        path.addLine(to: CGPoint(
            x: center.x + tangent.dx * radius,
            y: center.y + tangent.dy * radius
        ))
        path.addLine(to: CGPoint(
            x: center.x - radial.dx * radius,
            y: center.y - radial.dy * radius
        ))
        path.addLine(to: CGPoint(
            x: center.x - tangent.dx * radius,
            y: center.y - tangent.dy * radius
        ))
        path.closeSubpath()
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func color(forEnemyType type: Int) -> Color {
        switch type {
        case 1:
            return .yellow
        case 2:
            return .orange
        case 3:
            return .purple
        case 4:
            return .white
        default:
            return Color(red: 1.0, green: 0.9, blue: 0.0)
        }
    }

    private func vectorColor(argb: UInt32, intensity: Int) -> Color {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        let normalized = max(0.0, min(1.0, Double(intensity) / 255.0))
        let i = min(1.0, pow(normalized, 0.62) * 2.10)
        return Color(
            red: min(1.0, r * i),
            green: min(1.0, g * i),
            blue: min(1.0, b * i),
            opacity: min(1.0, a * max(0.32, normalized * 1.60))
        )
    }

    private func colorKey(argb: UInt32, intensity: Int) -> UInt64 {
        (UInt64(argb) << 16) | UInt64(max(0, min(255, intensity)))
    }
}

private struct ROMVectorViewport {
    private let rawWidth: Double
    private let rawHeight: Double
    private let scale: Double
    private let offsetX: Double
    private let offsetY: Double
    private let minX: Double
    private let minY: Double
    private let renderer: String

    init(
        rawWidth: Double,
        rawHeight: Double,
        targetSize: CGSize,
        lines: [GameVectorLineData],
        renderer: String
    ) {
        let swiftAVGConfig = renderer == "swift_avg_vector"
            ? TempestVectorViewportConfig.swiftAVG()
            : nil
        let viewportWidth = swiftAVGConfig?.width ?? rawWidth
        let viewportHeight = swiftAVGConfig?.height ?? rawHeight

        self.rawWidth = viewportWidth
        self.rawHeight = viewportHeight
        self.renderer = renderer

        // Keep ROM-vector output pinned to the device bounds. Fitting to only
        // the visible lines makes the playfield jump whenever bullets, score
        // text, or attract-mode messages enter and leave the frame.
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            let x = Double(point.x)
            let y = Double(point.y)
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }

        if let swiftAVGConfig {
            include(Self.displayPoint(
                x: swiftAVGConfig.minX,
                y: swiftAVGConfig.minY,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: swiftAVGConfig.maxX,
                y: swiftAVGConfig.minY,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: swiftAVGConfig.minX,
                y: swiftAVGConfig.maxY,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: swiftAVGConfig.maxX,
                y: swiftAVGConfig.maxY,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
        } else if renderer == "mame_vector" {
            include(Self.displayPoint(
                x: 0,
                y: 0,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: viewportWidth,
                y: 0,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: 0,
                y: viewportHeight,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
            include(Self.displayPoint(
                x: viewportWidth,
                y: viewportHeight,
                rawWidth: viewportWidth,
                rawHeight: viewportHeight,
                renderer: renderer
            ))
        } else {
            for line in lines {
                include(Self.displayPoint(
                    x: line.x0,
                    y: line.y0,
                    rawWidth: viewportWidth,
                    rawHeight: viewportHeight,
                    renderer: renderer
                ))
                include(Self.displayPoint(
                    x: line.x1,
                    y: line.y1,
                    rawWidth: viewportWidth,
                    rawHeight: viewportHeight,
                    renderer: renderer
                ))
            }
        }

        if !minX.isFinite || !minY.isFinite || maxX <= minX || maxY <= minY {
            minX = 0
            minY = 0
            maxX = viewportWidth
            maxY = viewportHeight
        }

        let contentWidth = max(1.0, maxX - minX)
        let contentHeight = max(1.0, maxY - minY)
        let padding = max(contentWidth, contentHeight) * 0.035
        self.minX = minX - padding
        self.minY = minY - padding
        let displayWidth = contentWidth + (padding * 2.0)
        let displayHeight = contentHeight + (padding * 2.0)
        self.scale = min(
            Double(targetSize.width) / displayWidth,
            Double(targetSize.height) / displayHeight
        )
        self.offsetX = (Double(targetSize.width) - (displayWidth * scale)) * 0.5
        self.offsetY = (Double(targetSize.height) - (displayHeight * scale)) * 0.5
    }

    func point(x: Double, y: Double) -> CGPoint {
        let display = Self.displayPoint(
            x: x,
            y: y,
            rawWidth: rawWidth,
            rawHeight: rawHeight,
            renderer: renderer
        )
        return CGPoint(
            x: offsetX + ((Double(display.x) - minX) * scale),
            y: offsetY + ((Double(display.y) - minY) * scale)
        )
    }

    private static func displayPoint(
        x: Double,
        y: Double,
        rawWidth: Double,
        rawHeight: Double,
        renderer: String
    ) -> CGPoint {
        if renderer == "mame_vector" {
            return CGPoint(x: y, y: rawWidth - x)
        }
        if renderer == "swift_avg_vector" {
            return CGPoint(x: x, y: y)
        }
        return CGPoint(x: x, y: y)
    }
}

private struct TubeGeometry {
    let laneCount = 16
    let size: CGSize
    let center: CGPoint
    let scale: CGFloat
    let wraps: Bool
    let outer: [CGPoint]
    let inner: [CGPoint]

    var edgeCount: Int { wraps ? laneCount : laneCount - 1 }
    var ringDepths: [Double] { [0.0, 0.34, 0.66, 1.0] }

    init(size: CGSize, frame: GameFrameData) {
        self.size = size
        self.scale = min(size.width, size.height)
        self.center = CGPoint(x: size.width * 0.5, y: size.height * 0.53)
        let tubeIndex = Self.tubeIndex(forLevel: frame.level)
        self.wraps = !(frame.openLevel || Self.levelOpen[tubeIndex])

        let geometryCenter = center
        let rawVertices = (0..<laneCount).map {
            Self.webVertex(lane: $0, tubeIndex: tubeIndex)
        }
        let normalized = Self.normalize(vertices: rawVertices)
        let radius = scale * 0.39
        let outerPoints = normalized.map {
            CGPoint(
                x: geometryCenter.x + ($0.x * radius),
                y: geometryCenter.y + ($0.y * radius)
            )
        }
        let innerScale: CGFloat = frame.openLevel ? 0.18 : 0.23
        let innerPoints = outerPoints.map {
            CGPoint(
                x: geometryCenter.x + (($0.x - geometryCenter.x) * innerScale),
                y: geometryCenter.y + (($0.y - geometryCenter.y) * innerScale)
            )
        }
        self.outer = outerPoints
        self.inner = innerPoints
    }

    func angle(for lane: Double) -> Double {
        let outerPoint = pointOn(vertices: outer, lane: lane)
        let innerPoint = pointOn(vertices: inner, lane: lane)
        return atan2(
            Double(outerPoint.y - innerPoint.y),
            Double(outerPoint.x - innerPoint.x)
        )
    }

    func point(lane: Double, depth: Double) -> CGPoint {
        let clampedDepth = max(0.0, min(1.0, depth))
        let outerPoint = pointOn(vertices: outer, lane: lane)
        let innerPoint = pointOn(vertices: inner, lane: lane)
        return CGPoint(
            x: outerPoint.x + ((innerPoint.x - outerPoint.x) * clampedDepth),
            y: outerPoint.y + ((innerPoint.y - outerPoint.y) * clampedDepth)
        )
    }

    func ringPoints(depth: Double) -> [CGPoint] {
        (0..<laneCount).map { point(lane: Double($0), depth: depth) }
    }

    func nextLane(after lane: Int) -> Int {
        wraps ? ((lane + 1) % laneCount) : min(lane + 1, laneCount - 1)
    }

    private func pointOn(vertices: [CGPoint], lane: Double) -> CGPoint {
        let clamped: Double
        if wraps {
            clamped = lane.truncatingRemainder(dividingBy: Double(laneCount))
        } else {
            clamped = max(0.0, min(Double(laneCount - 1), lane))
        }
        let base = Int(floor(clamped))
        let next = wraps ? ((base + 1) % laneCount) : min(base + 1, laneCount - 1)
        let t = CGFloat(clamped - Double(base))
        let a = vertices[base]
        let b = vertices[next]
        return CGPoint(
            x: a.x + ((b.x - a.x) * t),
            y: a.y + ((b.y - a.y) * t)
        )
    }

    private static func tubeIndex(forLevel level: Int) -> Int {
        let shape = ((level % 16) + 16) % 16
        return levelRemap[shape]
    }

    private static func webVertex(lane: Int, tubeIndex: Int) -> CGPoint {
        let index = (tubeIndex * 16) + lane
        let x = CGFloat(Int(levelX[index]) - 0x80) / 112.0
        let y = CGFloat(0x80 - Int(levelY[index])) / 112.0
        return CGPoint(x: x, y: y)
    }

    // Original Atari Tempest tube geometry tables:
    // lev_x, lev_y, lev_remap, lev_open. Values are the 16 rim vertices
    // for each web shape, centered around 0x80 in the original coordinate
    // system. Keeping these tables here makes the native renderer follow the
    // actual game webs instead of approximating every level as a circle.
    private static let levelRemap: [Int] = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x0D, 0x09, 0x08, 0x0C, 0x0E, 0x0F, 0x0A, 0x0B,
    ]

    private static let levelOpen: [Bool] = [
        false, false, false, false, false, false, false, true,
        true, true, true, false, false, true, false, true,
    ]

    private static let levelX: [UInt8] = [
        0xF0, 0xE7, 0xCF, 0xAA, 0x80, 0x56, 0x31, 0x19, 0x10, 0x19, 0x31, 0x56, 0x80, 0xAA, 0xCF, 0xE7,
        0xF0, 0xF0, 0xF0, 0xB8, 0x80, 0x48, 0x10, 0x10, 0x10, 0x10, 0x10, 0x48, 0x80, 0xB8, 0xF0, 0xF0,
        0xF0, 0xF0, 0xB8, 0xB8, 0x80, 0x48, 0x48, 0x10, 0x10, 0x10, 0x48, 0x48, 0x80, 0xB8, 0xB8, 0xF0,
        0xEC, 0xD5, 0xB1, 0x90, 0x70, 0x4F, 0x2B, 0x14, 0x14, 0x2B, 0x4F, 0x70, 0x90, 0xB1, 0xD5, 0xEC,
        0xF0, 0xC0, 0xA0, 0x94, 0x6C, 0x60, 0x40, 0x10, 0x10, 0x40, 0x60, 0x6C, 0x94, 0xA0, 0xC0, 0xF0,
        0xD9, 0xC2, 0xAC, 0x97, 0x80, 0x69, 0x52, 0x3C, 0x27, 0x10, 0x35, 0x5A, 0x80, 0xA6, 0xCA, 0xF0,
        0xEA, 0xE0, 0x9C, 0x80, 0x64, 0x20, 0x16, 0x50, 0x16, 0x20, 0x64, 0x80, 0x9C, 0xE0, 0xEA, 0xB0,
        0x10, 0x1E, 0x2C, 0x3A, 0x48, 0x56, 0x64, 0x70, 0x90, 0x9E, 0xAC, 0xBA, 0xC8, 0xD6, 0xE4, 0xF0,
        0x10, 0x1E, 0x2D, 0x3C, 0x4B, 0x5A, 0x69, 0x78, 0x87, 0x96, 0xA5, 0xB4, 0xC3, 0xD2, 0xE1, 0xF0,
        0x10, 0x10, 0x10, 0x10, 0x16, 0x29, 0x46, 0x69, 0x97, 0xBA, 0xD7, 0xEA, 0xF0, 0xF0, 0xF0, 0xF0,
        0x10, 0x24, 0x30, 0x36, 0x3E, 0x49, 0x5A, 0x75, 0x94, 0xA4, 0xAC, 0xBA, 0xDA, 0xE2, 0xEA, 0xF0,
        0x80, 0x70, 0x48, 0x20, 0x10, 0x20, 0x48, 0x70, 0x80, 0x90, 0xB8, 0xE0, 0xF0, 0xE0, 0xB8, 0x90,
        0xDA, 0xA4, 0x87, 0x80, 0x79, 0x5C, 0x26, 0x10, 0x10, 0x20, 0x48, 0x80, 0xB8, 0xE0, 0xF0, 0xF0,
        0x10, 0x10, 0x30, 0x30, 0x50, 0x50, 0x70, 0x70, 0x90, 0x90, 0xB0, 0xB0, 0xD0, 0xD0, 0xF0, 0xF0,
        0xB0, 0x80, 0x50, 0x47, 0x18, 0x30, 0x18, 0x47, 0x50, 0x80, 0xB0, 0xB9, 0xE8, 0xD4, 0xE8, 0xB9,
        0x10, 0x1E, 0x21, 0x28, 0x3C, 0x55, 0x66, 0x73, 0x8D, 0x9A, 0xAB, 0xC4, 0xD8, 0xDF, 0xE2, 0xF0,
    ]

    private static let levelY: [UInt8] = [
        0x80, 0xAA, 0xCF, 0xE7, 0xF0, 0xE7, 0xCF, 0xAA, 0x80, 0x56, 0x31, 0x19, 0x10, 0x19, 0x31, 0x56,
        0x80, 0xB8, 0xF0, 0xF0, 0xF0, 0xF0, 0xF0, 0xB8, 0x80, 0x48, 0x10, 0x10, 0x10, 0x10, 0x10, 0x48,
        0x80, 0xB8, 0xB8, 0xF0, 0xF0, 0xF0, 0xB8, 0xB8, 0x80, 0x48, 0x48, 0x10, 0x10, 0x10, 0x48, 0x48,
        0x94, 0xB0, 0xB8, 0xA7, 0xA7, 0xB8, 0xB0, 0x94, 0x6C, 0x50, 0x48, 0x59, 0x59, 0x48, 0x50, 0x6C,
        0x96, 0xA3, 0xC5, 0xF0, 0xF0, 0xC5, 0xA3, 0x96, 0x6A, 0x5D, 0x3B, 0x10, 0x10, 0x3B, 0x5D, 0x6A,
        0x3D, 0x6A, 0x97, 0xC4, 0xF0, 0xC4, 0x97, 0x6A, 0x3D, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
        0xA0, 0xE0, 0xEA, 0xB0, 0xEA, 0xE0, 0xA0, 0x80, 0x60, 0x20, 0x16, 0x50, 0x16, 0x20, 0x60, 0x80,
        0xF0, 0xD0, 0xB0, 0x90, 0x70, 0x50, 0x30, 0x10, 0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0,
        0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,
        0xF0, 0xCB, 0xA6, 0x80, 0x5C, 0x39, 0x20, 0x12, 0x12, 0x20, 0x39, 0x5C, 0x80, 0xA6, 0xCB, 0xF0,
        0xC0, 0xA6, 0x8A, 0x6A, 0x4A, 0x2F, 0x14, 0x24, 0x20, 0x39, 0x59, 0x75, 0x72, 0x90, 0xB0, 0xD0,
        0x80, 0x57, 0x48, 0x57, 0x80, 0xA9, 0xBA, 0xA9, 0x80, 0x57, 0x48, 0x57, 0x80, 0xA9, 0xBA, 0xA9,
        0xE4, 0xE8, 0xB7, 0x80, 0xB7, 0xE8, 0xE4, 0xB2, 0x7A, 0x47, 0x20, 0x10, 0x20, 0x47, 0x7A, 0xB2,
        0x90, 0x70, 0x70, 0x50, 0x50, 0x30, 0x30, 0x10, 0x10, 0x30, 0x30, 0x50, 0x50, 0x70, 0x70, 0x90,
        0xE6, 0xD0, 0xE6, 0xB9, 0xAE, 0x80, 0x52, 0x47, 0x14, 0x30, 0x14, 0x47, 0x52, 0x80, 0xAE, 0xB9,
        0x7E, 0x6A, 0x51, 0x3A, 0x2C, 0x2C, 0x38, 0x4E, 0x4E, 0x38, 0x2C, 0x2C, 0x3A, 0x51, 0x6A, 0x7E,
    ]

    private static func normalize(vertices: [CGPoint]) -> [CGPoint] {
        guard let first = vertices.first else { return vertices }
        let bounds = vertices.reduce(
            (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { partial, point in
            (
                minX: min(partial.minX, point.x),
                maxX: max(partial.maxX, point.x),
                minY: min(partial.minY, point.y),
                maxY: max(partial.maxY, point.y)
            )
        }
        let midX = (bounds.minX + bounds.maxX) * 0.5
        let midY = (bounds.minY + bounds.maxY) * 0.5
        let width = max(bounds.maxX - bounds.minX, 0.001)
        let height = max(bounds.maxY - bounds.minY, 0.001)
        let divisor = max(width, height) * 0.55
        return vertices.map {
            CGPoint(x: ($0.x - midX) / divisor, y: ($0.y - midY) / divisor)
        }
    }
}
