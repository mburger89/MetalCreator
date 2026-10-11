import CreatorKernel
import Testing
@testable import CreatorApp

/// The pattern benchmark's plate is ready to measure (patterns spec §7): the three variants make the part they claim
/// to, every node OK, the part shown. They run here on a small grid so a plain `swift test` stays quick; the
/// benchmark builds the spec's 200 holes (`PatternBenchApp.columns` × `rows`).
@MainActor
struct PatternBenchAppTests {
    static let holeVolume = Double.pi * 6.25 * 6

    @Test func theBenchmarkIsTheSpecsTwoHundredHoles() {
        #expect(PatternBenchApp.columns * PatternBenchApp.rows == 200)
    }

    @Test func theShortcutCutsEveryHole() async throws {
        let bench = try await PatternBenchApp(.shortcut, columns: 5, rows: 3)
        expectAllOK(bench.app, "the shortcut")
        #expect(bench.app.viewport.items.count == 1, "the part is shown")
        let part = try #require(bench.part)
        #expect(abs(try await bench.kernel.properties(of: part).volume - (PatternBenchApp.plateVolume - 15 * Self.holeVolume)) < 1e-3)
    }

    @Test func thePlaceAndBooleanVariantCutsTheSamePart() async throws {
        let bench = try await PatternBenchApp(.explicit, columns: 5, rows: 3)
        expectAllOK(bench.app, "Place and Boolean")
        let part = try #require(bench.part)
        #expect(abs(try await bench.kernel.properties(of: part).volume - (PatternBenchApp.plateVolume - 15 * Self.holeVolume)) < 1e-3)
    }

    @Test func theFilletVariantRoundsOneHolesRimAndNothingElse() async throws {
        let bench = try await PatternBenchApp(.fillet, columns: 5, rows: 3)
        expectAllOK(bench.app, "the filleted hole")
        let part = try #require(bench.part)
        let faces = part.topology.faces.count
        let plain = try await PatternBenchApp(.shortcut, columns: 5, rows: 3)
        #expect(faces == (try #require(plain.part)).topology.faces.count, "the Hole Pattern's own result has no fillet")
        let output = try #require(bench.app.document.graph.nodes.values.first { $0.isOutput })
        let filleted = try #require(bench.solid(of: output))
        #expect(filleted.topology.faces.count == faces + 1, "one blend face")
    }

    @Test func editingTheDiameterRebuildsThePart() async throws {
        let bench = try await PatternBenchApp(.shortcut, columns: 5, rows: 3)
        try await bench.setDiameter(4)
        expectAllOK(bench.app, "after the edit")
        let part = try #require(bench.part)
        #expect(abs(try await bench.kernel.properties(of: part).volume - (PatternBenchApp.plateVolume - 15 * Double.pi * 4 * 6)) < 1e-3)
    }
}
