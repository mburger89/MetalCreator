#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 4: `Kernel.offsetSurface(_:distance:tag:)` (R4, R7 to R9, R11, R17, R18).
struct OffsetSurfaceTests {
    let kernel = OCCTKernel()
    let tag = newTag()

    func square(x: ClosedRange<Double> = 0...10, y: ClosedRange<Double> = 0...10, z: Double = 0) async throws -> Solid {
        // Clockwise seen from +z, which gives the face its +z normal.
        let corners = [Vector3(x.lowerBound, y.lowerBound, z), Vector3(x.lowerBound, y.upperBound, z),
                       Vector3(x.upperBound, y.upperBound, z), Vector3(x.upperBound, y.lowerBound, z),
        ]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    /// 20 mm line parallel to z at radius 10, revolved 90 degrees about z.
    func quarterCylinder() async throws -> Solid {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 20))], tag: newTag())
        return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)),
                                        angle: Angle(radians: .pi / 2), tag: newTag())
    }

    /// R18: +1 mm grows the area when the normal points away from the axis; the sign of a "toward the axis" distance.
    func towardAxisSign(_ sheet: Solid) async throws -> Double {
        let offset = try await kernel.offsetSurface(sheet, distance: 1, tag: newTag())
        return offset.topology.faces[0].area > sheet.topology.faces[0].area ? -1 : 1
    }

    func message(_ error: Error) -> String {
        guard case KernelError.invalidInput(let text) = error else { return "\(error)" }
        return text
    }

    func refusal(_ body: () async throws -> Solid) async -> String? {
        do { _ = try await body(); return nil } catch { return message(error) }
    }

    @Test func aPlaneMovesAlongItsNormal() async throws {
        let sheet = try await square()
        let normal = sheet.topology.faces[0].normal
        #expect(abs((normal?.z ?? 0) - 1) < 1e-9)
        let offset = try await kernel.offsetSurface(sheet, distance: 2, tag: tag)
        #expect(offset.topology.faces.count == 1)
        #expect(abs(offset.bounds.min.z - 2) < 1e-6 && abs(offset.bounds.max.z - 2) < 1e-6)
        #expect(abs(offset.topology.faces[0].area - 100) < 1e-6)
        #expect(offset.topology.faces[0].tags == sheet.topology.faces[0].tags.union([TopoTag(tag, .endCap)]))
        // Each boundary edge keeps its source edge's tags, paired by position.
        for edge in offset.topology.edges {
            let source = try #require(sheet.topology.edges.first {
                abs($0.midpoint.x - edge.midpoint.x) < 1e-6 && abs($0.midpoint.y - edge.midpoint.y) < 1e-6
            })
            #expect(edge.tags == source.tags && !edge.tags.isEmpty)
        }
    }

    @Test func aQuarterCylinderOffsetsToTheRightRadius() async throws {
        let sheet = try await quarterCylinder()
        let outer = try await kernel.offsetSurface(sheet, distance: 3, tag: tag)
        let inner = try await kernel.offsetSurface(sheet, distance: -3, tag: tag)
        let big = Double.pi / 2 * 13 * 20
        let small = Double.pi / 2 * 7 * 20
        let areas = [outer.topology.faces[0].area, inner.topology.faces[0].area]
        let pair = areas[0] > areas[1] ? (areas[0], areas[1]) : (areas[1], areas[0])
        #expect(abs(pair.0 - big) / big < 1e-6 && abs(pair.1 - small) / small < 1e-6)
        let s = try await towardAxisSign(sheet)
        let toward = try await kernel.offsetSurface(sheet, distance: s * 3, tag: tag)
        #expect(abs(toward.topology.faces[0].area - small) / small < 1e-6)
    }

    @Test func pastTheRadiusNamesTheLargest() async throws {
        let sheet = try await quarterCylinder()
        let s = try await towardAxisSign(sheet)
        let text = try #require(await refusal { try await kernel.offsetSurface(sheet, distance: s * 12, tag: tag) })
        let shown = (s * 12).millimetreText()
        #expect(text.hasPrefix("The surface can't be offset by \(shown) mm; the most that works is \(s < 0 ? "-" : "")9.9"))
        let away = try await kernel.offsetSurface(sheet, distance: -s * 12, tag: tag)
        #expect(away.topology.faces.count == 1)
    }

    @Test func theQuarterCylindersCurvatureLimitsAreItsRadiusAndNone() async throws {
        let sheet = try await quarterCylinder()
        let limits = [try await kernel.curvatureLimit(of: sheet, sign: 1), try await kernel.curvatureLimit(of: sheet, sign: -1)]
        let finite = limits.filter { $0.isFinite }
        #expect(finite.count == 1)
        #expect(abs((finite.first ?? 0) - 10) < 1e-6)
        #expect(limits.contains { $0 == .infinity })
    }

    @Test func offsetFailedWordsEachBranch() {
        func text(_ error: KernelError) -> String { message(error) }
        #expect(text(.offsetFailed(distance: -12, largest: nil)) == "The surface can't be offset by -12 mm; even -0.01 mm fails.")
        #expect(text(.offsetFailed(distance: 12, largest: nil, thickening: true))
            == "The surface can't be thickened by 12 mm; even 0.01 mm fails.")
        #expect(text(.offsetFailed(distance: 0.01, largest: nil)) == "The surface can't be offset by 0.01 mm.")
        #expect(text(.offsetFailed(distance: -12, largest: 9.9))
            == "The surface can't be offset by -12 mm; the most that works is -9.9 mm.")
    }

    @Test func anLSheetOffsetsAcrossItsSharpEdge() async throws {
        let line = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
        ], tag: newTag())
        let sheet = try await kernel.extrude(line, direction: Vector3(0, 0, 1), distance: 10, symmetric: false, tag: newTag())
        let offset = try await kernel.offsetSurface(sheet, distance: 1, tag: tag)
        #expect(offset.topology.faces.count == 2)
        let shape = try await kernel.shape(of: offset)
        let tolerance = try OCCTKernel.serialized { () throws -> Double in try shape.maxEdgeTolerance() }
        #expect(tolerance <= 0.01)
    }

    @Test func aFoldIsRefused() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 3, vCount: 3, degree: 1, tag: newTag())
        let folded = try await kernel.movingPoles(
            of: sheet, by: [PoleMove(index: PoleIndex(i: 0, j: 0), offset: Vector3(6, 6, 0))])
        let text = try #require(await refusal { try await kernel.offsetSurface(folded, distance: 1, tag: tag) })
        #expect(text == "The surface folds over itself, so it can't be offset; move its control points apart first.")
    }

    @Test func touchingLooseFacesAreRefused() async throws {
        let touching = try await kernel.compound([square(x: 0...10), square(x: 10...20)], tag: newTag())
        let text = try #require(await refusal { try await kernel.offsetSurface(touching, distance: 1, tag: tag) })
        #expect(text == "Parts of the surface touch but aren't joined; Sew them first.")
        let apart = try await kernel.compound([square(x: 0...10), square(x: 15...25)], tag: newTag())
        let offset = try await kernel.offsetSurface(apart, distance: 1, tag: tag)
        #expect(offset.topology.faces.count == 2)
    }

    @Test func aSheetWhoseOwnEdgesTouchIsNotRefused() async throws {
        let sheet = try await kernel.wrappedSheet(radius: 10, height: 10, tag: newTag())
        let touches = try await kernel.touchesItself(sheet)
        #expect(touches == false)
        // Recorded outcome: OCCT's offset of this wrapped surface is never valid at 1 mm either way, so the search names a tiny
        // distance; the point is that R11's sentence is not the refusal.
        for distance in [1.0, -1.0] {
            let text = try #require(await refusal { try await kernel.offsetSurface(sheet, distance: distance, tag: tag) })
            #expect(text.hasPrefix("The surface can't be offset by \(distance.millimetreText()) mm; the most that works is"))
        }
    }

    @Test func aValueHoldingASolidIsRefused() async throws {
        let box = try await box(kernel, 10, 10, 10)
        let mixed = try await kernel.compound([box, square(x: 20...30)], tag: newTag())
        let text = try #require(await refusal { try await kernel.offsetSurface(mixed, distance: 1, tag: tag) })
        #expect(text == "Offset Surface takes sheets only; this value also holds a closed solid.")
    }

    @Test func aCancelledOffsetThrows() async throws {
        let sheet = try await square()
        let task = Task { () async throws -> Solid in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.offsetSurface(sheet, distance: 1, tag: tag)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    actor Counter {
        var count = 0
        func next() -> Int { count += 1; return count }
    }

    @Test func theSearchStopsWhenCancelled() async throws {
        let counter = Counter()
        let kernel = self.kernel
        let task = Task { () async throws -> Double? in
            try await kernel.largestValidOffset(below: 5, limit: .infinity) { _ in
                if await counter.next() == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                return false
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await counter.count <= 3)
    }

    @Test func refusals() async throws {
        let box = try await box(kernel, 10, 10, 10)
        let closed = try #require(await refusal { try await kernel.offsetSurface(box, distance: 1, tag: tag) })
        #expect(closed == "Offset Surface takes a sheet; this is a closed solid.")
        let sheet = try await square()
        let zero = try #require(await refusal { try await kernel.offsetSurface(sheet, distance: 0, tag: tag) })
        #expect(zero == "The distance can't be 0.")
    }
}
#endif
