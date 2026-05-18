import Foundation

struct SwiftReplayTransition {
    var state: [Float]
    var actionIndex: Int
    var reward: Float
    var nextState: [Float]
    var done: Bool
    var horizon: Int
    var isExpert: Bool
    var priority: Float
    var sourceGameID: Int
    var frame: Int
}

struct SwiftReplaySample {
    var transition: SwiftReplayTransition
    var index: Int
    var importanceWeight: Float
}

final class SwiftPrioritizedReplayMemory {
    private let capacity: Int
    private let alpha: Float
    private var storage: [SwiftReplayTransition] = []
    private var priorityTree: [Float]
    private var cursor = 0
    private var rng: UInt64 = 0x5250_4c41_594d_454d

    init(capacity: Int, alpha: Float = 0.7) {
        self.capacity = max(1, capacity)
        self.alpha = alpha
        self.priorityTree = Array(repeating: 0, count: self.capacity + 1)
    }

    var count: Int { storage.count }

    func removeAll(keepingCapacity keep: Bool = true) {
        storage.removeAll(keepingCapacity: keep)
        priorityTree = Array(repeating: 0, count: capacity + 1)
        cursor = 0
    }

    @discardableResult
    func append(_ transition: SwiftReplayTransition) -> Int {
        var transition = transition
        transition.priority = max(1e-6, pow(max(1e-6, transition.priority), alpha))
        let index: Int
        if storage.count < capacity {
            storage.append(transition)
            index = storage.count - 1
            updateTree(at: index, to: transition.priority)
        } else {
            index = cursor
            storage[cursor] = transition
            updateTree(at: index, to: transition.priority)
            cursor = (cursor + 1) % capacity
        }
        return index
    }

    func sample(batchSize: Int, beta: Float) -> [SwiftReplaySample] {
        guard !storage.isEmpty, batchSize > 0 else { return [] }
        let total = totalPriority
        guard total > 0 else { return [] }
        let actualBatch = min(batchSize, storage.count)
        var samples: [SwiftReplaySample] = []
        samples.reserveCapacity(actualBatch)
        var maxWeight = Float.leastNonzeroMagnitude

        for segment in 0..<actualBatch {
            let low = total * Float(segment) / Float(actualBatch)
            let high = total * Float(segment + 1) / Float(actualBatch)
            let draw = low + (high - low) * randomUnit()
            let index = index(forPriorityDraw: min(draw, total.nextDown))
            let probability = max(1e-10, storage[index].priority / total)
            let weight = pow(Float(storage.count) * probability, -beta)
            maxWeight = max(maxWeight, weight)
            samples.append(.init(
                transition: storage[index],
                index: index,
                importanceWeight: weight
            ))
        }

        if maxWeight > 0 {
            for index in samples.indices {
                samples[index].importanceWeight /= maxWeight
            }
        }
        return samples
    }

    func updatePriorities(indices: [Int], tdErrors: [Float]) {
        for pair in zip(indices, tdErrors) {
            guard storage.indices.contains(pair.0) else { continue }
            let priority = pow(abs(pair.1) + 1e-6, alpha)
            storage[pair.0].priority = priority
            updateTree(at: pair.0, to: priority)
        }
    }

    func boostPriorities(indices: [Int], factor: Float) {
        guard factor > 1 else { return }
        for index in indices where storage.indices.contains(index) {
            storage[index].priority *= factor
            updateTree(at: index, to: storage[index].priority)
        }
    }

    private var totalPriority: Float {
        prefixSum(upTo: capacity - 1)
    }

    private func index(forPriorityDraw draw: Float) -> Int {
        var target = max(0, draw)
        var index = 0
        var bitMask = 1
        while bitMask < capacity {
            bitMask <<= 1
        }
        while bitMask != 0 {
            let next = index + bitMask
            if next <= capacity && priorityTree[next] <= target {
                index = next
                target -= priorityTree[next]
            }
            bitMask >>= 1
        }
        return min(max(0, index), max(0, storage.count - 1))
    }

    private func updateTree(at index: Int, to priority: Float) {
        guard index >= 0 && index < capacity else { return }
        let current = prefixSum(upTo: index) - (index > 0 ? prefixSum(upTo: index - 1) : 0)
        addTreeDelta(at: index, delta: priority - current)
    }

