/// A binary min-heap of edge collapses by cost. Entries are never updated in place: a vertex's `stamp` counts the changes to it, and an
/// entry whose stamps are no longer the vertices' is stale and dropped when it comes to the top.
struct EdgeHeap: Sendable {
    struct Entry: Sendable {
        var cost: Double
        var u: Int32
        var v: Int32
        var stampU: UInt32
        var stampV: UInt32
    }

    private var items: [Entry] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func reserve(_ count: Int) {
        items.reserveCapacity(count)
    }

    mutating func push(_ entry: Entry) {
        items.append(entry)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].cost < items[parent].cost else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Entry? {
        guard let last = items.popLast() else { return nil }
        guard !items.isEmpty else { return last }
        let top = items[0]
        items[0] = last
        var parent = 0
        while true {
            let (left, right) = (2 * parent + 1, 2 * parent + 2)
            var smallest = parent
            if left < items.count, items[left].cost < items[smallest].cost { smallest = left }
            if right < items.count, items[right].cost < items[smallest].cost { smallest = right }
            if smallest == parent { break }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top
    }
}
