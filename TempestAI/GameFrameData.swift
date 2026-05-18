import Foundation

/// A compact, renderable view of the latest Tempest frame emitted by the
/// in-process Swift ROM runtime.
struct GameFrameData: Codable, Equatable {
    var clientID: Int
    var frame: Int
    var score: Int
    var highScore: Int
    var highScoreInitials: String
    var level: Int
    var displayLevel: Int
    var romLevelIndex: Int
    var geometryLevelIndex: Int
    var gamestate: Int
    var done: Bool
    var lifeLost: Bool
    var gameOver: Bool
    var lives: Int
    var fps: Double?
    var renderer: String
    var vectorWidth: Double
    var vectorHeight: Double
    var vectorLines: [GameVectorLineData]
    var openLevel: Bool
    var playerLane: Double
    var playerAlive: Bool
    var playerDepth: Double
    var superzapperUses: Int
    var remainingShots: Int
    var tubeAngles: [Double]
    var spikes: [Double]
    var enemies: [GameEnemyData]
    var playerShots: [GameShotData]
    var enemyShots: [GameShotData]

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case frame
        case score
        case highScore = "high_score"
        case highScoreInitials = "high_score_initials"
        case level
        case displayLevel = "display_level"
        case romLevelIndex = "rom_level_index"
        case geometryLevelIndex = "geometry_level_index"
        case gamestate
        case done
        case lifeLost = "life_lost"
        case gameOver = "game_over"
        case lives
        case fps
        case renderer
        case vectorWidth = "vector_width"
        case vectorHeight = "vector_height"
        case vectorLines = "vector_lines"
        case openLevel = "open_level"
        case playerLane = "player_lane"
        case playerAlive = "player_alive"
        case playerDepth = "player_depth"
        case superzapperUses = "superzapper_uses"
        case remainingShots = "remaining_shots"
        case tubeAngles = "tube_angles"
        case spikes
        case enemies
        case playerShots = "player_shots"
        case enemyShots = "enemy_shots"
    }

    init(
        clientID: Int,
        frame: Int,
        score: Int,
        highScore: Int = 0,
        highScoreInitials: String = "",
        level: Int = 1,
        displayLevel: Int? = nil,
        romLevelIndex: Int? = nil,
        geometryLevelIndex: Int? = nil,
        gamestate: Int = 0,
        done: Bool = false,
        lifeLost: Bool = false,
        gameOver: Bool = false,
        lives: Int = 0,
        fps: Double? = nil,
        renderer: String = "synthetic_fallback",
        vectorWidth: Double = 0,
        vectorHeight: Double = 0,
        vectorLines: [GameVectorLineData] = [],
        openLevel: Bool = false,
        playerLane: Double = 0,
        playerAlive: Bool = true,
        playerDepth: Double = 0,
        superzapperUses: Int = 0,
        remainingShots: Int = 0,
        tubeAngles: [Double] = [],
        spikes: [Double] = [],
        enemies: [GameEnemyData] = [],
        playerShots: [GameShotData] = [],
        enemyShots: [GameShotData] = []
    ) {
        self.clientID = clientID
        self.frame = frame
        self.score = score
        self.highScore = highScore
        self.highScoreInitials = highScoreInitials
        self.level = displayLevel ?? level
        self.displayLevel = displayLevel ?? level
        self.romLevelIndex = romLevelIndex ?? max(0, (displayLevel ?? level) - 1)
        self.geometryLevelIndex = geometryLevelIndex ?? self.romLevelIndex
        self.gamestate = gamestate
        self.done = done
        self.lifeLost = lifeLost
        self.gameOver = gameOver
        self.lives = lives
        self.fps = fps
        self.renderer = renderer
        self.vectorWidth = vectorWidth
        self.vectorHeight = vectorHeight
        self.vectorLines = vectorLines
        self.openLevel = openLevel
        self.playerLane = playerLane
        self.playerAlive = playerAlive
        self.playerDepth = playerDepth
        self.superzapperUses = superzapperUses
        self.remainingShots = remainingShots
        self.tubeAngles = tubeAngles
        self.spikes = spikes
        self.enemies = enemies
        self.playerShots = playerShots
        self.enemyShots = enemyShots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try c.decode(Int.self, forKey: .clientID)
        frame = try c.decode(Int.self, forKey: .frame)
        score = try c.decode(Int.self, forKey: .score)
        highScore = try c.decodeIfPresent(Int.self, forKey: .highScore) ?? 0
        highScoreInitials = try c.decodeIfPresent(String.self, forKey: .highScoreInitials) ?? ""
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        displayLevel = try c.decodeIfPresent(Int.self, forKey: .displayLevel) ?? level
        romLevelIndex = try c.decodeIfPresent(Int.self, forKey: .romLevelIndex) ?? max(0, displayLevel - 1)
        geometryLevelIndex = try c.decodeIfPresent(Int.self, forKey: .geometryLevelIndex) ?? romLevelIndex
        gamestate = try c.decodeIfPresent(Int.self, forKey: .gamestate) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        lifeLost = try c.decodeIfPresent(Bool.self, forKey: .lifeLost) ?? false
        gameOver = try c.decodeIfPresent(Bool.self, forKey: .gameOver) ?? false
        lives = try c.decodeIfPresent(Int.self, forKey: .lives) ?? 0
        fps = try c.decodeIfPresent(Double.self, forKey: .fps)
        renderer = try c.decodeIfPresent(String.self, forKey: .renderer) ?? "synthetic_fallback"
        vectorWidth = try c.decodeIfPresent(Double.self, forKey: .vectorWidth) ?? 0
        vectorHeight = try c.decodeIfPresent(Double.self, forKey: .vectorHeight) ?? 0
        vectorLines = try c.decodeIfPresent([GameVectorLineData].self, forKey: .vectorLines) ?? []
        openLevel = try c.decodeIfPresent(Bool.self, forKey: .openLevel) ?? false
        playerLane = try c.decodeIfPresent(Double.self, forKey: .playerLane) ?? 0
        playerAlive = try c.decodeIfPresent(Bool.self, forKey: .playerAlive) ?? true
        playerDepth = try c.decodeIfPresent(Double.self, forKey: .playerDepth) ?? 0
        superzapperUses = try c.decodeIfPresent(Int.self, forKey: .superzapperUses) ?? 0
        remainingShots = try c.decodeIfPresent(Int.self, forKey: .remainingShots) ?? 0
        tubeAngles = try c.decodeIfPresent([Double].self, forKey: .tubeAngles) ?? []
        spikes = try c.decodeIfPresent([Double].self, forKey: .spikes) ?? []
        enemies = try c.decodeIfPresent([GameEnemyData].self, forKey: .enemies) ?? []
        playerShots = try c.decodeIfPresent([GameShotData].self, forKey: .playerShots) ?? []
        enemyShots = try c.decodeIfPresent([GameShotData].self, forKey: .enemyShots) ?? []
        level = displayLevel
    }
}

struct GameVectorLineData: Codable, Equatable, Identifiable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    var argb: UInt32
    var intensity: Int

    var id: String {
        "\(x0),\(y0),\(x1),\(y1),\(argb),\(intensity)"
    }
}

struct GameEnemyData: Codable, Equatable, Identifiable {
    var slot: Int
    var type: Int
    var lane: Double
    var depth: Double
    var betweenSegments: Bool
    var movingAway: Bool
    var canShoot: Bool
    var topRail: Bool

    var id: Int { slot }

    enum CodingKeys: String, CodingKey {
        case slot
        case type
        case lane
        case depth
        case betweenSegments = "between_segments"
        case movingAway = "moving_away"
        case canShoot = "can_shoot"
        case topRail = "top_rail"
    }
}

struct GameShotData: Codable, Equatable, Identifiable {
    var slot: Int
    var lane: Double
    var depth: Double

    var id: Int { slot }
}
