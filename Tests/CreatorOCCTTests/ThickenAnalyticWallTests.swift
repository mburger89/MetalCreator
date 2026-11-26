#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-G Task 1: Thicken's walls between coaxial circles lie on analytic surfaces (R1), and its own open-edge sentence (R2).
struct ThickenAnalyticWallTests {
    let kernel = OCCTKernel()
    let tag = newTag()

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    func holePlate(half: Bool = false) async throws -> Solid {
        func ring(_ radius: Double, _ cx: Double, _ cy: Double) async throws -> Curve {
            let piece = CurvePiece.arc(center: Vector3(cx, cy, 0), normal: Vector3(0, 0, 1), radius: radius,
                                       start: Vector3(cx + radius, cy, 0), sweep: 2 * .pi)
            return try await kernel.makeCurve([piece], tag: newTag())
        }
        if !half {
            let outer = try await kernel.makeCurve(
                [.line(Vector3(0, 0, 0), Vector3(0, 40, 0)), .line(Vector3(0, 40, 0), Vector3(40, 40, 0)),
                 .line(Vector3(40, 40, 0), Vector3(40, 0, 0)), .line(Vector3(40, 0, 0), Vector3(0, 0, 0)),
                ], tag: newTag())
            return try await kernel.planarSurface([outer, ring(5, 20, 20)], tag: newTag())
        }
        let outline = try await kernel.makeCurve(
            [.line(Vector3(0, 0, 0), Vector3(0, 40, 0)), .line(Vector3(0, 40, 0), Vector3(40, 40, 0)),
             .line(Vector3(40, 40, 0), Vector3(40, 0, 0)), .line(Vector3(40, 0, 0), Vector3(25, 0, 0)),
             .arc(center: Vector3(20, 0, 0), normal: Vector3(0, 0, 1), radius: 5, start: Vector3(25, 0, 0), sweep: .pi),
             .line(Vector3(15, 0, 0), Vector3(0, 0, 0)),
            ], tag: newTag())
        return try await kernel.planarSurface([outline], tag: newTag())
    }

    func walls(_ solid: Solid) -> [FaceInfo] {
        solid.topology.faces.filter { face in
            face.tags.contains { if case .blend = $0.role { true } else { false } }
        }
    }

    @Test(arguments: [ThickenSide.front, .back, .both])
    func aHoleWallIsACylinder(side: ThickenSide) async throws {
        let plate = try await kernel.thickened(holePlate(), distance: 2, side: side, tag: tag)
        #expect(!plate.hasOpenShell)
        let cylinders = plate.topology.faces.filter { $0.kind == .cylinder }
        #expect(cylinders.count == 1)
        #expect(abs((cylinders.first?.radius ?? 0) - 5) < 1e-7)
        #expect(walls(plate).count == 5)
    }

    @Test func aHalfHoleWallIsACylinder() async throws {
        let plate = try await kernel.thickened(holePlate(half: true), distance: 2, side: .front, tag: tag)
        #expect(!plate.hasOpenShell)
        let cylinders = plate.topology.faces.filter { $0.kind == .cylinder }
        #expect(cylinders.count == 1)
        #expect(abs((cylinders.first?.radius ?? 0) - 5) < 1e-7)
    }

    @Test func aTubeRimWallIsFlat() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 20))], tag: newTag())
        let tube = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                            angle: Angle(radians: 2 * .pi), tag: newTag())
        let thick = try await kernel.thickened(tube, distance: 2, side: .both, tag: tag)
        #expect(!thick.hasOpenShell)
        let rims = walls(thick)
        #expect(rims.count == 2)
        #expect(rims.allSatisfy { $0.kind == .plane })
        let expected = Double.pi * (11 * 11 - 9 * 9) * 20
        #expect(abs(try await volume(thick) - expected) / expected < 1e-4)
    }

    @Test func aHalfTubeRimWallIsAnAnnularSector() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 20))], tag: newTag())
        let tube = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                            angle: Angle(radians: .pi), tag: newTag())
        let thick = try await kernel.thickened(tube, distance: 2, side: .both, tag: tag)
        #expect(!thick.hasOpenShell)
        // Two rim sectors and two straight sides.
        let sides = walls(thick)
        #expect(sides.count == 4 && sides.allSatisfy { $0.kind == .plane })
        let expected = Double.pi * (11 * 11 - 9 * 9) * 20 / 2
        #expect(abs(try await volume(thick) - expected) / expected < 1e-4)
    }

    @Test func aConeRimWallIsAConeOrPlane() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(5, 0, 10))], tag: newTag())
        let cone = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                            angle: Angle(radians: 2 * .pi), tag: newTag())
        let thick = try await kernel.thickened(cone, distance: 1, side: .front, tag: tag)
        #expect(!thick.hasOpenShell)
        let rims = walls(thick)
        #expect(rims.count == 2)
        #expect(rims.allSatisfy { $0.kind == .cone })
    }

    @Test func theWallKeepsItsName() async throws {
        let plate = try await kernel.thickened(holePlate(), distance: 2, side: .front, tag: tag)
        let cylinder = try #require(plate.topology.faces.first { $0.kind == .cylinder })
        let sources = cylinder.tags.compactMap { tag -> TopoTag? in
            if case .blend = tag.role { tag } else { nil }
        }
        #expect(sources.count == 1)
    }

    @Test func oneSidedOpenEdgesSayThicken() {
        #expect(OCCTKernel.thickenOpenEdgesSentence
            == "The thickened sides don't keep the surface's open edges, so it can't be thickened.")
    }
}
#endif
