import Foundation

final class SwiftRainbowModel {
    private let laneSin: [Float]
    private let laneCos: [Float]
    private let laneEmbedWeight: [Float]
    private let laneEmbedBias: [Float]
    private let laneNormWeight: [Float]
    private let laneNormBias: [Float]
    private let enemyEmbedWeight: [Float]
    private let enemyEmbedBias: [Float]
    private let enemyNormWeight: [Float]
    private let enemyNormBias: [Float]
    private let crossInProjWeight: [Float]
    private let crossInProjBias: [Float]
    private let crossOutProjWeight: [Float]
    private let crossOutProjBias: [Float]
    private let crossNormWeight: [Float]
    private let crossNormBias: [Float]
    private let support: [Float]
    private let trunk0Weight: [Float]
    private let trunk0Bias: [Float]
    private let trunk1Weight: [Float]
    private let trunk1Bias: [Float]
    private let trunk3Weight: [Float]
    private let trunk3Bias: [Float]
    private let trunk4Weight: [Float]
    private let trunk4Bias: [Float]
    private let valFCWeight: [Float]
    private let valFCBias: [Float]
    private let valOutWeight: [Float]
    private let valOutBias: [Float]
    private let advFCWeight: [Float]
    private let advFCBias: [Float]
    private let advOutWeight: [Float]
    private let advOutBias: [Float]

    init?(package: SwiftTensorPackage, section: String = "online_state_dict") {
        do {
            laneSin = try package.requireTensor(section: section, name: "_lane_sin_pos").values
            laneCos = try package.requireTensor(section: section, name: "_lane_cos_pos").values
            laneEmbedWeight = try package.requireTensor(section: section, name: "lane_cross_attn.lane_embed.weight").values
            laneEmbedBias = try package.requireTensor(section: section, name: "lane_cross_attn.lane_embed.bias").values
            laneNormWeight = try package.requireTensor(section: section, name: "lane_cross_attn.lane_norm.weight").values
            laneNormBias = try package.requireTensor(section: section, name: "lane_cross_attn.lane_norm.bias").values
            enemyEmbedWeight = try package.requireTensor(section: section, name: "lane_cross_attn.enemy_embed.weight").values
            enemyEmbedBias = try package.requireTensor(section: section, name: "lane_cross_attn.enemy_embed.bias").values
            enemyNormWeight = try package.requireTensor(section: section, name: "lane_cross_attn.enemy_norm.weight").values
            enemyNormBias = try package.requireTensor(section: section, name: "lane_cross_attn.enemy_norm.bias").values
            crossInProjWeight = try package.requireTensor(section: section, name: "lane_cross_attn.cross_attn.in_proj_weight").values
            crossInProjBias = try package.requireTensor(section: section, name: "lane_cross_attn.cross_attn.in_proj_bias").values
            crossOutProjWeight = try package.requireTensor(section: section, name: "lane_cross_attn.cross_attn.out_proj.weight").values
            crossOutProjBias = try package.requireTensor(section: section, name: "lane_cross_attn.cross_attn.out_proj.bias").values
            crossNormWeight = try package.requireTensor(section: section, name: "lane_cross_attn.cross_norm.weight").values
            crossNormBias = try package.requireTensor(section: section, name: "lane_cross_attn.cross_norm.bias").values
            support = try package.requireTensor(section: section, name: "support").values
            trunk0Weight = try package.requireTensor(section: section, name: "trunk.0.weight").values
            trunk0Bias = try package.requireTensor(section: section, name: "trunk.0.bias").values
            trunk1Weight = try package.requireTensor(section: section, name: "trunk.1.weight").values
            trunk1Bias = try package.requireTensor(section: section, name: "trunk.1.bias").values
            trunk3Weight = try package.requireTensor(section: section, name: "trunk.3.weight").values
            trunk3Bias = try package.requireTensor(section: section, name: "trunk.3.bias").values
            trunk4Weight = try package.requireTensor(section: section, name: "trunk.4.weight").values
            trunk4Bias = try package.requireTensor(section: section, name: "trunk.4.bias").values
            valFCWeight = try package.requireTensor(section: section, name: "val_fc.weight").values
            valFCBias = try package.requireTensor(section: section, name: "val_fc.bias").values
            valOutWeight = try package.requireTensor(section: section, name: "val_out.weight").values
            valOutBias = try package.requireTensor(section: section, name: "val_out.bias").values
            advFCWeight = try package.requireTensor(section: section, name: "adv_fc.weight").values
            advFCBias = try package.requireTensor(section: section, name: "adv_fc.bias").values
            advOutWeight = try package.requireTensor(section: section, name: "adv_out.weight").values
            advOutBias = try package.requireTensor(section: section, name: "adv_out.bias").values
        } catch {
            return nil
        }
    }

