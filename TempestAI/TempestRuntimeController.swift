import Combine
import Foundation
import os

/// App-wide controller for the self-contained Swift/Metal Tempest runtime.
///
/// Normal gameplay is fully in-process: original ROM execution, AI policy,
/// learning state, and vector frames are produced by Swift code.
final class TempestRuntimeController: ObservableObject {
    static let shared = TempestRuntimeController()

    @Published var metrics = MetricsData()
    @Published var status = "Starting Swift runtime…"
    @Published var isRunning = false
    @Published var isGameRunning = false
    @Published var isRuntimeReady = false
    @Published var gameFrame: GameFrameData?
    @Published var gameFramesByClientID: [Int: GameFrameData] = [:]
    @Published var logLines: [String] = []

    private var frameTimestampsByClientID: [Int: Date] = [:]
    private let staleFrameTimeout: TimeInterval = 3.0
    private let logger = Logger(subsystem: "com.tempest.ai", category: "runtime")
    private let swiftRuntime = SwiftTempestRuntime.shared
    private var swiftRuntimeCancellable: AnyCancellable?
    private var didLogSwiftAVGViewport = false

    private init() {}

    func start() {
        guard !isRunning else {
            log("Swift runtime already ready")
            return
        }

        log("Starting self-contained Swift/Metal runtime")
        swiftRuntime.prepare()
        swiftRuntime.prepareLearnerState()
        let learnerLoadStatus = swiftRuntime.status
        guard swiftRuntime.isAvailable else {
            status = swiftRuntime.status
            isRunning = false
            isRuntimeReady = false
            log("ERROR: \(swiftRuntime.status)")
            return
        }

        swiftRuntimeCancellable = swiftRuntime.$framesByClientID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frames in
                self?.applySwiftRuntimeFrames(frames)
            }

