import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// A profile with a hole (the built-in profile nodes make none).
private enum AnnulusProfileNode: NodeDefinition {
    static let typeID = "test.trimAnnulusProfile"
    static let displayName = "Annulus Profile"
    static let category = NodeCategory.profile
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("profile", .profile)]

    static func square(_ side: Double, at origin: Vector2) -> [Segment2D] {
        let p = [origin, origin + Vector2(side, 0), origin + Vector2(side, side), origin + Vector2(0, side)]
        return (0..<4).map { .line(p[$0], p[($0 + 1) % 4]) }
    }

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["profile": .profile(Profile2D(plane: .xy, outer: square(10, at: .zero), holes: [square(2, at: Vector2(4, 4))]))])
    }
}

/// An open curve: one straight line across x = 0.
private enum LineCurveNode: NodeDefinition {
    static let typeID = "test.trimLineCurve"
    static let displayName = "Line Curve"
    static let category = NodeCategory.surface
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("curve", .curve)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let line = try await kernel.makeCurve([.line(Vector3(0, -20, 0), Vector3(0, 20, 0))], tag: context.tag)
        return NodeOutputs(["curve": .curve(line)])
    }
}

struct TrimSurfaceNodeDefinitionTests {
    @Test func piecesAreHiddenInPreview() {
        #expect(TrimSurfaceNode.previewHiddenOutputs == ["pieces"])
        #expect(SplitSurfaceNode.previewHiddenOutputs.isEmpty)
    }

    @Test func theNodesSitInTheEditSection() {
        #expect(TrimSurfaceNode.category == .surface && TrimSurfaceNode.librarySubgroup == "Edit")
        #expect(SplitSurfaceNode.category == .surface && SplitSurfaceNode.librarySubgroup == "Edit")
        #expect(TrimSurfaceNode.outputs.map(\.name) == ["surface", "pieces"])
    }

    @Test func theInspectorShowsOnlyWhatTheModeNeeds() {
        var node = BuiltInNodes.registry.makeNode(TrimSurfaceNode.typeID)
        var controls = TrimSurfaceNode.inspector(for: node).flatMap(\.controls)
        #expect(controls.contains(.vector("direction")))
        #expect(controls.contains(.note("No regions picked")))
        #expect(controls.contains(.button(title: "Pick regions in view…", action: .pickTrimRegions)))
        #expect(controls.contains(.button(title: "Clear regions", action: .clearTrimRegions)))
        let pick = RegionPick(pick: FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .startCap)]))
        node.inputValues[NodeSetting.keepRegions] = .regionPicks([pick])
        node.inputValues["projection"] = .integer(1)
        node.inputValues["keep"] = .integer(0)
        controls = TrimSurfaceNode.inspector(for: node).flatMap(\.controls)
        #expect(!controls.contains(.vector("direction")))
        #expect(controls.contains(.note("1 region picked")))
        node.inputValues[NodeSetting.keepRegions] = .regionPicks([pick, pick])
        #expect(TrimSurfaceNode.inspector(for: node).flatMap(\.controls).contains(.note("2 regions picked")))
        node.inputValues["keep"] = .integer(1)
        controls = TrimSurfaceNode.inspector(for: node).flatMap(\.controls)
        #expect(!controls.contains { if case .button = $0 { true } else { false } })
    }
}

#if canImport(CreatorOCCT)
struct TrimSurfaceNodeTests {
    let kernel = OCCTKernel()
    var registry: NodeRegistry { NodeRegistry(BuiltInNodes.all + [AnnulusProfileNode.self, LineCurveNode.self]) }

    /// A 20 mm square sheet (Planar Surface), a 10 mm circle and a Trim Surface wired to both; returns the nodes.
    struct Rig {
        var h = Harness()
        var rect: Node
        var sheet: Node
        var circle: Node
        var trim: Node

        init(keep: Int, width: Double = 20, height: Double = 20) {
            rect = h.add(RectangleNode.self, ["width": .number(width), "height": .number(height)])
            sheet = h.add(PlanarSurfaceNode.self)
            circle = h.add(CircleNode.self, ["diameter": .number(10)])
            trim = h.add(TrimSurfaceNode.self, ["keep": .integer(keep)])
            h.wire(rect, "profile", to: sheet, "curves")
            h.wire(sheet, "surface", to: trim, "surface")
            h.wire(circle, "profile", to: trim, "curves")
        }
    }

