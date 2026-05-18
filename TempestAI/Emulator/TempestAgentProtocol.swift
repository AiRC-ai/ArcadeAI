import Foundation

struct TempestAgentAction: Equatable {
    var fire: Bool = false
    var zap: Bool = false
    var spinner: Int = 0
    var startAdvanced: Bool = false
    var startLevelMinimum: Int = 1
}

struct TempestAgentFrameEncoder {
    private static let invalidSegment = -32768
    private static let topRailAbsent = 255

    private var previousEnemySegments = Array(repeating: invalidSegment, count: 7)
    private var previousEnemyDepths = Array(repeating: 0, count: 7)
    private var previousEnemyTypes = Array(repeating: 0, count: 7)

    mutating func encode(
        ram: [UInt8],
        frameNumber: Int,
        commanded: TempestAgentAction
    ) -> Data {
        let state = stateVector(ram: ram)
        var data = Data()

        let gamestate = byte(ram, 0x0000)
        let gameMode = byte(ram, 0x0005)
        let lives = min(6, Int(byte(ram, 0x0048)))
        let score = scoreBCD(ram, 0x0040)
        let highScore = scoreBCD(ram, 0x071b)
        let initials = highScoreInitialBytes(ram)
        let playerSeg = byte(ram, 0x0200) & 0x0f
        let openLevel = byte(ram, 0x0111) != 0
        let level = byte(ram, 0x009f)
        let gameOver = gamestate == 0x12 || (((gameMode & 0x80) == 0) && score > 0 && lives == 0)

        data.appendUInt16BE(UInt16(state.count))
        data.appendDoubleBE(0.0)
        data.appendDoubleBE(0.0)
        data.appendUInt8(gamestate)
        data.appendUInt8(gameMode)
        data.appendUInt8(0)
        data.appendUInt16BE(UInt16(frameNumber & 0xffff))
        data.appendUInt32BE(UInt32(score))
        data.appendUInt32BE(UInt32(highScore))
        data.appendUInt8(initials.0)
        data.appendUInt8(initials.1)
        data.appendUInt8(initials.2)
        data.appendUInt8(0)
        data.appendUInt8(gameOver ? 1 : 0)
        data.appendUInt8(UInt8(lives))
        data.appendUInt8(0)
        data.appendUInt8(commanded.fire ? 1 : 0)
        data.appendUInt8(commanded.zap ? 1 : 0)
        data.appendInt16BE(Int16(commanded.spinner))
        data.appendInt16BE(-1)
        data.appendUInt8(playerSeg)
        data.appendUInt8(openLevel ? 1 : 0)
        data.appendUInt8(0)
        data.appendUInt8(0)
        data.appendUInt8(level)
        for value in state {
            data.appendFloat32BE(value)
        }
        return data
    }

