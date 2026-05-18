import Foundation
import MLX
import MLXNN

enum MLXRainbowTrainingOps {
    static let replayAlpha = Float(0.7)
    static let betaStart = Float(0.4)
    static let betaEnd = Float(1.0)
    static let nStep = 12
    static let gamma = Float(0.99)
    static let c51VMin = Float(-100)
    static let c51VMax = Float(100)
    static let batchSize = 768
    static let learningRate = Float(1e-4)
    static let minimumLearningRate = Float(4e-5)
    static let minimumReplayToTrain = 10_000
    static let maxSamplesPerFrame = Float(20)
    static let targetSyncInterval = 2_500
    static let epsilonStart = Float(1.0)
    static let epsilonEnd = Float(0.01)
    static let epsilonDecayFrames = 500_000
    static let expertRatioStart = Float(0.50)
    static let expertRatioEnd = Float(0.02)
    static let expertRatioDecayFrames = 5_000_000
    static let expertBCInitialWeight = Float(1.0)
    static let expertBCMinimumWeight = Float(0.001)
    static let expertBCDecayStart = 500_000
    static let expertBCDecayFrames = 2_000_000
    static let preDeathLookback = 120
    static let preDeathPriorityBoost = Float(2.0)

    static func importanceWeightedC51Loss(
        logits: MLXArray,
        targetDistributions: MLXArray,
        importanceWeights: MLXArray
    ) -> MLXArray {
        let logProbabilities = logSoftmax(logits, axis: -1)
        let perSampleLoss = -(targetDistributions * logProbabilities).sum(axis: -1)
        return (perSampleLoss * importanceWeights).mean()
    }

    static func qValues(
        distributions: MLXArray,
        support: MLXArray
    ) -> MLXArray {
        (distributions * support).sum(axis: -1)
    }

    static func greedyActionIndices(qValues: MLXArray) -> MLXArray {
        qValues.argMax(axis: -1)
    }

    static func beta(forReplayCount replayCount: Int, annealFrames: Int = 10_000_000) -> Float {
        guard annealFrames > 0 else { return betaEnd }
        let progress = min(1.0, max(0.0, Float(replayCount) / Float(annealFrames)))
        return betaStart + (betaEnd - betaStart) * progress
    }

    static func expertBCWeight(forFrameCount frameCount: Int) -> Float {
        if frameCount < expertBCDecayStart {
            return expertBCInitialWeight
        }
        let progress = min(
            Float(1),
            Float(frameCount - expertBCDecayStart) / Float(max(1, expertBCDecayFrames))
        )
        return expertBCInitialWeight + progress * (expertBCMinimumWeight - expertBCInitialWeight)
    }
}
