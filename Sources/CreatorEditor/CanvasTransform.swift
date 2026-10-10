import CreatorGeometry
import CreatorGraph

/// Pan and zoom of the graph canvas: `screen = canvas × zoom + offset`, in points, y down.
/// "Canvas" here means display coordinates, after the dock transpose (see `CanvasFlow`).
public struct CanvasTransform: Equatable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 0.25...3
    /// One press of +/− or a header zoom button.
    public static let zoomStep = 1.25

    public var offset: Vector2
    public var zoom: Double

    public init(offset: Vector2 = .zero, zoom: Double = 1) {
        self.offset = offset
        self.zoom = Self.clamped(zoom)
    }

    public init(_ viewState: ViewState) {
        self.init(offset: viewState.canvasOffset, zoom: viewState.canvasZoom)
    }

    public func toScreen(_ canvas: Vector2) -> Vector2 { canvas * zoom + offset }

    public func toCanvas(_ screen: Vector2) -> Vector2 {
        Vector2((screen.x - offset.x) / zoom, (screen.y - offset.y) / zoom)
    }

    /// Multiplies the zoom by `factor`, keeping the canvas point under `anchor` (screen) still.
    public func zoomed(by factor: Double, around anchor: Vector2) -> CanvasTransform {
        guard factor.isFinite, factor > 0 else { return self }
        let pinned = toCanvas(anchor)
        let zoom = Self.clamped(zoom * factor)
        return CanvasTransform(offset: anchor - pinned * zoom, zoom: zoom)
    }

    /// The transform that shows `rect` (display canvas points) as large as fits in a canvas of `size` (screen
    /// points) with `padding` screen points around it, centred; the zoom stays in `zoomRange`, so a small rect may
    /// fill less and a huge one overflow.
    public static func framing(_ rect: CanvasRect, in size: Vector2, padding: Double) -> CanvasTransform {
        let fit = min((size.x - 2 * padding) / rect.size.x, (size.y - 2 * padding) / rect.size.y)
        let zoom = CanvasTransform(zoom: fit).zoom
        return CanvasTransform(offset: size * 0.5 - rect.centre * zoom, zoom: zoom)
    }

    public func panned(by delta: Vector2) -> CanvasTransform {
        CanvasTransform(offset: offset + delta, zoom: zoom)
    }

    private static func clamped(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
