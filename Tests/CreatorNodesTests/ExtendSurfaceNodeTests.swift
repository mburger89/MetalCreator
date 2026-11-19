import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// NS-4 Task 7: the Extend Surface node.
struct ExtendSurfaceNodeTests {
    @Test func theNodeSitsInTheEditSection() {
        #expect(ExtendSurfaceNode.typeID == "creator.extendSurface")
        #expect(ExtendSurfaceNode.category == .surface && ExtendSurfaceNode.librarySubgroup == "Edit")
        #expect(ExtendSurfaceNode.inputs.map(\.name) == ["edges", "length", "mode"])
        #expect(ExtendSurfaceNode.outputs.map(\.name) == ["surface"])
        #expect(ExtendSurfaceNode.modeOptions == ["Natural", "Linear"])
    }

    @Test func theInspectorOffersTheControlsAndThePick() {
        let controls = ExtendSurfaceNode.inspector.flatMap(\.controls)
        #expect(controls.contains(.segmented("mode", options: ["Natural", "Linear"])))
        #expect(controls.contains(.ruleSummary("edges")))
        #expect(controls.contains(.button(title: "Pick edges in view…", action: .pickEdgesInView)))
    }

    #if canImport(CreatorOCCT)
    let kernel = OCCTKernel()

    /// A planar sheet and every edge of it, wired into Extend Surface.
    func rig(mode: Int, length: Double = 4) -> (h: Harness, node: Node) {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self, ["width": .number(10), "height": .number(10)])
        let sheet = h.add(PlanarSurfaceNode.self)
        h.wire(rectangle, "profile", to: sheet, "curves")
        let edges = h.add(AllEdgesNode.self)
        h.wire(sheet, "surface", to: edges, "solid")
        let node = h.add(ExtendSurfaceNode.self, ["length": .number(length), "mode": .integer(mode)])
        h.wire(edges, "edges", to: node, "edges")
        return (h, node)
    }

    @Test(arguments: [0, 1]) func theNodeExtends(mode: Int) async throws {
        let (h, node) = rig(mode: mode)
        let report = try await h.run([node], kernel: kernel)
        let surface = try #require(report.value(node, "surface")?.solids?.first, "\(String(describing: report.state(node)))")
        #expect(report.isOK(node))
        // 10 x 10 grown by 4 on every side.
        let area = try await kernel.properties(of: surface).surfaceArea
        #expect(isClose(area, 18 * 18, relative: 1e-6), "area \(area)")
    }

    @Test func aZeroLengthIsRefusedInWords() async throws {
        var (h, node) = rig(mode: 0)
        h.set(node, "length", .number(0))
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) != nil)
    }
    #endif
}
