import CreatorGeometry

extension DrawingSymbols {
    /// The advance of a label symbol: its box and 0.3h either side.
    public static func labelSymbolAdvance(h: Double) -> Double { 1.6 * h }

    /// Strokes of a label symbol in a box h by h whose baseline left corner is `origin` (plan R12).
    public static func labelSymbol(_ symbol: LabelSymbol, origin: Vector2, h: Double) -> [SheetSegment] {
        func point(_ x: Double, _ y: Double) -> Vector2 { Vector2(origin.x + x * h, origin.y + y * h) }
        switch symbol {
        case .depth:
            return [
                .line(point(0.5, 1), point(0.5, 0)),
                .polyline([point(0.15, 0.35), point(0.5, 0), point(0.85, 0.35)]),
                .line(point(0, 0), point(1, 0)),
            ]
        case .counterbore:
            return [.polyline([point(0, 0.6), point(0, 0), point(1, 0), point(1, 0.6)])]
        case .countersink:
            return [.polyline([point(0, 0.6), point(0.5, 0), point(1, 0.6)])]
        }
    }
}
