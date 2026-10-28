import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorNodes

struct DimensionSpecsTests {
    let geometry = DimensionGeometry.linear(from: .zero, to: .unitX, direction: .unitX, side: .unitY, placement: .standoff)

    @Test func planeBoundsCoverTheOuterLoopOnly() {
        let profile = Profile2D(plane: .xy,
                                outer: Profile2D.rectangle(width: 20, height: 10, plane: .xy).outer,
                                holes: [Profile2D.rectangle(width: 100, height: 100, plane: .xy).outer])
        let bounds = DimensionSpecs.planeBounds(of: profile)
        #expect(bounds?.min == Vector2(-10, -5) && bounds?.max == Vector2(10, 5))
        #expect(DimensionSpecs.planeBounds(of: Profile2D(plane: .xy, segments: [])) == nil)
    }

    @Test func perpendicularIsUnitAndStable() throws {
        for direction in [Vector3.unitX, .unitY, .unitZ, Vector3(1, 1, 1)] {
            let result = DimensionSpecs.perpendicular(to: direction)
            #expect(abs(result.length - 1) < 1e-9 && abs(result.dot(direction)) < 1e-9)
        }
        #expect(DimensionSpecs.perpendicular(to: .unitX) == -.unitY)
    }

    @Test func equalValuesCollapseToOneSpecWithACount() {
        let specs = DimensionSpecs.repeated(.input("d"), .length, values: [5, 5, 5]) { _ in geometry }
        #expect(specs.count == 1 && specs[0].count == 3 && specs[0].value == 5)
    }

    @Test func differingValuesGetOneSpecEachUpToTheLimit() {
        let values = (0..<40).map(Double.init)
        let specs = DimensionSpecs.repeated(.input("d"), .length, values: values) { _ in geometry }
        #expect(specs.count == DimensionSpecs.instanceLimit)
        #expect(specs.map(\.value) == Array(values.prefix(DimensionSpecs.instanceLimit)))
        #expect(specs.allSatisfy { $0.count == nil })
    }

    @Test func aSingleInstanceHasNoCountAndNoInstancesNoSpecs() {
        #expect(DimensionSpecs.repeated(.input("d"), .length, values: [4]) { _ in geometry }.first?.count == nil)
        #expect(DimensionSpecs.repeated(.input("d"), .length, values: []) { _ in geometry }.isEmpty)
    }
}
