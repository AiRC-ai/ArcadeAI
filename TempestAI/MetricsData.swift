import Foundation

/// Live training metrics received from the AI learner/runtime.
struct MetricsData: Codable, Equatable {
    var frameCount: Int = 0
    var totalTrainingSteps: Int = 0
    var mlxOptimizerSteps: Int = 0
    var fps: Double = 0
    var epsilon: Double = 1.0
    var expertRatio: Double = 0.5
    var memoryBufferSize: Int = 0
    var gameCount: Int = 0
    var loss: Double = 0
    var gradNorm: Double = 0
    var qMean: Double = 0
    var agreement: Double = 0
    var peakGameScore: Int = 0
    var peakLevel: Int = 0
    var episodes: Int = 0
    var averageLevel: Double = 0
    var trainingEnabled: Bool = true
    var expertMode: Bool = false
    var authenticGameplay: Bool = false
    var originalGameStatus: String = "Original game not checked"
    var originalGameDetail: String = ""
    var romName: String = "tempest1"
    var runtimePid: Int = 0
    var runtimeHeadless: Bool = true
    var debugWindow: Bool = false
    var scoreSource: String = "Original ROM RAM"
    var highScoreSource: String = "Original EAROM/RAM"
    var rendererRole: String = "Swift AVG vectors"
    var aiRuntimeStatus: String = "Swift AI"
    var romHighScore: Int = 0
    var simFramesPerSecond: Double = 0
    var runtimeTickMS: Double = 0
    var emulatorStepMS: Double = 0
    var inferenceMS: Double = 0
    var replaySampleMS: Double = 0
    var trainingBatchMS: Double = 0
    var optimizerMS: Double = 0
    var learnerUpdatesPerSecond: Double = 0
    var renderPublishFPS: Double = 0
    var droppedFrames: Int = 0
    var trainingInFlight: Bool = false

