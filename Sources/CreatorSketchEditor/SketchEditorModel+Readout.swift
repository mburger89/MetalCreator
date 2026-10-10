import CreatorGeometry
import CreatorViewport

/// The live readout by the pointer while drawing (user, 2026-10-09; S5a's, distinct from S5b's dimension labels in
/// the view): what the next click would commit, read off the rubber band, so it shows the snapped values. A line
/// (after its first click) reads its length and angle, a circle (after its centre) its diameter, an arc its radius
/// (after the centre) then its radius and sweep (after the start), and the Point tool the pointer's position on the
/// plane. While a point is dragged, the drag's readout (`dragReadout`) instead, whatever the tool. Nothing otherwise:
/// no stroke, Esc, the pointer off the view, the Select and Dimension tools.
extension SketchEditorModel {
    public var pointerReadout: String? {
        if let dragged { return dragReadout(dragged) }
        switch drawState {
        case .idle:
            guard tool == .point, let at = preview.points.first else { return nil }
            return ReadoutText.position(at)
        case .lineFrom:
            guard case .line(let start, let end)? = preview.curves.first else { return nil }
            return ReadoutText.line(from: start, to: end)
        case .circleAround:
            guard case .circle(_, let radius)? = preview.curves.first else { return nil }
            return ReadoutText.diameter(radius)
        case .arcAround:
            guard case .line(let center, let target)? = preview.curves.first else { return nil }
            return ReadoutText.radius((target - center).length)
        case .arcFrom(let center, let start):
            guard !preview.points.isEmpty else { return nil }
            guard case .arc(_, _, let end)? = preview.curves.first else {
                return ReadoutText.radius((start.position - center.position).length)
            }
            return ReadoutText.arc(center: center.position, start: start.position, end: end)
        case .arcThroughFrom:
            // A 3-point arc reads its chord after the start, then its radius and sweep after the end.
            guard case .line(let start, let end)? = preview.curves.first else { return nil }
            return ReadoutText.line(from: start, to: end)
        case .arcThrough:
            guard case .arc(let center, let start, let end)? = preview.curves.first else { return nil }
            return ReadoutText.arc(center: center, start: start, end: end)
        }
    }

    /// The readout placed by the pointer on screen (`ReadoutChip`), or `nil` with no readout or no pointer over the view.
    public var readoutChip: ReadoutChip? {
        guard let text = pointerReadout, let pointer = pointerOnScreen, !viewSize.isEmpty else { return nil }
        return ReadoutChip(text: text, pointer: pointer, in: viewSize, modelArea: modelArea)
    }
}
