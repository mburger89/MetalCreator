import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Sketcher spec §7, Plane from Face.
struct PlaneFromFaceNodeTests {
    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    /// A 20 × 10 × `height` box wired into a Plane from Face picking the box's face with `role`.
    func plane(on role: TopoRole, height: Double = 6, kernel: any Kernel) async throws -> (Harness, Node, Node) {
        var h = Harness()
        let box = h.box(20, 10, height)
        let plane = h.add(PlaneFromFaceNode.self)
        h.wire(box, "solid", to: plane, "solid")
        let solid = try onlySolid(try await h.run([box], kernel: kernel), box)
        let face = try #require(solid.topology.faces.first { $0.tags.contains(TopoTag(node: box.id, item: 0, role: role)) })
        h.set(plane, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: face.id))))
        return (h, box, plane)
    }

    @Test func aTopFacePlaneSitsOnItsCentroidFacingOut() async throws {
        let kernel = OCCTKernel()
        let (h, _, plane) = try await plane(on: .endCap, kernel: kernel)
        let report = try await h.run([plane], kernel: kernel)
        let result = try #require(report.value(plane, "plane")?.planes?.first)
        #expect(report.isOK(plane))
        #expect(near(result.origin, Vector3(0, 0, 6)))
        #expect(near(result.normal, .unitZ))
        #expect(near(result.xAxis, .unitX))
    }

    @Test func aFaceFacingWorldXTakesWorldYAsItsXAxis() async throws {
        let kernel = OCCTKernel()
        // Segment 1 of the centred rectangle is its right side, facing +X.
        let (h, _, plane) = try await plane(on: .side(segment: 1), kernel: kernel)
        let result = try #require(try await h.run([plane], kernel: kernel).value(plane, "plane")?.planes?.first)
        #expect(near(result.origin, Vector3(10, 0, 3)))
        #expect(near(result.normal, .unitX))
        #expect(near(result.xAxis, .unitY))
        #expect(near(result.yAxis, .unitZ))
    }

    @Test func thePlaneFollowsTheFaceWhenTheModelChanges() async throws {
        let kernel = OCCTKernel()
        let (start, box, plane) = try await plane(on: .endCap, kernel: kernel)
        var h = start
        h.set(box, "distance", .number(15))
        let report = try await h.run([plane], kernel: kernel)
        #expect(report.isOK(plane))
        #expect(near(try #require(report.value(plane, "plane")?.planes?.first).origin, Vector3(0, 0, 15)))
    }

    @Test func aCurvedFaceIsAPlainError() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(10)])
        let rod = h.add(ExtrudeNode.self, ["distance": .number(5)])
        h.wire(circle, "profile", to: rod, "profile")
        let wall = FacePick(tags: [TopoTag(node: rod.id, item: 0, role: .side(segment: 0))])
        let plane = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(wall)])
        h.wire(rod, "solid", to: plane, "solid")
        #expect(try await h.run([plane], kernel: kernel).error(plane) == PlaneFromFaceNode.notFlat)
    }

    @Test func aMissingUnreadableOrStalePickIsAPlainError() async throws {
        var h = Harness()
        let box = h.box(20, 10, 6)
        let plane = h.add(PlaneFromFaceNode.self)
        h.wire(box, "solid", to: plane, "solid")
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.nothingPicked)
        h.set(plane, NodeSetting.face, .text("top"))
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.unreadablePick)
        h.set(plane, NodeSetting.face, .facePick(FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])))
        #expect(try await h.run([plane]).error(plane) == PlaneFromFaceNode.noMatch)
    }

    @Test func aPickMatchingSeveralFacesWarnsAndUsesTheFirst() async throws {
        // FakeKernel's union keeps both operands' faces, so a box unioned with itself has two top caps.
        var h = Harness()
        let box = h.box(20, 10, 6)
        let union = h.add(BooleanNode.self)
        h.wire(box, "solid", to: union, "target")
        h.wire(box, "solid", to: union, "tools")
        let top = FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])
        let plane = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(top)])
        h.wire(union, "solid", to: plane, "solid")
        let report = try await h.run([plane])
        #expect(report.warning(plane) == "The pick matches 2 faces; the plane is on the first.")
        #expect(report.value(plane, "plane")?.planes?.first?.normal == .unitZ)
    }

    @Test func xAxisIsWorldXProjectedOntoTheFace() {
        let tilted = FacePlane.plane(origin: .zero, normal: Vector3(1, 1, 0) * (1 / 2.0.squareRoot()))
        #expect(near(tilted.xAxis, Vector3(1, -1, 0) * (1 / 2.0.squareRoot())))
        let almostX = FacePlane.plane(origin: .zero, normal: Vector3(1, 1e-6, 0).normalized ?? .unitX)
        #expect(abs(almostX.xAxis.dot(.unitY)) > 0.999)
        #expect(abs(almostX.xAxis.dot(almostX.normal)) < 1e-12)
    }
}
