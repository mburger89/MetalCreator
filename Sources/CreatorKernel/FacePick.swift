import CreatorGeometry

/// A remembered face pick (sketcher spec §7, Plane from Face): the picked face's tags. It names every
/// face whose tags include all of them, so a face a union merged with a coplanar one still matches.
/// A face that a union had merged names both operands' tags and matches nothing once they stop merging;
/// then the pick is retried per operand (`Topology.resolution(of:)`), ranked by where the face was.
public struct FacePick: Hashable, Sendable {
    public var tags: Set<TopoTag>
    /// The face's outward normal when it was picked, if it was flat. Optional key in the file: it is what
    /// tells the parts of a face that has since come apart from each other. `nil` for picks made without it.
    public var normal: Vector3?
    /// The face's centroid when it was picked. Optional, like `normal`.
    public var centroid: Vector3?

    public init(tags: Set<TopoTag>, normal: Vector3? = nil, centroid: Vector3? = nil) {
        self.tags = tags
        self.normal = normal
        self.centroid = centroid
    }

    /// True when a tag is the `.unnamed` fallback (directly or inside a blend's source edge), which is
    /// unstable across rebuilds, like `EdgePick.touchesUnnamedFace`.
    public var touchesUnnamedFace: Bool { tags.contains { $0.role.isUnstable } }
}
