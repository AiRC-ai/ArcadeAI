import Foundation
import MLX
import MLXNN
import MLXOptimizers

struct TempestPolicyFrame {
    struct Threat {
        var lane: Int
        var depth: Int
        var type: Int
        var canShoot: Bool
    }

    var sourceGameID: Int = 0
    var frame: Int
    var gamestate: Int
    var playerLane: Int
    var lives: Int
    var score: Int
    var openLevel: Bool = false
    var spikeDepths: [Int] = []
    var pulsing: Int = 0
    var shotCount: Int = 0
    var superzapperUses: Int = 0
    var enemiesPending: Int = 0
    var enemies: [Threat]
    var enemyShots: [Threat]
}

enum TempestActionSpace {
    static let fireZapCount = 4
    static let spinnerLevels = [0, 12, 9, 6, 3, 1, -1, -3, -6, -9, -12]
    static let actionCount = fireZapCount * spinnerLevels.count

    static func fireZapIndex(fire: Bool, zap: Bool) -> Int {
        (fire ? 2 : 0) + (zap ? 1 : 0)
    }

    static func decodeFireZap(_ index: Int) -> (fire: Bool, zap: Bool) {
        let clamped = max(0, min(fireZapCount - 1, index))
        return (((clamped >> 1) & 1) != 0, (clamped & 1) != 0)
    }

    static func combine(fireZapIndex: Int, spinnerIndex: Int) -> Int {
        max(0, min(fireZapCount - 1, fireZapIndex)) * spinnerLevels.count +
            max(0, min(spinnerLevels.count - 1, spinnerIndex))
    }

    static func split(_ jointIndex: Int) -> (fireZapIndex: Int, spinnerIndex: Int) {
        let clamped = max(0, min(actionCount - 1, jointIndex))
        return (clamped / spinnerLevels.count, clamped % spinnerLevels.count)
    }

    static func action(for jointIndex: Int) -> TempestAgentAction {
        let split = split(jointIndex)
        let fireZap = decodeFireZap(split.fireZapIndex)
        return TempestAgentAction(
            fire: fireZap.fire,
            zap: fireZap.zap,
            spinner: spinnerLevels[split.spinnerIndex]
        )
    }

    static func index(for action: TempestAgentAction) -> Int {
        combine(
            fireZapIndex: fireZapIndex(fire: action.fire, zap: action.zap),
            spinnerIndex: nearestSpinnerIndex(for: action.spinner)
        )
    }

    static func nearestSpinnerIndex(for command: Int) -> Int {
        spinnerLevels
            .enumerated()
            .min { abs($0.element - command) < abs($1.element - command) }?
            .offset ?? 0
    }
}

final class SwiftTempestLearner {
    private struct PersistentState: Codable {
        var version: Int
        var source: String
        var checkpointHash: String?
        var replayCount: Int
        var trainingSteps: Int
        var epsilon: Double
        var expertRatio: Double
        var trainingEnabled: Bool
        var bestAIMode: Bool
        var loss: Double
        var gradNorm: Double
        var qMean: Double
        var agreement: Double
        var episodes: Int
        var optimizerStep: Int?
        var replayCapacity: Int?
        var clearedTrainingFloor: Bool?
        var savedAt: Date
    }

    private struct MLXReplayTrainingBatch {
        var states: [[Float]]
        var actionMask: MLXArray
        var targetDistributions: MLXArray
        var importanceWeights: MLXArray
        var expertMask: MLXArray
        var indices: [Int]
        var tdErrors: [Float]
        var meanSelectedQ: Float
    }

    struct Snapshot {
        var epsilon: Double
        var expertRatio: Double
        var trainingEnabled: Bool
        var bestAIMode: Bool
        var replayCount: Int
        var trainingSteps: Int
        var loss: Double
        var gradNorm: Double
        var qMean: Double
        var agreement: Double
        var episodes: Int
        var averageLevel: Double
        var optimizerStep: Int
        var neuralRuntimeStatus: String
        var replaySampleMS: Double
        var trainingBatchMS: Double
        var optimizerMS: Double
        var learnerUpdatesPerSecond: Double
        var trainingInFlight: Bool
    }

    private var epsilon = Double(MLXRainbowTrainingOps.epsilonStart)
    private var expertRatio = Double(MLXRainbowTrainingOps.expertRatioStart)
    private var trainingEnabled = true
    private var bestAIMode = false
    private var replayCount = 0
    private var trainingSteps = 0
    private var loss = 0.0
    private var gradNorm = 0.0
    private var qMean = 0.0
    private var agreement = 0.0
    private var episodes = 0
    private var optimizerStep = 0
    private var clearedTrainingFloor = false
    private var replaySampleMS = 0.0
    private var trainingBatchMS = 0.0
    private var optimizerMS = 0.0
    private var learnerUpdatesPerSecond = 0.0
    private var trainingInFlight = false
    private var updatesSinceRateSample = 0
    private var lastUpdateRateSample = Date()
    private var levelSamples = 0
    private var levelTotal = 0.0
    private var transitionsSinceOptimizerStep = 0
    private var rng: UInt64 = 0x5445_4d50_4553_5441
    private var loadedSource = "defaults"
    private var checkpointHash: String?
    private var rainbowModel: SwiftRainbowModel?
    private var onlineRainbowModel: MLXRainbowTrainableNetwork?
    private var targetRainbowModel: MLXRainbowTrainableNetwork?
    private var optimizer = PersistentAdamOptimizer(
        learningRate: MLXRainbowTrainingOps.learningRate
    )
    private var neuralRuntimeStatus = "CPU policy fallback"
    private let replay = SwiftPrioritizedReplayMemory(capacity: 250_000, alpha: 0.7)
    private let replayLock = NSLock()
    private let modelLock = NSLock()
    private let trainingQueue = DispatchQueue(
        label: "tempest.swift-emulator.learner",
        qos: .utility
    )
    private var nStepBuffers: [Int: SwiftNStepReplayBuffer] = [:]
    private var lastActionWasExpertByGameID: [Int: Bool] = [:]
    private var recentReplayIndicesByGameID: [Int: [Int]] = [:]
    private let replayCapacity = 250_000
    private let zoomGamestate = 0x20
    private let zoomExpertMultiplier = 2.0
    private let zoomEpsilonMultiplier = 0.2
    private let superzapGateDecayFrames = 10_000_000

