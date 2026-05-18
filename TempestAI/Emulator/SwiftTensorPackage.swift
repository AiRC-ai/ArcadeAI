import CryptoKit
import Foundation

struct SwiftTensorPackage: Decodable {
    struct Tensor: Decodable {
        let section: String
        let name: String
        let dtype: String
        let shape: [Int]
        let file: String
        let sha256: String
    }

    let format: String
    let formatVersion: Int
    let checkpointSHA256: String
    let engineVersion: Int
    let stateSize: Int
    let actionCount: Int
    let atoms: Int
    let attentionDim: Int
    let attentionHeads: Int
    let trainingSteps: Int
    let frameCount: Int
    let totalTrainingSteps: Int
    let epsilon: Double
    let expertRatio: Double
    let tensors: [Tensor]
    let rootURL: URL?

    enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case checkpointSHA256 = "checkpoint_sha256"
        case engineVersion = "engine_version"
        case stateSize = "state_size"
        case actionCount = "action_count"
        case atoms
        case attentionDim = "attention_dim"
        case attentionHeads = "attention_heads"
        case trainingSteps = "training_steps"
        case frameCount = "frame_count"
        case totalTrainingSteps = "total_training_steps"
        case epsilon
        case expertRatio = "expert_ratio"
        case tensors
    }

    struct TensorData {
        let spec: Tensor
        let values: [Float]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        checkpointSHA256 = try c.decode(String.self, forKey: .checkpointSHA256)
        engineVersion = try c.decode(Int.self, forKey: .engineVersion)
        stateSize = try c.decode(Int.self, forKey: .stateSize)
        actionCount = try c.decode(Int.self, forKey: .actionCount)
        atoms = try c.decode(Int.self, forKey: .atoms)
        attentionDim = try c.decode(Int.self, forKey: .attentionDim)
        attentionHeads = try c.decode(Int.self, forKey: .attentionHeads)
        trainingSteps = try c.decode(Int.self, forKey: .trainingSteps)
        frameCount = try c.decode(Int.self, forKey: .frameCount)
        totalTrainingSteps = try c.decode(Int.self, forKey: .totalTrainingSteps)
        epsilon = try c.decode(Double.self, forKey: .epsilon)
        expertRatio = try c.decode(Double.self, forKey: .expertRatio)
        tensors = try c.decode([Tensor].self, forKey: .tensors)
        rootURL = nil
    }

    private init(decoded package: SwiftTensorPackage, rootURL: URL) {
        format = package.format
        formatVersion = package.formatVersion
        checkpointSHA256 = package.checkpointSHA256
        engineVersion = package.engineVersion
        stateSize = package.stateSize
        actionCount = package.actionCount
        atoms = package.atoms
        attentionDim = package.attentionDim
        attentionHeads = package.attentionHeads
        trainingSteps = package.trainingSteps
        frameCount = package.frameCount
        totalTrainingSteps = package.totalTrainingSteps
        epsilon = package.epsilon
        expertRatio = package.expertRatio
        tensors = package.tensors
        self.rootURL = rootURL
    }

    static func bundled() -> SwiftTensorPackage? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("models/swift_tensors/manifest.json") else {
            return nil
        }
        return load(from: url)
    }

    static func load(from url: URL) -> SwiftTensorPackage? {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(SwiftTensorPackage.self, from: data)
            let package = SwiftTensorPackage(
                decoded: decoded,
                rootURL: url.deletingLastPathComponent()
            )
            guard package.format == "tempest-swift-tensor-package",
                  package.stateSize == 195,
                  package.actionCount == TempestActionSpace.actionCount,
                  package.atoms == 51,
                  package.attentionDim == 128,
                  package.attentionHeads == 8 else {
                return nil
            }
            return package
        } catch {
            return nil
        }
    }

    func tensor(section: String, name: String) -> TensorData? {
        guard let rootURL else { return nil }
        guard let spec = tensors.first(where: {
            $0.section == section && $0.name == name
        }) else {
            return nil
        }
        let url = rootURL.appendingPathComponent(spec.file)
        do {
            let data = try Data(contentsOf: url)
            let actual = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actual == spec.sha256 else { return nil }
            let expectedCount = spec.shape.reduce(1, *)
            guard data.count == expectedCount * MemoryLayout<Float>.size else {
                return nil
            }
            let values = data.withUnsafeBytes { raw -> [Float] in
                let buffer = raw.bindMemory(to: Float.self)
                return Array(buffer)
            }
            return TensorData(spec: spec, values: values)
        } catch {
            return nil
        }
    }

    func requireTensor(section: String, name: String) throws -> TensorData {
        if let tensor = tensor(section: section, name: name) {
            return tensor
        }
        throw TensorLoadError.missingOrInvalid(section: section, name: name)
    }

    enum TensorLoadError: Error {
        case missingOrInvalid(section: String, name: String)
    }
}