    enum CodingKeys: String, CodingKey {
        case frameCount = "frame_count"
        case totalTrainingSteps = "total_training_steps"
        case mlxOptimizerSteps = "mlx_optimizer_steps"
        case fps
        case epsilon
        case expertRatio = "expert_ratio"
        case memoryBufferSize = "memory_buffer_size"
        case gameCount = "client_count"
        case loss
        case gradNorm = "grad_norm"
        case qMean = "q_mean"
        case agreement
        case peakGameScore = "peak_game_score"
        case peakLevel = "peak_level"
        case episodes
        case averageLevel = "average_level"
        case trainingEnabled = "training_enabled"
        case expertMode = "expert_mode"
        case authenticGameplay = "authentic_gameplay"
        case originalGameStatus = "original_game_status"
        case originalGameDetail = "original_game_detail"
        case romName = "rom_name"
        case runtimePid = "runtime_pid"
        case runtimeHeadless = "runtime_headless"
        case debugWindow = "debug_window"
        case scoreSource = "score_source"
        case highScoreSource = "high_score_source"
        case rendererRole = "renderer_role"
        case aiRuntimeStatus = "ai_runtime_status"
        case romHighScore = "rom_high_score"
        case simFramesPerSecond = "sim_frames_per_second"
        case runtimeTickMS = "runtime_tick_ms"
        case emulatorStepMS = "emulator_step_ms"
        case inferenceMS = "inference_ms"
        case replaySampleMS = "replay_sample_ms"
        case trainingBatchMS = "training_batch_ms"
        case optimizerMS = "optimizer_ms"
        case learnerUpdatesPerSecond = "learner_updates_per_second"
        case renderPublishFPS = "render_publish_fps"
        case droppedFrames = "dropped_frames"
        case trainingInFlight = "training_in_flight"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frameCount = try c.decodeIfPresent(Int.self, forKey: .frameCount) ?? 0
        totalTrainingSteps = try c.decodeIfPresent(Int.self, forKey: .totalTrainingSteps) ?? 0
        mlxOptimizerSteps = try c.decodeIfPresent(Int.self, forKey: .mlxOptimizerSteps) ?? 0
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? 0
        epsilon = try c.decodeIfPresent(Double.self, forKey: .epsilon) ?? 1.0
        expertRatio = try c.decodeIfPresent(Double.self, forKey: .expertRatio) ?? 0.5
        memoryBufferSize = try c.decodeIfPresent(Int.self, forKey: .memoryBufferSize) ?? 0
        gameCount = try c.decodeIfPresent(Int.self, forKey: .gameCount) ?? 0
        loss = try c.decodeIfPresent(Double.self, forKey: .loss) ?? 0
        gradNorm = try c.decodeIfPresent(Double.self, forKey: .gradNorm) ?? 0
        qMean = try c.decodeIfPresent(Double.self, forKey: .qMean) ?? 0
        agreement = try c.decodeIfPresent(Double.self, forKey: .agreement) ?? 0
        peakGameScore = try c.decodeIfPresent(Int.self, forKey: .peakGameScore) ?? 0
        peakLevel = try c.decodeIfPresent(Int.self, forKey: .peakLevel) ?? 0
        episodes = try c.decodeIfPresent(Int.self, forKey: .episodes) ?? 0
        averageLevel = try c.decodeIfPresent(Double.self, forKey: .averageLevel) ?? 0
        trainingEnabled = try c.decodeIfPresent(Bool.self, forKey: .trainingEnabled) ?? true
        expertMode = try c.decodeIfPresent(Bool.self, forKey: .expertMode) ?? false
        authenticGameplay = try c.decodeIfPresent(Bool.self, forKey: .authenticGameplay) ?? false
        originalGameStatus = try c.decodeIfPresent(String.self, forKey: .originalGameStatus) ?? "Original game not checked"
        originalGameDetail = try c.decodeIfPresent(String.self, forKey: .originalGameDetail) ?? ""
        romName = try c.decodeIfPresent(String.self, forKey: .romName) ?? "tempest1"
        runtimePid = try c.decodeIfPresent(Int.self, forKey: .runtimePid) ?? 0
        runtimeHeadless = try c.decodeIfPresent(Bool.self, forKey: .runtimeHeadless) ?? true
        debugWindow = try c.decodeIfPresent(Bool.self, forKey: .debugWindow) ?? false
        scoreSource = try c.decodeIfPresent(String.self, forKey: .scoreSource) ?? "Original ROM RAM"
        highScoreSource = try c.decodeIfPresent(String.self, forKey: .highScoreSource) ?? "Original EAROM/RAM"
        rendererRole = try c.decodeIfPresent(String.self, forKey: .rendererRole) ?? "Swift AVG vectors"
        aiRuntimeStatus = try c.decodeIfPresent(String.self, forKey: .aiRuntimeStatus) ?? "Swift AI"
        romHighScore = try c.decodeIfPresent(Int.self, forKey: .romHighScore) ?? 0
        simFramesPerSecond = try c.decodeIfPresent(Double.self, forKey: .simFramesPerSecond) ?? 0
        runtimeTickMS = try c.decodeIfPresent(Double.self, forKey: .runtimeTickMS) ?? 0
        emulatorStepMS = try c.decodeIfPresent(Double.self, forKey: .emulatorStepMS) ?? 0
        inferenceMS = try c.decodeIfPresent(Double.self, forKey: .inferenceMS) ?? 0
        replaySampleMS = try c.decodeIfPresent(Double.self, forKey: .replaySampleMS) ?? 0
        trainingBatchMS = try c.decodeIfPresent(Double.self, forKey: .trainingBatchMS) ?? 0
        optimizerMS = try c.decodeIfPresent(Double.self, forKey: .optimizerMS) ?? 0
        learnerUpdatesPerSecond = try c.decodeIfPresent(Double.self, forKey: .learnerUpdatesPerSecond) ?? 0
        renderPublishFPS = try c.decodeIfPresent(Double.self, forKey: .renderPublishFPS) ?? 0
        droppedFrames = try c.decodeIfPresent(Int.self, forKey: .droppedFrames) ?? 0
        trainingInFlight = try c.decodeIfPresent(Bool.self, forKey: .trainingInFlight) ?? false
    }
}
