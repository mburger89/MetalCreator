import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Hatch pattern")
struct HatchPatternTests {
    private let view = ViewID()
    private let mapping = ViewMapping(scale: 1, offset: Vector2(100, 100))
    private let spacing = 2.5

    private func rectangle(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Vector2] {
        [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
    }

    private func strokes(
        _ regions: [HatchRegion], mapping: ViewMapping? = nil, clips: [HatchClip] = []
    ) -> [SheetStroke] {
        HatchPattern.strokes(regions, mapping: mapping ?? self.mapping, clips: clips, spacing: spacing, width: 0.25, view: view)
    }

    private func ends(_ stroke: SheetStroke) -> [Vector2] {
        stroke.segments.flatMap { segment -> [Vector2] in
            if case .line(let a, let b) = segment { return [a, b] }
            return []
        }
    }

    private var plate: HatchRegion { HatchRegion(part: 0, edges: [rectangle(0, 0, 40, 20)], band: nil) }

    @Test func linesAreAt45Degrees() {
        let all = strokes([plate])
        #expect(!all.isEmpty)
        let h = (0.5).squareRoot()
        for stroke in all {
            let e = ends(stroke)
            let d = e[1] - e[0]
            #expect(abs(d.x / d.length - h) < 1e-9 && abs(d.y / d.length - h) < 1e-9)
        }
    }

    @Test func phaseFollowsTheSheet() {
        let moved = ViewMapping(scale: 1, offset: Vector2(100.7, 100))
        let normal = Vector2(-(0.5).squareRoot(), (0.5).squareRoot())
        for stroke in strokes([plate], mapping: moved) {
            let p = ends(stroke)[0]
            let value = (normal.x * p.x + normal.y * p.y) / spacing
            #expect(abs(value - value.rounded()) < 1e-9)
        }
    }

    @Test func aHoleIsLeftEmpty() {
        let region = HatchRegion(part: 0, edges: [rectangle(0, 0, 40, 20), rectangle(15, 5, 25, 15)], band: nil)
        for stroke in strokes([region]) {
            for p in ends(stroke) {
                let inside = p.x > 115 + 1e-9 && p.x < 125 - 1e-9 && p.y > 105 + 1e-9 && p.y < 115 - 1e-9
                #expect(!inside)
            }
            let e = ends(stroke)
            let mid = (e[0] + e[1]) * 0.5
            #expect(!(mid.x > 115 && mid.x < 125 && mid.y > 105 && mid.y < 115))
        }
    }

    @Test func loopsInAnyOrder() {
        let outer = rectangle(0, 0, 40, 20), hole = rectangle(15, 5, 25, 15)
        let a = strokes([HatchRegion(part: 0, edges: [outer, hole], band: nil)])
        let b = strokes([HatchRegion(part: 0, edges: [hole, outer], band: nil)])
        #expect(a == b)
    }

    @Test func aBandCutsTheLines() {
        let region = HatchRegion(part: 0, edges: [rectangle(0, 0, 40, 20)], band: HatchBand(axis: .horizontal, low: nil, high: 20))
        let all = strokes([region])
        #expect(!all.isEmpty)
        for stroke in all { for p in ends(stroke) { #expect(p.x <= 120 + 1e-9) } }
        #expect(all.contains { stroke in ends(stroke).contains { abs($0.x - 120) < 1e-9 } })
    }

    @Test func aClipStopsAtTheCircle() {
        let clip = HatchClip(center: Vector2(20, 10), radius: 6)
        let all = strokes([plate], clips: [clip])
        #expect(!all.isEmpty)
        for stroke in all { for p in ends(stroke) { #expect((p - Vector2(120, 110)).length <= 6 + 1e-9) } }
    }

    @Test func everyClipStops() {
        let first = HatchClip(center: Vector2(20, 10), radius: 6)
        let second = HatchClip(center: Vector2(26, 10), radius: 6)
        let all = strokes([plate], clips: [first, second])
        #expect(!all.isEmpty)
        for stroke in all {
            for p in ends(stroke) {
                #expect((p - Vector2(120, 110)).length <= 6 + 1e-9)
                #expect((p - Vector2(126, 110)).length <= 6 + 1e-9)
            }
        }
    }

    @Test func eachSolidHasItsOwnAngle() {
        let h = (0.5).squareRoot(), r = (3.0).squareRoot() / 2
        let expected = [
            Vector2(h, h), Vector2(-h, h), Vector2(r, 0.5), Vector2(-0.5, r), Vector2(0.5, r), Vector2(-r, 0.5), Vector2(h, h),
        ]
        for part in 0...6 { #expect(HatchPattern.direction(forPart: part) == expected[part]) }
    }

    @Test func directionsAreExactConstants() {
        let h = (0.5).squareRoot(), r = (3.0).squareRoot() / 2
        let allowed: Set<Double> = [h, -h, r, -r, 0.5, -0.5]
        for part in 0..<6 {
            let d = HatchPattern.direction(forPart: part)
            #expect(allowed.contains(d.x) && allowed.contains(d.y))
            #expect(abs(d.length - 1) < 1e-15)
        }
    }

    @Test func aThinRegionGetsOneLine() {
        let n = Vector2(-(0.5).squareRoot(), (0.5).squareRoot())
        // Place the centre c so that n . c = 1.25 (mod 2.5): the square's extent across the lines lies between two lines.
        let centre = Vector2(10, (1.25 - 10 * n.x) / n.y)
        let across = n.x * centre.x + n.y * centre.y
        #expect(abs(across - 1.25) < 1e-9)
        let region = HatchRegion(
            part: 0, edges: [rectangle(centre.x - 0.5, centre.y - 0.5, centre.x + 0.5, centre.y + 0.5)], band: nil)
        let all = strokes([region], mapping: ViewMapping(scale: 1, offset: .zero))
        #expect(all.count == 1)
        let e = ends(all[0])
        let mid = (e[0] + e[1]) * 0.5
        #expect((mid - centre).length < 1e-9)
        #expect(abs((e[1] - e[0]).length - 2.0.squareRoot()) < 1e-6)
        for p in e { #expect(abs(p.x - centre.x) <= 0.5 + 1e-9 && abs(p.y - centre.y) <= 0.5 + 1e-9) }
    }

    /// A point at `across` (n . p) and `along` (d . p) of the part-0 family, in sheet millimetres.
    private func point(across: Double, along: Double) -> Vector2 {
        let h = (0.5).squareRoot()
        return Vector2(-h * across + h * along, h * across + h * along)
    }

    @Test func aSliverInsideAStepsBandIsHatched() throws {
        // A diagonal strip across 0.5...1.5 (no line of the 2.5 grid) with a tab reaching across 3.0 far along it. The tab holds the
        // line at 2.5, but the band ends before the tab, so the piece that is drawn has no line of its own.
        let loop = [
            point(across: 0.5, along: 0), point(across: 1.5, along: 0), point(across: 1.5, along: 30), point(across: 3.0, along: 30),
            point(across: 3.0, along: 40), point(across: 0.5, along: 40),
        ]
        let band = HatchBand(axis: .horizontal, low: nil, high: 0.5.squareRoot() * 25)
        let region = HatchRegion(part: 0, edges: [loop], band: band)
        let all = strokes([region], mapping: ViewMapping(scale: 1, offset: .zero))
        #expect(all.count == 1)
        let e = ends(try #require(all.first))
        let h = (0.5).squareRoot()
        #expect(abs((-h * e[0].x + h * e[0].y) - 1.0) < 1e-9)
        for p in e { #expect(p.x <= band.high! + 1e-9) }
    }

    @Test func anExtentThatOnlyTouchesALineIsHatched() throws {
        // The edge from (0, 0) to (10, 10) lies exactly on the grid line n . x = 0 and the rest of the triangle on one side of it.
        let triangle = [Vector2(0, 0), Vector2(10, 10), Vector2(10, 8)]
        let all = strokes([HatchRegion(part: 0, edges: [triangle], band: nil)], mapping: ViewMapping(scale: 1, offset: .zero))
        #expect(all.count == 1)
        let e = ends(try #require(all.first))
        let h = (0.5).squareRoot()
        #expect(abs((-h * e[0].x + h * e[0].y) + 2.0.squareRoot() / 2) < 1e-9)
    }

    @Test func strokesAreThinOnTheHatchLayer() {
        for stroke in strokes([plate]) {
            #expect(stroke.layer == .hatch && stroke.width == 0.25 && stroke.source == nil && stroke.view == view)
            #expect(stroke.pattern == .solid && stroke.annotation == nil)
        }
    }

    @Test func orderIsFixed() {
        #expect(strokes([plate]) == strokes([plate]))
    }

    @Test func bandsFollowTheLinesEnds() {
        let top = StandardOrientation.top.frame
        func bands(_ points: [Vector2]) -> [HatchBand] {
            HatchBand.bands(for: SectionCutter(frame: top, points: points, viewing: Vector2(0, -1)))
        }
        let leftToRight = bands([Vector2(-5, 5), Vector2(20, 5), Vector2(20, 15), Vector2(45, 15)])
        #expect(leftToRight.count == 2)
        #expect(leftToRight[0].low == nil && leftToRight[0].high == 20 && leftToRight[0].axis == .horizontal)
        #expect(leftToRight[1].low == 20 && leftToRight[1].high == nil)
        let rightToLeft = bands([Vector2(45, 15), Vector2(20, 15), Vector2(20, 5), Vector2(-5, 5)])
        #expect(rightToLeft.count == 2)
        #expect(rightToLeft[0].low == 20 && rightToLeft[0].high == nil)
        #expect(rightToLeft[1].low == nil && rightToLeft[1].high == 20)
        let straight = bands([Vector2(0, 0), Vector2(30, 0)])
        #expect(straight.count == 1 && straight[0].low == nil && straight[0].high == nil)
        let region = { (band: HatchBand) in HatchRegion(part: 0, edges: [self.rectangle(0, 0, 40, 20)], band: band) }
        let covered = strokes(rightToLeft.map(region))
        let xs = covered.flatMap(ends).map(\.x)
        #expect(xs.min().map { $0 <= 100 + 1e-9 } == true)
        #expect(xs.max().map { $0 >= 140 - 1e-9 } == true)
    }
}
