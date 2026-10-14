import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// `Field.slopeBound` and `Field.valueRange` (implicit spec §3.3): hand-worked values, then the bound against the sampler on random
/// pairs of points.
struct FieldSlopeTests {
    struct Ball: ImplicitPayload, Hashable {
        var radius: Double
        var summary: String { "ball" }
        var estimatedBytes: Int { 96 }
        var payloadBounds: BoundingBox { BoundingBox(min: Vector3(-radius, -radius, -radius), max: Vector3(radius, radius, radius)) }
        var lipschitz: Double { 1.5 }
        func signedDistance(at point: Vector3) -> Double { 1.5 * (point.length - radius) }
    }

    /// A 4 × 4 picture whose columns step 0, 21,845, 43,690 and 65,535: a quarter of the range per column.
    static let ramp = GreyImage(width: 4, height: 4,
                                pixels: (0..<16).map { UInt16(($0 % 4) * 21_845) })

    func slope(_ field: Field) -> Double { field.slopeBound.value }

    @Test func sourcesHaveTheirAnalyticSlopes() {
        #expect(slope(.constant(5)) == 0)
        #expect(slope(.distance(.point(.zero), signed: false)) == 1)
        #expect(slope(.linearGradient(plane: .xy, length: 20)) == 0.05)
        #expect(slope(.radialGradient(center: .zero, radius: 4)) == 0.25)
        #expect(Field.constant(1).slopeBound.isKnown)
    }

    @Test func noiseHasADeclaredBound() {
        #expect(slope(.noise(seed: 1, scale: 8, octaves: 1)) == FieldNoise.unitSlope / 8)
        // Two octaves: 2 × 4 / (2 × 0.75 × 8).
        #expect(abs(slope(.noise(seed: 1, scale: 8, octaves: 2)) - 8.0 / 12) < 1e-12)
    }

    @Test func anImageIsBoundedByItsPixelDifferences() throws {
        let image = try #require(Self.ramp)
        // Across: 21,845 / 65,535 = 1/3 per pixel; the picture is 8 mm wide, so a pixel is 2 mm: 1/6 per mm. Down: 0.
        let clamped = Field.image(image, plane: .xy, width: 8, height: 8, edges: .clamp)
        #expect(abs(slope(clamped) - 1.0 / 6) < 1e-5)
        // Tiling counts the wrap from the last column back to the first: a step of 65,535, a full unit per pixel.
        let tiled = Field.image(image, plane: .xy, width: 8, height: 8, edges: .tile)
        #expect(abs(slope(tiled) - 0.5) < 1e-5)
    }

    @Test func anImplicitTakesItsPayloadsBound() {
        #expect(slope(.implicit(ImplicitReference(Ball(radius: 3)))) == 1.5)
    }

    @Test func theMathsCombinesBounds() {
        let linear = Field.linearGradient(plane: .xy, length: 10)
        let radial = Field.radialGradient(center: .zero, radius: 5)
        #expect(abs(slope(.add(linear, radial)) - 0.3) < 1e-12)
        #expect(slope(.minimum(linear, radial)) == 0.2 && slope(.maximum(linear, radial)) == 0.2)
        #expect(slope(.smoothMinimum(linear, radial, width: 2)) == 0.2)
        #expect(abs(slope(.remap(linear, fromLow: 0, fromHigh: 2, toLow: 0, toHigh: 10, clamped: true)) - 0.5) < 1e-12)
        #expect(slope(.remap(linear, fromLow: 1, fromHigh: 1, toLow: 0, toHigh: 10, clamped: false)) == 0)
        #expect(slope(.clamp(radial, low: 0, high: 1)) == 0.2)
        // Noise is in 0…1: its product with a constant 3 weighs the noise's slope by 3.
        let noise = Field.noise(seed: 1, scale: 8, octaves: 1)
        #expect(abs(slope(.multiply(noise, .constant(3))) - 3 * 0.5) < 1e-12)
        // Two noises: each weighs the other's range (1).
        #expect(abs(slope(.multiply(noise, noise)) - 1.0) < 1e-12)
    }

    @Test func aProductWithAnUnboundedSideHasNoBound() {
        let distance = Field.distance(.point(.zero), signed: false)
        let product = Field.multiply(distance, .linearGradient(plane: .xy, length: 10))
        #expect(!product.slopeBound.isKnown && product.slopeBound.value == Field.unknownSlope)
        #expect(Field.add(product, .constant(1)).slopeBound.value >= Field.unknownSlope)
        // Clamping both sides gives each a range again: 1 × slope(distance) + 5 × slope(linear).
        let clamped = Field.multiply(.clamp(distance, low: 0, high: 5), .clamp(.linearGradient(plane: .xy, length: 10), low: 0, high: 1))
        #expect(clamped.slopeBound.isKnown && abs(slope(clamped) - (1 + 5 * 0.1)) < 1e-12)
    }

