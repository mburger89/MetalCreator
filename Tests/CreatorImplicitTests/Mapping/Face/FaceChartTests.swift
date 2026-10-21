import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorImplicit

/// The grid, the assembler and the analysis of a face chart (implicit spec §3.5, Face mapping), on surfaces written as formulas.
struct FaceChartTests {
    // MARK: Grid

    @Test func aGridIsWholeBlocksCoveringTheBoxWithinTheSampleBudget() {
        let box = BoundingBox(min: Vector3(-10, 0, 5), max: Vector3(20, 17, 9))
        let grid = FaceChartGrid(covering: box, spacing: 1)
        #expect(grid.counts.allSatisfy { $0 % 8 == 0 } && grid.sampleCount <= FaceChartGrid.maximumSamples)
        #expect(grid.spacing == 1 && grid.origin == box.min)
        let last = grid.bounds.max
        #expect(last.x >= box.max.x - 1e-9 && last.y >= box.max.y - 1e-9 && last.z >= box.max.z - 1e-9)
        #expect(grid.points.count == grid.sampleCount && grid.points[0] == box.min)
        #expect(grid.points[1] == box.min + Vector3(1, 0, 0), "x runs fastest")
    }

    @Test func aBigBoxIsMeasuredMoreCoarsely() {
        let grid = FaceChartGrid(covering: BoundingBox(min: .zero, max: Vector3(400, 400, 400)), spacing: 0.4)
        #expect(grid.sampleCount <= FaceChartGrid.maximumSamples && grid.spacing > 0.4)
        #expect(grid.bounds.max.x >= 400 - 1e-9)
    }

    @Test func blocksReadBackTheSamplesTheyWereMadeFrom() {
        let grid = FaceChartGrid(covering: BoundingBox(min: Vector3(1, 2, 3), max: Vector3(20, 18, 14)), spacing: 1)
        let values = grid.points.map { Float($0.x * 2 - $0.y + 0.5 * $0.z) }
        let blocks = grid.blocks(values, lipschitz: 1)
        for index in stride(from: 0, to: values.count, by: 97) {
            let point = grid.points[index]
            #expect(abs(blocks.channelValue(at: point) - Double(values[index])) < 1e-4, "\(point)")
        }
        // Between samples the value is trilinear, which is exact for a linear function.
        let between = Vector3(7.3, 9.9, 6.1)
        #expect(abs(blocks.channelValue(at: between) - (2 * 7.3 - 9.9 + 0.5 * 6.1)) < 1e-4)
        // Outside the grid the value is the one at its edge: nothing is added for the distance.
        #expect(abs(blocks.channelValue(at: Vector3(1 - 50, 2, 3)) - blocks.channelValue(at: Vector3(1, 2, 3))) < 1e-9)
        #expect(blocks.value(at: Vector3(1 - 50, 2, 3)) > blocks.channelValue(at: Vector3(1 - 50, 2, 3)) + 40, "a distance adds it")
    }

    // MARK: Assembler

    @Test func aPlaneHasNoPeriodNoSingularCellAndMillimetreSlopes() {
        let chart = SyntheticFace.plane(height: 2)
        #expect(chart.firstTurn == nil && chart.secondTurn == nil && chart.singular == nil && !chart.hasSingular)
        #expect(abs(chart.firstSlope - 1) < 1e-3 && abs(chart.secondSlope - 1) < 1e-3 && abs(chart.depthSlope - 1) < 1e-3)
        #expect(chart.firstSine == nil && chart.secondSine == nil && chart.singularPoints.isEmpty)
        let map = FaceMap(chart: chart, firstCell: nil, secondCell: nil)
        let c = map.coordinates(at: Vector3(3.3, -4.4, 7))
        #expect(abs(c.x - 3.3) < 1e-4 && abs(c.y + 4.4) < 1e-4 && abs(c.z - 5) < 1e-4, "\(c)")
        #expect(map.stretch >= 1 && map.stretch < 2, "three unit slopes make √3")
        #expect(map.singularDistance(at: .zero) == .infinity && map.turns.first == nil)
    }

    @Test func aCylindersSideIsAnAngleAHeightAndADepth() throws {
        let chart = SyntheticFace.cylinder(radius: 14)
        let map = FaceMap(chart: chart, firstCell: nil, secondCell: nil)
        let turn = try #require(chart.firstTurn)
        #expect(abs(turn - 2 * Double.pi * 14) < 1e-9 && chart.secondTurn == nil)
        #expect(chart.firstSine != nil && chart.secondSine == nil)
        for (radius, degrees, z) in [(10.0, 30.0, 3.0), (16.0, 200.0, -7), (12.0, 359.0, 0), (13.0, 181.0, 5)] {
            let angle = degrees * .pi / 180
            let c = map.coordinates(at: Vector3(radius * cos(angle), radius * sin(angle), z))
            // The angle is measured from the middle of u (π), and the length of a radian is the cylinder's 14 mm.
            #expect(abs(c.x - (angle - Double.pi) * 14) < 0.05, "angle at \(degrees)°: \(c.x) against \((angle - Double.pi) * 14)")
            #expect(abs(c.y - z) < 1e-3 && abs(c.z - (radius - 14)) < 0.02, "\(c)")
        }
    }

