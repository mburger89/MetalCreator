import CreatorGraph

/// Which items a Random Reduce drops (patterns spec §4). Every item gets a key from the seeded generator (purpose `.reduce`, so
/// the same seed on Random Values or Jitter draws other numbers), drawn by where it
/// is (its branch's ordinal as the stream, its index in the branch as the draw), and the items with the smallest keys go.
/// So the choice depends on the seed and on the items' places alone: the same seed drops the same items on every machine, a
/// bigger amount drops the ones a smaller amount did and more, and adding items to the end never changes which of the
/// earlier ones are lowest.
enum RandomReduction {
    /// How much to drop from a branch (or, overall, from the tree).
    enum Amount {
        case count(Int)
        case fraction(Double)

        /// How many of `items` to drop: a count is capped at the items there are, a fraction is rounded to the nearest whole
        /// number with halves going up (a quarter of 6 items is 2).
        func dropped(of items: Int) -> Int {
            switch self {
            case .count(let count): min(count, items)
            case .fraction(let fraction): min(items, Int((fraction * Double(items)).rounded(.toNearestOrAwayFromZero)))
            }
        }
    }

    /// One item: the ordinal of its branch (`DataTree.rebuildingLeaves`) and its place among that branch's items.
    struct Slot: Hashable {
        let ordinal: Int
        let k: Int
    }

    private struct Ranked {
        let key: UInt64
        let slot: Slot

        /// By key, then by place, so equal keys (which a 64-bit draw makes vanishingly rare) still sort the same everywhere.
        static func before(_ a: Ranked, _ b: Ranked) -> Bool {
            (a.key, a.slot.ordinal, a.slot.k) < (b.key, b.slot.ordinal, b.slot.k)
        }
    }

    /// The items to drop from `tree`: `amount` of each branch, or of the whole tree when `overall`.
    static func slotsToDrop(in tree: DataTree, seed: Int, amount: Amount, overall: Bool) -> Set<Slot> {
        let ranked = tree.leaves.enumerated().map { ordinal, leaf -> [Ranked] in
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .reduce)
            return leaf.positions.enumerated().map { k, position in
                Ranked(key: random.value(at: position), slot: Slot(ordinal: ordinal, k: k))
            }
        }
        let groups = overall ? [ranked.flatMap { $0 }] : ranked
        var dropped = Set<Slot>()
        for group in groups {
            let ordered = group.sorted(by: Ranked.before)
            dropped.formUnion(ordered.prefix(amount.dropped(of: ordered.count)).map(\.slot))
        }
        return dropped
    }
}
