import COCCT
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Task 1 of G-d: the end-constrained loft in the shim (`occt_loft_ends`), the go/no-go gate (spec "Construction").
struct LoftEndConditionTests {
    struct Face {
        var index: Int
        var kind: Int
        var normal: [Double]
        var centroid: [Double]
    }

    struct Edge {
        var index: Int
        var midpoint: [Double]
        var faceA: Int
        var faceB: Int
    }

    func topology(of shape: OCCTShape) -> (faces: [Face], edges: [Edge]) {
        OCCTKernel.serialized {
            var raw = occt_topology()
            var status = occt_status()
            #expect(occt_read_topology(shape.raw, &raw, &status) == 1)
            defer { occt_topology_free(&raw) }
            let faces = (0..<Int(raw.face_count)).map { i in
                let f = raw.faces[i]
                return Face(index: i + 1, kind: Int(f.kind), normal: [f.normal.0, f.normal.1, f.normal.2],
                            centroid: [f.centroid.0, f.centroid.1, f.centroid.2])
            }
            let edges = (0..<Int(raw.edge_count)).map { i in
                let e = raw.edges[i]
                return Edge(index: i + 1, midpoint: [e.midpoint.0, e.midpoint.1, e.midpoint.2], faceA: Int(e.face_a),
                            faceB: Int(e.face_b))
            }
            return (faces, edges)
        }
    }

    /// The 1-based index of the planar face whose outward normal is `normal` and whose centroid is at `height` in z.
    func planarFace(of shape: OCCTShape, normal: [Double], height: Double) throws -> Int {
        let found = topology(of: shape).faces.first { f in
            f.kind == 0 && (0..<3).allSatisfy { abs(f.normal[$0] - normal[$0]) < 1e-9 } && abs(f.centroid[2] - height) < 1e-9
        }
        return try #require(found).index
    }

    /// A box `width` × `depth` × `height` centred on (cx, cy), from z = `bottom`.
    func box(_ width: Double, _ depth: Double, _ height: Double, centre: Vector2 = Vector2(0, 0), bottom: Double = 0) throws
        -> OCCTShape {
        let plane = Plane(origin: Vector3(centre.x, centre.y, bottom), normal: .unitZ, xAxis: .unitX)
        let rectangle = Profile2D.rectangle(width: width, height: depth, plane: plane)
        return try OCCTKernel.serialized { try OCCTShape.extrude(rectangle, distance: height).0 }
    }

