#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 5: `Kernel.thickened(_:distance:side:tag:)` (R3, R7 to R9, R11, R17, R18).
struct ThickenTests {
    let kernel = OCCTKernel()
    let tag = newTag()
    /// Task 4's fixtures and helpers (R18's `towardAxisSign` among them).
    let offsets = OffsetSurfaceTests()

    func rectangle(width: Double, depth: Double) async throws -> Solid {
        try await offsets.square(x: 0...width, y: 0...depth)
    }

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    func refusal(_ body: () async throws -> Solid) async -> String? {
        do { _ = try await body(); return nil } catch { return offsets.message(error) }
    }

    func lSheet() async throws -> Solid {
        let line = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
        ], tag: newTag())
        return try await kernel.extrude(line, direction: Vector3(0, 0, 1), distance: 10, symmetric: false, tag: newTag())
    }

    func circle(_ radius: Double) async throws -> Curve {
        let piece = CurvePiece.arc(center: .zero, normal: Vector3(0, 0, 1), radius: radius,
                                   start: Vector3(radius, 0, 0), sweep: 2 * .pi)
        return try await kernel.makeCurve([piece], tag: newTag())
    }

    func zRange(_ face: FaceInfo) -> Double { face.centroid.z }

    @Test func aPlateThickensToItsVolume() async throws {
        let sheet = try await rectangle(width: 20, depth: 30)
        let normal = sheet.topology.faces[0].normal
        #expect(abs((normal?.z ?? 0) - 1) < 1e-9)
        let plate = try await kernel.thickened(sheet, distance: 2, side: .front, tag: tag)
        let plateVolume = try await volume(plate)
        #expect(abs(plateVolume - 1200) / 1200 < 1e-6)
        #expect(!plate.hasOpenShell)
        #expect(plate.topology.faces.count == 6)
        let start = plate.topology.faces.filter { $0.tags.contains(TopoTag(tag, .startCap)) }
        let end = plate.topology.faces.filter { $0.tags.contains(TopoTag(tag, .endCap)) }
        #expect(start.count == 1 && end.count == 1)
        #expect(abs((end.first?.centroid.z ?? 0) - 2) < 1e-6)
        // R3: both caps carry the source face's own tags besides the cap role.
        let sourceTags = Set(sheet.topology.faces[0].tags)
        #expect(!sourceTags.isEmpty)
        #expect(start.allSatisfy { sourceTags.isSubset(of: Set($0.tags)) })
        #expect(end.allSatisfy { sourceTags.isSubset(of: Set($0.tags)) })
        var keys: [EdgeKey] = []
        for face in plate.topology.faces {
            for item in face.tags {
                if case .blend(let key) = item.role { keys.append(key) }
            }
        }
        #expect(keys.count == 4 && Set(keys).count == 4)
        let boundary = Set(sheet.topology.edges.compactMap { sheet.topology.key(of: $0) })
        #expect(Set(keys) == boundary)
    }

    @Test func sidesPutTheFacesWhereR3Says() async throws {
        let sheet = try await rectangle(width: 20, depth: 30)
        func caps(_ plate: Solid) -> (start: Double, end: Double) {
            let start = plate.topology.faces.first { $0.tags.contains(TopoTag(tag, .startCap)) }
            let end = plate.topology.faces.first { $0.tags.contains(TopoTag(tag, .endCap)) }
            return (start?.centroid.z ?? .nan, end?.centroid.z ?? .nan)
        }
        let back = try await kernel.thickened(sheet, distance: 2, side: .back, tag: tag)
        let backVolume = try await volume(back)
        #expect(abs(backVolume - 1200) / 1200 < 1e-6)
        #expect(abs(caps(back).end) < 1e-6 && abs(caps(back).start + 2) < 1e-6)
        let both = try await kernel.thickened(sheet, distance: 2, side: .both, tag: tag)
        let bothVolume = try await volume(both)
        #expect(abs(bothVolume - 1200) / 1200 < 1e-6)
        #expect(abs(caps(both).start + 1) < 1e-6 && abs(caps(both).end - 1) < 1e-6)
    }

    @Test func anLSheetThickensToTheSpikesVolumes() async throws {
        let sheet = try await lSheet()
        let front = try await kernel.thickened(sheet, distance: 1, side: .front, tag: tag)
        let back = try await kernel.thickened(sheet, distance: 1, side: .back, tag: tag)
        let volumes = [try await volume(front), try await volume(back)].sorted()
        #expect(abs(volumes[0] - 190) <= 0.01 && abs(volumes[1] - 210) <= 0.01)
        for plate in [front, back] {
            #expect(!plate.hasOpenShell)
            let shape = try await kernel.shape(of: plate)
            let tolerance = try OCCTKernel.serialized { () throws -> Double in try shape.maxEdgeTolerance() }
            #expect(tolerance <= 0.01)
        }
    }

    @Test func aRingGetsTwoWalls() async throws {
        let sheet = try await kernel.planarSurface([circle(10), circle(4)], tag: newTag())
        let ring = try await kernel.thickened(sheet, distance: 1, side: .front, tag: tag)
        let expected = Double.pi * (100 - 16)
        let ringVolume = try await volume(ring)
        #expect(abs(ringVolume - expected) / expected < 1e-4)
        let walls = ring.topology.faces.filter { face in
            face.tags.contains { if case .blend = $0.role { true } else { false } }
        }
        #expect(walls.count == 2)
    }

    @Test func aClosedSheetThickensToAHollowSolid() async throws {
        let half = CurvePiece.arc(center: .zero, normal: Vector3(0, 1, 0), radius: 10, start: Vector3(0, 0, -10), sweep: .pi)
        let arc = try await kernel.makeCurve([half], tag: newTag())
        let sphere = try await kernel.revolve(arc, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                              angle: Angle(radians: 2 * .pi), tag: newTag())
        #expect(sphere.hasOpenShell)
        let outward = 4.0 / 3 * Double.pi * (1331 - 1000)
        let inward = 4.0 / 3 * Double.pi * (1000 - 729)
        let front = try await kernel.thickened(sphere, distance: 1, side: .front, tag: tag)
        let back = try await kernel.thickened(sphere, distance: 1, side: .back, tag: tag)
        for solid in [front, back] { #expect(!solid.hasOpenShell) }
        let volumes = [try await volume(front), try await volume(back)].sorted()
        #expect(abs(volumes[0] - inward) / inward < 1e-4 && abs(volumes[1] - outward) / outward < 1e-4)
        let both = try await kernel.thickened(sphere, distance: 2, side: .both, tag: tag)
        let shell = 4.0 / 3 * Double.pi * (1331 - 729)
        #expect(!both.hasOpenShell)
        let hollow = try await volume(both)
        #expect(abs(hollow - shell) / shell < 1e-4)
        #expect(hollow < 4.0 / 3 * Double.pi * 1331)
    }

    func sphereSheet(centreX: Double = 0) async throws -> Solid {
        let half = CurvePiece.arc(center: Vector3(centreX, 0, 0), normal: Vector3(0, 1, 0), radius: 10,
                                  start: Vector3(centreX, 0, -10), sweep: .pi)
        let arc = try await kernel.makeCurve([half], tag: newTag())
        return try await kernel.revolve(arc, axis: Axis(origin: Vector3(centreX, 0, 0), direction: Vector3(0, 0, 1)),
                                        angle: Angle(radians: 2 * .pi), tag: newTag())
    }

    @Test func aClosedSheetBesideAPlateStaysHollow() async throws {
        let sphere = try await sphereSheet()
        let plate = try await offsets.square(x: 20...30)
        let mixed = try await kernel.compound([sphere, plate], tag: newTag())
        let result = try await kernel.thickened(mixed, distance: 1, side: .front, tag: tag)
        let plateOnly = try await volume(try await kernel.thickened(plate, distance: 1, side: .front, tag: tag))
        let expected = 4.0 / 3 * Double.pi * (1331 - 1000) + plateOnly
        #expect(abs(try await volume(result) - expected) / expected < 1e-4)
        #expect(!result.hasOpenShell)
    }

    @Test func twoClosedSheetsEachStayHollow() async throws {
        let pair = try await kernel.compound([try await sphereSheet(), try await sphereSheet(centreX: 40)], tag: newTag())
        let result = try await kernel.thickened(pair, distance: 1, side: .front, tag: tag)
        let expected = 2 * 4.0 / 3 * Double.pi * (1331 - 1000)
        #expect(abs(try await volume(result) - expected) / expected < 1e-4)
    }

    @Test func pastTheRadiusNamesTheLargest() async throws {
        let sheet = try await offsets.quarterCylinder()
        let s = try await offsets.towardAxisSign(sheet)
        let toward: ThickenSide = s < 0 ? .back : .front
        let away: ThickenSide = s < 0 ? .front : .back
        let text = try #require(await refusal { try await kernel.thickened(sheet, distance: 12, side: toward, tag: tag) })
        #expect(text.hasPrefix("The surface can't be thickened by 12 mm; the most that works is 9.9"))
        let built = try await kernel.thickened(sheet, distance: 12, side: away, tag: tag)
        #expect(!built.hasOpenShell)
    }

    @Test func aThickenedSheetIsAcceptedDownstream() async throws {
        let sheet = try await rectangle(width: 20, depth: 30)
        let plate = try await kernel.thickened(sheet, distance: 2, side: .front, tag: tag)
        let hole = try await kernel.extrude(.circle(radius: 2, center: Vector2(10, 15), plane: .xy), distance: 10,
                                            mode: .symmetric, tag: newTag())
        let cut = try await kernel.boolean(.subtract, plate, [hole], tag: newTag())
        let cutVolume = try await volume(cut)
        #expect(cutVolume < 1200)
        let wall = try #require(plate.topology.edges.first { $0.kind == .line && abs($0.length - 20) < 1e-6 && $0.midpoint.z > 1.9 })
        let rounded = try await kernel.fillet(plate, edges: [wall.id], radius: 0.5, tag: newTag())
        #expect(!rounded.hasOpenShell)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thicken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (format, name) in [(ExportFormat.step, "plate.step"), (.stl, "plate.stl")] {
            let url = directory.appendingPathComponent(name)
            try await kernel.export([plate], format: format, to: url)
            #expect((try? Data(contentsOf: url).count) ?? 0 > 100)
        }
    }

    @Test func aFoldIsRefused() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: newTag())
        let folded = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(6, 6, 0))])
        let text = try #require(await refusal { try await kernel.thickened(folded, distance: 1, side: .front, tag: tag) })
        #expect(text == "The surface folds over itself, so it can't be thickened; move its control points apart first.")
    }

    @Test func touchingLooseFacesAreRefused() async throws {
        let touching = try await kernel.compound([offsets.square(x: 0...10), offsets.square(x: 10...20)], tag: newTag())
        let text = try #require(await refusal { try await kernel.thickened(touching, distance: 1, side: .front, tag: tag) })
        #expect(text == "Parts of the surface touch but aren't joined; Sew them first.")
        let apart = try await kernel.compound([offsets.square(x: 0...10), offsets.square(x: 15...25)], tag: newTag())
        let two = try await kernel.thickened(apart, distance: 1, side: .front, tag: tag)
        let twoVolume = try await volume(two)
        #expect(!two.hasOpenShell && abs(twoVolume - 200) < 1e-4)
    }

    @Test func aValueHoldingASolidIsRefused() async throws {
        let solid = try await box(kernel, 10, 10, 10)
        let mixed = try await kernel.compound([solid, offsets.square(x: 20...30)], tag: newTag())
        let text = try #require(await refusal { try await kernel.thickened(mixed, distance: 1, side: .front, tag: tag) })
        #expect(text == "Thicken takes sheets only; this value also holds a closed solid.")
    }

    @Test func refusals() async throws {
        let solid = try await box(kernel, 10, 10, 10)
        let closed = try #require(await refusal { try await kernel.thickened(solid, distance: 1, side: .front, tag: tag) })
        #expect(closed == "Thicken takes a sheet; this is a closed solid.")
        let sheet = try await rectangle(width: 10, depth: 10)
        let zero = try #require(await refusal { try await kernel.thickened(sheet, distance: 0, side: .front, tag: tag) })
        #expect(zero == "The distance must be greater than 0.")
    }

    @Test func aCancelledThickenThrows() async throws {
        let sheet = try await rectangle(width: 10, depth: 10)
        let task = Task { () async throws -> Solid in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.thickened(sheet, distance: 1, side: .front, tag: tag)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif
