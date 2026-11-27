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

    /// A 40 x 40 plate with a radius-5 hole: whole, cut in half by the bottom edge (its arc starts at 0 degrees) or by the top edge
    /// (its arc starts at 180 degrees, the atan2 branch cut).
    func holePlate(half: Bool = false, topEdge: Bool = false) async throws -> Solid {
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
        if topEdge {
            let outline = try await kernel.makeCurve(
                [.line(Vector3(0, 0, 0), Vector3(0, 40, 0)), .line(Vector3(0, 40, 0), Vector3(15, 40, 0)),
                 .arc(center: Vector3(20, 40, 0), normal: Vector3(0, 0, 1), radius: 5, start: Vector3(15, 40, 0), sweep: .pi),
                 .line(Vector3(25, 40, 0), Vector3(40, 40, 0)), .line(Vector3(40, 40, 0), Vector3(40, 0, 0)),
                 .line(Vector3(40, 0, 0), Vector3(0, 0, 0)),
                ], tag: newTag())
            return try await kernel.planarSurface([outline], tag: newTag())
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
        let expected = (1600 - Double.pi * 25) * 2
        #expect(abs(try await volume(plate) - expected) / expected < 1e-4)
    }

    @Test(arguments: [ThickenSide.front, .back, .both], [false, true])
    func aHalfHoleWallIsACylinder(side: ThickenSide, topEdge: Bool) async throws {
        let sheet = try await holePlate(half: true, topEdge: topEdge)
        let plate = try await kernel.thickened(sheet, distance: 2, side: side, tag: tag)
        #expect(!plate.hasOpenShell)
        let cylinders = plate.topology.faces.filter { $0.kind == .cylinder }
        #expect(cylinders.count == 1)
        #expect(abs((cylinders.first?.radius ?? 0) - 5) < 1e-7)
        #expect(walls(plate).count == 6)
        let expected = (1600 - Double.pi * 25 / 2) * 2
        #expect(abs(try await volume(plate) - expected) / expected < 1e-4)
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

    /// A cone sheet from `from` to `to` (radius, height) revolved about z: thickened 1 mm toward `side`, its two rim walls are cones and
    /// its volume is Pappus' (the rectangle of the slant length by 1 mm, turned about z).
    func coneCheck(from: (Double, Double), to: (Double, Double), side: ThickenSide) async throws -> Double {
        let line = try await kernel.makeCurve(
            [.line(Vector3(from.0, 0, from.1), Vector3(to.0, 0, to.1))], tag: newTag())
        let cone = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                            angle: Angle(radians: 2 * .pi), tag: newTag())
        let thick = try await kernel.thickened(cone, distance: 1, side: side, tag: tag)
        #expect(!thick.hasOpenShell)
        let rims = walls(thick)
        #expect(rims.count == 2)
        #expect(rims.allSatisfy { $0.kind == .cone })
        return try await volume(thick)
    }

    /// Both ways of leaning, each thickened to both sides of the normal: the volume is 2 pi x (mean radius -/+ half the radial part of
    /// the unit normal) x slant length, so a wrong orientation or a wrong cone shows.
    @Test(arguments: [(10.0, 0.0, 5.0, 10.0), (5.0, 0.0, 10.0, 10.0)])
    func aConeRimWallIsACone(r0: Double, z0: Double, r1: Double, z1: Double) async throws {
        let slant = ((r1 - r0) * (r1 - r0) + (z1 - z0) * (z1 - z0)).squareRoot()
        let mean = (r0 + r1) / 2
        let radial = abs(z1 - z0) / slant // the normal's radial part, in magnitude
        let grow = 2 * Double.pi * (mean + 0.5 * radial) * slant
        let shrink = 2 * Double.pi * (mean - 0.5 * radial) * slant
        let front = try await coneCheck(from: (r0, z0), to: (r1, z1), side: .front)
        let back = try await coneCheck(from: (r0, z0), to: (r1, z1), side: .back)
        let (outward, inward) = front > back ? (front, back) : (back, front)
        #expect(abs(outward - grow) / grow < 1e-4)
        #expect(abs(inward - shrink) / shrink < 1e-4)
    }

    /// Two circular rims whose seams differ (one starts at 0 degrees, the other at 90): the analytic wall's own circles would put both seams
    /// at the lower start, so the guard leaves this pair to the ruled wall. The result is still a closed solid. (The loft's rims are splines, so this may not reach the guard; no fixture with circular rims of differing seams is reachable through the kernel.)
    @Test func rimsWithDifferentSeamsStayValid() async throws {
        func ring(_ z: Double, start: Double) async throws -> Curve {
            let piece = CurvePiece.arc(center: Vector3(0, 0, z), normal: Vector3(0, 0, 1), radius: 10,
                                       start: Vector3(10 * cos(start), 10 * sin(start), z), sweep: 2 * .pi)
            return try await kernel.makeCurve([piece], tag: newTag())
        }
        let tube = try await kernel.loftSurface([ring(0, start: 0), ring(20, start: .pi / 2)], ruled: false, closed: false, tag: newTag())
        let thick = try await kernel.thickened(tube, distance: 1, side: .both, tag: tag)
        #expect(!thick.hasOpenShell)
        #expect(try await volume(thick) > 0) // the loft twists between the seams, so no closed-form volume
    }

    @Test func theWallKeepsItsName() async throws {
        let plate = try await kernel.thickened(holePlate(), distance: 2, side: .front, tag: tag)
        let cylinder = try #require(plate.topology.faces.first { $0.kind == .cylinder })
        let sources = cylinder.tags.compactMap { tag -> TopoTag? in
            if case .blend = tag.role { tag } else { nil }
        }
        #expect(sources.count == 1)
    }

    /// No sheet is known whose offset sides lose an open edge (the shim's own refusal stays unreachable through `thickened`), so
    /// the sentence is pinned where it is made and where it passes: the shim's source, the kernel's wording and its pass-through.
    @Test func oneSidedOpenEdgesSayThicken() throws {
        let sentence = "The thickened sides don't keep the surface's open edges, so it can't be thickened."
        #expect(OCCTKernel.thickenOpenEdgesSentence == sentence)
        #expect(OCCTKernel.thickenFailureReason(sentence) == sentence)
        #expect(OCCTKernel.thickenFailureReason(OCCTKernel.openEdgesSentence) == nil)
        #expect(OCCTKernel.thickenFailureReason("The offset couldn't be built.") == nil)
        let header = try String(contentsOf: Self.repository.appending(path: "Sources/COCCT/cocct_offset.hpp"), encoding: .utf8)
        #expect(header.contains("kThickenOpenEdges = \"\(sentence)\""))
        let shim = try String(contentsOf: Self.repository.appending(path: "Sources/COCCT/cocct_thicken.cpp"), encoding: .utf8)
        #expect(shim.contains("throw user_error(kThickenOpenEdges)"))
        #expect(!shim.contains("user_error(kOffsetOpenEdges)"))
    }

    static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
#endif
