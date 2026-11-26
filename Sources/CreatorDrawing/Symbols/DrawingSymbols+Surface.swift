import CreatorGeometry

extension DrawingSymbols {
    /// The surface texture symbol from its apex (plan R6): legs at 60 degrees to the surface, the bar for removal required, the
    /// inscribed circle for removal prohibited, and with `extension` (the length past the long leg) the horizontal line.
    public static func surface(_ process: SurfaceProcess, apex: Vector2, h: Double, extension: Double?) -> [SheetSegment] {
        let style = SymbolStyle.of(.iso)
        let short = style.surfaceShort * h, long = style.surfaceLong * h
        func point(_ x: Double, _ y: Double) -> Vector2 { Vector2(apex.x + x, apex.y + y) }
        let shortTop = point(-short * slant, short)
        let longTop = point(long * slant, long)
        var segments: [SheetSegment] = [.line(apex, shortTop), .line(apex, longTop)]
        switch process {
        case .any: break
        case .removalRequired: segments.append(.line(shortTop, point(short * slant, short)))
        case .removalProhibited:
            segments.append(.arc(center: point(0, 2 * short / 3), radius: short / 3, start: 0, sweep: 2 * .pi))
        }
        if let length = `extension` { segments.append(.line(longTop, Vector2(longTop.x + length, longTop.y))) }
        return segments
    }
}
