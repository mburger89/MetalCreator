import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// G-b Task 4: the Fillet node's Continuity and tangency weight.
struct FilletContinuityTests {
    /// A box with its four vertical edges selected, feeding a Fillet.
    func filletOnABox(_ values: [SocketName: ConstantValue] = [:]) -> (h: Harness, box: Node, fillet: Node) {
        var h = Harness()
        let box = h.box(10, 20, 30)
        let vertical = h.add(EdgesByDirectionNode.self)
        h.wire(box, "solid", to: vertical, "solid")
        let fillet = h.add(FilletNode.self, values)
        h.wire(vertical, "edges", to: fillet, "edges")
        return (h, box, fillet)
    }

    @Test func aNewFilletIsTangent() async throws {
        let (h, _, fillet) = filletOnABox()
        let kernel = FakeKernel()
        let report = try await h.run([fillet], kernel: kernel)
        #expect(report.isOK(fillet))
        #expect(await kernel.filletProfiles == [.circular])
    }

    @Test func anOldFilletReadsTangent() async throws {
        var (h, _, fillet) = filletOnABox()
        // A node saved before the input existed has neither value.
        h.set(fillet, "continuity", nil)
        h.set(fillet, "tangency weight", nil)
        let kernel = FakeKernel()
        let report = try await h.run([fillet], kernel: kernel)
        #expect(report.isOK(fillet))
        #expect(await kernel.filletProfiles == [.circular])
    }

    @Test func weightIsHiddenForTangent() {
        func controls(_ node: Node) -> [InspectorControl] { FilletNode.inspector(for: node).flatMap(\.controls) }
        var node = BuiltInNodes.registry.makeNode(FilletNode.typeID)
        #expect(!controls(node).contains(.slider("tangency weight")))
        #expect(controls(node).contains(.segmented("continuity", options: ["Tangent (G1)", "Curvature (G2)"])))
        node.inputValues["continuity"] = .integer(1)
        #expect(controls(node).contains(.slider("tangency weight")))
    }

    @Test func curvaturePassesTheWeight() async throws {
        let (h, _, fillet) = filletOnABox(["continuity": .integer(1), "tangency weight": .number(1.4)])
        let kernel = FakeKernel()
        let report = try await h.run([fillet], kernel: kernel)
        #expect(report.isOK(fillet))
        #expect(await kernel.filletProfiles == [.curvatureContinuous(weight: 1.4)])
    }

    @Test func cornerWarningCopy() async throws {
        for (corners, joins, expected) in [
            (1, 0, "1 fillet corner is tangent only (G1)."),
            (3, 0, "3 fillet corners are tangent only (G1)."),
            (0, 1, "1 fillet join is tangent only (G1) where the edges kink."),
            (0, 3, "3 fillet joins are tangent only (G1) where the edges kink."),
        ] {
            let (h, _, fillet) = filletOnABox(["continuity": .integer(1)])
            let kernel = FakeKernel()
            await kernel.setFilletTangentOnly(corners: corners, joins: joins)
            let report = try await h.run([fillet], kernel: kernel)
            #expect(report.warning(fillet) == expected)
        }
    }

    #if canImport(CreatorOCCT)
    /// The Edges by Tag rule on the fillet's blend faces and the box's top cap, resolved against `solid`.
    func blendTopEdges(_ solid: Solid, box: Node, fillet: Node) -> [EdgeID] {
        let blend = solid.topology.faces.flatMap(\.tags).first { $0.node == fillet.id }
        guard let blend else { return [] }
        let top = TopoTag(node: box.id, item: 0, role: .endCap)
        return solid.topology.edges(matching: EdgeKey([blend], [top])).map(\.id)
    }

    @Test func switchingContinuityKeepsADownstreamPick() async throws {
        let kernel = OCCTKernel()
        var (h, box, fillet) = filletOnABox(["radius": .number(2)])
        let rule = h.add(EdgesByTagNode.self)
        h.wire(fillet, "solid", to: rule, "solid")
        let first = try await h.run([fillet], kernel: kernel)
        let solid = try onlySolid(first, fillet)
        let picked = blendTopEdges(solid, box: box, fillet: fillet)
        #expect(!picked.isEmpty)
        h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: picked)))
        let chamfer = h.add(ChamferNode.self, ["distance": .number(0.2)])
        h.wire(rule, "edges", to: chamfer, "edges")

        let tangent = try await h.run([chamfer], kernel: kernel)
        let tangentSet = try #require(tangent.value(rule, "edges")?.edgeSets?.first)
        #expect(tangentSet.edges.count == picked.count)
        #expect(tangent.state(rule).map { if case .ok = $0 { true } else { false } } == true)

        h.set(fillet, "continuity", .integer(1))
        let curved = try await h.run([chamfer], kernel: kernel)
        let curvedSet = try #require(curved.value(rule, "edges")?.edgeSets?.first)
        #expect(curvedSet.edges.count == picked.count)
        #expect(curved.state(rule).map { if case .ok = $0 { true } else { false } } == true, "\(String(describing: curved.state(rule)))")
        #expect(curved.error(chamfer) == tangent.error(chamfer))
    }
    #endif
}