    @Test func theCellsNextToTheAxisAreSingularAndTheRestAreNot() throws {
        let chart = SyntheticFace.cylinder(radius: 14)
        #expect(chart.hasSingular && chart.singularNoun == "the cylinder's axis")
        let map = FaceMap(chart: chart, firstCell: nil, secondCell: nil)
        #expect(map.singularDistance(at: Vector3(0, 0, 3)) < LatticeMapping.exclusion, "the axis is inside the exclusion")
        #expect(map.singularDistance(at: Vector3(9, 0, 3)) == FaceChart.singularCap, "far from it the distance is held to the cap")
        #expect(map.singularDistance(at: Vector3(6, 0, 3)) > 3, "and grows with the distance from the cells next to the axis")
        let near = chart.singularPoints
        let limit = FaceChartAssembler.maximumSingularPoints
        #expect(!near.isEmpty && near.count <= limit && near.allSatisfy { Vector3($0.x, $0.y, 0).length < 2 })
        // 14 mm over 25 (the limit) is 0.56 mm: only the cells that touch the axis stretch that far.
        #expect(map.stretch > 5 && map.stretch < 40, "stretch \(map.stretch)")
    }

    @Test func aSmallBoxAroundOnlyAFewSingularCellsStillFindsThem() {
        let chart = SyntheticFace.cylinder(radius: 14)
        let mapping = LatticeMapping.face(FaceMap(chart: chart, firstCell: nil, secondCell: nil))
        let box = BoundingBox(min: Vector3(-0.5, -0.5, 2), max: Vector3(0.5, 0.5, 3))
        #expect(!mapping.singularSamples(in: box).isEmpty, "a 1 mm box on the axis holds singular cells")
        let away = BoundingBox(min: Vector3(8, 8, 2), max: Vector3(9, 9, 3))
        #expect(mapping.singularSamples(in: away).isEmpty)
    }

    @Test func aSteeperSurfaceHasMoreSingularCellsAndAPlaneHasNone() {
        let tight = SyntheticFace.cylinder(radius: 40)
        let wide = SyntheticFace.cylinder(radius: 14)
        let tightMap = FaceMap(chart: tight, firstCell: nil, secondCell: nil)
        let wideMap = FaceMap(chart: wide, firstCell: nil, secondCell: nil)
        #expect(tightMap.singularDistance(at: Vector3(2.5, 0, 0)) < wideMap.singularDistance(at: Vector3(2.5, 0, 0)),
                "a radius of 40 mm stretches 25× out to 1.6 mm from the axis")
    }

    @Test func theTurnIsRoundedToWholeCellsLikeTheCylindricalMappings() throws {
        let chart = SyntheticFace.cylinder(radius: 14)
        let map = FaceMap(chart: chart, firstCell: 8, secondCell: 8)
        let cells = try #require(map.turns.first) / 8
        #expect(abs(cells - cells.rounded()) < 1e-9 && cells >= 1, "\(cells) cells go round")
        #expect(abs((map.firstRadius ?? 0) - LatticeMapping.turnRadius(mean: 14, cell: 8)) < 1e-12)
        #expect(map.secondRadius == nil)
        #expect(LatticeMapping.face(map).periods.first == map.turns.first)
    }

    // MARK: A face is a mapping like the others

    @Test func theMappingSaysWhatTheChartSays() {
        let cylinder = LatticeMapping.face(FaceMap(chart: SyntheticFace.cylinder(), firstCell: nil, secondCell: nil))
        #expect(cylinder.reachesSingularity && cylinder.singularNoun == "the cylinder's axis" && cylinder.stretch > 1)
        let plane = LatticeMapping.face(FaceMap(chart: SyntheticFace.plane(), firstCell: nil, secondCell: nil))
        #expect(!plane.reachesSingularity && plane.singularNoun == nil && plane.singularSamples(in: SyntheticFace.bounds).isEmpty)
        #expect(plane.cutSamples(in: SyntheticFace.bounds).isEmpty)
        #expect(!cylinder.singularSamples(in: SyntheticFace.bounds).isEmpty)
        #expect(cylinder.lipschitz(base: 10, valueBound: 5) > 10 + 1 + 10, "the blend adds its slope")
        #expect(plane.lipschitz(base: 10, valueBound: 5) == 10)
        #expect(plane.reach(straight: 0) > 0)
    }
}
