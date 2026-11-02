#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Splines in profiles (sketch splines, Task 2): the shim builds the sketch curve as a degree-5 B-spline edge.
struct SplineProfileTests {
    static let nodes = [0.0, -0.5384693101056831, 0.5384693101056831, -0.9061798459386640, 0.9061798459386640]
    static let weights = [0.5688888888888889, 0.4786286704993665, 0.4786286704993665, 0.2369268850561891, 0.2369268850561891]

    /// ∮ f(x, y, dx, dy) dt over a closed loop, by 5-point Gauss–Legendre per span (exact for the degree-9 integrands used here).
    static func integral(_ loop: [Segment2D], _ f: (Double, Double, Double, Double) -> Double) -> Double {
        var total = 0.0
        func gauss(_ a: Double, _ b: Double, _ eval: (Double) -> (Vector2, Vector2)) {
            for (node, weight) in zip(nodes, weights) {
                let t = (a + b) / 2 + (b - a) / 2 * node
                let (p, d) = eval(t)
                total += weight * (b - a) / 2 * f(p.x, p.y, d.x, d.y)
            }
        }
        for segment in loop {
            switch segment {
            case .line(let a, let b): gauss(0, 1) { t in (a + (b - a) * t, b - a) }
            case .spline(let curve):
                for (a, b) in zip(curve.knots, curve.knots.dropFirst()) {
                    gauss(a, b) { t in (curve.point(at: t), curve.derivative(at: t, order: 1)) }
                }
            case .arc: Issue.record("no arcs here")
            }
        }
        return total
    }

    static func area(_ loop: [Segment2D]) -> Double { integral(loop) { x, y, dx, dy in (x * dy - y * dx) / 2 } }
    /// ∫∫ x dA = ½ ∮ x² dy.
    static func firstMomentX(_ loop: [Segment2D]) -> Double { integral(loop) { x, _, _, dy in x * x * dy / 2 } }

    static func curve(_ points: [Vector2], handles: [SplineHandle] = []) -> SplineCurve2D {
        SplineDefinition(points: points, handles: handles).curve()
    }

