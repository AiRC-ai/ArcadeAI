import Foundation
import MLX
import MLXNN
import MLXOptimizers
import MLXRandom

/// MLX-backed Rainbow-Attention policy for Tempest.
///
/// The state-to-token packing remains in Swift so it can exactly mirror the
/// original Python feature contract and nearest-first enemy ordering. Every
/// learned layer after that point runs through MLX arrays: lane/enemy embeds,
/// 8-head lane cross-attention, trunk, dueling C51 heads, support expectation,
/// and greedy action selection.
class MLXRainbowTrainableNetwork: Module {
    static let stateSize = 195
    static let actionCount = 44
    static let atomCount = 51
    static let attentionDim = 128
    static let attentionHeads = 8
    static let enemySlots = 7
    static let laneCount = 16

    private let laneSin: [Float]
    private let laneCos: [Float]
    private let laneEmbedWeight: MLXArray
    private let laneEmbedBias: MLXArray
    private let laneNormWeight: MLXArray
    private let laneNormBias: MLXArray
    private let enemyEmbedWeight: MLXArray
    private let enemyEmbedBias: MLXArray
    private let enemyNormWeight: MLXArray
    private let enemyNormBias: MLXArray
    private let queryWeight: MLXArray
    private let queryBias: MLXArray
    private let keyWeight: MLXArray
    private let keyBias: MLXArray
    private let valueWeight: MLXArray
    private let valueBias: MLXArray
    private let crossOutProjWeight: MLXArray
    private let crossOutProjBias: MLXArray
    private let crossNormWeight: MLXArray
    private let crossNormBias: MLXArray
    private let support: MLXArray
    private let trunk0Weight: MLXArray
    private let trunk0Bias: MLXArray
    private let trunk1Weight: MLXArray
    private let trunk1Bias: MLXArray
    private let trunk3Weight: MLXArray
    private let trunk3Bias: MLXArray
    private let trunk4Weight: MLXArray
    private let trunk4Bias: MLXArray
    private let valFCWeight: MLXArray
    private let valFCBias: MLXArray
    private let valOutWeight: MLXArray
    private let valOutBias: MLXArray
    private let advFCWeight: MLXArray
    private let advFCBias: MLXArray
    private let advOutWeight: MLXArray
    private let advOutBias: MLXArray
    private let checkpointHash: String
    private let tensorShapes: [String: [Int]]