        isRunning = true
        isRuntimeReady = true
        isGameRunning = false
        status = "Swift runtime ready"
        configureSwiftRuntimeMetrics()
        log(learnerLoadStatus)
        log("Original Tempest ROM verified")
        log("Renderer: Swift AVG vectors")
        log("AI: Swift in-process policy/learner")
    }

    func stop() {
        stopSwiftRuntime()
    }

    func terminateForAppExit() {
        stopSwiftRuntime()
    }

    func sendCommand(
        _ cmd: String,
        params: [String: Any] = [:],
        completion: ((Error?) -> Void)? = nil
    ) {
        log("→ \(cmd)")
        handleSwiftRuntimeCommand(cmd, params: params)
        completion?(nil)
    }

    func removeGame(clientID: Int) {
        sendCommand("remove_instance", params: ["client_id": clientID])
        removeFrame(clientID: clientID)
    }

    private func handleSwiftRuntimeCommand(_ cmd: String, params: [String: Any]) {
        switch cmd {
        case "start_training":
            swiftRuntime.start()
            isGameRunning = true
            status = "Swift emulator running"
            log("← status: Swift emulator running")
        case "add_instance":
            swiftRuntime.addInstance()
            log("← status: Swift game added")
        case "remove_instance":
            if let clientID = params["client_id"] as? Int {
                swiftRuntime.removeInstance(clientID: clientID)
            } else {
                swiftRuntime.removeLastInstance()
            }
            log("← status: Swift game removed")
        case "stop_training":
            swiftRuntime.stop()
            clearSwiftRuntimeFrames(status: "Swift emulator stopped")
            log("← status: Swift emulator stopped")
        case "shutdown":
            stopSwiftRuntime()
        case "save_model":
            swiftRuntime.savePersistentState()
            status = "Saved Swift learner and high-score state"
            log("← status: saved Swift learner/high-score state")
        case "load_old_model":
            swiftRuntime.loadBundledLearnerSeed(wait: true)
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
            status = "Loaded bundled Swift learner seed"
            log("← status: loaded bundled Swift learner seed")
        case "set_epsilon":
            if let value = params["value"] as? Double {
                swiftRuntime.setEpsilon(value)
            }
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
        case "set_expert_ratio":
            if let value = params["value"] as? Double {
                swiftRuntime.setExpertRatio(value)
            }
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
        case "set_training":
            if let enabled = params["enabled"] as? Bool {
                swiftRuntime.setTraining(enabled)
            }
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
        case "reset_epsilon":
            swiftRuntime.resetExploration()
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
        case "reset_expert":
            swiftRuntime.resetExpert()
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
        case "best_ai_mode":
            swiftRuntime.setBestAIMode()
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
            status = "Best AI mode"
            log("← status: Best AI mode")
        case "train_mode":
            swiftRuntime.setLearningMode()
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
            status = "Learning mode"
            log("← status: Learning mode")
        case "flush_buffer":
            swiftRuntime.clearReplay()
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
            log("← status: examples cleared")
        case "epsilon_pulse":
            swiftRuntime.setEpsilon(0.25)
            configureSwiftRuntimeMetrics(with: Array(gameFramesByClientID.values))
            log("← status: random-practice burst enabled")
        default:
            log("← status: Swift command \(cmd) is not implemented")
        }
    }

    private func stopSwiftRuntime() {
        swiftRuntime.stop(wait: true)
        swiftRuntimeCancellable = nil
        isRunning = false
        isRuntimeReady = false
        clearSwiftRuntimeFrames(status: "Swift runtime stopped")
        log("Swift runtime stopped")
    }

    private func applySwiftRuntimeFrames(_ frames: [Int: GameFrameData]) {
        logSwiftAVGViewportIfNeeded(frames: frames)
        gameFramesByClientID = frames
        gameFrame = frames.values.sorted { $0.clientID < $1.clientID }.first
        let now = Date()
        let activeIDs = Set(frames.keys)
        for id in activeIDs {
            frameTimestampsByClientID[id] = now
        }
        for id in Array(frameTimestampsByClientID.keys) where !activeIDs.contains(id) {
            frameTimestampsByClientID.removeValue(forKey: id)
        }
        isGameRunning = !frames.isEmpty && swiftRuntime.isRunning
        status = userFacingStatus(for: swiftRuntime.status, frames: frames)
        configureSwiftRuntimeMetrics(with: Array(frames.values))
    }

    private func userFacingStatus(for runtimeStatus: String, frames: [Int: GameFrameData]) -> String {
        if runtimeStatus.hasPrefix("loaded saved Swift learner state")
            || runtimeStatus.hasPrefix("loaded bundled Swift learner seed")
            || runtimeStatus.hasPrefix("using default Swift learner state") {
            return frames.isEmpty ? "Swift runtime ready" : "Swift emulator running"
        }
        return runtimeStatus
    }

    private func logSwiftAVGViewportIfNeeded(frames: [Int: GameFrameData]) {
        guard !didLogSwiftAVGViewport else { return }
        guard let frame = frames.values
            .sorted(by: { $0.clientID < $1.clientID })
            .first(where: {
                $0.renderer == "swift_avg_vector" && !$0.vectorLines.isEmpty
            }) else {
            return
        }

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for line in frame.vectorLines {
            minX = min(minX, line.x0, line.x1)
            minY = min(minY, line.y0, line.y1)
            maxX = max(maxX, line.x0, line.x1)
            maxY = max(maxY, line.y0, line.y1)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return
        }

        let viewport = TempestVectorViewportConfig.swiftAVG()
        didLogSwiftAVGViewport = true
        log(String(
            format: "Swift AVG bounds x=%.1f..%.1f y=%.1f..%.1f viewport center=%.1f,%.1f size=%.1fx%.1f",
            minX,
            maxX,
            minY,
            maxY,
            viewport.centerX,
            viewport.centerY,
            viewport.width,
            viewport.height
        ))
    }

    private func configureSwiftRuntimeMetrics(with frames: [GameFrameData] = []) {
        let learner = swiftRuntime.learnerSnapshot()
        let runtimePerformance = swiftRuntime.performanceSnapshot()
        metrics.authenticGameplay = true
        metrics.originalGameStatus = "Original Tempest ROM verified"
        metrics.originalGameDetail = "Swift runtime executes bundled tempest1 ROM bytes"
        metrics.romName = "tempest1"
        metrics.runtimePid = 0
        metrics.runtimeHeadless = true
        metrics.debugWindow = false
        metrics.scoreSource = "Original ROM RAM"
        metrics.highScoreSource = "Original EAROM/RAM"
        metrics.rendererRole = "Swift AVG vectors"
        metrics.aiRuntimeStatus = learner.neuralRuntimeStatus
        metrics.gameCount = frames.count
        metrics.epsilon = learner.epsilon
        metrics.expertRatio = learner.expertRatio
        metrics.trainingEnabled = learner.trainingEnabled
        metrics.memoryBufferSize = learner.replayCount
        metrics.totalTrainingSteps = learner.trainingSteps
        metrics.mlxOptimizerSteps = learner.optimizerStep
        metrics.loss = learner.loss
        metrics.gradNorm = learner.gradNorm
        metrics.qMean = learner.qMean
        metrics.agreement = learner.agreement
        metrics.episodes = learner.episodes
        metrics.averageLevel = learner.averageLevel
        metrics.fps = runtimePerformance.simFramesPerSecond > 0
            ? runtimePerformance.simFramesPerSecond
            : (frames.compactMap(\.fps).max() ?? 0)
        metrics.simFramesPerSecond = runtimePerformance.simFramesPerSecond
        metrics.runtimeTickMS = runtimePerformance.runtimeTickMS
        metrics.emulatorStepMS = runtimePerformance.emulatorStepMS
        metrics.inferenceMS = runtimePerformance.inferenceMS
        metrics.replaySampleMS = learner.replaySampleMS
        metrics.trainingBatchMS = learner.trainingBatchMS
        metrics.optimizerMS = learner.optimizerMS
        metrics.learnerUpdatesPerSecond = learner.learnerUpdatesPerSecond
        metrics.renderPublishFPS = runtimePerformance.renderPublishFPS
        metrics.droppedFrames = runtimePerformance.droppedFrames
        metrics.trainingInFlight = learner.trainingInFlight
        if let maxFrame = frames.map(\.frame).max() {
            metrics.frameCount = max(metrics.frameCount, maxFrame)
        }
        let scoringFrames = frames.filter { $0.score > 0 && !$0.gameOver }
        if let maxScore = scoringFrames.map(\.score).max() {
            metrics.peakGameScore = max(metrics.peakGameScore, maxScore)
        }
        if let maxLevel = scoringFrames.map(\.displayLevel).max() {
            metrics.peakLevel = max(metrics.peakLevel, maxLevel)
        }
        if let maxHighScore = frames.map(\.highScore).max() {
            metrics.romHighScore = max(metrics.romHighScore, maxHighScore)
        }
    }

    private func clearSwiftRuntimeFrames(status newStatus: String) {
        gameFrame = nil
        gameFramesByClientID.removeAll()
        frameTimestampsByClientID.removeAll()
        isGameRunning = false
        metrics.gameCount = 0
        status = newStatus
    }

    private func log(_ msg: String) {
        logger.info("\(msg)")
        appendDebugLog(msg)
        DispatchQueue.main.async {
            self.logLines.append(msg)
            if self.logLines.count > 200 {
                self.logLines.removeFirst(50)
            }
        }
    }

    private func appendDebugLog(_ msg: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/tempest_ai_app.log")
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // os.Logger and the in-app log are still available.
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    func receivedAt(for clientID: Int) -> Date? {
        frameTimestampsByClientID[clientID]
    }

    func pruneStaleFrames(now: Date = Date()) {
        guard !frameTimestampsByClientID.isEmpty else { return }
        let staleIDs = frameTimestampsByClientID.compactMap { clientID, date in
            now.timeIntervalSince(date) > staleFrameTimeout ? clientID : nil
        }
        guard !staleIDs.isEmpty else { return }
        for clientID in staleIDs {
            frameTimestampsByClientID.removeValue(forKey: clientID)
            gameFramesByClientID.removeValue(forKey: clientID)
        }
        if gameFramesByClientID.isEmpty {
            gameFrame = nil
        }
    }

    private func removeFrame(clientID: Int) {
        frameTimestampsByClientID.removeValue(forKey: clientID)
        gameFramesByClientID.removeValue(forKey: clientID)
        gameFrame = gameFramesByClientID.values.sorted { $0.clientID < $1.clientID }.first
        metrics.gameCount = gameFramesByClientID.count
        if gameFramesByClientID.isEmpty {
            isGameRunning = false
        }
    }
}
