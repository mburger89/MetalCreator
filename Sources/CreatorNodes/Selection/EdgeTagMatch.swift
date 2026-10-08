import CreatorKernel

/// Resolves remembered picks against a solid's topology (spec §5.3, rules 5–6). Pure, so the
/// drift and warning rules are testable without a kernel.
struct EdgeTagMatch: Equatable {
    var edges: [EdgeID]
    var warnings: [String]

    static let nothingPicked = "Pick edges in view to fill this rule."
    static let unnamedPick = "A picked edge borders a face with no stable name, so the pick may move to a different edge "
        + "when the model changes. Pick it again after the change."

    /// Drift is reported per drifted pick, so two picks drifting in opposite directions
    /// (1 → 2 and 1 → 0) never cancel out into "Matched 2 edges, expected 2.".
    static func resolve(_ picks: [EdgePick], in topology: Topology) -> EdgeTagMatch {
        guard !picks.isEmpty else { return EdgeTagMatch(edges: [], warnings: [nothingPicked]) }
        var selected: [EdgeID] = []
        var seen: Set<EdgeID> = []
        var drifts: [(found: Int, expected: Int)] = []
        for pick in picks {
            let matches = topology.edges(matching: pick.key)
            if matches.count != pick.matchCount { drifts.append((matches.count, pick.matchCount)) }
            let chosen = pick.ordinals.map { ordinals in ordinals.filter(matches.indices.contains).map { matches[$0] } } ?? matches
            for edge in chosen where seen.insert(edge.id).inserted {
                selected.append(edge.id)
            }
        }
        var warnings: [String] = []
        if !drifts.isEmpty {
            let counts = drifts.map { "\($0.found) \($0.found == 1 ? "edge" : "edges"), expected \($0.expected)" }
            warnings.append("Matched \(counts.joined(separator: "; ")).")
        } else if selected.isEmpty {
            warnings.append("Matched 0 edges, expected \(picks.reduce(0) { $0 + $1.matchCount }).")
        }
        if picks.contains(where: \.touchesUnnamedFace) {
            warnings.append(unnamedPick)
        }
        return EdgeTagMatch(edges: selected, warnings: warnings)
    }
}
