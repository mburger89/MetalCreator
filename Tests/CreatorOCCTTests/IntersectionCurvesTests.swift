#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-4 Task 6: `Kernel.intersectionCurves(_:_:tag:)` (R14).
struct IntersectionCurvesTests {
    let tag = newTag()
    let kernel = OCCTKernel()

    func rectangleSheet(z: Double, half: Double = 20) async throws -> Solid {
        let c = [Vector3(-half, -half, z), Vector3(half, -half, z), Vector3(half, half, z), Vector3(-half, half, z)]
        let loop = try await kernel.makeCurve(c.indices.map { .line(c[$0], c[($0 + 1) % 4]) }, tag: tag)
        return try await kernel.planarSurface([loop], tag: tag)
    }

    func loftSheet(_ a: [Vector3], _ b: [Vector3]) async throws -> Solid {
        let first = try await kernel.makeCurve([.line(a[0], a[1])], tag: tag)
        let second = try await kernel.makeCurve([.line(b[0], b[1])], tag: tag)
        return try await kernel.loftSurface([first, second], ruled: true, closed: false, tag: tag)
    }

    func start(_ curve: Curve) -> Vector3 { curve.polyline[0] }

    @Test func aPlaneThroughABoxGivesItsSquare() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let curves = try await kernel.intersectionCurves(part, try await rectangleSheet(z: 5), tag: tag)
        #expect(curves.count == 1)
        let square = try #require(curves.first)
        #expect(square.isClosed)
        #expect(square.pieceCount == 4)
        #expect(abs(square.length - 40) < 1e-6)
        #expect((start(square) - Vector3(-5, -5, 5)).length < 1e-6)
    }

    @Test func twoSheetsGiveAnOpenCurve() async throws {
        let flat = try await loftSheet([Vector3(-10, -10, 0), Vector3(10, -10, 0)], [Vector3(-10, 10, 0), Vector3(10, 10, 0)])
        let upright = try await loftSheet([Vector3(-10, 0, -5), Vector3(10, 0, -5)], [Vector3(-10, 0, 5), Vector3(10, 0, 5)])
        let curves = try await kernel.intersectionCurves(flat, upright, tag: tag)
        #expect(curves.count == 1)
        let curve = try #require(curves.first)
        #expect(!curve.isClosed)
        #expect(abs(curve.length - 20) < 1e-5)
        #expect((start(curve) - Vector3(-10, 0, 0)).length < 1e-5)
        let reversed = try await kernel.intersectionCurves(upright, flat, tag: tag)
        #expect((start(try #require(reversed.first)) - Vector3(-10, 0, 0)).length < 1e-5)
    }

    @Test func disjointBodiesGiveNothing() async throws {
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(100, 0, 0)), tag: tag)
        #expect(try await kernel.intersectionCurves(a, b, tag: tag).isEmpty)
    }

    @Test func theSameBodyTwiceIsRefused() async throws {
        let part = try await box(kernel, 10, 10, 10)
        await #expect(throws: KernelError.invalidInput("Intersection Curves needs two different bodies.")) {
            _ = try await kernel.intersectionCurves(part, part, tag: tag)
        }
    }

    func holedBlock() async throws -> Solid {
        let outer = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let profile = Profile2D(plane: .xy, outer: outer.segments,
                                holes: [Profile2D.circle(radius: 2, center: .zero, plane: .xy).segments])
        return try await kernel.extrude(profile, distance: 10, mode: .oneSided, tag: tag)
    }

    @Test func aHoledBlockGivesTwoLoopsInOrder() async throws {
        let curves = try await kernel.intersectionCurves(try await holedBlock(), try await rectangleSheet(z: 5), tag: tag)
        #expect(curves.count == 2)
        for curve in curves { #expect(curve.isClosed) }
        #expect(abs(curves[0].length - 40) < 1e-6)
        #expect(abs(curves[1].length - 4 * .pi) < 1e-6)
    }

    @Test func orderIsStableUnderACommonMove() async throws {
        let move = Transform(translation: Vector3(1, 1, 1))
        let a = try await kernel.transform(try await holedBlock(), by: move, tag: tag)
        let b = try await kernel.transform(try await rectangleSheet(z: 5), by: move, tag: tag)
        let moved = try await kernel.intersectionCurves(a, b, tag: tag)
        #expect(moved.count == 2)
        #expect(abs(moved[0].length - 40) < 1e-6 && abs(moved[1].length - 4 * .pi) < 1e-6)
        let plain = try await kernel.intersectionCurves(try await holedBlock(), try await rectangleSheet(z: 5), tag: tag)
        for (m, p) in zip(moved, plain) {
            #expect((start(m) - start(p) - Vector3(1, 1, 1)).length < 1e-6)
        }
    }
}
#endif
