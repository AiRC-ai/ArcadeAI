import Foundation

struct SwiftRuntimePerformanceSnapshot {
    var simFramesPerSecond: Double = 0
    var runtimeTickMS: Double = 0
    var emulatorStepMS: Double = 0
    var inferenceMS: Double = 0
    var droppedFrames: Int = 0
    var renderPublishFPS: Double = 0
}

final class TempestMachine {
    let clientID: Int
    private let romSet: TempestROMSet
    private let bus: TempestMemoryBus
    private let cpu: MOS6502
    private let avg: TempestAVG
    private let mathbox: TempestMathbox
    private var frameNumber = 0
    private var haltedReason: String?
    private var nextIRQCycle: UInt64 = 0
    private let irqPeriodCycles: UInt64 = 6_144

    init(clientID: Int, romSet: TempestROMSet) {
        self.clientID = clientID
        self.romSet = romSet
        self.bus = TempestMemoryBus(romSet: romSet)
        self.cpu = MOS6502(bus: bus)
        self.avg = TempestAVG(romSet: romSet)
        self.mathbox = TempestMathbox(promData: romSet.mathPROMs)
        self.cpu.reset()
        self.nextIRQCycle = self.cpu.cycles + irqPeriodCycles
    }

    func setInput(_ input: TempestInputState) {
        bus.applyInput(input)
    }

    func agentFramePacket(
        encoder: inout TempestAgentFrameEncoder,
        commanded: TempestAgentAction
    ) -> Data {
        encoder.encode(
            ram: bus.ram,
            frameNumber: frameNumber,
            commanded: commanded
        )
    }

    func policyFrame() -> TempestPolicyFrame {
        var enemies: [TempestPolicyFrame.Threat] = []
        var shots: [TempestPolicyFrame.Threat] = []
        let playerLane = Int(bus.ram[0x0200] & 0x0f)
        let spikeDepths = (0..<16).map { Int(bus.ram[0x03ac + $0]) }
        for i in 0..<7 {
            let depth = Int(bus.ram[0x02df + i])
            guard depth > 0 else { continue }
            let type = Int(bus.ram[0x0283 + i])
            let state = Int(bus.ram[0x028a + i])
            enemies.append(.init(
                lane: Int(bus.ram[0x02b9 + i] & 0x0f),
                depth: depth,
                type: type & 0x07,
                canShoot: (state & 0x40) != 0
            ))
        }
        for i in 0..<4 {
            let depth = Int(bus.ram[0x02db + i])
            guard depth > 0 else { continue }
            shots.append(.init(
                lane: Int(bus.ram[0x02b5 + i] & 0x0f),
                depth: depth,
                type: 0,
                canShoot: true
            ))
        }
        return TempestPolicyFrame(
            sourceGameID: clientID,
            frame: frameNumber,
            gamestate: Int(bus.ram[0x00]),
            playerLane: playerLane,
            lives: Int(bus.ram[0x48]),
            score: bus.scoreBCD(),
            openLevel: bus.ram[0x0111] != 0,
            spikeDepths: spikeDepths,
            pulsing: Int(Int8(bitPattern: bus.ram[0x0147])),
            shotCount: Int(bus.ram[0x0135]),
            superzapperUses: Int(bus.ram[0x03aa]),
            enemiesPending: Int(bus.ram[0x03ab]),
            enemies: enemies,
            enemyShots: shots
        )
    }

    func automationGamestate() -> Int {
        Int(bus.ram[0x00])
    }

    func stateVector(encoder: inout TempestAgentFrameEncoder) -> [Float] {
        encoder.stateVector(ram: bus.ram)
    }

    func debugSummary() -> String {
        let vectorBytes = bus.vectorRAM.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        let prefix = bus.vectorRAM.prefix(16).map { String(format: "%02X", $0) }.joined(separator: "")
        let nonzero = bus.vectorRAM.enumerated()
            .filter { $0.element != 0 }
            .prefix(8)
            .map { String(format: "%03X:%02X", $0.offset, $0.element) }
            .joined(separator: ",")
        return String(
            format: "pc=%04X cycles=%llu score=%d levelRaw=%d lives=%d vectorBytes=%d v0=%@ nz=%@",
            cpu.programCounter,
            cpu.cycles,
            bus.scoreBCD(),
            currentGeometryLevelIndex(),
            bus.ram[0x48],
            vectorBytes,
            prefix,
            nonzero
        )
    }