    func resetForRun() {
        levelSamples = 0
        levelTotal = 0
    }

    func action(
        for frame: TempestPolicyFrame,
        stateVector: [Float]? = nil
    ) -> TempestAgentAction {
        actions(for: [(frame: frame, stateVector: stateVector)]).first
            ?? TempestAgentAction()
    }

    func actions(
        for requests: [(frame: TempestPolicyFrame, stateVector: [Float]?)]
    ) -> [TempestAgentAction] {
        guard !requests.isEmpty else { return [] }

        var policies = Array(
            repeating: TempestAgentAction(),
            count: requests.count
        )
        var experts = Array(
            repeating: TempestAgentAction(),
            count: requests.count
        )
        var mlxRequestIndices: [Int] = []
        var mlxStates: [[Float]] = []

        for index in requests.indices {
            let frame = requests[index].frame
            if Self.isInactive(frame) {
                continue
            }
            let expert = expertAction(for: frame)
            experts[index] = expert
            if let stateVector = requests[index].stateVector,
               stateVector.count == MLXRainbowNetwork.stateSize {
                mlxRequestIndices.append(index)
                mlxStates.append(stateVector)
            } else {
                policies[index] = fallbackPolicyAction(
                    stateVector: requests[index].stateVector,
                    expert: expert
                )
            }
        }

        if !mlxStates.isEmpty,
           let onlineRainbowModel,
           modelLock.try() {
            defer { modelLock.unlock() }
            if let mlxActions = onlineRainbowModel.actions(for: mlxStates),
               mlxActions.count == mlxRequestIndices.count {
                for (offset, requestIndex) in mlxRequestIndices.enumerated() {
                    policies[requestIndex] = mlxActions[offset]
                }
            } else {
                for requestIndex in mlxRequestIndices {
                    policies[requestIndex] = fallbackPolicyAction(
                        stateVector: requests[requestIndex].stateVector,
                        expert: experts[requestIndex]
                    )
                }
            }
        } else {
            for requestIndex in mlxRequestIndices {
                policies[requestIndex] = fallbackPolicyAction(
                    stateVector: requests[requestIndex].stateVector,
                    expert: experts[requestIndex]
                )
            }
        }

        var chosenActions: [TempestAgentAction] = []
        chosenActions.reserveCapacity(requests.count)
        var agreementHits = 0
        var qAccumulator = 0.0
        var activeCount = 0

        for index in requests.indices {
            let frame = requests[index].frame
            if Self.isInactive(frame) {
                chosenActions.append(TempestAgentAction())
                lastActionWasExpertByGameID[frame.sourceGameID] = false
                continue
            }
            activeCount += 1
            let expert = experts[index]
            let effectiveExpertRatio = expertRatio(for: frame)
            let effectiveEpsilon = epsilon(for: frame)
            let useExpert = !bestAIMode && randomUnit() < effectiveExpertRatio
            let explore = !bestAIMode && randomUnit() < effectiveEpsilon
            let chosen: TempestAgentAction
            if explore {
                chosen = randomAction()
            } else {
                chosen = useExpert ? expert : policies[index]
            }
            lastActionWasExpertByGameID[frame.sourceGameID] = useExpert && !explore
            let gated = gateSuperzapIfNeeded(chosen, expert: expert)
            if chosen.spinner == expert.spinner {
                agreementHits += 1
            }
            qAccumulator += Double(abs(gated.spinner))
            chosenActions.append(gated)
        }

        if activeCount > 0 {
            agreement = agreement * 0.995 +
                (Double(agreementHits) / Double(activeCount)) * 0.005
            qMean = qMean * 0.99 +
                (qAccumulator / Double(activeCount)) * 0.01
        }
        return chosenActions
    }

