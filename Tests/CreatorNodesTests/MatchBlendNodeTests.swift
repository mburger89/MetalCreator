import Foundation
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// NS-4 Task 10: the Match Surface and Blend Surface nodes.
struct MatchBlendNodeTests {
    @Test func theNodesSitInTheEditSection() {
        #expect(MatchSurfaceNode.typeID == "creator.matchSurface" && BlendSurfaceNode.typeID == "creator.blendSurface")
        #expect(MatchSurfaceNode.category == .surface && MatchSurfaceNode.librarySubgroup == "Edit")
        #expect(BlendSurfaceNode.category == .surface && BlendSurfaceNode.librarySubgroup == "Edit")
        #expect(MatchSurfaceNode.inputs.map(\.name) == ["edges", "target", "continuity"])
        #expect(BlendSurfaceNode.inputs.map(\.name)
            == ["edges", "other edges", "continuity", "other continuity", "bulge", "other bulge"])
        #expect(MatchSurfaceNode.outputs.map(\.name) == ["surface"] && BlendSurfaceNode.outputs.map(\.name) == ["surface"])
        #expect(MatchSurfaceNode.continuityOptions == ["G0", "G1", "G2"] && BlendSurfaceNode.continuityOptions == ["G1", "G2"])
        #expect(MatchSurfaceNode.inputs[2].defaultValue == .integer(1) && BlendSurfaceNode.inputs[2].defaultValue == .integer(0))
    }

    @Test func theInspectorsOfferTheControlsAndThePicks() {
        let match = MatchSurfaceNode.inspector.flatMap(\.controls)
        #expect(match.contains(.segmented("continuity", options: ["G0", "G1", "G2"])))
        #expect(match.contains(.ruleSummary("edges")) && match.contains(.ruleSummary("target")))
        #expect(match.contains(.button(title: "Pick edge in view…", action: .pickEdgesInView)))
        #expect(match.contains(.button(title: "Pick target edge in view…", action: .pickTargetEdgesInView)))
        let blend = BlendSurfaceNode.inspector.flatMap(\.controls)
        #expect(blend.contains(.ruleSummary("edges")) && blend.contains(.ruleSummary("other edges")))
        #expect(blend.contains(.button(title: "Pick edge in view…", action: .pickEdgesInView)))
        #expect(blend.contains(.button(title: "Pick other edge in view…", action: .pickOtherEdgesInView)))
    }

    @Test func matchReadsScrubbingOnlyAtG2() {
        for (grade, reads) in [(0, false), (1, false), (2, true)] {
            var node = BuiltInNodes.registry.makeNode(MatchSurfaceNode.typeID)
            node.inputValues["continuity"] = .integer(grade)
            #expect(MatchSurfaceNode.readsScrubbing(for: node) == reads, "G\(grade)")
        }
    }

    @Test func blendReadsScrubbingOnlyWithAG2Side() {
        for (first, second, reads) in [(0, 0, false), (1, 0, true), (0, 1, true), (1, 1, true)] {
            var node = BuiltInNodes.registry.makeNode(BlendSurfaceNode.typeID)
            node.inputValues["continuity"] = .integer(first)
            node.inputValues["other continuity"] = .integer(second)
            #expect(BlendSurfaceNode.readsScrubbing(for: node) == reads, "\(first) \(second)")
        }
    }

    /// Two boxes and one picked edge of each, wired into `node` (`names` are its two edge sockets), for the fake kernel's recording.
    func boxRig(_ definition: any NodeDefinition.Type, _ names: (SocketName, SocketName),
                _ values: [SocketName: ConstantValue]) async throws -> (h: Harness, node: Node) {
        var h = Harness()
        let node = h.add(definition, values)
        for (index, socket) in [names.0, names.1].enumerated() {
            let box = h.box(10, 10, 10, at: Vector3(Double(index) * 20, 0, 0))
            let report = try await h.run([box])
            let solid = try #require(report.value(box, "solid")?.solids?.first)
            let rule = h.add(EdgesByTagNode.self, [NodeSetting.picks: .edgePicks(solid.topology.picks(for: [solid.topology.edges[0].id]))])
            h.wire(box, "solid", to: rule, "solid")
            h.wire(rule, "edges", to: node, socket)
        }
        return (h, node)
    }

    @Test(arguments: [(2, true, PatchContinuity.g1), (2, false, .g2), (1, true, .g1), (0, false, .g0)])
    func matchAsksTheKernelForTheRightGrade(chosen: Int, scrubbing: Bool, asked: PatchContinuity) async throws {
        let (h, node) = try await boxRig(MatchSurfaceNode.self, ("edges", "target"), ["continuity": .integer(chosen)])
        let fake = FakeKernel()
        _ = try await Evaluator(registry: BuiltInNodes.registry, kernel: fake)
            .evaluate(h.graph, demand: [node.id], isScrubbing: scrubbing)
        #expect(await fake.matchContinuities == [asked])
    }

    @Test(arguments: [(1, true, PatchContinuity.g1), (1, false, .g2), (0, false, .g1)])
    func blendAsksTheKernelForTheRightGrade(chosen: Int, scrubbing: Bool, asked: PatchContinuity) async throws {
        let (h, node) = try await boxRig(BlendSurfaceNode.self, ("edges", "other edges"),
                                         ["continuity": .integer(chosen), "other continuity": .integer(0)])
        let fake = FakeKernel()
        _ = try await Evaluator(registry: BuiltInNodes.registry, kernel: fake)
            .evaluate(h.graph, demand: [node.id], isScrubbing: scrubbing)
        #expect(await fake.blendContinuities == [[asked, .g1]])
    }

    #if canImport(CreatorOCCT)
    let kernel = OCCTKernel()

    /// A, a 10 x 10 sheet in z = 0 centred on the origin; B, a 10 x 10 sheet that shares A's edge at x = 5 and leaves it along
    /// `degrees` from +x (180 degrees is A's own plane continued the other way, 150 folds back over A).
    struct Rig {
        var h = Harness()
        var a: Node, b: Node, node: Node
        var aEdges: Node, bEdges: Node
        let aEdge: EdgeInfo, bEdge: EdgeInfo
    }

    func makeRig(_ definition: any NodeDefinition.Type = MatchSurfaceNode.self, degrees: Double = 150, gap: Double = 0,
                 allOnA: Bool = false, allOnB: Bool = false, values: [SocketName: ConstantValue] = [:],
                 second: String = "target") async throws -> Rig {
        var h = Harness()
        let rectA = h.add(RectangleNode.self, ["width": .number(10), "height": .number(10)])
        let a = h.add(PlanarSurfaceNode.self)
        h.wire(rectA, "profile", to: a, "curves")
        let first = try await h.run([a], kernel: kernel)
        let sheetA = try #require(first.value(a, "surface")?.solids?.first)
        let aEdge = try #require(sheetA.topology.edges.max { $0.midpoint.x < $1.midpoint.x })
        let direction = Vector3(cos(degrees * .pi / 180), 0, sin(degrees * .pi / 180))
        let normal = direction.cross(Vector3(0, 1, 0))
        let rectB = h.add(RectangleNode.self, [
            "width": .number(10), "height": .number(10),
            "plane": .plane(Plane(origin: aEdge.midpoint + direction * (5 + gap), normal: normal, xAxis: direction)),
        ])
        let b = h.add(PlanarSurfaceNode.self)
        h.wire(rectB, "profile", to: b, "curves")
        let second2 = try await h.run([b], kernel: kernel)
        let sheetB = try #require(second2.value(b, "surface")?.solids?.first)
        let bEdge = try #require(sheetB.topology.edges.first { ($0.midpoint - (aEdge.midpoint + direction * gap)).length < 1e-6 })
        let aEdges = allOnA ? h.add(AllEdgesNode.self)
            : h.add(EdgesByTagNode.self, [NodeSetting.picks: .edgePicks(sheetA.topology.picks(for: [aEdge.id]))])
        h.wire(a, "surface", to: aEdges, "solid")
        let bEdges = allOnB ? h.add(AllEdgesNode.self)
            : h.add(EdgesByTagNode.self, [NodeSetting.picks: .edgePicks(sheetB.topology.picks(for: [bEdge.id]))])
        h.wire(b, "surface", to: bEdges, "solid")
        let node = h.add(definition, values)
        h.wire(aEdges, "edges", to: node, "edges")
        h.wire(bEdges, "edges", to: node, SocketName(second))
        return Rig(h: h, a: a, b: b, node: node, aEdges: aEdges, bEdges: bEdges, aEdge: aEdge, bEdge: bEdge)
    }

    func solid(_ report: EvaluationReport, _ node: Node, _ socket: SocketName = "surface") throws -> Solid {
        try #require(report.value(node, socket)?.solids?.first, "\(String(describing: report.error(node)))")
    }

    @Test func matchNodeMatches() async throws {
        let rig = try await makeRig(degrees: 135, values: ["continuity": .integer(1)])
        let report = try await rig.h.run([rig.node], kernel: kernel)
        #expect(report.isOK(rig.node), "\(String(describing: report.error(rig.node)))")
        let result = try solid(report, rig.node)
        #expect(result.hasOpenShell && result.topology.faces.count == 1)
        let target = try solid(report, rig.b)
        let edge = try #require(result.topology.edges.first { ($0.midpoint - rig.aEdge.midpoint).length < 1e-6 })
        let found = try await kernel.continuity(of: edge.id, in: result, against: FaceID(0), of: target)
        #expect(found.grade >= .g1, "angle \(found.angleGap)")
    }

    @Test func matchCountsEdges() async throws {
        let mine = try await makeRig(degrees: 135, allOnA: true)
        let first = try await mine.h.run([mine.node], kernel: kernel)
        #expect(first.error(mine.node) == "Match Surface takes one edge to change; “edges” gives 4.")
        let theirs = try await makeRig(degrees: 135, allOnB: true)
        let second = try await theirs.h.run([theirs.node], kernel: kernel)
        #expect(second.error(theirs.node) == "Match Surface takes one target edge; “target” gives 4.")
    }

    /// The same evaluator over a graph, scrubbing or not.
    func evaluate(_ rig: Rig, _ evaluator: Evaluator, scrubbing: Bool) async throws -> EvaluationReport {
        try await evaluator.evaluate(rig.h.graph, demand: [rig.node.id], isScrubbing: scrubbing)
    }

    @Test func matchBuildsG1WhileScrubbing() async throws {
        let rig = try await makeRig(degrees: 135, values: ["continuity": .integer(2)])
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        let dragging = try await evaluate(rig, evaluator, scrubbing: true)
        #expect(dragging.isOK(rig.node) && dragging.warning(rig.node) == nil, "\(String(describing: dragging.error(rig.node)))")
        let released = try await evaluate(rig, evaluator, scrubbing: false)
        #expect(released.evaluatedNodes.contains(rig.node.id))
        #expect(released.isOK(rig.node))
    }

    /// 165 degrees is a smooth hairpin: the normal turns through it without ever vanishing, so it is no fold (R10).
    @Test func aSmoothHairpinIsNotAFold() async throws {
        let rig = try await makeRig(degrees: 165, values: ["continuity": .integer(1)])
        let report = try await rig.h.run([rig.node], kernel: kernel)
        #expect(report.isOK(rig.node) && report.warning(rig.node) == nil, "\(String(describing: report.state(rig.node)))")
        #expect(try await kernel.folds(solid(report, rig.node)) == false)
    }
    #endif

    /// The fake kernel hands back the sheet and says it folds, so these test the node's timing around the warning alone (a
    /// Match cannot be made to fold for real: its result bends smoothly, `FoldConfirmationTests` holds a true fold).
    func foldRig(grade: Int) async throws -> (rig: (h: Harness, node: Node), fake: FakeKernel, evaluator: Evaluator) {
        let rig = try await boxRig(MatchSurfaceNode.self, ("edges", "target"), ["continuity": .integer(grade)])
        let fake = FakeKernel()
        await fake.setMatchPassThrough(folds: true)
        return (rig, fake, Evaluator(registry: BuiltInNodes.registry, kernel: fake))
    }

    func run(_ rig: (h: Harness, node: Node), _ evaluator: Evaluator, scrubbing: Bool) async throws -> EvaluationReport {
        try await evaluator.evaluate(rig.h.graph, demand: [rig.node.id], isScrubbing: scrubbing)
    }

    @Test func aG1FoldWarnsAfterADrag() async throws {
        let (rig, _, evaluator) = try await foldRig(grade: 1)
        let dragging = try await run(rig, evaluator, scrubbing: true)
        #expect(dragging.warning(rig.node) == EditSurfaceNode.foldWarning, "\(String(describing: dragging.state(rig.node)))")
        let released = try await run(rig, evaluator, scrubbing: false)
        #expect(!released.evaluatedNodes.contains(rig.node.id))
        #expect(released.warning(rig.node) == EditSurfaceNode.foldWarning)
    }

    @Test func aG2FoldWarnsOnlyAfterTheFlagClears() async throws {
        let (rig, _, evaluator) = try await foldRig(grade: 2)
        let dragging = try await run(rig, evaluator, scrubbing: true)
        #expect(dragging.isOK(rig.node) && dragging.warning(rig.node) == nil, "\(String(describing: dragging.state(rig.node)))")
        let released = try await run(rig, evaluator, scrubbing: false)
        #expect(released.evaluatedNodes.contains(rig.node.id))
        #expect(released.warning(rig.node) == EditSurfaceNode.foldWarning, "\(String(describing: released.state(rig.node)))")
    }

    #if canImport(CreatorOCCT)
    @Test func blendNodeBlends() async throws {
        let rig = try await makeRig(BlendSurfaceNode.self, degrees: 0, gap: 4, second: "other edges")
        let report = try await rig.h.run([rig.node], kernel: kernel)
        #expect(report.isOK(rig.node), "\(String(describing: report.error(rig.node)))")
        let result = try solid(report, rig.node)
        #expect(result.hasOpenShell && result.topology.faces.count == 1)
        #expect(result.topology.faces[0].tags.contains { $0.role == .side(loop: 0, segment: 0) })
    }

    @Test func blendTakesOneEdgeEachSide() async throws {
        let rig = try await makeRig(BlendSurfaceNode.self, degrees: 0, gap: 4, allOnA: true, second: "other edges")
        let report = try await rig.h.run([rig.node], kernel: kernel)
        #expect(report.error(rig.node) == "Blend Surface takes one edge on each side; “edges” gives 4.")
        let other = try await makeRig(BlendSurfaceNode.self, degrees: 0, gap: 4, allOnB: true, second: "other edges")
        let second = try await other.h.run([other.node], kernel: kernel)
        #expect(second.error(other.node) == "Blend Surface takes one edge on each side; “other edges” gives 4.")
    }

    @Test func blendBuildsG1WhileScrubbing() async throws {
        let rig = try await makeRig(BlendSurfaceNode.self, degrees: 0, gap: 4,
                                values: ["continuity": .integer(1), "other continuity": .integer(1)],
                                second: "other edges")
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        let dragging = try await evaluate(rig, evaluator, scrubbing: true)
        #expect(dragging.isOK(rig.node) && dragging.warning(rig.node) == nil, "\(String(describing: dragging.error(rig.node)))")
        let released = try await evaluate(rig, evaluator, scrubbing: false)
        #expect(released.evaluatedNodes.contains(rig.node.id))
        #expect(released.isOK(rig.node))
    }
    #endif
}