    func highScore() -> Int {
        bus.highScoreBCD()
    }

    func currentSnapshot() -> TempestSnapshot {
        snapshot(status: haltedReason ?? "running", includeVectors: true)
    }

    func earomSnapshot() -> [UInt8] {
        bus.earomSnapshot()
    }

    var hasUnsavedEAROM: Bool {
        bus.earomDirty
    }

    func markEAROMSaved() {
        bus.markEAROMSaved()
    }

    func runFrame(includeVectors: Bool = true) -> TempestSnapshot {
        guard haltedReason == nil else {
            return snapshot(
                status: haltedReason ?? "halted",
                includeVectors: includeVectors
            )
        }

        let targetCycles = 1_512_000 / 60
        var executed = 0
        do {
            while executed < targetCycles {
                if cpu.cycles >= nextIRQCycle {
                    executed += cpu.irq()
                    nextIRQCycle += irqPeriodCycles
                }
                executed += try cpu.step()
            }
        } catch {
            haltedReason = error.localizedDescription
        }
        frameNumber += 1
        return snapshot(
            status: haltedReason ?? "running",
            includeVectors: includeVectors
        )
    }

    private func snapshot(status: String, includeVectors: Bool) -> TempestSnapshot {
        let lines = includeVectors
            ? avg.renderVectorFrame(vectorRAM: bus.displayVectorRAM, colorRAM: bus.colorRAM)
            : []
        _ = mathbox
        let playerLevelIndex = currentPlayerLevelIndex()
        let geometryLevelIndex = currentGeometryLevelIndex()
        return TempestSnapshot(
            clientID: clientID,
            frame: frameNumber,
            score: bus.scoreBCD(),
            highScore: bus.highScoreBCD(),
            highScoreInitials: bus.highScoreInitials(),
            displayLevel: playerLevelIndex + 1,
            romLevelIndex: playerLevelIndex,
            geometryLevelIndex: geometryLevelIndex,
            gamestate: Int(bus.ram[0x00]),
            lives: Int(bus.ram[0x48]),
            vectorWidth: 581,
            vectorHeight: 571,
            vectorLines: lines,
            runtimeStatus: status
        )
    }

    private func currentPlayerLevelIndex() -> Int {
        min(98, max(0, Int(bus.ram[0x0046])))
    }

    private func currentGeometryLevelIndex() -> Int {
        min(98, max(0, Int(bus.ram[0x009f])))
    }
}

final class SwiftTempestRuntime: ObservableObject {
    static let shared = SwiftTempestRuntime()

    @Published private(set) var isAvailable = false
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Swift emulator not loaded"
    @Published private(set) var framesByClientID: [Int: GameFrameData] = [:]

    private var romSet: TempestROMSet?
    private var instances: [SwiftTempestInstance] = []
    private var timer: DispatchSourceTimer?
    private var nextClientID = 0
    private var runtimeActive = false
    private var tickCounter = 0
    private var lastEAROMAutosave = Date.distantPast
    private var lastFramePublish = Date.distantPast
    private var lastPerformanceSample = Date()
    private var simFramesSincePerformanceSample = 0
    private var publishFramesSincePerformanceSample = 0
    private var performance = SwiftRuntimePerformanceSnapshot()
    private let learner = SwiftTempestLearner()
    private let maxSpeedTraining = ProcessInfo.processInfo
        .environment["TEMPEST_MAX_SPEED_TRAINING"] != "0"
    private let renderPublishInterval = max(
        1.0 / 120.0,
        min(
            1.0,
            Double(ProcessInfo.processInfo.environment["TEMPEST_RENDER_PUBLISH_INTERVAL"] ?? "0.033") ?? 0.033
        )
    )
    private let simulationFramesPerTick = max(
        1,
        min(
            64,
            Int(
                ProcessInfo.processInfo.environment["TEMPEST_SIM_FRAMES_PER_TICK"] ??
                    (ProcessInfo.processInfo.environment["TEMPEST_MAX_SPEED_TRAINING"] == "0" ? "2" : "8")
            ) ?? 8
        )
    )
    private let runtimeQueue = DispatchQueue(
        label: "tempest.swift-emulator.runtime",
        qos: .userInitiated
    )
    private let runtimeQueueKey = DispatchSpecificKey<Bool>()

