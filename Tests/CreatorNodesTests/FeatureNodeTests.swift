import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

struct FeatureNodeTests {
    /// A 10 × 20 × 30 box with its four vertical edges selected, feeding `feature`.
    func verticalEdgesOfABox(_ h: inout Harness, into feature: any NodeDefinition.Type,
                             _ values: [SocketName: ConstantValue]) -> Node {
        let box = h.box(10, 20, 30)
        let vertical = h.add(EdgesByDirectionNode.self)
        h.wire(box, "solid", to: vertical, "solid")
        let node = h.add(feature, values)
        h.wire(vertical, "edges", to: node, "edges")
        return node
    }

    @Test func filletRemovesTheAnalyticVolumeAndNamesBlends() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let fillet = verticalEdgesOfABox(&h, into: FilletNode.self, ["radius": .number(2)])
        let report = try await h.run([fillet], kernel: kernel)
        let solid = try onlySolid(report, fillet)
        #expect(isClose(try await volume(solid, kernel), 6000 - 4 * (4 - Double.pi) * 30))
        let blends = solid.topology.faces.filter { $0.tags.contains { $0.node == fillet.id } }
        #expect(blends.count == 4)
        #expect(report.isOK(fillet))
    }

    @Test func chamferRemovesTheAnalyticVolume() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let chamfer = verticalEdgesOfABox(&h, into: ChamferNode.self, ["distance": .number(1)])
        let solid = try onlySolid(try await h.run([chamfer], kernel: kernel), chamfer)
        #expect(isClose(try await volume(solid, kernel), 6000 - 4 * 0.5 * 30))
    }

    @Test func anImpossibleRadiusIsAPlainErrorAndTheNextValueWorks() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let fillet = verticalEdgesOfABox(&h, into: FilletNode.self, ["radius": .number(40)])
        let failed = try await h.run([fillet], kernel: kernel)
        let message = try #require(failed.error(fillet))
        #expect(message.contains("40"))
        #expect(!message.contains("occt"))
        h.set(fillet, "radius", .number(1))
        #expect(try await h.run([fillet], kernel: kernel).isOK(fillet))
    }

    @Test func anEmptyEdgeSetIsExplained() async throws {
        var h = Harness()
        let cylinder = h.add(CircleNode.self)
        let extrude = h.add(ExtrudeNode.self)
        h.wire(cylinder, "profile", to: extrude, "profile")
        let vertical = h.add(EdgesByDirectionNode.self)
        h.wire(extrude, "solid", to: vertical, "solid")
        let fillet = h.add(FilletNode.self)
        h.wire(vertical, "edges", to: fillet, "edges")
        let report = try await h.run([fillet], kernel: OCCTKernel())
        #expect(report.warning(vertical) == "This rule matched no edges.")
        #expect(report.error(fillet) == "No edges are selected.")
    }

    @Test func handlesAndInspectorMatchTheSpec() {
        #expect(FilletNode.handles == [.radial("radius")])
        #expect(ChamferNode.handles == [.radial("distance")])
        #expect(ExtrudeNode.handles == [.linear("distance")])
        let controls = FilletNode.inspector.flatMap(\.controls)
        #expect(controls.contains(.button(title: "Pick edges in view…", action: .pickEdgesInView)))
        #expect(controls.contains(.ruleSummary("edges")))
        #expect(controls.contains(.toggle(NodeSetting.showHandle, label: "Show handle in view")))
        // Seeded at creation, so M5's binding (`inputValues[socket] ?? spec?.defaultValue`) shows "on".
        for definition in [FilletNode.self, ChamferNode.self] as [any NodeDefinition.Type] {
            #expect(BuiltInNodes.registry.makeNode(definition.typeID).inputValues[NodeSetting.showHandle] == .bool(true))
        }
    }
}
