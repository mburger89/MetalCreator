import CreatorGraph

/// What a Cull Index takes out (patterns spec §4): item indices, which name that place in every branch (`3` is `{0;3}`,
/// `{1;3}`, …; always the last level, so on `{row;column;0}` cells only `0` names anything), and paths, which name one
/// item (`{0;3}`) or, when they stop short of the items, everything under them (`{1}` is the whole second row). An
/// index or path names the place an item had before any cull, so culling twice never shifts it.
struct CullTargets {
    private(set) var indices: Set<Int> = []
    private(set) var paths: [TreePath] = []

    /// Reads the node's text setting: indices and paths separated by commas, `1, 4, {0;3}`. Nothing at all is allowed.
    init(parsing text: String) throws {
        var tokens: [String] = []
        var current = ""
        var inBraces = false
        for character in text {
            if character == "{" { inBraces = true }
            if character == "}" { inBraces = false }
            if character == ",", !inBraces {
                tokens.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        tokens.append(current)
        for token in tokens.map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            if token.hasPrefix("{"), let path = TreePath(parsing: token) {
                // `{}` has no indices, so every item would start with it and a stray one would empty the tree without a word.
                guard path.count > 0 else {
                    throw NodeError.invalidValue("“{}” names the whole tree. To cull everything, use Cull Pattern with 0.")
                }
                paths.append(path)
            } else if let index = Int(token), index >= 0 {
                indices.insert(index)
            } else {
                throw NodeError.invalidValue("“\(token)” isn't an index or a path. Write indices like 3 and paths like {0;3}, "
                    + "separated by commas.")
            }
        }
    }

    /// Adds the indices wired into `indices`: whole numbers from 0 up.
    mutating func add(wired values: [Double]) throws {
        for value in values {
            guard value.isFinite, value >= 0, value == value.rounded(), value < Double(Int.max) else {
                let shown = value.formatted(.number.locale(.messages))
                throw NodeError.invalidValue("“indices” must be whole numbers from 0 up, not \(shown).")
            }
            indices.insert(Int(value))
        }
    }

    /// Refuses a path with more indices than an item of `tree` has, naming the shape.
    func validate(against tree: DataTree) throws {
        for path in paths where path.count > tree.depth {
            let example = TreePath(Array(repeating: 0, count: tree.depth))
            throw NodeError.invalidValue("\(path) has \(path.count.display) indices, but an item of this tree (\(tree.shapeText)) "
                + "needs \(tree.depth.display). Write it like \(example).")
        }
    }

    /// Whether item `k` of `leaf` is taken out. `depth` is the tree's.
    func drops(_ leaf: DataTree.Leaf, at k: Int, depth: Int) -> Bool {
        let position = leaf.positions[k]
        if indices.contains(position) { return true }
        return paths.contains { path in
            path.count == depth
                ? path.indices.dropLast() == leaf.path.indices && path.indices.last == position
                : leaf.path.indices.starts(with: path.indices)
        }
    }

    /// The paths that name nothing in `tree`: a branch that isn't there or an item that was never there (or is gone).
    func unmatched(in tree: DataTree) -> [TreePath] {
        paths.filter { path in
            if path.count < tree.depth { return tree.branch(at: path) == nil }
            guard let last = path.indices.last, let leaf = tree.branch(at: TreePath(Array(path.indices.dropLast()))) else { return true }
            return !leaf.itemPositions.contains(last)
        }
    }
}
