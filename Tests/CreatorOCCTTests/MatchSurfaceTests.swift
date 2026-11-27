#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-4 Task 8: `Kernel.matched(_:edge:to:of:continuity:)` (R9).
struct MatchSurfaceTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    /// A, a ruled Loft Surface of two lines; its `.boundary(.end)` edge is the line on x = 10. `lowered` drops the start line to z = -2.
    func sheetA(lowered: Bool = false) async throws -> Solid {
        let z = lowered ? -2.0 : 0.0
        let first = try await kernel.makeCurve([.line(Vector3(0, 0, z), Vector3(0, 10, z))], tag: tag)
        let second = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 10, 0))], tag: tag)
        return try await kernel.loftSurface([first, second], ruled: true, closed: false, tag: tag)
    }

    /// B, a Revolve Curve sheet of a line at x = 10 about an axis parallel to y, 60 degrees. Its start edge is the line x = 10, z = 0.
    func sheetB(from: Double = 0, to: Double = 10, axisZ: Double = 17.3205, shift: Vector3 = .zero) async throws -> Solid {
        let line = try await kernel.makeCurve([.line(Vector3(10, from, 0) + shift, Vector3(10, to, 0) + shift)], tag: tag)
        return try await kernel.revolve(line, axis: Axis(origin: Vector3(0, 0, axisZ), direction: Vector3(0, -1, 0)),
                                        angle: .degrees(60), tag: tag)
    }

    func endEdge(_ sheet: Solid) throws -> EdgeInfo {
        try #require(sheet.topology.edges.first { $0.tags.contains(TopoTag(tag, .boundary(.end))) })
    }

    /// The straight edge of `sheet` through x = 10, z = 0 (B's start edge, A's end edge).
    func lineAtX10(_ sheet: Solid) throws -> EdgeInfo {
        try #require(sheet.topology.edges.first {
            $0.kind == .line && abs($0.midpoint.x - 10) < 1e-6 && abs($0.midpoint.z) < 1e-6
        })
    }

    func grade(_ result: Solid, edge: EdgeID, against target: Solid, face: Int = 0) async throws -> EdgeContinuity {
        try await kernel.continuity(of: edge, in: result, against: FaceID(face), of: target)
    }

    func structure(_ topology: Topology) -> [String] {
        topology.faces.map { "f\($0.id.rawValue) \($0.tags.map(String.init(describing:)).sorted())" }
            + topology.edges.map { "e\($0.id.rawValue) \($0.faces.map(\.rawValue)) \($0.tags.map(String.init(describing:)).sorted())" }
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return "other: \(error)" }
        return nil
    }

    @Test func g0IsAlreadyMetByTheFixtures() async throws {
        let a = try await sheetA(), b = try await sheetB()
        let found = try await grade(a, edge: try endEdge(a).id, against: b)
        #expect(found.grade == .g0)
        #expect(found.positionGap < 1e-6)
    }

    @Test func g1MakesTheEdgeTangent() async throws {
        let a = try await sheetA(), b = try await sheetB()
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        let found = try await grade(result, edge: try endEdge(result).id, against: b)
        #expect(found.grade >= .g1, "angle \(found.angleGap)")
        #expect(found.positionGap <= 1e-4)
        #expect(result.hasOpenShell)
    }

    @Test func g2MakesItCurvatureContinuous() async throws {
        let a = try await sheetA(), b = try await sheetB()
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g2)
        let found = try await grade(result, edge: try endEdge(result).id, against: b)
        #expect(found.grade >= .g2, "angle \(found.angleGap) curvature \(found.curvatureGap) \(found.absoluteCurvatureGap)")
        #expect(found.positionGap <= 1e-4)
    }

    @Test func g0MeetsAWavyTarget() async throws {
        let a = try await sheetA()
        let wavy = [Vector3(10, 0, 0), Vector3(10, 3.3, 0.4), Vector3(10, 6.7, 0.4), Vector3(10, 10, 0)]
        let flat = wavy.map { Vector3(20, $0.y, 0) }
        func curve(_ poles: [Vector3]) async throws -> Curve {
            try await kernel.makeCurve([.spline(BSplineCurve3D(degree: 3, poles: poles, knots: [0, 1], multiplicities: [4, 4]))], tag: tag)
        }
        let target = try await kernel.loftSurface([try await curve(wavy), try await curve(flat)], ruled: true, closed: false, tag: tag)
        let edge = try #require(target.topology.edges.first { $0.faces.count == 1 && abs($0.midpoint.x - 10) < 1e-6 })
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: edge.id, of: target, continuity: .g0)
        let found = try await grade(result, edge: try endEdge(result).id, against: target)
        #expect(found.positionGap <= 1e-4, "gap \(found.positionGap)")
    }

    @Test func theOppositeEdgeStays() async throws {
        let a = try await sheetA(), b = try await sheetB()
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g2)
        let start = try #require(result.topology.edges.first { $0.tags.contains(TopoTag(tag, .boundary(.start))) })
        for i in 0..<9 {
            let point = Vector3(0, 10 * Double(i) / 8, 0)
            let gap = try await kernel.shortestDistance(between: .point(point), and: .edge(result, start.id)).distance
            #expect(gap < 1e-9, "gap \(gap)")
        }
    }

    @Test func topologyIsKept() async throws {
        let a = try await sheetA(), b = try await sheetB()
        for continuity in [PatchContinuity.g0, .g1, .g2] {
            let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: continuity)
            #expect(structure(result.topology) == structure(a.topology))
            #expect(result.topology.edges.map(\.faces) == a.topology.edges.map(\.faces))
        }
    }

    @Test func endsApartRefuse() async throws {
        let a = try await sheetA()
        let b = try await sheetB(from: 0.8, to: 10.8)
        let end = try endEdge(a).id, line = try lineAtX10(b).id
        let text = await refusal { _ = try await kernel.matched(a, edge: end, to: line, of: b, continuity: .g1) }
        #expect(text == "The edges' ends are 0.8 mm apart; Match needs them to meet.")
    }

    @Test func farApartEndsReadInPlainDecimals() async throws {
        let a = try await sheetA()
        let b = try await sheetB(from: 12, to: 22)
        let text = await refusal {
            _ = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        }
        #expect(text == "The edges' ends are 12 mm apart; Match needs them to meet.")
    }

    @Test func aSolidIsNotASheet() async throws {
        let box = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let b = try await sheetB()
        let text = await refusal {
            _ = try await kernel.matched(box, edge: box.topology.edges[0].id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        }
        #expect(text == "Match Surface takes a sheet; this is a closed solid.")
    }

    @Test func aSheetOfSeveralFacesRefuses() async throws {
        let rows = [0.0, 5, 10, 15]
        var sections: [Curve] = []
        for (i, x) in rows.enumerated() {
            sections.append(try await kernel.makeCurve([.line(Vector3(x, 0, Double(i % 2)), Vector3(x, 10, Double(i % 2)))], tag: tag))
        }
        let three = try await kernel.loftSurface(sections, ruled: true, closed: false, tag: tag)
        #expect(three.topology.faces.count == 3)
        let b = try await sheetB()
        let text = await refusal {
            _ = try await kernel.matched(three, edge: three.topology.edges[0].id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        }
        #expect(text == "Match Surface changes a sheet with one face; this one has 3.")
    }

    @Test func aTwoFaceEdgeRefuses() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 20))], tag: tag)
        let cylinder = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: .unitZ), angle: .degrees(360), tag: tag)
        let seam = try #require(cylinder.topology.edges.first { $0.isSeam })
        let b = try await sheetB()
        let text = await refusal { _ = try await kernel.matched(cylinder, edge: seam.id, to: try lineAtX10(b).id, of: b, continuity: .g1) }
        #expect(text == "Match Surface changes an open edge of the sheet; this edge has two faces.")
    }

    @Test func aTrimmedEdgeRefuses() async throws {
        func square(_ half: Double) async throws -> Curve {
            let c = [Vector3(-half, -half, 0), Vector3(half, -half, 0), Vector3(half, half, 0), Vector3(-half, half, 0)]
            return try await kernel.makeCurve(c.indices.map { .line(c[$0], c[($0 + 1) % 4]) }, tag: tag)
        }
        let plane = try await kernel.planarSurface([try await square(40), try await square(10)], tag: tag)
        let hole = try #require(plane.topology.edges.first { abs($0.midpoint.x) < 1e-6 && abs($0.midpoint.y + 10) < 1e-6 })
        let b = try await sheetB()
        let text = await refusal { _ = try await kernel.matched(plane, edge: hole.id, to: try lineAtX10(b).id, of: b, continuity: .g1) }
        #expect(text == "Match Surface works on an untrimmed edge of its surface; this edge is a trim.")
    }

    @Test func theTargetMustBeAnotherBody() async throws {
        let a = try await sheetA()
        let end = try endEdge(a)
        let text = await refusal { _ = try await kernel.matched(a, edge: end.id, to: end.id, of: a, continuity: .g1) }
        #expect(text == "The target edge must be on another body.")
    }

    @Test func aSolidTargetUsesTheContinuedFace() async throws {
        let a = try await sheetA(lowered: true)
        let moved = Transform(translation: Vector3(15, 5, -10))
        let cube = try await kernel.transform(try await box(kernel, 10, 10, 10), by: moved, tag: newTag())
        let edge = try #require(cube.topology.edges.first {
            $0.faces.count == 2 && abs($0.midpoint.x - 10) < 1e-6 && abs($0.midpoint.z) < 1e-6 && abs($0.midpoint.y - 5) < 1e-6
        })
        let top = try #require(cube.topology.faces.first { abs(($0.normal?.z ?? 0) - 1) < 1e-6 && abs($0.centroid.z) < 1e-6 })
        let before = try await grade(a, edge: try endEdge(a).id, against: cube, face: top.id.rawValue)
        #expect(before.grade == .g0)
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: edge.id, of: cube, continuity: .g1)
        let found = try await grade(result, edge: try endEdge(result).id, against: cube, face: top.id.rawValue)
        #expect(found.grade >= .g1, "angle \(found.angleGap)")
    }

    @Test func aReversedEdgeIsPaired() async throws {
        let a = try await sheetA()
        let b = try await sheetB(from: 10, to: 0)
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        let found = try await grade(result, edge: try endEdge(result).id, against: b)
        #expect(found.grade >= .g1)
    }

    @Test func aSteepMatchIsNotRefused() async throws {
        let a = try await sheetA()
        // B leaves the edge along (cos 150, 0, sin 150): folded back over A.
        let b = try await sheetB(axisZ: -17.3205)
        let result = try await kernel.matched(a, edge: try endEdge(a).id, to: try lineAtX10(b).id, of: b, continuity: .g1)
        #expect(result.hasOpenShell)
        #expect(result.topology.faces.count == 1)
    }

    @Test func aRationalSheetIsMatched() async throws {
        let a = try await sheetA(), b = try await sheetB()
        let before = try await kernel.controlNet(of: b).surface
        let rational = try #require(before.weights)
        #expect(Set(rational.map { ($0 * 1e9).rounded() }).count > 1)
        let source = try lineAtX10(b)
        for continuity in [PatchContinuity.g1, .g2] {
            let result = try await kernel.matched(b, edge: source.id, to: try endEdge(a).id, of: a, continuity: continuity)
            let found = try await kernel.continuity(of: try lineAtX10(result).id, in: result, against: FaceID(0), of: a)
            #expect(found.grade >= (continuity == .g2 ? .g2 : .g1), "angle \(found.angleGap) curvature \(found.curvatureGap)")
            #expect(found.positionGap <= 1e-4)
            // The far edge (the other end of the arc) stays put.
            let far = try #require(b.topology.edges.first { $0.kind == .line && $0.midpoint.x > 11 })
            let farNow = try #require(result.topology.edges.first { $0.kind == .line && $0.midpoint.x > 11 })
            for i in 0..<9 {
                let point = far.midpoint + Vector3(0, 10 * (Double(i) / 8 - 0.5), 0)
                let gap = try await kernel.shortestDistance(between: .point(point), and: .edge(result, farNow.id)).distance
                #expect(gap < 1e-9, "gap \(gap)")
            }
            if continuity == .g1 {
                let after = try await kernel.controlNet(of: result).surface
                let kept = Set(rational.map { ($0 * 1e9).rounded() })
                #expect(Set((after.weights ?? []).map { ($0 * 1e9).rounded() }) == kept)
            }
        }
    }
}
#endif