    func square(_ side: Double, at z: Double) -> Profile2D {
        .rectangle(width: side, height: side, plane: Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX))
    }

    func end(_ face: Int, _ continuity: Int32, weight: Double = 1) -> occt_loft_end {
        occt_loft_end(face_index: Int32(face), continuity: continuity, weight: weight)
    }

    typealias Built = (shape: OCCTShape, history: [OCCTHistoryRecord], report: occt_loft_report)

    func loft(_ part: OCCTShape?, start: occt_loft_end?, end: occt_loft_end?, sections: [Profile2D]) throws -> Built {
        try OCCTKernel.serialized { try OCCTShape.loftEnds(part: part, start: start, end: end, sections: sections) }
    }

    /// Builds the loft 10 times and returns the last with the mean time.
    func timed(_ body: () throws -> Built) throws -> (Built, Duration) {
        var built: Built?
        let time = try ContinuousClock().measure {
            for _ in 0..<10 { built = try body() }
        } / 10
        return (try #require(built), time)
    }

    func columns(_ report: occt_loft_report) -> [Int] {
        withUnsafeBytes(of: report.columns) { raw in
            Array(raw.bindMemory(to: Int32.self).prefix(Int(report.segments)).map { Int($0) })
        }
    }

    func describe(_ name: String, _ built: Built, _ time: Duration) {
        let r = built.report
        print("LOFTENDS \(name): time \(time) columns \(columns(r)) seams \(r.seams_total) judged \(r.seams_judged)"
            + " worst position \(r.worst_seam.position) angle° \(r.worst_seam.angle_degrees)"
            + " curvature ratio \(r.worst_seam.curvature_ratio) side gap \(r.side_gap) section gap \(r.section_gap)")
    }

    func union(_ a: OCCTShape, _ b: OCCTShape) throws -> OCCTShape {
        try OCCTKernel.serialized { try OCCTShape.boolean(.union, a, [b]).0 }
    }

    /// The continuity of every two-face edge of `shape` whose midpoint `where` accepts.
    func continuities(of shape: OCCTShape, where accepts: ([Double]) -> Bool) throws -> [EdgeContinuity] {
        let edges = topology(of: shape).edges.filter { $0.faceA != $0.faceB && $0.faceA > 0 && $0.faceB > 0 && accepts($0.midpoint) }
        return try edges.map { edge in try OCCTKernel.serialized { try shape.continuity(edgeIndex: edge.index) } }
    }

    func isValid(_ shape: OCCTShape) -> Bool { OCCTKernel.serialized { shape.isValid } }

    /// The largest |x| of the shape's cross-section at height `z`: how far the side bulges out there.
    func halfWidth(of shape: OCCTShape, at z: Double) throws -> Double {
        let section = try OCCTKernel.serialized {
            try shape.section(by: Plane(origin: Vector3(0, 0, z), normal: .unitZ, xAxis: .unitX), tolerance: 1e-3)
        }
        let xs = section.regions.flatMap { $0.positions.map(\.x) }
        return try #require(xs.map(abs).max())
    }

    // MARK: The gate

    func boxToSquare(_ continuity: Int32, weight: Double = 1, name: String) throws -> (Built, OCCTShape, [EdgeContinuity]) {
        let part = try box(20, 20, 10)
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let start = end(top, continuity, weight: weight)
        let (built, time) = try timed { try loft(part, start: start, end: nil, sections: [square(12, at: 20)]) }
        describe(name, built, time)
        #expect(isValid(built.shape))
        let joined = try union(part, built.shape)
        #expect(isValid(joined))
        let found = try continuities(of: joined) { m in
            abs(m[2] - 10) < 1e-6 && (abs(abs(m[0]) - 10) < 1e-6 || abs(abs(m[1]) - 10) < 1e-6)
        }
        print("LOFTENDS \(name): joint grades \(found.map(\.grade)) angle \(found.map(\.angleGap).max() ?? -1)"
            + " curvature \(found.map(\.curvatureGap).max() ?? -1) faces \(OCCTKernel.serialized { joined.faceCount })")
        #expect(found.count == 4)
        return (built, joined, found)
    }

    @Test func boxTopToSmallerSquareTangentIsG1() throws {
        let (built, _, found) = try boxToSquare(1, name: "box tangent")
        #expect(found.allSatisfy { $0.grade == .g1 })
        #expect(built.report.seams_total == 4)
        #expect(built.report.seams_judged == 1)
    }

    @Test func boxTopToSmallerSquareCurvatureIsG2() throws {
        let (built, _, found) = try boxToSquare(2, name: "box curvature")
        #expect(found.allSatisfy { $0.grade == .g2 })
        #expect(built.report.seams_total == 4)
    }

    @Test func freeFaceEndMatchesThruSections() throws {
        let part = try box(20, 20, 10)
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let free = try loft(part, start: end(top, 0), end: nil, sections: [square(12, at: 20)])
        #expect(free.report.used_thru_sections == 1)
        let reference = try OCCTKernel.serialized { try OCCTShape.loft([square(20, at: 10), square(12, at: 20)], ruled: false).0 }
        let (a, b) = OCCTKernel.serialized { (free.shape, reference) }
        #expect(OCCTKernel.serialized { a.faceCount } == OCCTKernel.serialized { b.faceCount })
        let va = OCCTKernel.serialized { a.volume }, vb = OCCTKernel.serialized { b.volume }
        #expect(abs(va - vb) < 1e-6)
        for z in [10.5, 12.5, 15, 17.5, 19.5] {
            #expect(abs(try halfWidth(of: a, at: z) - halfWidth(of: b, at: z)) < 1e-6)
        }
        // Tags: the caps and one side per segment.
        #expect(free.history.filter { $0.kind == .startCap }.count == 1)
        #expect(free.history.filter { $0.kind == .endCap }.count == 1)
        #expect(Set(free.history.filter { $0.kind == .segment }.map(\.index)) == [0, 1, 2, 3])
    }

    @Test func cylinderTopToSmallerCircleIsG2() throws {
        let part = try OCCTKernel.serialized {
            try OCCTShape.extrude(.circle(radius: 10, center: Vector2(0, 0), plane: .xy), distance: 10).0
        }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let circle = Profile2D.circle(radius: 6, center: Vector2(0, 0), plane: .xy.offset(by: 20))
        let (built, time) = try timed { try loft(part, start: end(top, 2), end: nil, sections: [circle]) }
        describe("cylinder curvature", built, time)
        #expect(isValid(built.shape))
        let joined = try union(part, built.shape)
        #expect(isValid(joined))
        let found = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 }
        print("LOFTENDS cylinder: joint grades \(found.map(\.grade))")
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.grade == .g2 })
    }

    @Test func bridgeBetweenTwoBoxesBothEndsG2() throws {
        let lower = try box(20, 20, 10)
        let upper = try box(14, 14, 10, centre: Vector2(4, 2), bottom: 30)
        let both = try union(lower, upper)
        let top = try planarFace(of: both, normal: [0, 0, 1], height: 10)
        let bottom = try planarFace(of: both, normal: [0, 0, -1], height: 30)
        let (built, time) = try timed { try loft(both, start: end(top, 2), end: end(bottom, 2), sections: []) }
        describe("bridge curvature", built, time)
        #expect(isValid(built.shape))
        #expect(built.report.seams_total == 8)
        let joined = try union(both, built.shape)
        #expect(isValid(joined))
        let found = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 || abs(m[2] - 30) < 1e-6 }
        print("LOFTENDS bridge: joint grades \(found.map(\.grade))")
        #expect(found.count == 8)
        #expect(found.allSatisfy { $0.grade == .g2 })
    }

    @Test func bridgeWithAMiddleSectionBothEndsG2() throws {
        let lower = try box(20, 20, 10)
        let upper = try box(14, 14, 10, centre: Vector2(4, 2), bottom: 30)
        let both = try union(lower, upper)
        let top = try planarFace(of: both, normal: [0, 0, 1], height: 10)
        let bottom = try planarFace(of: both, normal: [0, 0, -1], height: 30)
        let (built, time) = try timed { try loft(both, start: end(top, 2), end: end(bottom, 1), sections: [square(8, at: 20)]) }
        describe("bridge waist", built, time)
        #expect(isValid(built.shape))
        let joined = try union(both, built.shape)
        #expect(isValid(joined))
        let lowerGrades = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 }.map(\.grade)
        let upperGrades = try continuities(of: joined) { m in abs(m[2] - 30) < 1e-6 }.map(\.grade)
        print("LOFTENDS bridge waist: lower \(lowerGrades) upper \(upperGrades)")
        #expect(lowerGrades.count == 4 && lowerGrades.allSatisfy { $0 == .g2 })
        #expect(upperGrades.count == 4 && upperGrades.allSatisfy { $0 != .g0 })
    }

    @Test func weightIsMonotonic() throws {
        var widths: [Double] = []
        for weight in [0.1, 0.5, 1, 1.5, 2] {
            let (built, _, found) = try boxToSquare(2, weight: weight, name: "box curvature w=\(weight)")
            #expect(found.allSatisfy { $0.grade == .g2 })
            widths.append(try halfWidth(of: built.shape, at: 15))
        }
        print("LOFTENDS weight: half widths at mid-height \(widths)")
        #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: Probes beyond the gate

    /// A dome: a disc of radius 8 at z = 6 on a sphere band of radius 10, so the wall curves across the joint (normal
    /// curvature 1/10), which the gate's straight walls never do.
    @Test func domeTopToSmallerCircleIsG2() throws {
        let xz = Plane(origin: .zero, normal: Vector3(0, -1, 0), xAxis: .unitX)
        let profile = Profile2D(plane: xz, segments: [
            .line(Vector2(0, 0), Vector2(10, 0)),
            .arc(center: Vector2(0, 0), radius: 10, start: Angle(radians: 0), end: Angle(radians: atan2(6, 8))),
            .line(Vector2(8, 6), Vector2(0, 6)),
            .line(Vector2(0, 6), Vector2(0, 0)),
        ])
        let part = try OCCTKernel.serialized { try OCCTShape.revolve(profile, axis: .z, angle: Angle(radians: 2 * .pi)).0 }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 6)
        let circle = Profile2D.circle(radius: 4, center: Vector2(0, 0), plane: .xy.offset(by: 14))
        for (continuity, grade) in [(Int32(1), ContinuityClass.g1), (2, .g2)] {
            let (built, time) = try timed { try loft(part, start: end(top, continuity), end: nil, sections: [circle]) }
            describe("dome c=\(continuity)", built, time)
            #expect(isValid(built.shape))
            let joined = try union(part, built.shape)
            #expect(isValid(joined))
            let found = try continuities(of: joined) { m in abs(m[2] - 6) < 1e-6 }
            print("LOFTENDS dome c=\(continuity): joint \(found.map(\.grade)) curvature \(found.map(\.curvatureGap))")
            #expect(!found.isEmpty)
            #expect(found.allSatisfy { $0.grade == grade })
        }
    }

    /// A frustum (20 × 20 at z = 0 to 14 × 14 at z = 10, straight sides): its walls lean in and meet at an angle, so
    /// the columns at the vertices run along the frustum's slanted corner edges, not across either wall.
    @Test func frustumTopToSquareIsG2() throws {
        let part = try OCCTKernel.serialized { try OCCTShape.loft([square(20, at: 0), square(14, at: 10)], ruled: true).0 }
        let top = try planarFace(of: part, normal: [0, 0, 1], height: 10)
        let (built, time) = try timed { try loft(part, start: end(top, 2), end: nil, sections: [square(6, at: 18)]) }
        describe("frustum curvature", built, time)
        #expect(isValid(built.shape))
        let joined = try union(part, built.shape)
        #expect(isValid(joined))
        let found = try continuities(of: joined) { m in abs(m[2] - 10) < 1e-6 }
        print("LOFTENDS frustum: joint \(found.map(\.grade)) angle \(found.map(\.angleGap))")
        #expect(found.count == 4)
        #expect(found.allSatisfy { $0.grade == .g2 })
    }
}
