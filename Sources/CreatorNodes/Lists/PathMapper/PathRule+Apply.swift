import CreatorGraph

/// What applying a rule made, and how much of the tree it matched.
struct PathMapResult {
    var tree: DataTree
    /// Branches that matched the source, of `total`. The others were passed through where they were.
    var matched: Int
    var total: Int
    /// Passed-through branches that sit where the rule also wrote results, so their items are mixed in with them.
    var merged = 0
}

extension PathRule {
    /// Moves every item of `tree` to the branch the target names. Items arrive in the order of the source (branch by
    /// branch, item by item), so a merge keeps the order. A branch the source doesn't match (a letter repeated with two
    /// different indices, or a whole number that isn't its index) is passed through unchanged, which only works when the
    /// rule keeps the tree's depth. Gaps in the numbering of the result are empty branches.
    ///
    /// The source names branches (as many terms as the tree has levels of branches) or, with one term more, branches and
    /// then the item's index in its branch (User decision 2, option c).
    func apply(to tree: DataTree) throws -> PathMapResult {
        let levels = tree.depth - 1
        if source.count == levels + 1 { return try applyToItems(of: tree) }
        guard source.count == levels else {
            throw PathRuleError("The rule's source \(sourceText) names \(source.count.display) "
                + "\(source.count == 1 ? "level" : "levels"), but this tree (\(tree.shapeText)) has \(Self.levels(levels)) "
                + "of branches. Write the source with \(Self.levels(levels)), like \(Self.example(levels)), "
                + "or with \((levels + 1).display), like \(Self.example(levels + 1)), to name items too.")
        }
        var destination: [TreePath: [Scalar]] = [:]
        var written: Set<TreePath> = []
        var passedThrough: [TreePath] = []
        var matched = 0
        let leaves = tree.leaves
        for leaf in leaves {
            guard let bindings = bind(leaf.path) else {
                destination[leaf.path, default: []] += leaf.items
                passedThrough.append(leaf.path)
                continue
            }
            matched += 1
            if usesItemIndex {
                for (index, item) in leaf.items.enumerated() {
                    let at = try targetPath(bindings, itemIndex: index, from: leaf.path)
                    written.insert(at)
                    destination[at, default: []].append(item)
                }
            } else {
                let at = try targetPath(bindings, itemIndex: 0, from: leaf.path)
                written.insert(at)
                destination[at, default: []] += leaf.items
            }
        }
        if matched < leaves.count, target.count != levels {
            throw PathRuleError("The rule changes how deep the tree is, so the \((leaves.count - matched).display) branches it "
                + "doesn't match can't stay where they were. Make every branch match, or give the target \(Self.levels(levels)).")
        }
        let result = try Self.assemble(destination, branchLevels: target.count)
        return PathMapResult(tree: result, matched: matched, total: leaves.count,
                             merged: passedThrough.count { written.contains($0) })
    }

