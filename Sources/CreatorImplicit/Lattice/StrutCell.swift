import CreatorGeometry
import Foundation

/// The unit cells of the strut lattice (implicit spec §3.4): a set of straight struts in a cell of side 1, repeated in every direction.
/// Each cell lists every strut of the periodic lattice exactly once: a strut belongs to the cell its midpoint is in, so the lists have
/// no duplicates, and a strut may reach up to 0.125 of a cell beyond its own (the struts that cross cell faces).
public enum StrutCell: Int, Hashable, Sendable, CaseIterable {
    /// The cube's edges: 3 struts of length 1.
    case cubic = 0
    /// The centre to the 8 corners: 8 struts of length √3/2.
    case bcc = 1
    /// The face diagonals: each corner to the centres of the faces next to it, 12 struts of length √2/2.
    case fcc = 2
    /// The face diagonals and the edges of the octahedron between the face centres: 24 struts of length √2/2, the octet truss.
    case octet = 3
    /// The edges of truncated octahedra packed in a body-centred arrangement: 24 struts of length √2/4.
    case kelvin = 4
    /// The bonds of the diamond cubic structure: 16 struts of length √3/4.
    case diamond = 5

    /// The names the node's segmented control shows, in raw-value order.
    public static let options = ["Cubic", "BCC", "FCC", "Octet", "Kelvin", "Diamond"]

    public var name: String { Self.options[rawValue] }

    /// One strut, from `start` to `end`, in cell coordinates (a cell is 0 ... 1 on each axis).
    public struct Strut: Hashable, Sendable {
        public var start: Vector3
        public var end: Vector3
    }

    /// The struts of this cell.
    public var struts: [Strut] { Self.table[rawValue] }

    /// How far, in cells, a strut of any cell reaches beyond the cell its midpoint is in.
    public static let spill = 0.125

    private static let table: [[Strut]] = allCases.map { Self.canonical(Self.raw($0)) }

    // MARK: Building the lists

    private static func raw(_ cell: StrutCell) -> [Strut] {
        switch cell {
        case .cubic:
            return [Vector3.unitX, .unitY, .unitZ].map { Strut(start: .zero, end: $0) }
        case .bcc:
            let centre = Vector3(0.5, 0.5, 0.5)
            return corners.map { Strut(start: centre, end: $0) }
        case .fcc:
            return faceDiagonals
        case .octet:
            return faceDiagonals + octahedronEdges
        case .kelvin:
            let origin = Vector3.zero, centre = Vector3(0.5, 0.5, 0.5)
            return truncatedOctahedron(about: origin) + truncatedOctahedron(about: centre)
        case .diamond:
            let atoms = [Vector3.zero, Vector3(0.5, 0.5, 0), Vector3(0.5, 0, 0.5), Vector3(0, 0.5, 0.5)]
            let bonds = [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)].map { $0 * 0.25 }
            return atoms.flatMap { atom in bonds.map { Strut(start: atom, end: atom + $0) } }
        }
    }

    private static let corners: [Vector3] = (0..<8).map { Vector3(Double($0 & 1), Double(($0 >> 1) & 1), Double($0 >> 2)) }

    private static let faceCentres: [Vector3] = [
        Vector3(0, 0.5, 0.5), Vector3(1, 0.5, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, 1, 0.5), Vector3(0.5, 0.5, 0),
        Vector3(0.5, 0.5, 1),
    ]

    /// Each corner to the centres of the three faces it lies on, over the faces at x, y or z = 0 (the others belong to the next cell).
    private static var faceDiagonals: [Strut] {
        let near = [(faceCentres[0], 0), (faceCentres[2], 1), (faceCentres[4], 2)]
        return near.flatMap { centre, axis in
            corners.filter { [$0.x, $0.y, $0.z][axis] == 0 }.map { Strut(start: $0, end: centre) }
        }
    }

    /// Between the centres of faces that are not opposite: the twelve edges of the octahedron.
    private static var octahedronEdges: [Strut] {
        var edges: [Strut] = []
        for (index, first) in faceCentres.enumerated() {
            for second in faceCentres[(index + 1)...] where (first - second).length < 0.71 {
                edges.append(Strut(start: first, end: second))
            }
        }
        return edges
    }

    /// The 36 edges of a truncated octahedron of vertices (0, ±1, ±2) and permutations, scaled by ¼, about `centre`.
    private static func truncatedOctahedron(about centre: Vector3) -> [Strut] {
        let permutations = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        var vertices = Set<Vector3>()
        for order in permutations {
            for signs in 0..<4 {
                let magnitudes = [0.0, 1.0, 2.0]
                var v = [0.0, 0.0, 0.0]
                for (slot, axis) in order.enumerated() {
                    let sign = slot == 0 ? 1.0 : (slot == 1 ? (signs & 1 == 0 ? 1.0 : -1.0) : (signs & 2 == 0 ? 1.0 : -1.0))
                    v[axis] = sign * magnitudes[slot]
                }
                vertices.insert(Vector3(v[0], v[1], v[2]))
            }
        }
        let ordered = vertices.sorted { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
        var edges: [Strut] = []
        for (index, first) in ordered.enumerated() {
            for second in ordered[(index + 1)...] where abs((first - second).length - 2.0.squareRoot()) < 1e-9 {
                edges.append(Strut(start: centre + first * 0.25, end: centre + second * 0.25))
            }
        }
        return edges
    }

    /// Moves every strut by whole cells so its midpoint is in [0, 1)³, and keeps one of each.
    private static func canonical(_ struts: [Strut]) -> [Strut] {
        var seen = Set<[Int]>()
        var result: [Strut] = []
        for strut in struts {
            let middle = (strut.start + strut.end) * 0.5
            let shift = Vector3(floor(middle.x + 1e-9), floor(middle.y + 1e-9), floor(middle.z + 1e-9))
            let (start, end) = (strut.start - shift, strut.end - shift)
            let ends = [start, end].sorted { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
            let key = ends.flatMap { [$0.x, $0.y, $0.z] }.map { Int(($0 * 1_000_000).rounded()) }
            if seen.insert(key).inserted { result.append(Strut(start: ends[0], end: ends[1])) }
        }
        return result
    }
}
