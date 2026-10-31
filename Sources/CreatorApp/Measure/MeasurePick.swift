import CreatorGeometry
import CreatorKernel

/// Which end of an edge a corner pick is.
enum CornerEnd: Hashable, Sendable { case start, end, centre }

/// One thing the Measure tool has picked: a face, an edge or a corner (an edge's end, or a full circle's centre).
enum MeasurePick: Hashable, Sendable {
    case face(solid: Int, FaceID)
    case edge(solid: Int, EdgeID)
    case corner(solid: Int, EdgeID, CornerEnd, at: Vector3)

    var solidIndex: Int {
        switch self {
        case let .face(solid, _), let .edge(solid, _), let .corner(solid, _, _, _): solid
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
        }
    }
}
