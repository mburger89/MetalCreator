import CreatorGeometry

/// A dimension on screen: everything the view draws, in viewport points (y down).
public struct PlacedDimension: Hashable, Sendable {
    /// Space between the text and its box's edge at each side, and the box's height.
    public static let textPadding = 4.0, textHeight = 18.0

    /// A filled triangle whose point is `tip`.
    public struct Arrow: Hashable, Sendable {
        public var tip: ScreenPoint
        /// Unit, on screen, pointing at the tip.
        public var direction: Vector2

        public init(tip: ScreenPoint, direction: Vector2) {
            self.tip = tip
            self.direction = direction
        }

        /// The tip, then the two corners of the base, `length` behind the tip and `width` apart.
        public func corners(length: Double, width: Double) -> [ScreenPoint] {
            let base = ScreenPoint(tip.x - direction.x * length, tip.y - direction.y * length)
            let (nx, ny) = (-direction.y * width / 2, direction.x * width / 2)
            return [tip, ScreenPoint(base.x + nx, base.y + ny), ScreenPoint(base.x - nx, base.y - ny)]
        }
    }

    public var id: OverlayDimensionID
    public var text: String
    public var tint: OverlayTint
    public var isGhosted: Bool
    public var segments: [ScreenSegment]
    public var arrows: [Arrow]
    /// The text box's top-left corner and size.
    public var textOrigin: ScreenPoint
    public var textSize: ViewportSize
    public var showsText: Bool
    /// The pin mark's centre (the text box's top-right corner), for a pinned dimension.
    public var pinMark: ScreenPoint?

    public init(id: OverlayDimensionID, text: String, tint: OverlayTint, isGhosted: Bool, segments: [ScreenSegment],
                arrows: [Arrow], textOrigin: ScreenPoint, textSize: ViewportSize, showsText: Bool = true,
                pinMark: ScreenPoint? = nil) {
        self.id = id
        self.text = text
        self.tint = tint
        self.isGhosted = isGhosted
        self.segments = segments
        self.arrows = arrows
        self.textOrigin = textOrigin
        self.textSize = textSize
        self.showsText = showsText
        self.pinMark = pinMark
    }

    /// Whether `point` is in the text box (what a click or double-click on the dimension means).
    public func textContains(_ point: ScreenPoint) -> Bool {
        showsText && point.x >= textOrigin.x && point.x <= textOrigin.x + textSize.width
            && point.y >= textOrigin.y && point.y <= textOrigin.y + textSize.height
    }
}
