import CreatorGeometry
import CreatorKernel

/// Where an auxiliary view's arrow goes (R9).
public enum AuxiliaryRule {
    public static let lineSentence = "An auxiliary view looks square to a straight edge; pick a line."
    public static let trueSizeSentence = "This edge isn't square to the view, so a view square to it wouldn't show its true size."

    /// The picked edge's midpoint and unit direction in the parent's model plane, or the sentence that says why not.
    public static func arrow(
        for candidate: PickCandidate, click: Vector2, topology: Topology, frame: ProjectionFrame, mapping: ViewMapping
    ) -> Result<(at: Vector2, along: Vector2), DrawingRefusal> {
        let id: EdgeID
        switch candidate {
        case .edge(let picked, _): id = picked
        case .corner(let picked, _): id = picked
        case .centre, .outline: return .failure(DrawingRefusal(sentence: lineSentence))
        }
        guard let edge = topology.edge(id), case .line(let start, let end)? = edge.curve else {
            return .failure(DrawingRefusal(sentence: lineSentence))
        }
        let along = end - start
        let length = along.length
        guard length > 0, abs(along.dot(frame.direction)) <= 1e-9 * length else {
            return .failure(DrawingRefusal(sentence: trueSizeSentence))
        }
        let a = frame.place(start), b = frame.place(end)
        let flat = b - a
        let flatLength = flat.length
        guard flatLength > 0 else { return .failure(DrawingRefusal(sentence: trueSizeSentence)) }
        return .success((at: frame.place((start + end) * 0.5), along: flat * (1 / flatLength)))
    }
}