    /// A counter-clockwise loop: a spline along the bottom, then three lines.
    static func bottomSplineLoop(offset: Vector2 = .zero) -> [Segment2D] {
        let spline = curve([Vector2(0, 0), Vector2(3, 2), Vector2(6, 1.5), Vector2(10, 0)])
        let loop: [Segment2D] = [
            .spline(spline), .line(Vector2(10, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        return loop.map { $0.translated(by: offset) }
    }

    @Test func aSplineProfileExtrudes() async throws {
        let loop = Self.bottomSplineLoop()
        let solid = try await OCCTKernel().extrude(Profile2D(plane: .xy, segments: loop), distance: 4, mode: .oneSided,
                                                   tag: newTag())
        let expected = 4 * Self.area(loop)
        let volume = try await OCCTKernel().properties(of: solid).volume
        #expect(abs(volume - expected) / expected < 1e-6, "\(volume) vs \(expected)")
    }

    @Test func theEdgeIsTheSketchCurve() async throws {
        let kernel = OCCTKernel()
        let tag = newTag()
        let loop = Self.bottomSplineLoop()
        guard case .spline(let curve) = loop[0] else { Issue.record("no spline"); return }
        let solid = try await kernel.extrude(Profile2D(plane: .xy, segments: loop), distance: 3, mode: .oneSided, tag: tag)
        let wall = try #require(faces(solid, role: .side(loop: 0, segment: 0), of: tag).first)
        let bottoms = edges(solid, between: { $0.id == wall.id }, and: { $0.kind == .plane && abs($0.normal?.z ?? 0) > 0.5 })
        #expect(bottoms.count == 2, "\(bottoms.count)")
        let range = curve.parameterRange
        let samples = (0..<200).map { k -> Vector3 in
            let p = curve.point(at: range.lowerBound + (range.upperBound - range.lowerBound) * Double(k) / 199)
            return Vector3(p.x, p.y, 0)
        }
        let found = try await kernel.distances(from: samples, to: .edges(EdgeSet(solid: solid, edges: bottoms.map(\.id))),
                                               signed: false)
        #expect((found.max() ?? 1) < 1e-9)
    }

    static func holeLoop(clockwise: Bool) -> [Segment2D] {
        if clockwise {
            return [
                .spline(curve([Vector2(-5, -3), Vector2(-6, 3), Vector2(0, 6), Vector2(5, -3)])),
                .line(Vector2(5, -3), Vector2(-5, -3)),
            ]
        }
        return [
            .line(Vector2(-5, -3), Vector2(5, -3)),
            .spline(curve([Vector2(5, -3), Vector2(6, 3), Vector2(0, 6), Vector2(-5, -3)])),
        ]
    }

    @Test(arguments: [false, true])
    func holeOrientationWithASpline(clockwise: Bool) async throws {
        let hole = Self.holeLoop(clockwise: clockwise)
        let outline = Profile2D.rectangle(width: 40, height: 30, plane: .xy).segments
        let solid = try await OCCTKernel().extrude(Profile2D(plane: .xy, outer: outline, holes: [hole]), distance: 2,
                                                   mode: .oneSided, tag: newTag())
        let expected = 2 * (1200 - abs(Self.area(hole)))
        let volume = try await OCCTKernel().properties(of: solid).volume
        #expect(abs(volume - expected) / expected < 1e-6, "\(volume) vs \(expected)")
    }

    @Test func revolveAndLoftASplineProfile() async throws {
        let kernel = OCCTKernel()
        let loop = Self.bottomSplineLoop(offset: Vector2(5, 0))
        let angle = Double.pi / 2
        let revolved = try await kernel.revolve(Profile2D(plane: .xy, segments: loop), axis: Axis(origin: .zero, direction: .unitY),
                                                angle: Angle(radians: angle), tag: newTag())
        let expected = angle * Self.firstMomentX(loop)
        let volume = try await kernel.properties(of: revolved).volume
        #expect(abs(volume - expected) / expected < 1e-7)

        let top = Plane(origin: Vector3(0, 0, 10), normal: .unitZ, xAxis: .unitX)
        let lofted = try await kernel.loft([Profile2D(plane: .xy, segments: loop), Profile2D(plane: top, segments: loop)],
                                           ruled: true, tag: newTag())
        let loftVolume = try await kernel.properties(of: lofted).volume
        #expect(abs(loftVolume - 10 * Self.area(loop)) / (10 * Self.area(loop)) < 1e-5, "\(loftVolume) vs \(10 * Self.area(loop))")
    }

    @Test func sideTagsUnchanged() async throws {
        let tag = newTag()
        let loop = Self.bottomSplineLoop()
        let solid = try await OCCTKernel().extrude(Profile2D(plane: .xy, segments: loop), distance: 3, mode: .oneSided, tag: tag)
        #expect(solid.topology.faces.count == loop.count + 2)
        for segment in 0..<loop.count {
            #expect(faces(solid, role: .side(loop: 0, segment: segment), of: tag).count == 1, "wall \(segment)")
        }
        #expect(faces(solid, role: .side(loop: 0, segment: 0), of: tag).first?.kind != .plane)
    }

    /// A spline whose end meets a line with the line's tangent: G2 when its end curvature is the line's 0, G1 when it is not.
    @Test(arguments: [(Vector2(0, 0), ContinuityClass.g2), (Vector2(0, 3), ContinuityClass.g1)])
    func aLineSplineJointIsG2WhenTheCurveSaysSo(curvature: Vector2, expected: ContinuityClass) async throws {
        let kernel = OCCTKernel()
        let tag = newTag()
        let end = SplineHandle(tangent: Vector2(5, 0), curvature: curvature)
        let spline = Self.curve([Vector2(0, 0), Vector2(3, 2), Vector2(6, 1.5), Vector2(10, 0)],
                                handles: [.automatic, .automatic, .automatic, end])
        let loop: [Segment2D] = [
            .spline(spline), .line(Vector2(10, 0), Vector2(20, 0)), .line(Vector2(20, 0), Vector2(20, 10)),
            .line(Vector2(20, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        let solid = try await kernel.extrude(Profile2D(plane: .xy, segments: loop), distance: 3, mode: .oneSided, tag: tag)
        let curved = try #require(faces(solid, role: .side(loop: 0, segment: 0), of: tag).first)
        let flat = try #require(faces(solid, role: .side(loop: 0, segment: 1), of: tag).first)
        let joint = try #require(edges(solid, between: { $0.id == curved.id }, and: { $0.id == flat.id }).first)
        let found = try await kernel.continuity(along: joint.id, of: solid)
        #expect(found.grade == expected, "\(found)")
    }
}
#endif
