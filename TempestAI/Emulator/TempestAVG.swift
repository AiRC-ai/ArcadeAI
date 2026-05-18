import Foundation

final class TempestAVG {
    private let romSet: TempestROMSet
    private let xCenter = 290 << 16
    private let yCenter = 285 << 16

    init(romSet: TempestROMSet) {
        self.romSet = romSet
    }

    func renderVectorFrame(vectorRAM: [UInt8], colorRAM: [UInt8]) -> [TempestVectorLine] {
        var machine = AVGState(
            vectorRAM: vectorRAM,
            vectorROM: romSet.vectorROM,
            prom: romSet.avgPROM,
            colorRAM: colorRAM,
            xCenter: xCenter,
            yCenter: yCenter
        )
        return machine.run()
    }
}

private struct AVGPoint {
    var x: Int
    var y: Int
    var argb: UInt32
    var intensity: Int
}

private struct AVGState {
    let vectorRAM: [UInt8]
    let vectorROM: [UInt8]
    let prom: [UInt8]
    let colorRAM: [UInt8]
    let xCenter: Int
    let yCenter: Int

    var pc = 0
    var sp = 0
    var dvx = 0
    var dvy = 0
    var stack = Array(repeating: 0, count: 4)
    var data = 0
    var stateLatch = 0
    var scale = 0
    var intensity = 0
    var op = 0
    var halt = 0
    var xpos = 0
    var ypos = 0
    var dvy12 = 0
    var timer = 0
    var intLatch = 0
    var binScale = 0
    var color = 0
    var previousPoint: AVGPoint?
    var pointCount = 0
    var lines: [TempestVectorLine] = []

    mutating func run() -> [TempestVectorLine] {
        pc = 0
        sp = 0
        stateLatch = 0
        scale = 0
        color = 0
        halt = 0
        xpos = xCenter
        ypos = yCenter
        previousPoint = nil
        pointCount = 0
        lines.removeAll(keepingCapacity: true)
        lines.reserveCapacity(1024)

        var cycles = 0
        var producedFrame = false
        var iterations = 0
        while iterations < 80_000 && cycles < 2_000_000 {
            iterations += 1
            let addr = stateAddress()
            let promNibble = addr < prom.count ? Int(prom[addr] & 0x0f) : 0
            stateLatch = (stateLatch & 0x10) | promNibble

            if st3 {
                updateDatabus()
                switch stateLatch & 7 {
                case 0: cycles += handler0()
                case 1: cycles += handler1()
                case 2: cycles += handler2()
                case 3: cycles += handler3()
                case 4: cycles += handler4()
                case 5: cycles += handler5()
                case 6: cycles += handler6()
                case 7:
                    cycles += handler7()
                    if pc == 0 && pointCount > 10 {
                        producedFrame = true
                    }
                default:
                    break
                }
            }

            stateLatch = (halt << 4) | (stateLatch & 0x0f)
            cycles += 8

            if halt != 0 || producedFrame {
                break
            }
        }
        return lines
    }

    private var op0: Bool { (op & 0x01) != 0 }
    private var op1: Bool { (op & 0x02) != 0 }
    private var op2: Bool { (op & 0x04) != 0 }
    private var st3: Bool { (stateLatch & 0x08) != 0 }

    private func stateAddress() -> Int {
        ((((stateLatch >> 4) ^ 1) & 1) << 7) | ((op & 0x0f) << 4) | (stateLatch & 0x0f)
    }

    private mutating func updateDatabus() {
        data = Int(readVectorByte(pc ^ 1))
    }

    private func readVectorByte(_ address: Int) -> UInt8 {
        let a = address & 0x1fff
        if a < 0x1000 {
            return a < vectorRAM.count ? vectorRAM[a] : 0
        }
        let index = a - 0x1000
        return index < vectorROM.count ? vectorROM[index] : 0
    }

    private mutating func handler0() -> Int {
        dvy = (dvy & 0x1f00) | data
        pc = (pc + 1) & 0xffff
        return 0
    }

    private mutating func handler1() -> Int {
        dvy12 = (data >> 4) & 1
        op = data >> 5
        intLatch = 0
        dvy = (dvy12 << 12) | ((data & 0x0f) << 8)
        dvx = 0
        pc = (pc + 1) & 0xffff
        return 0
    }