    private func addTreeDelta(at index: Int, delta: Float) {
        var treeIndex = index + 1
        while treeIndex < priorityTree.count {
            priorityTree[treeIndex] += delta
            treeIndex += treeIndex & -treeIndex
        }
    }

    private func prefixSum(upTo index: Int) -> Float {
        guard index >= 0 else { return 0 }
        var treeIndex = min(index + 1, capacity)
        var sum = Float(0)
        while treeIndex > 0 {
            sum += priorityTree[treeIndex]
            treeIndex -= treeIndex & -treeIndex
        }
        return sum
    }

    private func randomUnit() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float(rng & 0xffff) / 65_535.0
    }
}

final class SwiftNStepReplayBuffer {
    private struct Pending {
        var state: [Float]
        var actionIndex: Int
        var reward: Float
        var nextState: [Float]
        var done: Bool
        var isExpert: Bool
        var sourceGameID: Int
        var frame: Int
    }

    private let nStep: Int
    private let gamma: Float
    private var pending: [Pending] = []

    init(nStep: Int = 12, gamma: Float = 0.99) {
        self.nStep = max(1, nStep)
        self.gamma = gamma
    }

    func append(
        state: [Float],
        actionIndex: Int,
        reward: Float,
        nextState: [Float],
        done: Bool,
        isExpert: Bool,
        sourceGameID: Int,
        frame: Int
    ) -> [SwiftReplayTransition] {
        pending.append(.init(
            state: state,
            actionIndex: actionIndex,
            reward: reward,
            nextState: nextState,
            done: done,
            isExpert: isExpert,
            sourceGameID: sourceGameID,
            frame: frame
        ))
        var matured: [SwiftReplayTransition] = []
        if pending.count >= nStep {
            matured.append(makeTransition(startIndex: 0))
            pending.removeFirst()
        }
        if done {
            while !pending.isEmpty {
                matured.append(makeTransition(startIndex: 0))
                pending.removeFirst()
            }
        }
        return matured
    }

    private func makeTransition(startIndex: Int) -> SwiftReplayTransition {
        var reward = Float(0)
        var multiplier = Float(1)
        var end = pending[startIndex]
        var horizon = 0
        for item in pending[startIndex..<min(pending.count, startIndex + nStep)] {
            reward += multiplier * item.reward
            multiplier *= gamma
            end = item
            horizon += 1
            if item.done { break }
        }
        let first = pending[startIndex]
        return SwiftReplayTransition(
            state: first.state,
            actionIndex: first.actionIndex,
            reward: reward,
            nextState: end.nextState,
            done: end.done,
            horizon: horizon,
            isExpert: first.isExpert,
            priority: max(0.01, abs(reward) + (end.done ? 2.0 : 0.0)),
            sourceGameID: first.sourceGameID,
            frame: first.frame
        )
    }
}

enum SwiftC51Projection {
    static let atomCount = 51
    static let vMin = Float(-100)
    static let vMax = Float(100)

    static var support: [Float] {
        let delta = (vMax - vMin) / Float(atomCount - 1)
        return (0..<atomCount).map { vMin + Float($0) * delta }
    }

    static func project(
        reward: Float,
        done: Bool,
        horizon: Int,
        gamma: Float,
        nextDistribution: [Float]
    ) -> [Float] {
        let delta = (vMax - vMin) / Float(atomCount - 1)
        let gammaN = pow(gamma, Float(max(1, horizon)))
        var projected = Array(repeating: Float(0), count: atomCount)
        let supportValues = support
        for atom in 0..<min(atomCount, nextDistribution.count) {
            let tz = min(vMax, max(vMin, reward + (done ? 0 : gammaN * supportValues[atom])))
            let b = (tz - vMin) / delta
            let lower = max(0, min(atomCount - 1, Int(floor(b))))
            let upper = max(0, min(atomCount - 1, Int(ceil(b))))
            let mass = nextDistribution[atom]
            if lower == upper {
                projected[lower] += mass
            } else {
                projected[lower] += mass * (Float(upper) - b)
                projected[upper] += mass * (b - Float(lower))
            }
        }
        return projected
    }
}
