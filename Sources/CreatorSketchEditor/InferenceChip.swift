import CreatorViewport

/// Where the inferred constraints' glyphs sit, in viewport points (y down): one chip naming them ("Horizontal",
/// "Point on · Tangent"), `ReadoutChip.gap` below and right of the pointer; else below left, above right, above left
/// (near the model area's trailing side and bottom); else stacked `ReadoutChip.margin` beyond the readout's chip, on
/// its far side from the pointer. Never over the readout's chip (`readout`, placed first): a spot that would touch it
/// is skipped. Sized like the readout's chip (`ReadoutChip`'s height, character width and padding), never measured;
/// none when no spot fits in the model area.
public struct InferenceChip: Hashable, Sendable {
    public var text: String
    /// The chip's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init?(kinds: [SketchConstraintKind], pointer: ScreenPoint, in view: ViewportSize,
                 modelArea: ViewportInsets = ViewportInsets(), avoiding readout: ReadoutChip? = nil) {
        guard !kinds.isEmpty else { return nil }
        let text = kinds.map(\.title).joined(separator: " · ")
        let size = ViewportSize(width: Double(text.count) * ReadoutChip.characterWidth + 2 * ReadoutChip.padding,
                                height: ReadoutChip.height)
        let area = (left: modelArea.leading + ReadoutChip.margin, right: view.width - modelArea.trailing - ReadoutChip.margin,
                    top: modelArea.top + ReadoutChip.margin, bottom: view.height - modelArea.bottom - ReadoutChip.margin)
        let fits = { (p: ScreenPoint) in
            p.x >= area.left && p.x + size.width <= area.right && p.y >= area.top && p.y + size.height <= area.bottom
                && !(readout.map { Self.touches(p, size, $0) } ?? false)
        }
        guard let origin = Self.candidates(size, pointer: pointer, readout: readout).first(where: fits) else { return nil }
        self.text = text
        self.origin = origin
        self.size = size
    }

    /// The spots tried, in order: the four corners round the pointer, then beyond the readout's chip.
    private static func candidates(_ size: ViewportSize, pointer: ScreenPoint, readout: ReadoutChip?) -> [ScreenPoint] {
        let gap = ReadoutChip.gap
        let right = pointer.x + gap
        let left = pointer.x - gap - size.width
        let below = pointer.y + gap
        let above = pointer.y - gap - size.height
        var spots = [ScreenPoint(right, below), ScreenPoint(left, below), ScreenPoint(right, above), ScreenPoint(left, above)]
        if let readout {
            let beyond = readout.origin.y < pointer.y
                ? readout.origin.y - ReadoutChip.margin - size.height
                : readout.origin.y + readout.size.height + ReadoutChip.margin
            spots += [ScreenPoint(right, beyond), ScreenPoint(left, beyond)]
        }
        return spots
    }

    /// Whether a chip at `origin` of `size` would touch `readout` (closer than `ReadoutChip.margin`).
    private static func touches(_ origin: ScreenPoint, _ size: ViewportSize, _ readout: ReadoutChip) -> Bool {
        let m = ReadoutChip.margin
        return origin.x < readout.origin.x + readout.size.width + m && readout.origin.x < origin.x + size.width + m
            && origin.y < readout.origin.y + readout.size.height + m && readout.origin.y < origin.y + size.height + m
    }
}
