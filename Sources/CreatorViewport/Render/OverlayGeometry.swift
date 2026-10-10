import CreatorGeometry
import Foundation

/// Turns a `ViewportOverlay` into line instances (pure, so it's tested without a GPU): the plane grid first, so the
/// sketch draws over it, then the lines (dashed ones cut into dashes at the current zoom), then the points.
enum OverlayGeometry {
    /// A dash and the gap after it, in points.
    static let dash = 6.0
    static let gap = 4.0
    /// More dashes than this on one line and it's drawn solid (a dash pattern finer than a pixel reads as solid).
    static let dashLimit = 2_000
    /// The plane grid's minor and major line widths, in points.
    static let gridWidth = 1.0
    static let majorGridWidth = 1.25

    static func instances(_ overlay: ViewportOverlay, pose: CameraPose, size: ViewportSize, gridSpacing: Double,
                          scale: Float, palette: ViewportPalette) -> [LineInstance] {
        var instances: [LineInstance] = []
        let millimetresPerPoint = CameraMath.millimetresPerPoint(pose, size: size)
        if let plane = overlay.gridPlane {
            for line in gridLines(on: plane, pose: pose, size: size, spacing: gridSpacing) {
                let color = line.major ? palette.gridMajor : palette.gridMinor
                let width = Float(line.major ? majorGridWidth : gridWidth) * scale
                instances.append(LineInstance(a: GPUGeometry.float3(line.a), b: GPUGeometry.float3(line.b), color: color,
                                              width: width, id: 0))
            }
        }
        for line in overlay.lines {
            let color = palette.color(line.tint)
            let width = Float(line.width) * scale
            let pieces = line.isDashed ? dashes(line.a, line.b, millimetresPerPoint: millimetresPerPoint) : [(line.a, line.b)]
            for (a, b) in pieces {
                instances.append(LineInstance(a: GPUGeometry.float3(a), b: GPUGeometry.float3(b), color: color, width: width, id: 0))
            }
        }
        for point in overlay.points {
            let at = GPUGeometry.float3(point.position)
            instances.append(LineInstance(a: at, b: at, color: palette.color(point.tint), width: Float(point.size) * scale, id: 0))
        }
        return instances
    }

    /// Three vertices per triangle of every fill, in the tint's colour; a fill's trailing one or two vertices are ignored.
    static func fillVertices(_ fills: [OverlayFill], palette: ViewportPalette) -> [FillVertex] {
        fills.flatMap { fill -> [FillVertex] in
            let color = palette.color(fill.tint)
            return fill.vertices.prefix(fill.triangleCount * 3).map { FillVertex(position: GPUGeometry.float3($0), color: color) }
        }
    }

    /// `a`–`b` cut into dashes `dash` points long with `gap`-point gaps at `millimetresPerPoint`, the last dash
    /// clipped at `b`. A degenerate zoom, or more than `dashLimit` dashes, gives the whole line.
    static func dashes(_ a: Vector3, _ b: Vector3, millimetresPerPoint: Double) -> [(Vector3, Vector3)] {
        let length = (b - a).length
        let period = (dash + gap) * millimetresPerPoint
        guard length > 0, period.isFinite, period > 0, length / period <= Double(dashLimit) else { return [(a, b)] }
        let direction = (b - a) * (1 / length)
        var pieces: [(Vector3, Vector3)] = []
        var start = 0.0
        while start < length {
            let end = min(start + dash * millimetresPerPoint, length)
            pieces.append((a + direction * start, a + direction * end))
            start += period
        }
        return pieces
    }

    /// Grid lines on `plane` every `spacing` mm, every tenth one major, around the camera's target dropped onto the
    /// plane (snapped to a major line so the grid doesn't swim while panning), reaching past the view's edges.
    static func gridLines(on plane: Plane, pose: CameraPose, size: ViewportSize,
                          spacing: Double) -> [(a: Vector3, b: Vector3, major: Bool)] {
        guard spacing.isFinite, spacing > 0, !size.isEmpty else { return [] }
        let offset = pose.target - plane.origin
        let major = spacing * 10
        let centreX = (offset.dot(plane.xAxis) / major).rounded() * major
        let centreY = (offset.dot(plane.yAxis) / major).rounded() * major
        let reach = (pose.visibleHeight * max(size.aspect, 1) / spacing).rounded(.up) * spacing + major
        let count = Int(reach / spacing)
        var lines: [(a: Vector3, b: Vector3, major: Bool)] = []
        for step in -count...count {
            let along = Double(step) * spacing
            let isMajor = ((centreX + along) / major).rounded() * major == centreX + along
            lines.append((plane.point(Vector2(centreX + along, centreY - reach)), plane.point(Vector2(centreX + along, centreY + reach)),
                          isMajor))
        }
        for step in -count...count {
            let along = Double(step) * spacing
            let isMajor = ((centreY + along) / major).rounded() * major == centreY + along
            lines.append((plane.point(Vector2(centreX - reach, centreY + along)), plane.point(Vector2(centreX + reach, centreY + along)),
                          isMajor))
        }
        return lines
    }
}
