import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Scale chooser")
struct ScaleChooserTests {
    private let area = DrawingArea.rect(for: DrawingSheet(name: "S"), standard: .iso)

    @Test func aSmallPartGetsAnEnlargement() {
        let scale = ScaleChooser.firstScale(extents: (10, 10, 10), area: area)
        #expect(scale == DrawingScale(numerator: 5, denominator: 1))
    }

    @Test func aLargePartGetsAReduction() {
        let scale = ScaleChooser.firstScale(extents: (300, 200, 100), area: area)
        #expect(scale == DrawingScale(numerator: 1, denominator: 2))
    }

    @Test func nothingFitsGivesTheSmallest() {
        let scale = ScaleChooser.firstScale(extents: (1e6, 1e6, 1e6), area: area)
        #expect(scale == DrawingScale(numerator: 1, denominator: 1000))
    }

    @Test func noBoundsGivesFullSize() {
        #expect(ScaleChooser.firstScale(extents: nil, area: area) == DrawingScale(numerator: 1, denominator: 1))
    }

    @Test func extentsUseTheEightCorners() {
        let box = BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 20, 30))
        let extents = ViewExtents.of(box, frame: StandardOrientation.front.frame)
        #expect(abs(extents.width - 10) < 1e-9 && abs(extents.height - 30) < 1e-9 && abs(extents.depth - 20) < 1e-9)
    }
}