    init?(package: SwiftTensorPackage, section: String = "online_state_dict") {
        guard package.stateSize == Self.stateSize,
              package.actionCount == Self.actionCount,
              package.atoms == Self.atomCount,
              package.attentionDim == Self.attentionDim,
              package.attentionHeads == Self.attentionHeads else {
            return nil
        }
        do {
            laneSin = try package.requireTensor(
                section: section,
                name: "_lane_sin_pos"
            ).values
            laneCos = try package.requireTensor(
                section: section,
                name: "_lane_cos_pos"
            ).values

            laneEmbedWeight = try Self.tensor(package, section, "lane_cross_attn.lane_embed.weight", [128, 5])
            laneEmbedBias = try Self.tensor(package, section, "lane_cross_attn.lane_embed.bias", [128])
            laneNormWeight = try Self.tensor(package, section, "lane_cross_attn.lane_norm.weight", [128])
            laneNormBias = try Self.tensor(package, section, "lane_cross_attn.lane_norm.bias", [128])
            enemyEmbedWeight = try Self.tensor(package, section, "lane_cross_attn.enemy_embed.weight", [128, 14])
            enemyEmbedBias = try Self.tensor(package, section, "lane_cross_attn.enemy_embed.bias", [128])
            enemyNormWeight = try Self.tensor(package, section, "lane_cross_attn.enemy_norm.weight", [128])
            enemyNormBias = try Self.tensor(package, section, "lane_cross_attn.enemy_norm.bias", [128])

            let inProjWeight = try package.requireTensor(
                section: section,
                name: "lane_cross_attn.cross_attn.in_proj_weight"
            )
            let inProjBias = try package.requireTensor(
                section: section,
                name: "lane_cross_attn.cross_attn.in_proj_bias"
            )
            guard inProjWeight.spec.shape == [384, 128],
                  inProjBias.spec.shape == [384] else {
                return nil
            }
            queryWeight = MLXArray(Array(inProjWeight.values[0..<(128 * 128)]), [128, 128])
            keyWeight = MLXArray(Array(inProjWeight.values[(128 * 128)..<(256 * 128)]), [128, 128])
            valueWeight = MLXArray(Array(inProjWeight.values[(256 * 128)..<(384 * 128)]), [128, 128])
            queryBias = MLXArray(Array(inProjBias.values[0..<128]), [128])
            keyBias = MLXArray(Array(inProjBias.values[128..<256]), [128])
            valueBias = MLXArray(Array(inProjBias.values[256..<384]), [128])

            crossOutProjWeight = try Self.tensor(package, section, "lane_cross_attn.cross_attn.out_proj.weight", [128, 128])
            crossOutProjBias = try Self.tensor(package, section, "lane_cross_attn.cross_attn.out_proj.bias", [128])
            crossNormWeight = try Self.tensor(package, section, "lane_cross_attn.cross_norm.weight", [128])
            crossNormBias = try Self.tensor(package, section, "lane_cross_attn.cross_norm.bias", [128])
            support = try Self.tensor(package, section, "support", [51]).reshaped([1, 1, Self.atomCount])

            trunk0Weight = try Self.tensor(package, section, "trunk.0.weight", [384, 323])
            trunk0Bias = try Self.tensor(package, section, "trunk.0.bias", [384])
            trunk1Weight = try Self.tensor(package, section, "trunk.1.weight", [384])
            trunk1Bias = try Self.tensor(package, section, "trunk.1.bias", [384])
            trunk3Weight = try Self.tensor(package, section, "trunk.3.weight", [384, 384])
            trunk3Bias = try Self.tensor(package, section, "trunk.3.bias", [384])
            trunk4Weight = try Self.tensor(package, section, "trunk.4.weight", [384])
            trunk4Bias = try Self.tensor(package, section, "trunk.4.bias", [384])

            valFCWeight = try Self.tensor(package, section, "val_fc.weight", [192, 384])
            valFCBias = try Self.tensor(package, section, "val_fc.bias", [192])
            valOutWeight = try Self.tensor(package, section, "val_out.weight", [51, 192])
            valOutBias = try Self.tensor(package, section, "val_out.bias", [51])
            advFCWeight = try Self.tensor(package, section, "adv_fc.weight", [192, 384])
            advFCBias = try Self.tensor(package, section, "adv_fc.bias", [192])
            advOutWeight = try Self.tensor(package, section, "adv_out.weight", [44 * 51, 192])
            advOutBias = try Self.tensor(package, section, "adv_out.bias", [44 * 51])

            checkpointHash = package.checkpointSHA256
            tensorShapes = Dictionary(
                uniqueKeysWithValues: package.tensors
                    .filter { $0.section == section }
                    .map { ($0.name, $0.shape) }
            )
            super.init()
            freeze(recursive: false, keys: ["support"])
            _ = Adam(learningRate: MLXRainbowTrainingOps.learningRate)
            MLXRandom.seed(0x5445_4d50)
        } catch {
            return nil
        }
    }

    var modelIdentity: String {
        "MLX Rainbow-Attention \(checkpointHash.prefix(12))"
    }

    var loadedTensorShapes: [String: [Int]] {
        tensorShapes
    }

