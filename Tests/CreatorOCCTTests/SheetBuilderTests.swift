#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-1 Task 4: extrude, revolve and loft of curves into sheets.
struct SheetBuilderTests {
    let tag = newTag()

    func message(of error: any Error) -> String? {
        guard case KernelError.invalidInput(let text) = error else { return nil }
        return text
    }

    /// Three lines of 10 mm: (0,0) to (10,0) to (10,10) to (0,10).
    func threeLines(_ kernel: OCCTKernel) async throws -> Curve {
        let points = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)]
        return try await kernel.makeCurve((0..<3).map { .line(points[$0], points[$0 + 1]) }, tag: tag)
    }

    func arc(_ kernel: OCCTKernel, z: Double = 0, radius: Double = 5, sweep: Double = .pi / 2) async throws -> Curve {
        try await kernel.makeCurve([
            .arc(center: Vector3(0, 0, z), normal: .unitZ, radius: radius,
                 start: Vector3(radius, 0, z), sweep: sweep),
        ], tag: tag)
    }

    func circle(_ kernel: OCCTKernel, z: Double, radius: Double = 5) async throws -> Curve {
        try await arc(kernel, z: z, radius: radius, sweep: 2 * .pi)
    }

    func count(_ solid: Solid, _ role: BoundaryRole) -> Int {
        solid.topology.edges.filter { $0.tags.contains { $0.role == .boundary(role) } }.count
    }

    @Test func anOpenCurveExtrudesToOneFacePerPiece() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.extrude(try await threeLines(kernel), direction: .unitZ, distance: 10,
                                             symmetric: false, tag: tag)
        #expect(sheet.topology.faces.count == 3)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 300))
        #expect(!sheet.isClosed)
        #expect(count(sheet, .start) == 3 && count(sheet, .end) == 3)
        #expect(count(sheet, .rail(0)) == 1 && count(sheet, .rail(1)) == 1)
        for k in 0..<3 {
            #expect(sheet.topology.faces.contains { $0.tags.contains(TopoTag(tag, .side(loop: 0, segment: k))) })
        }
        // The end edges are at z = 10.
        let end = sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }
        #expect(end.allSatisfy { abs($0.midpoint.z - 10) < 1e-6 })
    }

    @Test func aSymmetricExtrusionDoublesTheAreaAndStartsBelow() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.extrude(try await threeLines(kernel), direction: .unitZ, distance: 10,
                                             symmetric: true, tag: tag)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 600))
        #expect(sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.start) } }
            .allSatisfy { abs($0.midpoint.z + 10) < 1e-6 })
        #expect(sheet.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.end) } }
            .allSatisfy { abs($0.midpoint.z - 10) < 1e-6 })
    }

    @Test func aClosedCircleExtrudesToATubeWithoutRails() async throws {
        let kernel = OCCTKernel()
        let tube = try await kernel.extrude(try await circle(kernel, z: 0), direction: .unitZ, distance: 4,
                                            symmetric: false, tag: tag)
        #expect(tube.topology.faces.count == 1)
        #expect(!tube.isClosed)
        #expect(count(tube, .start) == 1 && count(tube, .end) == 1)
        #expect(tube.topology.edges.filter { $0.tags.contains { if case .boundary(.rail) = $0.role { true } else { false } } }.isEmpty)
        #expect(tube.topology.edges.filter(\.isBoundary).count == 2)
        #expect(isClose(try await kernel.properties(of: tube).surfaceArea, 2 * .pi * 5 * 4))
    }

    @Test func aQuarterArcRevolvedAllTheWayRoundHasNoStartOrEnd() async throws {
        let kernel = OCCTKernel()
        // From (5,0,0) to (0,5,0) about the Y axis: a hemisphere whose pole is on the axis.
        let dome = try await kernel.revolve(try await arc(kernel), axis: Axis(origin: .zero, direction: Vector3(0, 1, 0)),
                                            angle: Angle(radians: 2 * .pi), tag: tag)
        #expect(isClose(try await kernel.properties(of: dome).surfaceArea, 2 * .pi * 25))
        #expect(count(dome, .start) == 0 && count(dome, .end) == 0)
        #expect(count(dome, .rail(0)) == 1)
        #expect(count(dome, .rail(1)) == 0)
        #expect(!dome.isClosed)
        #expect(dome.topology.faces.contains { $0.tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))) })
    }

    @Test func aPartialRevolutionHasStartAndEndEdges() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.revolve(try await arc(kernel), axis: Axis(origin: .zero, direction: Vector3(0, 1, 0)),
                                             angle: Angle(radians: .pi), tag: tag)
        #expect(isClose(try await kernel.properties(of: sheet).surfaceArea, 25 * .pi))
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        #expect(count(sheet, .rail(0)) == 1)
    }

    @Test func aLoftOfTwoOpenArcsIsOneBSplineFace() async throws {
        let kernel = OCCTKernel()
        let sheet = try await kernel.loftSurface([try await arc(kernel, z: 0), try await arc(kernel, z: 8, radius: 7)],
                                                 ruled: false, closed: false, tag: tag)
        #expect(sheet.topology.faces.count == 1)
        #expect(!sheet.isClosed)
        #expect(sheet.topology.faces[0].tags.contains(TopoTag(tag, .side(loop: 0, segment: 0))))
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        #expect(count(sheet, .rail(0)) == 1 && count(sheet, .rail(1)) == 1)
        // Rail 0 joins the first vertices: (5,0,0) and (7,0,8).
        let rail = try #require(sheet.topology.edges.first { $0.tags.contains { $0.role == .boundary(.rail(0)) } })
        #expect(abs(rail.midpoint.y) < 0.5 && abs(rail.midpoint.z - 4) < 0.5)
    }

    @Test func aClosedLoftOfThreeCirclesHasNoStartOrEnd() async throws {
        let kernel = OCCTKernel()
        let sections = [try await circle(kernel, z: 0), try await circle(kernel, z: 6, radius: 7), try await circle(kernel, z: 12)]
        let sheet = try await kernel.loftSurface(sections, ruled: false, closed: true, tag: tag)
        #expect(count(sheet, .start) == 0 && count(sheet, .end) == 0)
        #expect(sheet.topology.edges.allSatisfy { !$0.isBoundary })
        #expect(sheet.isClosed)
    }

    @Test func refusals() async throws {
        let kernel = OCCTKernel()
        let line = try await threeLines(kernel)
        let closedCircle = try await circle(kernel, z: 5)
        let open = try await arc(kernel)
        await #expect(throws: KernelError.invalidInput("A loft needs at least two sections.")) {
            _ = try await kernel.loftSurface([line], ruled: false, closed: false, tag: tag)
        }
        await #expect(throws: KernelError.invalidInput(
            "Section 2 is open and section 1 is closed; a loft's sections must all be open or all closed.")) {
            _ = try await kernel.loftSurface([closedCircle, open], ruled: false, closed: false, tag: tag)
        }
        await #expect(throws: KernelError.invalidInput("The direction can't be zero.")) {
            _ = try await kernel.extrude(line, direction: .zero, distance: 1, symmetric: false, tag: tag)
        }
        for degrees in [0.0, -10, 361] {
            await #expect(throws: KernelError.invalidInput("The angle must be more than 0° and at most 360°.")) {
                _ = try await kernel.revolve(line, axis: Axis(origin: .zero, direction: .unitY),
                                             angle: Angle.degrees(degrees), tag: tag)
            }
        }
    }

    @Test func zeroDistanceIsRefused() async throws {
        let kernel = OCCTKernel()
        await #expect(throws: KernelError.invalidInput("The distance must be greater than 0 mm.")) {
            _ = try await kernel.extrude(try await threeLines(kernel), direction: .unitZ, distance: 0, symmetric: false, tag: tag)
        }
    }

    @Test func sectionsWithDifferentPieceCountsAreRefused() async throws {
        let kernel = OCCTKernel()
        let lines = try await threeLines(kernel)
        let single = try await arc(kernel, z: 5)
        for ruled in [false, true] {
            await #expect(throws: KernelError.invalidInput("Loft sections need the same number of pieces.")) {
                _ = try await kernel.loftSurface([lines, single], ruled: ruled, closed: false, tag: tag)
            }
        }
    }

    func faceSpans(_ sheet: Solid) -> Set<Int> {
        var spans: Set<Int> = []
        for face in sheet.topology.faces {
            for item in face.tags { if case .side(let loop, _) = item.role { spans.insert(loop) } }
        }
        return spans
    }

    func railCount(_ sheet: Solid, _ which: Int) -> Int { count(sheet, .rail(which)) }

    func untaggedBoundaries(_ sheet: Solid) -> Int { sheet.topology.edges.filter { $0.isBoundary && $0.tags.isEmpty }.count }

    @Test func aRuledOpenLoftOfThreeSectionsNamesEverySpanAndRail() async throws {
        let kernel = OCCTKernel()
        let sections = [try await arc(kernel, z: 0), try await arc(kernel, z: 5, radius: 7), try await arc(kernel, z: 9)]
        let sheet = try await kernel.loftSurface(sections, ruled: true, closed: false, tag: tag)
        #expect(sheet.topology.faces.count == 2)
        #expect(faceSpans(sheet) == [0, 1])
        #expect(sheet.topology.faces.allSatisfy { $0.tags.count == 1 })
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        #expect(railCount(sheet, 0) == 2 && railCount(sheet, 1) == 2)
        #expect(untaggedBoundaries(sheet) == 0)
    }

    @Test func aSmoothOpenLoftOfThreeSectionsIsOneNamedSpan() async throws {
        let kernel = OCCTKernel()
        let sections = [try await arc(kernel, z: 0), try await arc(kernel, z: 5, radius: 7), try await arc(kernel, z: 9)]
        let sheet = try await kernel.loftSurface(sections, ruled: false, closed: false, tag: tag)
        #expect(sheet.topology.faces.count == 1 && faceSpans(sheet) == [0])
        #expect(count(sheet, .start) == 1 && count(sheet, .end) == 1)
        #expect(railCount(sheet, 0) == 1 && railCount(sheet, 1) == 1)
        #expect(untaggedBoundaries(sheet) == 0)
    }

    @Test func aRuledClosedLoftNamesEverySpanIncludingTheReturn() async throws {
        let kernel = OCCTKernel()
        let sections = [try await circle(kernel, z: 0), try await circle(kernel, z: 5, radius: 7), try await circle(kernel, z: 9)]
        let sheet = try await kernel.loftSurface(sections, ruled: true, closed: true, tag: tag)
        #expect(sheet.topology.faces.count == 3 && faceSpans(sheet) == [0, 1, 2])
        #expect(count(sheet, .start) == 0 && count(sheet, .end) == 0)
        #expect(untaggedBoundaries(sheet) == 0)
    }
}
#endif
