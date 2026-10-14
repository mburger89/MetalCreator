import CreatorGeometry
import Testing
@testable import CreatorNodes

/// The generator behind every random node (patterns spec §4: "the same seed gives the same result on every machine").
/// These numbers are pinned: if one changes, every saved file's random results change with it, so a failure here means the
/// algorithm was altered, not that the expectation is stale.
struct SeededRandomTests {
    /// SplitMix64's published test vector: seed 0 gives these four numbers first.
    @Test func seedZeroGivesSplitMix64sPublishedSequence() {
        var random = SeededRandom(seed: 0)
        #expect([random.next(), random.next(), random.next(), random.next()]
            == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC])
    }

    @Test(arguments: [
        (1, [0x910A_2DEC_8902_5CC1, 0xBEEB_8DA1_658E_EC67, 0xF893_A2EE_FB32_555E]),
        (42, [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103, 0x4752_6757_130F_9F52]),
        (-1, [0xE4D9_7177_1B65_2C20, 0xE99F_F867_DBF6_82C9, 0x382F_F84C_B272_81E9]),
    ] as [(Int, [UInt64])])
    func fixedSeedsGiveFixedNumbers(seed: Int, expected: [UInt64]) {
        var random = SeededRandom(seed: seed)
        #expect(expected.map { _ in random.next() } == expected)
    }

    @Test func streamsAreIndependentRunsOfTheSameSeed() {
        var first = SeededRandom(seed: 42, stream: 1)
        var second = SeededRandom(seed: 42, stream: 2)
        #expect((0..<3).map { _ in first.next() } == [0x57E1_FABA_6510_7204, 0xF4AB_D143_FEB2_4055, 0x7C81_6738_C129_03B2])
        #expect((0..<3).map { _ in second.next() } == [0xFC99_1BCA_1A1A_A1AE, 0x4F04_82A7_2B57_EE7D, 0x81BA_563D_5522_8AB4])
        #expect(SeededRandom(seed: 42, stream: 0).value(at: 0) == SeededRandom(seed: 42).value(at: 0), "stream 0 is the seed itself")
    }

    @Test func anyDrawCanBeReachedDirectlyAndMatchesTheSequence() {
        var sequential = SeededRandom(seed: 7, stream: 3)
        let direct = SeededRandom(seed: 7, stream: 3)
        for index in 0..<20 {
            #expect(sequential.next() == direct.value(at: index))
        }
    }

    @Test func theSameSeedGivesTheSameNumbersWhenAskedAgain() {
        let a = SeededRandom(seed: 99), b = SeededRandom(seed: 99)
        #expect((0..<50).map { a.value(at: $0) } == (0..<50).map { b.value(at: $0) })
        #expect(SeededRandom(seed: 100).value(at: 0) != a.value(at: 0))
    }

    @Test func realsArePinnedAndInsideZeroToOne() {
        let random = SeededRandom(seed: 42)
        #expect((0..<4).map { random.unit(at: $0) } == [0.7415648787718233, 0.1599103928769201, 0.27860113025513866, 0.34419071652363753])
        #expect((0..<1000).allSatisfy { (0.0..<1.0).contains(random.unit(at: $0)) })
    }

    @Test func wholeNumbersArePinnedAndBelowTheBound() {
        let random = SeededRandom(seed: 42)
        #expect((0..<8).map { random.below(10, at: $0) } == [7, 1, 2, 3, 0, 8, 2, 8])
        #expect((0..<8).map { random.below(6, at: $0) } == [4, 0, 1, 2, 0, 5, 1, 4])
        #expect((0..<1000).allSatisfy { (0..<7).contains(random.below(7, at: $0)) })
        #expect(random.below(1, at: 5) == 0)
    }

    @Test func eachWholeNumberTurnsUpAboutAsOftenAsTheOthers() {
        let random = SeededRandom(seed: 5)
        var counts = [Int](repeating: 0, count: 6)
        for index in 0..<6000 { counts[random.below(6, at: index)] += 1 }
        #expect(counts.allSatisfy { (850...1150).contains($0) }, "got \(counts)")
    }

    // MARK: purposes

    /// The numbers each random node draws for seed 42, pinned: they are what makes equal seeds on different nodes independent.
    @Test(arguments: [
        (SeededRandom.Purpose.reduce, [0xED46_CB32_7858_9E11, 0x2E0B_23F3_B198_49ED, 0x4754_6584_6F85_B6A6]),
        (.values, [0xF9BB_CEF4_C416_28FE, 0xA58E_6243_02BB_490E, 0x2860_470B_EC01_3B99]),
        (.jitter, [0x9673_367E_075B_CECA, 0xEDD4_89D4_9837_C26E, 0xC753_6F39_C67C_D7BC]),
    ] as [(SeededRandom.Purpose, [UInt64])])
    func eachPurposeHasItsOwnPinnedNumbers(purpose: SeededRandom.Purpose, expected: [UInt64]) {
        let random = SeededRandom(seed: 42, purpose: purpose)
        #expect((0..<3).map { random.value(at: $0) } == expected)
    }

    @Test func thePlainPurposeIsTheBareGeneratorAndAStreamStillStartsFromThePurposesSeed() {
        #expect(SeededRandom(seed: 42, purpose: .plain).value(at: 0) == SeededRandom(seed: 42).value(at: 0))
        let second = SeededRandom(seed: 42, stream: 2, purpose: .values)
        #expect([second.value(at: 0), second.value(at: 1)] == [0x5CAC_DAA9_7C6F_B7CC, 0xF62B_5C3A_1A2A_CAAA])
    }

    @Test func equalSeedsOnDifferentPurposesDrawDifferentNumbers() {
        for seed in -20..<50 {
            let firsts = [SeededRandom.Purpose.plain, .reduce, .values, .jitter].map { SeededRandom(seed: seed, purpose: $0).value(at: 0) }
            #expect(Set(firsts).count == 4, "seed \(seed)")
        }
    }
}
