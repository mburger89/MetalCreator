import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The fast path on the shapes that exercise its less common branches: reversed faces, cylinder sectors across the seam,
/// cylinders with windows or with non-analytic edges, arcs under a full turn, vertices with a raised tolerance, and targets
/// with nothing for the formulas. Each is compared with `BRepExtrema` alone to 1e-9 mm.
struct DistanceFastPathShapeTests: DistanceFastPathChecking {
    func box(_ kernel: OCCTKernel, size: Double, height: Double, at z: Double = 0) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: size, height: size, plane: Plane.xy.offset(by: z)), distance: height,
                                 mode: .oneSided, tag: newTag())
    }

    // MARK: - Reversed faces

    @Test(arguments: [true, false])
    func aHollowedSolidAndItsInnerFacesMatchExtrema(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        let outer = try await box(kernel, size: 20, height: 20)
        let cavity = try await box(kernel, size: 8, height: 8, at: 6)
        let hollow = try await kernel.boolean(.subtract, outer, [cavity], tag: newTag())
        let shape = try await kernel.shape(of: hollow)
        // The levels ±4, ±10, 6, 14, 0 and 20 are all on this grid.
        let points = grid(x: -12...12, y: -12...12, z: -2...22, step: 1)
        try expectAgreement(shape, points, signed: signed)
        let inner = hollow.topology.faces.filter {
            abs($0.centroid.x) < 5 && abs($0.centroid.y) < 5 && $0.centroid.z > 5 && $0.centroid.z < 15
        }
        #expect(inner.count == 6)
        let picks = inner.map { Int32($0.id.rawValue + 1) }
        try expectAgreement(shape, points, kind: .faces, indices: picks, signed: false)
        for pick in picks {
            try expectAgreement(shape, points, kind: .faces, indices: [pick], signed: false)
        }
    }

    @Test(arguments: [true, false])
    func aNotchCutThroughAnEdgeMatchesExtrema(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        let outer = try await box(kernel, size: 20, height: 20)
        let notch = try await kernel.extrude(.rectangle(width: 8, height: 8, plane: Plane.xy.offset(by: 6)), distance: 8,
                                             mode: .oneSided, tag: newTag())
        let moved = try await kernel.transform(notch, by: Transform(translation: Vector3(7, 3, 0)), tag: newTag())
        let cut = try await kernel.boolean(.subtract, outer, [moved], tag: newTag())
        try expectAgreement(try await kernel.shape(of: cut), grid(x: -12...14, y: -12...12, z: -2...22, step: 1), signed: signed)
    }

    // MARK: - Cylinders

    /// A tube of radii 5 and 12 and length 10 about a tilted, off-origin axis, cut to the sector `centre ± 45°`.
    func sector(_ kernel: OCCTKernel, centre degrees: Double) async throws -> (shape: OCCTShape, frame: AxisFrame) {
        let frame = AxisFrame()
        let profile = Profile2D.polyline([Vector2(0, 5), Vector2(10, 5), Vector2(10, 12), Vector2(0, 12)], closed: true,
                                         plane: frame.profilePlane)
        let tube = try await kernel.revolve(profile, axis: frame.axis, angle: Angle(radians: 2 * .pi), tag: newTag())
        let phi = degrees * .pi / 180
        let wedgePlane = Plane(origin: frame.origin - frame.direction * 2, normal: frame.direction,
                               xAxis: frame.e1 * cos(phi) + frame.e2 * sin(phi))
        let wedge = try await kernel.extrude(.polyline([Vector2(0, 0), Vector2(40, -40), Vector2(40, 40)], closed: true, plane: wedgePlane),
                                             distance: 14, mode: .oneSided, tag: newTag())
        let part = try await kernel.boolean(.intersect, tube, [wedge], tag: newTag())
        return (try await kernel.shape(of: part), frame)
    }

    @Test(arguments: [0.0, 30, 60, 165, 270])
    func aSectorAcrossTheSeamOfATiltedCylinderMatchesExtrema(_ centre: Double) async throws {
        let kernel = OCCTKernel()
        let (shape, frame) = try await sector(kernel, centre: centre)
        var points: [Vector3] = []
        for degrees in stride(from: 0.0, to: 360, by: 7.5) {
            for radius in [0.0, 3, 5, 8.5, 12, 14] {
                for along in [-1.0, 0, 5, 10, 11] {
                    points.append(frame.point(along: along, radius: radius, degrees: degrees))
                }
            }
        }
        try expectAgreement(shape, points, signed: true)
        try expectAgreement(shape, points, signed: false)
    }

    @Test func aPartialRevolveOfATiltedCylinderMatchesExtrema() async throws {
        let kernel = OCCTKernel()
        let frame = AxisFrame()
        let profile = Profile2D.polyline([Vector2(0, 5), Vector2(10, 5), Vector2(10, 12), Vector2(0, 12)], closed: true,
                                         plane: frame.profilePlane)
        let part = try await kernel.revolve(profile, axis: frame.axis, angle: .degrees(90), tag: newTag())
        let shape = try await kernel.shape(of: part)
        var points: [Vector3] = []
        for degrees in stride(from: 0.0, to: 360, by: 7.5) {
            for radius in [0.0, 5, 8.5, 12, 14] {
                for along in [-1.0, 0, 5, 10, 11] {
                    points.append(frame.point(along: along, radius: radius, degrees: degrees))
                }
            }
        }
        try expectAgreement(shape, points, signed: true)
        try expectAgreement(shape, points, signed: false)
    }

    @Test(arguments: [true, false])
    func aCylinderWithWindowsThroughItsWallMatchesExtrema(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        let post = try await kernel.extrude(.circle(radius: 6, center: .zero, plane: .xy), distance: 12, mode: .oneSided, tag: newTag())
        // A slot straight through, so the wall's face has two windows (inner wires of lines and arcs).
        let slot = try await kernel.extrude(.rectangle(width: 20, height: 4, plane: Plane.xy.offset(by: 4)), distance: 4,
                                            mode: .oneSided, tag: newTag())
        let part = try await kernel.boolean(.subtract, post, [slot], tag: newTag())
        let shape = try await kernel.shape(of: part)
        try expectAgreement(shape, grid(x: -9...9, y: -9...9, z: -1...13, step: 1), signed: signed)
        var fan: [Vector3] = []
        for degrees in stride(from: 0.0, to: 360, by: 5) {
            let angle = degrees * .pi / 180
            for radius in [3.0, 5.9, 6, 6.1, 8] {
                for z in [3.9, 4, 6, 8, 8.1] {
                    fan.append(Vector3(radius * cos(angle), radius * sin(angle), z))
                }
            }
        }
        try expectAgreement(shape, fan, signed: signed)
    }

    @Test(arguments: [true, false])
    func crossingCylindersFallBackToExtremaWhereTheEdgesAreNotCircles(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        let upright = try await kernel.extrude(.circle(radius: 4, center: .zero, plane: Plane.xy.offset(by: -10)), distance: 20,
                                               mode: .oneSided, tag: newTag())
        let across = try await kernel.extrude(.circle(radius: 3, center: .zero, plane: Plane.yz.offset(by: -10)), distance: 20,
                                              mode: .oneSided, tag: newTag())
        let points = grid(x: -12...12, y: -12...12, z: -12...12, step: 1.5)
        let unioned = try await kernel.boolean(.union, upright, [across], tag: newTag())
        let subtracted = try await kernel.boolean(.subtract, upright, [across], tag: newTag())
        for part in [unioned, subtracted] {
            try expectAgreement(try await kernel.shape(of: part), points, signed: signed)
        }
    }

    // MARK: - Arcs under a full turn, and extrema

    /// A slot: two lines and two semicircles, `clockwise` or not, turned by `degrees`.
    func slotLoop(at centre: Vector2, halfLength: Double, radius: Double, degrees: Double, clockwise: Bool) -> [Segment2D] {
        let turn = degrees * .pi / 180
        func place(_ x: Double, _ y: Double) -> Vector2 {
            centre + Vector2(x * cos(turn) - y * sin(turn), x * sin(turn) + y * cos(turn))
        }
        func arc(_ x: Double, from start: Double, to end: Double) -> Segment2D {
            .arc(center: place(x, 0), radius: radius, start: .degrees(start + degrees), end: .degrees(end + degrees))
        }
        let (l, r) = (halfLength, radius)
        if clockwise {
            return [
                arc(-l, from: 270, to: 90), .line(place(-l, r), place(l, r)), arc(l, from: 90, to: -90),
                .line(place(l, -r), place(-l, -r)),
            ]
        }
        return [
            .line(place(-l, -r), place(l, -r)), arc(l, from: -90, to: 90), .line(place(l, r), place(-l, r)),
            arc(-l, from: 90, to: 270),
        ]
    }

    @Test(arguments: [true, false])
    func slotHolesAndArcsStartingAtAnExtremumMatchExtrema(_ signed: Bool) async throws {
        let semicircles: [Segment2D] = [
            .arc(center: Vector2(0, -12), radius: 3, start: .degrees(90), end: .degrees(270)),
            .arc(center: Vector2(0, -12), radius: 3, start: .degrees(270), end: .degrees(450)),
        ]
        let fullTurn: [Segment2D] = [.arc(center: Vector2(-24, -12), radius: 2, start: .degrees(90), end: .degrees(450))]
        let holes = [
            slotLoop(at: Vector2(-12, 5), halfLength: 4, radius: 2, degrees: 0, clockwise: false),
            slotLoop(at: Vector2(12, -6), halfLength: 4, radius: 2, degrees: 30, clockwise: true),
            slotLoop(at: Vector2(14, 10), halfLength: 3, radius: 1.5, degrees: 90, clockwise: false),
            semicircles, fullTurn,
        ]
        let shape = try await plate(OCCTKernel(), holes: holes)
        try expectAgreement(shape, grid(x: -36...36, y: -26...26, z: -1...7, step: 1), signed: signed)
        try expectAgreement(shape, scattered(4000, x: -34...34, y: -24...24, z: -2...8), signed: signed)
        // In the plane of the top and bottom faces, beside and in each hole, at the levels of the arcs' extrema.
        var levels: [Vector3] = []
        for (centre, reach) in [(Vector2(-12, 5), 4.0), (Vector2(12, -6), 6), (Vector2(0, -12), 3), (Vector2(-24, -12), 2)] {
            // Offsets of 1e-6 and not 1e-7: BRepExtrema itself answers 1e-7 instead of 0 for a point 1e-7 outside a rim (its
            // confusion tolerance); the exact distance, which the fast path gives, is 0 there.
            for dy in [-2.0, -1.5, 0, 1.5, 2, 3, 3.000001, -2.999999] {
                for dx in stride(from: -reach - 3, through: reach + 3, by: 0.5) {
                    levels += [Vector3(centre.x + dx, centre.y + dy, 0), Vector3(centre.x + dx, centre.y + dy, 6)]
                }
            }
        }
        try expectAgreement(shape, levels, signed: signed)
    }

    // MARK: - Raised vertex tolerance

    @Test(arguments: [true, false])
    func aBooleanWhoseVerticesHaveAHigherToleranceMatchesExtrema(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        var found = 0
        for (index, angle) in [17.3, 31.7, 44.9, 59.2, 73.6].enumerated() {
            let base = try await box(kernel, size: 20, height: 20)
            let cutter = try await box(kernel, size: 9, height: 30, at: -5)
            let axis = Axis(origin: Vector3(1.1, 0.7, 3.3), direction: Vector3(Double(index) + 1, 2, 3))
            let turned = try await kernel.transform(cutter, by: Transform(translation: Vector3(5.3, 2.9, 0.1), rotationAxis: axis,
                                                                          rotation: .degrees(angle)), tag: newTag())
            let result = try await kernel.boolean(.subtract, base, [turned], tag: newTag())
            let shape = try await kernel.shape(of: result)
            let tolerance = OCCTKernel.serialized { shape.largestVertexTolerance }
            if tolerance > 1.5e-7 { found += 1 }
            try expectAgreement(shape, grid(x: -12...12, y: -12...12, z: -2...22, step: 1.5), signed: signed)
            try expectAgreement(shape, scattered(1500, x: -12...12, y: -12...12, z: -2...22), signed: signed)
        }
        #expect(found > 0, "no boolean here raised a vertex tolerance above the default")
    }

    // MARK: - Nothing for the formulas

    @Test(arguments: [true, false])
    func anEmptyPickAndATargetWithoutAnalyticFacesMatchExtrema(_ signed: Bool) async throws {
        let kernel = OCCTKernel()
        let points = grid(x: -8...8, y: -8...8, z: -8...8, step: 2)
        let plateShape = try await plate(kernel)
        // An empty pick has nothing to measure to: both paths refuse it with the same words.
        for kind in [OCCTShape.DistanceKind.faces, .edges] {
            let (fast, reference) = OCCTKernel.serialized { () -> (String, String) in
                var fast = "no error", reference = "no error"
                do { _ = try plateShape.distances(from: points[...], kind: kind, indices: [], signed: signed) } catch {
                    fast = String(describing: error)
                }
                do { _ = try plateShape.distancesByExtrema(from: points[...], kind: kind, indices: [], signed: signed) } catch {
                    reference = String(describing: error)
                }
                return (fast, reference)
            }
            #expect(fast == "nothing to measure to" && reference == fast, "\(kind): \(fast) / \(reference)")
        }
        let ball = try await kernel.revolve(
            Profile2D(plane: .xz, segments: [
                .arc(center: Vector2(0, 0), radius: 5, start: .degrees(-90), end: .degrees(90)),
                .line(Vector2(0, 5), Vector2(0, -5)),
            ]),
            axis: Axis(origin: .zero, direction: Vector3(0, 0, 1)), angle: Angle(radians: 2 * .pi), tag: newTag())
        let sphere = try await kernel.shape(of: ball)
        try expectAgreement(sphere, points, signed: signed)
        for pick in 1...Int32(sphere.faceCount) {
            try expectAgreement(sphere, points, kind: .faces, indices: [pick], signed: false)
        }
    }
}

/// A tilted axis off the origin, with two directions across it, for building and measuring round it.
struct AxisFrame {
    let origin = Vector3(3, -2, 1)
    let direction = Vector3(1, 2, 2) * (1.0 / 3.0)
    let e1 = Vector3(2, -1, 0) * (1.0 / 5.0.squareRoot())
    var e2: Vector3 { direction.cross(e1) }
    var axis: Axis { Axis(origin: origin, direction: direction) }
    /// A plane through the axis whose x runs along it and whose y is `e1`.
    var profilePlane: Plane { Plane(origin: origin, normal: direction.cross(e1), xAxis: direction) }

    func point(along: Double, radius: Double, degrees: Double) -> Vector3 {
        let angle = degrees * .pi / 180
        return origin + direction * along + (e1 * cos(angle) + e2 * sin(angle)) * radius
    }
}
