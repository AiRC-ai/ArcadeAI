import CryptoKit
import Foundation

struct TempestROMFileSpec: Equatable {
    var name: String
    var region: String
    var offset: Int
    var size: Int
    var sha1: String
}

struct TempestROMSet {
    let root: URL
    let mainCPU: [UInt8]
    let vectorROM: [UInt8]
    let avgPROM: [UInt8]
    let mathPROMs: [[UInt8]]
    let earom: [UInt8]
    let earomURL: URL

    static let mainCPUSize = 0x10000
    static let vectorROMSize = 0x1000

    static let requiredFiles: [TempestROMFileSpec] = [
        .init(name: "136002-113.d1", region: "maincpu", offset: 0x9000, size: 2048, sha1: "38a1e8a8f65b7887cf3e190269fe4ce2c6f818aa"),
        .init(name: "136002-114.e1", region: "maincpu", offset: 0x9800, size: 2048, sha1: "ed8ff0ca969da6672a7683b93d4fcf2935a0d903"),
        .init(name: "136002-115.f1", region: "maincpu", offset: 0xa000, size: 2048, sha1: "bd04fcfbbba995e08c3144c1474fcddaaeb1c700"),
        .init(name: "136002-116.h1", region: "maincpu", offset: 0xa800, size: 2048, sha1: "a013ede292189a8f5a907de882ee1a573d784b3c"),
        .init(name: "136002-117.j1", region: "maincpu", offset: 0xb000, size: 2048, sha1: "470d914fa52fce3786cb6330889876d3547dca65"),
        .init(name: "136002-118.k1", region: "maincpu", offset: 0xb800, size: 2048, sha1: "f213166d3970e0bd0f29d8dea8d6afa6990cce38"),
        .init(name: "136002-119.lm1", region: "maincpu", offset: 0xc000, size: 2048, sha1: "ea302e43a313a5a18115e74ddbaaedde0fbecda7"),
        .init(name: "136002-120.mn1", region: "maincpu", offset: 0xc800, size: 2048, sha1: "48f1e8bed7ec6afa0b4c549a30e5ec331c071e40"),
        .init(name: "136002-121.p1", region: "maincpu", offset: 0xd000, size: 2048, sha1: "9980606376a79ba94f8e2a325871a6c8d10d83fc"),
        .init(name: "136002-122.r1", region: "maincpu", offset: 0xd800, size: 2048, sha1: "c862a0d4ea330161e4c3cc8e5e9ad38893fffbd4"),
        .init(name: "136002-123.np3", region: "vectorrom", offset: 0x0000, size: 2048, sha1: "686c8b9b8901262e743497cee7f2f7dd5cb3af7e"),
        .init(name: "136002-124.r3", region: "vectorrom", offset: 0x0800, size: 2048, sha1: "a30a3662c740810c0f20e3712679606921b8ca06"),
        .init(name: "136002-125.d7", region: "avgprom", offset: 0x0000, size: 256, sha1: "24bc0366f394ad0ec486919212e38be0f08d0239"),
    ]

    enum LoadError: Error, LocalizedError {
        case romRootNotFound
        case missingFile(String)
        case wrongSize(String, expected: Int, actual: Int)
        case sha1Mismatch(String, expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .romRootNotFound:
                return "Could not find bundled or source roms/tempest1 directory"
            case .missingFile(let name):
                return "Missing Tempest ROM file \(name)"
            case .wrongSize(let name, let expected, let actual):
                return "\(name) has \(actual) bytes, expected \(expected)"
            case .sha1Mismatch(let name, let expected, let actual):
                return "\(name) SHA1 \(actual), expected \(expected)"
            }
        }
    }

    static func load() throws -> TempestROMSet {
        let root = try locateROMRoot()
        var main = Array(repeating: UInt8(0), count: mainCPUSize)
        var vector = Array(repeating: UInt8(0), count: vectorROMSize)
        var avg: [UInt8] = []

        for spec in requiredFiles {
            let bytes = try loadFile(spec, from: root)
            switch spec.region {
            case "maincpu":
                main.replaceSubrange(spec.offset..<(spec.offset + spec.size), with: bytes)
            case "vectorrom":
                vector.replaceSubrange(spec.offset..<(spec.offset + spec.size), with: bytes)
            case "avgprom":
                avg = bytes
            default:
                break
            }
        }

        let mathNames = [
            "136002-132.l1", "136002-131.k1", "136002-130.j1",
            "136002-129.h1", "136002-128.f1", "136002-127.e1",
        ]
        let math = mathNames.compactMap { name -> [UInt8]? in
            let url = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return Array(data)
        }
        let earom = loadEAROM(nextTo: root)
        return TempestROMSet(
            root: root,
            mainCPU: main,
            vectorROM: vector,
            avgPROM: avg,
            mathPROMs: math,
            earom: earom.bytes,
            earomURL: earom.url
        )
    }

    private static func loadEAROM(nextTo romRoot: URL) -> (bytes: [UInt8], url: URL) {
        let resourceRoot = romRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = resourceRoot
            .appendingPathComponent("nvram/tempest1/earom")
        let writableURL = writableEAROMURL(fallback: sourceURL)
        if let data = try? Data(contentsOf: writableURL), data.count >= 0x40 {
            return (Array(data.prefix(0x40)), writableURL)
        }
        if let data = try? Data(contentsOf: sourceURL), data.count >= 0x40 {
            return (Array(data.prefix(0x40)), writableURL)
        }
        return (defaultEAROM(), writableURL)
    }

    private static func writableEAROMURL(fallback sourceURL: URL) -> URL {
        let resourcePath = Bundle.main.resourceURL?.path ?? ""
        if !resourcePath.isEmpty && sourceURL.path.hasPrefix(resourcePath) {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            return appSupport
                .appendingPathComponent("Tempest AI", isDirectory: true)
                .appendingPathComponent("nvram/tempest1/earom")
        }
        return sourceURL
    }

    private static func defaultEAROM() -> [UInt8] {
        var data = Array(repeating: UInt8(0), count: 0x40)
        let rcc: [UInt8] = [0x02, 0x02, 0x11]
        for slot in 0..<3 {
            data.replaceSubrange((slot * 3)..<((slot * 3) + 3), with: rcc)
        }
        data[9] = 0x3f
        return data
    }

    private static func locateROMRoot() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("roms/tempest1", isDirectory: true) {
            candidates.append(bundled)
        }
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(sourceRoot.appendingPathComponent("roms/tempest1", isDirectory: true))

        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw LoadError.romRootNotFound
    }

    private static func loadFile(_ spec: TempestROMFileSpec, from root: URL) throws -> [UInt8] {
        let url = root.appendingPathComponent(spec.name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.missingFile(spec.name)
        }
        let data = try Data(contentsOf: url)
        guard data.count == spec.size else {
            throw LoadError.wrongSize(spec.name, expected: spec.size, actual: data.count)
        }
        let actual = Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == spec.sha1 else {
            throw LoadError.sha1Mismatch(spec.name, expected: spec.sha1, actual: actual)
        }
        return Array(data)
    }
}