    func atomLogits(for states: [[Float]]) -> MLXArray? {
        guard !states.isEmpty,
              states.allSatisfy({ $0.count == Self.stateSize }) else {
            return nil
        }
        let batchSize = states.count
        let (laneTokens, enemyTokens, enemyMask) = packedTokens(for: states)
        let laneInput = MLXArray(laneTokens, [batchSize, Self.laneCount, 5])
        let enemyInput = MLXArray(enemyTokens, [batchSize, Self.enemySlots, 14])
        let mask = MLXArray(enemyMask, [batchSize, 1, 1, Self.enemySlots])

        let laneEmbeddings = layerNorm(
            linear(laneInput, weight: laneEmbedWeight, bias: laneEmbedBias),
            gamma: laneNormWeight,
            beta: laneNormBias
        )
        let enemyEmbeddings = layerNorm(
            linear(enemyInput, weight: enemyEmbedWeight, bias: enemyEmbedBias),
            gamma: enemyNormWeight,
            beta: enemyNormBias
        )

        let query = linear(laneEmbeddings, weight: queryWeight, bias: queryBias)
            .reshaped([batchSize, Self.laneCount, Self.attentionHeads, 16])
            .transposed(0, 2, 1, 3)
        let key = linear(enemyEmbeddings, weight: keyWeight, bias: keyBias)
            .reshaped([batchSize, Self.enemySlots, Self.attentionHeads, 16])
            .transposed(0, 2, 1, 3)
        let value = linear(enemyEmbeddings, weight: valueWeight, bias: valueBias)
            .reshaped([batchSize, Self.enemySlots, Self.attentionHeads, 16])
            .transposed(0, 2, 1, 3)

        let scores = matmul(query, key.transposed(0, 1, 3, 2)) * Float(1.0 / sqrt(16.0))
        let weights = softmax(scores + mask, axis: -1)
        let context = matmul(weights, value)
            .transposed(0, 2, 1, 3)
            .reshaped([batchSize, Self.laneCount, Self.attentionDim])
        let attended = linear(context, weight: crossOutProjWeight, bias: crossOutProjBias)
        let enriched = layerNorm(
            attended + laneEmbeddings,
            gamma: crossNormWeight,
            beta: crossNormBias
        )
        let pooled = enriched.mean(axis: 1)

        let stateInput = MLXArray(states.flatMap { $0 }, [batchSize, Self.stateSize])
        let trunkInput = concatenated([stateInput, pooled], axis: 1)
        var x = linear(trunkInput, weight: trunk0Weight, bias: trunk0Bias)
        x = relu(layerNorm(x, gamma: trunk1Weight, beta: trunk1Bias))
        x = linear(x, weight: trunk3Weight, bias: trunk3Bias)
        x = relu(layerNorm(x, gamma: trunk4Weight, beta: trunk4Bias))

        let valueHidden = relu(linear(x, weight: valFCWeight, bias: valFCBias))
        let valueAtoms = linear(valueHidden, weight: valOutWeight, bias: valOutBias)
            .expandedDimensions(axis: 1)
        let advantageHidden = relu(linear(x, weight: advFCWeight, bias: advFCBias))
        let advantageAtoms = linear(advantageHidden, weight: advOutWeight, bias: advOutBias)
            .reshaped([batchSize, Self.actionCount, Self.atomCount])
        return valueAtoms + advantageAtoms - advantageAtoms.mean(axis: 1, keepDims: true)
    }

    func actionDistributions(for states: [[Float]]) -> MLXArray? {
        guard let logits = atomLogits(for: states) else { return nil }
        return softmax(logits, axis: -1)
    }

    func qValues(for states: [[Float]]) -> MLXArray? {
        guard let distributions = actionDistributions(for: states) else { return nil }
        return MLXRainbowTrainingOps.qValues(distributions: distributions, support: support)
    }

    func greedyActionIndices(for states: [[Float]]) -> [Int]? {
        guard let qValues = qValues(for: states) else { return nil }
        let indices = MLXRainbowTrainingOps.greedyActionIndices(qValues: qValues)
            .asArray(Int32.self)
        guard indices.count == states.count else {
            return nil
        }
        return indices.map { max(0, min(Self.actionCount - 1, Int($0))) }
    }

    func actions(for states: [[Float]]) -> [TempestAgentAction]? {
        greedyActionIndices(for: states)?.map {
            TempestActionSpace.action(for: $0)
        }
    }

    func sync(from other: MLXRainbowTrainableNetwork) {
        update(parameters: other.parameters())
        eval(self)
    }

