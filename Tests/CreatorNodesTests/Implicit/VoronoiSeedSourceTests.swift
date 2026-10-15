import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The built-in seeds of the Voronoi lattice: drawn from the new random purpose, the same for the same inputs, placed by the density.
struct VoronoiSeedSourceTests {
    static let box = BoundingBox(min: Vector3(-20, -20, -20), max: Vector3(20, 20, 20))

    func points(_ count: Int, density: Field = .constant(1), seed: Int = 0, in box: BoundingBox = Self.box) async throws
        -> VoronoiSeedSource.Result {
        try await VoronoiSeedSource.points(count: count, density: density, seed: seed, in: box, kernel: FakeKernel(),
                                           cache: FieldDistanceCache())
    }

    /// The numbers the Voronoi purpose draws for seed 42, pinned (worked out by an independent SplitMix64 in Python).
    @Test func theVoronoiPurposeHasItsOwnPinnedNumbers() {
        let random = SeededRandom(seed: 42, purpose: .voronoi)
        #expect((0..<3).map { random.value(at: $0) } == [0x7D23_E4F4_7933_A1A1, 0xB16C_A8E7_101B_45E3, 0x0A28_989E_1988_FF51])
        #expect(SeededRandom.Purpose.voronoi.rawValue == 0x566F_726F_6E6F_695F, "“Voronoi_” in ASCII")
        #expect(SeededRandom(seed: 42, purpose: .voronoi).value(at: 0) != SeededRandom(seed: 42, purpose: .scatter).value(at: 0))
    }

    @Test func theSeedsFillTheRegionAndAMarginAndAreTheFirstDrawsWhenTheDensityIsOne() async throws {
        let made = try await points(50)
        let area = VoronoiSeedSource.area(for: Self.box, count: 50)
        #expect(made.points.count == 50 && made.warnings.isEmpty)
        #expect(area.min.x < -20 && area.max.x > 20, "a margin of half the mean spacing")
        #expect(made.points.allSatisfy { $0.x >= area.min.x && $0.x <= area.max.x && $0.z >= area.min.z && $0.z <= area.max.z })
        let random = SeededRandom(seed: 0, purpose: .voronoi)
        let first = area.min + Vector3(area.size.x * random.unit(at: 0), area.size.y * random.unit(at: 1), area.size.z * random.unit(at: 2))
        #expect(made.points[0] == first)
    }

    @Test func theSameInputsGiveTheSameSeedsAndMoreSeedsKeepTheEarlierOnes() async throws {
        let a = try await points(40, seed: 3), b = try await points(40, seed: 3), other = try await points(40, seed: 4)
        #expect(a.points == b.points && a.points != other.points)
        let more = try await points(60, seed: 3)
        #expect(Array(more.points.prefix(40)) != a.points, "the margin grows with the count, so the box moves")
        let same = try await points(40, seed: 3, in: Self.box)
        #expect(same.points == a.points)
    }

    @Test func aDensityFieldKeepsSeedsWhereItIsHigh() async throws {
        // x / 40: negative for x < 0 (never kept), 1 for x ≥ 40 (always); half the box is empty of seeds.
        let ramp = Field.linearGradient(plane: Plane(origin: .zero, normal: .unitX, xAxis: .unitY), length: 40)
        let made = try await points(200, density: ramp)
        #expect(made.points.count == 200 && made.points.allSatisfy { $0.x >= 0 })
        let mean = made.points.reduce(0) { $0 + $1.x } / 200
        #expect(mean > 10, "weighted towards +x: \(mean)")
    }

    @Test func aDensityOfZeroIsRefusedAndAnAlmostZeroOneWarns() async throws {
        await #expect(throws: NodeError.invalidValue("The density is 0 everywhere in the region, so there are no seeds.")) {
            _ = try await points(10, density: .constant(0))
        }
        let sparse = try await points(100, density: .constant(0.001))
        #expect(sparse.points.count < 100 && !sparse.points.isEmpty)
        #expect(sparse.warnings == ["The density left room for only \(sparse.points.count) of the 100 seeds."])
    }

    @Test func aNotANumberDensityKeepsNothing() async throws {
        let nothing = Field.multiply(.constant(Double.nan), .constant(1))
        await #expect(throws: NodeError.self) { _ = try await points(10, density: nothing) }
    }
}
