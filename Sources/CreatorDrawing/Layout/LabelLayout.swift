import CreatorGeometry
import Foundation

/// Lays a `DimensionLabel` out in Helvetica's metrics, in sheet millimetres (plan R8, R12).
public enum LabelLayout {
    /// The label's texts and symbol strokes, centred on `center` (the first line's middle) and turned by `angle`.
    /// Pieces run left to right, symbols advance `1.6h`, a stack follows the first line's pieces and the trailing text a space
    /// after that; further lines go `linePitch × h` below. Each text's `original` is the label's `plainText` when it was typed.
    public static func place(
        _ label: DimensionLabel, height h: Double, center: Vector2, angle: Double, style: AnnotationStyle
    ) -> (texts: [PlacedText], segments: [SheetSegment], width: Double, box: [Vector2]?) {
        var pen = Pen(label: label, height: h, center: center, angle: angle, style: style)
        let lines = label.lines.isEmpty ? [[]] : label.lines
        var widths = lines.map(pen.advance(of:))
        widths[0] += pen.tailWidth(after: widths[0]) + 2 * pen.padding
        let total = widths.max() ?? 0
        let left = -total / 2
        for (index, line) in lines.enumerated() {
            let baseline = -h / 2 - Double(index) * style.linePitch * h
            var x = left + (index == 0 ? pen.padding : 0)
            for piece in line { x += pen.place(piece, x: x, baseline: baseline) }
            if index == 0 { pen.placeTail(x: x, floor: left + pen.padding, baseline: baseline) }
        }
        var box: [Vector2]?
        if label.isBoxed {
            let right = left + widths[0]
            let top = h / 2 + pen.padding, bottom = -h / 2 - pen.padding
            box = [
                pen.point(left, bottom), pen.point(right, bottom), pen.point(right, top), pen.point(left, top),
                pen.point(left, bottom),
            ]
        }
        return (pen.texts, pen.segments, total, box)
    }

    /// The width a label takes, boxes and stacks included.
    public static func width(of label: DimensionLabel, height: Double, style: AnnotationStyle) -> Double {
        place(label, height: height, center: .zero, angle: 0, style: style).width
    }
}

/// Places pieces along a baseline in the label's own frame (x along the text, y up, origin the first line's middle).
private struct Pen {
    let label: DimensionLabel
    let h: Double
    let center: Vector2
    let angle: Double
    let style: AnnotationStyle
    let u: Vector2
    let up: Vector2
    let padding: Double
    let space: Double
    let stackHeight: Double
    var texts: [PlacedText] = []
    var segments: [SheetSegment] = []

    init(label: DimensionLabel, height: Double, center: Vector2, angle: Double, style: AnnotationStyle) {
        self.label = label
        self.h = height
        self.center = center
        self.angle = angle
        self.style = style
        u = Vector2(cos(angle), sin(angle))
        up = Vector2(-u.y, u.x)
        padding = label.isBoxed ? style.boxPadding : 0
        space = DrawingText.layout(" ", height: height).width
        stackHeight = style.toleranceScale * height
    }

    func point(_ x: Double, _ y: Double) -> Vector2 { center + u * x + up * y }

    func advance(of line: [LabelPiece]) -> Double {
        line.reduce(0) { sum, piece in
            switch piece {
            case .text(let text): sum + DrawingText.layout(text, height: h).width
            case .symbol: sum + DrawingSymbols.labelSymbolAdvance(h: h)
            }
        }
    }

    func stackWidth(_ stack: StackedText) -> Double {
        Swift.max(
            DrawingText.layout(stack.upper, height: stackHeight).width, DrawingText.layout(stack.lower, height: stackHeight).width)
    }

    /// What the stack and the trailing text add to a first line already `first` wide.
    func tailWidth(after first: Double) -> Double {
        var added = 0.0
        var width = first
        if let stack = label.stack {
            added += (width > 0 ? space : 0) + stackWidth(stack)
            width += added
        }
        if !label.trailing.isEmpty { added += (width > 0 ? space : 0) + DrawingText.layout(label.trailing, height: h).width }
        return added
    }

    mutating func add(_ string: String, x: Double, baseline: Double, height: Double) {
        texts.append(
            PlacedText(
                run: DrawingText.layout(string, height: height), original: label.hasTypedText ? label.plainText : string,
                origin: point(x, baseline), height: height, angle: angle))
    }

    /// Places one piece and returns how far it advances.
    mutating func place(_ piece: LabelPiece, x: Double, baseline: Double) -> Double {
        switch piece {
        case .text(let text):
            add(text, x: x, baseline: baseline, height: h)
            return DrawingText.layout(text, height: h).width
        case .symbol(let symbol):
            let box = DrawingSymbols.labelSymbolAdvance(h: h)
            let base = point(x + (box - h) / 2, baseline)
            for segment in DrawingSymbols.labelSymbol(symbol, origin: .zero, h: h) {
                segments.append(turned(segment, base: base))
            }
            return box
        }
    }

    /// The stack, then the trailing text, after the first line's pieces ending at `x`.
    mutating func placeTail(x start: Double, floor: Double, baseline: Double) {
        var x = start
        if let stack = label.stack {
            if x > floor { x += space }
            add(stack.upper, x: x, baseline: stackHeight * 0.1, height: stackHeight)
            add(stack.lower, x: x, baseline: -stackHeight * 1.1, height: stackHeight)
            x += stackWidth(stack)
        }
        if !label.trailing.isEmpty {
            if x > floor { x += space }
            add(label.trailing, x: x, baseline: baseline, height: h)
        }
    }

    private func turned(_ segment: SheetSegment, base: Vector2) -> SheetSegment {
        func map(_ p: Vector2) -> Vector2 { base + u * p.x + up * p.y }
        switch segment {
        case let .line(a, b): return .line(map(a), map(b))
        case let .polyline(points): return .polyline(points.map(map))
        default: return segment
        }
    }
}
