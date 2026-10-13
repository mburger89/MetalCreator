import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// Fields spec §2.2 and §8: every source and maths node against hand-worked values; a batch equals point by point exactly.
struct FieldSamplerTests {
    let kernel = FakeKernel()
    let tag = NodeTag(node: NodeID(), item: 0)

    func sample(_ field: Field, _ points: [Vector3]) async throws -> [Double] {
        try await FieldSampler.sample(field, at: points, kernel: kernel)
    }

    func at(_ field: Field, _ point: Vector3) async throws -> Double {
        try await sample(field, [point])[0]
    }

    /// A 10 mm cube standing on z = 0, centred on x and y.
    func cube() async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    // MARK: sources

    @Test func aConstantIsTheSameEverywhere() async throws {
        #expect(try await sample(.constant(2.5), [.zero, Vector3(1, 2, 3), Vector3(-9, 9, 0)]) == [2.5, 2.5, 2.5])
    }

    @Test func aLinearGradientIsTheSignedDistanceAlongTheNormalOverTheLength() async throws {
        let field = Field.linearGradient(plane: Plane.xy.offset(by: 2), length: 5)
        #expect(try await sample(field, [Vector3(9, 9, 2), Vector3(0, 0, 7), Vector3(1, 1, -3), Vector3(0, 0, 12)]) == [0, 1, -1, 2])
    }

    @Test func aGradientPlaneWithALongNormalIsTreatedAsUnit() async throws {
        let plane = Plane(origin: .zero, normal: Vector3(0, 0, 2), xAxis: .unitX)
        #expect(try await at(.linearGradient(plane: plane, length: 4), Vector3(0, 0, 6)) == 1.5)
    }

    @Test func aRadialGradientIsTheDistanceFromTheCentreOverTheRadius() async throws {
        let field = Field.radialGradient(center: Vector3(1, 1, 1), radius: 2)
        #expect(try await sample(field, [Vector3(1, 1, 1), Vector3(1, 1, 3), Vector3(3, 1, 1), Vector3(1, 1, -3)]) == [0, 1, 1, 2])
    }

    @Test func aPointDistanceIsPlainDistance() async throws {
        let field = Field.distance(.point(Vector3(1, 2, 3)), signed: false)
        #expect(try await sample(field, [Vector3(1, 2, 3), Vector3(4, 6, 3), Vector3(1, 2, -2)]) == [0, 5, 5])
    }

    @Test func aProfileDistanceIsToItsLoopsInThreeD() async throws {
        let field = Field.distance(.profile(.rectangle(width: 10, height: 10, plane: .xy)), signed: false)
        let found = try await sample(field, [Vector3(0, 0, 0), Vector3(8, 0, 3)])
        #expect(found[0] == 5 && abs(found[1] - 18.0.squareRoot()) < 1e-12)
    }

    @Test func aSolidDistanceIsSignedAndAsksTheKernelOnce() async throws {
        let solid = try await cube()
        await kernel.clearLog()
        let points = [Vector3(0, 0, 5), Vector3(8, 0, 5), Vector3(5, 0, 5)]
        let found = try await sample(.distance(.kernel(.solid(solid)), signed: true), points)
        #expect(found == [-5, 3, 0])
        #expect(await kernel.operationLog == ["distances"], "one call for the whole batch")
        let unsigned = try await sample(.distance(.kernel(.solid(solid)), signed: false), [Vector3(0, 0, 5)])
        #expect(unsigned == [5])
    }

    @Test func anEdgeDistanceMeasuresToTheEdges() async throws {
        let solid = try await cube()
        let field = Field.distance(.kernel(.edges(EdgeSet(solid: solid, edges: [EdgeID(0)]))), signed: false)
        #expect(try await sample(field, [Vector3(0, -8, 4)]) == [5])
    }

    @Test func noiseIsTheNoiseTypeAtEachPoint() async throws {
        let points = [Vector3(1, 2, 3), Vector3(-4.5, 0.25, 7), Vector3(10, 10, 10)]
        let found = try await sample(.noise(seed: 42, scale: 10, octaves: 1), points)
        let noise = FieldNoise(seed: 42, scale: 10, octaves: 1)
        #expect(found == points.map { noise.value(at: $0) })
    }

    // MARK: maths

    @Test func addMultiplyMinimumAndMaximumAreElementwise() async throws {
        let x = Field.linearGradient(plane: Plane.yz, length: 1)  // the x coordinate
        let points = [Vector3(1, 0, 0), Vector3(-2, 0, 0), Vector3(4, 0, 0)]
        #expect(try await sample(.add(x, .constant(10)), points) == [11, 8, 14])
        #expect(try await sample(.multiply(x, .constant(0.5)), points) == [0.5, -1, 2])
        #expect(try await sample(.minimum(x, .constant(0)), points) == [0, -2, 0])
        #expect(try await sample(.maximum(x, .constant(0)), points) == [1, 0, 4])
    }

