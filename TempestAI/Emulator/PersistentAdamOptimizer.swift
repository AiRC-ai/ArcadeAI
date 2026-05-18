import Foundation
import MLX
import MLXNN

final class PersistentAdamOptimizer: Evaluatable {
    private struct MomentPair {
        var first: MLXArray
        var second: MLXArray
    }

    private struct Manifest: Codable {
        var version: Int
        var learningRate: Float
        var beta1: Float
        var beta2: Float
        var epsilon: Float
        var entries: [Entry]
    }

    private struct Entry: Codable {
        var key: String
        var shape: [Int]
        var firstFile: String
        var secondFile: String
    }

    private enum PersistError: Error {
        case invalidData
    }

    var learningRate: Float
    var betas: (Float, Float)
    var epsilon: Float

    private var moments = NestedDictionary<String, MomentPair>()

    init(
        learningRate: Float,
        betas: (Float, Float) = (0.9, 0.999),
        epsilon: Float = 1e-8
    ) {
        self.learningRate = learningRate
        self.betas = betas
        self.epsilon = epsilon
    }

    func update(model: Module, gradients: ModuleParameters) {
        let parameters = model.parameters()
        let (updatedParameters, updatedMoments) = gradients.mapValues(
            parameters,
            moments
        ) { gradient, parameter, moment in
            guard let parameter else {
                return (gradient, moment)
            }
            let currentMoment = moment ?? MomentPair(
                first: MLXArray.zeros(like: parameter),
                second: MLXArray.zeros(like: parameter)
            )
            let (beta1, beta2) = betas
            let first = beta1 * currentMoment.first + (1 - beta1) * gradient
            let second = beta2 * currentMoment.second + (1 - beta2) * square(gradient)
            let updated = parameter - learningRate * first / (sqrt(second) + epsilon)
            return (updated, MomentPair(first: first, second: second))
        }
        moments = updatedMoments
        model.update(parameters: updatedParameters)
    }

    func reset() {
        moments = NestedDictionary<String, MomentPair>()
    }

    func innerState() -> [MLXArray] {
        moments.flattenedValues().flatMap { [$0.first, $0.second] }
    }

    var momentCount: Int {
        moments.flattened().count
    }

    func momentChecksum() -> Float {
        moments.flattened()
            .sorted { $0.0 < $1.0 }
            .reduce(Float(0)) { partial, entry in
                let values = entry.1.first.asArray(Float.self)
                    + entry.1.second.asArray(Float.self)
                return partial + values.reduce(Float(0)) {
                    $0 + abs($1)
                }
            }
    }

    func saveState(to directory: URL, manifestName: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let entries = try moments.flattened().map { key, moment in
                let safeKey = key.replacingOccurrences(of: ".", with: "__")
                let firstFile = "\(safeKey)__adam_m.f32"
                let secondFile = "\(safeKey)__adam_v.f32"
                try write(moment.first, to: directory.appendingPathComponent(firstFile))
                try write(moment.second, to: directory.appendingPathComponent(secondFile))
                return Entry(
                    key: key,
                    shape: moment.first.shape,
                    firstFile: firstFile,
                    secondFile: secondFile
                )
            }
            let manifest = Manifest(
                version: 1,
                learningRate: learningRate,
                beta1: betas.0,
                beta2: betas.1,
                epsilon: epsilon,
                entries: entries
            )
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

    func loadState(from directory: URL, manifestName: String) -> Bool {
        do {
            let manifestData = try Data(
                contentsOf: directory.appendingPathComponent(manifestName)
            )
            let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
            guard manifest.version == 1 else { return false }
            learningRate = manifest.learningRate
            betas = (manifest.beta1, manifest.beta2)
            epsilon = manifest.epsilon
            let flat: [(String, MomentPair)] = try manifest.entries.map { entry in
                let first = try read(
                    from: directory.appendingPathComponent(entry.firstFile),
                    shape: entry.shape
                )
                let second = try read(
                    from: directory.appendingPathComponent(entry.secondFile),
                    shape: entry.shape
                )
                return (entry.key, MomentPair(first: first, second: second))
            }
            moments = NestedDictionary<String, MomentPair>.unflattened(flat)
            return true
        } catch {
            return false
        }
    }

    private func write(_ array: MLXArray, to url: URL) throws {
        let values = array.asArray(Float.self)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url, options: .atomic)
    }

    private func read(from url: URL, shape: [Int]) throws -> MLXArray {
        let data = try Data(contentsOf: url)
        let expectedCount = shape.reduce(1, *)
        guard data.count == expectedCount * MemoryLayout<Float>.size else {
            throw PersistError.invalidData
        }
        let values = data.withUnsafeBytes { raw -> [Float] in
            Array(raw.bindMemory(to: Float.self))
        }
        return MLXArray(values, shape)
    }
}
