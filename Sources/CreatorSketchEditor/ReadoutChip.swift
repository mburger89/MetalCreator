import CreatorViewport

/// Where the pointer readout's chip sits, in viewport points (y down), inside the model area (the view less the
/// panels covering its edges, `ViewportProjector.modelArea`): centred on the pointer, `gap` above it; flipped `gap`
/// below it when it would rise within `margin` of the model area's top; kept `margin` inside the model area's sides.
/// A model area too small to hold the chip and its margins (narrower than the chip, or too short for it above or below
/// the pointer) shows none. Its size is computed from the text, never measured (editor geometry is computed, so
/// drawing and placement agree).
public struct ReadoutChip: Hashable, Sendable {
    /// Points between the pointer and the chip's nearer edge: clear of the crosshair.
    public static let gap = 14.0
    /// Points kept between the chip and the model area's edges.
    public static let margin = 4.0
    /// The chip's height, and its width per character and padding at each side. MetalUI's `.caption` is 10 pt; its
    /// widest characters here (digits, "⌀", "°", "·", "-") advance under 7 pt, so 7 pt a character always holds
    /// the text (`SketchViewTests.theChipHoldsItsText` renders the widest readouts).
    public static let height = 22.0
    public static let characterWidth = 7.0
    public static let padding = 8.0

    public var text: String
    /// The chip's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init?(text: String, pointer: ScreenPoint, in view: ViewportSize, modelArea: ViewportInsets = ViewportInsets()) {
        let width = Double(text.count) * Self.characterWidth + 2 * Self.padding
        let left = modelArea.leading + Self.margin
        let right = view.width - modelArea.trailing - Self.margin
        let top = modelArea.top + Self.margin
        let bottom = view.height - modelArea.bottom - Self.margin
        guard right - left >= width else { return nil }
        let above = pointer.y - Self.gap - Self.height
        let below = pointer.y + Self.gap
        let y = above >= top ? above : below
        guard y >= top, y + Self.height <= bottom else { return nil }
        self.text = text
        size = ViewportSize(width: width, height: Self.height)
        origin = ScreenPoint(min(max(pointer.x - width / 2, left), right - width), y)
    }
}
