#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 3: `Kernel.sewn(_:tolerance:tag:)` (R5, R6, R19).
struct SewTests {
    let sewTag = NodeTag(node: NodeID(), item: 0)

    /// The box's loose faces read back as the sheet Import Model makes, with R19's precondition asserted.
    func looseSheet(_ kernel: OCCTKernel, moving: Double = 0, doubling: Bool = false) async throws -> Solid {
        let data = try OCCTKernel.looseBoxFaces(size: 10, movingTopBy: moving, doublingTop: doubling)
        let read = try await kernel.readShapes(data, format: .step, tag: newTag())
        let sheet = try #require(read.sheets.first)
        #expect(read.sheets.count == 1 && read.solids.isEmpty)
        #expect(sheet.topology.faces.count == (doubling ? 7 : 6))
        #expect(sheet.topology.edges.filter(\.isBoundary).count == (doubling ? 28 : 24))
        return sheet
    }

    func rectangle(_ kernel: OCCTKernel, x: ClosedRange<Double>, y: ClosedRange<Double>) async throws -> Solid {
        let corners = [Vector3(x.lowerBound, y.lowerBound, 0), Vector3(x.upperBound, y.lowerBound, 0),
                       Vector3(x.upperBound, y.upperBound, 0), Vector3(x.lowerBound, y.upperBound, 0),
        ]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    func tagSets(_ solid: Solid) -> [[String]] {
        solid.topology.faces.map { $0.tags.map(\.sortKey).sorted() }.sorted { $0.joined() < $1.joined() }
    }

    @Test func sixFacesOfABoxSewIntoASolid() async throws {
        let kernel = OCCTKernel()
        let sheet = try await looseSheet(kernel)
        let sewn = try await kernel.sewn([sheet], tolerance: 0.01, tag: sewTag)
        #expect(sewn.solids == 1 && sewn.sheets == 0 && sewn.unclosable == 0)
        #expect(!sewn.body.hasOpenShell)
        #expect(try await abs(kernel.properties(of: sewn.body).volume - 1000) <= 1e-3)
        #expect(tagSets(sewn.body) == tagSets(sheet))
        #expect(sewn.body.topology.edges.allSatisfy { !$0.isBoundary })
    }

    @Test func aGapWiderThanTheToleranceStaysOpen() async throws {
        let kernel = OCCTKernel()
        let sheet = try await looseSheet(kernel, moving: 0.05)
        let tight = try await kernel.sewn([sheet], tolerance: 0.01, tag: sewTag)
        #expect(tight.solids == 0 && tight.sheets == 2)
        #expect(tight.body.hasOpenShell)
        #expect(tight.body.topology.edges.filter(\.isBoundary).count == 8)
        let wide = try await kernel.sewn([sheet], tolerance: 0.1, tag: sewTag)
        #expect(wide.solids == 1 && wide.sheets == 0)
    }

    @Test func aDuplicateFaceNeverMakesAnInvalidSolid() async throws {
        let kernel = OCCTKernel()
        let sheet = try await looseSheet(kernel, doubling: true)
        let copyTag = try #require(sheet.topology.faces.last?.tags)
        #expect(copyTag.contains { $0.role == .imported(face: 6) })
        let sewn = try await kernel.sewn([sheet], tolerance: 0.01, tag: sewTag)
        let shape = try await kernel.shape(of: sewn.body)
        #expect(shape.isValid)
        #expect(sewn.solids == 1 && sewn.sheets == 1)
        #expect(try await abs(kernel.properties(of: sewn.body).volume - 1000) <= 1e-3)
        let open = sewn.body.topology.faces.filter(\.isOnOpenShell)
        #expect(open.count == 1)
        #expect(open.first?.tags.contains { $0.role == .imported(face: 6) } == true)
        #expect(sewn.body.topology.edges.filter(\.isBoundary).count == 4)
    }

    @Test func aSewnEdgeRemembersItsBoundaryNames() async throws {
        let kernel = OCCTKernel()
        let left = try await rectangle(kernel, x: 0...10, y: 0...10)
        let right = try await rectangle(kernel, x: 10...20, y: 0...10)
        func edge(_ solid: Solid, at point: Vector3) throws -> EdgeInfo {
            try #require(solid.topology.edges.first { ($0.midpoint - point).length < 1e-6 })
        }
        let leftSide = try edge(left, at: Vector3(10, 5, 0))
        let rightSide = try edge(right, at: Vector3(10, 5, 0))
        #expect(!leftSide.tags.isEmpty && !rightSide.tags.isEmpty && leftSide.tags != rightSide.tags)
        let sewn = try await kernel.sewn([left, right], tolerance: 0.01, tag: sewTag)
        #expect(sewn.solids == 0 && sewn.sheets == 1)
        let joined = try edge(sewn.body, at: Vector3(10, 5, 0))
        #expect(joined.faces.count == 2)
        #expect(joined.tags == leftSide.tags.union(rightSide.tags))
        let free = try edge(sewn.body, at: Vector3(5, 0, 0))
        #expect(free.isBoundary)
        #expect(free.tags == (try edge(left, at: Vector3(5, 0, 0))).tags)
    }

    @Test func aSolidInTheListPassesThrough() async throws {
        let kernel = OCCTKernel()
        let square = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 6)),
            .line(Vector2(10, 6), Vector2(0, 6)), .line(Vector2(0, 6), Vector2(0, 0)),
        ])
        let box = try await kernel.extrude(square, distance: 4, mode: .oneSided, tag: newTag())
        let far = try await rectangle(kernel, x: 40...50, y: 0...10)
        let sewn = try await kernel.sewn([box, far], tolerance: 0.01, tag: sewTag)
        #expect(sewn.solids == 1 && sewn.sheets == 1)
        let closed = sewn.body.topology.faces.filter { !$0.isOnOpenShell }
        #expect(closed.map { $0.tags.map(\.sortKey).sorted() }.sorted { $0.joined() < $1.joined() } == tagSets(box))
    }

    @Test func refusals() async throws {
        let kernel = OCCTKernel()
        let sheet = try await rectangle(kernel, x: 0...10, y: 0...10)
        await #expect(throws: KernelError.invalidInput("Sew needs at least one surface.")) {
            _ = try await kernel.sewn([], tolerance: 0.01, tag: sewTag)
        }
        for bad in [0.0, -1, .nan, .infinity] {
            await #expect(throws: KernelError.invalidInput("The tolerance must be greater than 0.")) {
                _ = try await kernel.sewn([sheet], tolerance: bad, tag: sewTag)
            }
        }
        let task = Task { try await kernel.sewn([sheet], tolerance: 0.01, tag: sewTag) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
#endif
