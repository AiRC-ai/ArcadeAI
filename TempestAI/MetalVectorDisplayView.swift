import MetalKit
import simd
import SwiftUI

struct MetalVectorDisplayView: NSViewRepresentable {
    let frame: GameFrameData

    func makeCoordinator() -> MetalVectorRenderer {
        MetalVectorRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(frame: frame, drawableSize: nsView.drawableSize)
        nsView.draw()
    }
}

private struct MetalVectorLineRecord {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var color: SIMD4<Float>
    var width: Float
    var dotRadius: Float
    var isDot: Float
    var _padding: Float = 0
}

private struct MetalVectorUniforms {
    var drawableSize: SIMD2<Float>
}

private struct MetalVectorLineKey: Hashable {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int
    var argb: UInt32
    var intensity: Int

    init(_ line: GameVectorLineData) {
        x0 = Int((line.x0 * 16.0).rounded())
        y0 = Int((line.y0 * 16.0).rounded())
        x1 = Int((line.x1 * 16.0).rounded())
        y1 = Int((line.y1 * 16.0).rounded())
        argb = line.argb
        intensity = line.intensity
    }
}

final class MetalVectorRenderer: NSObject, MTKViewDelegate {
    private static let envLineWidth = "TEMPEST_VECTOR_LINE_WIDTH"
    private static let envDotRadius = "TEMPEST_VECTOR_DOT_RADIUS"

    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private var lineBuffer: MTLBuffer?
    private var lineBufferCapacity = 0
    private var lineCount = 0

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.pipelineState = device.flatMap { Self.makePipeline(device: $0) }
        super.init()
    }

    func update(frame: GameFrameData, drawableSize: CGSize) {
        guard let device else {
            lineCount = 0
            return
        }

        let records = Self.lineRecords(
            for: frame,
            drawableSize: drawableSize
        )
        let requiredBytes = records.count * MemoryLayout<MetalVectorLineRecord>.stride
        guard requiredBytes > 0 else {
            lineCount = 0
            return
        }

        if lineBuffer == nil || lineBufferCapacity < requiredBytes {
            lineBufferCapacity = max(requiredBytes, max(4096, lineBufferCapacity * 2))
            lineBuffer = device.makeBuffer(
                length: lineBufferCapacity,
                options: .storageModeShared
            )
        }

        guard let lineBuffer else {
            lineCount = 0
            return
        }

        records.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                lineBuffer.contents().copyMemory(
                    from: baseAddress,
                    byteCount: requiredBytes
                )
            }
        }
        lineCount = records.count
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let commandQueue,
            let pipelineState,
            let lineBuffer,
            lineCount > 0,
            let pass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: pass)
        var uniforms = MetalVectorUniforms(
            drawableSize: SIMD2<Float>(
                Float(max(1, view.drawableSize.width)),
                Float(max(1, view.drawableSize.height))
            )
        )
        encoder?.setRenderPipelineState(pipelineState)
        encoder?.setVertexBuffer(lineBuffer, offset: 0, index: 0)
        encoder?.setVertexBytes(
            &uniforms,
            length: MemoryLayout<MetalVectorUniforms>.stride,
            index: 1
        )
        encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)
        encoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float2 start;
            float2 end;
            float4 color;
            float width;
            float dotRadius;
            float isDot;
            float padding;
        };

        struct Uniforms {
            float2 drawableSize;
        };

        struct VertexOut {
            float4 position [[position]];
            float4 color;
            float2 pixelPosition;
            float2 start;
            float2 end;
            float width;
            float dotRadius;
            float isDot;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                     const device VertexIn *lines [[buffer(0)]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
            constexpr float2 corners[6] = {
                float2(-1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0, -1.0),
                float2( 1.0, -1.0),
                float2(-1.0,  1.0),
                float2( 1.0,  1.0)
            };
            uint lineIndex = vertexID / 6;
            uint cornerIndex = vertexID % 6;
            VertexIn input = lines[lineIndex];
            float2 corner = corners[cornerIndex];
            float2 delta = input.end - input.start;
            float len = max(length(delta), 0.0001);
            float2 dir = delta / len;
            float2 normal = float2(-dir.y, dir.x);
            float2 center = mix(input.start, input.end, (corner.x + 1.0) * 0.5);
            float halfExtent = (input.width * 0.5) + 0.65;
            float2 position = center + normal * corner.y * halfExtent;
            if (input.isDot > 0.5) {
                position = input.start + corner * (input.dotRadius + 0.65);
            }
            float2 ndc = float2(
                (position.x / uniforms.drawableSize.x) * 2.0 - 1.0,
                1.0 - (position.y / uniforms.drawableSize.y) * 2.0
            );
            VertexOut output;
            output.position = float4(ndc, 0.0, 1.0);
            output.color = input.color;
            output.pixelPosition = position;
            output.start = input.start;
            output.end = input.end;
            output.width = input.width;
            output.dotRadius = input.dotRadius;
            output.isDot = input.isDot;
            return output;
        }

        fragment float4 fragment_main(VertexOut input [[stage_in]]) {
            float alpha = 1.0;
            if (input.isDot > 0.5) {
                float distance = length(input.pixelPosition - input.start);
                alpha = 1.0 - smoothstep(input.dotRadius, input.dotRadius + 0.65, distance);
            } else {
                float2 segment = input.end - input.start;
                float denom = max(dot(segment, segment), 0.0001);
                float t = clamp(dot(input.pixelPosition - input.start, segment) / denom, 0.0, 1.0);
                float2 nearest = input.start + segment * t;
                float distance = length(input.pixelPosition - nearest);
                float halfWidth = max(input.width * 0.5, 0.25);
                alpha = 1.0 - smoothstep(halfWidth, halfWidth + 0.65, distance);
            }
            return float4(input.color.rgb, input.color.a * alpha);
        }
        """
        guard
            let library = try? device.makeLibrary(source: source, options: nil),
            let vertex = library.makeFunction(name: "vertex_main"),
            let fragment = library.makeFunction(name: "fragment_main")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func lineRecords(
        for frame: GameFrameData,
        drawableSize: CGSize
    ) -> [MetalVectorLineRecord] {
        guard drawableSize.width > 1, drawableSize.height > 1 else { return [] }
        let viewport = MetalVectorViewport(
            rawWidth: max(1.0, frame.vectorWidth),
            rawHeight: max(1.0, frame.vectorHeight),
            targetSize: drawableSize,
            lines: frame.vectorLines,
            renderer: frame.renderer
        )
        var records: [MetalVectorLineRecord] = []
        records.reserveCapacity(frame.vectorLines.count)

        let baseWidth = vectorLineWidth(drawableSize: drawableSize)
        let dotRadius = vectorDotRadius(lineWidth: baseWidth)
        var seenLines = Set<MetalVectorLineKey>()
        for line in frame.vectorLines {
            let lineKey = MetalVectorLineKey(line)
            guard seenLines.insert(lineKey).inserted else {
                continue
            }
            let start = viewport.point(x: line.x0, y: line.y0)
            let end = viewport.point(x: line.x1, y: line.y1)
            let color = vectorColor(argb: line.argb, intensity: line.intensity)
            let length = hypot(end.x - start.x, end.y - start.y)
            records.append(.init(
                start: SIMD2<Float>(Float(start.x), Float(start.y)),
                end: SIMD2<Float>(Float(end.x), Float(end.y)),
                color: color,
                width: Float(baseWidth),
                dotRadius: Float(dotRadius),
                isDot: length < 0.75 ? 1 : 0
            ))
        }
        return records
    }

    private static func vectorLineWidth(drawableSize: CGSize) -> CGFloat {
        let fallback = max(
            0.45,
            min(0.78, min(drawableSize.width, drawableSize.height) * 0.00055)
        )
        return envPositiveCGFloat(envLineWidth, defaultValue: fallback)
    }

    private static func vectorDotRadius(lineWidth: CGFloat) -> CGFloat {
        let fallback = max(0.55, lineWidth * 0.95)
        return envPositiveCGFloat(envDotRadius, defaultValue: fallback)
    }

    private static func envPositiveCGFloat(
        _ key: String,
        defaultValue: CGFloat
    ) -> CGFloat {
        guard
            let raw = ProcessInfo.processInfo.environment[key],
            let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            value.isFinite,
            value > 0
        else {
            return defaultValue
        }
        return CGFloat(value)
    }

    private static func vectorColor(argb: UInt32, intensity: Int) -> SIMD4<Float> {
        let a = Float((argb >> 24) & 0xff) / 255.0
        let r = Float((argb >> 16) & 0xff) / 255.0
        let g = Float((argb >> 8) & 0xff) / 255.0
        let b = Float(argb & 0xff) / 255.0
        let normalized = max(0.0, min(1.0, Float(intensity) / 255.0))
        let beam = min(1.0, max(0.88, pow(normalized, 0.38) * 2.8))
        let alpha = min(1.0, a * max(0.92, pow(normalized, 0.42) * 2.4))
        return SIMD4<Float>(r * beam, g * beam, b * beam, alpha)
    }
}

private struct MetalVectorViewport {
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

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, Double(point.x))
            minY = min(minY, Double(point.y))
            maxX = max(maxX, Double(point.x))
            maxY = max(maxY, Double(point.y))
        }

        if let swiftAVGConfig {
            include(Self.displayPoint(x: swiftAVGConfig.minX, y: swiftAVGConfig.minY, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: swiftAVGConfig.maxX, y: swiftAVGConfig.minY, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: swiftAVGConfig.minX, y: swiftAVGConfig.maxY, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: swiftAVGConfig.maxX, y: swiftAVGConfig.maxY, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
        } else if renderer == "mame_vector" {
            include(Self.displayPoint(x: 0, y: 0, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: viewportWidth, y: 0, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: 0, y: viewportHeight, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
            include(Self.displayPoint(x: viewportWidth, y: viewportHeight, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
        } else {
            for line in lines {
                include(Self.displayPoint(x: line.x0, y: line.y0, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
                include(Self.displayPoint(x: line.x1, y: line.y1, rawWidth: viewportWidth, rawHeight: viewportHeight, renderer: renderer))
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
        self.scale = min(Double(targetSize.width) / displayWidth, Double(targetSize.height) / displayHeight)
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
