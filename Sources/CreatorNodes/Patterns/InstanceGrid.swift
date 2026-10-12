import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The instances a pattern node makes, and what each one's inputs are (patterns spec §3 and §5, with trees). The
/// inputs are matched by the same rules broadcasting uses, and the node still makes one kernel call for all of them:
///
/// - The deepest input sets the shape: when all are flat, the longest sets the number of instances and a shorter list
///   repeats its last item (as before trees); when one is a tree, its items are the instances and the instance at
///   `{r;c}` is item `c` of branch `r`. Ties go to the first name asked for, which is the placements.
/// - A flat list applies to every branch and matches that branch's items (a flat list of 8 against 3 rows of 8).
/// - A tree as deep as the shape is matched level by level, a shorter side repeating its last branch (a tree of three
///   one-item branches gives each of three rings one value: Graft a list of diameters).
/// - A tree of another depth is refused, naming both shapes, and so is a branch with no items to take from.
///
/// Any input with no items at all makes no instances, as an empty list always has.
struct InstanceGrid {
    /// Each instance's indices in the tree: `[i]` for a flat list, `[r, c]` for item `c` of branch `r`.
    let paths: [[Int]]
    /// Each instance's tag item (`InstancePath.item(for:)`): its flat index for `[i]`, a packed negative number deeper.
    let items: [Int]
    private let shape: DataTree?
    private let depth: Int
    private let columns: [SocketName: [Scalar]]

    var count: Int { paths.count }

    /// The instances of the inputs `names`, each read as a whole tree (`.tree` access, so a flat list arrives as a tree
    /// of depth 1 and a single value as a list of one).
    init(_ inputs: NodeInputs, _ names: [SocketName]) throws {
        try self.init(names.map { (name: $0, tree: try inputs.tree($0)) })
    }

    init(_ trees: [(name: SocketName, tree: DataTree)]) throws {
        guard var lead = trees.first else { throw NodeError.invalidValue("A pattern needs placements.") }
        for entry in trees where entry.tree.depth > lead.tree.depth { lead = entry }
        if trees.contains(where: { $0.tree.itemCount == 0 }) {
            (paths, items, shape, depth, columns) = ([], [], nil, lead.tree.depth, [:])
            return
        }
        var cells: [(path: [Int], leaf: Int, position: Int)] = []
        if lead.tree.depth == 1 {
            let count = trees.map(\.tree.itemCount).max() ?? 0
            try PatternLimit.check(count)
            cells = (0..<count).map { ([$0], 0, $0) }
        } else {
            for entry in trees where entry.tree.depth != 1 && entry.tree.depth != lead.tree.depth {
                throw NodeError.invalidValue("“\(entry.name)” (\(entry.tree.shapeText)) and “\(lead.name)” "
                    + "(\(lead.tree.shapeText)) are nested differently. Use a flat list, or trees of the same depth.")
            }
            try PatternLimit.check(lead.tree.itemCount)
            for (leaf, entry) in lead.tree.leaves.enumerated() {
                for position in entry.items.indices { cells.append((entry.path.indices + [position], leaf, position)) }
            }
        }
        var items: [Int] = []
        items.reserveCapacity(cells.count)
        for cell in cells {
            guard let item = InstancePath.item(for: cell.path) else {
                throw NodeError.invalidValue("Instance \(InstancePath.text(indices: cell.path)) can't be named: patterns take trees up "
                    + "to \(InstancePath.maximumDepth) levels deep, with branch numbers below \((InstancePath.maximumIndex + 1).display).")
            }
            items.append(item)
        }
        var columns: [SocketName: [Scalar]] = [:]
        let leaves = lead.tree.depth == 1 ? [] : lead.tree.leaves
        for entry in trees {
            columns[entry.name] = try Self.values(of: entry, matching: cells.map { ($0.leaf, $0.position, $0.path) }, leaves: leaves)
        }
        (self.paths, self.items, self.depth, self.columns) = (cells.map(\.path), items, lead.tree.depth, columns)
        shape = lead.tree.depth == 1 ? nil : lead.tree
    }

    /// The input's item for each cell: the cell's own position among the items it is matched with, repeating the last.
    private static func values(of entry: (name: SocketName, tree: DataTree), matching cells: [(leaf: Int, position: Int, path: [Int])],
                               leaves: [DataTree.Leaf]) throws -> [Scalar] {
        let tree = entry.tree
        if tree.depth == 1 {
            let items = tree.items
            return cells.map { items[min($0.position, items.count - 1)] }
        }
        var byLeaf: [Int: [Scalar]] = [:]
        var result: [Scalar] = []
        result.reserveCapacity(cells.count)
        for cell in cells {
            if byLeaf[cell.leaf] == nil {
                byLeaf[cell.leaf] = try items(of: entry, at: leaves[cell.leaf].path)
            }
            let items = byLeaf[cell.leaf] ?? []
            result.append(items[min(cell.position, items.count - 1)])
        }
        return result
    }

    /// The items of the branch a leaf is matched with: level by level, a shorter side repeating its last branch.
    private static func items(of entry: (name: SocketName, tree: DataTree), at path: TreePath) throws -> [Scalar] {
        var branch = entry.tree
        for index in path.indices {
            let branches = branch.branches
            guard let last = branches.indices.last else { throw empty(entry.name, path) }
            branch = branches[min(index, last)]
        }
        guard !branch.items.isEmpty else { throw empty(entry.name, path) }
        return branch.items
    }

    private static func empty(_ name: SocketName, _ path: TreePath) -> NodeError {
        NodeError.invalidValue("“\(name)” has no items for the branch \(path).")
    }

    /// A tree holding `scalars`, one per instance, in the shape the instances came in: a flat list for a flat pattern, else
    /// the tree (the empty branches too) the instances sit in.
    func tree(of scalars: [Scalar]) -> DataTree {
        if let shape { return shape.replacingItems(scalars) ?? .empty(depth: depth) }
        return depth > 1 && scalars.isEmpty ? .empty(depth: depth) : .list(scalars)
    }

    // MARK: Typed inputs, one value per instance

    func numbers(_ name: SocketName) throws -> [Double] {
        try typed(name, .number) { if case .number(let value) = $0 { value } else { nil } }
    }

    func integers(_ name: SocketName) throws -> [Int] {
        try typed(name, .integer) { if case .integer(let value) = $0 { value } else { nil } }
    }

    func bools(_ name: SocketName) throws -> [Bool] {
        try typed(name, .bool) { if case .bool(let value) = $0 { value } else { nil } }
    }

    func planes(_ name: SocketName) throws -> [Plane] {
        try typed(name, .plane) { if case .plane(let value) = $0 { value } else { nil } }
    }

    func solids(_ name: SocketName) throws -> [Solid] {
        try typed(name, .solid) { if case .solid(let value) = $0 { value } else { nil } }
    }

    private func typed<T>(_ name: SocketName, _ type: SocketType, _ extract: (Scalar) -> T?) throws -> [T] {
        try (columns[name] ?? []).map { scalar in
            guard let value = extract(scalar) else { throw NodeError.typeMismatch(name, expected: type) }
            return value
        }
    }
}
