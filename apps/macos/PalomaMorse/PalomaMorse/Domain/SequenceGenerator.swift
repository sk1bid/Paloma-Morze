import Foundation

/// Port of `generateSequence` from `ui/src/Reception.jsx`: a balanced pool,
/// shuffled, with no two identical signs in a row when the pool allows it.
enum SequenceGenerator {
    /// Marker between groups of five in the paper-based control work.
    static let groupGap = " "

    static func generate(pool: [String], count: Int, groupSize: Int = 5, groupGaps: Bool) -> [String] {
        var rng = SystemRandomNumberGenerator()
        return generate(pool: pool, count: count, groupSize: groupSize, groupGaps: groupGaps, using: &rng)
    }

    static func generate<R: RandomNumberGenerator>(
        pool: [String],
        count: Int,
        groupSize: Int = 5,
        groupGaps: Bool,
        using rng: inout R
    ) -> [String] {
        guard !pool.isEmpty, count > 0 else { return [] }

        var items: [String] = []
        while items.count < count {
            items += pool.shuffled(using: &rng)
        }
        items = Array(items.prefix(count))
        items.shuffle(using: &rng)

        if Set(pool).count > 1 {
            removeConsecutiveRepeats(&items)
        }

        guard groupGaps, groupSize > 0 else { return items }

        var grouped: [String] = []
        for (index, item) in items.enumerated() {
            if index > 0, index.isMultiple(of: groupSize) {
                grouped.append(groupGap)
            }
            grouped.append(item)
        }
        return grouped
    }

    private static func removeConsecutiveRepeats(_ items: inout [String]) {
        guard items.count > 2 else { return }
        for i in 0..<(items.count - 1) where items[i] == items[i + 1] {
            for k in items.indices where k != i && k != i + 1 {
                let moving = items[i + 1]
                let candidate = items[k]
                let candidateFits = candidate != items[i] && (i + 2 >= items.count || candidate != items[i + 2])
                let movingFits = (k == 0 || moving != items[k - 1]) && (k + 1 >= items.count || moving != items[k + 1])
                if candidateFits && movingFits {
                    items.swapAt(i + 1, k)
                    break
                }
            }
        }
    }
}