    func area(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).surfaceArea }

    func output(_ report: EvaluationReport, _ node: Node, _ socket: SocketName = "surface") throws -> Solid {
        try #require(report.value(node, socket)?.solids?.first, "\(String(describing: report.state(node)))")
    }

    /// One piece per face of the whole split, which holds the disk and the ring (not touching one another across a shared face).
    func pieces(of whole: Solid) -> [[FaceID]] { whole.topology.faces.map { [$0.id] } }

    @Test func insideKeepsTheDisk() async throws {
        let rig = Rig(keep: 1)
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.isOK(rig.trim), "\(String(describing: report.state(rig.trim)))")
        let disk = try await area(try output(report, rig.trim))
        #expect(isClose(disk, 25 * .pi, relative: 1e-6))
    }

    @Test func outsideKeepsTheRing() async throws {
        let rig = Rig(keep: 2)
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        let ring = try await area(try output(report, rig.trim))
        #expect(isClose(ring, 400 - 25 * .pi, relative: 1e-6))
    }

    @Test func noPicksKeepsEverythingAndWarns() async throws {
        let rig = Rig(keep: 0)
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.warning(rig.trim) == "Pick the regions to keep; until then Trim Surface keeps every piece.")
        #expect(isClose(try await area(try output(report, rig.trim)), 400, relative: 1e-6))
    }

    @Test func piecesOutputIsTheWholeSplit() async throws {
        let rig = Rig(keep: 1)
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        let whole = try output(report, rig.trim, "pieces")
        #expect(whole.topology.faces.count == 2)
        #expect(isClose(try await area(whole), 400, relative: 1e-6))
    }

    /// The pick of the piece whose faces carry `side`, written as Task 11 will write it.
    func pick(in whole: Solid, side: CutSide) throws -> RegionPick {
        let faces = whole.topology.faces
        let wanted = try #require(faces.first { face in
            face.tags.contains { if case .cutSide(_, side) = $0.role { true } else { false } }
        })
        let index = try #require(faces.firstIndex(of: wanted))
        return try #require(TrimRegions.pick(forPiece: index, pieces: pieces(of: whole), in: whole.topology))
    }

    @Test func aPickedRegionIsKept() async throws {
        var rig = Rig(keep: 0)
        let first = try await rig.h.run([rig.trim], kernel: kernel)
        let region = try pick(in: try output(first, rig.trim, "pieces"), side: .inside)
        rig.h.set(rig.trim, NodeSetting.keepRegions, .regionPicks([region]))
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.isOK(rig.trim), "\(String(describing: report.state(rig.trim)))")
        #expect(isClose(try await area(try output(report, rig.trim)), 25 * .pi, relative: 1e-6))
    }

    @Test func aPickFollowsTheDiskWhenTheRadiusChanges() async throws {
        var rig = Rig(keep: 0)
        let first = try await rig.h.run([rig.trim], kernel: kernel)
        let region = try pick(in: try output(first, rig.trim, "pieces"), side: .inside)
        rig.h.set(rig.trim, NodeSetting.keepRegions, .regionPicks([region]))
        rig.h.set(rig.circle, "diameter", .number(12))
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.isOK(rig.trim), "\(String(describing: report.state(rig.trim)))")
        #expect(isClose(try await area(try output(report, rig.trim)), 36 * .pi, relative: 1e-6))
    }

    @Test func aVanishedPickIsRefused() async throws {
        var rig = Rig(keep: 0)
        let gone = RegionPick(pick: FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .startCap)]))
        rig.h.set(rig.trim, NodeSetting.keepRegions, .regionPicks([gone]))
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.error(rig.trim) == "None of the picked regions exist any more; pick the regions to keep again.")
    }

    @Test func insideNeedsAClosedCutter() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self, ["width": .number(20), "height": .number(20)])
        let sheet = h.add(PlanarSurfaceNode.self)
        let line = h.add(LineCurveNode.self)
        let trim = h.add(TrimSurfaceNode.self, ["keep": .integer(1)])
        h.wire(rect, "profile", to: sheet, "curves")
        h.wire(sheet, "surface", to: trim, "surface")
        let cutter = Link(from: Endpoint(node: line.id, socket: "curve"), to: Endpoint(node: trim.id, socket: "curves"))
        let report = try await Evaluator(registry: registry, kernel: kernel).evaluate(
            Graph(nodes: h.nodes, links: h.links + [cutter]).adding(line), demand: [trim.id], images: ImageResolver())
        #expect(report.error(trim) == "Inside and Outside need a closed cutter: closed flat curves or a closed solid. "
            + "Pick the regions to keep instead.")
    }

    @Test func curvesAndBodyRefuse() async throws {
        var rig = Rig(keep: 1)
        rig.h.wire(rig.sheet, "surface", to: rig.trim, "cutter")
        let report = try await rig.h.run([rig.trim], kernel: kernel)
        #expect(report.error(rig.trim) == "Trim Surface takes cutting curves or a cutting body, not both.")
    }

    @Test func nothingToCutWithIsRefused() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self)
        let sheet = h.add(PlanarSurfaceNode.self)
        let trim = h.add(TrimSurfaceNode.self)
        h.wire(rect, "profile", to: sheet, "curves")
        h.wire(sheet, "surface", to: trim, "surface")
        let report = try await h.run([trim], kernel: kernel)
        #expect(report.error(trim) == "Wire curves or a body to cut with.")
    }

    @Test func splitListsPieces() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self, ["width": .number(20), "height": .number(20)])
        let sheet = h.add(PlanarSurfaceNode.self)
        let circle = h.add(CircleNode.self, ["diameter": .number(10)])
        let split = h.add(SplitSurfaceNode.self)
        h.wire(rect, "profile", to: sheet, "curves")
        h.wire(sheet, "surface", to: split, "surface")
        h.wire(circle, "profile", to: split, "curves")
        let report = try await h.run([split], kernel: kernel)
        let sheets = try #require(report.value(split, "pieces")?.solids, "\(String(describing: report.state(split)))")
        #expect(sheets.count == 2)
        var areas: [Double] = []
        for piece in sheets { areas.append(try await area(piece)) }
        // R6: the pieces are ordered by their smallest face tag set; the disk and the ring differ only in their cut side.
        #expect(areas.contains { isClose($0, 25 * .pi, relative: 1e-6) })
        #expect(areas.contains { isClose($0, 400 - 25 * .pi, relative: 1e-6) })
    }

    @Test func aProfileWithAHoleTrimsAnAnnulus() async throws {
        var h = Harness()
        let rect = h.add(RectangleNode.self, ["width": .number(40), "height": .number(40)])
        let sheet = h.add(PlanarSurfaceNode.self)
        let annulus = registry.makeNode(AnnulusProfileNode.typeID)
        let trim = h.add(TrimSurfaceNode.self, ["keep": .integer(1)])
        h.wire(rect, "profile", to: sheet, "curves")
        h.wire(sheet, "surface", to: trim, "surface")
        let links = h.links + [Link(from: Endpoint(node: annulus.id, socket: "profile"), to: Endpoint(node: trim.id, socket: "curves"))]
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(Graph(nodes: h.nodes, links: links).adding(annulus), demand: [trim.id], images: ImageResolver())
        let kept = try output(report, trim)
        #expect(isClose(try await area(kept), 96, relative: 1e-6), "\(String(describing: report.state(trim)))")
    }

    /// Task 4's band: a 20 x 6 strip cut by a 10 mm circle leaves the disc's part and two outside pieces that share one name.
    @Test func aBandCutLeavesTwoOutsidePiecesThatPickCleanly() async throws {
        var rig = Rig(keep: 0, width: 20, height: 6)
        let first = try await rig.h.run([rig.trim], kernel: kernel)
        let whole = try output(first, rig.trim, "pieces")
        #expect(whole.topology.faces.count == 3)
        let outside = whole.topology.faces.enumerated().filter { _, face in
            face.tags.contains { if case .cutSide(_, .outside) = $0.role { true } else { false } }
        }
        let left = try #require(outside.first { $0.element.centroid.x < 0 })
        let region = try #require(TrimRegions.pick(forPiece: left.offset, pieces: pieces(of: whole), in: whole.topology))
        #expect(region.sharedBy == 2)
        rig.h.set(rig.trim, NodeSetting.keepRegions, .regionPicks([region]))
        for diameter in [10.0, 8] {
            rig.h.set(rig.circle, "diameter", .number(diameter))
            let report = try await rig.h.run([rig.trim], kernel: kernel)
            #expect(report.isOK(rig.trim), "\(String(describing: report.state(rig.trim)))")
            let kept = try output(report, rig.trim)
            #expect(kept.topology.faces.count == 1)
            #expect(try #require(kept.topology.faces.first).centroid.x < 0)
        }
    }
}

