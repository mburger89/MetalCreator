import CreatorGeometry

/// The editor's note under a dimension's text while the pointer is on it (spec §3.1: a reference names its source).
extension ViewportModel {
    /// Records the dimension under `point`, as last drawn: none while dragging or animating, or when the pointer is off the view.
    func refreshDimensionHover(at point: ScreenPoint?) {
        let newHovered = point.flatMap { drag == nil && animation == nil ? dimension(at: $0) : nil }
        if hoveredDimension != newHovered { hoveredDimension = newHovered }
    }

    /// The hovered dimension's note, with the point below its text box's bottom centre (a `textGap` under it) where the note goes.
    /// `nil` when the editor has nothing to say or the text is not drawn.
    public var dimensionHoverNote: (id: OverlayDimensionID, text: String, at: ScreenPoint)? {
        guard let id = hoveredDimension, let placed = drawnDimensions.first(where: { $0.id == id }), placed.showsText,
              let text = dimensionEditor?.hoverNote(for: id) else { return nil }
        return (id, text, ScreenPoint(placed.textOrigin.x + placed.textSize.width / 2,
                                      placed.textOrigin.y + placed.textSize.height + dimensionStyle.textGap))
    }
}
