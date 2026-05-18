from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_swift_model_exposes_q_values_and_c51_distributions():
    source = (ROOT / "TempestAI/Emulator/SwiftRainbowModel.swift").read_text()
    assert "func qValues(for state: [Float]) -> [Float]?" in source
    assert "func actionDistributions(for state: [Float]) -> [[Float]]?" in source
    assert "func actionAtomLogits(for state: [Float]) -> [[Float]]" in source
    assert "support[atom]" in source


def test_swift_ai_parity_self_test_compares_against_pytorch_fixtures():
    source = (ROOT / "TempestAI/Emulator/AIParitySelfTest.swift").read_text()
    app = (ROOT / "TempestAI/TempestAIApp.swift").read_text()
    assert "TEMPEST_AI_PARITY_FIXTURE" in source
    assert "TEMPEST_SWIFT_TENSOR_MANIFEST" in source
    assert "TEMPEST_AI_PARITY_Q_TOLERANCE" in source
    assert "TEMPEST_AI_PARITY_ALLOW_HASH_MISMATCH" in source
    assert "checkpointSHA256 != package.checkpointSHA256" in source
    assert "SwiftRainbowModel(package: package)" in source
    assert "MLXRainbowTrainableNetwork(package: package)" in source
    assert "mlxModel.qValues(for: states)" in source
    assert "cpuMatch >= 0.99" in source
    assert "mlxMatch >= 0.99" in source
    assert "maxCPUDelta <= tolerance" in source
    assert "maxMLXDelta <= tolerance" in source
    assert "AIParitySelfTest.runIfRequested()" in app


def test_current_learner_uses_real_mlx_optimizer_path():
    learner = (ROOT / "TempestAI/Emulator/SwiftTempestLearner.swift").read_text()
    assert "actionBiases" not in learner
    assert "private var onlineRainbowModel: MLXRainbowTrainableNetwork?" in learner
    assert "private var targetRainbowModel: MLXRainbowTrainableNetwork?" in learner
    assert "private var optimizer = PersistentAdamOptimizer(" in learner
    assert "trainFromReplayIfReady()" in learner
    assert "replayCount >= MLXRainbowTrainingOps.minimumReplayToTrain" in learner
    assert "private let trainingQueue = DispatchQueue(" in learner
    assert "performTrainingStep(" in learner
    assert "!trainingInFlight" in learner
    assert "valueAndGrad(model: onlineRainbowModel)" in learner
    assert "optimizer.update(model: onlineRainbowModel, gradients: clippedGradients)" in learner
    assert "optimizer.saveState(" in learner
    assert "optimizer.loadState(" in learner
    assert "targetRainbowModel.sync(from: onlineRainbowModel)" in learner
    assert "actionBiases" not in learner
    assert "isExpert: false" not in learner
    assert "lastActionWasExpertByGameID" in learner
    assert "expertMask: MLXArray" in learner
    assert "selectedActionLogProbability * batch.expertMask" in learner
    assert "expertBCWeight(" in learner
    assert "epsilon = Double(MLXRainbowTrainingOps.epsilonStart)" in learner
    assert "expertRatio = Double(MLXRainbowTrainingOps.expertRatioStart)" in learner
    assert "epsilon = max(epsilon, naturalEpsilon())" in learner
    assert "expertRatio = max(expertRatio, naturalExpertRatio())" in learner
    assert "epsilon = Double(MLXRainbowTrainingOps.epsilonStart)" in learner
    assert "expertRatio = Double(MLXRainbowTrainingOps.expertRatioStart)" in learner


def test_mlx_optimizer_self_test_exists_and_runs_real_update_path():
    source = (ROOT / "TempestAI/Emulator/MLXLearnerSelfTest.swift").read_text()
    app = (ROOT / "TempestAI/TempestAIApp.swift").read_text()
    assert "TEMPEST_MLX_SELF_TEST" in source
    assert "MLXRainbowTrainableNetwork(" in source
    assert "valueAndGrad(model: model)" in source
    assert "optimizer.update(model: model, gradients: gradients)" in source
    assert "PersistentAdamOptimizer(" in source
    assert "verifyOptimizerPersistence(optimizer)" in source
    assert "totalAbsoluteDelta(before: before, after: after)" in source
    assert "delta > 1e-7" in source
    assert "MLXLearnerSelfTest.runIfRequested()" in app


def test_persistent_adam_optimizer_saves_moments():
    source = (ROOT / "TempestAI/Emulator/PersistentAdamOptimizer.swift").read_text()
    assert "final class PersistentAdamOptimizer: Evaluatable" in source
    assert "func update(model: Module, gradients: ModuleParameters)" in source
    assert "first: MLXArray" in source
    assert "second: MLXArray" in source
    assert "beta1 * currentMoment.first" in source
    assert "beta2 * currentMoment.second" in source
    assert "func saveState(to directory: URL, manifestName: String) -> Bool" in source
    assert "func loadState(from directory: URL, manifestName: String) -> Bool" in source
    assert "var momentCount: Int" in source
    assert "func momentChecksum() -> Float" in source
    assert "optimizer_manifest.json" in (ROOT / "TempestAI/Emulator/SwiftTempestLearner.swift").read_text()


def test_package_declares_mlx_swift_runtime():
    package = (ROOT / "Package.swift").read_text()
    assert 'url: "https://github.com/ml-explore/mlx-swift.git"' in package
    assert '.product(name: "MLX", package: "mlx-swift")' in package
    assert '.product(name: "MLXNN", package: "mlx-swift")' in package
    assert '.product(name: "MLXOptimizers", package: "mlx-swift")' in package
    assert '.product(name: "MLXRandom", package: "mlx-swift")' in package