    private mutating func handler2() -> Int {
        dvx = (dvx & 0x1f00) | data
        pc = (pc + 1) & 0xffff
        return 0
    }

    private mutating func handler3() -> Int {
        intLatch = data >> 4
        dvx = ((intLatch & 1) << 12) | ((data & 0x0f) << 8) | (dvx & 0xff)
        pc = (pc + 1) & 0xffff
        return 0
    }

    private mutating func handler4() -> Int {
        if op0 {
            stack[sp & 3] = pc
        } else {
            var i = 0
            while (((dvy ^ (dvy << 1)) & 0x1000) == 0)
                && (((dvx ^ (dvx << 1)) & 0x1000) == 0)
                && i < 16 {
                i += 1
                dvy = (dvy & 0x1000) | ((dvy << 1) & 0x1fff)
                dvx = (dvx & 0x1000) | ((dvx << 1) & 0x1fff)
                timer >>= 1
                timer |= 0x4000 | (op1 ? 0x80 : 0)
            }
            if op1 {
                timer &= 0xff
            }
        }
        return 0
    }

    private mutating func handler5() -> Int {
        if !op2 {
            if binScale > 0 {
                for _ in 0..<binScale {
                    timer >>= 1
                    timer |= 0x4000 | (op1 ? 0x80 : 0)
                }
            }
            if op1 {
                timer &= 0xff
            }
        }
        return commonStrobe1()
    }

    private mutating func handler6() -> Int {
        if !op2 && dvy12 == 0 {
            if (dvy & 0x800) != 0 {
                color = dvy & 0x0f
            } else {
                intensity = (dvy >> 4) & 0x0f
            }
        }
        return commonStrobe2()
    }

    private mutating func handler7() -> Int {
        let usedCycles = commonStrobe3()
        if !op0 && !op2 {
            addTempestPoint(x: xpos, y: ypos)
        }
        return usedCycles
    }

    private mutating func commonStrobe1() -> Int {
        if op2 {
            if op1 {
                sp = (sp - 1) & 0x0f
            } else {
                sp = (sp + 1) & 0x0f
            }
        }
        return 0
    }

    private mutating func commonStrobe2() -> Int {
        if op2 {
            if op0 {
                pc = (dvy << 1) & 0xffff
            } else {
                pc = stack[sp & 3]
            }
        } else if dvy12 != 0 {
            scale = dvy & 0xff
            binScale = (dvy >> 8) & 7
        }
        return 0
    }

    private mutating func commonStrobe3() -> Int {
        var usedCycles = 0
        halt = op0 ? 1 : 0
        if !op0 && !op2 {
            if op1 {
                usedCycles = 0x100 - (timer & 0xff)
            } else {
                usedCycles = 0x8000 - timer
            }
            timer = 0

            let dxInput = (((dvx >> 3) ^ 0x200) - 0x200)
            let dyInput = (((dvy >> 3) ^ 0x200) - 0x200)
            let scaleFactor = scale ^ 0xff
            xpos += (dxInput * usedCycles * scaleFactor) >> 4
            ypos -= (dyInput * usedCycles * scaleFactor) >> 4
        }

        if op2 {
            usedCycles = 0x8000 - timer
            timer = 0
            xpos = xCenter
            ypos = yCenter
            recordPoint(AVGPoint(x: xpos, y: ypos, argb: 0, intensity: 0))
        }
        return max(0, usedCycles)
    }

    private mutating func addTempestPoint(x: Int, y: Int) {
        let argb = tempestColorARGB()
        let visibleIntensity = (((intLatch >> 1) == 1) ? intensity : (intLatch & 0x0e)) << 4
        recordPoint(AVGPoint(x: x, y: y, argb: argb, intensity: visibleIntensity))
    }

    private mutating func recordPoint(_ point: AVGPoint) {
        if let previous = previousPoint, point.intensity > 0 {
            lines.append(TempestVectorLine(
                x0: fixedToScreen(previous.x),
                y0: fixedToScreen(previous.y),
                x1: fixedToScreen(point.x),
                y1: fixedToScreen(point.y),
                argb: point.argb,
                intensity: min(255, max(0, point.intensity))
            ))
        }
        previousPoint = point
        pointCount += 1
    }