    func action(for state: [Float]) -> TempestAgentAction? {
        guard let qValues = qValues(for: state) else { return nil }
        guard let bestAction = qValues.indices.max(by: { qValues[$0] < qValues[$1] }) else {
            return nil
        }
        return TempestActionSpace.action(for: bestAction)
    }

    func qValues(for state: [Float]) -> [Float]? {
        guard let probabilities = actionDistributions(for: state) else { return nil }
        return probabilities.map { actionDistribution in
            var q = Float(0)
            for atom in 0..<min(actionDistribution.count, support.count) {
                q += actionDistribution[atom] * support[atom]
            }
            return q
        }
    }

    func actionDistributions(for state: [Float]) -> [[Float]]? {
        guard state.count == 195 else { return nil }
        let logits = actionAtomLogits(for: state)
        return logits.map { softmax($0) }
    }

    func actionAtomLogits(for state: [Float]) -> [[Float]] {
        var input = state
        input.append(contentsOf: laneCrossAttention(state: state))

        var x = linear(input, weight: trunk0Weight, bias: trunk0Bias, out: 384, input: 323)
        layerNorm(&x, gamma: trunk1Weight, beta: trunk1Bias)
        relu(&x)
        x = linear(x, weight: trunk3Weight, bias: trunk3Bias, out: 384, input: 384)
        layerNorm(&x, gamma: trunk4Weight, beta: trunk4Bias)
        relu(&x)

        var valueHidden = linear(x, weight: valFCWeight, bias: valFCBias, out: 192, input: 384)
        relu(&valueHidden)
        let valueAtoms = linear(valueHidden, weight: valOutWeight, bias: valOutBias, out: 51, input: 192)

        var advHidden = linear(x, weight: advFCWeight, bias: advFCBias, out: 192, input: 384)
        relu(&advHidden)
        let advantageAtoms = linear(advHidden, weight: advOutWeight, bias: advOutBias, out: 44 * 51, input: 192)

        var meanAdvantage = Array(repeating: Float(0), count: 51)
        for atom in 0..<51 {
            for action in 0..<TempestActionSpace.actionCount {
                meanAdvantage[atom] += advantageAtoms[action * 51 + atom]
            }
            meanAdvantage[atom] /= Float(TempestActionSpace.actionCount)
        }
        var logitsByAction: [[Float]] = []
        logitsByAction.reserveCapacity(TempestActionSpace.actionCount)
        for action in 0..<TempestActionSpace.actionCount {
            var logits = Array(repeating: Float(0), count: 51)
            for atom in 0..<51 {
                logits[atom] = valueAtoms[atom] + advantageAtoms[action * 51 + atom] - meanAdvantage[atom]
            }
            logitsByAction.append(logits)
        }
        return logitsByAction
    }

