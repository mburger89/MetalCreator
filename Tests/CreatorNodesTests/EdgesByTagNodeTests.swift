import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

struct EdgesByTagNodeTests {
    /// A 30 × 10 × 10 bar minus a 4 × 4 notch tool placed by a Vector node (initially far away),
    /// with an Edges by Tag rule on the result.
    struct Notched {
        var h = Harness()
        let barProfile: Node
        let notchPosition: Node
        let bar: Node
        let cut: Node
        let rule: Node

        init() {
            barProfile = h.add(RectangleNode.self, ["width": .number(30), "height": .number(10)])
            bar = h.add(ExtrudeNode.self, ["distance": .number(10)])
            h.wire(barProfile, "profile", to: bar, "profile")
            notchPosition = h.add(VectorNode.self, ["x": .number(100)])
            let notchProfile = h.add(RectangleNode.self, ["width": .number(4), "height": .number(4)])
            h.wire(notchPosition, "vector", to: notchProfile, "plane")
            let notch = h.add(ExtrudeNode.self, ["distance": .number(30), "mode": .integer(1)])
            h.wire(notchProfile, "profile", to: notch, "profile")
            cut = h.add(BooleanNode.self, ["operation": .integer(1)])
            h.wire(bar, "solid", to: cut, "target")
            h.wire(notch, "solid", to: cut, "tools")
            rule = h.add(EdgesByTagNode.self)
            h.wire(cut, "solid", to: rule, "solid")
        }
    }

    /// The edges between the bar's top cap and its front side (segment 0, at y = −5).
    func topFrontEdges(_ solid: Solid, bar: Node) -> [EdgeID] {
        let top = TopoTag(node: bar.id, item: 0, role: .endCap)
        let front = TopoTag(node: bar.id, item: 0, role: .side(segment: 0))
        return solid.topology.edges(matching: EdgeKey([top], [front])).map(\.id)
    }

    @Test func pickedEdgesSurviveAnUnrelatedChange() async throws {
        var notched = Notched()
        let first = try await notched.h.run([notched.rule], kernel: OCCTKernel())
        let solid = try onlySolid(first, notched.cut)
        let picked = topFrontEdges(solid, bar: notched.bar)
        #expect(picked.count == 1)
        notched.h.set(notched.rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: picked)))
        let firstPick = try await notched.h.run([notched.rule], kernel: OCCTKernel())
        #expect(firstPick.isOK(notched.rule))

        notched.h.set(notched.barProfile, "width", .number(50))
        let wider = try await notched.h.run([notched.rule], kernel: OCCTKernel())
        let set = try #require(wider.value(notched.rule, "edges")?.edgeSets?.first)
        #expect(set.edges.count == 1)
        #expect(isClose(try #require(set.solid.topology.edge(set.edges[0])).length, 50))
        #expect(wider.isOK(notched.rule))
    }

    @Test func aSplitEdgeWarnsAndKeepsBothPieces() async throws {
        var notched = Notched()
        let first = try await notched.h.run([notched.rule], kernel: OCCTKernel())
        let solid = try onlySolid(first, notched.cut)
        notched.h.set(notched.rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: topFrontEdges(solid, bar: notched.bar))))
        notched.h.set(notched.notchPosition, "x", .number(0))
        notched.h.set(notched.notchPosition, "y", .number(-5))
        let split = try await notched.h.run([notched.rule], kernel: OCCTKernel())
        #expect(split.warning(notched.rule) == "Matched 2 edges, expected 1.")
        #expect(split.value(notched.rule, "edges")?.edgeSets?.first?.edges.count == 2)
    }

    @Test func noPicksAsksForOne() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let rule = h.add(EdgesByTagNode.self)
        h.wire(box, "solid", to: rule, "solid")
        let report = try await h.run([rule])
        #expect(report.warning(rule) == "Pick edges in view to fill this rule.")
        #expect(report.value(rule, "edges")?.edgeSets?.first?.edges == [])
    }

    @Test func anUnreadableSettingIsAnError() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let rule = h.add(EdgesByTagNode.self, [NodeSetting.picks: .text("garbage")])
        h.wire(box, "solid", to: rule, "solid")
        #expect(try await h.run([rule]).error(rule) == "This rule's picked edges can't be read. Pick the edges again.")
    }
}
