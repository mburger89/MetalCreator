import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// NS-4 Task 6: the Intersection Curves node.
struct IntersectionCurvesNodeTests {
    @Test func theNodeSitsInTheCurvesSection() {
        #expect(IntersectionCurvesNode.typeID == "creator.intersectionCurves")
        #expect(IntersectionCurvesNode.category == .surface && IntersectionCurvesNode.librarySubgroup == "Curves")
        #expect(IntersectionCurvesNode.inputs.map(\.name) == ["a", "b"])
        #expect(IntersectionCurvesNode.outputs.map(\.name) == ["curves"])
    }

    #if canImport(CreatorOCCT)
    let kernel = OCCTKernel()

    func rig(at base: Vector3) -> (h: Harness, node: Node) {
        var h = Harness()
        let a = h.box(10, 10, 10)
        let b = h.box(10, 10, 10, at: base)
        let node = h.add(IntersectionCurvesNode.self)
        h.wire(a, "solid", to: node, "a")
        h.wire(b, "solid", to: node, "b")
        return (h, node)
    }

    @Test func theNodeListsCurves() async throws {
        let (h, node) = rig(at: Vector3(5, 5, 5))
        let report = try await h.run([node], kernel: kernel)
        let curves = try #require(report.value(node, "curves")?.curves, "\(String(describing: report.state(node)))")
        #expect(!curves.isEmpty)
        #expect(report.isOK(node))
    }

    @Test func noMeetingWarns() async throws {
        let (h, node) = rig(at: Vector3(100, 0, 0))
        let report = try await h.run([node], kernel: kernel)
        #expect(report.warning(node) == "The bodies don't meet, so there are no intersection curves.")
        #expect(report.value(node, "curves")?.curves?.isEmpty == true)
    }
    #endif
}
