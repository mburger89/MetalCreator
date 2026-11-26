#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NURBS gaps Task 2: `Kernel.separated(_:tag:)` (R3).
struct SeparateSolidsTests {
    let kernel = OCCTKernel()
    let tag = newTag()

    /// A Planar Surface over `x` and y 0 to 10 at `z`.
    func square(x: ClosedRange<Double>, z: Double = 0) async throws -> Solid {
        let corners = [Vector3(x.lowerBound, 0, z), Vector3(x.lowerBound, 10, z), Vector3(x.upperBound, 10, z), Vector3(x.upperBound, 0, z)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    func tagSets(_ solids: [Solid]) -> [Set<TopoTag>] {
        solids.flatMap(\.topology.faces).map(\.tags)
    }

    @Test func aSolidAndASheetComeApart() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let sheet = try await square(x: 30...40)
        let mixed = try await kernel.compound([part, sheet], tag: newTag())
        #expect(mixed.hasOpenShell && mixed.holdsClosedSolid)
        let parts = try await kernel.separated(mixed, tag: tag)
        #expect(parts.solids.count == 1 && parts.sheets.count == 1)
        #expect(parts.solids[0].isClosed && !parts.solids[0].hasOpenShell)
        #expect(parts.sheets[0].hasOpenShell && !parts.sheets[0].holdsClosedSolid)
        // Every face tag of the input is in exactly one output.
        let output = tagSets(parts.solids + parts.sheets)
        let input = tagSets([mixed])
        #expect(output.count == input.count)
        for tags in input { #expect(output.filter { $0 == tags }.count == input.filter { $0 == tags }.count) }
        #expect(parts.solids[0].topology.faces.count == 6 && parts.sheets[0].topology.faces.count == 1)
        // The sheet keeps its boundary edge names.
        #expect(parts.sheets[0].topology.edges.filter(\.isBoundary).count == 4)
    }

    @Test func onlySolidsLeaveSheetsEmpty() async throws {
        let first = try await box(kernel, 10, 10, 10)
        let second = try await box(kernel, 5, 5, 5)
        let moved = try await kernel.transform(second, by: Transform(translation: Vector3(40, 0, 0)), tag: newTag())
        let both = try await kernel.compound([first, moved], tag: newTag())
        let parts = try await kernel.separated(both, tag: tag)
        #expect(parts.solids.count == 2 && parts.sheets.isEmpty)
        #expect(parts.solids.allSatisfy { !$0.hasOpenShell })
    }

    @Test func onlySheetsLeaveSolidsEmpty() async throws {
        let apart = try await kernel.compound([square(x: 0...10), square(x: 20...30)], tag: newTag())
        let parts = try await kernel.separated(apart, tag: tag)
        #expect(parts.solids.isEmpty && parts.sheets.count == 2)
        #expect(parts.sheets.allSatisfy { $0.hasOpenShell })
    }

    @Test func aLoneSolidComesOutAsOne() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let parts = try await kernel.separated(part, tag: tag)
        #expect(parts.solids.count == 1 && parts.sheets.isEmpty)
        #expect(parts.solids[0].topology.faces.map(\.tags) == part.topology.faces.map(\.tags))
    }
}
#endif