    private func tempestColorARGB() -> UInt32 {
        let data = color < colorRAM.count ? colorRAM[color] : 0
        let bit3 = ((~data >> 3) & 1)
        let bit2 = ((~data >> 2) & 1)
        let bit1 = ((~data >> 1) & 1)
        let bit0 = ((~data >> 0) & 1)
        let r = UInt32(bit1) * 0xf3 + UInt32(bit0) * 0x0c
        let g = UInt32(bit3) * 0xf3
        let b = UInt32(bit2) * 0xf3
        return 0xff00_0000 | (r << 16) | (g << 8) | b
    }

    private func fixedToScreen(_ value: Int) -> Double {
        Double(value) / 65_536.0
    }
}

final class TempestMathbox {
    private var result: Int32 = 0
    private var registers = Array(repeating: Int32(0), count: 16)

    init(promData: [[UInt8]]) {
        _ = promData
    }

    func status() -> UInt8 {
        0
    }

    func lo() -> UInt8 {
        UInt8(truncatingIfNeeded: result)
    }

    func hi() -> UInt8 {
        UInt8(truncatingIfNeeded: result >> 8)
    }

    func write(offset rawOffset: Int, value rawValue: UInt8) {
        let offset = rawOffset & 0x1f
        let data = Int32(rawValue)
        switch offset {
        case 0x00: setLow(0, data)
        case 0x01: setHigh(0, data)
        case 0x02: setLow(1, data)
        case 0x03: setHigh(1, data)
        case 0x04: setLow(2, data)
        case 0x05: setHigh(2, data)
        case 0x06: setLow(3, data)
        case 0x07: setHigh(3, data)
        case 0x08: setLow(4, data)
        case 0x09: setHigh(4, data)
        case 0x0a: setLow(5, data)
        case 0x0c: setRegister(6, data)
        case 0x15: setLow(7, data)
        case 0x16: setHigh(7, data)
        case 0x1a: setLow(8, data)
        case 0x1b: setHigh(8, data)
        case 0x0d: setLow(10, data)
        case 0x0e: setHigh(10, data)
        case 0x0f: setLow(11, data)
        case 0x10: setHigh(11, data)
        case 0x17: result = registers[7]
        case 0x18: result = registers[9]
        case 0x19: result = registers[8]
        case 0x0b:
            setHigh(5, data)
            registers[15] = -1
            registers[4] = wrap16(registers[4] - registers[2])
            registers[5] = wrap16(registers[5] - registers[3])
            step048()
        case 0x11:
            setHigh(5, data)
            registers[15] = 0
            step048()
        case 0x12:
            step12()
        case 0x13:
            divide(c: registers[9], q: registers[8])
        case 0x14:
            divide(c: registers[10], q: registers[11])
        case 0x1c:
            setHigh(5, data)
            windowTest()
        case 0x1d:
            setHigh(3, data)
            registers[2] = abs16(registers[2] - registers[0])
            registers[3] = abs16(registers[3] - registers[1])
            distanceApprox()
        case 0x1e:
            distanceApprox()
        default:
            break
        }
    }

    private func lowHigh(_ index: Int, low: Int32? = nil, high: Int32? = nil) -> Int32 {
        let current = UInt16(truncatingIfNeeded: registers[index])
        let lo = UInt16(low.map { UInt8(truncatingIfNeeded: $0) } ?? UInt8(current & 0xff))
        let hi = UInt16(high.map { UInt8(truncatingIfNeeded: $0) } ?? UInt8((current >> 8) & 0xff))
        return wrap16(Int32((hi << 8) | lo))
    }

    private func setRegister(_ index: Int, _ value: Int32) {
        registers[index] = wrap16(value)
        result = registers[index]
    }

    private func setLow(_ index: Int, _ value: Int32) {
        setRegister(index, lowHigh(index, low: value))
    }

    private func setHigh(_ index: Int, _ value: Int32) {
        setRegister(index, lowHigh(index, high: value))
    }

    private func wrap16(_ value: Int32) -> Int32 {
        Int32(Int16(truncatingIfNeeded: value))
    }

