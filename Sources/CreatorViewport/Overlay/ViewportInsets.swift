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

    /// These insets as far as a view of `size` can honour them, for framing: a negative or non-finite side counts
    /// as 0, and insets that would leave a model area under one point wide or high are dropped (the whole view is
    /// used), as they are for an empty view.
    func usable(in size: ViewportSize) -> ViewportInsets {
        func side(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
        let result = ViewportInsets(top: side(top), leading: side(leading), bottom: side(bottom), trailing: side(trailing))
        guard !size.isEmpty, size.width - result.leading - result.trailing >= 1,
              size.height - result.top - result.bottom >= 1 else { return ViewportInsets() }
        return result
    }
}
