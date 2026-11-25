import CreatorGeometry

/// Where views may go (plan R8): the frame's inside minus a band the title block's height along the whole bottom.
public enum DrawingArea {
    public static func rect(for sheet: DrawingSheet, standard: DrawingStandard) -> Rect2D {
        let frame = SheetFrame.rect(for: sheet, standard: standard)
        return Rect2D(min: Vector2(frame.min.x, frame.min.y + TitleBlockLayout.height), max: frame.max)
    }
}
