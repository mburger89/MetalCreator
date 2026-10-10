import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing

/// Why an exposed dimension isn't an input (`SketchSockets.refused`): no name, a name the node already uses, or a name
/// another exposed dimension has; and the singular wording of the degrees-of-freedom warning (`SketchSolve.run`).
struct SketchExposedNameTests {
    func sketchNode(_ h: inout Harness, _ sketch: Sketch) -> Node {
        h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
    }

    /// One degree of freedom left reads "1 degree", where `SketchNodeTests` pins the plural ("8 degrees").
    @Test func aSketchWithOneDegreeOfFreedomLeftWarnsInTheSingular() async throws {
        var rectangle = RectangleSketch()
        rectangle.sketch.dimensions[rectangle.height] = nil  // The height is the only thing left free.
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(SketchSolver.solve(rectangle.sketch).degreesOfFreedom == 1)
        #expect(report.warning(node) == "The sketch has 1 degree of freedom left, so it isn't fully constrained.")
    }

    @Test func aDimensionWithNoNameIsNotExposedAndWarns() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        rectangle.sketch.dimensions[rectangle.width]?.name = ""
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references"])
        let report = try await h.run([node])
        #expect(report.warning(node) == "An exposed dimension has no name, so it isn't an input. Name it to expose it.")
    }

    /// Two exposed dimensions with one name can only come from a hand-edited file (renaming refuses a taken name). The
    /// first, in id order, is the input; the other's warning says why, which isn't "the node already has an input or
    /// setting with that name".
    @Test func aSecondExposedDimensionWithTheSameNameIsNotExposedAndSaysSo() async throws {
        var rectangle = RectangleSketch()
        rectangle.expose(rectangle.width)
        rectangle.expose(rectangle.height)
        let name = rectangle.sketch.dimensions[rectangle.width]?.name ?? ""
        rectangle.sketch.dimensions[rectangle.height]?.name = name
        var h = Harness()
        let node = sketchNode(&h, rectangle.sketch)
        let report = try await h.run([node])
        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references", SocketName(name)])
        #expect(report.warning(node) == "Dimension “\(name)” can't be an input: another exposed dimension has the same name. "
            + "Rename one of them.")
    }
}
