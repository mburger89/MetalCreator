#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-4 Task 7: `Kernel.extended(_:edges:length:mode:)` (R8).
struct ExtendSurfaceTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func spline(_ poles: [Vector3], degree: Int = 3) async throws -> Curve {
        let count = poles.count
        let interior = Array(1..<(count - degree))
        let knots = [0.0] + interior.map { Double($0) } + [Double(count - degree)]
        let mults = [degree + 1] + interior.map { _ in 1 } + [degree + 1]
        return try await kernel.makeCurve(
            [.spline(BSplineCurve3D(degree: degree, poles: poles, knots: knots, multiplicities: mults))], tag: tag)
    }

    /// A smooth loft of three open curves (one face); its `.boundary(.end)` edge is the section at z = 10.
    func wavySheet() async throws -> Solid {
        var sections: [Curve] = []
        for (z, bulge) in [(0.0, 0.0), (5, 2), (10, 0)] {
            sections.append(try await spline([Vector3(0, 0, z), Vector3(3, bulge, z), Vector3(7, -bulge, z), Vector3(10, 0, z)]))
        }
        return try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
    }

    func endEdge(_ sheet: Solid) throws -> EdgeInfo {
        try #require(sheet.topology.edges.first { $0.tags.contains(TopoTag(tag, .boundary(.end))) })
    }

    func quarterCylinder() async throws -> Solid {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 10))], tag: tag)
        return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: .unitZ), angle: .degrees(90), tag: tag)
    }

    func fullCylinder() async throws -> Solid {
        let line = try await kernel.makeCurve([.line(Vector3(10, 0, 0), Vector3(10, 0, 20))], tag: tag)
        return try await kernel.revolve(line, axis: Axis(origin: .zero, direction: .unitZ), angle: .degrees(360), tag: tag)
    }

    /// The curved edge round the cylinder at height `z` (a grown edge is a B-spline, a kept one a circle).
    func topCircle(_ sheet: Solid, z: Double) throws -> EdgeInfo {
        try #require(sheet.topology.edges.first { $0.kind != .line && abs($0.midpoint.z - z) < 1e-6 && !$0.isSeam })
    }

    func plane(z: Double) async throws -> Solid {
        let c = [Vector3(-40, -40, z), Vector3(40, -40, z), Vector3(40, 40, z), Vector3(-40, 40, z)]
        let loop = try await kernel.makeCurve(c.indices.map { .line(c[$0], c[($0 + 1) % 4]) }, tag: tag)
        return try await kernel.planarSurface([loop], tag: tag)
    }

    /// The grade of the join along the plane z = `z`, which cuts the result along the old edge.
    func grade(_ sheet: Solid, cutAt z: Double) async throws -> ContinuityClass {
        let split = try await kernel.split(sheet, by: .body(try await plane(z: z)), tag: newTag())
        let cut = try #require(split.whole.topology.edges.first { $0.faces.count == 2 && $0.faces[0] != $0.faces[1] })
        return try await kernel.continuity(along: cut.id, of: split.whole).grade
    }

    func structure(_ topology: Topology) -> [String] {
        topology.faces.map { "f\($0.id.rawValue) \($0.tags.map(String.init(describing:)).sorted())" }
            + topology.edges.map { "e\($0.id.rawValue) \($0.faces.map(\.rawValue)) \($0.tags.map(String.init(describing:)).sorted())" }
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return "other: \(error)" }
        return nil
    }

    @Test func naturalGrowsTheEdge() async throws {
        let sheet = try await wavySheet()
        let old = try endEdge(sheet)
        let result = try await kernel.extended(sheet, edges: [old.id], length: 5, mode: .natural)
        let grown = try endEdge(result)
        let moved = (grown.midpoint - old.midpoint).length
        #expect(abs(moved - 5) <= 0.5, "moved \(moved)")
        #expect(result.topology.faces[0].area > sheet.topology.faces[0].area)
        #expect(result.hasOpenShell)
    }

    @Test func theOldSurfaceIsUnchanged() async throws {
        let sheet = try await wavySheet()
        let result = try await kernel.extended(sheet, edges: [try endEdge(sheet).id], length: 5, mode: .natural)
        let mesh = try await kernel.tessellate(sheet, tolerance: 0.02, angle: 0.2)
        let step = max(1, mesh.positions.count / 25)
        let points = stride(from: 0, to: mesh.positions.count, by: step).map { mesh.positions[$0] }
        #expect(points.count >= 25)
        for point in points.prefix(25) {
            let gap = try await kernel.shortestDistance(between: .point(point), and: .face(result, result.topology.faces[0].id)).distance
            #expect(gap < 1e-7, "gap \(gap)")
        }
    }

    @Test func naturalIsCurvatureContinuous() async throws {
        let sheet = try await wavySheet()
        let result = try await kernel.extended(sheet, edges: [try endEdge(sheet).id], length: 5, mode: .natural)
        #expect(try await grade(result, cutAt: 10) == .g2)
    }

    @Test func linearIsTangentAndStraight() async throws {
        let sheet = try await wavySheet()
        let result = try await kernel.extended(sheet, edges: [try endEdge(sheet).id], length: 5, mode: .linear)
        #expect(try await grade(result, cutAt: 10) >= .g1)
        // On a cylinder the straight continuation of a ruling's side is the tangent plane: x = 10 at the ruling's middle.
        let cylinder = try await quarterCylinder()
        let ruling = try #require(cylinder.topology.edges.first { $0.kind == .line && abs($0.midpoint.y) < 1e-9 && $0.midpoint.x > 9.9 })
        let extended = try await kernel.extended(cylinder, edges: [ruling.id], length: 5, mode: .linear)
        let grown = try #require(extended.topology.edges.first {
            $0.kind != .circle && $0.faces.count == 1 && $0.midpoint.y < -4 && abs($0.midpoint.z - 5) < 1e-6
        })
        #expect(abs(grown.midpoint.x - 10) < 1e-6, "midpoint \(grown.midpoint)")
        #expect(abs(grown.midpoint.y + 5) < 1e-4)
    }

    @Test func topologyIsKept() async throws {
        for mode in [ExtendMode.natural, .linear] {
            let sheet = try await wavySheet()
            let result = try await kernel.extended(sheet, edges: [try endEdge(sheet).id], length: 5, mode: mode)
            #expect(structure(result.topology) == structure(sheet.topology))
            #expect(result.topology.edges.map(\.faces) == sheet.topology.edges.map(\.faces))
        }
    }

    @Test func aRevolvedSheetExtends() async throws {
        let sheet = try await quarterCylinder()
        let top = try #require(sheet.topology.edges.first { $0.kind == .circle && abs($0.midpoint.z - 10) < 1e-6 })
        for mode in [ExtendMode.natural, .linear] {
            let result = try await kernel.extended(sheet, edges: [top.id], length: 5, mode: mode)
            #expect(structure(result.topology) == structure(sheet.topology))
            #expect(try await grade(result, cutAt: 10) >= (mode == .natural ? .g2 : .g1))
            let grown = try topCircle(result, z: 15)
            #expect(abs(grown.length - top.length) < 1e-4)
        }
    }

    @Test func aPeriodicSheetsEndExtends() async throws {
        let sheet = try await fullCylinder()
        let top = try topCircle(sheet, z: 20)
        let bottom = try topCircle(sheet, z: 0)
        for mode in [ExtendMode.natural, .linear] {
            let result = try await kernel.extended(sheet, edges: [top.id], length: 5, mode: mode)
            let shape = try await kernel.shape(of: result)
            #expect(shape.isValid)
            #expect(structure(result.topology) == structure(sheet.topology))
            let seam = try #require(result.topology.edges.first { $0.isSeam })
            #expect(seam.faces.count == 2)
            #expect(try await grade(result, cutAt: 20) >= (mode == .natural ? .g2 : .g1))
            let gap = try OCCTKernel.serialized { () throws -> Double in try shape.pcurveGap(ofFace: 0) }
            #expect(gap < 1e-7, "pcurve gap \(gap)")
            let kept = try topCircle(result, z: 0)
            #expect((kept.midpoint - bottom.midpoint).length < 1e-9 && abs(kept.length - bottom.length) < 1e-9)
            let grown = try topCircle(result, z: 25)
            #expect(abs(grown.length - top.length) < 1e-4)
        }
    }

    @Test func aPlaneExtendsInBothModes() async throws {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        let sheet = try await kernel.planarSurface([loop], tag: tag)
        let edge = try #require(sheet.topology.edges.first { abs($0.midpoint.x - 10) < 1e-9 })
        for mode in [ExtendMode.natural, .linear] {
            let result = try await kernel.extended(sheet, edges: [edge.id], length: 4, mode: mode)
            #expect(abs(result.topology.faces[0].area - 140) < 1e-4, "area \(result.topology.faces[0].area)")
            #expect(structure(result.topology) == structure(sheet.topology))
        }
    }

    @Test(arguments: [ExtendMode.natural, .linear]) func aPlaneExtendsOnEverySide(mode: ExtendMode) async throws {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        let sheet = try await kernel.planarSurface([loop], tag: tag)
        var areas: [Double] = []
        for count in 1...4 {
            let result = try await kernel.extended(sheet, edges: sheet.topology.edges.prefix(count).map(\.id), length: 4, mode: mode)
            areas.append(result.topology.faces[0].area)
        }
        #expect(areas.map { $0.rounded() } == [140, 196, 252, 324], "areas \(areas)")
    }

    @Test func twoPickedEdgesOnOneSideCountOnce() async throws {
        let sheet = try await wavySheet()
        let end = try endEdge(sheet)
        let once = try await kernel.extended(sheet, edges: [end.id], length: 5, mode: .natural)
        let twice = try await kernel.extended(sheet, edges: [end.id, end.id], length: 5, mode: .natural)
        #expect(abs(once.topology.faces[0].area - twice.topology.faces[0].area) < 1e-9)
    }

    @Test func twoSidesExtend() async throws {
        let sheet = try await wavySheet()
        let end = try endEdge(sheet)
        let side = try #require(sheet.topology.edges.first { $0.tags.contains(TopoTag(tag, .boundary(.rail(0)))) })
        let both = try await kernel.extended(sheet, edges: [end.id, side.id], length: 3, mode: .natural)
        let one = try await kernel.extended(sheet, edges: [end.id], length: 3, mode: .natural)
        #expect(both.topology.faces[0].area > one.topology.faces[0].area)
        #expect(structure(both.topology) == structure(sheet.topology))
        #expect(try await kernel.shape(of: both).isValid)
    }

    @Test func theRefusals() async throws {
        let sheet = try await wavySheet()
        let end = try endEdge(sheet)
        func bent(z: Double) async throws -> Curve {
            try await kernel.makeCurve(
                [.line(Vector3(0, 0, z), Vector3(10, 0, z)), .line(Vector3(10, 0, z), Vector3(10, 5, z))], tag: tag)
        }
        let ruled = try await kernel.loftSurface([try await bent(z: 0), try await bent(z: 8)], ruled: true, closed: false, tag: tag)
        #expect(ruled.topology.faces.count == 2)
        #expect(await refusal { _ = try await kernel.extended(ruled, edges: [ruled.topology.edges[0].id], length: 5, mode: .natural) }
                == "Extend Surface takes a sheet with one face; this one has 2.")
        let solid = try await box(kernel, 10, 10, 10)
        #expect(await refusal { _ = try await kernel.extended(solid, edges: [solid.topology.edges[0].id], length: 5, mode: .natural) }
                == "Extend Surface takes a sheet; this is a closed solid.")
        let circle = try await kernel.makeCurve(
            [.arc(center: .zero, normal: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: 2 * .pi)], tag: tag)
        let disk = try await kernel.planarSurface([circle], tag: tag)
        let rim = try #require(disk.topology.edges.first { $0.faces.count == 1 })
        #expect(await refusal { _ = try await kernel.extended(disk, edges: [rim.id], length: 5, mode: .natural) }
                == "Only an untrimmed edge can be extended; this edge is a trim.")
        #expect(await refusal { _ = try await kernel.extended(sheet, edges: [end.id], length: 0, mode: .natural) }
                == "The length must be greater than 0 mm.")
        let cylinder = try await fullCylinder()
        let seam = try #require(cylinder.topology.edges.first { $0.isSeam })
        #expect(await refusal { _ = try await kernel.extended(cylinder, edges: [seam.id], length: 5, mode: .natural) }
                == "Only a sheet's open edges can be extended.")
    }
}
#endif
