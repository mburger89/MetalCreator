import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Which instances of a pattern did nothing to the part (patterns spec §5): a hole in empty space, a boss beside the
/// plate. They don't fail the node; it warns with the count, "3 of 24 holes miss the part."
enum PatternMisses {
    /// How many of `copies` missed `part`. A subtracted or intersected copy missed when none of the faces the
    /// operation left carries its tag (a cut leaves its tool's faces as the walls of what it cut, and a tool that
    /// found nothing to cut leaves none). A united copy missed when its bounds don't touch the part's: it brings its
    /// faces along wherever it stands, and a copy apart from the part is a piece of its own.
    static func count(_ op: BooleanOp, part: Solid, result: Solid, copies: [Solid]) -> Int {
        switch op {
        case .union:
            return copies.filter { !touches($0.bounds, part.bounds) }.count
        case .subtract, .intersect:
            let nodes = Set(copies.flatMap { $0.topology.faces.flatMap(\.tags) }.map(\.node).filter(\.isInstanceQualified))
            let present = Set(result.topology.faces.flatMap(\.tags).filter { nodes.contains($0.node) }.map(\.item))
            return copies.indices.filter { !present.contains($0) }.count
        }
    }

    /// Whether two boxes overlap or touch, to a micrometre.
    static func touches(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        let slack = 1e-3
        return a.min.x <= b.max.x + slack && b.min.x <= a.max.x + slack
            && a.min.y <= b.max.y + slack && b.min.y <= a.max.y + slack
            && a.min.z <= b.max.z + slack && b.min.z <= a.max.z + slack
    }

    /// "3 of 24 holes miss the part." (or "1 of 1 hole misses the part."), or `nil` when none missed.
    static func warning(missed: Int, of total: Int, singular: String, plural: String) -> String? {
        guard missed > 0 else { return nil }
        let noun = total == 1 ? "\(singular) misses" : "\(plural) miss"
        return "\(missed.display) of \(total.display) \(noun) the part."
    }
}
