import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The coarse grid and the flood fill behind Check Trapped Volumes and Drain Holes (implicit spec §4.6).
struct OccupancyGridTests {
    @Test func theCellIsHalfAMillimetreOrAThirtySecondOfTheLongestSideWhicheverIsFiner() {
        #expect(OccupancyGrid.cellSize(forSize: Vector3(10, 10, 10)) == 10.0 / 32)
        #expect(OccupancyGrid.cellSize(forSize: Vector3(16, 3, 3)) == 0.5)
        #expect(OccupancyGrid.cellSize(forSize: Vector3(100, 100, 100)) == 0.5)
        #expect(OccupancyGrid.cellSize(forSize: Vector3(150, 150, 150)) == 0.5, "a 150 mm cube still has 0.5 mm cells")
    }

    @Test func aLargePartGetsCoarserCellsOnlyAsFarAsTheCellBudgetNeeds() {
        // A plate a metre square and 10 mm thick has 80 million 0.5 mm cells, so its cell grows a little; a metre cube's grows a lot.
        let middling = OccupancyGrid.cellSize(forSize: Vector3(300, 300, 300))
        #expect(middling > 0.5 && middling < 1.1, "\(middling)")
        let plate = OccupancyGrid.cellSize(forSize: Vector3(1_000, 1_000, 10))
        #expect(plate > 0.5 && plate < 1, "\(plate)")
        let cube = OccupancyGrid.cellSize(forSize: Vector3(1_000, 1_000, 1_000))
        #expect(cube > 2.5 && cube < 4, "\(cube)")
        for size in [Vector3(1_000, 1_000, 10), Vector3(1_000, 1_000, 1_000), Vector3(5_000, 20, 20)] {
            let grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: size))
            #expect(grid.counts.x * grid.counts.y * grid.counts.z <= OccupancyGrid.largestCellCount, "\(size)")
        }
        #expect(OccupancyGrid.cellSize(forSize: Vector3(0, 0, 0)) > 0, "a point has a cell")
    }

    @Test func aHoleIsSeenFromFourCellsAcrossWhichIsTwoMillimetresExceptInAHugePart() {
        #expect(OccupancyGrid.smallestSeenHole(forSize: Vector3(100, 80, 40)) == 2)
        #expect(OccupancyGrid.smallestSeenHole(forSize: Vector3(10, 10, 10)) == 4 * 10.0 / 32)
        #expect(OccupancyGrid.smallestSeenHole(forSize: Vector3(1_000, 1_000, 1_000)) > 2, "the limit of the grid, which the check says")
    }

    @Test func theGridHasTwoCellsOfPaddingAndIndexesRoundTrip() {
        let grid = OccupancyGrid(bounds: BoundingBox(min: Vector3(0, 0, 0), max: Vector3(10, 20, 30)))
        #expect(grid.cell == 0.5)
        #expect(grid.counts == SIMD3(24, 44, 64), "20, 40 and 60 cells and two of padding either side")
        let index = grid.index(3, 4, 5)
        #expect(grid.coordinates(of: index) == SIMD3(3, 4, 5))
        let centre = grid.center(of: index)
        #expect(grid.index(containing: centre) == index)
        #expect(grid.index(containing: Vector3(-100, 0, 0)) == nil && grid.index(containing: Vector3(.nan, 0, 0)) == nil)
    }

    /// A grid with a solid shell of one cell round a block of empty cells, and a second block in the open.
    func shell(openAt hole: Int? = nil) -> OccupancyGrid {
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
        for k in 4..<14 {
            for j in 4..<14 {
                for i in 4..<14 {
                    let onShell = [i, j, k].contains { $0 == 4 || $0 == 13 }
                    grid.setSolid(onShell, at: grid.index(i, j, k))
                }
            }
        }
        if let hole { grid.setSolid(false, at: hole) }
        return grid
    }

    @Test func anEmptyBlockInsideASolidShellIsAVoid() throws {
        let grid = shell()
        let found = try EnclosedVoids(grid)
        #expect(found.voids.count == 1 && found.voids[0].count == 8 * 8 * 8)
        #expect(found.label[grid.index(8, 8, 8)] == 0 && found.label[grid.index(0, 0, 0)] == -1)
    }

    @Test func aHoleInTheShellLetsTheOutsideIn() throws {
        #expect(try EnclosedVoids(shell(openAt: shell().index(8, 8, 13))).voids.isEmpty)
    }

    @Test func aSingleEmptyCellIsNotAVoid() throws {
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
        for index in 0..<grid.cellCount { grid.setSolid(true, at: index) }
        grid.setSolid(false, at: grid.index(8, 8, 8))
        grid.setSolid(false, at: grid.index(0, 0, 0))
        #expect(try EnclosedVoids(grid).voids.isEmpty, "one cell of air is below what the grid can see")
        grid.setSolid(false, at: grid.index(9, 8, 8))
        #expect(try EnclosedVoids(grid).voids.count == 1)
    }

    @Test func twoPocketsAreTwoVoids() throws {
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
        for index in 0..<grid.cellCount {
            let c = grid.coordinates(of: index)
            grid.setSolid((4..<30).contains(c.x) && (4..<30).contains(c.y) && (4..<30).contains(c.z), at: index)
        }
        for (i, j) in [(8, 8), (20, 20)] {
            for dx in 0..<3 { grid.setSolid(false, at: grid.index(i + dx, j, j)) }
        }
        let found = try EnclosedVoids(grid)
        #expect(found.voids.count == 2 && found.voids.allSatisfy { $0.count == 3 })
    }

    @Test func fillingFromADistanceMarksTheCellsNearTheSurfaceToo() throws {
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(10, 10, 10)))
        // A ball of radius 3 about (5, 5, 5).
        try grid.fill { points in points.map { ($0 - Vector3(5, 5, 5)).length - 3 } }
        #expect(grid.isSolid[grid.index(containing: Vector3(5, 5, 5)) ?? 0])
        #expect(grid.isSolid[grid.index(containing: Vector3(5 + 3.1, 5, 5)) ?? 0], "just outside, within half a cell")
        #expect(!grid.isSolid[grid.index(containing: Vector3(5 + 4.2, 5, 5)) ?? 0])
    }

    /// The cells a signed distance makes solid, one at a time: what `fill` must agree with.
    func bruteForce(_ grid: OccupancyGrid, _ distance: (Vector3) -> Double) -> [Bool] {
        (0..<grid.cellCount).map { distance(grid.center(of: $0)) <= grid.reach }
    }

    @Test func fillingByBlocksGivesWhatFillingCellByCellGives() throws {
        let centre = Vector3(10, 10, 10)
        let ball = { (point: Vector3) in (point - centre).length - 6 }
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(20, 20, 20)))
        var asked = 0
        try grid.fill { points in
            asked += points.count
            return points.map(ball)
        }
        #expect(grid.isSolid == bruteForce(grid, ball))
        #expect(asked < grid.cellCount / 2, "the surface is asked about cell by cell, the rest by blocks: \(asked) of \(grid.cellCount)")
    }

    @Test func aDistanceThatGrowsFasterThanOneMillimetreAMillimetreStillFillsExactlyWithItsBound() throws {
        let ball = { (point: Vector3) in 2.5 * ((point - Vector3(10, 10, 10)).length - 6) }
        var grid = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(20, 20, 20)))
        try grid.fill(lipschitz: 2.5) { points in points.map(ball) }
        #expect(grid.isSolid == bruteForce(grid, ball))
    }

    @Test func aFillCanBeWaitedForAndGivesTheSameCells() async throws {
        let ball = { (point: Vector3) in (point - Vector3(10, 10, 10)).length - 6 }
        var waited = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(20, 20, 20)))
        try await waited.fill(awaiting: { points in points.map(ball) })
        var direct = OccupancyGrid(bounds: BoundingBox(min: .zero, max: Vector3(20, 20, 20)))
        try direct.fill { points in points.map(ball) }
        #expect(waited.isSolid == direct.isSolid)
    }

    @Test func aDrainHoleOfTwoMillimetresIsSeenThroughAtTheDefaultCell() throws {
        // A plate 6 mm thick with a cavity 3 mm high, and a hole of the default 2 mm drilled up through its floor into the middle of the cavity: the
        // grid must see the hole, or Check Trapped Volumes would go on reporting a void that drains. (Each is a max or a min of
        // distances that grow at most one for one, so the whole is a valid bound for `fill`.)
        let middling = OccupancyGrid.cellSize(forSize: Vector3(300, 300, 300))
        #expect(middling > 0.5 && middling < 1.1, "\(middling)")
        let plate = BoundingBox(min: Vector3(-20, -20, 0), max: Vector3(20, 20, 6))
        func block(_ p: Vector3) -> Double { max(abs(p.x) - 20, abs(p.y) - 20, abs(p.z - 3) - 3) }
        func cavity(_ p: Vector3) -> Double { max(abs(p.x) - 17, abs(p.y) - 17, abs(p.z - 3) - 1.5) }
        func hole(_ p: Vector3) -> Double { max((p.x * p.x + p.y * p.y).squareRoot() - 1, p.z - 3) }
        var drained = OccupancyGrid(bounds: plate)
        try drained.fill { points in points.map { max(block($0), -min(cavity($0), hole($0))) } }
        #expect(try EnclosedVoids(drained).voids.isEmpty, "the hole opens the cavity to the outside")
        var sealed = OccupancyGrid(bounds: plate)
        try sealed.fill { points in points.map { max(block($0), -cavity($0)) } }
        #expect(try EnclosedVoids(sealed).voids.count == 1, "and without it the cavity is a void")
    }
}
