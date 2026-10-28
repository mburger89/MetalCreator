import Foundation
import CreatorGeometry
import Testing
@testable import CreatorSketch

/// `ModelDimensionKind.between`: the dimension two picked entities give.
struct ModelDimensionKindTests {
    @Test func twoCirclesGiveCentreToCentre() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.c1, plate.c2, in: plate.sketch) == .centreDistance(plate.c1, plate.c2))
    }

    @Test func aCircleAndAPointGiveCentreToCentre() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.c1, plate.corners[0], in: plate.sketch)
                == .centreDistance(plate.c1, plate.corners[0]))
    }

    @Test func parallelLinesGiveEdgeToEdge() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.lines[0], plate.lines[2], in: plate.sketch)
                == .lineDistance(plate.lines[0], plate.lines[2]))
    }

    @Test func crossingLinesGiveAnAngle() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.lines[0], plate.lines[1], in: plate.sketch)
                == .angle(plate.lines[0], plate.lines[1]))
    }

    @Test func linesJustOverHalfADegreeApartGiveAnAngle() {
        var sketch = Sketch()
        let first = sketch.addLine(.zero, Vector2(100, 0))
        let nearly = sketch.addLine(Vector2(0, 10), Vector2(100, 10 + 100 * tan(0.6 * .pi / 180)))
        let almost = sketch.addLine(Vector2(0, 20), Vector2(100, 20 + 100 * tan(0.4 * .pi / 180)))
        #expect(ModelDimensionKind.between(first, nearly, in: sketch) == .angle(first, nearly))
        #expect(ModelDimensionKind.between(first, almost, in: sketch) == .lineDistance(first, almost))
    }

    @Test func aPointAndALineGivePointToLine() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.corners[1], plate.lines[3], in: plate.sketch)
                == .distance(plate.corners[1], plate.lines[3]))
        #expect(ModelDimensionKind.between(plate.lines[3], plate.corners[1], in: plate.sketch)
                == .distance(plate.corners[1], plate.lines[3]))
    }

    @Test func aCircleAndALineMeasureFromTheCentre() {
        let plate = HoledPlate()
        let centre = plate.sketch.centerOf(plate.c1)
        #expect(ModelDimensionKind.between(plate.c1, plate.lines[3], in: plate.sketch) == .distance(centre, plate.lines[3]))
        #expect(ModelDimensionKind.between(plate.lines[3], plate.c1, in: plate.sketch) == .distance(centre, plate.lines[3]))
    }

    @Test func twoPointsGiveTheirDistance() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.corners[0], plate.corners[2], in: plate.sketch)
                == .distance(plate.corners[0], plate.corners[2]))
    }

    @Test func theSameEntityTwiceGivesNothing() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.c1, plate.c1, in: plate.sketch) == nil)
        #expect(ModelDimensionKind.between(plate.lines[0], plate.lines[0], in: plate.sketch) == nil)
    }

    @Test func anEntityThatIsGoneGivesNothing() {
        let plate = HoledPlate()
        #expect(ModelDimensionKind.between(plate.c1, SketchEntityID(9999), in: plate.sketch) == nil)
    }

    @Test func projectedCurvesCountAsTheirKind() {
        var plate = HoledPlate()
        let line = plate.sketch.add(SketchEntity(.projected(
            ProjectionSource(reference: "e1", curve: .line(Vector2(0, 5), Vector2(60, 5))))))
        let circle = plate.sketch.add(SketchEntity(.projected(
            ProjectionSource(reference: "e2", curve: .circle(center: Vector2(30, 20), radius: 3)))))
        #expect(ModelDimensionKind.between(plate.lines[0], line, in: plate.sketch) == .lineDistance(plate.lines[0], line))
        #expect(ModelDimensionKind.between(plate.lines[1], line, in: plate.sketch) == .angle(plate.lines[1], line))
        #expect(ModelDimensionKind.between(plate.c1, circle, in: plate.sketch) == .centreDistance(plate.c1, circle))
        #expect(ModelDimensionKind.between(plate.corners[0], circle, in: plate.sketch) == .centreDistance(plate.corners[0], circle))
        // A projected circle has no centre point to measure from.
        #expect(ModelDimensionKind.between(circle, plate.lines[0], in: plate.sketch) == nil)
        #expect(ModelDimensionKind.between(plate.lines[0], circle, in: plate.sketch) == nil)
    }
}
