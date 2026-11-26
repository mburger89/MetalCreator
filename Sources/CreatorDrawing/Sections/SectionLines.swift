import CreatorKernel

/// R4's step-line filter: no line is drawn where the cut changes plane (ISO 128-40).
public enum SectionLines {
    /// `projection` without the lines whose source edge borders a step face (a cut face of the cutting line's odd segment) or whose
    /// source is such a face.
    public static func droppingSteps(_ projection: Projection2D, topology: Topology) -> Projection2D {
        var steps = Set<FaceID>()
        for face in topology.faces where isStep(face) { steps.insert(face.id) }
        guard !steps.isEmpty else { return projection }
        var result = projection
        result.lines = projection.lines.filter { line in
            switch line.source {
            case .edge(let id)?:
                guard let edge = topology.edge(id) else { return true }
                return !edge.faces.contains { steps.contains($0) }
            case .face(let id)?:
                return !steps.contains(id)
            default:
                return true
            }
        }
        return result
    }

    private static func isStep(_ face: FaceInfo) -> Bool {
        face.tags.contains { tag in
            guard tag.node == SectionCutter.toolNode, case .side(_, let segment) = tag.role else { return false }
            return segment % 2 == 1
        }
    }
}
