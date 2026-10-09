import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp

/// The app reads exposed dimensions the way the Sketch node partitions them (sketcher spec §7), so a wire or a
/// constant reaches the one dimension the node applies it to.
struct SketchStoreTests {
    @Test func aRepeatedExposedNameIsOneSocketAsTheNodeSeesIt() throws {
        var sketch = rectangleSketch(exposed: true)
        let height = try #require(sketch.dimensionIDs.last)
        sketch.dimensions[height]?.name = "width" // renameDimension refuses a repeat; a decoded file can hold one
        sketch.dimensions[height]?.isExposed = true
        let names = SketchStore.exposedNames(sketch)
        #expect(names.count == 1 && names.values.first == "width")
        #expect(Set(names.keys) == Set(SketchNode.exposedSocketNames(sketch).keys))
        let folded = SketchStore.folded(sketch, constants: ["width": .number(75)])
        let values = sketch.dimensionIDs.compactMap { folded.dimensions[$0]?.value }
        #expect(values.sorted() == [40, 75], "only the socket's dimension takes the constant")
    }
}