def test_legacy_python_oracle_is_removed_not_root_runtime():
    assert not (ROOT / "Scripts").exists()
    assert not (ROOT / "archive").exists()
    assert not (ROOT / "LUAScripts").exists()


def test_mlx_rainbow_network_contract_exists():
    source = (ROOT / "TempestAI/Emulator/MLXRainbowNetwork.swift").read_text()
    assert "import MLX" in source
    assert "import MLXNN" in source
    assert "import MLXOptimizers" in source
    assert "class MLXRainbowTrainableNetwork: Module" in source
    assert "final class MLXRainbowNetwork" in source
    assert "static let stateSize = 195" in source
    assert "static let actionCount = 44" in source
    assert "static let atomCount = 51" in source
    assert "func qValues(for states: [[Float]]) -> MLXArray?" in source
    assert "func greedyActionIndices(for states: [[Float]]) -> [Int]?" in source
    assert "MLXRainbowTrainingOps.greedyActionIndices(qValues: qValues)" in source
    assert ".asArray(Int32.self)" in source
    assert "softmax(logits, axis: -1)" in source
    assert "func sync(from other: MLXRainbowTrainableNetwork)" in source
    assert "func saveParameters(to directory: URL, manifestName: String) -> Bool" in source
    assert "func loadParameters(from directory: URL, manifestName: String) -> Bool" in source


def test_learner_prefers_mlx_policy_backend():
    learner = (ROOT / "TempestAI/Emulator/SwiftTempestLearner.swift").read_text()
    assert "private var onlineRainbowModel: MLXRainbowTrainableNetwork?" in learner
    assert "func actions(\n        for requests:" in learner
    assert "modelLock.try()" in learner
    assert "onlineRainbowModel.actions(for: mlxStates)" in learner
    assert "policies[requestIndex] = mlxActions[offset]" in learner
    assert "private static var mlxMetalLibraryAvailable: Bool" in learner
    assert "neuralRuntimeStatus" in learner
    assert "MLX aborts the process if its Metal kernels cannot be found" in learner
    assert "bestAIMode" in learner
    assert "MLX Swift Rainbow policy ready" in learner


def test_replay_uses_tree_sampling_instead_of_full_scan():
    source = (ROOT / "TempestAI/Emulator/SwiftRainbowTrainingPrimitives.swift").read_text()
    assert "private var priorityTree: [Float]" in source
    assert "@discardableResult\n    func append(_ transition: SwiftReplayTransition) -> Int" in source
    assert "func sample(batchSize: Int, beta: Float)" in source
    assert "private func updateTree(at index: Int, to priority: Float)" in source
    assert "private func prefixSum(upTo index: Int) -> Float" in source
    assert "storage.reduce(Float(0))" not in source
    assert "for index in storage.indices" not in source


def test_swift_policy_keeps_original_zoom_and_superzap_guards():
    learner = (ROOT / "TempestAI/Emulator/SwiftTempestLearner.swift").read_text()
    assert "private let zoomGamestate = 0x20" in learner
    assert "private let zoomExpertMultiplier = 2.0" in learner
    assert "private let zoomEpsilonMultiplier = 0.2" in learner
    assert "private let superzapGateDecayFrames = 10_000_000" in learner
    assert "expertRatio(for: frame)" in learner
    assert "epsilon(for: frame)" in learner
    assert "gateSuperzapIfNeeded(chosen, expert: expert)" in learner
    assert "guard !bestAIMode, action.zap, !expert.zap else { return action }" in learner
    assert "sourceGameID: clientID" in (ROOT / "TempestAI/Emulator/TempestMachine.swift").read_text()
    assert "lastActionWasExpertByGameID[frame.sourceGameID] = useExpert && !explore" in learner


def test_mlx_training_ops_lock_original_rainbow_contract():
    source = (ROOT / "TempestAI/Emulator/MLXRainbowTrainingOps.swift").read_text()
    assert "static let replayAlpha = Float(0.7)" in source
    assert "static let betaStart = Float(0.4)" in source
    assert "static let betaEnd = Float(1.0)" in source
    assert "static let nStep = 12" in source
    assert "static let gamma = Float(0.99)" in source
    assert "static let c51VMin = Float(-100)" in source
    assert "static let c51VMax = Float(100)" in source
    assert "static let batchSize = 768" in source
    assert "static let learningRate = Float(1e-4)" in source
    assert "static let minimumLearningRate = Float(4e-5)" in source
    assert "static let minimumReplayToTrain = 10_000" in source
    assert "static let maxSamplesPerFrame = Float(20)" in source
    assert "static let targetSyncInterval = 2_500" in source
    assert "static let epsilonStart = Float(1.0)" in source
    assert "static let epsilonEnd = Float(0.01)" in source
    assert "static let epsilonDecayFrames = 500_000" in source
    assert "static let expertRatioStart = Float(0.50)" in source
    assert "static let expertRatioEnd = Float(0.02)" in source
    assert "static let expertRatioDecayFrames = 5_000_000" in source
    assert "static let expertBCInitialWeight = Float(1.0)" in source
    assert "static let expertBCMinimumWeight = Float(0.001)" in source
    assert "static let expertBCDecayStart = 500_000" in source
    assert "static let expertBCDecayFrames = 2_000_000" in source
    assert "static let preDeathLookback = 120" in source
    assert "static let preDeathPriorityBoost = Float(2.0)" in source
    assert "importanceWeightedC51Loss" in source
    assert "logSoftmax(logits, axis: -1)" in source
    assert "greedyActionIndices" in source
    assert "expertBCWeight(forFrameCount" in source
