import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Field Scatter on a picked flat face (fields spec §3.3): the same face pick, holes and margin as Face Pattern.
struct FieldScatterFaceTests {
    #if canImport(CreatorOCCT)
    /// The 60 × 40 × 6 plate (top on z = 0) with an optional Ø20 hole, and a Field Scatter wired to its solid.
    struct Fixture {
        var plate = PatternPlate()
        let scatter: Node
        let part: Node

        init(drilled: Bool = false, _ settings: [SocketName: ConstantValue] = [:]) {
            scatter = plate.h.add(FieldScatterNode.self, settings)
            if drilled {
                let hole = plate.cylinder(diameter: 20, from: -7, to: 1)
                let cut = plate.h.add(BooleanNode.self, ["operation": .integer(1)])
                plate.h.wire(plate.plate, "solid", to: cut, "target")
                plate.h.wire(hole, "solid", to: cut, "tools")
                part = cut
            } else {
                part = plate.plate
            }
            plate.h.wire(part, "solid", to: scatter, "solid")
        }

        /// Picks the face of the part facing `normal`, then runs the scatter.
        mutating func pick(normal: Vector3 = .unitZ, kind: SurfaceKind = .plane, kernel: any Kernel = OCCTKernel()) async throws
            -> EvaluationReport {
            let solid = try onlySolid(try await plate.h.run([part], kernel: kernel), part)
            let face = try #require(solid.topology.faces.filter { face in
                face.kind == kind && (kind != .plane || face.normal.map { isClose($0, normal) } == true)
            }.max { $0.centroid.dot(normal) < $1.centroid.dot(normal) })
            plate.h.set(scatter, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: face.id))))
            return try await plate.h.run([scatter], kernel: kernel)
        }
    }

    @Test func pointsFillTheTopFaceKeepingTheMargin() async throws {
        var f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
        let report = try await f.pick()
        let planes = try #require(report.value(f.scatter, "placements")?.planes, "\(String(describing: report.state(f.scatter)))")
        #expect(planes.count >= 20)
        #expect(planes.allSatisfy { isClose($0.origin.z, 0) && isClose($0.normal, .unitZ) })
        #expect(planes.allSatisfy { abs($0.origin.x) <= 27 + 1e-6 && abs($0.origin.y) <= 17 + 1e-6 })
    }

    @Test func aHoleInTheFaceAndItsMarginStayEmpty() async throws {
        var f = Fixture(drilled: true, ["minSpacing": .number(4), "maxSpacing": .number(4), "margin": .number(2)])
        let report = try await f.pick()
        let planes = try #require(report.value(f.scatter, "placements")?.planes, "\(String(describing: report.state(f.scatter)))")
        #expect(planes.count > 15)
        #expect(planes.allSatisfy { Vector3($0.origin.x, $0.origin.y, 0).length >= 12 - 1e-6 }, "Ø20 hole plus the 2 mm margin")
    }

    @Test func aFaceThatIsNotFlatIsRefusedInThisNodesName() async throws {
        var f = Fixture(drilled: true)
        let report = try await f.pick(kind: .cylinder)
        #expect(report.error(f.scatter) == "Field Scatter works on flat faces for now.")
    }

    @Test func aSolidWithNoPickedFaceAsksForOne() async throws {
        let f = Fixture()
        let report = try await f.plate.h.run([f.scatter], kernel: FakeKernel())
        #expect(report.error(f.scatter) == "Pick a face for this pattern to fill.")
    }

    @Test func theResultIsTheSameOnASecondRun() async throws {
        var f = Fixture(["minSpacing": .number(5), "maxSpacing": .number(9)])
        let first = try #require(try await f.pick().value(f.scatter, "placements")?.planes)
        let second = try #require(try await f.plate.h.run([f.scatter], kernel: OCCTKernel()).value(f.scatter, "placements")?.planes)
        #expect(first == second && !first.isEmpty)
    }
    #endif
}
