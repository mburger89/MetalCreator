#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 6: `Kernel.cappingPlanarHoles(_:tag:)` (R5, R12, R17).
struct CapPlanarHolesTests {
    let kernel = OCCTKernel()
    let tag = newTag()

    func circle(_ radius: Double, z: Double) async throws -> Curve {
        let piece = CurvePiece.arc(center: Vector3(0, 0, z), normal: Vector3(0, 0, 1), radius: radius,
                                   start: Vector3(radius, 0, z), sweep: 2 * .pi)
        return try await kernel.makeCurve([piece], tag: newTag())
    }

    func tube() async throws -> Solid {
        try await kernel.loftSurface([circle(10, z: 0), circle(6, z: 20)], ruled: false, closed: false, tag: newTag())
    }

    func cylinderSheet(_ radius: Double) async throws -> Solid {
        let line = try await kernel.makeCurve([.line(Vector3(radius, 0, 0), Vector3(radius, 0, 20))], tag: newTag())
        return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                        angle: Angle(radians: 2 * .pi), tag: newTag())
    }

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    func blendKeys(_ face: FaceInfo) -> [EdgeKey] {
        face.tags.compactMap { if case .blend(let key) = $0.role { key } else { nil } }
    }

    @Test func aLoftedTubeCapsIntoASolid() async throws {
        let sheet = try await tube()
        #expect(sheet.hasOpenShell)
        let result = try await kernel.cappingPlanarHoles(sheet, tag: tag)
        #expect(result.capped == 2 && result.notFlat == 0)
        #expect(!result.body.hasOpenShell)
        let expected = Double.pi * 20 * (100 + 60 + 36) / 3
        let measured = try await volume(result.body)
        #expect(abs(measured - expected) / expected < 1e-4)
        let caps = result.body.topology.faces.filter { !blendKeys($0).isEmpty }
        #expect(caps.count == 2)
        let keys = caps.flatMap(blendKeys)
        #expect(Set(keys).count == 2)
        // One cap names the tube's start edge, the other its end edge.
        let boundary = sheet.topology.edges.filter(\.isBoundary)
        #expect(boundary.count == 2)
        let expectedKeys = Set(boundary.compactMap { sheet.topology.key(of: $0) })
        #expect(Set(keys) == expectedKeys)
    }

    @Test func concentricLoopsMakeAnAnnulus() async throws {
        let outer = try await cylinderSheet(10)
        let inner = try await cylinderSheet(6)
        let both = try await kernel.compound([outer, inner], tag: newTag())
        let result = try await kernel.cappingPlanarHoles(both, tag: tag)
        #expect(result.capped == 2 && result.notFlat == 0)
        #expect(!result.body.hasOpenShell)
        let expected = Double.pi * (100 - 36) * 20
        let measured = try await volume(result.body)
        #expect(abs(measured - expected) / expected < 1e-4)
        // A revolved cylinder's circles carry no names, so the caps are found by their kind.
        let caps = result.body.topology.faces.filter { $0.kind == .plane }
        #expect(caps.count == 2)
        // An annulus: its area is pi (100 - 36), each cap one face with a hole.
        for cap in caps { #expect(abs(cap.area - Double.pi * 64) / (Double.pi * 64) < 1e-6) }
    }

    @Test func aBentLoopStaysOpen() async throws {
        let line = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
        ], tag: newTag())
        let sheet = try await kernel.extrude(line, direction: Vector3(0, 0, 1), distance: 10, symmetric: false, tag: newTag())
        let result = try await kernel.cappingPlanarHoles(sheet, tag: tag)
        #expect(result.capped == 0 && result.notFlat == 1)
        #expect(result.body.hasOpenShell)
        #expect(result.body.topology.faces.count == sheet.topology.faces.count)
        #expect(result.body.topology.faces.map { Set($0.tags) } == sheet.topology.faces.map { Set($0.tags) })
    }

    @Test func aClosedSolidPassesThrough() async throws {
        let cube = try await box(kernel, 10, 10, 10)
        let result = try await kernel.cappingPlanarHoles(cube, tag: tag)
        #expect(result.capped == 0 && result.notFlat == 0)
        #expect(result.body.topology.faces.count == 6)
        #expect(result.body.topology.faces.map { Set($0.tags) } == cube.topology.faces.map { Set($0.tags) })
        #expect(!result.body.hasOpenShell)
    }

    @Test func aClosedBareShellBecomesASolid() async throws {
        let half = CurvePiece.arc(center: .zero, normal: Vector3(0, 1, 0), radius: 10, start: Vector3(0, 0, -10), sweep: .pi)
        let arc = try await kernel.makeCurve([half], tag: newTag())
        let sphere = try await kernel.revolve(arc, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                              angle: Angle(radians: 2 * .pi), tag: newTag())
        #expect(sphere.hasOpenShell)
        let result = try await kernel.cappingPlanarHoles(sphere, tag: tag)
        #expect(result.capped == 0)
        #expect(!result.body.hasOpenShell)
        let expected = 4.0 / 3 * Double.pi * 1000
        let measured = try await volume(result.body)
        #expect(abs(measured - expected) / expected < 1e-3)
    }

    @Test func capEdgesRememberTheirNames() async throws {
        let sheet = try await tube()
        let result = try await kernel.cappingPlanarHoles(sheet, tag: tag)
        let body = result.body
        let sourceTags = Set(sheet.topology.edges.filter(\.isBoundary).flatMap(\.tags))
        #expect(sourceTags.count >= 2)
        // The two circles between a cap and the tube carry the tube's boundary edge tags.
        let joins = body.topology.edges.filter { edge in
            guard edge.faces.count == 2, let a = body.topology.face(edge.faces[0]), let b = body.topology.face(edge.faces[1]) else {
                return false
            }
            return blendKeys(a).isEmpty != blendKeys(b).isEmpty
        }
        #expect(joins.count == 2)
        #expect(Set(joins.flatMap(\.tags)) == sourceTags)
    }

    @Test func aMixedValueCapsOnlyItsSheets() async throws {
        let cube = try await box(kernel, 10, 10, 10)
        let moved = try await kernel.transform(cube, by: Transform(translation: Vector3(50, 0, 0)), tag: newTag())
        let sheet = try await tube()
        let mixed = try await kernel.compound([moved, sheet], tag: newTag())
        #expect(mixed.holdsClosedSolid && mixed.hasOpenShell)
        let result = try await kernel.cappingPlanarHoles(mixed, tag: tag)
        #expect(result.capped == 2)
        #expect(!result.body.hasOpenShell)
        let frustum = Double.pi * 20 * (100 + 60 + 36) / 3
        let measured = try await volume(result.body)
        #expect(abs(measured - (1000 + frustum)) / (1000 + frustum) < 1e-4)
        // Two bodies: faces joined by a shared edge belong together (no API names bodies, so the topology says).
        let topology = result.body.topology
        var parent = Array(topology.faces.indices)
        func root(_ i: Int) -> Int { parent[i] == i ? i : root(parent[i]) }
        for edge in topology.edges where edge.faces.count == 2 {
            let ids = edge.faces.compactMap { id in topology.faces.firstIndex { $0.id == id } }
            if ids.count == 2 { parent[root(ids[0])] = root(ids[1]) }
        }
        var sizes: [Int: Int] = [:]
        for i in topology.faces.indices { sizes[root(i), default: 0] += 1 }
        #expect(sizes.values.sorted() == [3, 6])
        // The box is untouched (volume 1000 from the original), so the other body carries the frustum's remainder.
        let boxVolume = try await volume(moved)
        #expect(abs(boxVolume - 1000) < 1e-6)
        #expect(abs(measured - boxVolume - frustum) / frustum < 1e-4)
        let boxFaces = result.body.topology.faces.filter { $0.centroid.x > 40 }
        #expect(boxFaces.count == 6)
        #expect(Set(boxFaces.map { Set($0.tags) }) == Set(moved.topology.faces.map { Set($0.tags) }))
        #expect(boxFaces.allSatisfy { blendKeys($0).isEmpty })
    }

    @Test func aFlatSheetIsNotCapped() async throws {
        let sheet = try await kernel.planarSurface([circle(10, z: 0)], tag: newTag())
        let result = try await kernel.cappingPlanarHoles(sheet, tag: tag)
        #expect(result.capped == 0)
        #expect(result.body.hasOpenShell)
        #expect(result.body.topology.faces.count == 1)
        #expect(result.body.topology.faces.map { Set($0.tags) } == sheet.topology.faces.map { Set($0.tags) })
    }

    @Test func aFlatBSplineSheetIsNotCapped() async throws {
        let patch = try await kernel.boundaryPatch(PatchBoundary(curves: [circle(10, z: 0)], edges: [], part: nil), interior: [],
                                                   interior: [], continuity: .g0, tag: newTag()).sheet
        let rebuilt = try await kernel.rebuilt(try await kernel.planarSurface([circle(10, z: 0)], tag: newTag()),
                                               as: RebuildSpec(degreeU: 3, degreeV: 3, spansU: 4, spansV: 4)).sheet
        for sheet in [patch, rebuilt] {
            let result = try await kernel.cappingPlanarHoles(sheet, tag: tag)
            #expect(result.capped == 0)
            #expect(result.body.hasOpenShell)
            #expect(result.body.topology.faces.count == 1)
        }
    }

    @Test func concentricLoopsAlongADiagonalAxisMakeAnAnnulus() async throws {
        let root = 0.5.squareRoot()
        let direction = Vector3(root, -root, 0)
        func sheet(_ radius: Double) async throws -> Solid {
            let start = Vector3(radius * root, radius * root, 0)
            let end = Vector3(start.x + 20 * direction.x, start.y + 20 * direction.y, 0)
            let line = try await kernel.makeCurve([.line(start, end)], tag: newTag())
            return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: direction),
                                            angle: Angle(radians: 2 * .pi), tag: newTag())
        }
        let both = try await kernel.compound([sheet(10), sheet(6)], tag: newTag())
        let result = try await kernel.cappingPlanarHoles(both, tag: tag)
        #expect(result.capped == 2 && result.notFlat == 0)
        #expect(!result.body.hasOpenShell)
        let expected = Double.pi * (100 - 36) * 20
        let measured = try await volume(result.body)
        #expect(abs(measured - expected) / expected < 1e-4)
    }
}
#endif