    private func abs16(_ value: Int32) -> Int32 {
        let wrapped = wrap16(value)
        return wrapped < 0 ? wrap16(-wrapped) : wrapped
    }

    private func multiplyHighLow(_ lhs: Int32, _ rhs: Int32) -> (high: Int32, low: Int32) {
        let product = lhs * rhs
        return (wrap16(product >> 16), wrap16(product & 0xffff))
    }

    private func step048() {
        let first = multiplyHighLow(registers[0], registers[4])
        registers[12] = first.high
        registers[14] = first.low

        let second = multiplyHighLow(-registers[1], registers[5])
        registers[7] = wrap16(second.high + registers[12])

        registers[14] = wrap16((registers[14] >> 1) & 0x7fff)
        registers[12] = wrap16((second.low >> 1) & 0x7fff)
        let q = wrap16(registers[12] + registers[14])
        if q < 0 {
            registers[7] = wrap16(registers[7] + 1)
        }
        result = registers[7]

        if registers[15] < 0 {
            return
        }
        registers[7] = wrap16(registers[7] + registers[2])
        step12()
    }

    private func step12() {
        let first = multiplyHighLow(registers[1], registers[4])
        registers[12] = first.high
        registers[9] = first.low

        let second = multiplyHighLow(registers[0], registers[5])
        registers[8] = wrap16(second.high + registers[12])

        registers[9] = wrap16((registers[9] >> 1) & 0x7fff)
        registers[12] = wrap16((second.low >> 1) & 0x7fff)
        registers[9] = wrap16(registers[9] + registers[12])
        if registers[9] < 0 {
            registers[8] = wrap16(registers[8] + 1)
        }
        registers[9] = wrap16(registers[9] << 1)
        result = registers[8]

        if registers[15] < 0 {
            return
        }
        registers[8] = wrap16(registers[8] + registers[3])
        registers[9] = wrap16(registers[9] & 0xff00)
        divide(c: registers[9], q: registers[8])
    }

    private func divide(c: Int32, q inputQ: Int32) {
        registers[12] = c
        var q = inputQ
        registers[14] = registers[7] ^ q
        registers[13] = q
        if q >= 0 {
            q = registers[12]
        } else {
            registers[13] = wrap16(-q - 1)
            q = wrap16(-registers[12] - 1)
            if q < 0 && wrap16(q + 1) < 0 {
                registers[13] = wrap16(registers[13] + 1)
            }
            q = wrap16(q + 1)
        }

        registers[12] = registers[7] >= 0 ? registers[7] : wrap16(-registers[7])
        registers[15] = registers[6]
        repeat {
            registers[13] = wrap16(registers[13] - registers[12])
            let msb = (q & 0x8000) != 0 ? 1 : 0
            q = wrap16(q << 1)
            if registers[13] >= 0 {
                q = wrap16(q + 1)
            } else {
                registers[13] = wrap16(registers[13] + registers[12])
            }
            registers[13] = wrap16((registers[13] << 1) + Int32(msb))
            registers[15] = wrap16(registers[15] - 1)
        } while registers[15] >= 0

        result = registers[14] >= 0 ? q : wrap16(-q)
    }

    private func windowTest() {
        repeat {
            registers[14] = wrap16((registers[4] + registers[7]) >> 1)
            registers[15] = wrap16((registers[5] + registers[8]) >> 1)
            if registers[11] < registers[14]
                && registers[15] < registers[14]
                && wrap16(registers[14] + registers[15]) >= 0 {
                registers[7] = registers[14]
                registers[8] = registers[15]
            } else {
                registers[4] = registers[14]
                registers[5] = registers[15]
            }
            registers[6] = wrap16(registers[6] - 1)
        } while registers[6] >= 0
        result = registers[8]
    }

    private func distanceApprox() {
        if registers[3] >= registers[2] {
            registers[12] = registers[2]
            registers[13] = registers[3]
        } else {
            registers[13] = registers[2]
            registers[12] = registers[3]
        }
        registers[12] = wrap16(registers[12] >> 2)
        registers[13] = wrap16(registers[13] + registers[12])
        registers[12] = wrap16(registers[12] >> 1)
        registers[13] = wrap16(registers[12] + registers[13])
        result = registers[13]
    }
}
