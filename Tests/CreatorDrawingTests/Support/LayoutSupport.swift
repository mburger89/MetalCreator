import CreatorGeometry
import Foundation

@testable import CreatorDrawing

/// Shared helpers of the dimension layout tests (A3, h = 2.5, 1:1 unless said).
enum LayoutSupport {
    static let h = 2.5
    static let identity = ViewMapping(scale: 1, offset: .zero)

    static func label(_ text: String) -> DimensionLabel { DimensionLabel(lines: [[.text(text)]]) }

    static func width(_ text: String, height: Double = h) -> Double { DrawingText.layout(text, height: height).width }

    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    static func close(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool {
        close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
    }

    /// The straight lines of a drawing.
    static func lines(_ drawing: AnnotationDrawing) -> [(Vector2, Vector2)] {
        drawing.segments.compactMap { segment in
            if case let .line(a, b) = segment { return (a, b) }
            return nil
        }
    }

    static func hasLine(_ drawing: AnnotationDrawing, _ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool {
        lines(drawing).contains {
            (close($0.0, a, tolerance) && close($0.1, b, tolerance)) || (close($0.0, b, tolerance) && close($0.1, a, tolerance))
        }
    }

    static func linear(
        _ a: Vector2, _ b: Vector2, direction: Vector2, kind: DrawingDimensionKind, labels: [DimensionLabel],
        offset: Double, textShift: Double? = nil, standard: DrawingStandard = .iso, points: [Vector2]? = nil
    ) -> AnnotationDrawing {
        SheetDimensionLayout.draw(
            .linear(points: points ?? [a, b], direction: direction), kind: kind, labels: labels,
            placement: DimensionPlacement(offset: offset, angle: 0, textShift: textShift), mapping: identity, standard: standard,
            height: h)
    }
}
