import CreatorGeometry
import CreatorKernel

/// An item balloon (DR-5 R4): the leader's end names a line of a part; `offset` runs from the foot to the circle's centre, in sheet mm.
public struct Balloon: Hashable, Codable, Sendable {
    public var leader: LeaderEnd
    public var offset: Vector2

    public init(leader: LeaderEnd, offset: Vector2) {
        self.leader = leader
        self.offset = offset
    }

    /// The part the balloon is on: the leader's `onPart` part, else the view's source.
    public func part(in view: DrawingView) -> NodeID { leader.target.part ?? view.source }
}