    mutating func stateVector(ram: [UInt8]) -> [Float] {
        let playerAbs = Int(byte(ram, 0x0200) & 0x0f)
        let open = byte(ram, 0x0111) != 0
        var values: [Float] = []
        values.reserveCapacity(195)

        func push(_ value: Float) {
            values.append(max(-1.0, min(1.0, value)))
        }
        func natural(_ address: Int) {
            push(Float(byte(ram, address)) / 255.0)
        }
        func small(_ value: Int, _ maxValue: Int) {
            guard maxValue > 0 else {
                push(0)
                return
            }
            push(Float(min(max(value, 0), maxValue)) / Float(maxValue))
        }
        func bool(_ value: Bool) {
            push(value ? 1.0 : 0.0)
        }
        func depth(_ value: Int) {
            push(Float(min(max(value, 0), 255)) / 255.0)
        }
        func fixed(_ intAddress: Int, _ fracAddress: Int? = nil) {
            let whole = Double(byte(ram, intAddress))
            let frac = fracAddress.map { Double(byte(ram, $0)) / 256.0 } ?? 0
            push(Float(min(256.0, max(0.0, whole + frac)) / 256.0))
        }
        func signed(_ value: Int, magnitude: Int) {
            guard magnitude > 0 else {
                push(0)
                return
            }
            let clamped = min(max(value, -magnitude), magnitude)
            push(Float(clamped) / Float(magnitude))
        }
        func rel(_ value: Double) {
            if Int(value) == Self.invalidSegment || Int(value) == Self.topRailAbsent {
                push(-1.0)
                return
            }
            push(Float(min(15.0, max(-15.0, value)) / 15.0))
        }
        func relativeSegment(_ abs: Int) -> Double {
            if abs < 0 { return Double(Self.invalidSegment) }
            if open {
                return Double(abs - playerAbs)
            }
            let cw = (abs - playerAbs + 16) % 16
            let ccw = (playerAbs - abs + 16) % 16
            if cw <= ccw {
                return Double(cw)
            }
            return Double(-ccw)
        }
        func signed16(lsb: Int, msb: Int) -> Int {
            var combined = Int(byte(ram, msb)) * 256 + Int(byte(ram, lsb))
            if combined > 32767 { combined -= 65536 }
            return combined
        }
        func tempestAngle(segAbs: Int, increasing: Bool) -> Int {
            let seg = segAbs & 0x0f
            if increasing {
                let previous = (seg + 15) & 0x0f
                return (Int(byte(ram, 0x03ee + previous) & 0x0f) + 8) & 0x0f
            }
            return Int(byte(ram, 0x03ee + seg) & 0x0f)
        }
        func betweenProgress(segAbs: Int, increasing: Bool, angleNibble: Int) -> Double {
            let start = tempestAngle(segAbs: segAbs, increasing: increasing)
            let target = tempestAngle(segAbs: segAbs, increasing: !increasing)
            let current = angleNibble & 0x0f
            let traveled: Int
            let total: Int
            if increasing {
                traveled = (start - current) & 0x0f
                total = (start - target) & 0x0f
            } else {
                traveled = (current - start) & 0x0f
                total = (target - start) & 0x0f
            }
            guard total > 0 else { return 0.0 }
            return min(1.0, max(0.0, Double(traveled) / Double(total)))
        }
        func wrapClosedRelative(_ value: Double) -> Double {
            var wrapped = value
            while wrapped > 8.0 { wrapped -= 16.0 }
            while wrapped < -8.0 { wrapped += 16.0 }
            return wrapped
        }

        small(Int(byte(ram, 0x0000)), 36)
        natural(0x0005)
        natural(0x0004)
        small(Int(byte(ram, 0x0048)), 6)
        let levelNumber = Int(byte(ram, 0x009f))
        small(min(levelNumber, 98), 98)

        small(playerAbs, 15)
        bool((byte(ram, 0x0201) & 0x80) == 0)
        small(Int(byte(ram, 0x0201) & 0x0f), 15)
        depth(Int(byte(ram, 0x0202)))
        small(Int(byte(ram, 0x03aa)), 2)
        small(min(Int(byte(ram, 0x0125)), 19), 19)
        small(8 - min(Int(byte(ram, 0x0135)), 8), 8)
        for i in 0..<8 { depth(Int(byte(ram, 0x02d3 + i))) }
        for i in 0..<8 {
            let shotDepth = byte(ram, 0x02d3 + i)
            if shotDepth == 0 {
                rel(Double(Self.invalidSegment))
            } else {
                rel(relativeSegment(Int(byte(ram, 0x02ad + i) & 0x0f)))
            }
        }

        small(min(levelNumber, 98), 98)
        bool(open)
        small(levelNumber % 16, 15)
        for i in 0..<16 {
            let raw = Int(byte(ram, 0x03ac + i))
            depth(raw == 0 ? 0 : 255 - raw)
        }
        for i in 0..<16 { small(Int(byte(ram, 0x03ee + i) & 0x0f), 15) }

        for address in [0x0142, 0x0143, 0x0144, 0x0145, 0x0146] {
            small(Int(byte(ram, address)), 7)
        }
        for address in [0x013d, 0x013e, 0x013f, 0x0140, 0x0141] {
            small(Int(byte(ram, address)), 7)
        }
        small(Int(byte(ram, 0x0108)), 7)
        small(Int(byte(ram, 0x0109)), 7)
        small(min(Int(byte(ram, 0x03ab)), 63), 63)
        small(min(Int(byte(ram, 0x00b2)), 40), 40)
        let pulse = Int(Int8(bitPattern: byte(ram, 0x0147)))
        signed(pulse, magnitude: 12)
        natural(0x0148)
        small(min(Int(byte(ram, 0x015d)), 135), 135)
        natural(0x015f)
        for pair in [(0x0160, 0x0165), (0x0161, 0x0166), (0x0162, 0x0167), (0x0163, 0x0168), (0x0164, 0x0169)] {
            signed(signed16(lsb: pair.0, msb: pair.1), magnitude: 2560)
        }

        var enemyAbs = Array(repeating: Self.invalidSegment, count: 7)
        var enemyDepths = Array(repeating: 0, count: 7)
        var enemyTypes = Array(repeating: 0, count: 7)
        var enemyRels = Array(repeating: Double(Self.invalidSegment), count: 7)
        var enemyCanShoot = Array(repeating: 0, count: 7)
        for i in 0..<7 {
            let d = Int(byte(ram, 0x02df + i))
            enemyDepths[i] = d
            if d > 0 {
                let absSeg = Int(byte(ram, 0x02b9 + i) & 0x0f)
                let type = Int(byte(ram, 0x0283 + i))
                let state = Int(byte(ram, 0x028a + i))
                enemyAbs[i] = absSeg
                enemyTypes[i] = type & 0x07
                enemyRels[i] = relativeSegment(absSeg)
                if (type & 0x80) != 0, enemyTypes[i] != 4 {
                    let progress = betweenProgress(
                        segAbs: absSeg,
                        increasing: (type & 0x40) != 0,
                        angleNibble: Int(byte(ram, 0x02cc + i) & 0x0f)
                    )
                    var relFloat = enemyRels[i]
                    if (type & 0x40) != 0 {
                        relFloat = relFloat + progress - 1.0
                    } else {
                        relFloat = relFloat - progress
                    }
                    enemyRels[i] = open ? relFloat : wrapClosedRelative(relFloat)
                }
                small(type & 0x07, 7)
                small((type & 0x40) != 0 ? 1 : 0, 1)
                small((type & 0x80) != 0 ? 1 : 0, 1)
                small((state & 0x80) != 0 ? 1 : 0, 1)
                let canShoot = (state & 0x40) != 0 ? 1 : 0
                enemyCanShoot[i] = canShoot
                small(canShoot, 1)
                small(state & 0x03, 3)
            } else {
                for _ in 0..<6 { push(0) }
            }
        }
        for value in enemyRels { rel(value) }
        for value in enemyDepths { depth(value) }
        for i in 0..<7 {
            if enemyDepths[i] == 0x10 {
                rel(enemyRels[i])
            } else {
                rel(Double(Self.invalidSegment))
            }
        }
        for i in 0..<4 { fixed(0x02db + i, 0x02e6 + i) }
        var enemyShotAbs = Array(repeating: Self.invalidSegment, count: 4)
        var enemyShotRels = Array(repeating: Double(Self.invalidSegment), count: 4)
        for i in 0..<4 {
            if byte(ram, 0x02db + i) != 0 {
                let absSeg = Int(byte(ram, 0x02b5 + i) & 0x0f)
                enemyShotAbs[i] = absSeg
                enemyShotRels[i] = relativeSegment(absSeg)
            }
            rel(enemyShotRels[i])
        }
        for i in 0..<7 {
            if enemyTypes[i] == 1 {
                depth(enemyDepths[i])
            } else {
                depth(0)
            }
        }
        for i in 0..<7 {
            if enemyTypes[i] == 1 {
                rel(enemyRels[i])
            } else {
                rel(Double(Self.invalidSegment))
            }
        }
        for i in 0..<7 {
            if enemyDepths[i] > 0 && enemyDepths[i] <= 0x10 && (enemyTypes[i] == 1 || enemyTypes[i] == 0) {
                rel(enemyRels[i])
            } else {
                rel(Double(Self.topRailAbsent))
            }
        }

        func nearestThreat(inLane lane: Int) -> Int {
            if lane < 0 || lane > 15 { return 255 }
            var best = 255
            let spike = Int(byte(ram, 0x03ac + lane))
            if spike > 0 { best = min(best, spike) }
            for i in 0..<7 where enemyAbs[i] == lane && enemyDepths[i] > 0 {
                best = min(best, enemyDepths[i])
            }
            for i in 0..<4 where enemyShotAbs[i] == lane {
                best = min(best, Int(byte(ram, 0x02db + i)))
            }
            return best
        }
        let left = open ? playerAbs - 1 : (playerAbs + 15) % 16
        let right = open ? playerAbs + 1 : (playerAbs + 1) % 16
        depth(nearestThreat(inLane: playerAbs))
        depth(nearestThreat(inLane: left))
        depth(nearestThreat(inLane: right))

        for i in 0..<7 {
            if enemyDepths[i] > 0 && previousEnemyDepths[i] > 0 && enemyTypes[i] == previousEnemyTypes[i]
                && enemyAbs[i] != Self.invalidSegment && previousEnemySegments[i] != Self.invalidSegment {
                var delta = enemyAbs[i] - previousEnemySegments[i]
                if !open {
                    if delta > 8 { delta -= 16 }
                    if delta < -8 { delta += 16 }
                }
                signed(delta, magnitude: 8)
            } else {
                signed(0, magnitude: 8)
            }
        }
        for i in 0..<7 {
            if enemyDepths[i] > 0 && previousEnemyDepths[i] > 0 && enemyTypes[i] == previousEnemyTypes[i] {
                signed(enemyDepths[i] - previousEnemyDepths[i], magnitude: 128)
            } else {
                signed(0, magnitude: 128)
            }
        }

        previousEnemySegments = enemyAbs
        previousEnemyDepths = enemyDepths
        previousEnemyTypes = enemyTypes

        if values.count < 195 {
            values.append(contentsOf: Array(repeating: 0, count: 195 - values.count))
        }
        if values.count > 195 {
            values = Array(values.prefix(195))
        }
        return values
    }