    @Test func remapMapsTheRangeAndClampsToTheOutputRange() async throws {
        let x = Field.linearGradient(plane: Plane.yz, length: 1)
        let points = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0), Vector3(-10, 0, 0)]
        let clamped = Field.remap(x, fromLow: 0, fromHigh: 20, toLow: 1, toHigh: 0, clamped: true)
        #expect(try await sample(clamped, points) == [1, 0.5, 0, 0, 1])
        let free = Field.remap(x, fromLow: 0, fromHigh: 20, toLow: 1, toHigh: 0, clamped: false)
        #expect(try await sample(free, points) == [1, 0.5, 0, -0.5, 1.5])
        let rising = Field.remap(x, fromLow: 0, fromHigh: 20, toLow: 5, toHigh: 15, clamped: true)
        #expect(try await sample(rising, points) == [5, 10, 15, 15, 5])
    }

    @Test func aRemapWithAnEmptyFromRangeIsTheLowEndRatherThanNaN() async throws {
        let field = Field.remap(.constant(3), fromLow: 2, fromHigh: 2, toLow: 7, toHigh: 9, clamped: true)
        #expect(try await at(field, .zero) == 7)
    }

    @Test func clampHoldsAFieldBetweenItsBounds() async throws {
        let x = Field.linearGradient(plane: Plane.yz, length: 1)
        #expect(try await sample(.clamp(x, low: -1, high: 2), [Vector3(-5, 0, 0), Vector3(0.5, 0, 0), Vector3(9, 0, 0)]) == [-1, 0.5, 2])
    }

    @Test func aSmoothMinimumBlendsWithinTheWidthAndIsThePlainMinimumBeyondIt() async throws {
        func blend(_ a: Double, _ b: Double, _ width: Double) async throws -> Double {
            try await at(.smoothMinimum(.constant(a), .constant(b), width: width), .zero)
        }
        #expect(try await blend(0, 0, 2) == -0.5, "equal inputs dip by a quarter of the width")
        #expect(try await blend(0, 1, 2) == -0.125, "a half-width apart: 0 − 0.5² × 2 ÷ 4")
        #expect(try await blend(0, 2, 2) == 0, "as far apart as the width: the plain minimum")
    }

    @Test func aSmoothMinimumIsSymmetricAndFallsBackToMinimum() async throws {
        let a = Field.constant(1.25), b = Field.constant(2)
        #expect(try await at(.smoothMinimum(a, b, width: 3), .zero) == at(.smoothMinimum(b, a, width: 3), .zero))
        #expect(try await at(.smoothMinimum(a, b, width: 0), .zero) == 1.25, "width 0 is the plain minimum")
        #expect(try await at(.smoothMinimum(a, b, width: 0.5), .zero) == 1.25, "inputs further apart than the width")
        let blended = try await at(.smoothMinimum(a, b, width: 3), .zero)
        #expect(blended < 1.25 && blended > 1.25 - 3 / 4)
    }

    // MARK: determinism and batching (§2.2)

    /// A field using every kind of leaf and every maths node.
    func everything() async throws -> Field {
        let solid = try await cube()
        let distance = Field.distance(.kernel(.solid(solid)), signed: true)
        let edge = Field.distance(.kernel(.edges(EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(8)]))), signed: false)
        let profile = Field.distance(.profile(.circle(radius: 4, center: Vector2(1, 1), plane: .xy)), signed: false)
        let noise = Field.noise(seed: 11, scale: 6, octaves: 3)
        let blend = Field.smoothMinimum(.remap(distance, fromLow: -5, fromHigh: 15, toLow: 1, toHigh: 0, clamped: true), noise, width: 0.3)
        let gradients = Field.add(.linearGradient(plane: .xz, length: 7), .radialGradient(center: Vector3(1, 2, 3), radius: 9))
        return .clamp(.maximum(.multiply(blend, gradients), .minimum(edge, profile)), low: -3, high: 8)
    }

    func scatter(_ count: Int) -> [Vector3] {
        (0..<count).map { Vector3(Double($0 % 37) * 0.9 - 16, Double($0 % 23) * 1.1 - 12, Double($0 % 17) * 0.8 - 3) }
    }

    @Test func aBatchEqualsPointByPointExactly() async throws {
        let field = try await everything()
        let points = scatter(2600)  // three chunks
        let batch = try await sample(field, points)
        #expect(batch.count == 2600)
        for index in stride(from: 0, to: points.count, by: 37) {
            #expect(try await at(field, points[index]) == batch[index], "point \(index)")
        }
        #expect(try await at(field, points[2599]) == batch[2599])
    }

    @Test func aLongerPointListChangesNoEarlierSample() async throws {
        let field = try await everything()
        let short = try await sample(field, scatter(1500))
        let long = try await sample(field, scatter(3100))
        #expect(Array(long.prefix(1500)) == short)
    }

    @Test func theSameFieldAndPointsGiveTheSameNumbersEveryTime() async throws {
        let field = try await everything()
        let first = try await sample(field, scatter(1300))
        let second = try await sample(field, scatter(1300))
        #expect(first == second)
        #expect(first.allSatisfy { $0.isFinite })
    }

    @Test func noPointsGiveNoNumbersAndNoKernelCall() async throws {
        let field = try await everything()
        await kernel.clearLog()
        #expect(try await sample(field, []).isEmpty)
        #expect(await kernel.operationLog.isEmpty)
    }

    // MARK: the kernel and the cache

    @Test func eachDistanceLeafMakesOneKernelCallAndACacheSharesThem() async throws {
        let solid = try await cube()
        let leaf = Field.distance(.kernel(.solid(solid)), signed: true)
        let twice = Field.add(leaf, leaf)
        await kernel.clearLog()
        _ = try await FieldSampler.sample(twice, at: scatter(50), kernel: kernel)
        #expect(await kernel.operationLog == ["distances", "distances"], "no cache: one call per leaf")
        await kernel.clearLog()
        let cache = FieldDistanceCache()
        _ = try await FieldSampler.sample(twice, at: scatter(50), kernel: kernel, cache: cache)
        _ = try await FieldSampler.sample(twice, at: scatter(50), kernel: kernel, cache: cache)
        #expect(await kernel.operationLog == ["distances"], "one call for both leaves and both samplings")
        #expect(await cache.hits == 3)
    }

    @Test func aKernelRefusalPassesThroughWithItsOwnMessage() async throws {
        let solid = try await cube()
        let field = Field.distance(.kernel(.faces(FaceSet(solid: solid, faces: [FaceID(99)]))), signed: false)
        await #expect(throws: KernelError.invalidInput("A selected face doesn't exist on the solid.")) {
            try await sample(field, [.zero])
        }
    }

    // MARK: cancellation

    @Test func aCancelledSamplingStopsWithCancellationError() async throws {
        let field = try await everything()
        let points = scatter(5000)
        let sampler = kernel
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FieldSampler.sample(field, at: points, kernel: sampler)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Runs `loop`, whose transform calls the `tick` it is given once per point, on a task that the first tick cancels. Gives the
    /// points the loop reached and whether it stopped with `CancellationError`.
    func cancelledOnFirstPoint(_ loop: @escaping @Sendable (_ tick: () -> Void) throws -> Void) async -> (reached: Int, cancelled: Bool) {
        await Task {
            var reached = 0
            do {
                try loop {
                    reached += 1
                    if reached == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            } catch is CancellationError {
                return (reached, true)
            } catch {
                return (reached, false)
            }
            return (reached, false)
        }.value
    }

    /// The spec's per-chunk check (§2.2): 3,000 points are three chunks, and the transform cancels the task on the first point of
    /// the first, so a loop that checks between chunks has reached exactly 1,024 points when it stops. A loop with no check
    /// would reach all 3,000 and return.
    @Test func everyLoopStopsBetweenChunksWhenCancelled() async throws {
        let points = scatter(3000)
        let numbers = (0..<3000).map(Double.init)
        let overPoints = await cancelledOnFirstPoint { tick in _ = try FieldSampler.map(points) { _ in tick(); return 0 } }
        let overNumbers = await cancelledOnFirstPoint { tick in _ = try FieldSampler.map(numbers) { _ in tick(); return 0 } }
        let overPairs = await cancelledOnFirstPoint { tick in _ = try FieldSampler.combine(numbers, numbers) { _, _ in tick(); return 0 } }
        for (name, outcome) in [("points", overPoints), ("numbers", overNumbers), ("pairs", overPairs)] {
            #expect(outcome.cancelled, "the loop over \(name) noticed")
            #expect(outcome.reached == FieldSampler.chunkSize, "the loop over \(name) stopped after its first chunk: \(outcome.reached)")
        }
    }

    /// A batch that is cancelled after the kernel has answered (the kernel call is the only await in the walk) stops in the next
    /// loop, not at the end: the entry check has long passed.
    @Test func aSamplingCancelledInsideTheKernelStopsAtTheNextLoop() async throws {
        let solid = try await cube()
        let cancelling = CancellingDistanceKernel()
        let field = Field.add(.distance(.kernel(.solid(solid)), signed: true), .noise(seed: 1, scale: 5, octaves: 1))
        let points = scatter(3000)
        let task = Task { try await FieldSampler.sample(field, at: points, kernel: cancelling) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await cancelling.calls == 1, "the kernel was reached, so the stop came after it")
    }

    @Test func theChunkIsOneThousandAndTwentyFourPoints() {
        #expect(FieldSampler.chunkSize == 1024)
    }
}
