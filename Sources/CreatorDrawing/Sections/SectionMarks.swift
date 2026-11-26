import CreatorGeometry
import CreatorKernel

/// The marks a section, detail or auxiliary view puts on its parent, and a detail's boundary (R6), in sheet millimetres. Nothing here
/// uses `sin` or `cos`: directions come from the model plane's own vectors and `letterDiagonal`.
public enum SectionMarks {
    /// What marks add to a picture.
    public typealias Pieces = (strokes: [SheetStroke], fills: [SheetFill], texts: [SheetText])

    /// The cutting-plane line, its two arrows and their letters. `mapping` is the parent's.
    public static func cuttingLine(
        _ cutter: SectionCutter, letter: String, mapping: ViewMapping, parent: ViewID, mark: ViewID, standard: DrawingStandard
    ) -> Pieces {
        let marks = Maker(parent: parent, mark: mark, standard: standard)
        let points = cutter.points.map(mapping.sheet)
        guard points.count >= 2, let first = points.first, let last = points.last else { return ([], [], []) }
        var pieces: Pieces = (marks.chain(points), [], [])
        for end in [first, last] {
            marks.arrow(from: end, direction: cutter.viewing, letter: letter, into: &pieces)
        }
        return pieces
    }

    /// A detail's circle on its parent, with its letter at the diagonal.
    public static func detailCircle(
        _ circle: DetailCircle, letter: String, mapping: ViewMapping, parent: ViewID, mark: ViewID, standard: DrawingStandard
    ) -> Pieces {
        let marks = Maker(parent: parent, mark: mark, standard: standard)
        let center = mapping.sheet(circle.center)
        let radius = circle.radius * mapping.scale
        var pieces: Pieces = ([marks.circle(center: center, radius: radius)], [], [])
        let diagonal = SectionMarkStyle.of(standard).letterDiagonal
        let distance = radius + marks.marks.letterGap + marks.height / 2
        marks.letter(letter, at: center + diagonal * distance, into: &pieces)
        return pieces
    }

    /// An auxiliary view's arrow at the edge's midpoint, pointing the way the view looks, with its letter behind the tail.
    public static func auxiliaryArrow(
        _ arrow: AuxiliaryArrow, letter: String, mapping: ViewMapping, parent: ViewID, mark: ViewID, standard: DrawingStandard
    ) -> Pieces {
        let marks = Maker(parent: parent, mark: mark, standard: standard)
        let v = arrow.viewing
        let at = mapping.sheet(arrow.at)
        let tip = at - v * marks.marks.viewArrowGap
        let tail = at - v * (marks.marks.viewArrowGap + marks.marks.arrowShaft)
        var pieces: Pieces = ([marks.shaft(from: tail, to: tip)], [marks.head(tip: tip, back: v * -1)], [])
        marks.letter(letter, at: tail - v * (marks.marks.letterGap + marks.height / 2), into: &pieces)
        return pieces
    }

    /// A detail view's boundary: a thin solid circle round its centre (`center` and `radius` already in sheet millimetres).
    public static func detailBoundary(center: Vector2, radius: Double, view: ViewID, standard: DrawingStandard) -> Pieces {
        let marks = Maker(parent: view, mark: view, standard: standard)
        return ([marks.circle(center: center, radius: radius)], [], [])
    }

    /// The box a set of marks covers, letters included.
    static func bounds(of pieces: Pieces) -> Rect2D? {
        var points: [Vector2] = []
        for stroke in pieces.strokes {
            let box = stroke.bounds
            points += [box.min, box.max]
        }
        for fill in pieces.fills { points += fill.points }
        for text in pieces.texts {
            points += [text.origin, text.origin + Vector2(text.run.width, text.height)]
        }
        return Rect2D(points: points)
    }

    private struct Maker {
        let parent: ViewID
        let mark: ViewID
        let standard: DrawingStandard
        let drawing: DrawingStyle
        let marks: SectionMarkStyle
        let annotation: AnnotationStyle

