/// A remembered face pick (sketcher spec §7, Plane from Face): the picked face's tags. It names every
/// face whose tags include all of them, so a face a union merged with a coplanar one still matches.
public struct FacePick: Hashable, Sendable {
    public var tags: Set<TopoTag>

    public init(tags: Set<TopoTag>) {
        self.tags = tags
    }

    /// True when a tag is the `.unnamed` fallback (directly or inside a blend's source edge), which is
    /// unstable across rebuilds, like `EdgePick.touchesUnnamedFace`.
    public var touchesUnnamedFace: Bool { tags.contains { $0.role.isUnstable } }
}
