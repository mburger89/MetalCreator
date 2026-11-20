#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 9: Sew, Thicken, Offset Surface, Cap Planar Holes and Split Solid through the real Evaluator and OCCT.
struct BackToSolidsNodeTests {
    let kernel = OCCTKernel()

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    /// A 10 x 20 sheet on the XY plane through `z` (Planar Surface, normal +z).
    func sheet(_ h: inout Harness, z: Double = 0) -> Node {
        let rect = h.add(RectangleNode.self, ["width": .number(10), "height": .number(20), "plane": .plane(.through(Vector3(0, 0, z)))])
        let surface = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: surface, "curves")
        return surface
    }

    /// The box's six loose faces read by Import Model (R19), their top moved by `moving`.
    func looseBox(_ h: inout Harness, moving: Double) throws -> (node: Node, images: ImageResolver) {
        let data = try OCCTKernel.looseBoxFaces(size: 10, movingTopBy: moving, doublingTop: false)
        let hash = ImageHash(of: data)
        let node = h.add(ImportModelNode.self, [NodeSetting.modelFile: .modelFile(.embedded(hash))])
        return (node, ImageResolver(embedded: [hash: data]))
    }

    func firstNormal(_ report: EvaluationReport, _ node: Node) throws -> Vector3 {
        let solid = try #require(report.value(node, "surface")?.solids?.first)
        return try #require(solid.topology.faces.first?.normal)
    }

    func facts(_ report: EvaluationReport, _ node: Node) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try #require(report.results[node.id]?.facts).map { ($0.label, $0.value) })
    }

    @Test func theNodesSitWhereTheLibraryLooksForThem() {
        let solidsGroup = [SewNode.librarySubgroup, ThickenNode.librarySubgroup, CapPlanarHolesNode.librarySubgroup]
        #expect(solidsGroup == ["Solids", "Solids", "Solids"])
        #expect(OffsetSurfaceNode.librarySubgroup == "Edit")
        #expect(NodeCategory.surface.librarySubgroups == ["Curves", "Make", "Edit", "Solids"])
        #expect(SplitSolidNode.category == .solid)
        #expect(SewNode.showsFreeEdges && CapPlanarHolesNode.showsFreeEdges && !ThickenNode.showsFreeEdges)
        #expect(SewNode.factsTitle == "Sew" && CapPlanarHolesNode.factsTitle == "Caps")
    }

    @Test func sewFactsAndWarnings() async throws {
        var h = Harness()
        let (model, images) = try looseBox(&h, moving: 0.05)
        let sew = h.add(SewNode.self)
        h.wire(model, "sheets", to: sew, "bodies")
        let report = try await h.run([sew], kernel: kernel, images: images)
        let facts = try facts(report, sew)
        #expect(facts["Result"] == "2 sheets" && facts["Free edges"] == "8" && facts["Faces"] == "6")
        #expect(report.warning(sew) == "The sewn surface still has 8 free edges, so it stays open.")
    }

    @Test func sewClosesABox() async throws {
        var h = Harness()
        let (model, images) = try looseBox(&h, moving: 0)
        let sew = h.add(SewNode.self)
        h.wire(model, "sheets", to: sew, "bodies")
        let report = try await h.run([sew], kernel: kernel, images: images)
        #expect(try facts(report, sew)["Result"] == "1 solid")
        #expect(report.isOK(sew), "\(String(describing: report.state(sew)))")
    }

    @Test func thickenSidesAreSegmented() async throws {
        #expect(ThickenNode.sides == ["Front", "Back", "Both"])
        var ranges: [ClosedRange<Double>] = []
        var sign = 1.0
        for side in 0..<3 {
            var h = Harness()
            let surface = sheet(&h)
            let thicken = h.add(ThickenNode.self, ["distance": .number(2), "side": .integer(side)])
            h.wire(surface, "surface", to: thicken, "surface")
            let report = try await h.run([surface, thicken], kernel: kernel)
            #expect(report.isOK(thicken), "\(String(describing: report.state(thicken)))")
            let normal = try firstNormal(report, surface)
            #expect(abs(normal.z) > 0.99)
            sign = normal.z > 0 ? 1 : -1
            let solid = try #require(report.value(thicken, "solid")?.solids?.first)
            #expect(!solid.hasOpenShell)
            #expect(isClose(try await volume(solid), 400, relative: 1e-6))
            ranges.append(solid.bounds.min.z...solid.bounds.max.z)
        }
        // Front grows toward the sheet's normal, Back against it (R3); a sheet's normal may point either way (R18).
        func span(_ a: Double, _ b: Double) -> ClosedRange<Double> { min(a * sign, b * sign)...max(a * sign, b * sign) }
        func matches(_ range: ClosedRange<Double>, _ expected: ClosedRange<Double>) -> Bool {
            isClose(range.lowerBound, expected.lowerBound) && isClose(range.upperBound, expected.upperBound)
        }
        #expect(matches(ranges[0], span(0, 2)))
        #expect(matches(ranges[1], span(-2, 0)))
        #expect(matches(ranges[2], span(-1, 1)))
    }

    @Test func thickenRefusesASolid() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10), thicken = h.add(ThickenNode.self)
        h.wire(box, "solid", to: thicken, "surface")
        let report = try await h.run([thicken], kernel: kernel)
        #expect(report.error(thicken) == "Thicken takes a sheet; this is a closed solid.")
    }

    @Test func thickenRefusesAMixedValue() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10), surface = sheet(&h, z: 30)
        let merge = h.add(MergeNode.self), sew = h.add(SewNode.self), thicken = h.add(ThickenNode.self)
        h.wire(box, "solid", to: merge, "a")
        h.wire(surface, "surface", to: merge, "b")
        h.wire(merge, "list", to: sew, "bodies")
        h.wire(sew, "solid", to: thicken, "surface")
        let report = try await h.run([thicken], kernel: kernel)
        #expect(report.error(thicken) == "Thicken takes sheets only; this value also holds a closed solid.")
    }

    @Test func offsetSurfaceNegativeDistance() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let offset = h.add(OffsetSurfaceNode.self, ["distance": .number(-3)])
        h.wire(surface, "surface", to: offset, "surface")
        let report = try await h.run([surface, offset], kernel: kernel)
        #expect(report.isOK(offset), "\(String(describing: report.state(offset)))")
        let normal = try firstNormal(report, surface)
        #expect(abs(normal.z) > 0.99)
        let moved = try #require(report.value(offset, "surface")?.solids?.first)
        // A negative distance goes against the normal, whichever way that points (R18).
        let expected = normal.z > 0 ? -3.0 : 3.0
        #expect(moved.hasOpenShell && isClose(moved.bounds.min.z, expected) && isClose(moved.bounds.max.z, expected))
    }

    @Test func capWarnsAboutABentLoop() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["step": .number(10), "count": .integer(3)])
        let points = h.add(VectorNode.self, ["x": .number(10)])
        h.wire(series, "values", to: points, "z")
        let line = h.add(CurveThroughPointsNode.self)
        h.wire(points, "vector", to: line, "points")
        let revolve = h.add(RevolveCurveNode.self, ["axis direction": .vector(Vector3(0, 0, 1)), "angle": .number(90)])
        h.wire(line, "curve", to: revolve, "curve")
        let cap = h.add(CapPlanarHolesNode.self)
        h.wire(revolve, "surface", to: cap, "surface")
        let report = try await h.run([cap], kernel: kernel)
        let message = try #require(report.warning(cap), "\(String(describing: report.state(cap)))")
        #expect(message.contains("1 hole isn't flat, so it was left open."))
        #expect(message.contains("The capped surface still has "))
        let facts = try facts(report, cap)
        #expect(facts["Holes capped"] == "0" && facts["Left open"] == "1")
    }

    func splitRig(withTool: Bool) -> (Harness, Node) {
        var h = Harness()
        let box = h.box(10, 10, 10), split = h.add(SplitSolidNode.self)
        h.wire(box, "solid", to: split, "solid")
        if withTool {
            let cutter = sheetCutter(&h)
            h.wire(cutter, "surface", to: split, "tools")
        }
        return (h, split)
    }

    func sheetCutter(_ h: inout Harness) -> Node {
        let rect = h.add(RectangleNode.self, ["width": .number(20), "height": .number(20), "plane": .plane(.through(Vector3(0, 0, 5)))])
        let surface = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: surface, "curves")
        return surface
    }

    @Test func splitSolidListsItsPieces() async throws {
        let (h, split) = splitRig(withTool: true)
        let report = try await h.run([split], kernel: kernel)
        #expect(report.isOK(split), "\(String(describing: report.state(split)))")
        let pieces = try #require(report.value(split, "solids")?.solids)
        #expect(pieces.count == 2 && pieces.allSatisfy { !$0.hasOpenShell })
        var total = 0.0
        for piece in pieces { total += try await volume(piece) }
        #expect(isClose(total, 1000, relative: 1e-6))
    }

    @Test func splitSolidWithNoToolsGivesTheSolidBack() async throws {
        let (h, split) = splitRig(withTool: false)
        let report = try await h.run([split], kernel: kernel)
        let pieces = try #require(report.value(split, "solids")?.solids)
        #expect(pieces.count == 1 && !pieces[0].hasOpenShell)
    }

    @Test func splitSolidRefusesASheetInItsOwnWords() async throws {
        var h = Harness()
        let surface = sheet(&h), box = h.box(10, 10, 10), split = h.add(SplitSolidNode.self)
        h.wire(surface, "surface", to: split, "solid")
        h.wire(box, "solid", to: split, "tools")
        let report = try await h.run([split], kernel: kernel)
        #expect(report.error(split) == "Split Solid takes a closed solid; “solid” is an open surface. "
            + "Use Split to cut a surface, or Thicken or Sew it first.")
    }

    @Test func booleanPointsToSplitSolid() async throws {
        var h = Harness()
        let surface = sheet(&h), box = h.box(10, 10, 10), boolean = h.add(BooleanNode.self)
        h.wire(box, "solid", to: boolean, "target")
        h.wire(surface, "surface", to: boolean, "tools")
        let report = try await h.run([boolean], kernel: kernel)
        #expect(report.error(boolean) == "“tools” is an open surface; use Split Solid to cut with it, or Thicken or Sew it first.")
    }
}
#endif
