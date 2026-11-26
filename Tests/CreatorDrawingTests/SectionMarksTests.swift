import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Section marks")
struct SectionMarksTests {
    private let parent = ViewID()
    private let mark = ViewID()
    private let frame = StandardOrientation.front.frame
    private let identity = ViewMapping(scale: 1, offset: .zero)

    private var stepped: SectionCutter {
        SectionCutter(
            frame: frame, points: [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(40, 10)], viewing: Vector2(0, 1))
    }

    private func cutting(_ standard: DrawingStandard, cutter: SectionCutter? = nil) -> SectionMarks.Pieces {
        SectionMarks.cuttingLine(
            cutter ?? stepped, letter: "A", mapping: identity, parent: parent, mark: mark, standard: standard)
    }

    private func length(_ stroke: SheetStroke) -> Double {
        stroke.segments.reduce(0) { total, segment in
            switch segment {
            case let .line(a, b): total + (b - a).length
            case let .polyline(points): total + zip(points, points.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
            default: total
            }
        }
    }

    /// R6's constants, in sheet millimetres; a change to one is a change to every drawing's marks.
    @Test func theStylesConstantsArePinned() {
        let iso = SectionMarkStyle.of(.iso), asme = SectionMarkStyle.of(.asme)
        #expect(iso.chainWidth == 0.25 && iso.thickEndLength == 5 && iso.thickCornerLength == 3)
        #expect(iso.arrowShaft == 7 && iso.letterGap == 1 && iso.viewArrowGap == 2)
        #expect(asme.chainWidth == 0.6 && asme.thickEndLength == 0 && asme.thickCornerLength == 0)
        #expect(asme.arrowShaft == 8 && asme.letterGap == 1.5 && asme.viewArrowGap == 2)
        #expect(iso.letterDiagonal == Vector2((0.5).squareRoot(), (0.5).squareRoot()))
    }

    @Test func isoThickEndsAndCorners() {
        let pieces = cutting(.iso)
        let chain = pieces.strokes.filter { $0.layer == .center }
        let thick = chain.filter { $0.pattern == .solid }
        let thin = chain.filter { $0.pattern == .centre }
        #expect(thick.count == 4)
        #expect(thin.count == 3)
        #expect(thick.allSatisfy { $0.width == DrawingStyle.iso.thick })
        #expect(thin.allSatisfy { $0.width == DrawingStyle.iso.thin })
        // 5 at each end, 3 either side of each of the two corners.
        #expect(thick.map(length) == [5, 6, 6, 5])
        #expect(thin.map(length) == [12, 4, 12])
        #expect(thick[0].segments == [.line(Vector2(0, 0), Vector2(5, 0))])
        #expect(thick[1].segments == [.polyline([Vector2(17, 0), Vector2(20, 0), Vector2(20, 3)])])
    }

    @Test func aZeroLengthLastSegmentKeepsTheThickEnd() {
        // The line's last two points coincide: the end is still the previous segment's, thick for 5 mm, never lost or thin.
        let doubled = SectionCutter(
            frame: frame, points: [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(40, 10), Vector2(40, 10)],
            viewing: Vector2(0, 1))
        #expect(cutting(.iso, cutter: doubled).strokes == cutting(.iso).strokes)
        let leading = SectionCutter(
            frame: frame, points: [Vector2(0, 0), Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(40, 10)],
            viewing: Vector2(0, 1))
        #expect(cutting(.iso, cutter: leading).strokes == cutting(.iso).strokes)
    }

    @Test func asmeIsThickThroughout() {
        let chain = cutting(.asme).strokes.filter { $0.layer == .center }
        #expect(chain.count == 1)
        #expect(chain[0].pattern == .centre)
        #expect(chain[0].width == DrawingStyle.asme.thick)
        #expect(chain[0].segments == [.polyline(stepped.points)])
    }

    @Test func arrowsPointTheViewingWay() throws {
        let pieces = cutting(.iso)
        let shafts = pieces.strokes.filter { $0.layer == .dimension }
        #expect(shafts.map(\.segments) == [[.line(Vector2(0, 0), Vector2(0, 7))], [.line(Vector2(40, 10), Vector2(40, 17))]])
        #expect(shafts.allSatisfy { $0.width == DrawingStyle.iso.thin })
        #expect(pieces.fills.count == 2)
        let head = try #require(pieces.fills.first)
        #expect(head.points[0] == Vector2(0, 7))
        let base = head.points[1] - Vector2(0, 7)
        #expect(abs(base.y + AnnotationStyle.iso.arrowLength) < 1e-12, "the base lies the head's length behind the tip")
        let asme = cutting(.asme).strokes.filter { $0.layer == .dimension }
        #expect(asme.first?.segments == [.line(Vector2(0, 0), Vector2(0, 8))])
    }

    @Test func lettersBeyondTheArrows() throws {
        let pieces = cutting(.iso)
        #expect(pieces.texts.map(\.original) == ["A", "A"])
        let text = try #require(pieces.texts.first)
        let height = DrawingStyle.iso.viewLabelHeight
        #expect(text.height == height && height == 5)
        #expect(abs(text.origin.x + text.run.width / 2) < 1e-12)
        #expect(abs(text.origin.y + height / 2 - (7 + 1 + height / 2)) < 1e-12)
        #expect(text.layer == .text)
    }

    @Test func aDetailCircleAndLetter() throws {
        let mapping = ViewMapping(scale: 2, offset: Vector2(100, 50))
        let circle = DetailCircle(parent: parent, center: Vector2(10, 10), radius: 5)
        let pieces = SectionMarks.detailCircle(
            circle, letter: "B", mapping: mapping, parent: parent, mark: mark, standard: .iso)
        let stroke = try #require(pieces.strokes.first)
        #expect(stroke.segments == [.arc(center: Vector2(120, 70), radius: 10, start: 0, sweep: 2 * .pi)])
        #expect(stroke.layer == .dimension && stroke.pattern == .solid && stroke.width == DrawingStyle.iso.thin)
        let diagonal = (0.5).squareRoot()
        #expect(SectionMarkStyle.of(.iso).letterDiagonal == Vector2(diagonal, diagonal))
        let distance = 10.0 + 1.0 + DrawingStyle.iso.viewLabelHeight / 2
        let text = try #require(pieces.texts.first)
        let centre = Vector2(text.origin.x + text.run.width / 2, text.origin.y + text.height / 2)
        #expect((centre - (Vector2(120, 70) + Vector2(diagonal, diagonal) * distance)).length < 1e-9)
    }

    @Test func anAuxiliaryArrowPointsAtTheEdge() throws {
        let arrow = AuxiliaryArrow(parent: parent, parentFrame: frame, at: Vector2(30, 20), viewing: Vector2(0, 1))
        let pieces = SectionMarks.auxiliaryArrow(
            arrow, letter: "C", mapping: identity, parent: parent, mark: mark, standard: .iso)
        let shaft = try #require(pieces.strokes.first)
        #expect(shaft.segments == [.line(Vector2(30, 11), Vector2(30, 18))], "the tip stops 2 mm short of the edge")
        #expect(pieces.fills.first?.points.first == Vector2(30, 18))
        let text = try #require(pieces.texts.first)
        #expect(abs(text.origin.y + text.height / 2 - (11 - 1 - 2.5)) < 1e-12, "behind the tail")
    }

    @Test func aDetailBoundaryIsACircleOnTheDetail() throws {
        let pieces = SectionMarks.detailBoundary(center: Vector2(150, 100), radius: 25, view: mark, standard: .iso)
        let stroke = try #require(pieces.strokes.first)
        #expect(stroke.segments == [.arc(center: Vector2(150, 100), radius: 25, start: 0, sweep: 2 * .pi)])
        #expect(stroke.view == mark && stroke.mark == mark && stroke.layer == .dimension)
        #expect(pieces.fills.isEmpty && pieces.texts.isEmpty)
    }

    @Test func everythingCarriesItsMark() {
        let arrow = AuxiliaryArrow(parent: parent, parentFrame: frame, at: Vector2(30, 20), viewing: Vector2(0, 1))
        let circle = DetailCircle(parent: parent, center: .zero, radius: 4)
        for standard in [DrawingStandard.iso, .asme] {
            let all = [
                cutting(standard),
                SectionMarks.auxiliaryArrow(
                    arrow, letter: "C", mapping: identity, parent: parent, mark: mark, standard: standard),
                SectionMarks.detailCircle(
                    circle, letter: "B", mapping: identity, parent: parent, mark: mark, standard: standard),
            ]
            for pieces in all {
                #expect(pieces.strokes.allSatisfy { $0.view == parent && $0.mark == mark })
                #expect(pieces.fills.allSatisfy { $0.view == parent && $0.mark == mark })
                #expect(pieces.texts.allSatisfy { $0.view == parent && $0.mark == mark })
            }
        }
    }
}
