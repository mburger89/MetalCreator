import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// A bridge needs no profile, and the loft's face-pick warnings read as Face Pattern's and Plane from Face's do.
struct LoftBridgeAndWordingTests {
    func pick(_ box: Node, _ role: TopoRole) -> ConstantValue {
        .facePick(FacePick(tags: [TopoTag(node: box.id, item: 0, role: role)]))
    }

    @Test func theSharedWordingIsTheOtherNodesText() {
        #expect(LoftEndSetup.unnamedPick == FacePickWording.unnamed("loft"))
        #expect(LoftEndSetup.mergedPick == FacePickWording.merged("The loft uses"))
        #expect(PlaneFromFaceNode.mergedPick == FacePickWording.merged("The plane sits on"))
        #expect(FacePatternNode.mergedPick == FacePickWording.merged("The pattern fills"))
        #expect(LoftEndSetup.mergedPick.hasPrefix("The picked face was merged with a face from another part of the model"))
        #expect(LoftEndSetup.unnamedPick.hasSuffix("when the model changes. Pick it again after the change."))
        #expect(FacePickWording.several(3, "the loft uses") == "The pick matches 3 faces; the loft uses the first.")
    }

    #if canImport(CreatorOCCT)
    @Test func aSingleFaceWithNoProfileIsRefusedInTheOldWords() async throws {
        var h = Harness()
        let box = h.box(20, 20, 10)
        let loft = h.add(LoftNode.self, [NodeSetting.startFace: pick(box, .endCap)])
        h.wire(box, "solid", to: loft, "solid")
        let message = try #require(try await h.run([loft], kernel: OCCTKernel()).error(loft))
        #expect(message.contains("at least two sections"))
    }

    @Test func aBridgeBetweenTwoBoxesNeedsNoProfileAndJoinsAtG2() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let lower = h.box(20, 20, 10)
        let upper = h.box(14, 14, 10, at: Vector3(0, 0, 30))
        let both = h.add(BooleanNode.self)
        h.wire(lower, "solid", to: both, "target")
        h.wire(upper, "solid", to: both, "tools")
        let loft = h.add(LoftNode.self, [
            NodeSetting.startFace: pick(lower, .endCap), NodeSetting.endFace: pick(upper, .startCap),
            "startContinuity": .integer(2), "endContinuity": .integer(2),
        ])
        h.wire(both, "solid", to: loft, "solid")
        let union = h.add(BooleanNode.self)
        h.wire(both, "solid", to: union, "target")
        h.wire(loft, "solid", to: union, "tools")
        let report = try await h.run([union], kernel: kernel)
        #expect(report.error(loft) == nil && report.error(union) == nil, "\(String(describing: report.state(loft)))")
        let joined = try onlySolid(report, union)
        let joint = joined.topology.edges.filter { edge in
            let reach = max(abs(edge.midpoint.x), abs(edge.midpoint.y))
            return (abs(edge.midpoint.z - 10) < 1e-6 && abs(reach - 10) < 1e-6)
                || (abs(edge.midpoint.z - 30) < 1e-6 && abs(reach - 7) < 1e-6)
        }
        #expect(joint.count == 8)
        for edge in joint { #expect(try await kernel.continuity(along: edge.id, of: joined).grade == .g2) }
    }

    @Test func aLoftFaceOnAHoleThatIsGoneNamesTheHole() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate()
        let rings = plate.h.add(CircularPatternNode.self, ["count": .integer(4), "radius": .number(10), "rings": .integer(2)])
        let holes = plate.h.add(HolePatternNode.self, ["diameter": .number(4), "depth": .number(3)])
        plate.h.wire(plate.plate, "solid", to: holes, "part")
        plate.h.wire(rings, "placements", to: holes, "placements")
        let drilled = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
        let qualifier = NodeID.instanceScoped([holes.id, holes.id])
        let item = try #require(InstancePath.item(for: [1, 2]))
        let floor = try #require(drilled.topology.faces.first { face in
            face.kind == .plane && face.normal == .unitZ && abs(face.centroid.z + 3) < 1e-6
                && face.tags.contains { $0.node == qualifier && $0.item == item }
        })
        let square = plate.h.add(RectangleNode.self, ["width": .number(2), "height": .number(2),
                                                      "plane": .plane(.through(Vector3(0, 0, 10))),
                                                      ])
        let loft = plate.h.add(LoftNode.self, [NodeSetting.startFace: .facePick(try #require(drilled.topology.facePick(for: floor.id)))])
        plate.h.wire(square, "profile", to: loft, "sections")
        plate.h.wire(holes, "solid", to: loft, "solid")
        plate.h.set(rings, "rings", .integer(1))
        let report = try await plate.h.run([loft], kernel: kernel)
        #expect(report.error(loft) ==
            "Instance {1;2} no longer exists, so the loft's start face isn't there any more. Pick the face again.")
    }
    #endif
}
