import CreatorGeometry
import Foundation
import Testing
@testable import CreatorNodes

/// Fields spec §3.1 and §8: the noise is pinned to fixed numbers (as `SeededRandomTests`), stays in 0…1, is smooth, and a value
/// never depends on the other points sampled with it.
struct FieldNoiseTests {
    static let points = [Vector3(1, 2, 3), Vector3(-4.5, 0.25, 7), Vector3(10, 10, 10), Vector3(0.1, 0.2, 0.3), Vector3(33, -21, 5)]

    func close(_ a: [Double], _ b: [Double], tolerance: Double = 1e-12) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    // MARK: the purposes

    func ascii(_ value: UInt64) -> String {
        String(bytes: (0..<8).map { UInt8((value >> UInt64(56 - 8 * $0)) & 0xFF) }, encoding: .ascii) ?? ""
    }

    @Test func theNewPurposesAreNamedAfterTheirNodes() {
        let (noise, cull) = (SeededRandom.Purpose.fieldNoise.rawValue, SeededRandom.Purpose.fieldCull.rawValue)
        #expect(noise == 0x464E_6F69_7365_5F31 && ascii(noise) == "FNoise_1")
        #expect(cull == 0x4643_756C_6C5F_5F31 && ascii(cull) == "FCull__1")
    }

    @Test(arguments: [
        (SeededRandom.Purpose.fieldNoise, [0xE252_309A_038E_6AE1, 0xA8D4_134C_CE10_A658, 0xF392_E67A_A1F8_F994]),
        (.fieldCull, [0xF097_D3AF_58C3_BD40, 0xA61B_D3B0_5954_6630, 0xE25B_A44C_9FE6_F27A]),
    ] as [(SeededRandom.Purpose, [UInt64])])
    func eachNewPurposeHasItsOwnPinnedNumbers(purpose: SeededRandom.Purpose, expected: [UInt64]) {
        let random = SeededRandom(seed: 42, purpose: purpose)
        #expect((0..<3).map { random.value(at: $0) } == expected)
    }

    @Test func equalSeedsOnDifferentPurposesStillDrawDifferentNumbers() {
        for seed in -20..<50 {
            let all: [SeededRandom.Purpose] = [.plain, .reduce, .values, .jitter, .fieldNoise, .fieldCull]
            #expect(Set(all.map { SeededRandom(seed: seed, purpose: $0).value(at: 0) }).count == all.count, "seed \(seed)")
        }
    }

    // MARK: pinned values

    @Test func theNoiseIsPinnedToFixedNumbers() {
        let one = FieldNoise(seed: 42, scale: 10, octaves: 1)
        #expect(close(Self.points.map { one.value(at: $0) },
                      [0.4825604, 0.10436887369602482, 0.5, 0.5205431403229187, 0.21333028806584342]))
        let three = FieldNoise(seed: 7, scale: 4, octaves: 3)
        #expect(close(Self.points.map { three.value(at: $0) },
                      [0.5499755952380952, 0.2662216308763594, 0.5, 0.39366352874888383, 0.5052696520429169]))
        let zero = FieldNoise(seed: 0, scale: 10, octaves: 1)
        #expect(close(Self.points.map { zero.value(at: $0) },
                      [0.529907184, 0.5984188810295815, 0.5, 0.47945685967708135, 0.5130305349794241]))
    }

    @Test func theOriginIsExactlyHalfForEverySeedAndOctaveCount() {
        for seed in [-5, 0, 42, 1_000_003] {
            for octaves in 1...6 {
                #expect(FieldNoise(seed: seed, scale: 7.5, octaves: octaves).value(at: .zero) == 0.5)
            }
        }
    }

    // MARK: properties

    @Test func valuesStayInZeroToOneAndUseMostOfIt() {
        let noise = FieldNoise(seed: 3, scale: 5, octaves: 2)
        var low = 1.0, high = 0.0, sum = 0.0
        let count = 20_000
        for i in 0..<count {
            let point = Vector3(Double(i % 41) * 0.77 - 15, Double(i % 53) * 0.61 - 12, Double(i % 29) * 1.3 - 9)
            let value = noise.value(at: point)
            #expect((0.0...1.0).contains(value))
            low = min(low, value)
            high = max(high, value)
            sum += value
        }
        #expect(low < 0.1 && high > 0.9, "got \(low)…\(high)")
        #expect(abs(sum / Double(count) - 0.5) < 0.05)
    }

    @Test func nearbyPointsHaveNearbyValues() {
        let noise = FieldNoise(seed: 3, scale: 5, octaves: 2)
        var worst = 0.0
        for i in 0..<3000 {
            let point = Vector3(Double(i % 41) * 0.77 - 15, Double(i % 53) * 0.61 - 12, Double(i % 29) * 1.3 - 9)
            worst = max(worst, abs(noise.value(at: point) - noise.value(at: point + Vector3(0.01, 0.01, 0.01))))
        }
        #expect(worst < 0.02, "a 0.017 mm step moved the value by \(worst)")
    }

    @Test func scalingThePointsAndTheScaleTogetherGivesTheSameNumbers() {
        let small = FieldNoise(seed: 3, scale: 10, octaves: 3), large = FieldNoise(seed: 3, scale: 20, octaves: 3)
        for i in 0..<1000 {
            let point = Vector3(Double(i) * 0.37, Double(i % 17), Double(i % 5))
            #expect(small.value(at: point) == large.value(at: point * 2))
        }
    }

    @Test func anotherSeedGivesAnotherFieldAndTheSameSeedTheSameOne() {
        let a = FieldNoise(seed: 3, scale: 10, octaves: 3), b = FieldNoise(seed: 4, scale: 10, octaves: 3)
        let again = FieldNoise(seed: 3, scale: 10, octaves: 3)
        for i in 0..<200 {
            let point = Vector3(Double(i) * 0.37 + 0.1, Double(i % 17) + 0.2, Double(i % 5) + 0.3)
            #expect(a.value(at: point) != b.value(at: point))
            #expect(a.value(at: point) == again.value(at: point))
        }
    }

    @Test func moreOctavesAddDetailWithoutLeavingTheRange() {
        let one = FieldNoise(seed: 9, scale: 8, octaves: 1), six = FieldNoise(seed: 9, scale: 8, octaves: 6)
        let points = (0..<500).map { Vector3(Double($0) * 0.41, Double($0 % 13) * 1.7, Double($0 % 7)) }
        #expect(points.contains { one.value(at: $0) != six.value(at: $0) })
        #expect(points.allSatisfy { (0.0...1.0).contains(six.value(at: $0)) })
    }

    @Test func hugeAndOddCoordinatesNeverTrap() {
        let noise = FieldNoise(seed: 1, scale: 0.001, octaves: 6)
        for point in [Vector3(1e300, 0, 0), Vector3(-1e300, 1e300, -1e300), Vector3(1e15, 1e15, 1e15), Vector3(.infinity, 0, 0)] {
            let value = noise.value(at: point)
            if point.x.isFinite, point.y.isFinite, point.z.isFinite {
                #expect(value.isFinite && (0.0...1.0).contains(value), "\(point)")
            } else {
                #expect(value.isNaN || (0.0...1.0).contains(value), "\(point)")
            }
        }
    }
}
