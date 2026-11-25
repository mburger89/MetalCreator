import CreatorGeometry

public enum ScaleChooser {
    /// The gap kept around and between views (plan R8).
    static let gap = 20.0

    /// The largest preferred scale whose view and its depth fit the drawing area; 1:1000 when none does, 1:1 with no bounds.
    public static func firstScale(extents: (width: Double, height: Double, depth: Double)?, area: Rect2D) -> DrawingScale {
        guard let extents else { return DrawingScale(numerator: 1, denominator: 1) }
        for scale in DrawingScale.preferred {
            let s = scale.value
            let fitsWide = s * (extents.width + extents.depth) + 3 * gap <= area.width
            let fitsTall = s * (extents.height + extents.depth) + 3 * gap <= area.height
            if fitsWide && fitsTall { return scale }
        }
        return DrawingScale(numerator: 1, denominator: 1000)
    }
}