    private init() {
        runtimeQueue.setSpecific(key: runtimeQueueKey, value: true)
    }

    func prepare() {
        do {
            romSet = try TempestROMSet.load()
            isAvailable = true
            status = "Swift emulator ROM set verified"
        } catch {
            isAvailable = false
            status = error.localizedDescription
        }
    }

    func prepareLearnerState() {
        runtimeQueue.sync {
            status = learner.loadPersistentState()
        }
    }

    func start() {
        if romSet == nil {
            prepare()
        }
        guard let romSet else {
            status = "Swift emulator unavailable: \(status)"
            return
        }
        runtimeQueue.async { [weak self] in
            self?.startOnRuntimeQueue(romSet: romSet)
        }
    }

    func addInstance() {
        runtimeQueue.async { [weak self] in
            guard let self, self.runtimeActive, let romSet = self.romSet else { return }
            self.instances.append(SwiftTempestInstance(
                machine: TempestMachine(clientID: self.nextClientID, romSet: romSet)
            ))
            self.nextClientID += 1
            self.publish(status: "Swift emulator running")
        }
    }

    func removeLastInstance() {
        runtimeQueue.async { [weak self] in
            guard let self, self.runtimeActive, self.instances.count > 1 else { return }
            self.instances.removeLast()
            self.publishRemainingInstances()
        }
    }

    func removeInstance(clientID: Int) {
        runtimeQueue.async { [weak self] in
            guard let self, self.runtimeActive, self.instances.count > 1 else { return }
            guard let index = self.instances.firstIndex(where: {
                $0.machine.clientID == clientID
            }) else { return }
            self.instances.remove(at: index)
            self.publishRemainingInstances()
        }
    }

    func stop(wait: Bool = false) {
        let work = { [weak self] in
            self?.stopOnRuntimeQueue()
        }
        if DispatchQueue.getSpecific(key: runtimeQueueKey) == true {
            work()
        } else if wait {
            runtimeQueue.sync(execute: work)
        } else {
            runtimeQueue.async {
                work()
            }
        }
    }

    func savePersistentState(wait: Bool = false) {
        let work = { [weak self] in
            self?.saveEAROMIfNeeded(force: true)
        }
        if DispatchQueue.getSpecific(key: runtimeQueueKey) == true {
            work()
        } else if wait {
            runtimeQueue.sync(execute: work)
        } else {
            runtimeQueue.async {
                work()
            }
        }
    }

    private func startOnRuntimeQueue(romSet: TempestROMSet) {
        stopOnRuntimeQueue(publishStopped: false)
        instances.removeAll()
        nextClientID = 0
        tickCounter = 0
        status = learner.loadPersistentState()
        instances.append(SwiftTempestInstance(
            machine: TempestMachine(clientID: nextClientID, romSet: romSet)
        ))
        nextClientID += 1
        runtimeActive = true
        learner.resetForRun()
        lastEAROMAutosave = Date()
        lastFramePublish = Date.distantPast
        lastPerformanceSample = Date()
        simFramesSincePerformanceSample = 0
        publishFramesSincePerformanceSample = 0
        performance = SwiftRuntimePerformanceSnapshot()
        publish(isRunning: true, status: "Swift emulator running", frames: [:])
        startTimerOnRuntimeQueue()
    }

    private func stopOnRuntimeQueue(publishStopped: Bool = true) {
        timer?.cancel()
        timer = nil
        saveEAROMIfNeeded(force: true)
        _ = learner.savePersistentState()
        instances.removeAll()
        runtimeActive = false
        if publishStopped {
            publish(isRunning: false, status: "Swift emulator stopped", frames: [:])
        }
    }

