#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 Task 4: the boundary patch at G0 and G1.
struct BoundaryPatchTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func line(_ a: Vector3, _ b: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(a, b)], tag: tag)
    }

    /// The closed polygon through `points`, one line each.
    func polygon(_ points: [Vector3]) async throws -> [Curve] {
        var lines: [Curve] = []
        for index in points.indices {
            lines.append(try await line(points[index], points[(index + 1) % points.count]))
        }
        return lines
    }

    func square(z: Double = 0, size: Double = 10, origin: Vector3 = .zero) async throws -> [Curve] {
        try await polygon([Vector3(0, 0, z), Vector3(size, 0, z), Vector3(size, size, z), Vector3(0, size, z)]
            .map { $0 + origin })
    }

    func patch(_ curves: [Curve], points: [Vector3] = [], continuity: PatchContinuity = .g0) async throws -> PatchResult {
        try await kernel.boundaryPatch(PatchBoundary(curves: curves, edges: [], part: nil), interior: points, interior: [],
                                       continuity: continuity, tag: tag)
    }

    func refusal(_ curves: [Curve]) async -> String? {
        do { _ = try await patch(curves) } catch { return message(of: error) }
        return nil
    }

    @Test func fourLinesMakeAFlatSquare() async throws {
        let result = try await patch(try await square())
        let sheet = result.sheet
        #expect(sheet.topology.faces.count == 1 && !sheet.isClosed)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 100, relative: 1e-6))
        #expect(abs(sheet.bounds.max.z) < 1e-4 && abs(sheet.bounds.min.z) < 1e-4)
        #expect(result.warnings.isEmpty)
    }

    @Test func aLensOfTwoArcs() async throws {
        // Two circles of radius 5 centred at (0, -3) and (0, 3) cross at (+-4, 0).
        let sweep = Double.pi - 2 * atan2(3.0, 4.0)
        let first = CurvePiece.arc(center: Vector3(0, -3, 0), normal: .unitZ, radius: 5, start: Vector3(4, 0, 0), sweep: sweep)
        let second = CurvePiece.arc(center: Vector3(0, 3, 0), normal: .unitZ, radius: 5, start: Vector3(-4, 0, 0), sweep: sweep)
        let upper = try await kernel.makeCurve([first], tag: tag)
        let lower = try await kernel.makeCurve([second], tag: tag)
        let sheet = try await patch([upper, lower]).sheet
        let lens = 2 * (25 * acos(0.6) - 3 * 4)
        #expect(abs(try await kernel.properties(of: sheet).surfaceArea - lens) < 1e-3)
    }

    @Test func aGapIsRefusedNamingThePieces() async throws {
        let lines = [
            try await line(Vector3(0, 0, 0), Vector3(10, 0, 0)), try await line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
            try await line(Vector3(10.5, 10, 0), Vector3(0, 10, 0)), try await line(Vector3(0, 10, 0), Vector3(0, 0, 0)),
        ]
        #expect(await refusal(lines) == "The bounding pieces don't form a closed loop; pieces 2 and 3 are 0.5 mm apart.")
    }

    @Test func seventeenPiecesAreRefused() async throws {
        let points = (0..<17).map { Vector3(5 * cos(Double($0) * 2 * .pi / 17), 5 * sin(Double($0) * 2 * .pi / 17), 0) }
        #expect(await refusal(try await polygon(points)) == "A patch needs 2 to 16 bounding pieces.")
        #expect(await refusal([try await line(.zero, Vector3(1, 0, 0))]) == "A patch needs 2 to 16 bounding pieces.")
    }

    @Test func twoLoopsAreRefused() async throws {
        let both = try await square() + (try await square(origin: Vector3(30, 0, 0)))
        #expect(await refusal(both) == "The bounding pieces form more than one loop.")
    }

    @Test func throughAPointBulges() async throws {
        let point = Vector3(5, 5, 2)
        let sheet = try await patch(try await square(), points: [point]).sheet
        let near = try await kernel.distances(from: [point], to: .solid(sheet), signed: false)
        #expect(near[0] <= 1e-3)
        #expect(sheet.bounds.max.z > 1.9)
    }

    @Test func pointsThatContradictAreRefused() async throws {
        // Two points 2 mm apart on one vertical line cannot both be on a patch that is a graph over the square: OCCT either
        // cannot build it or misses the boundary; either way the patch is refused in words and nothing is returned.
        await #expect {
            try await patch(try await square(), points: [Vector3(5, 5, 2), Vector3(5, 5, -2)])
        } throws: { message(of: $0)?.hasPrefix("The patch ") == true }
    }

    @Test func g1WithOnlyCurvesWarns() async throws {
        let result = try await patch(try await square(), continuity: .g1)
        #expect(result.warnings == ["No bounding edge lies on a surface, so the patch is only G0."])
    }

    @Test func namesThePieces() async throws {
        let sheet = try await patch(try await square()).sheet
        #expect(sheet.topology.faces[0].tags.contains(TopoTag(tag, .startCap)))
        let mids = [Vector3(5, 0, 0), Vector3(10, 5, 0), Vector3(5, 10, 0), Vector3(0, 5, 0)]
        for (k, mid) in mids.enumerated() {
            let edge = sheet.topology.edges.filter { $0.tags.contains(TopoTag(tag, .boundary(.piece(loop: 0, segment: k)))) }
            #expect(edge.count == 1)
            #expect(edge.allSatisfy { ($0.midpoint - mid).length < 1e-6 })
        }
    }

    @Test func aCancelledTaskStopsThePatch() async throws {
        let curves = try await square()
        let kernel = self.kernel
        let tag = self.tag
        let task = Task {
            try await kernel.boundaryPatch(PatchBoundary(curves: curves, edges: [], part: nil), interior: [], interior: [],
                                           continuity: .g0, tag: tag)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func g2IsNotYetAvailable() async throws {
        await #expect(throws: KernelError.self) { try await patch(try await square(), continuity: .g2) }
    }

    // MARK: A hole in a sheet

    /// Half a circle of radius `r` at height `z`, then the other half: a closed section of two pieces.
    func ring(z: Double, r: Double) async throws -> Curve {
        try await kernel.makeCurve([
            .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: r, start: Vector3(r, 0, z), sweep: .pi),
            .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: r, start: Vector3(-r, 0, z), sweep: .pi),
        ], tag: tag)
    }

    /// A smooth open bell, 5 mm in radius at the bottom and 3 mm at the top, and the two edges of its open top. (Two offset
    /// squares lofted instead have walls that meet at corners with different tangent planes, so no patch can be tangent to all
    /// four at once: the fill then misses the corner by 0.077 mm and the patch is refused.)
    func bell() async throws -> (sheet: Solid, top: [EdgeID]) {
        let sections = [try await ring(z: 0, r: 5), try await ring(z: 5, r: 4.5), try await ring(z: 10, r: 3)]
        let sheet = try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
        let edges = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }.map(\.id)
        return (sheet, edges)
    }

    @Test func aG1PatchClosesASheetsHole() async throws {
        let (sheet, top) = try await bell()
        #expect(top.count == 2)
        let result = try await kernel.boundaryPatch(PatchBoundary(curves: [], edges: top, part: sheet), interior: [], interior: [],
                                                    continuity: .g1, tag: tag)
        #expect(result.warnings.isEmpty)
        #expect(result.sheet.topology.faces.count == 1)
        for k in 0..<2 {
            let role = TopoTag(tag, .boundary(.piece(loop: 0, segment: k)))
            let edge = try #require(result.sheet.topology.edges.first { $0.tags.contains(role) })
            // Piece k is the k-th picked edge.
            #expect((edge.midpoint - sheet.topology.edges[top[k].rawValue].midpoint).length < 1e-6)
            let face = try #require(sheet.topology.edges[top[k].rawValue].faces.first)
            let found = try await kernel.continuity(of: edge.id, in: result.sheet, against: face, of: sheet)
            #expect(found.grade >= .g1, "piece \(k + 1): \(found)")
            #expect(found.positionGap < 1e-4)
        }
    }

    @Test func aHolesEdgesAtG0AreOnlyG0() async throws {
        let (sheet, top) = try await bell()
        let result = try await kernel.boundaryPatch(PatchBoundary(curves: [], edges: top, part: sheet), interior: [], interior: [],
                                                    continuity: .g0, tag: tag)
        let role = TopoTag(tag, .boundary(.piece(loop: 0, segment: 0)))
        let edge = try #require(result.sheet.topology.edges.first { $0.tags.contains(role) })
        let face = try #require(sheet.topology.edges[top[0].rawValue].faces.first)
        let found = try await kernel.continuity(of: edge.id, in: result.sheet, against: face, of: sheet)
        #expect(found.positionGap < 1e-4)
    }

    @Test func aMixOfCurvesAndEdgesFormsOneLoop() async throws {
        // A bell's top is two edges; the patch is bounded by one of them and a curve (an arc) that replaces the other.
        let (sheet, top) = try await bell()
        let other = sheet.topology.edges[top[1].rawValue]
        let half = CurvePiece.arc(center: Vector3(0, 0, 10), normal: .unitZ, radius: 3, start: Vector3(-3, 0, 10), sweep: .pi)
        let arc = try await kernel.makeCurve([half], tag: tag)
        #expect(abs(other.midpoint.y + 3) < 1e-6 || abs(other.midpoint.y - 3) < 1e-6)
        let result = try await kernel.boundaryPatch(PatchBoundary(curves: [arc], edges: [top[0]], part: sheet), interior: [], interior: [],
                                                    continuity: .g1, tag: tag)
        #expect(result.sheet.topology.faces.count == 1)
    }
}
#endif
