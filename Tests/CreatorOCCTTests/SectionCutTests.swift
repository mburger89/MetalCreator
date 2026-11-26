#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// DR-3 Task 2: `Kernel.cutAway` on OpenCascade (R1, R4).
struct SectionCutTests {
    let kernel = OCCTKernel()
    let tag = NodeTag(node: SectionCutter.toolNode, item: 0)
    let source = NodeTag(node: NodeID(), item: 0)
    let top = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))

    func rectangle(_ width: Double, _ height: Double) -> Profile2D {
        Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(width, 0)), .line(Vector2(width, 0), Vector2(width, height)),
            .line(Vector2(width, height), Vector2(0, height)), .line(Vector2(0, height), Vector2(0, 0)),
        ])
    }

    func box() async throws -> Solid {
        try await kernel.extrude(rectangle(40, 20), distance: 10, mode: .oneSided, tag: source)
    }

    func cutter(_ points: [(Double, Double)]) -> SectionCutter {
        SectionCutter(frame: top, points: points.map { Vector2($0.0, $0.1) }, viewing: Vector2(0, 1))
    }

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    @Test func aStraightCutKeepsTheFarSide() async throws {
        let result = try #require(try await kernel.cutAway(box(), by: cutter([(-5, 5), (45, 5)]), tag: tag))
        #expect(abs(result.bounds.min.y - 5) < 1e-6 && abs(result.bounds.max.y - 20) < 1e-6)
        #expect(abs(try await volume(result) - 6000) < 1e-6)
    }

    @Test func aSteppedCutLeavesTheStep() async throws {
        let line = cutter([(-5, 5), (20, 5), (20, 15), (45, 15)])
        let result = try #require(try await kernel.cutAway(box(), by: line, tag: tag))
        #expect(abs(try await volume(result) - 4000) < 1e-6)
    }

    @Test func cutFacesCarryTheCuttersNames() async throws {
        let line = cutter([(-5, 5), (20, 5), (20, 15), (45, 15)])
        let result = try #require(try await kernel.cutAway(box(), by: line, tag: tag))
        var found = Set<Int>()
        for face in result.topology.faces {
            for tagged in face.tags where tagged.node == SectionCutter.toolNode {
                #expect(tagged.item == 0)
                if case .side(let loop, let segment) = tagged.role {
                    #expect(loop == 0)
                    found.insert(segment)
                }
            }
        }
        #expect(found == [0, 1, 2])
        for face in result.topology.faces {
            #expect(!face.tags.contains { if case .unnamed = $0.role { true } else { false } })
        }
        // A cut edge borders one part face and one cut face.
        func isCut(_ id: FaceID) -> Bool { result.topology.face(id)?.tags.contains { $0.node == SectionCutter.toolNode } == true }
        let cutEdges = result.topology.edges.filter { edge in edge.faces.filter(isCut).count == 1 }
        #expect(!cutEdges.isEmpty)
        for edge in cutEdges {
            let sides = edge.faces.compactMap { result.topology.face($0) }
            #expect(sides.contains { $0.tags.contains { $0.node == source.node } })
        }
    }

    @Test func aLineThatMissesReturnsTheSolid() async throws {
        let part = try await box()
        let result = try await kernel.cutAway(part, by: cutter([(-5, -10), (45, -10)]), tag: tag)
        #expect(result === part)
    }

    @Test func aLineThatSwallowsReturnsNil() async throws {
        let result = try await kernel.cutAway(box(), by: cutter([(-5, 30), (45, 30)]), tag: tag)
        #expect(result == nil)
    }

    @Test func aCutThroughAHoleAxisIsValid() async throws {
        let part = try await box()
        let circle = Profile2D(plane: .xy, segments: [
            .arc(center: Vector2(20, 10), radius: 4, start: Angle(radians: 0), end: Angle(radians: 2 * .pi)),
        ])
        let hole = try await kernel.extrude(circle, distance: 10, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let holed = try await kernel.boolean(.subtract, part, [hole], tag: source)
        let whole = try await volume(holed)
        let result = try #require(try await kernel.cutAway(holed, by: cutter([(-5, 10), (45, 10)]), tag: tag))
        #expect(abs(try await volume(result) - whole / 2) < 1e-6)
    }

    @Test func aCutAlongAFaceIsValidOrRefused() async throws {
        do {
            let result = try #require(try await kernel.cutAway(box(), by: cutter([(-5, 0), (45, 0)]), tag: tag))
            #expect(abs(try await volume(result) - 8000) < 1e-6)
        } catch let error as KernelError {
            guard case .operationFailed(let operation, let reason) = error else { throw error }
            #expect(operation == "section" && reason == "the section couldn't be cut through this part.")
        }
    }

    @Test func aSheetIsCut() async throws {
        let corners = [Vector3(0, 0, 0), Vector3(0, 20, 0), Vector3(40, 20, 0), Vector3(40, 0, 0)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: source)
        let sheet = try await kernel.planarSurface([loop], tag: source)
        let result = try #require(try await kernel.cutAway(sheet, by: cutter([(-5, 5), (45, 5)]), tag: tag))
        #expect(result.hasOpenShell)
        #expect(abs(result.bounds.min.y - 5) < 1e-6)
        let onLine = result.topology.edges.filter { $0.isBoundary && abs($0.midpoint.y - 5) < 1e-6 }
        #expect(!onLine.isEmpty)
    }

    @Test func aDiskSheetTheLineMissesIsKeptOrRemoved() async throws {
        let ring = CurvePiece.arc(center: .zero, normal: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: 2 * .pi)
        let sheet = try await kernel.planarSurface([try await kernel.makeCurve([ring], tag: source)], tag: source)
        let points = [(-20.0, 34.5), (20.0, -5.5)]
        let h = 0.5.squareRoot()
        let line = points.map { Vector2($0.0, $0.1) }
        let keptSide = SectionCutter(frame: top, points: line, viewing: Vector2(-h, -h))
        let removedSide = SectionCutter(frame: top, points: line, viewing: Vector2(h, h))
        let kept = try #require(try await kernel.cutAway(sheet, by: keptSide, tag: tag))
        #expect(kept.topology.faces.count == sheet.topology.faces.count)
        #expect(try await kernel.cutAway(sheet, by: removedSide, tag: tag) == nil)
    }

    private func polygonSheet(_ points: [(Double, Double)]) async throws -> Solid {
        let vectors = points.map { Vector3($0.0, $0.1, 0) }
        let pieces = vectors.indices.map { CurvePiece.line(vectors[$0], vectors[($0 + 1) % vectors.count]) }
        return try await kernel.planarSurface([try await kernel.makeCurve(pieces, tag: source)], tag: source)
    }

    /// The centroid of an L lies in its notch, inside the removed region, yet the whole L is on the kept side.
    @Test func anLSheetWhoseCentroidIsOffTheFaceIsKept() async throws {
        let sheet = try await polygonSheet([(0, 0), (40, 0), (40, 2), (2, 2), (2, 40), (0, 40)])
        let line = SectionCutter(frame: top, points: [Vector2(-50, 50), Vector2(5, 50), Vector2(5, 5), Vector2(60, 5)],
                                 viewing: Vector2(0, -1))
        let kept = try #require(try await kernel.cutAway(sheet, by: line, tag: tag))
        #expect(kept.topology.faces.count == 1)
        #expect(abs(kept.bounds.max.x - 40) < 1e-6 && abs(kept.bounds.max.y - 40) < 1e-6)
    }

    /// Two separate faces with the line between them: the one on the removed side goes, the other stays.
    @Test func twoSeparateFacesAreEachKeptOrRemoved() async throws {
        let left = try await polygonSheet([(0, 0), (10, 0), (10, 10), (0, 10)])
        let right = try await polygonSheet([(30, 0), (40, 0), (40, 10), (30, 10)])
        let both = try await kernel.compound([left, right], tag: source)
        let line = SectionCutter(frame: top, points: [Vector2(20, -5), Vector2(20, 15)], viewing: Vector2(1, 0))
        let kept = try #require(try await kernel.cutAway(both, by: line, tag: tag))
        #expect(kept.topology.faces.count == 1)
        #expect(abs(kept.bounds.min.x - 30) < 1e-6)
    }

    @Test func cancelledBeforeTheBoolean() async throws {
        let part = try await box()
        let line = cutter([(-5, 5), (45, 5)])
        let kernel = self.kernel, tag = self.tag
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.cutAway(part, by: line, tag: tag)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
#endif
