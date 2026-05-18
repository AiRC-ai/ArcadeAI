import Foundation

enum MOS6502Stop: Error, LocalizedError {
    case unimplementedOpcode(UInt8, pc: UInt16)

    var errorDescription: String? {
        switch self {
        case .unimplementedOpcode(let opcode, let pc):
            return String(format: "6502 opcode %02X at %04X is not implemented yet", opcode, pc)
        }
    }
}

final class MOS6502 {
    var a: UInt8 = 0
    var x: UInt8 = 0
    var y: UInt8 = 0
    var sp: UInt8 = 0xfd
    var pc: UInt16 = 0
    var status: UInt8 = 0x24
    private(set) var cycles: UInt64 = 0
    var programCounter: UInt16 { pc }

    private let bus: TempestMemoryBus

    init(bus: TempestMemoryBus) {
        self.bus = bus
    }

    func reset() {
        a = 0
        x = 0
        y = 0
        sp = 0xfd
        status = 0x24
        pc = read16(0xfffc)
        cycles = 7
    }

    @discardableResult
    func irq() -> Int {
        guard !flag(0x04) else { return 0 }
        push16(pc)
        push8(status & ~0x10)
        setInterruptDisable(true)
        pc = read16(0xfffe)
        cycles += 7
        return 7
    }

