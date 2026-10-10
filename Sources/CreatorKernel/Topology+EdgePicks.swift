extension Topology {
    /// Whether `key` names `edge`. Each side of the key must be a subset of the tags of one of the
    /// edge's two faces (a union merges coplanar faces and their tag sets, so a merged face still
    /// matches). Seams never match.
    public func edge(_ edge: EdgeInfo, matches key: EdgeKey) -> Bool {
        guard !edge.isSeam, edge.faces.count == 2,
              let a = face(edge.faces[0])?.tags, let b = face(edge.faces[1])?.tags else { return false }
        return (key.first.isSubset(of: a) && key.second.isSubset(of: b))
            || (key.first.isSubset(of: b) && key.second.isSubset(of: a))
    }

    /// Every edge `key` names, ordered by midpoint (x, then y, then z, to 1e-6 mm), then by ID.
    public func edges(matching key: EdgeKey) -> [EdgeInfo] {
        edges.filter { edge($0, matches: key) }.sorted(by: Self.midpointOrder)
    }

    /// The edges a remembered key names now (`resolution(of:expecting:)` without a count): its matches, else
    /// those of its narrowed key, else those of its operand keys.
    public func edges(resolving key: EdgeKey) -> [EdgeInfo] {
        resolution(of: key).edges
    }

    /// The picks that select exactly `ids`: one per distinct key, in first-picked order. A key that
    /// names more edges than were picked records the picked edges' ordinals; a key whose every match was
    /// picked records its run count when its matches form fewer runs than edges (`EdgePick.runCount`).
    /// Unknown IDs and seams are skipped.
    public func picks(for ids: [EdgeID]) -> [EdgePick] {
        let picked = Set(ids)
        var seenKeys: Set<EdgeKey> = []
        var result: [EdgePick] = []
        for id in ids {
            guard let edge = edge(id), !edge.isSeam, let key = key(of: edge), seenKeys.insert(key).inserted else { continue }
            let matches = edges(matching: key)
            let ordinals = matches.indices.filter { picked.contains(matches[$0].id) }
            guard ordinals.count == matches.count else {
                result.append(EdgePick(key: key, matchCount: matches.count, ordinals: ordinals))
                continue
            }
            let runs = Self.runCount(matches)
            result.append(EdgePick(key: key, matchCount: matches.count, runCount: runs == matches.count ? nil : runs))
        }
        return result
    }

    /// Deterministic order for edges sharing a key (spec §5.3, rule 5). Midpoints within 1e-6 mm tie and go by ID. That is
    /// not a strict weak ordering when three midpoints chain within the tolerance, which no real part does; it is left as
    /// it is because a saved pick's ordinals index this order.
    static func midpointOrder(_ a: EdgeInfo, _ b: EdgeInfo) -> Bool {
        let pairs = [(a.midpoint.x, b.midpoint.x), (a.midpoint.y, b.midpoint.y), (a.midpoint.z, b.midpoint.z)]
        for (p, q) in pairs where abs(p - q) > 1e-6 {
            return p < q
        }
        return a.id.rawValue < b.id.rawValue
    }
}
