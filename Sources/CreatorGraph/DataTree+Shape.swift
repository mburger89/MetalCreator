import CreatorKernel
import Foundation

extension DataTree {
    /// The size at each level when every branch at a level has the same size ([3, 8] for 3 branches of 8 items), else
    /// `nil`. An empty tree of depth 2 is [0, 0].
    public var dimensions: [Int]? {
        if depth == 1 { return [count] }
        guard let first = branches.first else { return [0] + [Int](repeating: 0, count: depth - 1) }
        guard let inner = first.dimensions, branches.allSatisfy({ $0.dimensions == inner }) else { return nil }
        return [count] + inner
    }

    /// How a tree is described in tooltips and the inspector: "3 × 8" when every branch is alike, else the branch
    /// count and the items in each branch ("3 branches: 8, 4, 8"), cut after the first few.
    public var shapeText: String {
        if let dimensions { return dimensions.map { $0.shapeNumber }.joined(separator: " × ") }
        let counts = leaves.map(\.items.count)
        let shown = counts.prefix(Self.shownCounts).map { $0.shapeNumber }.joined(separator: ", ")
        let more = counts.count > Self.shownCounts ? ", …" : ""
        return "\(counts.count.shapeNumber) \(counts.count == 1 ? "branch" : "branches"): \(shown)\(more)"
    }

    static let shownCounts = 6
}

extension Int {
    /// A count inside shape text, grouped the same way on every machine.
    var shapeNumber: String { formatted(.number.locale(.messages)) }
}

extension Value {
    /// How a value is described next to its socket: "1 item", "8 items", "3 × 8".
    public var shapeText: String {
        switch self {
        case .one: "1 item"
        case .list(let scalars): "\(scalars.count.shapeNumber) \(scalars.count == 1 ? "item" : "items")"
        case .tree(let tree): tree.shapeText
        }
    }
}