    @discardableResult
    func step() throws -> Int {
        let opcodePC = pc
        let opcode = read8(pc)
        pc &+= 1
        switch opcode {
        case 0x01:
            a |= read8(indirectX(fetch8()))
            setZN(a)
            cycles += 6
            return 6
        case 0x05:
            a |= read8(UInt16(fetch8()))
            setZN(a)
            cycles += 3
            return 3
        case 0x06:
            let addr = UInt16(fetch8())
            let value = asl(read8(addr))
            write8(addr, value)
            cycles += 5
            return 5
        case 0x08:
            push8(status | 0x10)
            cycles += 3
            return 3
        case 0x09:
            a |= fetch8()
            setZN(a)
            cycles += 2
            return 2
        case 0x0a:
            a = asl(a)
            cycles += 2
            return 2
        case 0x0d:
            a |= read8(fetch16())
            setZN(a)
            cycles += 4
            return 4
        case 0x0e:
            let addr = fetch16()
            let value = asl(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x10:
            let taken = branch(if: !flag(0x80))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0x11:
            a |= read8(indirectY(fetch8()))
            setZN(a)
            cycles += 5
            return 5
        case 0x15:
            a |= read8(zeroPageX(fetch8()))
            setZN(a)
            cycles += 4
            return 4
        case 0x16:
            let addr = zeroPageX(fetch8())
            let value = asl(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x19:
            a |= read8(fetch16() &+ UInt16(y))
            setZN(a)
            cycles += 4
            return 4
        case 0x1d:
            a |= read8(fetch16() &+ UInt16(x))
            setZN(a)
            cycles += 4
            return 4
        case 0x1e:
            let addr = fetch16() &+ UInt16(x)
            let value = asl(read8(addr))
            write8(addr, value)
            cycles += 7
            return 7
        case 0x00: // BRK
            pc &+= 1
            push16(pc)
            push8(status | 0x10)
            setInterruptDisable(true)
            pc = read16(0xfffe)
            cycles += 7
            return 7
        case 0x18: setCarry(false); cycles += 2; return 2
        case 0x20:
            let target = fetch16()
            push16(pc &- 1)
            pc = target
            cycles += 6
            return 6
        case 0x21:
            a &= read8(indirectX(fetch8()))
            setZN(a)
            cycles += 6
            return 6
        case 0x25:
            a &= read8(UInt16(fetch8()))
            setZN(a)
            cycles += 3
            return 3
        case 0x26:
            let addr = UInt16(fetch8())
            let value = rol(read8(addr))
            write8(addr, value)
            cycles += 5
            return 5
        case 0x28:
            status = pop8()
            cycles += 4
            return 4
        case 0x29:
            a &= fetch8()
            setZN(a)
            cycles += 2
            return 2
        case 0x2a:
            a = rol(a)
            cycles += 2
            return 2
        case 0x24:
            bit(read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0x2c:
            bit(read8(fetch16()))
            cycles += 4
            return 4
        case 0x2d:
            a &= read8(fetch16())
            setZN(a)
            cycles += 4
            return 4
        case 0x2e:
            let addr = fetch16()
            let value = rol(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x30:
            let taken = branch(if: flag(0x80))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0x31:
            a &= read8(indirectY(fetch8()))
            setZN(a)
            cycles += 5
            return 5
        case 0x35:
            a &= read8(zeroPageX(fetch8()))
            setZN(a)
            cycles += 4
            return 4
        case 0x36:
            let addr = zeroPageX(fetch8())
            let value = rol(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x38: setCarry(true); cycles += 2; return 2
        case 0x39:
            a &= read8(fetch16() &+ UInt16(y))
            setZN(a)
            cycles += 4
            return 4
        case 0x3d:
            a &= read8(fetch16() &+ UInt16(x))
            setZN(a)
            cycles += 4
            return 4
        case 0x3e:
            let addr = fetch16() &+ UInt16(x)
            let value = rol(read8(addr))
            write8(addr, value)
            cycles += 7
            return 7
        case 0x40:
            status = pop8()
            pc = pop16()
            cycles += 6
            return 6
        case 0x41:
            a ^= read8(indirectX(fetch8()))
            setZN(a)
            cycles += 6
            return 6
        case 0x45:
            a ^= read8(UInt16(fetch8()))
            setZN(a)
            cycles += 3
            return 3
        case 0x46:
            let addr = UInt16(fetch8())
            let value = lsr(read8(addr))
            write8(addr, value)
            cycles += 5
            return 5
        case 0x48:
            push8(a)
            cycles += 3
            return 3
        case 0x49:
            a ^= fetch8()
            setZN(a)
            cycles += 2
            return 2
        case 0x4a:
            a = lsr(a)
            cycles += 2
            return 2
        case 0x4d:
            a ^= read8(fetch16())
            setZN(a)
            cycles += 4
            return 4
        case 0x4e:
            let addr = fetch16()
            let value = lsr(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x50:
            let taken = branch(if: !flag(0x40))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0x51:
            a ^= read8(indirectY(fetch8()))
            setZN(a)
            cycles += 5
            return 5
        case 0x55:
            a ^= read8(zeroPageX(fetch8()))
            setZN(a)
            cycles += 4
            return 4
        case 0x56:
            let addr = zeroPageX(fetch8())
            let value = lsr(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x4c:
            pc = fetch16()
            cycles += 3
            return 3
        case 0x5d:
            a ^= read8(fetch16() &+ UInt16(x))
            setZN(a)
            cycles += 4
            return 4
        case 0x5e:
            let addr = fetch16() &+ UInt16(x)
            let value = lsr(read8(addr))
            write8(addr, value)
            cycles += 7
            return 7
        case 0x59:
            a ^= read8(fetch16() &+ UInt16(y))
            setZN(a)
            cycles += 4
            return 4
        case 0x58: setInterruptDisable(false); cycles += 2; return 2
        case 0x60:
            pc = pop16() &+ 1
            cycles += 6
            return 6
        case 0x61:
            adc(read8(indirectX(fetch8())))
            cycles += 6
            return 6
        case 0x65:
            adc(read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0x66:
            let addr = UInt16(fetch8())
            let value = ror(read8(addr))
            write8(addr, value)
            cycles += 5
            return 5
        case 0x68:
            a = pop8()
            setZN(a)
            cycles += 4
            return 4
        case 0x69:
            adc(fetch8())
            cycles += 2
            return 2
        case 0x6a:
            a = ror(a)
            cycles += 2
            return 2
        case 0x6d:
            adc(read8(fetch16()))
            cycles += 4
            return 4
        case 0x6c:
            let addr = fetch16()
            let lo = UInt16(read8(addr))
            let hiAddr = (addr & 0xff00) | UInt16(UInt8(truncatingIfNeeded: addr &+ 1))
            let hi = UInt16(read8(hiAddr))
            pc = lo | (hi << 8)
            cycles += 5
            return 5
        case 0x6e:
            let addr = fetch16()
            let value = ror(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x70:
            let taken = branch(if: flag(0x40))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0x71:
            adc(read8(indirectY(fetch8())))
            cycles += 5
            return 5
        case 0x75:
            adc(read8(zeroPageX(fetch8())))
            cycles += 4
            return 4
        case 0x76:
            let addr = zeroPageX(fetch8())
            let value = ror(read8(addr))
            write8(addr, value)
            cycles += 6
            return 6
        case 0x78: setInterruptDisable(true); cycles += 2; return 2
        case 0x79:
            adc(read8(fetch16() &+ UInt16(y)))
            cycles += 4
            return 4
        case 0x7d:
            adc(read8(fetch16() &+ UInt16(x)))
            cycles += 4
            return 4
        case 0x7e:
            let addr = fetch16() &+ UInt16(x)
            let value = ror(read8(addr))
            write8(addr, value)
            cycles += 7
            return 7
        case 0x81:
            write8(indirectX(fetch8()), a)
            cycles += 6
            return 6
        case 0x84:
            write8(UInt16(fetch8()), y)
            cycles += 3
            return 3
        case 0x85:
            write8(UInt16(fetch8()), a)
            cycles += 3
            return 3
        case 0x86:
            write8(UInt16(fetch8()), x)
            cycles += 3
            return 3
        case 0x88:
            y &-= 1
            setZN(y)
            cycles += 2
            return 2
        case 0x8a:
            a = x
            setZN(a)
            cycles += 2
            return 2
        case 0x8c:
            write8(fetch16(), y)
            cycles += 4
            return 4
        case 0x8d:
            write8(fetch16(), a)
            cycles += 4
            return 4
        case 0x8e:
            write8(fetch16(), x)
            cycles += 4
            return 4
        case 0x90:
            let taken = branch(if: !flag(0x01))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0x91:
            write8(indirectY(fetch8()), a)
            cycles += 6
            return 6
        case 0x94:
            write8(zeroPageX(fetch8()), y)
            cycles += 4
            return 4
        case 0x95:
            write8(UInt16(fetch8() &+ x), a)
            cycles += 4
            return 4
        case 0x96:
            write8(UInt16(fetch8() &+ y), x)
            cycles += 4
            return 4
        case 0x98:
            a = y
            setZN(a)
            cycles += 2
            return 2
        case 0x99:
            write8(fetch16() &+ UInt16(y), a)
            cycles += 5
            return 5
        case 0x9a:
            sp = x
            cycles += 2
            return 2
        case 0x9d:
            write8(fetch16() &+ UInt16(x), a)
            cycles += 5
            return 5
        case 0xa0:
            y = fetch8()
            setZN(y)
            cycles += 2
            return 2
        case 0xa1:
            a = read8(indirectX(fetch8()))
            setZN(a)
            cycles += 6
            return 6
        case 0xa2:
            x = fetch8()
            setZN(x)
            cycles += 2
            return 2
        case 0xa4:
            y = read8(UInt16(fetch8()))
            setZN(y)
            cycles += 3
            return 3
        case 0xa5:
            a = read8(UInt16(fetch8()))
            setZN(a)
            cycles += 3
            return 3
        case 0xa6:
            x = read8(UInt16(fetch8()))
            setZN(x)
            cycles += 3
            return 3
        case 0xa8:
            y = a
            setZN(y)
            cycles += 2
            return 2
        case 0xa9:
            a = fetch8()
            setZN(a)
            cycles += 2
            return 2
        case 0xaa:
            x = a
            setZN(x)
            cycles += 2
            return 2
        case 0xac:
            y = read8(fetch16())
            setZN(y)
            cycles += 4
            return 4
        case 0xad:
            a = read8(fetch16())
            setZN(a)
            cycles += 4
            return 4
        case 0xae:
            x = read8(fetch16())
            setZN(x)
            cycles += 4
            return 4
        case 0xb0:
            let taken = branch(if: flag(0x01))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0xb1:
            a = read8(indirectY(fetch8()))
            setZN(a)
            cycles += 5
            return 5
        case 0xb4:
            y = read8(zeroPageX(fetch8()))
            setZN(y)
            cycles += 4
            return 4
        case 0xb5:
            a = read8(zeroPageX(fetch8()))
            setZN(a)
            cycles += 4
            return 4
        case 0xb6:
            x = read8(zeroPageY(fetch8()))
            setZN(x)
            cycles += 4
            return 4
        case 0xb8:
            setOverflow(false)
            cycles += 2
            return 2
        case 0xb9:
            a = read8(fetch16() &+ UInt16(y))
            setZN(a)
            cycles += 4
            return 4
        case 0xba:
            x = sp
            setZN(x)
            cycles += 2
            return 2
        case 0xbc:
            y = read8(fetch16() &+ UInt16(x))
            setZN(y)
            cycles += 4
            return 4
        case 0xbd:
            a = read8(fetch16() &+ UInt16(x))
            setZN(a)
            cycles += 4
            return 4
        case 0xbe:
            x = read8(fetch16() &+ UInt16(y))
            setZN(x)
            cycles += 4
            return 4
        case 0xc0:
            compare(y, fetch8())
            cycles += 2
            return 2
        case 0xc1:
            compare(a, read8(indirectX(fetch8())))
            cycles += 6
            return 6
        case 0xc4:
            compare(y, read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0xc5:
            compare(a, read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0xc6:
            let addr = UInt16(fetch8())
            let value = read8(addr) &- 1
            write8(addr, value)
            setZN(value)
            cycles += 5
            return 5
        case 0xc9:
            compare(a, fetch8())
            cycles += 2
            return 2
        case 0xc8:
            y &+= 1
            setZN(y)
            cycles += 2
            return 2
        case 0xca:
            x &-= 1
            setZN(x)
            cycles += 2
            return 2
        case 0xce:
            let addr = fetch16()
            let value = read8(addr) &- 1
            write8(addr, value)
            setZN(value)
            cycles += 6
            return 6
        case 0xcd:
            compare(a, read8(fetch16()))
            cycles += 4
            return 4
        case 0xcc:
            compare(y, read8(fetch16()))
            cycles += 4
            return 4
        case 0xd0:
            let taken = branch(if: !flag(0x02))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0xd1:
            compare(a, read8(indirectY(fetch8())))
            cycles += 5
            return 5
        case 0xd5:
            compare(a, read8(zeroPageX(fetch8())))
            cycles += 4
            return 4
        case 0xd6:
            let addr = zeroPageX(fetch8())
            let value = read8(addr) &- 1
            write8(addr, value)
            setZN(value)
            cycles += 6
            return 6
        case 0xd8: setDecimal(false); cycles += 2; return 2
        case 0xd9:
            compare(a, read8(fetch16() &+ UInt16(y)))
            cycles += 4
            return 4
        case 0xdd:
            compare(a, read8(fetch16() &+ UInt16(x)))
            cycles += 4
            return 4
        case 0xde:
            let addr = fetch16() &+ UInt16(x)
            let value = read8(addr) &- 1
            write8(addr, value)
            setZN(value)
            cycles += 7
            return 7
        case 0xe0:
            compare(x, fetch8())
            cycles += 2
            return 2
        case 0xe1:
            sbc(read8(indirectX(fetch8())))
            cycles += 6
            return 6
        case 0xe4:
            compare(x, read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0xe5:
            sbc(read8(UInt16(fetch8())))
            cycles += 3
            return 3
        case 0xe6:
            let addr = UInt16(fetch8())
            let value = read8(addr) &+ 1
            write8(addr, value)
            setZN(value)
            cycles += 5
            return 5
        case 0xe8:
            x &+= 1
            setZN(x)
            cycles += 2
            return 2
        case 0xe9:
            sbc(fetch8())
            cycles += 2
            return 2
        case 0xea:
            cycles += 2
            return 2
        case 0xec:
            compare(x, read8(fetch16()))
            cycles += 4
            return 4
        case 0xed:
            sbc(read8(fetch16()))
            cycles += 4
            return 4
        case 0xee:
            let addr = fetch16()
            let value = read8(addr) &+ 1
            write8(addr, value)
            setZN(value)
            cycles += 6
            return 6
        case 0xf0:
            let taken = branch(if: flag(0x02))
            cycles += taken ? 3 : 2
            return taken ? 3 : 2
        case 0xf1:
            sbc(read8(indirectY(fetch8())))
            cycles += 5
            return 5
        case 0xf5:
            sbc(read8(zeroPageX(fetch8())))
            cycles += 4
            return 4
        case 0xf6:
            let addr = zeroPageX(fetch8())
            let value = read8(addr) &+ 1
            write8(addr, value)
            setZN(value)
            cycles += 6
            return 6
        case 0xf8:
            setDecimal(true)
            cycles += 2
            return 2
        case 0xf9:
            sbc(read8(fetch16() &+ UInt16(y)))
            cycles += 4
            return 4
        case 0xfd:
            sbc(read8(fetch16() &+ UInt16(x)))
            cycles += 4
            return 4
        case 0xfe:
            let addr = fetch16() &+ UInt16(x)
            let value = read8(addr) &+ 1
            write8(addr, value)
            setZN(value)
            cycles += 7
            return 7
        default:
            throw MOS6502Stop.unimplementedOpcode(opcode, pc: opcodePC)
        }
    }

    private func fetch8() -> UInt8 {
        let value = read8(pc)
        pc &+= 1
        return value
    }

    private func fetch16() -> UInt16 {
        let lo = UInt16(fetch8())
        let hi = UInt16(fetch8())
        return lo | (hi << 8)
    }

    private func branch(if condition: Bool) -> Bool {
        let offset = Int8(bitPattern: fetch8())
        guard condition else { return false }
        pc = UInt16(Int(pc) + Int(offset))
        return true
    }

    private func indirectY(_ zeroPage: UInt8) -> UInt16 {
        let lo = UInt16(read8(UInt16(zeroPage)))
        let hi = UInt16(read8(UInt16(zeroPage &+ 1)))
        return (lo | (hi << 8)) &+ UInt16(y)
    }

    private func indirectX(_ zeroPage: UInt8) -> UInt16 {
        let ptr = zeroPage &+ x
        let lo = UInt16(read8(UInt16(ptr)))
        let hi = UInt16(read8(UInt16(ptr &+ 1)))
        return lo | (hi << 8)
    }

    private func zeroPageX(_ zeroPage: UInt8) -> UInt16 {
        UInt16(zeroPage &+ x)
    }

    private func zeroPageY(_ zeroPage: UInt8) -> UInt16 {
        UInt16(zeroPage &+ y)
    }

    private func read8(_ address: UInt16) -> UInt8 {
        bus.read(address)
    }

    private func write8(_ address: UInt16, _ value: UInt8) {
        bus.write(address, value)
    }

    private func read16(_ address: UInt16) -> UInt16 {
        let lo = UInt16(read8(address))
        let hi = UInt16(read8(address &+ 1))
        return lo | (hi << 8)
    }

    private func push8(_ value: UInt8) {
        write8(0x0100 | UInt16(sp), value)
        sp &-= 1
    }

    private func pop8() -> UInt8 {
        sp &+= 1
        return read8(0x0100 | UInt16(sp))
    }

    private func push16(_ value: UInt16) {
        push8(UInt8((value >> 8) & 0xff))
        push8(UInt8(value & 0xff))
    }

    private func pop16() -> UInt16 {
        let lo = UInt16(pop8())
        let hi = UInt16(pop8())
        return lo | (hi << 8)
    }

    private func setZN(_ value: UInt8) {
        setFlag(0x02, value == 0)
        setFlag(0x80, (value & 0x80) != 0)
    }

    private func compare(_ lhs: UInt8, _ rhs: UInt8) {
        let result = lhs &- rhs
        setFlag(0x01, lhs >= rhs)
        setZN(result)
    }

    private func asl(_ value: UInt8) -> UInt8 {
        setFlag(0x01, (value & 0x80) != 0)
        let result = value << 1
        setZN(result)
        return result
    }

    private func lsr(_ value: UInt8) -> UInt8 {
        setFlag(0x01, (value & 0x01) != 0)
        let result = value >> 1
        setZN(result)
        return result
    }

    private func rol(_ value: UInt8) -> UInt8 {
        let carryIn: UInt8 = flag(0x01) ? 0x01 : 0x00
        setFlag(0x01, (value & 0x80) != 0)
        let result = (value << 1) | carryIn
        setZN(result)
        return result
    }

    private func ror(_ value: UInt8) -> UInt8 {
        let carryIn: UInt8 = flag(0x01) ? 0x80 : 0x00
        setFlag(0x01, (value & 0x01) != 0)
        let result = (value >> 1) | carryIn
        setZN(result)
        return result
    }

    private func bit(_ value: UInt8) {
        setFlag(0x02, (a & value) == 0)
        setFlag(0x40, (value & 0x40) != 0)
        setFlag(0x80, (value & 0x80) != 0)
    }

    private func adc(_ value: UInt8) {
        if flag(0x08) {
            decimalADC(value)
            return
        }
        let carry = flag(0x01) ? 1 : 0
        let sum = UInt16(a) + UInt16(value) + UInt16(carry)
        let result = UInt8(truncatingIfNeeded: sum)
        setFlag(0x01, sum > 0xff)
        setFlag(0x40, ((~(a ^ value) & (a ^ result)) & 0x80) != 0)
        a = result
        setZN(a)
    }

    private func sbc(_ value: UInt8) {
        adc(value ^ 0xff)
    }

    private func decimalADC(_ value: UInt8) {
        let carry = flag(0x01) ? 1 : 0
        var low = Int(a & 0x0f) + Int(value & 0x0f) + carry
        var high = Int((a >> 4) & 0x0f) + Int((value >> 4) & 0x0f)
        if low > 9 {
            low += 6
            high += 1
        }
        if high > 9 {
            high += 6
        }
        let binarySum = UInt16(a) + UInt16(value) + UInt16(carry)
        let result = UInt8(((high << 4) | (low & 0x0f)) & 0xff)
        setFlag(0x01, high > 15)
        setFlag(0x40, ((~(a ^ value) & (a ^ UInt8(truncatingIfNeeded: binarySum))) & 0x80) != 0)
        a = result
        setZN(a)
    }

    private func setCarry(_ enabled: Bool) { setFlag(0x01, enabled) }
    private func setInterruptDisable(_ enabled: Bool) { setFlag(0x04, enabled) }
    private func setDecimal(_ enabled: Bool) { setFlag(0x08, enabled) }
    private func setOverflow(_ enabled: Bool) { setFlag(0x40, enabled) }

    private func flag(_ mask: UInt8) -> Bool {
        (status & mask) != 0
    }

    private func setFlag(_ mask: UInt8, _ enabled: Bool) {
        if enabled {
            status |= mask
        } else {
            status &= ~mask
        }
    }
}
