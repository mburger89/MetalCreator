import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// What a refused fillet costs: the search for the largest size that works (up to about 20 failing tries, Errata
/// (Kernel: largest size for blends OCCT can't build)), against a blend that works, and the checker on its own
/// (`BRepCheck_Analyzer` on every blend result, the M0–M1 carry-over note's "watch" item). Two parts: §8's hexagon
/// flange at R3, whose result OCCT builds but its checker rejects, and the §7.2 bracket with its Fillet at a radius its
/// edges can't take (which of the two refusals it meets is not recorded; both run the search). Prints `BENCH blend-…`
/// lines.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct BlendRefusalBench {
    static func tag() -> NodeTag { NodeTag(node: NodeID(), item: 0) }

    /// The plate and hexagon flange of `Tests/CreatorOCCTTests/Support/HexagonFlange.swift` (CreatorOCCTTests, which this
    /// target can't import) and its four upright edges. A copy: `BlendRefusalFixtureTests` (run by a plain `swift test`)
    /// asserts what the original is known for, so the copies can't drift apart unnoticed.
    static func flange(_ kernel: OCCTKernel) async throws -> (union: Solid, edges: [EdgeID]) {
        let plate = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6,
                                             mode: .oneSided, tag: tag())
        let hexagon = try await kernel.extrude(.regularPolygon(sides: 6, radius: 15, rotation: .degrees(30),
                                                               plane: Plane.xz.offset(by: -20)),
                                               distance: 8, mode: .oneSided, tag: tag())
        let lifted = try await kernel.transform(hexagon, by: Transform(translation: Vector3(0, 0, 15)), tag: tag())
        let union = try await kernel.boolean(.union, plate, [lifted], tag: tag())
        let upright = union.topology.edges.filter { edge in
            edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
        }
        return (union, upright.map(\.id))
    }

    @Test func aRefusedFilletOnTheFlangeAgainstOneThatWorks() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let (union, edges) = try await Self.flange(kernel)
        let shape = try #require((union.storage as? OCCTSolidStorage)?.shape)
        var works = BenchSamples("blend-flange fillet R2.5 (works: build + check)")
        var refused = BenchSamples("blend-flange fillet R3 (refused: build + check + search)")
        var search = BenchSamples("blend-flange search alone (largestValidBlend below R3)")
        var check = BenchSamples("blend-flange checker alone (BRepCheck_Analyzer on the union)")
        let clock = ContinuousClock()
        for step in 0..<30 {
            let a = clock.now
            _ = try await kernel.fillet(union, edges: edges, radius: 2.5, tag: Self.tag())
            let b = clock.now
            let error = await #expect(throws: KernelError.self) {
                try await kernel.fillet(union, edges: edges, radius: 3, tag: Self.tag())
            }
            let c = clock.now
            #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
            _ = try await kernel.largestValidBlend(of: shape, edges: edges, below: 3, chamfer: false)
            let d = clock.now
            _ = OCCTKernel.serialized { shape.isValid }
            let e = clock.now
            guard step >= 5 else { continue }
            works.append(from: a, to: b)
            refused.append(from: b, to: c)
            search.append(from: c, to: d)
            check.append(from: d, to: e)
        }
        for samples in [works, refused, search, check] { print(samples.line()) }
    }

    @Test func aRefusedFilletOnTheBracketAgainstOneThatWorks() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        var works = BenchSamples("blend-bracket Fillet node R3.x (works; evaluation of the Fillet and what follows)")
        var refused = BenchSamples("blend-bracket Fillet node R8.x (refused; evaluation of the Fillet and what follows)")
        let clock = ContinuousClock()
        for step in 0..<25 {
            let a = clock.now
            try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(3 + Double(step) * 0.01)))
            await app.settle()
            let b = clock.now
            try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(8 + Double(step) * 0.05)))
            await app.settle()
            let c = clock.now
            guard step >= 5 else { continue }
            works.append(from: a, to: b)
            refused.append(from: b, to: c)
        }
        guard case .error(let message)? = app.document.results[bracket.fillet.id]?.state else {
            Issue.record("the Fillet at R8 should be in error")
            return
        }
        print("BENCH blend-bracket message: \(message)")
        print(works.line())
        print(refused.line())
    }
}
