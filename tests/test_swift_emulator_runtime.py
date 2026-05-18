from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_swift_emulator_runtime_scaffold_exists():
    romset = (ROOT / "TempestAI" / "Emulator" / "TempestROMSet.swift").read_text()
    memory = (ROOT / "TempestAI" / "Emulator" / "TempestMemoryBus.swift").read_text()
    machine = (ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift").read_text()
    cpu = (ROOT / "TempestAI" / "Emulator" / "MOS6502.swift").read_text()
    avg = (ROOT / "TempestAI" / "Emulator" / "TempestAVG.swift").read_text()
    protocol = (
        ROOT / "TempestAI" / "Emulator" / "TempestAgentProtocol.swift"
    ).read_text()

    assert "136002-113.d1" in romset
    assert "136002-122.r1" in romset
    assert "136002-123.np3" in romset
    assert "136002-124.r3" in romset
    assert "Insecure.SHA1.hash" in romset
    assert "loadEAROM" in romset
    assert "earomURL" in romset
    assert "PythonBackend/roms" not in romset
    assert ".applicationSupportDirectory" in romset
    assert "defaultEAROM" in romset
    assert "0x3f" in romset

    assert "0x2000...0x2fff" in memory
    assert "displayVectorRAM" in memory
    assert "vectorFrameSerial" in memory
    assert "displayVectorRAM = vectorRAM" in memory
    assert "0x3000...0x3fff" in memory
    assert "case 0x0c00:" in memory
    assert "AVG done/HALT is active-high" in memory
    assert "0x6000...0x603f" in memory
    assert "earomAddress" in memory
    assert "earomControl" in memory
    assert "earomDirty" in memory
    assert "earomSnapshot" in memory
    assert "highScoreInitials" in memory
    assert "func applyInput" in memory
    assert "var dsw1: UInt8 = 0x02" in memory
    assert "ram[0x0050]" in memory
    assert "0x60c0...0x60cf" in memory
    assert "0x60d0...0x60df" in memory
    assert "0x9000...0xdfff" in memory
    assert "0xe000...0xffff" in memory

    assert "final class MOS6502" in cpu
    assert "func reset()" in cpu
    assert "func irq()" in cpu
    assert "func step()" in cpu
    assert "unimplementedOpcode" in cpu

    assert "final class TempestAVG" in avg
    assert "renderVectorFrame" in avg
    assert "AVGState" in avg
    assert "stateAddress()" in avg
    assert "addTempestPoint" in avg
    assert "final class TempestMathbox" in avg
    assert "func status()" in avg
    assert "func lo()" in avg
    assert "func hi()" in avg
    assert "func write(offset rawOffset:" in avg

    assert "final class TempestMachine" in machine
    assert "avg.renderVectorFrame(vectorRAM: bus.displayVectorRAM" in machine
    assert "irqPeriodCycles: UInt64 = 6_144" in machine
    assert "final class SwiftTempestRuntime" in machine
    assert "TempestROMSet.load()" in machine
    assert "TempestMachine(clientID:" in machine
    assert "agentFramePacket" in machine
    assert "bus.applyInput(input)" in machine
    assert "SwiftTempestLearner" in machine
    assert "coin1: scriptedCoin" in machine
    assert "DispatchSourceTimer" in machine
    assert "tempest.swift-emulator.runtime" in machine
    assert "func prepareLearnerState()" in machine
    assert "status = learner.loadPersistentState()" in machine
    assert "learner.actions(" in machine
    assert "learner.observeTransition(" in machine
    assert "private static func reward(" in machine
    assert "policyFrame: TempestPolicyFrame" in machine
    assert "laneSafetyReward" in machine
    assert "laneHasNearbyThreat" in machine
    assert "$0.depth <= 0x80" in machine
    assert "self.learner.clearReplay()" in machine
    assert "_ = self.learner.savePersistentState()" in machine
    assert 'self.publish(status: "Swift learner examples cleared")' in machine
    assert "automationGamestate()" in machine
    assert "let isLevelSelect = gamestate == 0x16" in machine
    assert "fire: isLevelSelect || (frame > 165 && action.fire)" in machine
    assert "bootstrapSpinner" not in machine
    assert "policyFrame()" in machine
    assert "let shouldPublishFrames = now.timeIntervalSince(lastFramePublish) >= renderPublishInterval" in machine
    assert "renderPublishInterval" in machine
    assert "savePersistentState" in machine
    assert "saveEAROMIfNeeded" in machine
    assert "includeVectors: Bool" in machine
    assert "shouldPublishFrames" in machine
    assert "simulationFramesPerTick" in machine
    assert "TEMPEST_SIM_FRAMES_PER_TICK" in machine
    assert "for simStep in 0..<simulationFramesPerTick" in machine
    assert "if isLastSimulationStep {\n                    let policyFrame" in machine
    assert "frame: policyFrame" in machine
    assert "private func currentPlayerLevelIndex()" in machine
    assert "private func currentGeometryLevelIndex()" in machine
    assert "displayLevel: playerLevelIndex + 1" in machine
    assert "romLevelIndex: playerLevelIndex" in machine
    assert "geometryLevelIndex: geometryLevelIndex" in machine
    assert "Int(bus.ram[0x0046])" in machine
    assert "Int(bus.ram[0x009f])" in machine
    assert "displayLevel: Int(bus.ram[0x46]) + 1" not in machine

    assert "struct TempestAgentAction" in protocol
    assert "struct TempestAgentFrameEncoder" in protocol
    assert "values.reserveCapacity(195)" in protocol
    assert "if values.count < 195" in protocol
    assert "betweenProgress" in protocol
    assert "tempestAngle" in protocol
    assert "let levelNumber = Int(byte(ram, 0x009f))" in protocol
    assert "small(min(Int(byte(ram, 0x0046)), 98), 98)" not in protocol
    assert "enemyDepths[i] == 0x10" in protocol
    assert "enemyTypes[i] == 1 || enemyTypes[i] == 0" in protocol
    assert "Darwin.connect" not in protocol


def test_swift_runtime_avoids_json_frame_conversion_in_hot_path():
    emulator_types = (
        ROOT / "TempestAI" / "Emulator" / "TempestEmulatorTypes.swift"
    ).read_text()
    game_frame = (ROOT / "TempestAI" / "GameFrameData.swift").read_text()
    renderer = (ROOT / "TempestAI" / "GameDisplayView.swift").read_text()
    metal_renderer = (ROOT / "TempestAI" / "MetalVectorDisplayView.swift").read_text()

    assert "GameFrameData(" in emulator_types
    assert "JSONSerialization" not in emulator_types
    assert "JSONDecoder" not in emulator_types
    assert "init(\n        clientID: Int" in game_frame
    assert "rendersAsynchronously: true" in renderer
    assert "opaque: true" in renderer
    assert "strokeGroups" in renderer
    assert "colorKey(argb:" in renderer
    assert "TEMPEST_CANVAS_FALLBACK" in renderer
    assert 'environment["TEMPEST_CANVAS_FALLBACK"] != "1"' in renderer
    assert "useMetalRenderer && !frame.vectorLines.isEmpty" in renderer
    assert "MetalVectorDisplayView(frame: frame)" in renderer
    assert "struct MetalVectorDisplayView: NSViewRepresentable" in metal_renderer
    assert "MTKView" in metal_renderer
    assert "private var lineBuffer: MTLBuffer?" in metal_renderer
    assert "MetalVectorLineRecord" in metal_renderer
    assert "TEMPEST_VECTOR_LINE_WIDTH" in metal_renderer
    assert "TEMPEST_VECTOR_DOT_RADIUS" in metal_renderer
    assert "lineBuffer.contents().copyMemory" in metal_renderer
    assert "setVertexBytes(" in metal_renderer
    assert "&uniforms" in metal_renderer
    assert "drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: lineCount * 6)" in metal_renderer
    assert "MetalVectorViewport" in metal_renderer
    assert "TEMPEST_CANVAS_VECTOR_GLOW" in renderer


def test_app_runtime_uses_swift_rom_runtime_by_default():
    swift_runtime = (
        ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift"
    ).read_text()
    controller = (ROOT / "TempestAI" / "TempestRuntimeController.swift").read_text()
    build_script = (ROOT / "build_app.sh").read_text()

    assert "SwiftTempestRuntime.shared" in controller
    assert "Starting self-contained Swift/Metal runtime" in controller
    assert "handleSwiftRuntimeCommand" in controller
    assert "Process()" not in controller
    assert "NWConnection" not in controller
    assert "main.py" not in build_script
    assert "Scripts/*.lua" not in build_script
    assert "requirements.txt" not in build_script
    assert "PythonBackend" not in build_script
    assert "MAME" not in swift_runtime
    assert "displayPID" not in controller
    assert "hideExternalProcess" not in controller
    assert "NSRunningApplication" not in controller


def test_swift_emulator_runtime_uses_in_process_ai_learner():
    controller = (ROOT / "TempestAI" / "TempestRuntimeController.swift").read_text()
    launcher = (ROOT / "run_swift_emulator_app.sh").read_text()
    metrics = (ROOT / "TempestAI" / "MetricsData.swift").read_text()
    learner = (
        ROOT / "TempestAI" / "Emulator" / "SwiftTempestLearner.swift"
    ).read_text()
    machine = (
        ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift"
    ).read_text()
    training_primitives = (
        ROOT / "TempestAI" / "Emulator" / "SwiftRainbowTrainingPrimitives.swift"
    ).read_text()

    assert "handleSwiftRuntimeCommand" in controller
    assert "SwiftTempestRuntime.shared" in controller
    assert "AI: Swift in-process policy/learner" in controller
    assert "swiftRuntime.prepareLearnerState()" in controller
    assert "userFacingStatus(for: swiftRuntime.status, frames: frames)" in controller
    assert 'return frames.isEmpty ? "Swift runtime ready" : "Swift emulator running"' in controller
    assert "swiftRuntime.savePersistentState" in controller
    assert "swiftRuntime.stop(wait: true)" in controller
    assert "stopSwiftRuntimeBackend" not in controller
    assert "signalChildProcesses" not in controller
    assert "Process()" not in controller
    assert "gameFramesByClientID = frames" in controller
    assert "metrics.gameCount = frames.count" in controller
    assert "metrics.aiRuntimeStatus = learner.neuralRuntimeStatus" in controller
    assert "metrics.mlxOptimizerSteps = learner.optimizerStep" in controller
    assert "metrics.simFramesPerSecond = runtimePerformance.simFramesPerSecond" in controller
    assert "metrics.replaySampleMS = learner.replaySampleMS" in controller
    assert "metrics.optimizerMS = learner.optimizerMS" in controller
    assert "let scoringFrames = frames.filter { $0.score > 0 && !$0.gameOver }" in controller
    assert "if let maxLevel = scoringFrames.map(\\.displayLevel).max()" in controller
    assert "var gameCount: Int = 0" in metrics
    assert "var mlxOptimizerSteps: Int = 0" in metrics
    assert "var aiRuntimeStatus: String = \"Swift AI\"" in metrics
    assert "var simFramesPerSecond: Double = 0" in metrics
    assert "var optimizerMS: Double = 0" in metrics
    assert "var trainingInFlight: Bool = false" in metrics
    assert 'case gameCount = "client_count"' in metrics
    assert 'case mlxOptimizerSteps = "mlx_optimizer_steps"' in metrics
    assert 'case aiRuntimeStatus = "ai_runtime_status"' in metrics
    assert "var clientCount" not in metrics
    assert "final class SwiftTempestLearner" in learner
    assert "TempestPolicyFrame" in learner
    assert "var openLevel: Bool = false" in learner
    assert "var spikeDepths: [Int] = []" in learner
    assert "var pulsing: Int = 0" in learner
    assert "var shotCount: Int = 0" in learner
    assert "var superzapperUses: Int = 0" in learner
    assert "var enemiesPending: Int = 0" in learner
    assert "enum TempestActionSpace" in learner
    assert "spinnerLevels = [0, 12, 9, 6, 3, 1, -1, -3, -6, -9, -12]" in learner
    assert "static let actionCount = fireZapCount * spinnerLevels.count" in learner
    assert "static func split(_ jointIndex: Int)" in learner
    assert "static func action(for jointIndex: Int)" in learner
    assert "loadPersistentState()" in learner
    assert "loadBundledSeed()" in learner
    assert "mergeTrainingFloor(from: bundledSeed)" in learner
    assert "loaded saved Swift learner state + bundled training floor" in learner
    assert "savePersistentState()" in learner
    assert "swift_learner_seed.json" in learner
    assert "SwiftTensorPackage.bundled()" in learner
    assert "learner_state.json" in learner
    assert "SwiftReplayTransition" in training_primitives
    assert "SwiftPrioritizedReplayMemory" in training_primitives
    assert "SwiftNStepReplayBuffer" in training_primitives
    assert "SwiftC51Projection" in training_primitives
    assert "private var recentReplayIndicesByGameID: [Int: [Int]] = [:]" in learner
    assert "observeTransition(" in learner
    assert "trainFromReplayIfReady()" in learner
    assert "let index = replay.append(transition)" in learner
    assert "rememberRecentReplayIndex(index, sourceGameID: sourceGameID)" in learner
    assert "if done {\n                boostPreDeathPriorities(sourceGameID: sourceGameID)" in learner
    assert "private func rememberRecentReplayIndex(_ index: Int, sourceGameID: Int)" in learner
    assert "private func boostPreDeathPriorities(sourceGameID: Int)" in learner
    assert "MLXRainbowTrainingOps.preDeathPriorityBoost" in learner
    assert "recentReplayIndicesByGameID.removeAll(keepingCapacity: true)" in learner
    assert "sample(batchSize: Int, beta: Float)" in training_primitives
    assert "@discardableResult\n    func append(_ transition: SwiftReplayTransition) -> Int" in training_primitives
    assert "func boostPriorities(indices: [Int], factor: Float)" in training_primitives
    assert "replay.sample(\n            batchSize: MLXRainbowTrainingOps.batchSize" in learner
    assert "trainingQueue.async" in learner
    assert "performTrainingStep(" in learner
    assert "valueAndGrad(model: onlineRainbowModel)" in learner
    assert "optimizer.update(model: onlineRainbowModel, gradients: clippedGradients)" in learner
    assert "func actions(\n        for requests:" in learner
    assert "learner.actions(\n                for: policyRequests.map" in machine
    assert "actionBiases" not in learner
    assert "bestBiasedActionIndex" not in learner
    assert "defensiveEscapeAction" in learner
    assert "zoomEscapeAction" in learner
    assert "preferredColumnTarget" in learner
    assert "nearestSafeLane" in learner
    assert "isDangerLane" in learner
    assert "relativeDelta(" in learner
    assert "$0.depth == 0x10" in learner
    assert "$0.depth <= 0x60" in learner
    assert "sidestepAction(awayFromRelativeLane:" in learner
    assert "shouldSuperzap(frame:" in learner
    assert "frame.superzapperUses == 0" in learner
    assert "topRailCount >= 3 || frame.enemiesPending == 0" in learner
    assert "topRailCount >= 1 || frame.enemiesPending == 0" in learner
    assert "bus.ram[0x0111] != 0" in machine
    assert "spikeDepths = (0..<16).map" in machine
    assert "bus.ram[0x0147]" in machine
    assert "bus.ram[0x0135]" in machine
    assert "bus.ram[0x03aa]" in machine
    assert "bus.ram[0x03ab]" in machine
    assert "TEMPEST_SWIFT_EMULATOR" not in launcher


def test_swift_runtime_decouples_simulation_from_render_publish():
    machine = (ROOT / "TempestAI" / "Emulator" / "TempestMachine.swift").read_text()

    assert "TEMPEST_MAX_SPEED_TRAINING" in machine
    assert "TEMPEST_RENDER_PUBLISH_INTERVAL" in machine
    assert "let interval: DispatchTimeInterval = maxSpeedTraining" in machine
    assert "repeating: interval" in machine
    assert "lastFramePublish" in machine
    assert "now.timeIntervalSince(lastFramePublish) >= renderPublishInterval" in machine
    assert "SwiftRuntimePerformanceSnapshot" in machine
    assert "simFramesPerSecond" in machine


def test_saved_swift_learner_state_cannot_downgrade_bundled_training_seed():
    learner = (
        ROOT / "TempestAI" / "Emulator" / "SwiftTempestLearner.swift"
    ).read_text()

    assert "private func mergeTrainingFloor(from state: PersistentState)" in learner
    assert "var clearedTrainingFloor: Bool?" in learner
    assert "private var clearedTrainingFloor = false" in learner
    assert "if clearedTrainingFloor" in learner
    assert "clearedTrainingFloor = true" in learner
    assert 'loadedSource = "cleared_user_state"' in learner
    assert "clearedTrainingFloor: clearedTrainingFloor" in learner
    assert "guard !clearedTrainingFloor else { return }" in learner
    assert "replayCount = max(replayCount, max(0, state.replayCount))" in learner
    assert "trainingSteps = max(trainingSteps, max(0, state.trainingSteps))" in learner
    assert "if state.version >= 3" in learner
    assert "optimizerStep = state.version >= 3" in learner
    assert 'if loadedSource == "defaults"' in learner
    assert 'loadedSource = "saved_state_plus_bundled_seed"' in learner


def test_swift_only_ui_does_not_expose_transitional_runtime_language():
    ui_sources = "\n".join(
        path.read_text()
        for path in (ROOT / "TempestAI").glob("*.swift")
    )

    forbidden_user_phrases = [
        "Python backend",
        "Connected to Python",
        "MAME RAM",
        "MAME vectors",
        "random moves",
        "coach assist",
        "Reset Random",
        "Practice Burst",
        "Clients:",
    ]
    for phrase in forbidden_user_phrases:
        assert phrase not in ui_sources

    assert "Original ROM RAM" in ui_sources
    assert "Swift AVG" in ui_sources
    assert "External processes" in ui_sources
    assert "Reset Explore" in ui_sources
    assert "Explore Burst" in ui_sources


def test_legacy_original_runtime_is_removed_from_repository():
    legacy_root_names = [
        "Scripts",
        "LUAScripts",
        "Code",
        "tools",
        "audio",
        "cfg",
        "snap",
        "benchmark_reports",
        "requirements.txt",
        "startmame.sh",
        "run_macos_app.sh",
        "run_control_center.sh",
    ]
    for name in legacy_root_names:
        assert not (ROOT / name).exists()

    assert not (ROOT / "archive").exists()
    assert not (ROOT / "models" / "tempest_model_latest.pt").exists()
    assert (ROOT / "build" / "Tempest AI.app").is_dir()


def test_build_creates_swift_native_learner_seed():
    build_script = (ROOT / "build_app.sh").read_text()
    tensor_package = (
        ROOT / "TempestAI" / "Emulator" / "SwiftTensorPackage.swift"
    ).read_text()
    rainbow_model = (
        ROOT / "TempestAI" / "Emulator" / "SwiftRainbowModel.swift"
    ).read_text()

    assert "swift_learner_seed.json" in build_script
    assert "models/swift_tensors" in build_script
    assert "mlx.metallib" in build_script
    assert "cmake --build .build/mlx-cmake --target mlx-metallib" in build_script
    assert "MLX metallib not found" in build_script
    assert "APP_SUPPORT_STATE=" in build_script
    assert "LEARNER_WAS_CLEARED" in build_script
    assert "Intentional learner reset detected; bundling fresh Swift learner seed" in build_script
    assert "roms/tempest1/*" in build_script
    assert "cp -R roms/*" not in build_script
    assert '"checkpointHash": tensor_metadata.get("checkpoint_sha256")' in build_script
    assert '"replayCount": 0' in build_script
    assert '"trainingSteps": 0 if cleared else int(tensor_metadata.get("total_training_steps", 0) or 0)' in build_script
    assert '"optimizerStep": 0' in build_script
    assert '"trainingEnabled": True' in build_script
    assert '"epsilon": 1.0 if cleared else float(tensor_metadata.get("epsilon", 0.01) or 0.01)' in build_script
    assert '"expertRatio": 0.50 if cleared else float(tensor_metadata.get("expert_ratio", 0.02) or 0.02)' in build_script
    assert '"clearedTrainingFloor": cleared' in build_script
    assert "tempest_model_latest.pt" not in build_script
    assert "tempest_model_latest_replay" not in build_script
    assert "stateSize == 195" in tensor_package
    assert "actionCount == TempestActionSpace.actionCount" in tensor_package
    assert "final class SwiftRainbowModel" in rainbow_model
    assert "_lane_sin_pos" in rainbow_model
    assert "lane_cross_attn.cross_attn.in_proj_weight" in rainbow_model
    assert "laneCrossAttention(state:" in rainbow_model
    assert "buildLaneTokens(state:" in rainbow_model
    assert "buildEnemyTokens(state:" in rainbow_model
    assert "inProjection(_ vector:" in rainbow_model
    assert "repeatElement(Float(0), count: 128)" not in rainbow_model
    assert "trunk.0.weight" in rainbow_model
    assert "adv_out.weight" in rainbow_model
    assert "val_out.weight" in rainbow_model
    assert "TempestActionSpace.action(for: bestAction)" in rainbow_model