        init(parent: ViewID, mark: ViewID, standard: DrawingStandard) {
            self.parent = parent
            self.mark = mark
            self.standard = standard
            drawing = .of(standard)
            marks = .of(standard)
            annotation = .of(standard)
        }

        var height: Double { drawing.viewLabelHeight }

        func stroke(_ segment: SheetSegment, width: Double, pattern: StrokePattern, layer: DrawingLayer) -> SheetStroke {
            SheetStroke(segments: [segment], width: width, pattern: pattern, layer: layer, view: parent, mark: mark)
        }

        func circle(center: Vector2, radius: Double) -> SheetStroke {
            stroke(
                .arc(center: center, radius: radius, start: 0, sweep: 2 * .pi), width: drawing.thin, pattern: .solid,
                layer: .dimension)
        }

        func shaft(from a: Vector2, to b: Vector2) -> SheetStroke {
            stroke(.line(a, b), width: drawing.thin, pattern: .solid, layer: .dimension)
        }

        /// A filled head with its tip at `tip`; `back` is the unit direction from the tip toward the base.
        func head(tip: Vector2, back: Vector2) -> SheetFill {
            let base = tip + back * annotation.arrowLength
            let side = Vector2(-back.y, back.x) * (annotation.arrowWidth / 2)
            return SheetFill(points: [tip, base + side, base - side], layer: .dimension, view: parent, mark: mark)
        }

        /// A shaft from `end` along `direction`, its head at the far end, and the letter beyond the tip.
        func arrow(from end: Vector2, direction: Vector2, letter text: String, into pieces: inout Pieces) {
            let tip = end + direction * marks.arrowShaft
            pieces.strokes.append(shaft(from: end, to: tip))
            pieces.fills.append(head(tip: tip, back: direction * -1))
            letter(text, at: tip + direction * (marks.letterGap + height / 2), into: &pieces)
        }

        /// A letter centred on `center`.
        func letter(_ text: String, at center: Vector2, into pieces: inout Pieces) {
            guard !text.isEmpty else { return }
            let run = DrawingText.layout(text, height: height)
            pieces.texts.append(
                SheetText(
                    run: run, original: text, origin: Vector2(center.x - run.width / 2, center.y - height / 2), height: height,
                    layer: .text, view: parent, mark: mark))
        }

        /// The chain: thick solid pieces at the ends and each step's corners (ISO), thin chain between them; one thick chain
        /// stroke for ASME. All on the centre layer.
        func chain(_ points: [Vector2]) -> [SheetStroke] {
            guard marks.thickEndLength > 0 || marks.thickCornerLength > 0 else {
                return [stroke(.polyline(points), width: marks.chainWidth, pattern: .centre, layer: .center)]
            }
            var result: [SheetStroke] = []
            var run: [Vector2] = []
            func flush() {
                guard run.count >= 2 else { return }
                let segment: SheetSegment = run.count == 2 ? .line(run[0], run[1]) : .polyline(run)
                result.append(stroke(segment, width: drawing.thick, pattern: .solid, layer: .center))
                run = []
            }
            let lastSegment = points.count - 2
            for k in 0...lastSegment {
                let (a, b) = (points[k], points[k + 1])
                let length = (b - a).length
                guard length > 0 else { continue }
                let direction = (b - a) * (1 / length)
                let lead = k == 0 ? marks.thickEndLength : marks.thickCornerLength
                let trail = k == lastSegment ? marks.thickEndLength : marks.thickCornerLength
                if lead + trail >= length {
                    if run.isEmpty { run = [a] }
                    run.append(b)
                } else {
                    if run.isEmpty { run = [a] }
                    if lead > 0 { run.append(a + direction * lead) }
                    flush()
                    let (from, to) = (a + direction * lead, b - direction * trail)
                    result.append(stroke(.line(from, to), width: marks.chainWidth, pattern: .centre, layer: .center))
                    run = [to, b]
                }
                if k == lastSegment { flush() }
            }
            return result
        }
    }
}
