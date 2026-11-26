import CreatorGeometry

extension DrawingSymbols {
    /// The datum triangle's fill (plan R5): its base ends centred on `foot` along `along`, then the apex toward `n`.
    public static func datumTriangle(foot: Vector2, along: Vector2, toward n: Vector2, h: Double, standard: DrawingStandard) -> [Vector2] {
        let style = SymbolStyle.of(standard)
        let half = style.datumTriangle * h / 2
        let height = style.datumTriangle * h * sixty
        return [
            Vector2(foot.x - along.x * half, foot.y - along.y * half),
            Vector2(foot.x + along.x * half, foot.y + along.y * half),
            Vector2(foot.x + n.x * height, foot.y + n.y * height),
        ]
    }

    /// The datum square: a closed polyline of five points, 2h a side, about `center`.
    public static func datumSquare(center: Vector2, h: Double, standard: DrawingStandard) -> [Vector2] {
        let half = SymbolStyle.of(standard).datumSquare * h / 2
        return [
            Vector2(center.x - half, center.y - half), Vector2(center.x + half, center.y - half),
            Vector2(center.x + half, center.y + half), Vector2(center.x - half, center.y + half),
            Vector2(center.x - half, center.y - half),
        ]
    }
}
