import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorSketch
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// G-c Task 4: a Sketch node whose line and spline close a loop, joined by Curvature (or Tangent), extruded through the real
/// Evaluator on OpenCascade. `Kernel.continuity` on the vertical joint edges reads G2 (or G1 with a curvature jump).
struct SplineContinuityAcceptanceTests {
    /// A line along the bottom and a spline that leaves its right end, loops over the top and comes back to its left end, the
    /// constraint holding at both shared ends. Fit points are fixed, the end handles active.
    func loop(joining makeConstraint: (SketchEntityID, SketchEntityID) -> SketchConstraint) -> Sketch {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(20, 0))
        let line = sketch.addLine(from: start, to: end)
        var points = [end]
        for position in [Vector2(30, 10), Vector2(10, 20), Vector2(-10, 10)] { points.append(sketch.addPoint(position)) }
        points.append(start)
        for (index, point) in points.enumerated() {
            sketch.add(.fix(point, at: [Vector2(20, 0), Vector2(30, 10), Vector2(10, 20), Vector2(-10, 10), Vector2(0, 0)][index]))
        }
        let spline = sketch.addSpline(through: points)
        for index in [0, points.count - 1] {
            sketch.activateSplineHandle(spline, at: index, .tangent)
            sketch.activateSplineHandle(spline, at: index, .curvature)
        }
        sketch.add(makeConstraint(line, spline))
        return sketch
    }

    func continuities(of sketch: Sketch) async throws -> [EdgeContinuity] {
        let kernel = OCCTKernel()
        var h = Harness()
        let node = h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(8)])
        h.wire(node, "profiles", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: kernel)
        #expect(report.error(node) == nil && report.error(extrude) == nil)
        let solid = try onlySolid(report, extrude)
        func isSide(_ face: FaceID) -> Bool {
            solid.topology.face(face)?.tags.contains { if case .side = $0.role { true } else { false } } ?? false
        }
        let joints = solid.topology.edges.filter { edge in
            edge.kind == .line && edge.faces.count == 2 && edge.faces[0] != edge.faces[1] && edge.faces.allSatisfy(isSide)
        }
        try #require(joints.count == 2, "the two vertical edges where the line meets the spline")
        var result: [EdgeContinuity] = []
        for joint in joints { result.append(try await kernel.continuity(along: joint.id, of: solid)) }
        return result
    }

    @Test func aCurvatureJoinedSketchExtrudesToAG2Edge() async throws {
        let sketch = loop { .curvature($0, $1) }
        for found in try await continuities(of: sketch) {
            #expect(found.grade == .g2, "position \(found.positionGap) angle \(found.angleGap) curvature \(found.curvatureGap)")
        }
    }

    @Test func aTangentJoinedSketchExtrudesToAG1EdgeWithACurvatureJump() async throws {
        var sketch = loop { .tangent($0, $1) }
        // Tangent alone leaves the curvature handles free; give them a bend so the jump is a property of the joint.
        let splineID = sketch.entityIDs.first { sketch.splineParts(of: $0) != nil }
        guard let spline = splineID, case .splineHandles(var values)? = sketch.solved[spline] else {
            Issue.record("no spline handles")
            return
        }
        for index in [0, values.count - 1] where values[index].curvature != nil {
            values[index].curvature = (values[index].curvature ?? .zero) + Vector2(0, 0.5)
        }
        sketch.solved[spline] = .splineHandles(values)
        for found in try await continuities(of: sketch) {
            #expect(found.grade == .g1, "position \(found.positionGap) angle \(found.angleGap) curvature \(found.curvatureGap)")
            #expect(found.curvatureGap > EdgeContinuity.curvatureTolerance)
        }
    }
}
#endif