    /// A source one term longer than the tree has levels of branches: the first terms match the branch, the last matches the
    /// item's index in its branch (`{A;B} → {B;A}` on a 3 × 8 grid makes an 8 × 3 one). The target has the branch's terms
    /// (`{A}`: the items keep their order) or, one term more, the item's position in the branch it goes to (`{B;A}`: the
    /// items of a branch are ordered by position, ties by arrival). An item the source doesn't match stays at its own
    /// index in its own branch. A branch counts as matched when all its items matched.
    private func applyToItems(of tree: DataTree) throws -> PathMapResult {
        let levels = tree.depth - 1
        guard target.count == source.count || target.count == source.count - 1 else {
            throw PathRuleError("The target \(targetText) has \(target.count.display) \(target.count == 1 ? "level" : "levels"). "
                + "A source that names items takes a target with \(Self.levels(levels)) (the branch) "
                + "or \((levels + 1).display) (the branch and the position in it).")
        }
        let positioned = target.count == source.count
        var destination: [TreePath: [(position: Int, order: Int, item: Scalar)]] = [:]
        var written: Set<TreePath> = []
        var passedThrough: Set<TreePath> = []
        var order = 0
        var matched = 0
        let leaves = tree.leaves
        for leaf in leaves {
            var allMatched = true
            for (index, item) in leaf.items.enumerated() {
                order += 1
                guard let bindings = bind(leaf.path.indices + [index]) else {
                    allMatched = false
                    destination[leaf.path, default: []].append((positioned ? index : 0, order, item))
                    passedThrough.insert(leaf.path)
                    continue
                }
                let at = try targetPath(bindings, itemIndex: index, from: leaf.path, terms: target.prefix(levels))
                var position = 0
                if positioned, let last = target.last {
                    position = try last.expression.value(bindings, itemIndex: index, text: last.text)
                }
                written.insert(at)
                destination[at, default: []].append((position, order, item))
            }
            if allMatched { matched += 1 }
        }
        let ordered = destination.mapValues { entries in
            entries.sorted { ($0.position, $0.order) < ($1.position, $1.order) }.map(\.item)
        }
        let result = try Self.assemble(ordered, branchLevels: levels)
        return PathMapResult(tree: result, matched: matched, total: leaves.count,
                             merged: passedThrough.count { written.contains($0) })
    }

    private func bind(_ path: TreePath) -> [Character: Int]? { bind(path.indices) }

    private func bind(_ indices: [Int]) -> [Character: Int]? {
        var bindings: [Character: Int] = [:]
        for (term, index) in zip(source, indices) {
            switch term {
            case .index(let wanted):
                if wanted != index { return nil }
            case .letter(let letter):
                if let existing = bindings[letter], existing != index { return nil }
                bindings[letter] = index
            }
        }
        return bindings
    }

    private func targetPath(_ bindings: [Character: Int], itemIndex: Int, from branch: TreePath,
                            terms: ArraySlice<TargetTerm>? = nil) throws -> TreePath {
        var indices: [Int] = []
        for term in terms ?? target[...] {
            let value = try term.expression.value(bindings, itemIndex: itemIndex, text: term.text)
            guard value >= 0 else {
                throw PathRuleError("“\(term.text)” gives \(value) for the branch \(branch), and a path can't have a negative index.")
            }
            indices.append(value)
        }
        return TreePath(indices)
    }

    /// The tree whose branch at each path holds that path's items; a gap is an empty branch.
    private static func assemble(_ destination: [TreePath: [Scalar]], branchLevels: Int) throws -> DataTree {
        var widths: [TreePath: Int] = [:]
        for path in destination.keys {
            for level in 0..<path.count {
                let parent = TreePath(Array(path.indices.prefix(level)))
                widths[parent] = max(widths[parent] ?? 0, path.indices[level] + 1)
            }
        }
        var made = 0
        func build(_ prefix: TreePath) throws -> DataTree {
            if prefix.count == branchLevels {
                made += 1
                guard made <= GeneratorLimit.maximumItems else {
                    throw PathRuleError("The rule makes more than \(GeneratorLimit.maximumItems.display) branches.")
                }
                return .list(destination[prefix] ?? [])
            }
            let branches = try (0..<(widths[prefix] ?? 0)).map { try build(prefix.appending($0)) }
            return DataTree(depth: branchLevels - prefix.count + 1, branches: branches) ?? .empty(depth: 2)
        }
        return try build(TreePath())
    }

    private static func levels(_ count: Int) -> String { "\(count.display) \(count == 1 ? "level" : "levels")" }

    /// `{A;B}` for 2 levels: a source that would fit.
    private static func example(_ levels: Int) -> String {
        let names = (0..<min(levels, 26)).map { String(Character(UnicodeScalar(UInt8(65 + $0)))) }
        return "{" + names.joined(separator: ";") + "}"
    }
}