private extension Graph {
    /// This graph with `node` added.
    func adding(_ node: Node) -> Graph {
        var copy = self
        copy.nodes[node.id] = node
        return copy
    }
}
#endif

#if canImport(CreatorOCCT)
/// A test node that makes the ruled loft of Task 4's two-face sheet: three lines at y = 0, 10 and 20, rising along y.
private enum RuledSheetNode: NodeDefinition {
    static let typeID = "test.trimRuledSheet"
    static let displayName = "Ruled Sheet"
    static let category = NodeCategory.surface
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("surface", .solid)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        var sections: [Curve] = []
        for y in [0.0, 10, 20] {
            sections.append(try await kernel.makeCurve([.line(Vector3(-10, y, 0), Vector3(10, y, y / 5))], tag: context.tag))
        }
        return NodeOutputs(["surface": .solid(try await kernel.loftSurface(sections, ruled: true, closed: false, tag: context.tag))])
    }
}

struct TrimSurfaceMultiFaceTests {
    let kernel = OCCTKernel()

    @Test func aPickKeepsTheWholeRegionOfAMultiFaceSheet() async throws {
        let registry = NodeRegistry(BuiltInNodes.all + [RuledSheetNode.self])
        var h = Harness()
        let ruled = registry.makeNode(RuledSheetNode.typeID)
        let rect = h.add(RectangleNode.self, ["width": .number(80), "height": .number(60), "plane": .plane(.yz)])
        let wall = h.add(PlanarSurfaceNode.self)
        let trim = h.add(TrimSurfaceNode.self)
        h.wire(rect, "profile", to: wall, "curves")
        h.wire(wall, "surface", to: trim, "cutter")
        let links = h.links + [Link(from: Endpoint(node: ruled.id, socket: "surface"), to: Endpoint(node: trim.id, socket: "surface"))]
        var nodes = h.nodes
        nodes[ruled.id] = ruled
        func run(_ node: Node) async throws -> EvaluationReport {
            try await Evaluator(registry: registry, kernel: kernel)
                .evaluate(Graph(nodes: nodes, links: links), demand: [trim.id], images: ImageResolver())
        }
        let first = try await run(trim)
        let whole = try #require(first.value(trim, "pieces")?.solids?.first, "\(String(describing: first.state(trim)))")
        #expect(whole.topology.faces.count == 4)
        let negative = whole.topology.faces.filter { $0.centroid.x < 0 }
        #expect(negative.count == 2)
        // A pick of one face of the x < 0 piece (its tags name that face alone).
        let pickedFace = try #require(negative.first)
        let one = try #require(whole.topology.facePick(for: pickedFace.id))
        #expect(whole.topology.faces(matching: one).count == 1)
        nodes[trim.id]?.inputValues[NodeSetting.keepRegions] = .regionPicks([RegionPick(pick: one)])
        let report = try await run(trim)
        #expect(report.isOK(trim), "\(String(describing: report.state(trim)))")
        let kept = try #require(report.value(trim, "surface")?.solids?.first)
        #expect(kept.topology.faces.count == 2)
        #expect(kept.topology.faces.allSatisfy { $0.centroid.x < 0 })
        let expected = negative.reduce(0) { $0 + $1.area }
        #expect(isClose(try await kernel.properties(of: kept).surfaceArea, expected, relative: 1e-6))
    }
}
#endif