    private func laneCrossAttention(state: [Float]) -> [Float] {
        let laneTokens = buildLaneTokens(state: state)
        let (enemyTokens, enemyMask) = buildEnemyTokens(state: state)

        let laneEmbeddings: [[Float]] = laneTokens.map { token in
            var embedded = linear(token, weight: laneEmbedWeight, bias: laneEmbedBias, out: 128, input: 5)
            layerNorm(&embedded, gamma: laneNormWeight, beta: laneNormBias)
            return embedded
        }

        let enemyEmbeddings: [[Float]] = enemyTokens.map { token in
            var embedded = linear(token, weight: enemyEmbedWeight, bias: enemyEmbedBias, out: 128, input: 14)
            layerNorm(&embedded, gamma: enemyNormWeight, beta: enemyNormBias)
            return embedded
        }

        let query = laneEmbeddings.map { inProjection($0, block: 0) }
        let key = enemyEmbeddings.map { inProjection($0, block: 1) }
        let value = enemyEmbeddings.map { inProjection($0, block: 2) }

        let headCount = 8
        let headDim = 16
        let scale = Float(1.0 / sqrt(Double(headDim)))
        var enriched: [[Float]] = Array(
            repeating: Array(repeating: Float(0), count: 128),
            count: 16
        )

        for lane in 0..<16 {
            var concat = Array(repeating: Float(0), count: 128)
            for head in 0..<headCount {
                var scores = Array(repeating: -Float.greatestFiniteMagnitude, count: 7)
                var maxScore = -Float.greatestFiniteMagnitude
                for enemy in 0..<7 where !enemyMask[enemy] {
                    var dot = Float(0)
                    for d in 0..<headDim {
                        let index = head * headDim + d
                        dot += query[lane][index] * key[enemy][index]
                    }
                    let score = dot * scale
                    scores[enemy] = score
                    maxScore = max(maxScore, score)
                }

                if !maxScore.isFinite {
                    maxScore = 0
                    for enemy in 0..<7 {
                        scores[enemy] = 0
                    }
                }

                var denom = Float(0)
                var weights = Array(repeating: Float(0), count: 7)
                for enemy in 0..<7 where !enemyMask[enemy] {
                    let weight = exp(scores[enemy] - maxScore)
                    weights[enemy] = weight
                    denom += weight
                }
                if denom <= 0 {
                    denom = 1
                }

                for d in 0..<headDim {
                    var acc = Float(0)
                    for enemy in 0..<7 where !enemyMask[enemy] {
                        let index = head * headDim + d
                        acc += (weights[enemy] / denom) * value[enemy][index]
                    }
                    concat[head * headDim + d] = acc
                }
            }

            enriched[lane] = linear(
                concat,
                weight: crossOutProjWeight,
                bias: crossOutProjBias,
                out: 128,
                input: 128
            )
            for index in 0..<128 {
                enriched[lane][index] += laneEmbeddings[lane][index]
            }
            layerNorm(&enriched[lane], gamma: crossNormWeight, beta: crossNormBias)
        }

        var pooled = Array(repeating: Float(0), count: 128)
        for lane in 0..<16 {
            for index in 0..<128 {
                pooled[index] += enriched[lane][index]
            }
        }
        for index in 0..<128 {
            pooled[index] /= 16
        }
        return pooled
    }

    private func buildLaneTokens(state: [Float]) -> [[Float]] {
        let playerLane = min(15, max(0, Int((state[5] * 15).rounded())))
        return (0..<16).map { lane in
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
        for slot in 0..<7 {
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

    private func inProjection(_ vector: [Float], block: Int) -> [Float] {
        var result = Array(repeating: Float(0), count: 128)
        let rowOffset = block * 128
        for row in 0..<128 {
            let sourceRow = rowOffset + row
            var acc = crossInProjBias[sourceRow]
            let base = sourceRow * 128
            for col in 0..<128 {
                acc += crossInProjWeight[base + col] * vector[col]
            }
            result[row] = acc
        }
        return result
    }

    private func linear(
        _ inputValues: [Float],
        weight: [Float],
        bias: [Float],
        out: Int,
        input: Int
    ) -> [Float] {
        var result = Array(repeating: Float(0), count: out)
        for row in 0..<out {
            var acc = bias[row]
            let base = row * input
            for col in 0..<input {
                acc += weight[base + col] * inputValues[col]
            }
            result[row] = acc
        }
        return result
    }

    private func layerNorm(_ values: inout [Float], gamma: [Float], beta: [Float]) {
        let mean = values.reduce(Float(0), +) / Float(values.count)
        var variance = Float(0)
        for value in values {
            let delta = value - mean
            variance += delta * delta
        }
        variance /= Float(values.count)
        let invStd = 1.0 / sqrt(variance + 1e-5)
        for index in values.indices {
            values[index] = (values[index] - mean) * invStd * gamma[index] + beta[index]
        }
    }

    private func relu(_ values: inout [Float]) {
        for index in values.indices where values[index] < 0 {
            values[index] = 0
        }
    }

    private func softmax(_ logits: [Float]) -> [Float] {
        guard let maxLogit = logits.max(), maxLogit.isFinite else {
            return Array(repeating: 1.0 / Float(max(1, logits.count)), count: logits.count)
        }
        var values = Array(repeating: Float(0), count: logits.count)
        var denom = Float(0)
        for index in logits.indices {
            let value = exp(logits[index] - maxLogit)
            values[index] = value
            denom += value
        }
        guard denom > 0 else {
            return Array(repeating: 1.0 / Float(max(1, logits.count)), count: logits.count)
        }
        for index in values.indices {
            values[index] /= denom
        }
        return values
    }
}
