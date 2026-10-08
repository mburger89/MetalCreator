/// Splits the terms into connected components over the unknowns (spec §4 step 1). Components are
/// ordered by their smallest column, which is the order of their smallest entity ID because
/// columns are assigned in ID order. Terms with no unknowns (constraints between projected edges
/// only) each form a component with no columns, after all others.
struct ComponentPartition: Sendable {
    struct Component: Sendable {
        var columns: [Int]
        var terms: [SolverTerm]
    }

    let components: [Component]

    init(terms: [SolverTerm], layout: UnknownLayout) {
        var parent = Array(0..<layout.columnCount)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let (ra, rb) = (find(a), find(b))
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for column in layout.pointColumns.values { union(column, column + 1) }
        for term in terms {
            let columns = term.equation.columns
            for column in columns.dropFirst() { union(columns[0], column) }
        }
        var byRoot: [Int: Component] = [:]
        for column in 0..<layout.columnCount {
            byRoot[find(column), default: Component(columns: [], terms: [])].columns.append(column)
        }
        var constantOnly: [Component] = []
        for term in terms {
            if let first = term.equation.columns.first {
                byRoot[find(first)]?.terms.append(term)
            } else {
                constantOnly.append(Component(columns: [], terms: [term]))
            }
        }
        components = byRoot.keys.sorted().compactMap { byRoot[$0] } + constantOnly
    }
}
