import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Fields spec §2.1: `Field.description` is a one-line recipe, numbers in `Locale.messages`; pinned.
struct FieldDescriptionTests {
    func edges() async throws -> DistanceTarget {
        let solid = try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                                   tag: NodeTag(node: NodeID(), item: 0))
        return .edges(EdgeSet(solid: solid, edges: [EdgeID(0)]))
    }

    @Test func theSpecsExampleReadsAsWritten() async throws {
        let distance = Field.distance(.kernel(try await edges()), signed: false)
        let field = Field.multiply(.remap(distance, fromLow: 0, fromHigh: 20, toLow: 1, toHigh: 0, clamped: true),
                                   .noise(seed: 4, scale: 5, octaves: 3))
        #expect(field.description == "remap(distance(edges), 0…20 → 1…0) × noise(seed 4, scale 5, octaves 3)")
    }

    @Test func constantsUseTheMessageLocaleAndNeverPrintMinusZero() {
        #expect(Field.constant(0.5).description == "0.5")
        #expect(Field.constant(1234.5).description == "1,234.5")
        #expect(Field.constant(1.0 / 3).description == "0.33")
        #expect(Field.constant(-2).description == "-2")
        #expect(Field.constant(-0.0).description == "0")
    }

    @Test func theSourcesNameWhatTheyMeasure() async throws {
        let target = try await edges()
        #expect(Field.distance(.point(.zero), signed: false).description == "distance(point)")
        #expect(Field.distance(.profile(.rectangle(width: 1, height: 1, plane: .xy)), signed: false).description == "distance(profile)")
        #expect(Field.distance(.kernel(target), signed: false).description == "distance(edges)")
        guard case .edges(let set) = target else { return }
        #expect(Field.distance(.kernel(.faces(FaceSet(solid: set.solid, faces: [FaceID(0)]))), signed: true).description
            == "distance(faces)")
        #expect(Field.distance(.kernel(.solid(set.solid)), signed: true).description == "distance(solid)")
        #expect(Field.distance(.kernel(.solid(set.solid)), signed: false).description == "distance(solid, unsigned)")
        #expect(Field.linearGradient(plane: .xy, length: 20).description == "linear(length 20)")
        #expect(Field.radialGradient(center: .zero, radius: 7.25).description == "radial(radius 7.25)")
        #expect(Field.noise(seed: -3, scale: 2.5, octaves: 1).description == "noise(seed -3, scale 2.5, octaves 1)")
    }

    @Test func infixMathsBracketsOnlyWhereTheOrderNeedsIt() {
        let one = Field.constant(1), two = Field.constant(2), three = Field.constant(3)
        #expect(Field.add(one, two).description == "1 + 2")
        #expect(Field.multiply(.add(one, two), three).description == "(1 + 2) × 3")
        #expect(Field.add(.multiply(one, two), three).description == "1 × 2 + 3")
        #expect(Field.multiply(one, .multiply(two, three)).description == "1 × 2 × 3")
    }

    @Test func theFunctionsReadLikeCalls() {
        let one = Field.constant(1), two = Field.constant(2)
        #expect(Field.minimum(one, two).description == "min(1, 2)")
        #expect(Field.maximum(one, two).description == "max(1, 2)")
        #expect(Field.clamp(one, low: 0, high: 0.5).description == "clamp(1, 0…0.5)")
        #expect(Field.smoothMinimum(one, two, width: 1.5).description == "smoothMin(1, 2, width 1.5)")
        #expect(Field.remap(one, fromLow: 0, fromHigh: 10, toLow: 5, toHigh: -5, clamped: true).description == "remap(1, 0…10 → 5…-5)")
        #expect(Field.remap(one, fromLow: 0, fromHigh: 10, toLow: 5, toHigh: -5, clamped: false).description
            == "remap(1, 0…10 → 5…-5, unclamped)")
    }

    @Test func theTooltipFormIsShortenedToEightyCharacters() {
        var field = Field.constant(1)
        for step in 1...30 { field = .add(field, .constant(Double(step))) }
        #expect(field.description.count > 80)
        let short = field.description(limit: 80)
        #expect(short.count == 80 && short.hasSuffix("…") && field.description.hasPrefix(String(short.dropLast())))
        #expect(Field.constant(1).description(limit: 80) == "1")
        #expect(Field.constant(1).description(limit: 0) == "…")
    }
}
