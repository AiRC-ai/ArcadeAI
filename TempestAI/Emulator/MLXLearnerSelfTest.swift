import Foundation
import MLX
import MLXNN

enum MLXLearnerSelfTest {
    struct Result {
        var passed: Bool
        var message: String
    }

    private struct SyntheticBatch {
        var states: [[Float]]
        var actionMask: MLXArray
        var targetDistributions: MLXArray
        var importanceWeights: MLXArray
    }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["TEMPEST_MLX_SELF_TEST"] == "1" else {
            return
        }
        let result = run()
        let prefix = result.passed ? "[MLX-SELF-TEST] PASS" : "[MLX-SELF-TEST] FAIL"
        fputs("\(prefix): \(result.message)\n", result.passed ? stdout : stderr)
        Foundation.exit(result.passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func run() -> Result {
        guard metalLibraryAvailable else {
            return Result(
                passed: false,
                message: "MLX metallib was not found beside the executable or in Resources"
            )
        }
        guard let package = SwiftTensorPackage.bundled() else {
            return Result(
                passed: false,
                message: "bundled Swift tensor package was not found"
            )
        }
        guard let model = MLXRainbowTrainableNetwork(
            package: package,
            section: "online_state_dict"
        ) else {
            return Result(
                passed: false,
                message: "MLX Rainbow network failed to load the tensor package"
            )
        }

        let before = parameterSnapshot(model)
        guard !before.isEmpty else {
            return Result(
                passed: false,
                message: "MLX network exposes no trainable parameters"
            )
        }

        let optimizer = PersistentAdamOptimizer(
            learningRate: MLXRainbowTrainingOps.learningRate
        )
        let batch = syntheticBatch(sampleCount: 8)
        let lossAndGrad = valueAndGrad(model: model) {
            (model: MLXRainbowTrainableNetwork, batch: SyntheticBatch) -> [MLXArray] in
            guard let logits = model.atomLogits(for: batch.states) else {
                return [MLXArray(Float(1_000_000))]
            }
            let selectedLogits = (
                logits * batch.actionMask.expandedDimensions(axis: -1)
            ).sum(axis: 1)
            return [
                MLXRainbowTrainingOps.importanceWeightedC51Loss(
                    logits: selectedLogits,
                    targetDistributions: batch.targetDistributions,
                    importanceWeights: batch.importanceWeights
                )
            ]
        }
        let (lossValues, gradients) = lossAndGrad(model, batch)
        guard let lossValue = lossValues.first else {
            return Result(passed: false, message: "MLX self-test produced no loss value")
        }
        optimizer.update(model: model, gradients: gradients)
        eval(model, optimizer, lossValue)
        guard optimizer.momentCount > 0 else {
            return Result(
                passed: false,
                message: "optimizer did not create Adam moment state"
            )
        }

        let after = parameterSnapshot(model)
        let delta = totalAbsoluteDelta(before: before, after: after)
        let loss = lossValue.item(Float.self)
        guard loss.isFinite else {
            return Result(passed: false, message: "loss was not finite: \(loss)")
        }
        guard delta > 1e-7 else {
            return Result(
                passed: false,
                message: String(
                    format: "optimizer step did not change trainable weights; loss %.6f delta %.9f",
                    Double(loss),
                    Double(delta)
                )
            )
        }
        let persistence = verifyOptimizerPersistence(optimizer)
        guard persistence.passed else {
            return persistence
        }
        return Result(
            passed: true,
            message: String(
                format: "real MLX valueAndGrad+Adam update changed trainable weights and restored optimizer moments; loss %.6f total_delta %.6f",
                Double(loss),
                Double(delta)
            )
        )
    }

    private static func syntheticBatch(sampleCount: Int) -> SyntheticBatch {
        var states: [[Float]] = []
        states.reserveCapacity(sampleCount)
        for sample in 0..<sampleCount {
            var state = Array(
                repeating: Float(0),
                count: MLXRainbowTrainableNetwork.stateSize
            )
            state[0] = Float(sample) / Float(max(1, sampleCount - 1))
            state[3] = Float((sample % 5) + 1) / 8.0
            state[5] = Float(sample % 16) / 15.0
            for lane in 0..<MLXRainbowTrainableNetwork.laneCount {
                state[31 + lane] = lane == sample % 16 ? 1.0 : 0.0
                state[47 + lane] = lane == (sample + 3) % 16 ? 0.5 : 0.0
            }
            let enemySlot = sample % MLXRainbowTrainableNetwork.enemySlots
            let enemyOffset = 86 + enemySlot * 6
            state[enemyOffset] = 1.0
            state[enemyOffset + 1] = Float((sample + 2) % 16) / 15.0
            state[135 + enemySlot] = 0.15 + Float(sample) * 0.05
            state[142 + enemySlot] = 1.0
            states.append(state)
        }

        var actionMask = Array(
            repeating: Float(0),
            count: sampleCount * TempestActionSpace.actionCount
        )
        var targetDistributions = Array(
            repeating: Float(0),
            count: sampleCount * MLXRainbowTrainableNetwork.atomCount
        )
        let centerAtom = MLXRainbowTrainableNetwork.atomCount / 2
        for sample in 0..<sampleCount {
            let actionIndex = (sample * 7) % TempestActionSpace.actionCount
            actionMask[sample * TempestActionSpace.actionCount + actionIndex] = 1.0
            targetDistributions[
                sample * MLXRainbowTrainableNetwork.atomCount + centerAtom
            ] = 1.0
        }

        return SyntheticBatch(
            states: states,
            actionMask: MLXArray(
                actionMask,
                [sampleCount, TempestActionSpace.actionCount]
            ),
            targetDistributions: MLXArray(
                targetDistributions,
                [sampleCount, MLXRainbowTrainableNetwork.atomCount]
            ),
            importanceWeights: MLXArray(Array(repeating: Float(1), count: sampleCount), [sampleCount])
        )
    }

    private static func parameterSnapshot(
        _ model: MLXRainbowTrainableNetwork
    ) -> [String: [Float]] {
        Dictionary(
            uniqueKeysWithValues: model.trainableParameters().flattened().map {
                key, array in
                (key, array.asArray(Float.self))
            }
        )
    }

    private static func totalAbsoluteDelta(
        before: [String: [Float]],
        after: [String: [Float]]
    ) -> Float {
        var total = Float(0)
        for (key, beforeValues) in before {
            guard let afterValues = after[key],
                  afterValues.count == beforeValues.count else {
                continue
            }
            total += zip(beforeValues, afterValues).reduce(Float(0)) {
                $0 + abs($1.0 - $1.1)
            }
        }
        return total
    }

    private static func verifyOptimizerPersistence(
        _ optimizer: PersistentAdamOptimizer
    ) -> Result {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tempest-mlx-self-test-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        guard optimizer.saveState(
            to: directory,
            manifestName: "optimizer_manifest.json"
        ) else {
            return Result(passed: false, message: "failed to save optimizer moments")
        }
        let restored = PersistentAdamOptimizer(
            learningRate: MLXRainbowTrainingOps.learningRate
        )
        guard restored.loadState(
            from: directory,
            manifestName: "optimizer_manifest.json"
        ) else {
            return Result(passed: false, message: "failed to reload optimizer moments")
        }
        let expected = optimizer.momentChecksum()
        let actual = restored.momentChecksum()
        guard restored.momentCount == optimizer.momentCount,
              abs(expected - actual) <= max(1e-4, abs(expected) * 1e-5) else {
            return Result(
                passed: false,
                message: String(
                    format: "optimizer moment reload mismatch; expected %.6f actual %.6f",
                    Double(expected),
                    Double(actual)
                )
            )
        }
        return Result(passed: true, message: "optimizer moments round-trip")
    }

    private static var metalLibraryAvailable: Bool {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("mlx.metallib"),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("default.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("mlx.metallib"),
            Bundle.main.resourceURL?.appendingPathComponent("default.metallib"),
        ]
        return candidates.compactMap { $0 }.contains {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
