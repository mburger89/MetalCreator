import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// One thing the Measure tool has picked: a face, an edge or a corner (an edge's end, or a full circle's centre), a curve of the
/// section, or a point on a mesh.
enum MeasurePick: Hashable, Sendable {
    case face(solid: Int, FaceID)
    case edge(solid: Int, EdgeID)
    case corner(solid: Int, EdgeID, CornerEnd, at: Vector3)
    /// A piece of the section's outline; `at` is the point on it nearest the click.
    case sectionEdge(solid: Int, piece: SectionPiece, at: Vector3)
    case meshPoint(solid: Int, at: Vector3)

    var solidIndex: Int {
        switch self {
        case let .face(solid, _), let .edge(solid, _), let .corner(solid, _, _, _), let .sectionEdge(solid, _, _),
             let .meshPoint(solid, _): solid
        }
    }

    /// Whether the numbers behind this pick are approximate: a mesh point, or a section piece that is no exact line or arc.
    var isApproximate: Bool {
        switch self {
        case .meshPoint: true
        case let .sectionEdge(_, piece, _): piece.curve == nil
        case .face, .edge, .corner: false
        }
    }

    /// The element the kernel measures; a corner is the point it stands at.
    /// `nil` when the pick names a solid `solids` does not have.
    func element(in solids: [Solid]) -> MeasureElement? {
        guard solids.indices.contains(solidIndex) else { return nil }
        return switch self {
        case let .face(solid, id): MeasureElement.face(solids[solid], id)
        case let .edge(solid, id): MeasureElement.edge(solids[solid], id)
        case let .corner(_, _, _, point): MeasureElement.point(point)
        case let .sectionEdge(_, piece, _):
            if let curve = piece.curve { MeasureElement.curve(curve) } else { MeasureElement.polyline(piece.polyline) }
        case let .meshPoint(_, point): MeasureElement.point(point)
        }
    }
}
