/// Distances in viewport points from each edge of the viewport to the model area: the part no floating panel
/// covers (spec §6.1, the panels float over a full-bleed viewport).
public struct ViewportInsets: Hashable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}
