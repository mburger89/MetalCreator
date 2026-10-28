import CreatorGeometry
import Testing
@testable import CreatorSketch

/// `SketchRegion.sources`: the entity each loop segment comes from, parallel to the segments.
struct RegionSourceTests {
    /// A 60 × 40 rectangle from (0, 0): `lines` are bottom, right, top, left.
    func rectangle(_ sketch: inout Sketch) -> [SketchEntityID] {
        addPolygon(&sketch, [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
    }

    @Test func theOuterLoopNamesItsLinesFromTheSmallestCorner() throws {
        var sketch = Sketch()
        let lines = rectangle(&sketch)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(region.sources[0] == lines)
    }

    @Test func holesNameTheirCirclesInHoleOrder() throws {
        var sketch = Sketch()
        _ = rectangle(&sketch)
        let first = sketch.addCircle(center: Vector2(15, 20), radius: 4)
        let second = sketch.addCircle(center: Vector2(45, 20), radius: 4)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        try #require(region.sources.count == 3)
        #expect(!region.sources[1].isEmpty)
        #expect(region.sources[1].allSatisfy { $0 == first })
        #expect(!region.sources[2].isEmpty)
        #expect(region.sources[2].allSatisfy { $0 == second })
    }

    @Test func sourcesParallelTheSegments() throws {
        var sketch = Sketch()
        _ = rectangle(&sketch)
        sketch.addCircle(center: Vector2(15, 20), radius: 4)
        sketch.addCircle(center: Vector2(45, 20), radius: 4)
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        let loops = [region.outer] + region.holes
        try #require(region.sources.count == loops.count)
        for (loop, sources) in zip(loops, region.sources) { #expect(sources.count == loop.count) }
    }

    @Test func aSplitCurveNamesEachPiece() throws {
        var sketch = Sketch()
        let lines = rectangle(&sketch)
        // A vertical line across the middle splits the rectangle in two.
        let divider = sketch.addLine(Vector2(30, 0), Vector2(30, 40))
        let regions = SketchRegions.find(in: sketch).regions
        try #require(regions.count == 2)
        for region in regions {
            #expect(region.sources[0].contains(divider))
            #expect(region.sources[0].contains(lines[0]))
            #expect(region.sources[0].contains(lines[2]))
        }
        #expect(regions[0].sources[0].filter { $0 == lines[0] }.count == 1)
    }

    @Test func aProjectedEdgeNamesItsEntity() throws {
        var sketch = Sketch()
        let a = sketch.addLine(Vector2(0, 0), Vector2(0, 10))
        let b = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        let c = sketch.addLine(Vector2(10, 10), Vector2(10, 0))
        let projected = sketch.add(SketchEntity(.projected(ProjectionSource(reference: "e", curve: .line(Vector2(10, 0), Vector2(0, 0))))))
        let region = try #require(SketchRegions.find(in: sketch).regions.first)
        #expect(Set(region.sources[0]) == [a, b, c, projected])
        #expect(region.sources[0].count == 4)
    }
}
