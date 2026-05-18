import Foundation

final class TempestMemoryBus {
    private(set) var ram = Array(repeating: UInt8(0), count: 0x0800)
    private(set) var vectorRAM = Array(repeating: UInt8(0), count: 0x1000)
    private(set) var displayVectorRAM = Array(repeating: UInt8(0), count: 0x1000)
    private(set) var vectorFrameSerial: UInt64 = 0
    private let rom: [UInt8]
    private let vectorROM: [UInt8]
    private(set) var colorRAM = Array(repeating: UInt8(0), count: 0x10)
    private var earom = Array(repeating: UInt8(0), count: 0x40)
    private var earomAddress = 0
    private var earomControl: UInt8 = 0
    private var earomData: UInt8 = 0
    private(set) var earomDirty = false
    private var mathbox: TempestMathbox
    private var pokey1 = TempestPOKEY()
    private var pokey2 = TempestPOKEY()
    private var statusReadCount: UInt8 = 0

    var inputState = TempestInputState()
    // N13 coinage DIP. Use the original ROM's free-play setting for the app
    // runtime so automated Swift games can start without patching credits RAM.
    var dsw1: UInt8 = 0x02
    var dsw2: UInt8 = 0x00
    var in0: UInt8 = 0x7f
    var in1: UInt8 = 0xf0
    var in2: UInt8 = 0xe7

    init(romSet: TempestROMSet) {
        self.rom = romSet.mainCPU
        self.vectorROM = romSet.vectorROM
        self.earom.replaceSubrange(0..<min(0x40, romSet.earom.count), with: romSet.earom.prefix(0x40))
        self.mathbox = TempestMathbox(promData: romSet.mathPROMs)
    }

    func applyInput(_ input: TempestInputState) {
        inputState = input
        let spinner = Int8(clamping: input.spinnerDelta)
        ram[0x0050] = UInt8(bitPattern: spinner)
    }

    func read(_ address: UInt16) -> UInt8 {
        let a = Int(address)
        switch a {
        case 0x0000...0x07ff:
            return ram[a & 0x07ff]
        case 0x0800...0x080f:
            return colorRAM[a & 0x0f]
        case 0x0c00:
            return encodedInput0()
        case 0x0d00:
            return dsw1
        case 0x0e00:
            return dsw2
        case 0x2000...0x2fff:
            return vectorRAM[a - 0x2000]
        case 0x3000...0x3fff:
            return vectorROM[a - 0x3000]
        case 0x6040:
            return mathbox.status()
        case 0x6050:
            return earom[earomAddress & 0x3f]
        case 0x6060:
            return mathbox.lo()
        case 0x6070:
            return mathbox.hi()
        case 0x60c0...0x60cf:
            return readPokey1(register: a & 0x0f)
        case 0x60d0...0x60df:
            return readPokey2(register: a & 0x0f)
        case 0x9000...0xdfff:
            return rom[a]
        case 0xe000...0xffff:
            return rom[0xc000 + (a & 0x1fff)]
        default:
            return 0
        }
    }

    func write(_ address: UInt16, _ value: UInt8) {
        let a = Int(address)
        switch a {
        case 0x0000...0x07ff:
            ram[a & 0x07ff] = value
        case 0x0800...0x080f:
            colorRAM[a & 0x0f] = value
        case 0x2000...0x2fff:
            vectorRAM[a - 0x2000] = value
        case 0x4000:
            displayVectorRAM = vectorRAM
            vectorFrameSerial &+= 1
        case 0x4800, 0x5000, 0x5800, 0x60e0:
            break
        case 0x6000...0x603f:
            earomAddress = a & 0x3f
            earomData = value
            if (earomControl & 0x40) != 0, earom[earomAddress] != value {
                earom[earomAddress] = value
                earomDirty = true
            }
        case 0x6040:
            earomControl = value
        case 0x6080...0x609f:
            mathbox.write(offset: a & 0x1f, value: value)
        case 0x60c0...0x60cf:
            pokey1.write(register: a & 0x0f, value: value)
        case 0x60d0...0x60df:
            pokey2.write(register: a & 0x0f, value: value)
        default:
            break
        }
    }

    func scoreBCD() -> Int {
        let low = bcd(ram[0x40])
        let mid = bcd(ram[0x41])
        let high = bcd(ram[0x42])
        return high * 10000 + mid * 100 + low
    }

    func highScoreBCD() -> Int {
        guard ram.count > 0x71d else { return 0 }
        let low = bcd(ram[0x71b & 0x7ff])
        let mid = bcd(ram[0x71c & 0x7ff])
        let high = bcd(ram[0x71d & 0x7ff])
        return high * 10000 + mid * 100 + low
    }

    func highScoreInitials() -> String {
        let bytes = [ram[0x061d & 0x7ff], ram[0x061c & 0x7ff], ram[0x061b & 0x7ff]]
        let chars = bytes.map { initialValueToCharacter($0) }
        let text = String(chars)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func earomSnapshot() -> [UInt8] {
        earom
    }

    func markEAROMSaved() {
        earomDirty = false
    }

    private func bcd(_ value: UInt8) -> Int {
        let hi = min(9, Int((value >> 4) & 0x0f))
        let lo = min(9, Int(value & 0x0f))
        return (hi * 10) + lo
    }

    private func initialValueToCharacter(_ value: UInt8) -> Character {
        if value <= 25 {
            return Character(UnicodeScalar(Int(UInt8(ascii: "A") + value))!)
        }
        return " "
    }

    private func encodedInput0() -> UInt8 {
        statusReadCount &+= 1
        var value = in0
        if inputState.coin1 { value &= ~0x04 }
        value |= 0x40 // AVG done/HALT is active-high; the Swift AVG currently completes immediately.
        if (statusReadCount & 0x20) != 0 {
            value |= 0x80
        } else {
            value &= ~0x80
        }
        return value
    }

    private func encodedInput1() -> UInt8 {
        var value = in1
        let spinnerNibble = UInt8(truncatingIfNeeded: inputState.spinnerDelta) & 0x0f
        value = (value & 0xf0) | spinnerNibble
        return value
    }

    private func encodedInput2() -> UInt8 {
        var value = in2
        if inputState.fire { value &= ~0x10 }
        if inputState.zap { value &= ~0x08 }
        if inputState.start1 { value &= ~0x20 }
        return value
    }

    private func readPokey1(register: Int) -> UInt8 {
        if register == 8 {
            return ~encodedInput1()
        }
        if register <= 7 {
            return (encodedInput1() & (1 << register)) != 0 ? 0 : 228
        }
        return pokey1.read(register: register)
    }

    private func readPokey2(register: Int) -> UInt8 {
        if register == 8 {
            return ~encodedInput2()
        }
        if register <= 7 {
            return (encodedInput2() & (1 << register)) != 0 ? 0 : 228
        }
        return pokey2.read(register: register)
    }
}

private struct TempestPOKEY {
    private var registers = Array(repeating: UInt8(0), count: 16)
    private var lfsr: UInt32 = 0x1ffff

    mutating func read(register: Int) -> UInt8 {
        if register == 0x0a {
            lfsr = ((lfsr << 7) ^ (lfsr >> 3) ^ 0x1d872b41) & 0x1ffff
            return UInt8(truncatingIfNeeded: lfsr)
        }
        return registers[register & 0x0f]
    }

    mutating func write(register: Int, value: UInt8) {
        registers[register & 0x0f] = value
    }
}
