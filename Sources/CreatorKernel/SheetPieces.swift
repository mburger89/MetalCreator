import CreatorGeometry

/// R6, the one ordering of a split sheet's pieces (NS-4): the kernel's `SheetSplit.pieces` and a Trim Surface's region picks both
/// call it, so the two can never disagree about which piece is which.
public enum SheetPieces {
    /// `groups` holds each piece as indices of `topology`'s faces; the result is one list of faces per piece, each sorted, the pieces
    /// ordered by the canonical key of the piece's smallest face tag set, then by the area-weighted centroid (1e-9 mm ties).
    public static func ordered(groups: [[Int]], in topology: Topology) -> [[FaceID]] {
        func key(_ index: Int) -> String { topology.faces[index].tags.map(\.sortKey).sorted().joined(separator: "+") }
        struct Entry {
            var faces: [Int]
            var key: String
            var centroid: Vector3
        }
        let entries = groups.map { faces -> Entry in
            let area = faces.reduce(0) { $0 + topology.faces[$1].area }
            var centroid = Vector3.zero
            for index in faces {
                let face = topology.faces[index]
                centroid += face.centroid * (area > 0 ? face.area / area : 1 / Double(faces.count))
            }
            return Entry(faces: faces.sorted(), key: faces.map(key).min() ?? "", centroid: centroid)
        }
        let ordered = entries.sorted { a, b in
            if a.key != b.key { return a.key < b.key }
            if abs(a.centroid.x - b.centroid.x) > 1e-9 { return a.centroid.x < b.centroid.x }
            if abs(a.centroid.y - b.centroid.y) > 1e-9 { return a.centroid.y < b.centroid.y }
            return a.centroid.z < b.centroid.z
        }
        return ordered.map { $0.faces.map { FaceID($0) } }
    }
}
