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
