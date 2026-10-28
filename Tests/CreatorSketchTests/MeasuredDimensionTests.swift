import Foundation
import CreatorGeometry
import Testing
@testable import CreatorSketch

struct MeasuredDimensionTests {
    private let diagonal = 72.11102550927978

    /// A 60 × 40 rectangle with a fixed corner and horizontal/vertical sides; lengths optional.
    private func rectangle(withLengths: Bool) -> (sketch: Sketch, lines: [SketchEntityID], corners: [SketchEntityID]) {
        var sketch = Sketch()
        let lines = addPolygon(&sketch, [.zero, Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
        let corners = lines.map { sketch.ends($0).0 }
        sketch.add(.fix(corners[0], at: .zero))
        sketch.add(.horizontal(lines[0]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[3]))
        if withLengths {
            sketch.addDimension(.length(lines[0]), value: 60)
            sketch.addDimension(.length(lines[1]), value: 40)
        }
        return (sketch, lines, corners)
    }

    @Test func aFreeDiagonalDrives() throws {
        let fixture = rectangle(withLengths: false)
        let measured = try #require(fixture.sketch.measuredDimension(.distance(fixture.corners[0], fixture.corners[2])))
        #expect(isClose(measured.value, diagonal, tolerance: 1e-3))
        #expect(measured.isDriving)
    }

    @Test func aDiagonalOnAFullyDefinedRectangleIsAReference() throws {
        let fixture = rectangle(withLengths: true)
        let measured = try #require(fixture.sketch.measuredDimension(.distance(fixture.corners[0], fixture.corners[2])))
        #expect(isClose(measured.value, diagonal, tolerance: 1e-3))
        #expect(!measured.isDriving)
    }

    @Test func aRepeatedLengthIsAReference() throws {
        let fixture = rectangle(withLengths: true)
        let measured = try #require(fixture.sketch.measuredDimension(.length(fixture.lines[0])))
        #expect(isClose(measured.value, 60, tolerance: 1e-6))
        #expect(!measured.isDriving)
    }

    @Test func nothingToMeasureIsNil() {
        var sketch = Sketch()
        let first = sketch.addCircle(center: .zero, radius: 2)
        let second = sketch.addCircle(center: .zero, radius: 3)
        #expect(sketch.measuredDimension(.centreDistance(first, second)) == nil)

        var lines = Sketch()
        let long = lines.addLine(.zero, Vector2(10, 0))
        let point = lines.addPoint(Vector2(5, 0))
        let degenerate = lines.addLine(from: point, to: point)
        #expect(lines.measuredDimension(.lineDistance(long, degenerate)) == nil)
    }

    /// A fixed base line along +x and an arm from the origin drawn at `degrees`.
    private func vee(degrees: Double) -> (sketch: Sketch, base: SketchEntityID, arm: SketchEntityID) {
        var sketch = Sketch()
        let origin = sketch.addPoint(.zero)
        sketch.add(.fix(origin, at: .zero))
        let baseEnd = sketch.addPoint(Vector2(10, 0))
        sketch.add(.fix(baseEnd, at: Vector2(10, 0)))
        let base = sketch.addLine(from: origin, to: baseEnd)
        let radians = degrees * .pi / 180
        let arm = sketch.addLine(from: origin, to: sketch.addPoint(Vector2(cos(radians), sin(radians)) * 10))
        return (sketch, base, arm)
    }

    @Test func anObtuseAngleKeepsItsValue() throws {
        let fixture = vee(degrees: 120)
        let measured = try #require(fixture.sketch.measuredDimension(.angle(fixture.base, fixture.arm)))
        #expect(isClose(measured.value, 120, tolerance: 1e-6))
    }

    @Test func aNearZeroAngleIsNotNil() throws {
        let fixture = vee(degrees: 1e-6)
        let measured = try #require(fixture.sketch.measuredDimension(.angle(fixture.base, fixture.arm)))
        #expect(measured.value < 1e-4)
    }

    @Test func aRepeatedAngleIsAReference() throws {
        var fixture = vee(degrees: 120)
        fixture.sketch.addDimension(.angle(fixture.base, fixture.arm), value: 120)
        let measured = try #require(fixture.sketch.measuredDimension(.angle(fixture.base, fixture.arm)))
        #expect(isClose(measured.value, 120, tolerance: 1e-6))
        #expect(!measured.isDriving)
    }

    @Test func aFreeObtuseAngleDrives() throws {
        let fixture = vee(degrees: 120)
        let measured = try #require(fixture.sketch.measuredDimension(.angle(fixture.base, fixture.arm)))
        #expect(measured.isDriving)
    }
}
