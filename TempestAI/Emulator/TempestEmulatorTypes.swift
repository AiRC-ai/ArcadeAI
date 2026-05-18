import Foundation

struct TempestVectorLine: Equatable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    var argb: UInt32
    var intensity: Int
}

struct TempestInputState: Equatable {
    var coin1: Bool = false
    var start1: Bool = false
    var fire: Bool = false
    var zap: Bool = false
    var spinnerDelta: Int = 0
}

struct TempestSnapshot: Equatable {
    var clientID: Int
    var frame: Int
    var score: Int
    var highScore: Int
    var highScoreInitials: String
    var displayLevel: Int
    var romLevelIndex: Int
    var geometryLevelIndex: Int
    var gamestate: Int
    var lives: Int
    var vectorWidth: Int
    var vectorHeight: Int
    var vectorLines: [TempestVectorLine]
    var runtimeStatus: String

    static func empty(clientID: Int, status: String) -> TempestSnapshot {
        TempestSnapshot(
            clientID: clientID,
            frame: 0,
            score: 0,
            highScore: 0,
            highScoreInitials: "",
            displayLevel: 1,
            romLevelIndex: 0,
            geometryLevelIndex: 0,
            gamestate: 0,
            lives: 0,
            vectorWidth: 581,
            vectorHeight: 571,
            vectorLines: [],
            runtimeStatus: status
        )
    }
}

extension TempestSnapshot {
    func gameFrameData(fps: Double = 60.0) -> GameFrameData {
        GameFrameData(
            clientID: clientID,
            frame: frame,
            score: score,
            highScore: highScore,
            highScoreInitials: highScoreInitials,
            level: displayLevel,
            displayLevel: displayLevel,
            romLevelIndex: romLevelIndex,
            geometryLevelIndex: geometryLevelIndex,
            gamestate: gamestate,
            lives: lives,
            fps: fps,
            renderer: vectorLines.isEmpty ? "swift_emulator_bootstrap" : "swift_avg_vector",
            vectorWidth: Double(vectorWidth),
            vectorHeight: Double(vectorHeight),
            vectorLines: vectorLines.map {
                GameVectorLineData(
                    x0: $0.x0,
                    y0: $0.y0,
                    x1: $0.x1,
                    y1: $0.y1,
                    argb: $0.argb,
                    intensity: $0.intensity
                )
            },
            tubeAngles: Array(repeating: 0.0, count: 16),
            spikes: Array(repeating: 0.0, count: 16)
        )
    }
}
