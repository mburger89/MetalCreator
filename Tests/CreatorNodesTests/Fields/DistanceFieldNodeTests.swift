import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Distance Field (fields spec §3.1): a point, edges, a profile, faces or a solid; signed for a solid, negative inside.
struct DistanceFieldNodeTests {
    func direct(_ target: Scalar?, mode: Int = 1) async throws -> NodeOutputs {
        var slots: [SocketName: NodeInputs.Slot] = ["mode": .item(.integer(mode))]
        if let target { slots["target"] = .item(target) }
        let node = BuiltInNodes.registry.makeNode(DistanceFieldNode.typeID)
        return try await DistanceFieldNode.evaluate(NodeInputs(item: 0, slots: slots), kernel: FakeKernel(),
                                                    context: EvalContext(node: node, item: 0, parameters: [:]))
    }

    func message(_ target: Scalar?) async -> String? {
        do {
            _ = try await direct(target)
            return nil
        } catch {
            return Evaluator.message(for: error)
        }
    }

    // MARK: through the evaluator

    @Test func aSolidIsSignedByDefaultAndNegativeInside() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let distance = h.add(DistanceFieldNode.self)
        h.wire(box, "solid", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.field(distance)?.description == "distance(solid)")
        let found = try await sampled(report.field(distance), at: [Vector3(0, 0, 5), Vector3(5, 0, 5), Vector3(8, 0, 5)])
        #expect(found == [-5, 0, 3])
    }

    @Test func unsignedMeasuresToTheSurfaceFromInside() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let distance = h.add(DistanceFieldNode.self, ["mode": .integer(0)])
        h.wire(box, "solid", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.field(distance)?.description == "distance(solid, unsigned)")
        #expect(try await sampled(report.field(distance), at: [Vector3(0, 0, 5), Vector3(8, 0, 5)]) == [5, 3])
    }

    @Test func aPointIsMeasuredInPlainMaths() async throws {
        var h = Harness()
        let point = h.add(VectorNode.self, ["x": .number(1), "y": .number(2), "z": .number(3)])
        let distance = h.add(DistanceFieldNode.self)
        h.wire(point, "vector", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.field(distance)?.description == "distance(point)")
        #expect(try await sampled(report.field(distance), at: [Vector3(4, 6, 3)]) == [5], "signed is ignored for a point")
    }

    @Test func aProfileIsMeasuredToItsLoops() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self, ["width": .number(10), "height": .number(10)])
        let distance = h.add(DistanceFieldNode.self)
        h.wire(rectangle, "profile", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.field(distance)?.description == "distance(profile)")
        #expect(try await sampled(report.field(distance), at: [Vector3(0, 0, 0), Vector3(8, 0, 0)]) == [5, 3])
    }

    @Test func anEdgeSetIsMeasuredToItsEdgesAndSignedIsIgnored() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let edges = h.add(AllEdgesNode.self)
        let distance = h.add(DistanceFieldNode.self)  // Signed, the default
        h.wire(box, "solid", to: edges, "solid")
        h.wire(edges, "edges", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.isOK(distance))
        #expect(report.field(distance)?.description == "distance(edges)")
        let found = try await sampled(report.field(distance), at: [Vector3(0, 0, 5)])
        #expect(abs(found[0] - 50.0.squareRoot()) < 1e-12, "the cube's centre is 5√2 from its nearest edge")
    }

    // MARK: refusals

    @Test func withoutATargetTheNodeSaysWhatToWire() async throws {
        var h = Harness()
        let distance = h.add(DistanceFieldNode.self)
        let report = try await h.run([distance])
        #expect(report.error(distance) == "Distance Field needs a target: wire a point, edges, a profile, faces or a solid.")
    }

    @Test func aNumberIsNotATarget() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self)
        let distance = h.add(DistanceFieldNode.self)
        h.wire(number, "value", to: distance, "target")
        let report = try await h.run([distance])
        #expect(report.error(distance) == "Distance Field can't measure from a number: wire a point, edges, a profile, faces or a solid.")
    }

    @Test func anOutOfRangeModeIsRefused() async throws {
        #expect(await message(.vector(.zero)) == nil)
        do {
            _ = try await direct(.vector(.zero), mode: 7)
            Issue.record("expected a refusal")
        } catch {
            #expect(Evaluator.message(for: error) == "Choose Unsigned or Signed for “mode”.")
        }
    }

    @Test func emptySelectionsBadPointsAndBlankProfilesAreRefusedInWords() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        let nothing = "are empty: there is nothing to measure from."
        #expect(await message(.edgeSet(EdgeSet(solid: solid, edges: []))) == "Distance Field's edges \(nothing)")
        #expect(await message(.faceSet(FaceSet(solid: solid, faces: []))) == "Distance Field's faces \(nothing)")
        #expect(await message(.vector(Vector3(.nan, 0, 0))) == "Distance Field's point isn't a finite position.")
        #expect(await message(.profile(Profile2D(plane: .xy, outer: []))) == "Distance Field's profile has no outline.")
        #expect(await message(.edgeSet(EdgeSet(solid: solid, edges: [EdgeID(500)]))) == "A selected edge doesn't exist on the solid.")
        #expect(await message(.faceSet(FaceSet(solid: solid, faces: [FaceID(500)]))) == "A selected face doesn't exist on the solid.")
        #expect(await message(.faceSet(FaceSet(solid: solid, faces: [FaceID(0)]))) == nil)
    }

    #if canImport(CreatorOCCT)
    // MARK: faces, on OCCT

    @Test func aFaceSetIsMeasuredToThoseFacesOnOCCT() async throws {
        let kernel = OCCTKernel()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && ($0.normal?.z ?? 0) > 0.5 })
        let outputs = try await direct(.faceSet(FaceSet(solid: solid, faces: [top.id])))
        guard case .field(let field)? = outputs.values["field"] else {
            Issue.record("no field")
            return
        }
        #expect(field.description == "distance(faces)")
        let found = try await FieldSampler.sample(field, at: [Vector3(1, 2, 3), Vector3(0, 0, 10)], kernel: kernel)
        #expect(abs(found[0] - 7) < 1e-7 && abs(found[1]) < 1e-7)
    }
    #endif
}
