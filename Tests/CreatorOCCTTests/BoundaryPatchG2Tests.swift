#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-2 Task 5: the boundary patch at G2, over three and four sides.
///
/// The fixtures are sheets cut from one smooth surface (a cylinder, a sphere) around a small window: four panels around a
/// window of a cylinder, three around a spherical triangle. A tube's end loop split into four arcs (the brief's first idea)
/// is a smooth closed curve, so its four "corners" are straight angles and no regular four-sided patch has them.
struct BoundaryPatchG2Tests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func line(_ a: Vector3, _ b: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(a, b)], tag: tag)
    }

    func edgeID(of solid: Solid, near point: Vector3) throws -> EdgeID {
        let found = solid.topology.edges.first { ($0.midpoint - point).length < 1e-6 }
        return try #require(found, "no edge near \(point)").id
    }

    /// The patch over the picked `edges` of `part` and `curves`, at G2.
    func patch(edges: [EdgeID], of part: Solid?, curves: [Curve] = []) async throws -> PatchResult {
        try await kernel.boundaryPatch(PatchBoundary(curves: curves, edges: edges, part: part), interior: [], interior: [],
                                       continuity: .g2, tag: tag)
    }

    /// Asserts every picked edge's patch piece grades G2 against its own panel, and returns the worst gaps.
    func expectG2(_ result: PatchResult, edges: [EdgeID], of part: Solid, firstPiece: Int = 0) async throws {
        for (k, picked) in edges.enumerated() {
            let mid = part.topology.edges[picked.rawValue].midpoint
            let patchEdge = try #require(result.sheet.topology.edges.first { edge in
                (edge.midpoint - mid).length < 1e-5 && edge.tags.contains { entry in
                    if case .boundary(.piece(loop: 0, segment: _)) = entry.role { return true }
                    return false
                }
            }, "no patch edge for piece \(k + 1)")
            let face = try #require(part.topology.edges[picked.rawValue].faces.first)
            let found = try await kernel.continuity(of: patchEdge.id, in: result.sheet, against: face, of: part)
            #expect(found.grade == .g2, "piece \(k + firstPiece + 1): \(found)")
            #expect(found.positionGap < 1e-4, "piece \(k + firstPiece + 1): \(found)")
        }
    }

    // MARK: A window in a cylinder

    static let radius = 20.0
    static let span = 10.0 * Double.pi / 180
    static let height = 3.5

    /// The cylinder sheet over angles `from` to `from + span` and heights `z0` to `z0 + height`.
    func cylinderPanel(from angle: Double, z0: Double) async throws -> Solid {
        let r = Self.radius
        let piece = CurvePiece.arc(center: Vector3(0, 0, z0), normal: .unitZ, radius: r,
                                   start: Vector3(r * cos(angle), r * sin(angle), z0), sweep: Self.span)
        let arc = try await kernel.makeCurve([piece], tag: tag)
        return try await kernel.extrude(arc, direction: .unitZ, distance: Self.height, symmetric: false, tag: tag)
    }

    /// Four panels around the window (0 to 10 degrees, 0 to 3.5 mm), and the window's four edges: bottom, right, top, left.
    func cylinderWindow() async throws -> (part: Solid, edges: [EdgeID]) {
        let span = Self.span
        let panels = [
            try await cylinderPanel(from: -span, z0: 0), try await cylinderPanel(from: span, z0: 0),
            try await cylinderPanel(from: 0, z0: -Self.height), try await cylinderPanel(from: 0, z0: Self.height),
        ]
        let part = try await kernel.compound(panels, tag: tag)
        let r = Self.radius
        let mid = span / 2
        let marks = [
            Vector3(r * cos(mid), r * sin(mid), 0), Vector3(r * cos(span), r * sin(span), Self.height / 2),
            Vector3(r * cos(mid), r * sin(mid), Self.height), Vector3(r, 0, Self.height / 2),
        ]
        return (part, try marks.map { try edgeID(of: part, near: $0) })
    }

    @Test func aFourSidedG2PatchFillsAWindowInACylinder() async throws {
        let (part, edges) = try await cylinderWindow()
        let result = try await patch(edges: edges, of: part)
        #expect(result.warnings.isEmpty)
        #expect(result.sheet.topology.faces.count == 1)
        try await expectG2(result, edges: edges, of: part)
        let area = try await kernel.properties(of: result.sheet).surfaceArea
        #expect(abs(area - Self.radius * Self.span * Self.height) < 1e-3, "area \(area)")
        // The patch stays on the cylinder it fills.
        let r = Self.radius
        let samples = (1...3).flatMap { i in (1...3).map { j in
            let a = Self.span * Double(i) / 4, z = Self.height * Double(j) / 4
            return Vector3(r * cos(a), r * sin(a), z)
        } }
        let distances = try await kernel.distances(from: samples, to: .solid(result.sheet), signed: false)
        #expect((distances.max() ?? 1) < 1e-4, "\(distances)")
    }

    @Test func g2PieceNamesFollowTheLoop() async throws {
        let (part, edges) = try await cylinderWindow()
        let sheet = try await patch(edges: edges, of: part).sheet
        for (k, picked) in edges.enumerated() {
            let role = TopoTag(tag, .boundary(.piece(loop: 0, segment: k)))
            let found = try #require(sheet.topology.edges.first { $0.tags.contains(role) })
            #expect((found.midpoint - part.topology.edges[picked.rawValue].midpoint).length < 1e-5)
        }
    }

    // MARK: A triangle in a sphere

    static let ball = 10.0

    func vertex(_ k: Int, stand: Double = 6) -> Vector3 {
        let phi = (90 + 120 * Double(k)) * .pi / 180, rho = stand * .pi / 180
        return Vector3(Self.ball * sin(rho) * cos(phi), Self.ball * sin(rho) * sin(phi), Self.ball * cos(rho))
    }

    /// The sphere sheet outside the great-circle arc from `a` to `b`, away from `c`, 8 degrees wide.
    func spherePanel(_ a: Vector3, _ b: Vector3, awayFrom c: Vector3) async throws -> Solid {
        let m = try #require(a.cross(b).normalized)
        let away = c.dot(m) > 0 ? m * -1 : m
        let around = try #require(a.cross(away).normalized)
        let piece = CurvePiece.arc(center: .zero, normal: around, radius: Self.ball, start: a, sweep: 8 * .pi / 180)
        let arc = try await kernel.makeCurve([piece], tag: tag)
        let angle = acos(a.dot(b) / (Self.ball * Self.ball))
        return try await kernel.revolve(arc, axis: Axis(origin: .zero, direction: m), angle: Angle(radians: angle), tag: tag)
    }

    func sphereTriangle() async throws -> (part: Solid, edges: [EdgeID]) {
        let v = (0..<3).map { vertex($0) }
        var panels: [Solid] = []
        for k in 0..<3 {
            panels.append(try await spherePanel(v[k], v[(k + 1) % 3], awayFrom: v[(k + 2) % 3]))
        }
        let part = try await kernel.compound(panels, tag: tag)
        var edges: [EdgeID] = []
        for k in 0..<3 {
            let sum = v[k] + v[(k + 1) % 3]
            let mid = try #require(sum.normalized) * Self.ball
            edges.append(try edgeID(of: part, near: mid))
        }
        return (part, edges)
    }

    @Test func aThreeSidedG2PatchFillsATriangleInASphere() async throws {
        let (part, edges) = try await sphereTriangle()
        let result = try await patch(edges: edges, of: part)
        #expect(result.warnings.isEmpty)
        #expect(result.sheet.topology.faces.count == 1)
        try await expectG2(result, edges: edges, of: part)
        // The patch stays on the sphere it fills (the centroid of the triangle, and halfway to each corner).
        let centre = try #require((vertex(0) + vertex(1) + vertex(2)).normalized) * Self.ball
        var toward: [Vector3] = []
        for k in 0..<3 { toward.append(try #require((centre + vertex(k)).normalized) * Self.ball) }
        let distances = try await kernel.distances(from: [centre] + toward, to: .solid(result.sheet), signed: false)
        #expect((distances.max() ?? 1) < 1e-3, "\(distances)")
    }

    /// Four panels around the spherical square of four great-circle arcs (3 degrees from the pole to a corner), and its four edges.
    func sphereSquare() async throws -> (part: Solid, edges: [EdgeID]) {
        let corners = (0..<4).map { k -> Vector3 in
            let phi = (45 + 90 * Double(k)) * .pi / 180, rho = 3.0 * .pi / 180
            return Vector3(Self.ball * sin(rho) * cos(phi), Self.ball * sin(rho) * sin(phi), Self.ball * cos(rho))
        }
        let centre = Vector3(0, 0, Self.ball)
        var panels: [Solid] = []
        for k in 0..<4 {
            panels.append(try await spherePanel(corners[k], corners[(k + 1) % 4], awayFrom: centre))
        }
        let part = try await kernel.compound(panels, tag: tag)
        var edges: [EdgeID] = []
        for k in 0..<4 {
            let mid = try #require((corners[k] + corners[(k + 1) % 4]).normalized) * Self.ball
            edges.append(try edgeID(of: part, near: mid))
        }
        return (part, edges)
    }

    @Test func aFourSidedG2PatchFillsASphericalSquare() async throws {
        // Its corners are a tenth of a degree over 90, so the cross directions run just obliquely from one leg to the other.
        let (part, edges) = try await sphereSquare()
        let result = try await patch(edges: edges, of: part)
        #expect(result.warnings.isEmpty)
        #expect(result.sheet.topology.faces.count == 1)
        try await expectG2(result, edges: edges, of: part)
        let distances = try await kernel.distances(from: [Vector3(0, 0, Self.ball)], to: .solid(result.sheet), signed: false)
        #expect((distances.max() ?? 1) < 1e-3, "\(distances)")
    }

    // MARK: Flat plates

    /// A flat sheet: the line from `a` to `b` swept by `direction` over `distance`.
    func plate(_ a: Vector3, _ b: Vector3, direction: Vector3, distance: Double = 10) async throws -> Solid {
        try await kernel.extrude(try await line(a, b), direction: direction, distance: distance, symmetric: false, tag: tag)
    }

    /// Four plates around the 10 mm square hole at the origin; `top` is swept along `topDirection`.
    func squareHole(topDirection: Vector3 = Vector3(0, 1, 0)) async throws -> (part: Solid, edges: [EdgeID]) {
        let panels = [
            try await plate(Vector3(0, 0, 0), Vector3(10, 0, 0), direction: Vector3(0, -1, 0)),
            try await plate(Vector3(10, 0, 0), Vector3(10, 10, 0), direction: Vector3(1, 0, 0)),
            try await plate(Vector3(10, 10, 0), Vector3(0, 10, 0), direction: topDirection),
            try await plate(Vector3(0, 10, 0), Vector3(0, 0, 0), direction: Vector3(-1, 0, 0)),
        ]
        let part = try await kernel.compound(panels, tag: tag)
        let marks = [Vector3(5, 0, 0), Vector3(10, 5, 0), Vector3(5, 10, 0), Vector3(0, 5, 0)]
        return (part, try marks.map { try edgeID(of: part, near: $0) })
    }

    @Test func aFlatSquareHoleIsFilledAtG2() async throws {
        let (part, edges) = try await squareHole()
        let result = try await patch(edges: edges, of: part)
        try await expectG2(result, edges: edges, of: part)
        #expect(abs(try await kernel.properties(of: result.sheet).surfaceArea - 100) < 1e-6)
    }

    @Test func curvesBesideSheetsAreHeldAtG0() async throws {
        // Two plates with a 10 mm gap between them and a line along each open side: only the plates' edges are graded.
        let left = try await plate(Vector3(0, 0, 0), Vector3(0, 10, 0), direction: Vector3(-1, 0, 0))
        let right = try await plate(Vector3(10, 10, 0), Vector3(10, 0, 0), direction: Vector3(1, 0, 0))
        let part = try await kernel.compound([left, right], tag: tag)
        let edges = [try edgeID(of: part, near: Vector3(0, 5, 0)), try edgeID(of: part, near: Vector3(10, 5, 0))]
        let curves = [try await line(Vector3(0, 0, 0), Vector3(10, 0, 0)), try await line(Vector3(10, 10, 0), Vector3(0, 10, 0))]
        let result = try await patch(edges: edges, of: part, curves: curves)
        #expect(result.warnings.isEmpty)
        try await expectG2(result, edges: edges, of: part)
    }
}

// MARK: Refusals

extension BoundaryPatchG2Tests {

    func unitSquare() async throws -> [Curve] {
        [
            try await line(Vector3(0, 0, 0), Vector3(10, 0, 0)), try await line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
            try await line(Vector3(10, 10, 0), Vector3(0, 10, 0)), try await line(Vector3(0, 10, 0), Vector3(0, 0, 0)),
        ]
    }

    @Test func sixCurvesAtG2AreHeldAtG0WhateverTheSideCount() async throws {
        // R2's fallback comes before the side count: no piece lies on a sheet, so the loop is filled at G0 with R2's warning.
        let points = (0..<6).map { Vector3(5 * cos(Double($0) * .pi / 3), 5 * sin(Double($0) * .pi / 3), 0) }
        var lines: [Curve] = []
        for k in 0..<6 { lines.append(try await line(points[k], points[(k + 1) % 6])) }
        let result = try await patch(edges: [], of: nil, curves: lines)
        #expect(result.warnings == ["No bounding edge is a sheet's open edge, so the patch is only G0."])
    }

    @Test func sixSheetsAtG2AreRefused() async throws {
        let points = (0..<6).map { Vector3(5 * cos(Double($0) * .pi / 3), 5 * sin(Double($0) * .pi / 3), 0) }
        var panels: [Solid] = []
        for k in 0..<6 {
            let mid = (points[k] + points[(k + 1) % 6]) * 0.5
            panels.append(try await plate(points[k], points[(k + 1) % 6], direction: try #require(mid.normalized), distance: 4))
        }
        let part = try await kernel.compound(panels, tag: tag)
        let edges = try (0..<6).map { k in try edgeID(of: part, near: (points[k] + points[(k + 1) % 6]) * 0.5) }
        await #expect {
            try await patch(edges: edges, of: part)
        } throws: { message(of: $0) == "A G2 patch needs 3 or 4 sides; this loop has 6." }
    }

    @Test func g2WithOnlyCurvesWarnsLikeG1() async throws {
        let square = try await unitSquare()
        let result = try await patch(edges: [], of: nil, curves: square)
        #expect(result.warnings == ["No bounding edge is a sheet's open edge, so the patch is only G0."])
    }

    @Test func aWholeCircleInFourArcsIsTooComplexForAQuintic() async throws {
        // A tube's end loop (a circle in four quarter arcs): each arc is more than 1e-7 mm off any quintic, and the loop is
        // smooth, so its four corners are straight angles. The first refusal is the fit.
        func ring(z: Double) async throws -> Curve {
            try await kernel.makeCurve((0..<4).map { k in
                let angle = Double(k) * .pi / 2
                return .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: 5, start: Vector3(5 * cos(angle), 5 * sin(angle), z),
                            sweep: .pi / 2)
            }, tag: tag)
        }
        let tube = try await kernel.loftSurface([try await ring(z: 0), try await ring(z: 8)], ruled: false, closed: false, tag: tag)
        let ends = tube.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }.map(\.id)
        #expect(ends.count == 4)
        await #expect {
            try await patch(edges: ends, of: tube)
        } throws: { message(of: $0) == "Piece 1 can't be followed exactly by a G2 patch; use G1 for this hole." }
    }

    @Test func anIncompatibleCornerIsRefused() async throws {
        // The top plate is tilted 45 degrees out of the others' plane: at the corners it shares with the left and right plates
        // the tangent planes differ, and no patch is tangent to both.
        let tilt = Vector3(0, cos(Double.pi / 4), sin(Double.pi / 4))
        let (part, edges) = try await squareHole(topDirection: tilt)
        await #expect {
            try await patch(edges: edges, of: part)
        } throws: { message(of: $0) == Self.quadCorner(2) }
    }

    static func quadCorner(_ n: Int) -> String {
        "The surfaces meet at corner \(n) in a way a G2 patch can't follow; a four-sided G2 patch needs corners close to 90° and "
            + "sides that run straight across their surfaces. Use G1 for this hole."
    }

    /// A flat square hole whose left panel is a cylinder tangent to the plane along their shared line: the tangent planes
    /// agree along the whole side, but the panels' normal curvatures across it (0 and 1/20) do not, at either corner.
    @Test func disagreeingNormalCurvaturesAtACornerAreRefused() async throws {
        let radius = 20.0
        let piece = CurvePiece.arc(center: Vector3(0, 0, radius), normal: Vector3(0, 1, 0), radius: radius, start: .zero,
                                   sweep: 0.3)
        let arc = try await kernel.makeCurve([piece], tag: tag)
        let left = try await kernel.extrude(arc, direction: Vector3(0, 1, 0), distance: 10, symmetric: false, tag: tag)
        let panels = [
            try await plate(Vector3(0, 0, 0), Vector3(10, 0, 0), direction: Vector3(0, -1, 0)),
            try await plate(Vector3(10, 0, 0), Vector3(10, 10, 0), direction: Vector3(1, 0, 0)),
            try await plate(Vector3(10, 10, 0), Vector3(0, 10, 0), direction: Vector3(0, 1, 0)), left,
        ]
        let part = try await kernel.compound(panels, tag: tag)
        let marks = [Vector3(5, 0, 0), Vector3(10, 5, 0), Vector3(5, 10, 0), Vector3(0, 5, 0)]
        let edges = try marks.map { try edgeID(of: part, near: $0) }
        await #expect {
            try await patch(edges: edges, of: part)
        } throws: { message(of: $0) == Self.quadCorner(1) }
    }

    /// Three flat plates around a triangular hole with one of them a cylinder tangent along its edge: the triangle's corner
    /// blocks cannot be reconciled.
    @Test func aTriangleWithDisagreeingCurvaturesIsRefused() async throws {
        let v = (0..<3).map { k -> Vector3 in
            let a = (90 + 120 * Double(k)) * .pi / 180
            return Vector3(6 * cos(a), 6 * sin(a), 0)
        }
        let radius = 20.0
        var panels: [Solid] = []
        for k in 0..<3 {
            let a = v[k], b = v[(k + 1) % 3]
            let outward = try #require(((a + b) * 0.5).normalized)
            if k == 0 {
                let along = try #require((b - a).normalized)
                // Turning about the edge's direction carries the start sideways; sweep the way that leads away from the hole.
                let sideways = along.cross(Vector3(0, 0, -1)).dot(outward)
                let piece = CurvePiece.arc(center: a + Vector3(0, 0, radius), normal: along, radius: radius, start: a,
                                           sweep: sideways > 0 ? 0.3 : -0.3)
                let arc = try await kernel.makeCurve([piece], tag: tag)
                panels.append(try await kernel.extrude(arc, direction: b - a, distance: (b - a).length, symmetric: false, tag: tag))
            } else {
                panels.append(try await plate(a, b, direction: outward, distance: 4))
            }
        }
        let part = try await kernel.compound(panels, tag: tag)
        let edges = try (0..<3).map { k in try edgeID(of: part, near: (v[k] + v[(k + 1) % 3]) * 0.5) }
        await #expect {
            try await patch(edges: edges, of: part)
        } throws: { message(of: $0) == "The surfaces meet at corner 1 in a way a G2 patch can't follow. Use G1 for this hole." }
    }

    @Test func aThreeSidedPatchWithOneCurveSideKeepsItsSheetsAtG2() async throws {
        // A flat triangular hole: two plates and a line along the third side. Only the plates' edges are graded.
        let v = (0..<3).map { k -> Vector3 in
            let a = (90 + 120 * Double(k)) * .pi / 180
            return Vector3(6 * cos(a), 6 * sin(a), 0)
        }
        var panels: [Solid] = []
        for k in 0..<2 {
            let outward = try #require(((v[k] + v[k + 1]) * 0.5).normalized)
            panels.append(try await plate(v[k], v[k + 1], direction: outward, distance: 4))
        }
        let part = try await kernel.compound(panels, tag: tag)
        let edges = try (0..<2).map { k in try edgeID(of: part, near: (v[k] + v[k + 1]) * 0.5) }
        let result = try await patch(edges: edges, of: part, curves: [try await line(v[2], v[0])])
        #expect(result.warnings.isEmpty)
        #expect(result.sheet.topology.faces.count == 1)
        try await expectG2(result, edges: edges, of: part)
    }
}
#endif
