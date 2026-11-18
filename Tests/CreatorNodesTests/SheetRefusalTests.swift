#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// NS-1 Task 9: a Planar Surface sheet where a closed solid is needed, through the real Evaluator and OCCT.
struct SheetRefusalTests {
    let kernel = OCCTKernel()

    func sheet(_ h: inout Harness) -> Node {
        let rect = h.add(RectangleNode.self, ["width": .number(10), "height": .number(20)])
        let surface = h.add(PlanarSurfaceNode.self)
        h.wire(rect, "profile", to: surface, "curves")
        return surface
    }

    @Test func filletRefusesASheet() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let edges = h.add(AllEdgesNode.self), fillet = h.add(FilletNode.self)
        h.wire(surface, "surface", to: edges, "solid")
        h.wire(edges, "edges", to: fillet, "edges")
        let report = try await h.run([fillet], kernel: kernel)
        #expect(report.error(fillet) == "Fillet needs a closed solid; Thicken or Sew the sheet first.")
    }

    @Test func chamferRefusesASheet() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let edges = h.add(AllEdgesNode.self), chamfer = h.add(ChamferNode.self)
        h.wire(surface, "surface", to: edges, "solid")
        h.wire(edges, "edges", to: chamfer, "edges")
        let report = try await h.run([chamfer], kernel: kernel)
        #expect(report.error(chamfer) == "Chamfer needs a closed solid; Thicken or Sew the sheet first.")
    }

    @Test func booleanNamesTheInput() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let box = h.box(30, 30, 5)
        let asTool = h.add(BooleanNode.self), asTarget = h.add(BooleanNode.self)
        h.wire(box, "solid", to: asTool, "target")
        h.wire(surface, "surface", to: asTool, "tools")
        h.wire(surface, "surface", to: asTarget, "target")
        h.wire(box, "solid", to: asTarget, "tools")
        let report = try await h.run([asTool, asTarget], kernel: kernel)
        #expect(report.error(asTool) == "“tools” is an open surface; use Split or Trim, or Thicken or Sew it first.")
        #expect(report.error(asTarget) == "“target” is an open surface; use Split or Trim, or Thicken or Sew it first.")
    }

    @Test func aClosedLoftOfCirclesIsASheetAndBooleanRefusesIt() async throws {
        var h = Harness()
        let loft = h.add(LoftSurfaceNode.self, ["closed": .bool(true)])
        let merge = h.add(MergeNode.self)
        let sockets: [SocketName] = ["a", "b", "c"]
        for (z, socket) in zip([0.0, 6, 12], sockets) {
            let circle = h.add(CircleNode.self, ["plane": .plane(.through(Vector3(0, 0, z)))])
            let curves = h.add(ProfileToCurvesNode.self)
            h.wire(circle, "profile", to: curves, "profile")
            h.wire(curves, "curves", to: merge, socket)
        }
        h.wire(merge, "list", to: loft, "sections")
        let box = h.box(30, 30, 5)
        let boolean = h.add(BooleanNode.self)
        h.wire(box, "solid", to: boolean, "target")
        h.wire(loft, "surface", to: boolean, "tools")
        let report = try await h.run([boolean, loft], kernel: kernel)
        let surface = try #require(report.results[loft.id]?.outputs?["surface"]?.items.first)
        guard case .solid(let solid) = surface else { Issue.record("not a solid"); return }
        #expect(solid.hasOpenShell && solid.isClosed, "a closed bare shell is a sheet (isClosed stays edge-level)")
        #expect(report.error(boolean) == "“tools” is an open surface; use Split or Trim, or Thicken or Sew it first.")
    }

    @Test func toImplicitRefusesASheet() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let node = h.add(ToImplicitNode.self)
        h.wire(surface, "surface", to: node, "solid")
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == "To Implicit needs a closed solid; Thicken or Sew the sheet first.")
    }

    @Test func signedDistanceRefusesASheetButUnsignedDoesNot() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let signed = h.add(DistanceFieldNode.self, ["mode": .integer(1)])
        let unsigned = h.add(DistanceFieldNode.self, ["mode": .integer(0)])
        h.wire(surface, "surface", to: signed, "target")
        h.wire(surface, "surface", to: unsigned, "target")
        let report = try await h.run([signed, unsigned], kernel: kernel)
        #expect(report.error(signed) == "A signed distance needs a closed solid; use Unsigned for a sheet.")
        #expect(report.error(unsigned) == nil)
    }

    @Test func aPatternFeatureNamesPartAndTool() async throws {
        var h = Harness()
        let surface = sheet(&h)
        let box = h.box(30, 30, 5)
        let onPart = h.add(PatternFeatureNode.self, ["placements": .plane(.xy)])
        let onTool = h.add(PatternFeatureNode.self, ["placements": .plane(.xy)])
        h.wire(surface, "surface", to: onPart, "part")
        h.wire(box, "solid", to: onPart, "tool")
        h.wire(box, "solid", to: onTool, "part")
        h.wire(surface, "surface", to: onTool, "tool")
        let report = try await h.run([onPart, onTool], kernel: kernel)
        #expect(report.error(onPart) == "“part” is an open surface; use Split or Trim, or Thicken or Sew it first.")
        #expect(report.error(onTool) == "“tool” is an open surface; use Split or Trim, or Thicken or Sew it first.")
    }
}
#endif