    private func byte(_ ram: [UInt8], _ address: Int) -> UInt8 {
        ram[address & 0x7ff]
    }

    private func scoreBCD(_ ram: [UInt8], _ address: Int) -> Int {
        bcd(byte(ram, address + 2)) * 10000
            + bcd(byte(ram, address + 1)) * 100
            + bcd(byte(ram, address))
    }

    private func bcd(_ value: UInt8) -> Int {
        let hi = min(9, Int((value >> 4) & 0x0f))
        let lo = min(9, Int(value & 0x0f))
        return (hi * 10) + lo
    }

    private func highScoreInitialBytes(_ ram: [UInt8]) -> (UInt8, UInt8, UInt8) {
        (
            initialASCII(byte(ram, 0x061d)),
            initialASCII(byte(ram, 0x061c)),
            initialASCII(byte(ram, 0x061b))
        )
    }

    private func initialASCII(_ value: UInt8) -> UInt8 {
        value <= 25 ? UInt8(ascii: "A") + value : UInt8(ascii: " ")
    }
}

extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16BE(_ value: UInt16) {
        appendInteger(value.bigEndian)
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        appendInteger(value.bigEndian)
    }

    mutating func appendInt16BE(_ value: Int16) {
        appendInteger(UInt16(bitPattern: value).bigEndian)
    }

    mutating func appendFloat32BE(_ value: Float) {
        appendInteger(value.bitPattern.bigEndian)
    }

    mutating func appendDoubleBE(_ value: Double) {
        appendInteger(value.bitPattern.bigEndian)
    }

    private mutating func appendInteger<T>(_ value: T) {
        var value = value
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