    private func startTimerOnRuntimeQueue() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: runtimeQueue)
        let interval: DispatchTimeInterval = maxSpeedTraining
            ? .milliseconds(1)
            : .milliseconds(16)
        timer.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: maxSpeedTraining ? .milliseconds(1) : .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.tickOnRuntimeQueue()
        }
        timer.resume()
        self.timer = timer
    }

    private func tickOnRuntimeQueue() {
        guard runtimeActive else { return }
        let tickStart = Date()
        var updatedFrames: [Int: GameFrameData] = [:]
        var haltStatus: String?
        var policyRequests: [SwiftTempestPolicyRequest] = []
        tickCounter &+= 1
        let now = Date()
        let shouldPublishFrames = now.timeIntervalSince(lastFramePublish) >= renderPublishInterval
        let emulationStart = Date()
        for index in instances.indices {
            for simStep in 0..<simulationFramesPerTick {
                let input = Self.input(
                    frame: instances[index].age,
                    gamestate: instances[index].machine.automationGamestate(),
                    action: instances[index].lastAction
                )
                instances[index].machine.setInput(input)
                let isLastSimulationStep = simStep == simulationFramesPerTick - 1
                let includeVectors = shouldPublishFrames && isLastSimulationStep
                let snapshot = instances[index].machine.runFrame(
                    includeVectors: includeVectors
                )
                instances[index].age += 1
                simFramesSincePerformanceSample += 1
                if includeVectors {
                    updatedFrames[snapshot.clientID] = snapshot.gameFrameData(fps: gameFPS())
                }
                learner.recordLevel(snapshot.displayLevel)
                if snapshot.runtimeStatus != "running" {
                    haltStatus = "Swift emulator halted: \(snapshot.runtimeStatus)"
                    if !includeVectors {
                        updatedFrames[snapshot.clientID] = instances[index]
                            .machine
                            .currentSnapshot()
                            .gameFrameData(fps: gameFPS())
                    }
                    break
                }
                if isLastSimulationStep {
                    let policyFrame = instances[index].machine.policyFrame()
                    let stateVector = instances[index].machine.stateVector(
                        encoder: &instances[index].encoder
                    )
                    if let previousState = instances[index].previousStateVector {
                        learner.observeTransition(
                            sourceGameID: instances[index].machine.clientID,
                            frame: snapshot.frame,
                            state: previousState,
                            action: instances[index].previousAction,
                            reward: Self.reward(
                                previousScore: instances[index].previousScore,
                                previousLives: instances[index].previousLives,
                                previousLevel: instances[index].previousLevel,
                                snapshot: snapshot,
                                policyFrame: policyFrame
                            ),
                            nextState: stateVector,
                            done: Self.isTerminal(snapshot)
                        )
                    }
                    policyRequests.append(SwiftTempestPolicyRequest(
                        instanceIndex: index,
                        frame: policyFrame,
                        stateVector: stateVector,
                        snapshot: snapshot
                    ))
                }
            }
        }
        performance.emulatorStepMS = smoothPerformanceMetric(
            performance.emulatorStepMS,
            Date().timeIntervalSince(emulationStart) * 1_000
        )
        if !policyRequests.isEmpty {
            let inferenceStart = Date()
            let actions = learner.actions(
                for: policyRequests.map {
                    (frame: $0.frame, stateVector: Optional($0.stateVector))
                }
            )
            for (offset, request) in policyRequests.enumerated() {
                guard request.instanceIndex < instances.count else { continue }
                let nextAction = actions.indices.contains(offset)
                    ? actions[offset]
                    : TempestAgentAction()
                instances[request.instanceIndex].previousStateVector = request.stateVector
                instances[request.instanceIndex].previousAction = nextAction
                instances[request.instanceIndex].previousScore = request.snapshot.score
                instances[request.instanceIndex].previousLives = request.snapshot.lives
                instances[request.instanceIndex].previousLevel = request.snapshot.displayLevel
                instances[request.instanceIndex].lastAction = nextAction
            }
            performance.inferenceMS = smoothPerformanceMetric(
                performance.inferenceMS,
                Date().timeIntervalSince(inferenceStart) * 1_000
            )
        }
        if Date().timeIntervalSince(lastEAROMAutosave) >= 60.0 {
            saveEAROMIfNeeded(force: false)
            lastEAROMAutosave = Date()
        }
        if shouldPublishFrames || haltStatus != nil {
            if shouldPublishFrames {
                lastFramePublish = now
                publishFramesSincePerformanceSample += 1
            }
            publish(status: haltStatus, frames: updatedFrames)
        }
        let tickMS = Date().timeIntervalSince(tickStart) * 1_000
        performance.runtimeTickMS = smoothPerformanceMetric(performance.runtimeTickMS, tickMS)
        if tickMS > 16.7 {
            performance.droppedFrames += 1
        }
        updatePerformanceSampleIfNeeded()
    }

    func learnerSnapshot() -> SwiftTempestLearner.Snapshot {
        if DispatchQueue.getSpecific(key: runtimeQueueKey) == true {
            return learner.snapshot()
        }
        return runtimeQueue.sync {
            learner.snapshot()
        }
    }

    func performanceSnapshot() -> SwiftRuntimePerformanceSnapshot {
        if DispatchQueue.getSpecific(key: runtimeQueueKey) == true {
            return performance
        }
        return runtimeQueue.sync {
            performance
        }
    }

    private func gameFPS() -> Double {
        let games = max(1, instances.count)
        if performance.simFramesPerSecond > 0 {
            return performance.simFramesPerSecond / Double(games)
        }
        return Double(simulationFramesPerTick) * (maxSpeedTraining ? 1_000.0 : 60.0)
    }

    private func updatePerformanceSampleIfNeeded() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastPerformanceSample)
        guard elapsed >= 1.0 else { return }
        performance.simFramesPerSecond = Double(simFramesSincePerformanceSample) / elapsed
        performance.renderPublishFPS = Double(publishFramesSincePerformanceSample) / elapsed
        simFramesSincePerformanceSample = 0
        publishFramesSincePerformanceSample = 0
        lastPerformanceSample = now
    }

    private func smoothPerformanceMetric(_ current: Double, _ latest: Double) -> Double {
        current <= 0 ? latest : current * 0.9 + latest * 0.1
    }

    func loadBundledLearnerSeed(wait: Bool = false) {
        let work = { [weak self] in
            guard let self else { return }
            self.status = self.learner.loadBundledSeed()
            self.publish(status: self.status)
        }
        if DispatchQueue.getSpecific(key: runtimeQueueKey) == true {
            work()
        } else if wait {
            runtimeQueue.sync(execute: work)
        } else {
            runtimeQueue.async(execute: work)
        }
    }

    func setEpsilon(_ value: Double) {
        runtimeQueue.async { [weak self] in self?.learner.setEpsilon(value) }
    }

    func setExpertRatio(_ value: Double) {
        runtimeQueue.async { [weak self] in self?.learner.setExpertRatio(value) }
    }

    func setTraining(_ enabled: Bool) {
        runtimeQueue.async { [weak self] in self?.learner.setTraining(enabled) }
    }

    func setBestAIMode() {
        runtimeQueue.async { [weak self] in self?.learner.setBestAIMode() }
    }

    func setLearningMode() {
        runtimeQueue.async { [weak self] in self?.learner.setLearningMode() }
    }

    func resetExploration() {
        runtimeQueue.async { [weak self] in self?.learner.resetExploration() }
    }

    func resetExpert() {
        runtimeQueue.async { [weak self] in self?.learner.resetExpert() }
    }

    func clearReplay() {
        runtimeQueue.async { [weak self] in
            guard let self else { return }
            self.learner.clearReplay()
            _ = self.learner.savePersistentState()
            self.publish(status: "Swift learner examples cleared")
        }
    }

    private func publishRemainingInstances() {
        let frames = Dictionary(
            uniqueKeysWithValues: instances.map {
                ($0.machine.clientID, $0.machine.currentSnapshot().gameFrameData())
            }
        )
        publish(status: "Swift emulator instance removed", frames: frames)
    }

    private func saveEAROMIfNeeded(force: Bool) {
        guard let romSet else { return }
        _ = learner.savePersistentState()
        guard force || instances.contains(where: { $0.machine.hasUnsavedEAROM }) else { return }
        guard let selected = instances.max(by: {
            $0.machine.highScore() < $1.machine.highScore()
        }) else { return }
        let data = Data(selected.machine.earomSnapshot())
        do {
            let parent = romSet.earomURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            try data.write(to: romSet.earomURL, options: .atomic)
            for index in instances.indices {
                instances[index].machine.markEAROMSaved()
            }
        } catch {
            publish(status: "Swift emulator EAROM save failed: \(error.localizedDescription)")
        }
    }

    private func publish(
        isRunning newIsRunning: Bool? = nil,
        status newStatus: String? = nil,
        frames newFrames: [Int: GameFrameData]? = nil
    ) {
        DispatchQueue.main.async {
            if let newIsRunning {
                self.isRunning = newIsRunning
            }
            if let newStatus {
                self.status = newStatus
            }
            if let newFrames {
                self.framesByClientID = newFrames
            }
        }
    }

    private static func input(
        frame: Int,
        gamestate: Int,
        action: TempestAgentAction
    ) -> TempestInputState {
        let startCycle = frame % 360
        let scriptedStart = startCycle >= 105 && startCycle < 165
        let scriptedCoin = startCycle >= 40 && startCycle < 70
        let isLevelSelect = gamestate == 0x16
        let signedSpinner = max(-32, min(31, action.spinner))
        let spinner = frame > 165 && !isLevelSelect ? signedSpinner : 0
        return TempestInputState(
            coin1: scriptedCoin,
            start1: scriptedStart,
            fire: isLevelSelect || (frame > 165 && action.fire),
            zap: frame > 165 && action.zap,
            spinnerDelta: spinner
        )
    }

    private static func reward(
        previousScore: Int,
        previousLives: Int,
        previousLevel: Int,
        snapshot: TempestSnapshot,
        policyFrame: TempestPolicyFrame
    ) -> Float {
        let scoreDelta = snapshot.score - previousScore
        let levelDelta = snapshot.displayLevel - previousLevel
        let lostLives = max(0, previousLives - snapshot.lives)
        let scoreReward = Float(max(-1_000, min(5_000, scoreDelta))) * 0.01
        let levelReward = Float(max(0, levelDelta)) * 25.0
        let lifePenalty = Float(lostLives) * 12.0
        let survivalReward: Float = snapshot.runtimeStatus == "running" ? 0.01 : -5.0
        let safetyReward = laneSafetyReward(policyFrame)
        return max(-50.0, min(
            80.0,
            scoreReward + levelReward - lifePenalty + survivalReward + safetyReward
        ))
    }

    private static func laneSafetyReward(_ frame: TempestPolicyFrame) -> Float {
        guard frame.gamestate == 0x04 || frame.gamestate == 0x20 else { return 0 }
        let offsets = [0, 1, -1, 2, -2]
        var shaped: Float = 0
        var seen = Set<Int>()
        for offset in offsets {
            guard let lane = offsetLane(
                from: frame.playerLane,
                by: offset,
                openLevel: frame.openLevel
            ) else { continue }
            guard !seen.contains(lane) else { continue }
            seen.insert(lane)
            let distance = abs(offset)
            let weight: Float
            switch distance {
            case 0: weight = 1.0
            case 1: weight = 0.5
            default: weight = 0.25
            }
            shaped += laneHasNearbyThreat(lane, frame: frame)
                ? -2.0 * weight
                : 2.0 * weight
        }
        return shaped
    }

    private static func laneHasNearbyThreat(
        _ lane: Int,
        frame: TempestPolicyFrame
    ) -> Bool {
        let normalized = lane & 0x0f
        if frame.pulsing > 0 && frame.pulsing < 0x80 {
            if frame.enemies.contains(where: {
                $0.type == 1 && ($0.lane & 0x0f) == normalized && $0.depth > 0
            }) {
                return true
            }
        }
        if frame.enemies.contains(where: {
            ($0.lane & 0x0f) == normalized &&
                $0.depth > 0 &&
                $0.depth <= 0x80
        }) {
            return true
        }
        return frame.enemyShots.contains {
            ($0.lane & 0x0f) == normalized &&
                $0.depth > 0 &&
                $0.depth <= 0x80
        }
    }

    private static func offsetLane(
        from lane: Int,
        by delta: Int,
        openLevel: Bool
    ) -> Int? {
        if openLevel {
            let candidate = lane + delta
            return (0...15).contains(candidate) ? candidate : nil
        }
        return (lane + delta + 160) & 0x0f
    }

    private static func isTerminal(_ snapshot: TempestSnapshot) -> Bool {
        snapshot.runtimeStatus != "running" ||
            snapshot.gamestate == 0x12 ||
            (snapshot.score > 0 && snapshot.lives == 0)
    }
}

private struct SwiftTempestInstance {
    let machine: TempestMachine
    var age = 0
    var encoder = TempestAgentFrameEncoder()
    var lastAction = TempestAgentAction()
    var previousStateVector: [Float]?
    var previousAction = TempestAgentAction()
    var previousScore = 0
    var previousLives = 0
    var previousLevel = 1
}

private struct SwiftTempestPolicyRequest {
    let instanceIndex: Int
    let frame: TempestPolicyFrame
    let stateVector: [Float]
    let snapshot: TempestSnapshot
}
