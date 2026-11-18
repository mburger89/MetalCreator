#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-3 Task 2: reading control nets and surface facts.
struct ControlNetTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func message(_ error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    func spline(_ poles: [Vector3], degree: Int = 3) async throws -> Curve {
        let count = poles.count
        let interior = Array(1..<(count - degree))
        let knots = [0.0] + interior.map { Double($0) } + [Double(count - degree)]
        let mults = [degree + 1] + interior.map { _ in 1 } + [degree + 1]
        return try await kernel.makeCurve(
            [.spline(BSplineCurve3D(degree: degree, poles: poles, knots: knots, multiplicities: mults))], tag: tag)
    }

    func loftedSheet() async throws -> Solid {
        var sections: [Curve] = []
        for (z, bulge) in [(0.0, 0.0), (5, 2), (10, 0)] {
            sections.append(try await spline([Vector3(0, 0, z), Vector3(3, bulge, z), Vector3(7, -bulge, z), Vector3(10, 0, z)]))
        }
        return try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
    }

    @Test func aLoftedSheetGivesItsNet() async throws {
        let sheet = try await loftedSheet()
        let net = try await kernel.controlNet(of: sheet)
        #expect(net.convertedFrom == nil)
        #expect(net.surface.isWellFormed)
        #expect(net.surface.uCount * net.surface.vCount == net.surface.poles.count)
        #expect(net.normals.count == net.surface.poles.count)
        let corners = [net.surface.pole(0, 0), net.surface.pole(net.surface.uCount - 1, 0),
                       net.surface.pole(0, net.surface.vCount - 1),
                       net.surface.pole(net.surface.uCount - 1, net.surface.vCount - 1),
        ]
        let expected = [Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(10, 0, 0), Vector3(10, 0, 10)]
        // The net's u and v may run either way round: each expected corner must be one of the net's corners.
        for point in expected {
            #expect(corners.contains { ($0 - point).length < 1e-9 })
        }
    }

    @Test func aPlanarSheetConvertsExactly() async throws {
        let loop = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(10, 0, 0)), .line(Vector3(10, 0, 0), Vector3(10, 10, 0)),
            .line(Vector3(10, 10, 0), Vector3(0, 10, 0)), .line(Vector3(0, 10, 0), Vector3(0, 0, 0)),
        ], tag: tag)
        let sheet = try await kernel.planarSurface([loop], tag: tag)
        let net = try await kernel.controlNet(of: sheet)
        #expect(net.convertedFrom == .plane)
        #expect(net.surface.degreeU == 1 && net.surface.degreeV == 1)
        #expect(net.surface.uCount == 2 && net.surface.vCount == 2)
        #expect(net.surface.isWellFormed)
        for corner in [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0), Vector3(10, 10, 0)] {
            #expect(net.surface.poles.contains { ($0 - corner).length < 1e-9 })
        }
    }

    @Test func aRevolvedSheetIsRational() async throws {
        let line = try await kernel.makeCurve([.line(Vector3(5, 0, 0), Vector3(5, 0, 10))], tag: tag)
        let axis = Axis(origin: .zero, direction: Vector3(0, 0, 1))
        // A line parallel to the axis revolves into a cylinder; one that slants gives a cone or a surface of revolution.
        let sheet = try await kernel.revolve(line, axis: axis, angle: .degrees(90), tag: tag)
        let net = try await kernel.controlNet(of: sheet)
        #expect(net.surface.weights != nil)
        #expect(net.surface.isWellFormed)
        #expect(net.convertedFrom == .cylinder, "kind \(String(describing: net.convertedFrom))")
        #expect(net.normals.count == net.surface.poles.count)
        for normal in net.normals { #expect(abs(normal.length - 1) < 1e-9) }
    }

    @Test func aSheetOfTwoFacesIsRefused() async throws {
        let a = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(10, 0, 0))], tag: tag)
        let b = try await kernel.makeCurve([.line(Vector3(0, 5, 0), Vector3(10, 5, 0))], tag: tag)
        let c = try await kernel.makeCurve([.line(Vector3(0, 10, 0), Vector3(10, 10, 0))], tag: tag)
        let sheet = try await kernel.loftSurface([a, b, c], ruled: true, closed: false, tag: tag)
        #expect(sheet.topology.faces.count == 2)
        await #expect(throws: KernelError.invalidInput(
            "Edit Surface takes a sheet with one face; this one has 2. Rebuild or Split it first.")) {
            try await kernel.controlNet(of: sheet)
        }
    }

    @Test func aClosedSolidIsRefused() async throws {
        let box = try await kernel.extrude(
            Profile2D.rectangle(width: 5, height: 5, plane: Plane.xy), distance: 5, mode: .oneSided, tag: tag)
        await #expect(throws: KernelError.invalidInput("Edit Surface takes a sheet; this is a closed solid.")) {
            try await kernel.controlNet(of: box)
        }
    }

    @Test func aNetOverTheLimitIsRefused() async throws {
        let sheet = try await kernel.bsplineSheet(uCount: 400, vCount: 300, tag: tag)
        #expect(sheet.topology.faces.count == 1)
        await #expect(throws: KernelError.invalidInput(
            "This surface has 120,000 control points; Edit Surface works on at most 100,000.")) {
            try await kernel.controlNet(of: sheet)
        }
    }

    @Test func aCurvesNet() async throws {
        let points = (0..<6).map { Vector3(Double($0), sin(Double($0)), 0) }
        let curve = try await kernel.interpolate(points, degree: 5, closed: false, startTangent: nil, endTangent: nil, tag: tag)
        let net = try await kernel.controlNet(of: curve)
        let reference = try await kernel.splineInfo(of: curve)
        #expect(reference.degree == 5 && reference.poleCount == net.curve.poles.count, "ref \(reference)")
        #expect(net.curve.degree == 5, "degree \(net.curve.degree), \(net.curve.poles.count) poles")
        #expect(net.curve.isWellFormed)
        #expect(net.convertedFrom == nil && !net.isPeriodic)
        #expect((net.curve.startPoint - points[0]).length < 1e-6)
        #expect((net.curve.endPoint - points[5]).length < 1e-6)

        let line = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(4, 0, 0))], tag: tag)
        let lineNet = try await kernel.controlNet(of: line)
        #expect(lineNet.curve.degree == 1 && lineNet.curve.poles.count == 2)
        #expect(lineNet.convertedFrom == .line)

        let three = try await kernel.makeCurve([
            .line(Vector3(0, 0, 0), Vector3(5, 0, 0)), .line(Vector3(5, 0, 0), Vector3(5, 5, 0)),
            .line(Vector3(5, 5, 0), Vector3(0, 5, 0)),
        ], tag: tag)
        await #expect(throws: KernelError.invalidInput("Edit Curve takes a curve of one piece; this one has 3. Rebuild it first.")) {
            try await kernel.controlNet(of: three)
        }
    }

    @Test func surfaceInfoNamesTheKind() async throws {
        let box = try await kernel.extrude(
            Profile2D.rectangle(width: 5, height: 5, plane: Plane.xy), distance: 5, mode: .oneSided, tag: tag)
        let flat = try await kernel.surfaceInfo(of: FaceID(0), in: box)
        #expect(flat.kind == .plane && flat.net == nil)
        let sheet = try await loftedSheet()
        let lofted = try await kernel.surfaceInfo(of: FaceID(0), in: sheet)
        #expect(lofted.kind == .bspline)
        #expect(lofted.net?.isWellFormed == true)
        #expect(lofted.net == (try await kernel.controlNet(of: sheet)).surface)
    }
}
#endif
