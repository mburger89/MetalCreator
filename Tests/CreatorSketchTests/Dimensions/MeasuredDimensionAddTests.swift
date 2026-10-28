import CreatorGeometry
import Testing
@testable import CreatorSketch

/// `MeasuredDimension.add`: a dimension added at the value the geometry already has.
struct MeasuredDimensionAddTests {
    @Test func aFreeDistanceIsAddedDrivingAtItsMeasuredValue() throws {
        let plate = HoledPlate()
        let added = try #require(MeasuredDimension.add(.centreDistance(plate.c1, plate.c2),
                                                       measuredOn: plate.sketch, to: plate.sketch))
        #expect(isClose(added.value, 30, tolerance: 1e-6))
        #expect(added.isDriving)
        let dimension = try #require(added.sketch.dimensions[added.id])
        #expect(dimension.kind == .centreDistance(plate.c1, plate.c2))
        #expect(dimension.isDriving)
        #expect(dimension.labelPoint == nil)
        #expect(dimension.name == plate.sketch.nextDimensionName())
        #expect(isClose(dimension.value, added.value, tolerance: 0))
        let solution = SketchSolver.solve(added.sketch)
        for id in plate.sketch.entityIDs {
            guard let before = plate.sketch.position(of: id) else { continue }
            let after = try #require(solution.points[id])
            #expect(isClose(before, after, tolerance: 1e-9))
        }
    }

    @Test func anOverDefiningDimensionIsAddedAsAReference() throws {
        var plate = HoledPlate()
        plate.sketch.addDimension(.length(plate.lines[1]), value: 40)
        let added = try #require(MeasuredDimension.add(.lineDistance(plate.lines[0], plate.lines[2]),
                                                       measuredOn: plate.sketch, to: plate.sketch))
        #expect(!added.isDriving)
        #expect(isClose(added.value, 40, tolerance: 1e-6))
        #expect(added.sketch.dimensions[added.id]?.isDriving == false)
    }

    @Test func theValueComesFromTheEvaluatedSketch() throws {
        var plate = HoledPlate()
        let width = plate.sketch.addDimension(.length(plate.lines[0]), value: 60)
        let stored = plate.sketch
        var evaluated = stored
        evaluated.dimensions[width]?.value = 80
        evaluated.remember(SketchSolver.solve(evaluated))
        let added = try #require(MeasuredDimension.add(.lineDistance(plate.lines[1], plate.lines[3]),
                                                       measuredOn: evaluated, to: stored))
        #expect(isClose(added.value, 80, tolerance: 1e-6))
        #expect(isClose(try #require(added.sketch.dimensions[width]).value, 60, tolerance: 0))
        #expect(added.id == DimensionID(stored.nextID))
        #expect(added.sketch.dimensions[added.id] != nil)
        #expect(stored.dimensions[added.id] == nil)
    }

    @Test func anUnmeasurableKindAddsNothing() {
        var plate = HoledPlate()
        let suspended = plate.sketch.add(SketchEntity(.projected(
            ProjectionSource(reference: "gone", curve: .line(Vector2(0, 5), Vector2(60, 5)), isSuspended: true))))
        #expect(MeasuredDimension.add(.distance(plate.corners[0], suspended), measuredOn: plate.sketch, to: plate.sketch) == nil)
    }
}
