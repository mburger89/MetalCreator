/// What the host made of a Project pick: the edges that can be projected (one for an edge pick, each edge of the
/// face for a face pick) and, in plain words, why others were left out.
public struct ProjectionResolution: Hashable, Sendable {
    public var candidates: [ProjectionCandidate]
    public var skipped: [String]

    public init(candidates: [ProjectionCandidate], skipped: [String]) {
        self.candidates = candidates
        self.skipped = skipped
    }
}
