import Foundation
import MLX

enum AIParitySelfTest {
    struct Result {
        var passed: Bool
        var message: String
    }

    private struct FixturePayload: Decodable {
        let format: String
        let formatVersion: Int
        let checkpointSHA256: String?
        let stateSize: Int
        let actionCount: Int
        let atoms: Int
        let attentionDim: Int
        let attentionHeads: Int
        let fixtures: [Fixture]

        enum CodingKeys: String, CodingKey {
            case format
            case formatVersion = "format_version"
            case checkpointSHA256 = "checkpoint_sha256"
            case stateSize = "state_size"
            case actionCount = "action_count"
            case atoms
            case attentionDim = "attention_dim"
            case attentionHeads = "attention_heads"
            case fixtures
        }
    }

    private struct Fixture: Decodable {
        let index: Int
        let state: [Float]
        let qValues: [Float]
        let action: Int

        enum CodingKeys: String, CodingKey {
            case index
            case state
            case qValues = "q_values"
            case action
        }
    }

    static func runIfRequested() {
        guard let fixturePath = ProcessInfo.processInfo.environment["TEMPEST_AI_PARITY_FIXTURE"],
              !fixturePath.isEmpty else {
            return
        }
        let result = run(fixtureURL: URL(fileURLWithPath: fixturePath))
        let prefix = result.passed ? "[AI-PARITY] PASS" : "[AI-PARITY] FAIL"
        fputs("\(prefix): \(result.message)\n", result.passed ? stdout : stderr)
        Foundation.exit(result.passed ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func run(fixtureURL: URL) -> Result {
        do {
            let payload = try JSONDecoder().decode(
                FixturePayload.self,
                from: Data(contentsOf: fixtureURL)
            )
            guard payload.format == "tempest-ai-parity-fixtures",
                  payload.stateSize == MLXRainbowTrainableNetwork.stateSize,
                  payload.actionCount == MLXRainbowTrainableNetwork.actionCount,
                  payload.atoms == MLXRainbowTrainableNetwork.atomCount,
                  payload.attentionDim == MLXRainbowTrainableNetwork.attentionDim,
                  payload.attentionHeads == MLXRainbowTrainableNetwork.attentionHeads,
                  !payload.fixtures.isEmpty else {
                return Result(passed: false, message: "fixture header is incompatible")
            }

            guard let package = tensorPackageFromEnvironmentOrBundle() else {
                return Result(passed: false, message: "Swift tensor package was not found")
            }
            if let checkpointSHA256 = payload.checkpointSHA256,
               checkpointSHA256 != package.checkpointSHA256,
               ProcessInfo.processInfo.environment["TEMPEST_AI_PARITY_ALLOW_HASH_MISMATCH"] != "1" {
                return Result(
                    passed: false,
                    message: "fixture checkpoint \(checkpointSHA256.prefix(12)) does not match tensor package \(package.checkpointSHA256.prefix(12))"
                )
            }

            guard let cpuModel = SwiftRainbowModel(package: package),
                  let mlxModel = MLXRainbowTrainableNetwork(package: package) else {
                return Result(passed: false, message: "failed to load CPU and MLX Rainbow models")
            }

            let states = payload.fixtures.map(\.state)
            guard let mlxQValues = mlxModel.qValues(for: states) else {
                return Result(passed: false, message: "MLX model produced no Q-values")
            }
            let flatMLXQ = mlxQValues.asArray(Float.self)
            let expectedFlatCount = payload.fixtures.count * MLXRainbowTrainableNetwork.actionCount
            guard flatMLXQ.count == expectedFlatCount else {
                return Result(
                    passed: false,
                    message: "MLX Q-value count mismatch: \(flatMLXQ.count) != \(expectedFlatCount)"
                )
            }

            let tolerance = Float(
                ProcessInfo.processInfo.environment["TEMPEST_AI_PARITY_Q_TOLERANCE"]
                    .flatMap(Double.init) ?? 0.001
            )
            var maxCPUDelta = Float(0)
            var maxMLXDelta = Float(0)
            var cpuActionMatches = 0
            var mlxActionMatches = 0

            for (fixtureIndex, fixture) in payload.fixtures.enumerated() {
                guard fixture.state.count == MLXRainbowTrainableNetwork.stateSize,
                      fixture.qValues.count == MLXRainbowTrainableNetwork.actionCount else {
                    return Result(
                        passed: false,
                        message: "fixture \(fixture.index) has invalid vector dimensions"
                    )
                }
                guard let cpuQ = cpuModel.qValues(for: fixture.state),
                      let cpuAction = cpuQ.indices.max(by: { cpuQ[$0] < cpuQ[$1] }) else {
                    return Result(passed: false, message: "CPU model failed fixture \(fixture.index)")
                }
                let start = fixtureIndex * MLXRainbowTrainableNetwork.actionCount
                let mlxQ = Array(flatMLXQ[start..<(start + MLXRainbowTrainableNetwork.actionCount)])
                guard let mlxAction = mlxQ.indices.max(by: { mlxQ[$0] < mlxQ[$1] }) else {
                    return Result(passed: false, message: "MLX model failed fixture \(fixture.index)")
                }

                maxCPUDelta = max(maxCPUDelta, maxAbsDelta(cpuQ, fixture.qValues))
                maxMLXDelta = max(maxMLXDelta, maxAbsDelta(mlxQ, fixture.qValues))
                if cpuAction == fixture.action { cpuActionMatches += 1 }
                if mlxAction == fixture.action { mlxActionMatches += 1 }
            }

            let total = payload.fixtures.count
            let cpuMatch = Float(cpuActionMatches) / Float(total)
            let mlxMatch = Float(mlxActionMatches) / Float(total)
            guard cpuMatch >= 0.99, mlxMatch >= 0.99 else {
                return Result(
                    passed: false,
                    message: String(
                        format: "action parity below target: CPU %.1f%% MLX %.1f%% over %d fixtures",
                        Double(cpuMatch * 100),
                        Double(mlxMatch * 100),
                        total
                    )
                )
            }
            guard maxCPUDelta <= tolerance, maxMLXDelta <= tolerance else {
                return Result(
                    passed: false,
                    message: String(
                        format: "Q-value parity above tolerance %.6f: CPU %.6f MLX %.6f over %d fixtures",
                        Double(tolerance),
                        Double(maxCPUDelta),
                        Double(maxMLXDelta),
                        total
                    )
                )
            }
            return Result(
                passed: true,
                message: String(
                    format: "CPU and MLX match PyTorch fixtures; action %.1f%%/%.1f%% maxQ %.6f/%.6f over %d fixtures",
                    Double(cpuMatch * 100),
                    Double(mlxMatch * 100),
                    Double(maxCPUDelta),
                    Double(maxMLXDelta),
                    total
                )
            )
        } catch {
            return Result(passed: false, message: "fixture decode failed: \(error)")
        }
    }

    private static func tensorPackageFromEnvironmentOrBundle() -> SwiftTensorPackage? {
        if let manifestPath = ProcessInfo.processInfo.environment["TEMPEST_SWIFT_TENSOR_MANIFEST"],
           !manifestPath.isEmpty,
           let package = SwiftTensorPackage.load(from: URL(fileURLWithPath: manifestPath)) {
            return package
        }
        return SwiftTensorPackage.bundled()
    }

    private static func maxAbsDelta(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs).reduce(Float(0)) { current, pair in
            max(current, abs(pair.0 - pair.1))
        }
    }
}
