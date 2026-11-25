import CreatorGeometry

/// Sheet millimetres to canvas points: `canvas = sheet * zoom + offset`, with y flipped (the sheet's y runs up).
public struct SheetTransform: Hashable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 0.25...40

    public var offset: Vector2
    public var zoom: Double

    public init(offset: Vector2 = .zero, zoom: Double = 1) {
        self.offset = offset
        self.zoom = Self.clamped(zoom)
    }

    public static func clamped(_ zoom: Double) -> Double {
        Swift.min(Swift.max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    public func screenPoint(_ sheet: Vector2) -> Vector2 {
        Vector2(sheet.x * zoom + offset.x, -sheet.y * zoom + offset.y)
    }

    public func sheetPoint(_ canvas: Vector2) -> Vector2 {
        Vector2((canvas.x - offset.x) / zoom, (offset.y - canvas.y) / zoom)
    }

    /// The transform at `zoom` (clamped) that keeps the sheet point now under `canvas` under it.
    public func zoomed(to newZoom: Double, about canvas: Vector2) -> SheetTransform {
        let anchor = sheetPoint(canvas)
        let z = Self.clamped(newZoom)
        return SheetTransform(offset: Vector2(canvas.x - anchor.x * z, canvas.y + anchor.y * z), zoom: z)
    }
}