    func saveParameters(to directory: URL, manifestName: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let flat = parameters().flattened()
            let entries = try flat.map { key, array in
                let fileName = key
                    .replacingOccurrences(of: ".", with: "__")
                    .appending(".f32")
                let url = directory.appendingPathComponent(fileName)
                let values = array.asArray(Float.self)
                let data = values.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }
                try data.write(to: url, options: .atomic)
                return SavedTensorEntry(key: key, shape: array.shape, file: fileName)
            }
            let manifest = SavedTensorManifest(version: 1, tensors: entries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(
                to: directory.appendingPathComponent(manifestName),
                options: .atomic
            )
            return true
        } catch {
            return false
        }
    }

    func loadParameters(from directory: URL, manifestName: String) -> Bool {
        do {
            let manifestURL = directory.appendingPathComponent(manifestName)
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(
                SavedTensorManifest.self,
                from: manifestData
            )
            let flat: [(String, MLXArray)] = try manifest.tensors.map { entry in
                let url = directory.appendingPathComponent(entry.file)
                let data = try Data(contentsOf: url)
                let expectedCount = entry.shape.reduce(1, *)
                guard data.count == expectedCount * MemoryLayout<Float>.size else {
                    throw SavedTensorError.invalidData
                }
                let values = data.withUnsafeBytes { raw -> [Float] in
                    Array(raw.bindMemory(to: Float.self))
                }
                return (entry.key, MLXArray(values, entry.shape))
            }
            try update(parameters: ModuleParameters.unflattened(flat), verify: .shapeMismatch)
            eval(self)
            return true
        } catch {
            return false
        }
    }

    private static func tensor(
        _ package: SwiftTensorPackage,
        _ section: String,
        _ name: String,
        _ expectedShape: [Int]
    ) throws -> MLXArray {
        let tensor = try package.requireTensor(section: section, name: name)
        guard tensor.spec.shape == expectedShape else {
            throw SwiftTensorPackage.TensorLoadError.missingOrInvalid(
                section: section,
                name: name
            )
        }
        return MLXArray(tensor.values, expectedShape)
    }

    private func linear(_ input: MLXArray, weight: MLXArray, bias: MLXArray) -> MLXArray {
        matmul(input, weight.T) + bias
    }

    private func layerNorm(_ input: MLXArray, gamma: MLXArray, beta: MLXArray) -> MLXArray {
        let mean = input.mean(axis: -1, keepDims: true)
        let centered = input - mean
        let variance = (centered * centered).mean(axis: -1, keepDims: true)
        return centered * rsqrt(variance + Float(1e-5)) * gamma + beta
    }

    private func packedTokens(
        for states: [[Float]]
    ) -> (laneTokens: [Float], enemyTokens: [Float], enemyMask: [Float]) {
        var laneTokens: [Float] = []
        var enemyTokens: [Float] = []
        var enemyMask: [Float] = []
        laneTokens.reserveCapacity(states.count * Self.laneCount * 5)
        enemyTokens.reserveCapacity(states.count * Self.enemySlots * 14)
        enemyMask.reserveCapacity(states.count * Self.enemySlots)

        for state in states {
            laneTokens.append(contentsOf: buildLaneTokens(state: state).flatMap { $0 })
            let (tokens, mask) = buildEnemyTokens(state: state)
            enemyTokens.append(contentsOf: tokens.flatMap { $0 })
            enemyMask.append(contentsOf: mask.map { $0 ? -1.0e9 : 0.0 })
        }
        return (laneTokens, enemyTokens, enemyMask)
    }

    private func buildLaneTokens(state: [Float]) -> [[Float]] {
        let playerLane = min(15, max(0, Int((state[5] * 15).rounded())))
        return (0..<Self.laneCount).map { lane in
            [
                state[31 + lane],
                state[47 + lane],
                lane == playerLane ? 1 : 0,
                lane < laneSin.count ? laneSin[lane] : 0,
                lane < laneCos.count ? laneCos[lane] : 0
            ]
        }
    }

    private func buildEnemyTokens(state: [Float]) -> ([[Float]], [Bool]) {
        var entries: [(token: [Float], depth: Float, empty: Bool)] = []
        let playerPosNorm = state[5]
        for slot in 0..<Self.enemySlots {
            let depth = state[135 + slot]
            let empty = depth < 1e-6
            var token: [Float] = []
            token.reserveCapacity(14)
            for feature in 0..<6 {
                token.append(state[86 + slot * 6 + feature])
            }
            let enemyRelSeg = state[128 + slot]
            let enemyAbsRaw = playerPosNorm * 15 + enemyRelSeg * 15
            var enemyAbsFrac = enemyAbsRaw.truncatingRemainder(dividingBy: 16.0) / 16.0
            if enemyAbsFrac < 0 {
                enemyAbsFrac += 1.0
            }
            token.append(enemyRelSeg)
            token.append(depth)
            token.append(state[142 + slot])
            token.append(state[171 + slot])
            token.append(state[181 + slot])
            token.append(state[188 + slot])
            token.append(sin(Float.pi * 2 * enemyAbsFrac))
            token.append(cos(Float.pi * 2 * enemyAbsFrac))
            entries.append((token, empty ? 2.0 : depth, empty))
        }
        entries.sort { lhs, rhs in
            if lhs.depth == rhs.depth { return false }
            return lhs.depth < rhs.depth
        }
        let allEmpty = entries.allSatisfy(\.empty)
        return (
            entries.map(\.token),
            entries.map { allEmpty ? false : $0.empty }
        )
    }

    private struct SavedTensorManifest: Codable {
        var version: Int
        var tensors: [SavedTensorEntry]
    }

    private struct SavedTensorEntry: Codable {
        var key: String
        var shape: [Int]
        var file: String
    }

    private enum SavedTensorError: Error {
        case invalidData
    }
}

final class MLXRainbowNetwork: MLXRainbowTrainableNetwork {}