    func recordLevel(_ level: Int) {
        levelSamples += 1
        levelTotal += Double(level)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            epsilon: epsilon,
            expertRatio: expertRatio,
            trainingEnabled: trainingEnabled,
            bestAIMode: bestAIMode,
            replayCount: replayCount,
            trainingSteps: trainingSteps,
            loss: loss,
            gradNorm: gradNorm,
            qMean: qMean,
            agreement: agreement,
            episodes: episodes,
            averageLevel: levelSamples == 0 ? 0 : levelTotal / Double(levelSamples),
            optimizerStep: optimizerStep,
            neuralRuntimeStatus: neuralRuntimeStatus,
            replaySampleMS: replaySampleMS,
            trainingBatchMS: trainingBatchMS,
            optimizerMS: optimizerMS,
            learnerUpdatesPerSecond: learnerUpdatesPerSecond,
            trainingInFlight: trainingInFlight
        )
    }

    func observeTransition(
        sourceGameID: Int,
        frame: Int,
        state: [Float],
        action: TempestAgentAction,
        reward: Float,
        nextState: [Float],
        done: Bool
    ) {
        guard trainingEnabled, state.count == 195, nextState.count == 195 else { return }
        let actionIndex = TempestActionSpace.index(for: action)
        let nstep = nStepBuffers[sourceGameID] ?? SwiftNStepReplayBuffer(nStep: 12, gamma: 0.99)
        nStepBuffers[sourceGameID] = nstep
        let matured = nstep.append(
            state: state,
            actionIndex: actionIndex,
            reward: reward,
            nextState: nextState,
            done: done,
            isExpert: lastActionWasExpertByGameID[sourceGameID] ?? false,
            sourceGameID: sourceGameID,
            frame: frame
        )
        if !matured.isEmpty {
            replayLock.lock()
            for transition in matured {
                let index = replay.append(transition)
                rememberRecentReplayIndex(index, sourceGameID: sourceGameID)
            }
            if done {
                boostPreDeathPriorities(sourceGameID: sourceGameID)
            }
            let currentReplayCount = replay.count
            replayLock.unlock()
            replayCount = max(replayCount, currentReplayCount)
        }
        transitionsSinceOptimizerStep += matured.count
        if transitionsSinceOptimizerStep >= Int(MLXRainbowTrainingOps.maxSamplesPerFrame) {
            transitionsSinceOptimizerStep = 0
            trainFromReplayIfReady()
        }
    }

    @discardableResult
    func loadPersistentState() -> String {
        loadBundledTensorModel()
        let bundledSeedURL = Bundle.main.resourceURL?
            .appendingPathComponent("models/swift_learner_seed.json")
        let bundledSeed = bundledSeedURL.flatMap { loadState(from: $0) }
        if let state = loadState(from: Self.applicationSupportStateURL) {
            apply(state)
            loadSavedNetworkParameters()
            if let bundledSeed {
                if clearedTrainingFloor {
                    return "loaded saved Swift learner state"
                }
                mergeTrainingFloor(from: bundledSeed)
                return "loaded saved Swift learner state + bundled training floor"
            }
            return "loaded saved Swift learner state"
        }
        return loadBundledSeed()
    }

    @discardableResult
    func loadBundledSeed() -> String {
        let tensorStatus = loadBundledTensorModel()
        if let seedURL = Bundle.main.resourceURL?
            .appendingPathComponent("models/swift_learner_seed.json"),
           let state = loadState(from: seedURL) {
            apply(state)
            return "loaded bundled Swift learner seed (\(tensorStatus))"
        }
        loadedSource = "defaults"
        checkpointHash = nil
        return "using default Swift learner state"
    }

    @discardableResult
    func savePersistentState() -> Bool {
        let state = makePersistentState(source: loadedSource)
        do {
            let url = Self.applicationSupportStateURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: url, options: .atomic)
            return saveNetworkParameters()
        } catch {
            return false
        }
    }

    func setEpsilon(_ value: Double) {
        epsilon = min(1.0, max(0.0, value))
        if epsilon > 0.001 { bestAIMode = false }
    }

    func setExpertRatio(_ value: Double) {
        expertRatio = min(1.0, max(0.0, value))
        if expertRatio > 0.001 { bestAIMode = false }
    }

    func setTraining(_ enabled: Bool) {
        trainingEnabled = enabled
        if enabled { bestAIMode = false }
    }

    func setBestAIMode() {
        bestAIMode = true
        trainingEnabled = false
        epsilon = 0
        expertRatio = 0
    }

    func setLearningMode() {
        bestAIMode = false
        trainingEnabled = true
        epsilon = max(epsilon, naturalEpsilon())
        expertRatio = max(expertRatio, naturalExpertRatio())
    }

    func resetExploration() {
        setEpsilon(naturalEpsilon())
    }

    func resetExpert() {
        setExpertRatio(naturalExpertRatio())
    }

    func clearReplay() {
        replayLock.lock()
        replay.removeAll(keepingCapacity: true)
        replayLock.unlock()
        nStepBuffers.removeAll(keepingCapacity: true)
        optimizerStep = 0
        transitionsSinceOptimizerStep = 0
        replayCount = 0
        trainingSteps = 0
        clearedTrainingFloor = true
        loadedSource = "cleared_user_state"
        replaySampleMS = 0
        trainingBatchMS = 0
        optimizerMS = 0
        learnerUpdatesPerSecond = 0
        loss = 0
        gradNorm = 0
        qMean = 0
        agreement = 0
        lastActionWasExpertByGameID.removeAll(keepingCapacity: true)
        recentReplayIndicesByGameID.removeAll(keepingCapacity: true)
        if !bestAIMode {
            epsilon = Double(MLXRainbowTrainingOps.epsilonStart)
            expertRatio = Double(MLXRainbowTrainingOps.expertRatioStart)
            trainingEnabled = true
        }
    }

    func noteEpisodeComplete() {
        episodes += 1
    }

    private static func isInactive(_ frame: TempestPolicyFrame) -> Bool {
        frame.gamestate == 0 || frame.gamestate == 0x12
    }

    private func expertRatio(for frame: TempestPolicyFrame) -> Double {
        guard frame.gamestate == zoomGamestate else { return expertRatio }
        return min(1.0, max(0.0, expertRatio * zoomExpertMultiplier))
    }

    private func epsilon(for frame: TempestPolicyFrame) -> Double {
        guard frame.gamestate == zoomGamestate else { return epsilon }
        return min(1.0, max(0.0, epsilon * zoomEpsilonMultiplier))
    }

    private func gateSuperzapIfNeeded(
        _ action: TempestAgentAction,
        expert: TempestAgentAction
    ) -> TempestAgentAction {
        guard !bestAIMode, action.zap, !expert.zap else { return action }
        let progress = min(1.0, Double(max(0, replayCount)) / Double(superzapGateDecayFrames))
        let gateProbability = max(0.0, 1.0 - progress)
        guard randomUnit() < gateProbability else { return action }
        return TempestAgentAction(
            fire: action.fire,
            zap: false,
            spinner: action.spinner
        )
    }

    private func rememberRecentReplayIndex(_ index: Int, sourceGameID: Int) {
        var indices = recentReplayIndicesByGameID[sourceGameID] ?? []
        indices.append(index)
        let lookback = max(1, MLXRainbowTrainingOps.preDeathLookback)
        if indices.count > lookback {
            indices.removeFirst(indices.count - lookback)
        }
        recentReplayIndicesByGameID[sourceGameID] = indices
    }

    private func boostPreDeathPriorities(sourceGameID: Int) {
        guard let indices = recentReplayIndicesByGameID[sourceGameID],
              !indices.isEmpty else { return }
        replay.boostPriorities(
            indices: indices,
            factor: MLXRainbowTrainingOps.preDeathPriorityBoost
        )
        recentReplayIndicesByGameID[sourceGameID] = []
    }

    private func fallbackPolicyAction(
        stateVector: [Float]?,
        expert: TempestAgentAction
    ) -> TempestAgentAction {
        if let stateVector, let action = rainbowModel?.action(for: stateVector) {
            return action
        }
        return expert
    }

    private func trainFromReplayIfReady() {
        guard trainingEnabled,
              !trainingInFlight,
              replayCount >= MLXRainbowTrainingOps.minimumReplayToTrain,
              let onlineRainbowModel,
              let targetRainbowModel else {
            return
        }
        trainingInFlight = true
        let beta = MLXRainbowTrainingOps.beta(forReplayCount: replayCount)
        trainingQueue.async { [weak self, onlineRainbowModel, targetRainbowModel] in
            self?.performTrainingStep(
                onlineRainbowModel: onlineRainbowModel,
                targetRainbowModel: targetRainbowModel,
                beta: beta
            )
        }
    }

    private func performTrainingStep(
        onlineRainbowModel: MLXRainbowTrainableNetwork,
        targetRainbowModel: MLXRainbowTrainableNetwork,
        beta: Float
    ) {
        let sampleStart = Date()
        replayLock.lock()
        let samples = replay.sample(
            batchSize: MLXRainbowTrainingOps.batchSize,
            beta: beta
        )
        replayLock.unlock()
        let sampleMS = Date().timeIntervalSince(sampleStart) * 1_000

        let batchStart = Date()
        modelLock.lock()
        defer {
            modelLock.unlock()
            trainingInFlight = false
        }
        guard let batch = makeTrainingBatch(
            samples: samples,
            online: onlineRainbowModel,
            target: targetRainbowModel
        ) else {
            replaySampleMS = smoothMetric(replaySampleMS, sampleMS)
            return
        }
        let batchMS = Date().timeIntervalSince(batchStart) * 1_000

        let optimizerStart = Date()
        let lossAndGrad = valueAndGrad(model: onlineRainbowModel) {
            (model: MLXRainbowTrainableNetwork, batch: MLXReplayTrainingBatch) -> [MLXArray] in
            [self.rainbowLoss(model: model, batch: batch)]
        }
        let (lossValues, gradients) = lossAndGrad(onlineRainbowModel, batch)
        guard let lossValue = lossValues.first else { return }
        let (clippedGradients, gradientNorm) = clipGradNorm(
            gradients: gradients,
            maxNorm: 10
        )
        optimizer.update(model: onlineRainbowModel, gradients: clippedGradients)
        eval(onlineRainbowModel, optimizer, lossValue, gradientNorm)
        let optimizerStepMS = Date().timeIntervalSince(optimizerStart) * 1_000

        optimizerStep += 1
        trainingSteps += 1
        replayLock.lock()
        replay.updatePriorities(indices: batch.indices, tdErrors: batch.tdErrors)
        replayLock.unlock()
        if optimizerStep.isMultiple(of: MLXRainbowTrainingOps.targetSyncInterval) {
            targetRainbowModel.sync(from: onlineRainbowModel)
        }
        replaySampleMS = smoothMetric(replaySampleMS, sampleMS)
        trainingBatchMS = smoothMetric(trainingBatchMS, batchMS)
        optimizerMS = smoothMetric(optimizerMS, optimizerStepMS)
        updateLearnerRate()
        loss = Double(lossValue.item(Float.self))
        gradNorm = Double(gradientNorm.item(Float.self))
        qMean = Double(batch.meanSelectedQ)
    }

    private func smoothMetric(_ current: Double, _ latest: Double) -> Double {
        current <= 0 ? latest : current * 0.9 + latest * 0.1
    }

    private func updateLearnerRate() {
        updatesSinceRateSample += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdateRateSample)
        guard elapsed >= 1 else { return }
        learnerUpdatesPerSecond = Double(updatesSinceRateSample) / elapsed
        updatesSinceRateSample = 0
        lastUpdateRateSample = now
    }

    private func makeTrainingBatch(
        samples: [SwiftReplaySample],
        online: MLXRainbowTrainableNetwork,
        target: MLXRainbowTrainableNetwork
    ) -> MLXReplayTrainingBatch? {
        guard !samples.isEmpty else { return nil }
        let states = samples.map(\.transition.state)
        let nextStates = samples.map(\.transition.nextState)
        guard let onlineNextQ = online.qValues(for: nextStates)?.asArray(Float.self),
              let targetNextDistributions = target.actionDistributions(for: nextStates)?
                .asArray(Float.self),
              let currentQ = online.qValues(for: states)?.asArray(Float.self) else {
            return nil
        }

        let support = SwiftC51Projection.support
        var actionMask = Array(
            repeating: Float(0),
            count: samples.count * TempestActionSpace.actionCount
        )
        var targetDistributions: [Float] = []
        var tdErrors: [Float] = []
        var selectedQTotal = Float(0)
        targetDistributions.reserveCapacity(samples.count * SwiftC51Projection.atomCount)
        tdErrors.reserveCapacity(samples.count)

        for sampleIndex in samples.indices {
            let transition = samples[sampleIndex].transition
            let actionIndex = max(
                0,
                min(TempestActionSpace.actionCount - 1, transition.actionIndex)
            )
            actionMask[sampleIndex * TempestActionSpace.actionCount + actionIndex] = 1

            let nextQOffset = sampleIndex * TempestActionSpace.actionCount
            let nextAction = (0..<TempestActionSpace.actionCount).max {
                onlineNextQ[nextQOffset + $0] < onlineNextQ[nextQOffset + $1]
            } ?? 0
            let distributionOffset = (
                sampleIndex * TempestActionSpace.actionCount + nextAction
            ) * SwiftC51Projection.atomCount
            let nextDistribution = Array(
                targetNextDistributions[
                    distributionOffset..<(distributionOffset + SwiftC51Projection.atomCount)
                ]
            )
            let projected = SwiftC51Projection.project(
                reward: transition.reward,
                done: transition.done,
                horizon: transition.horizon,
                gamma: MLXRainbowTrainingOps.gamma,
                nextDistribution: nextDistribution
            )
            targetDistributions.append(contentsOf: projected)
            let targetQ = zip(projected, support).reduce(Float(0)) {
                $0 + $1.0 * $1.1
            }
            let selectedQ = currentQ[nextQOffset + actionIndex]
            selectedQTotal += selectedQ
            tdErrors.append(abs(targetQ - selectedQ) + 1e-6)
        }

        let importanceWeights = samples.map(\.importanceWeight)
        return MLXReplayTrainingBatch(
            states: states,
            actionMask: MLXArray(
                actionMask,
                [samples.count, TempestActionSpace.actionCount]
            ),
            targetDistributions: MLXArray(
                targetDistributions,
                [samples.count, SwiftC51Projection.atomCount]
            ),
            importanceWeights: MLXArray(importanceWeights, [samples.count]),
            expertMask: MLXArray(
                samples.map { $0.transition.isExpert ? Float(1) : Float(0) },
                [samples.count]
            ),
            indices: samples.map(\.index),
            tdErrors: tdErrors,
            meanSelectedQ: selectedQTotal / Float(max(1, samples.count))
        )
    }

    private func rainbowLoss(
        model: MLXRainbowTrainableNetwork,
        batch: MLXReplayTrainingBatch
    ) -> MLXArray {
        guard let logits = model.atomLogits(for: batch.states) else {
            return MLXArray(0)
        }
        let selectedLogits = (
            logits * batch.actionMask.expandedDimensions(axis: -1)
        ).sum(axis: 1)
        let c51Loss = MLXRainbowTrainingOps.importanceWeightedC51Loss(
            logits: selectedLogits,
            targetDistributions: batch.targetDistributions,
            importanceWeights: batch.importanceWeights
        )
        guard let qValues = model.qValues(for: batch.states) else {
            return c51Loss
        }
        let actionLogProbabilities = logSoftmax(qValues, axis: -1)
        let selectedActionLogProbability = (
            actionLogProbabilities * batch.actionMask
        ).sum(axis: -1)
        let expertLoss = -(
            selectedActionLogProbability * batch.expertMask
        ).sum() / (batch.expertMask.sum() + Float(1e-6))
        let expertWeight = MLXRainbowTrainingOps.expertBCWeight(
            forFrameCount: replayCount
        )
        return c51Loss + expertLoss * expertWeight
    }

    @discardableResult
    private func loadBundledTensorModel() -> String {
        guard let package = SwiftTensorPackage.bundled(),
              let model = SwiftRainbowModel(package: package) else {
            rainbowModel = nil
            onlineRainbowModel = nil
            targetRainbowModel = nil
            neuralRuntimeStatus = "no Swift tensor package"
            return "no Swift tensor package"
        }
        rainbowModel = model

        if Self.mlxMetalLibraryAvailable {
            onlineRainbowModel = MLXRainbowTrainableNetwork(
                package: package,
                section: "online_state_dict"
            )
            targetRainbowModel = MLXRainbowTrainableNetwork(
                package: package,
                section: "target_state_dict"
            ) ?? MLXRainbowTrainableNetwork(
                package: package,
                section: "online_state_dict"
            )
            neuralRuntimeStatus = onlineRainbowModel == nil
                ? "CPU policy fallback"
                : "MLX Swift Rainbow policy ready"
        } else {
            // MLX aborts the process if its Metal kernels cannot be found.
            // Keep the app usable and trainable code present, but do not
            // instantiate/evaluate MLX until build_app.sh can bundle the
            // generated mlx.metallib/default.metallib.
            onlineRainbowModel = nil
            targetRainbowModel = nil
            neuralRuntimeStatus = "CPU policy fallback; MLX metallib missing"
        }
        optimizer = PersistentAdamOptimizer(
            learningRate: MLXRainbowTrainingOps.learningRate
        )
        loadedSource = "bundled_tensor_package"
        checkpointHash = package.checkpointSHA256
        replayCount = max(replayCount, package.frameCount)
        trainingSteps = max(trainingSteps, package.totalTrainingSteps)
        epsilon = package.epsilon
        expertRatio = package.expertRatio
        return onlineRainbowModel == nil
            ? "Swift tensor package ready (\(neuralRuntimeStatus))"
            : neuralRuntimeStatus
    }

    private static var mlxMetalLibraryAvailable: Bool {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("mlx.metallib"),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("default.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("mlx.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("default.metallib"),
        ]
        return candidates.compactMap { $0 }.contains {
            fileManager.fileExists(atPath: $0.path)
        }
    }

    private static var applicationSupportStateURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return root
            .appendingPathComponent("TempestAI", isDirectory: true)
            .appendingPathComponent("learner_state.json")
    }

    private static var applicationSupportWeightsDirectory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        return root
            .appendingPathComponent("TempestAI", isDirectory: true)
            .appendingPathComponent("learner_weights", isDirectory: true)
    }

    private func loadState(from url: URL) -> PersistentState? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PersistentState.self, from: data)
        } catch {
            return nil
        }
    }

    private func apply(_ state: PersistentState) {
        loadedSource = state.source
        checkpointHash = state.checkpointHash
        replayCount = max(0, state.replayCount)
        trainingSteps = max(0, state.trainingSteps)
        optimizerStep = state.version >= 3
            ? max(0, state.optimizerStep ?? 0)
            : 0
        epsilon = min(1.0, max(0.0, state.epsilon))
        expertRatio = min(1.0, max(0.0, state.expertRatio))
        trainingEnabled = state.trainingEnabled
        bestAIMode = state.bestAIMode
        loss = max(0.0, state.loss)
        gradNorm = max(0.0, state.gradNorm)
        qMean = state.qMean
        agreement = min(1.0, max(0.0, state.agreement))
        episodes = max(0, state.episodes)
        clearedTrainingFloor = state.clearedTrainingFloor ?? false
    }

    private func mergeTrainingFloor(from state: PersistentState) {
        guard !clearedTrainingFloor else { return }
        replayCount = max(replayCount, max(0, state.replayCount))
        trainingSteps = max(trainingSteps, max(0, state.trainingSteps))
        if state.version >= 3 {
            optimizerStep = max(optimizerStep, max(0, state.optimizerStep ?? 0))
        }
        if checkpointHash == nil {
            checkpointHash = state.checkpointHash
        }
        if loadedSource == "defaults" {
            loadedSource = "saved_state_plus_bundled_seed"
        }
    }

    private func makePersistentState(source: String) -> PersistentState {
        PersistentState(
            version: 3,
            source: source,
            checkpointHash: checkpointHash,
            replayCount: replayCount,
            trainingSteps: trainingSteps,
            epsilon: epsilon,
            expertRatio: expertRatio,
            trainingEnabled: trainingEnabled,
            bestAIMode: bestAIMode,
            loss: loss,
            gradNorm: gradNorm,
            qMean: qMean,
            agreement: agreement,
            episodes: episodes,
            optimizerStep: optimizerStep,
            replayCapacity: replayCapacity,
            clearedTrainingFloor: clearedTrainingFloor,
            savedAt: Date()
        )
    }

    @discardableResult
    private func saveNetworkParameters() -> Bool {
        guard let onlineRainbowModel, let targetRainbowModel else { return true }
        let directory = Self.applicationSupportWeightsDirectory
        let onlineSaved = onlineRainbowModel.saveParameters(
            to: directory,
            manifestName: "online_manifest.json"
        )
        let targetSaved = targetRainbowModel.saveParameters(
            to: directory,
            manifestName: "target_manifest.json"
        )
        let optimizerSaved = optimizer.saveState(
            to: directory,
            manifestName: "optimizer_manifest.json"
        )
        return onlineSaved && targetSaved && optimizerSaved
    }

    @discardableResult
    private func loadSavedNetworkParameters() -> Bool {
        guard let onlineRainbowModel, let targetRainbowModel else { return false }
        let directory = Self.applicationSupportWeightsDirectory
        let onlineLoaded = onlineRainbowModel.loadParameters(
            from: directory,
            manifestName: "online_manifest.json"
        )
        let targetLoaded = targetRainbowModel.loadParameters(
            from: directory,
            manifestName: "target_manifest.json"
        )
        if onlineLoaded && !targetLoaded {
            targetRainbowModel.sync(from: onlineRainbowModel)
        }
        if onlineLoaded {
            _ = optimizer.loadState(
                from: directory,
                manifestName: "optimizer_manifest.json"
            )
        }
        return onlineLoaded
    }

    private func naturalEpsilon() -> Double {
        let progress = min(
            Float(1),
            Float(max(0, replayCount)) /
                Float(max(1, MLXRainbowTrainingOps.epsilonDecayFrames))
        )
        return Double(
            MLXRainbowTrainingOps.epsilonStart +
                progress * (
                    MLXRainbowTrainingOps.epsilonEnd -
                        MLXRainbowTrainingOps.epsilonStart
                )
        )
    }

    private func naturalExpertRatio() -> Double {
        let progress = min(
            Float(1),
            Float(max(0, replayCount)) /
                Float(max(1, MLXRainbowTrainingOps.expertRatioDecayFrames))
        )
        return Double(
            MLXRainbowTrainingOps.expertRatioStart +
                progress * (
                    MLXRainbowTrainingOps.expertRatioEnd -
                        MLXRainbowTrainingOps.expertRatioStart
                )
        )
    }

    private func expertAction(for frame: TempestPolicyFrame) -> TempestAgentAction {
        if frame.gamestate == zoomGamestate {
            return zoomEscapeAction(for: frame)
        }

        if let escape = defensiveEscapeAction(for: frame) {
            return escape
        }

        guard frame.gamestate == 0x04 else {
            return TempestAgentAction(fire: true, zap: false, spinner: 0)
        }

        let target = preferredColumnTarget(for: frame)
        let targetLane = target?.lane ?? nearestSafeLane(
            from: frame.playerLane,
            frame: frame
        )
        let delta = relativeDelta(
            from: frame.playerLane,
            to: targetLane,
            openLevel: frame.openLevel
        )
        let spinner = spinnerCommand(for: delta)
        return TempestAgentAction(
            fire: true,
            zap: shouldSuperzap(frame: frame),
            spinner: spinner
        )
    }

    private func defensiveEscapeAction(for frame: TempestPolicyFrame) -> TempestAgentAction? {
        let playerLane = frame.playerLane & 0x0f

        if let shot = frame.enemyShots
            .filter({ $0.depth > 0 && $0.depth <= 0x60 })
            .min(by: {
                abs(relativeDelta(from: playerLane, to: $0.lane, openLevel: frame.openLevel)) <
                    abs(relativeDelta(from: playerLane, to: $1.lane, openLevel: frame.openLevel))
            }) {
            let rel = relativeDelta(from: playerLane, to: shot.lane, openLevel: frame.openLevel)
            if abs(rel) <= 1 {
                return escapeAction(awayFromRelativeLane: rel, frame: frame)
            }
        }

        if let topRail = frame.enemies
            .filter({
                $0.depth == 0x10 &&
                    ($0.type == 0 || ($0.type == 1 && frame.enemiesPending == 0)) &&
                    abs(relativeDelta(from: playerLane, to: $0.lane, openLevel: frame.openLevel)) <= 2
            })
            .min(by: {
                abs(relativeDelta(from: playerLane, to: $0.lane, openLevel: frame.openLevel)) <
                    abs(relativeDelta(from: playerLane, to: $1.lane, openLevel: frame.openLevel))
            }) {
            let rel = relativeDelta(from: playerLane, to: topRail.lane, openLevel: frame.openLevel)
            return escapeAction(awayFromRelativeLane: rel, frame: frame)
        }

        if let fuseball = frame.enemies
            .filter({
                $0.type == 4 &&
                    $0.depth > 0 &&
                    $0.depth <= 0x50 &&
                    abs(relativeDelta(from: playerLane, to: $0.lane, openLevel: frame.openLevel)) <= 2
            })
            .min(by: { $0.depth < $1.depth }) {
            let rel = relativeDelta(from: playerLane, to: fuseball.lane, openLevel: frame.openLevel)
            return escapeAction(awayFromRelativeLane: rel, frame: frame)
        }

        if isDangerLane(playerLane, frame: frame) {
            let targetLane = nearestSafeLane(
                from: playerLane,
                frame: frame,
                includeCurrent: false
            )
            return actionToward(lane: targetLane, frame: frame, fire: true, zap: false)
        }

        return nil
    }

    private func zoomEscapeAction(for frame: TempestPolicyFrame) -> TempestAgentAction {
        var bestLane = frame.playerLane & 0x0f
        var bestSpike = spikeDepth(in: bestLane, frame: frame)
        var bestDistance = 0
        for lane in 0..<16 where isValidLane(lane, openLevel: frame.openLevel) {
            let spike = spikeDepth(in: lane, frame: frame)
            let distance = abs(relativeDelta(
                from: frame.playerLane,
                to: lane,
                openLevel: frame.openLevel
            ))
            let better: Bool
            if spike == 0 {
                better = bestSpike != 0 || distance < bestDistance
            } else if bestSpike != 0 {
                better = spike < bestSpike ||
                    (spike == bestSpike && distance < bestDistance)
            } else {
                better = false
            }
            if better {
                bestLane = lane
                bestSpike = spike
                bestDistance = distance
            }
        }
        return actionToward(lane: bestLane, frame: frame, fire: true, zap: false)
    }

    private func preferredColumnTarget(for frame: TempestPolicyFrame) -> TempestPolicyFrame.Threat? {
        let huntOrder = [4, 0, 2, 3, 1]
        for type in huntOrder {
            let candidates = frame.enemies
                .filter { $0.type == type && $0.depth > 0 }
            if let best = candidates.min(by: {
                columnTargetScore($0, frame: frame) <
                    columnTargetScore($1, frame: frame)
            }) {
                return best
            }
        }

        return (frame.enemyShots + frame.enemies)
            .filter { $0.depth > 0 }
            .min {
                columnTargetScore($0, frame: frame) <
                    columnTargetScore($1, frame: frame)
            }
    }

    private func columnTargetScore(
        _ threat: TempestPolicyFrame.Threat,
        frame: TempestPolicyFrame
    ) -> Int {
        let laneDistance = abs(relativeDelta(
            from: frame.playerLane,
            to: threat.lane,
            openLevel: frame.openLevel
        ))
        let depth = max(0, min(255, threat.depth))
        let unsafeLanePenalty = isDangerLane(threat.lane, frame: frame) ? 24 : 0
        let canShootBonus = threat.canShoot ? -8 : 0
        return laneDistance * 16 + depth + unsafeLanePenalty + canShootBonus
    }

    private func shouldSuperzap(frame: TempestPolicyFrame) -> Bool {
        let activeEnemies = frame.enemies.filter { $0.depth > 0 }.count
        guard frame.superzapperUses < 2, activeEnemies > 0 else { return false }
        let topRailCount = frame.enemies
            .filter { $0.depth > 0 && $0.depth <= 0x10 }
            .count
        if frame.superzapperUses == 0 {
            return topRailCount >= 3 || frame.enemiesPending == 0
        }
        return topRailCount >= 1 || frame.enemiesPending == 0
    }

    private func escapeAction(
        awayFromRelativeLane rel: Int,
        frame: TempestPolicyFrame
    ) -> TempestAgentAction {
        let preferredDirection: Int
        if rel == 0 {
            preferredDirection = (nextRandom() & 1) == 0 ? -1 : 1
        } else {
            preferredDirection = rel > 0 ? -1 : 1
        }
        let target = nearestSafeLane(
            from: frame.playerLane,
            frame: frame,
            preferredDirection: preferredDirection,
            includeCurrent: false
        )
        if target == (frame.playerLane & 0x0f) {
            return sidestepAction(awayFromRelativeLane: rel)
        }
        return actionToward(lane: target, frame: frame, fire: true, zap: false)
    }

    private func sidestepAction(awayFromRelativeLane rel: Int) -> TempestAgentAction {
        let direction: Int
        if rel == 0 {
            direction = (nextRandom() & 1) == 0 ? -1 : 1
        } else {
            direction = rel > 0 ? -1 : 1
        }
        return TempestAgentAction(
            fire: true,
            zap: false,
            spinner: spinnerCommand(for: direction)
        )
    }

    private func actionToward(
        lane: Int,
        frame: TempestPolicyFrame,
        fire: Bool,
        zap: Bool
    ) -> TempestAgentAction {
        let delta = relativeDelta(
            from: frame.playerLane,
            to: lane,
            openLevel: frame.openLevel
        )
        return TempestAgentAction(
            fire: fire,
            zap: zap,
            spinner: spinnerCommand(for: delta)
        )
    }

    private func nearestSafeLane(
        from start: Int,
        frame: TempestPolicyFrame,
        preferredDirection: Int? = nil,
        includeCurrent: Bool = true
    ) -> Int {
        let normalized = start & 0x0f
        if includeCurrent && !isDangerLane(normalized, frame: frame) {
            return normalized
        }
        let directions: [Int]
        if let preferredDirection, preferredDirection != 0 {
            directions = [preferredDirection > 0 ? 1 : -1, preferredDirection > 0 ? -1 : 1]
        } else {
            directions = [-1, 1]
        }
        for distance in 1...8 {
            for direction in directions {
                guard let lane = offsetLane(
                    from: normalized,
                    by: direction * distance,
                    openLevel: frame.openLevel
                ) else { continue }
                if !isDangerLane(lane, frame: frame) {
                    return lane
                }
            }
        }
        return normalized
    }

    private func isDangerLane(_ lane: Int, frame: TempestPolicyFrame) -> Bool {
        guard isValidLane(lane, openLevel: frame.openLevel) else { return true }
        let normalized = lane & 0x0f
        if frame.pulsing > 0 && frame.pulsing < 0x80 {
            if frame.enemies.contains(where: {
                $0.type == 1 && ($0.lane & 0x0f) == normalized && $0.depth > 0
            }) {
                return true
            }
        }
        for enemy in frame.enemies where (enemy.lane & 0x0f) == normalized && enemy.depth > 0 {
            if enemy.type == 4 && enemy.depth <= 0x50 { return true }
            if enemy.depth <= 0x20 { return true }
        }
        return frame.enemyShots.contains {
            ($0.lane & 0x0f) == normalized &&
                $0.depth > 0 &&
                $0.depth <= 0x60
        }
    }

    private func spikeDepth(in lane: Int, frame: TempestPolicyFrame) -> Int {
        guard isValidLane(lane, openLevel: frame.openLevel) else { return 255 }
        let normalized = lane & 0x0f
        guard frame.spikeDepths.indices.contains(normalized) else { return 0 }
        return max(0, min(255, frame.spikeDepths[normalized]))
    }

    private func offsetLane(
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

    private func isValidLane(_ lane: Int, openLevel: Bool) -> Bool {
        openLevel ? (0...15).contains(lane) : true
    }

    private func relativeDelta(
        from current: Int,
        to target: Int,
        openLevel: Bool
    ) -> Int {
        if openLevel {
            return max(-15, min(15, target - current))
        }
        return shortestDelta(from: current, to: target)
    }

    private func shortestDelta(from current: Int, to target: Int) -> Int {
        var delta = (target & 0x0f) - (current & 0x0f)
        if delta > 8 { delta -= 16 }
        if delta < -8 { delta += 16 }
        return delta
    }

    private func spinnerCommand(for delta: Int) -> Int {
        if delta == 0 { return 0 }
        let magnitude: Int
        switch abs(delta) {
        case 1: magnitude = 3
        case 2: magnitude = 6
        case 3...4: magnitude = 9
        default: magnitude = 12
        }
        return delta > 0 ? magnitude : -magnitude
    }

    private func randomAction() -> TempestAgentAction {
        let index = Int(nextRandom() % UInt64(TempestActionSpace.spinnerLevels.count))
        return TempestAgentAction(
            fire: (nextRandom() & 1) == 0,
            zap: false,
            spinner: TempestActionSpace.spinnerLevels[index]
        )
    }

    private func randomUnit() -> Double {
        Double(nextRandom() & 0xffff) / 65_535.0
    }

    private func nextRandom() -> UInt64 {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return rng
    }
}
