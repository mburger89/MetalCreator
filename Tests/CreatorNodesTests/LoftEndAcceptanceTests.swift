#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Loft end conditions through the real Evaluator on OpenCascade: a box, a Loft that leaves its top face at Curvature, one smaller
/// square section, and a Boolean union; the joint reads G2 on all four top edges.
struct LoftEndAcceptanceTests {
    /// Returns the harness, the Loft and the union, with the box's top picked by the loft's start.
    func rig(continuity: Int, weight: Double = 1) -> (Harness, Node, Node) {
        var h = Harness()
        let box = h.box(20, 20, 10)
        let square = h.add(RectangleNode.self, ["width": .number(12), "height": .number(12),
                                                "plane": .plane(.through(Vector3(0, 0, 20))),
        ])
        let loft = h.add(LoftNode.self, [
            NodeSetting.startFace: .facePick(FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])),
            "startContinuity": .integer(continuity), "startWeight": .number(weight),
        ])
        h.wire(square, "profile", to: loft, "sections")
        h.wire(box, "solid", to: loft, "solid")
        let union = h.add(BooleanNode.self)
        h.wire(box, "solid", to: union, "target")
        h.wire(loft, "solid", to: union, "tools")
        return (h, loft, union)
    }

    func topEdges(of solid: Solid) -> [EdgeInfo] {
        solid.topology.edges.filter { abs($0.midpoint.z - 10) < 1e-6 && abs(max(abs($0.midpoint.x), abs($0.midpoint.y)) - 10) < 1e-6 }
    }

    @Test(arguments: [(1, ContinuityClass.g1), (2, .g2)])
    func theJointReadsTheGradeAskedFor(_ asked: (Int, ContinuityClass)) async throws {
        let kernel = OCCTKernel()
        let (h, loft, union) = rig(continuity: asked.0)
        let report = try await h.run([union], kernel: kernel)
        #expect(report.error(loft) == nil && report.error(union) == nil, "\(String(describing: report.state(loft)))")
        let joined = try onlySolid(report, union)
        let joint = topEdges(of: joined)
        #expect(joint.count == 4)
        for edge in joint {
            let grade = try await kernel.continuity(along: edge.id, of: joined).grade
            #expect(grade == asked.1)
        }
    }

    @Test func freeContinuityWithAFaceKeepsTheCreaseAndBuildsLikeAPlainLoft() async throws {
        let kernel = OCCTKernel()
        let (h, loft, _) = rig(continuity: 0)
        let report = try await h.run([loft], kernel: kernel)
        let built = try onlySolid(report, loft)
        #expect(built.topology.faces.count == 6)
        let plain = try await kernel.loft(
            [.rectangle(width: 20, height: 20, plane: Plane.xy.offset(by: 10)),
             .rectangle(width: 12, height: 12, plane: Plane.xy.offset(by: 20)),
            ], ruled: false, tag: NodeTag(node: NodeID(), item: 0))
        #expect(isClose(try await volume(built, kernel), try await volume(plain, kernel), relative: 1e-6))
    }

    @Test func theWeightBulgesTheSideMonotonically() async throws {
        let kernel = OCCTKernel()
        var bulges: [Double] = []
        for weight in [0.1, 1, 2] {
            let (h, loft, _) = rig(continuity: 1, weight: weight)
            let built = try onlySolid(try await h.run([loft], kernel: kernel), loft)
            bulges.append(try await volume(built, kernel))
        }
        #expect(bulges[0] < bulges[1] && bulges[1] < bulges[2], "\(bulges)")
    }
}
#endif
