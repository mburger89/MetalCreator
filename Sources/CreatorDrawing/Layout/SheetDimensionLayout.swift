import CreatorGeometry
import Foundation

/// Where a leader's shoulder runs from its knee (plan R27).
public enum ShoulderSide: Hashable, Sendable {
    case left, right

    /// `.right` when `direction.x >= 0`.
    public static func toward(_ direction: Vector2) -> ShoulderSide { direction.x >= 0 ? .right : .left }

    var sign: Double { self == .right ? 1 : -1 }
}

// swiftlint:disable function_parameter_count
// The two public entry points take one argument per decision of the plan's R8, so they exceed the parameter limit.

/// Dimension layout in sheet millimetres (plan R8): one placement rule per standard, drawn the same on screen, PDF and DXF.
public enum SheetDimensionLayout {
    /// The drawing of a measured `figure` as `kind`: one label per value, an ordinate's origin label first.
    public static func draw(
        _ figure: AnnotationFigure, kind: DrawingDimensionKind, labels: [DimensionLabel], placement: DimensionPlacement,
        mapping: ViewMapping, standard: DrawingStandard, height: Double
    ) -> AnnotationDrawing {
        var builder = DrawingBuilder(style: .of(standard), height: height)
        guard !labels.isEmpty else { return builder.finish() }
        switch figure {
        case let .linear(points, direction):
            builder.linear(points.map(mapping.sheet), direction: direction, kind: kind, labels: labels, placement: placement)
        case let .ordinate(origin, points, direction):
            builder.ordinate(
                origin: mapping.sheet(origin), points: points.map(mapping.sheet), direction: direction, labels: labels,
                placement: placement)
        case let .radial(center, radius, isDiameter):
            builder.radial(
                center: mapping.sheet(center), radius: radius * mapping.scale, isDiameter: isDiameter, label: labels[0],
                placement: placement)
        case let .angle(vertex, first, second):
            builder.angle(
                vertex: mapping.sheet(vertex), first: first.map(mapping.sheet), second: second.map(mapping.sheet), label: labels[0],
                placement: placement)
        case let .chamfer(start, end):
            let a = mapping.sheet(start), b = mapping.sheet(end)
            builder.leaderDimension(tip: (a + b) * 0.5, radius: 0, label: labels[0], placement: placement)
        case .hole, .centreMark, .centreLine, .leaders:
            break
        }
        return builder.finish()
    }

    /// A hole callout: a leader onto the circle and its lines of text on a shoulder (R8).
    public static func callout(
        center: Vector2, radius: Double, lines: DimensionLabel, placement: DimensionPlacement, mapping: ViewMapping,
        standard: DrawingStandard, height: Double
    ) -> AnnotationDrawing {
        var builder = DrawingBuilder(style: .of(standard), height: height)
        builder.leaderDimension(tip: mapping.sheet(center), radius: radius * mapping.scale, label: lines, placement: placement)
        return builder.finish()
    }

    // swiftlint:enable function_parameter_count

    /// An arrowhead at `tip`, the line to `knee` and the shoulder `shoulder` mm from `knee` toward `side` (R27).
    public static func leader(tip: Vector2, knee: Vector2, side: ShoulderSide, style: AnnotationStyle) -> AnnotationDrawing {
        var builder = DrawingBuilder(style: style, height: 0)
        builder.leaderGeometry(tip: tip, knee: knee, side: side)
        return builder.finish()
    }
}

/// Collects what a layout draws.
struct DrawingBuilder {
    let style: AnnotationStyle
    let height: Double
    var drawing = AnnotationDrawing()

    init(style: AnnotationStyle, height: Double) {
        self.style = style
        self.height = height
    }

    mutating func finish() -> AnnotationDrawing {
        drawing.fitFrame()
        return drawing
    }

    mutating func line(_ a: Vector2, _ b: Vector2) { drawing.segments.append(.line(a, b)) }

    /// A filled triangle with its tip at `tip`; `back` is the unit direction from the tip toward the base.
    mutating func arrow(tip: Vector2, back: Vector2) {
        let base = tip + back * style.arrowLength
        let side = Vector2(-back.y, back.x) * (style.arrowWidth / 2)
        drawing.fills.append([tip, base + side, base - side])
    }

    /// Places `label` and records it; the first label sets `textCenter`.
    @discardableResult
    mutating func label(_ label: DimensionLabel, center: Vector2, angle: Double) -> Double {
        let placed = LabelLayout.place(label, height: height, center: center, angle: angle, style: style)
        drawing.texts += placed.texts
        drawing.segments += placed.segments
        if let box = placed.box { drawing.boxes.append(box) }
        if drawing.textCenter == nil { drawing.textCenter = center }
        return placed.width
    }

    func width(of label: DimensionLabel) -> Double { LabelLayout.width(of: label, height: height, style: style) }

    /// A leader's geometry: the head at `tip`, the line to `knee` and the shoulder.
    mutating func leaderGeometry(tip: Vector2, knee: Vector2, side: ShoulderSide) {
        let along = knee - tip
        let length = along.length
        let back = length > 1e-12 ? along * (1 / length) : Vector2(side.sign, 0)
        arrow(tip: tip, back: back)
        line(tip, knee)
        line(knee, Vector2(knee.x + side.sign * style.shoulder, knee.y))
    }
}

extension DrawingBuilder {
    /// The unit vector at `angle`.
    static func direction(_ angle: Double) -> Vector2 { Vector2(cos(angle), sin(angle)) }

    /// An angle folded into (-90, 90] degrees: how ISO text reads from the bottom or the right.
    static func folded(_ angle: Double) -> Double {
        let full = 2 * Double.pi
        var r = angle.truncatingRemainder(dividingBy: full)
        if r > .pi { r -= full }
        if r <= -.pi { r += full }
        if r > .pi / 2 { r -= .pi } else if r <= -.pi / 2 { r += .pi }
        return r
    }

    static func dot(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.x + a.y * b.y }

    /// The extent of a horizontal text box along the unit direction `d`.
    func horizontalExtent(_ width: Double, along d: Vector2) -> Double { abs(d.x) * width + abs(d.y) * height }
}
