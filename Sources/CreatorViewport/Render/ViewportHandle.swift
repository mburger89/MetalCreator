import CreatorGeometry

/// An in-view handle resolved against a node's output (spec §6.5). The host turns each `HandleSpec` into one
/// of these. The knob sits `value` mm from `anchor` along `direction`, and dragging it reports a new value.
public struct ViewportHandle: Hashable, Sendable {
    /// The host's key, reported back in `ViewportEvents.handleChanged`.
    public var id: String
    public var anchor: Vector3
    public var direction: Vector3
    public var value: Double
    public var range: ClosedRange<Double>
    public var style: HandleStyle
    public var tint: HandleTint

    public init(id: String, anchor: Vector3, direction: Vector3, value: Double, range: ClosedRange<Double>,
                style: HandleStyle, tint: HandleTint) {
        self.id = id
        self.anchor = anchor
        self.direction = direction
        self.value = value
        self.range = range
        self.style = style
        self.tint = tint
    }

    public var knob: Vector3 { anchor + (direction.normalized ?? .unitZ) * value }
}