    @Test func rangesFollowTheMaths() {
        let noise = Field.noise(seed: 1, scale: 8, octaves: 2)
        #expect(noise.valueRange == 0...1 && Field.constant(2).valueRange == 2...2)
        #expect(Field.distance(.point(.zero), signed: true).valueRange == nil)
        #expect(Field.add(noise, .constant(1)).valueRange == 1...2)
        #expect(Field.multiply(noise, .constant(-3)).valueRange == -3...0)
        #expect(Field.remap(noise, fromLow: 0, fromHigh: 1, toLow: 0.5, toHigh: 1.5, clamped: false).valueRange == 0.5...1.5)
        #expect(Field.remap(.distance(.point(.zero), signed: false), fromLow: 0, fromHigh: 1, toLow: 2, toHigh: 1, clamped: true)
            .valueRange == 1...2)
        #expect(Field.clamp(.distance(.point(.zero), signed: false), low: 1, high: 3).valueRange == 1...3)
        #expect(Field.minimum(noise, .constant(0.25)).valueRange == 0...0.25)
        #expect(Field.maximum(noise, .constant(0.25)).valueRange == 0.25...1)
        #expect(Field.smoothMinimum(noise, .constant(0.25), width: 1).valueRange == -0.25...0.25)
        #expect(Field.multiply(noise, .linearGradient(plane: .xy, length: 3)).valueRange == nil)
    }

    // MARK: the bound against the sampler

    func fields() throws -> [(String, Field)] {
        let image = try #require(Self.ramp)
        return [
            ("linear", .linearGradient(plane: .xy, length: 7)),
            ("radial", .radialGradient(center: Vector3(1, 2, 3), radius: 6)),
            ("distance", .distance(.point(Vector3(1, 2, 3)), signed: false)),
            ("noise 1", .noise(seed: 3, scale: 4, octaves: 1)),
            ("noise 3", .noise(seed: 9, scale: 2.5, octaves: 3)),
            ("image tile", .image(image, plane: .xy, width: 6, height: 5, edges: .tile)),
            ("image clamp", .image(image, plane: .xy, width: 6, height: 5, edges: .clamp)),
            ("implicit", .implicit(ImplicitReference(Ball(radius: 3)))),
            ("sum", .add(.noise(seed: 3, scale: 4, octaves: 2), .radialGradient(center: .zero, radius: 5))),
            ("product", .multiply(.noise(seed: 3, scale: 4, octaves: 2),
                                  .clamp(.radialGradient(center: .zero, radius: 5), low: 0, high: 2))),
            ("remap", .remap(.noise(seed: 5, scale: 3, octaves: 2), fromLow: 0.3, fromHigh: 0.7, toLow: 0.5, toHigh: 2, clamped: true)),
            ("smooth min", .smoothMinimum(.noise(seed: 5, scale: 3, octaves: 1), .linearGradient(plane: .xy, length: 9), width: 1)),
        ]
    }

    @Test func theBoundHoldsOnRandomPairs() async throws {
        let kernel = FakeKernel()
        for (name, field) in try fields() {
            let random = SeededRandom(seed: 11, stream: 5)
            let points = (0..<1500).map { Vector3(random.unit(at: 3 * $0) * 20 - 10, random.unit(at: 3 * $0 + 1) * 20 - 10,
                                                 random.unit(at: 3 * $0 + 2) * 20 - 10) }
            let nudged = points.enumerated().map { index, point in
                point + Vector3(random.unit(at: 5000 + 3 * index) - 0.5, random.unit(at: 5001 + 3 * index) - 0.5,
                                random.unit(at: 5002 + 3 * index) - 0.5) * 0.4
            }
            let (a, b) = (try await FieldSampler.sample(field, at: points, kernel: kernel),
                          try await FieldSampler.sample(field, at: nudged, kernel: kernel))
            var worst = 0.0
            for index in points.indices {
                let gap = (points[index] - nudged[index]).length
                if gap > 1e-9 { worst = max(worst, abs(a[index] - b[index]) / gap) }
            }
            #expect(worst <= field.slopeBound.value + 1e-9, "\(name): measured \(worst) against \(field.slopeBound.value)")
        }
    }

    @Test func rangesContainTheSamples() async throws {
        let kernel = FakeKernel()
        let random = SeededRandom(seed: 12, stream: 5)
        let points = (0..<2000).map { Vector3(random.unit(at: 3 * $0) * 30 - 15, random.unit(at: 3 * $0 + 1) * 30 - 15,
                                             random.unit(at: 3 * $0 + 2) * 30 - 15) }
        for (name, field) in try fields() {
            guard let range = field.valueRange else { continue }
            let values = try await FieldSampler.sample(field, at: points, kernel: kernel)
            #expect(values.allSatisfy { range.contains($0) }, "\(name): \(values.min() ?? 0)...\(values.max() ?? 0) outside \(range)")
        }
    }
}
