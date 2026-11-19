import CreatorGeometry
import CreatorKernel

/// Trim Surface's keep picks against the pieces of a split (NS-4, R4 and R17): pure, so a test needs no kernel.
public enum TrimRegions {
    static let vanishedPick = "A picked region no longer exists; pick the regions again."
    static let nothingLeft = "None of the picked regions exist any more; pick the regions to keep again."

    /// A pick whose own names match nothing now (the cutter changed kind or order) and was found again by where it came from.
    static let narrowedPick = "A picked region no longer matches the cutter exactly, so Trim Surface kept the piece nearest "
        + "where it was picked; pick the regions again to settle it."

    static func sharedWarning(_ count: Int) -> String {
        "A picked region now names \(count.display) pieces; Trim Surface kept the one nearest where it was picked."
    }

    /// The indices into `pieces` the picks keep, sorted and without repeats, and the warnings the picks earn. A pick keeps the one
    /// piece holding its faces, or, when it names several, the piece whose area-weighted centroid is nearest the pick's recorded
    /// centroid (warned only when it names more pieces than `sharedBy`, R17). When nothing is kept the caller refuses.
    public static func resolve(_ picks: [RegionPick], pieces: [[FaceID]], in topology: Topology) -> (pieces: [Int], warnings: [String]) {
        var pieceOf: [FaceID: Int] = [:]
        for (index, faces) in pieces.enumerated() { for face in faces { pieceOf[face] = index } }
        var kept: Set<Int> = []
        var warnings: [String] = []
        func warn(_ text: String) { if !warnings.contains(text) { warnings.append(text) } }
        for region in picks {
            let pick = region.pick
            let gone = topology.vanishedInstances(in: pick.tags)
            if !gone.isEmpty {
                warn(FacePickWording.vanished(gone))
                continue
            }
            let resolution = topology.resolution(of: pick)
            let named = Set(resolution.faces.compactMap { pieceOf[$0.id] }).sorted()
            guard !named.isEmpty else {
                warn(vanishedPick)
                continue
            }
            if resolution.isNarrowed { warn(narrowedPick) }
            if pick.touchesUnnamedFace { warn(FacePickWording.unnamed("trim")) }
            if named.count == 1 {
                kept.insert(named[0])
                continue
            }
            if named.count > region.sharedBy { warn(sharedWarning(named.count)) }
            kept.insert(nearest(of: named, to: pick.centroid, pieces: pieces, in: topology))
        }
        return (kept.sorted(), warnings)
    }

    /// The `RegionPick` that names piece `index`: a pick of its face with the smallest tag-set key, and how many pieces that pick names
    /// in this split. `nil` for a piece that isn't there or has no faces in the table.
    public static func pick(forPiece index: Int, pieces: [[FaceID]], in topology: Topology) -> RegionPick? {
        guard pieces.indices.contains(index) else { return nil }
        let faces = pieces[index].compactMap { topology.face($0) }
        func key(_ face: FaceInfo) -> String { face.tags.map(\.sortKey).sorted().joined(separator: "+") }
        let chosen = faces.min { a, b in
            let (ka, kb) = (key(a), key(b))
            return ka != kb ? ka < kb : a.id.rawValue < b.id.rawValue
        }
        guard let chosen, let pick = topology.facePick(for: chosen.id) else { return nil }
        var pieceOf: [FaceID: Int] = [:]
        for (number, members) in pieces.enumerated() { for face in members { pieceOf[face] = number } }
        let shared = Set(topology.faces(matching: pick).compactMap { pieceOf[$0.id] }).count
        return RegionPick(pick: pick, sharedBy: max(1, shared))
    }

    /// The pieces of a split sheet (`SheetSplit.whole`) as lists of its faces, in the kernel's order (R6: by the smallest face tag-set
    /// key, then the area-weighted centroid): faces joined across every edge that is not a cut edge `trim` made (`.boundary(.cut)` under its own node; an earlier Trim's cut edge is joined). It is
    /// what a region pick shows and toggles; the kernel's own `SheetSplit.pieces` is the same partition.
    public static func pieces(of whole: Solid, cutBy trim: NodeID) -> [[FaceID]] {
        let topology = whole.topology
        var parent = Array(topology.faces.indices)
        func root(_ start: Int) -> Int {
            var x = start
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        // Only this Trim's own cut edges divide: an earlier Trim's cut edge is an input edge here, and the kernel joins across it.
        func isOwnCut(_ tag: TopoTag) -> Bool {
            if tag.node == trim, case .boundary(.cut) = tag.role { true } else { false }
        }
        for edge in topology.edges where !edge.tags.contains(where: isOwnCut) {
            let adjacent = Set(edge.faces.map(\.rawValue)).filter { parent.indices.contains($0) }.sorted()
            guard adjacent.count == 2 else { continue }
            let (a, b) = (root(adjacent[0]), root(adjacent[1]))
            parent[max(a, b)] = min(a, b)
        }
        var groups: [Int: [Int]] = [:]
        for index in topology.faces.indices { groups[root(index), default: []].append(index) }
        return SheetPieces.ordered(groups: Array(groups.values), in: topology)
    }

    /// The piece among `candidates` whose area-weighted centroid is nearest `point` (the first when the pick recorded none).
    private static func nearest(of candidates: [Int], to point: Vector3?, pieces: [[FaceID]], in topology: Topology) -> Int {
        guard let point else { return candidates[0] }
        var best = candidates[0]
        var bestDistance = Double.infinity
        for index in candidates {
            let faces = pieces[index].compactMap { topology.face($0) }
            let total = faces.reduce(0) { $0 + $1.area }
            guard !faces.isEmpty else { continue }
            let centre = total > 0
                ? faces.reduce(Vector3.zero) { $0 + $1.centroid * ($1.area / total) }
                : faces.reduce(Vector3.zero) { $0 + $1.centroid * (1 / Double(faces.count)) }
            let distance = (centre - point).length
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}
