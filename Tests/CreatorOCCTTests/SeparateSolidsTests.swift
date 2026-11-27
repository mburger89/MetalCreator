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
        let mixed = try await kernel.sewn([part, sheet], tolerance: 0.01, tag: newTag()).body
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
        // The sheet keeps its boundary edge names, value for value.
        let boundary = { (solid: Solid) in solid.topology.edges.filter(\.isBoundary).map(\.tags) }
        let inputBoundary = boundary(mixed)
        #expect(inputBoundary.count == 4 && inputBoundary.allSatisfy { !$0.isEmpty })
        #expect(Set(boundary(parts.sheets[0])) == Set(inputBoundary))
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

    @Test func facesSharingAnEdgeAreOneSurface() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let edge = try #require(part.topology.edges.first { $0.faces.count == 2 && $0.faces[0] != $0.faces[1] })
        let first = try await kernel.subSheet([edge.faces[0]], of: part)
        let second = try await kernel.subSheet([edge.faces[1]], of: part)
        let joined = try await kernel.compound([first, second], tag: newTag())
        let parts = try await kernel.separated(joined, tag: tag)
        #expect(parts.solids.isEmpty && parts.sheets.count == 1)
        #expect(parts.sheets[0].topology.faces.count == 2)
    }

    @Test func aSolidWithAVoidIsOneSolid() async throws {
        let outer = try await box(kernel, 20, 20, 20)
        let inner = try await kernel.transform(try await box(kernel, 4, 4, 4), by: Transform(translation: Vector3(0, 0, 8)), tag: newTag())
        let hollow = try await kernel.boolean(.subtract, outer, [inner], tag: newTag())
        #expect(hollow.topology.faces.count == 12)
        let parts = try await kernel.separated(hollow, tag: tag)
        #expect(parts.solids.count == 1 && parts.sheets.isEmpty)
        #expect(parts.solids[0].topology.faces.count == 12)
    }

    @Test func splitSolidSentencesAtTheKernel() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let sheet = try await square(x: 30...40)
        let mixed = try await kernel.compound([part, sheet], tag: newTag())
        let openOnly = try await square(x: 0...10)
        for (value, sentence) in [
            (mixed, "Split Solid takes a closed solid; “solid” also holds a surface. Use Separate Solids to take the solid out first."),
            (openOnly, "Split Solid takes a closed solid; the solid is an open surface."),
        ] {
            do {
                _ = try await kernel.splitSolid(value, by: [sheet], tag: tag)
                Issue.record("expected a refusal")
            } catch let error as KernelError {
                #expect(error.userMessage == sentence)
            }
        }
    }

    @Test func aLoneSolidComesOutAsOne() async throws {
        let part = try await box(kernel, 10, 10, 10)
        let parts = try await kernel.separated(part, tag: tag)
        #expect(parts.solids.count == 1 && parts.sheets.isEmpty)
        #expect(parts.solids[0].topology.faces.map(\.tags) == part.topology.faces.map(\.tags))
    }
}
#endif
