#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// NURBS gaps Task 2: Separate Solids (R3) and Split Solid's sentence for a mixed value (R4), through the real Evaluator and OCCT.
struct SeparateSolidsNodeTests {
    let kernel = OCCTKernel()

    /// A box (z 0 to 10) and a 10 x 20 sheet at z 30, sewn into one value holding a closed solid and a sheet.
    func mixed(_ h: inout Harness) -> Node {
        let box = h.box(10, 10, 10)
        let rect = h.add(RectangleNode.self, ["width": .number(10), "height": .number(20), "plane": .plane(.through(Vector3(0, 0, 30)))])
        let surface = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: surface, "curves")
        let merge = h.add(MergeNode.self), sew = h.add(SewNode.self)
        h.wire(box, "solid", to: merge, "a")
        h.wire(surface, "surface", to: merge, "b")
        h.wire(merge, "list", to: sew, "bodies")
        return sew
    }

    @Test func separateSolidsIsInTheLibrary() {
        let node = BuiltInNodes.registry.makeNode(SeparateSolidsNode.typeID)
        #expect(node.typeID == "creator.separateSolids")
        #expect(SeparateSolidsNode.category == .surface && SeparateSolidsNode.librarySubgroup == "Solids")
        #expect(BuiltInNodes.all.contains { $0.typeID == "creator.separateSolids" })
        #expect(SeparateSolidsNode.inputs.map(\.name) == ["value"])
        #expect(SeparateSolidsNode.outputs.map(\.name) == ["solids", "surfaces"])
    }

    @Test func separateSolidsListsTheSolidAndTheSurface() async throws {
        var h = Harness()
        let sew = mixed(&h), separate = h.add(SeparateSolidsNode.self)
        h.wire(sew, "solid", to: separate, "value")
        let report = try await h.run([separate], kernel: kernel)
        #expect(report.isOK(separate), "\(String(describing: report.state(separate)))")
        let solids = try #require(report.value(separate, "solids")?.solids)
        let surfaces = try #require(report.value(separate, "surfaces")?.solids)
        #expect(solids.count == 1 && !solids[0].hasOpenShell)
        #expect(surfaces.count == 1 && surfaces[0].hasOpenShell)
        #expect(report.warning(separate) == nil)
    }

    @Test func separatedSolidFeedsSplitSolid() async throws {
        var h = Harness()
        let sew = mixed(&h), separate = h.add(SeparateSolidsNode.self)
        let pick = h.add(ListItemNode.self, ["index": .integer(0)]), split = h.add(SplitSolidNode.self)
        let rect = h.add(RectangleNode.self, ["width": .number(20), "height": .number(20), "plane": .plane(.through(Vector3(0, 0, 5)))])
        let cutter = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: cutter, "curves")
        h.wire(sew, "solid", to: separate, "value")
        h.wire(separate, "solids", to: pick, "tree")
        h.wire(pick, "item", to: split, "solid")
        h.wire(cutter, "surface", to: split, "tools")
        let report = try await h.run([split], kernel: kernel)
        #expect(report.isOK(split), "\(String(describing: report.state(split)))")
        let pieces = try #require(report.value(split, "solids")?.solids)
        #expect(pieces.count == 2 && pieces.allSatisfy { !$0.hasOpenShell })
    }

    @Test func aMixedValueSaysSeparate() async throws {
        var h = Harness()
        let sew = mixed(&h), split = h.add(SplitSolidNode.self)
        h.wire(sew, "solid", to: split, "solid")
        let report = try await h.run([split], kernel: kernel)
        #expect(report.error(split) == "Split Solid takes a closed solid; “solid” also holds a surface. "
            + "Use Separate Solids to take the solid out first.")
    }
}
#endif
