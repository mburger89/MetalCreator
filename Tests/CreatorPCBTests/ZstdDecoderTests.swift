import Foundation
import Testing
@testable import CreatorPCB

struct ZstdDecoderTests {
    private static let megabyte = 1 << 20

    private func frame(_ text: String) -> Data {
        Base64.decode(text[...].utf8, limit: 1 << 24) ?? Data()
    }

    private func decode(_ data: Data, limit: Int = 64 * megabyte) throws -> Data {
        try ZstdDecoder.decode(data, limit: limit, isCancelled: { false })
    }

    private func problem(_ data: Data, limit: Int = 64 * megabyte) -> ZstdProblem? {
        do {
            _ = try decode(data, limit: limit)
            return nil
        } catch {
            return error as? ZstdProblem
        }
    }

    private var fixtures: [(name: String, frame: Data, plain: [UInt8])] {
        [
            ("tiny", frame(ZstdFixtures.tiny), ZstdFixtureInputs.tiny),
            ("repetitive", frame(ZstdFixtures.repetitive), ZstdFixtureInputs.repetitive),
            ("text1", frame(ZstdFixtures.text1), ZstdFixtureInputs.text(seed: 1, size: 20_000)),
            ("nocheck", frame(ZstdFixtures.nocheck), ZstdFixtureInputs.text(seed: 1, size: 20_000)),
            ("fast", frame(ZstdFixtures.fast), ZstdFixtureInputs.text(seed: 1, size: 20_000)),
            ("same", frame(ZstdFixtures.same), ZstdFixtureInputs.same(0x41, count: 200_000)),
            ("samestdin", frame(ZstdFixtures.samestdin), ZstdFixtureInputs.same(0x41, count: 200_000)),
            ("empty", frame(ZstdFixtures.empty), []),
            ("small", frame(ZstdFixtures.small), ZstdFixtureInputs.text(seed: 9, size: 3_000)),
            ("onestream", frame(ZstdFixtures.onestream), ZstdFixtureInputs.mixed(seed: 0, size: 160)),
            ("fourstream", frame(ZstdFixtures.fourstream), ZstdFixtureInputs.mixed(seed: 0, size: 400)),
            ("rleoffsets", frame(ZstdFixtures.rleoffsets), ZstdFixtureInputs.text(seed: 28, size: 300)),
            ("repeatmix", frame(ZstdFixtures.repeatmix), ZstdFixtureInputs.mixed(seed: 0, size: 1_200)),
            ("direct", frame(ZstdFixtures.direct), Array(frame(ZstdFixtures.directPlain))),
            ("mixed300", frame(ZstdFixtures.mixed300), ZstdFixtureInputs.mixed(seed: 2, size: 300_000)),
            ("mixed120", frame(ZstdFixtures.mixed120), ZstdFixtureInputs.mixed(seed: 3, size: 120_000)),
        ]
    }

    @Test func fixturesDecodeByteExact() throws {
        for fixture in fixtures {
            #expect(!fixture.frame.isEmpty, "\(fixture.name) fixture is damaged")
            #expect(try decode(fixture.frame) == Data(fixture.plain), "\(fixture.name)")
        }
    }

    @Test func craftedRunLengthAndRawFrames() throws {
        let rle = Data([0x28, 0xB5, 0x2F, 0xFD, 0x20, 100, 0x23, 0x03, 0x00, 0x7A])
        #expect(try decode(rle) == Data(repeating: 0x7A, count: 100))
        let raw = Data([0x28, 0xB5, 0x2F, 0xFD, 0x20, 3, 0x19, 0x00, 0x00, 1, 2, 3])
        #expect(try decode(raw) == Data([1, 2, 3]))
    }

    @Test func aRunLengthLiteralsSectionWithNoSequences() throws {
        // Compressed block: literals of kind 1 (ten copies of "Q"), then a sequence count of 0.
        let bytes = Data([0x28, 0xB5, 0x2F, 0xFD, 0x20, 10, 0x1D, 0x00, 0x00, 0x51, 0x51, 0x00])
        #expect(try decode(bytes) == Data(repeating: 0x51, count: 10))
    }

    @Test func skippableFramesBeforeTheFrameAreSkipped() throws {
        let skippable = Data([0x5A, 0x2A, 0x4D, 0x18, 3, 0, 0, 0, 9, 9, 9])
        let tiny = frame(ZstdFixtures.tiny)
        #expect(try decode(skippable + skippable + tiny) == Data(ZstdFixtureInputs.tiny))
        #expect(problem(skippable) == .damaged)
        #expect(problem(tiny + skippable) == .damaged)
        #expect(problem(tiny + tiny) == .damaged)
    }

    @Test func checksumMismatchIsDamaged() {
        var bytes = frame(ZstdFixtures.tiny)
        bytes[bytes.count - 1] ^= 0x01
        #expect(problem(bytes) == .damaged)
        var noCheck = frame(ZstdFixtures.nocheck)
        noCheck[noCheck.count - 1] ^= 0x01
        #expect(problem(noCheck) != nil || (try? decode(noCheck)) != nil)
    }

    @Test func dictionaryIsRefused() {
        let withDictionary = Data([0x28, 0xB5, 0x2F, 0xFD, 0x21, 5, 0x00, 0x01, 0x00, 0x00])
        #expect(problem(withDictionary) == .dictionary)
        #expect(ZstdProblem.dictionary.message == "The stored model uses a zstd dictionary, which isn't supported.")
    }

    @Test func statedSizeOverTheLimitIsRefusedBeforeDecoding() {
        // Single segment, an eight-byte content size of 1 GB, then nothing.
        var header = Data([0x28, 0xB5, 0x2F, 0xFD, 0xE0])
        header.append(contentsOf: withUnsafeBytes(of: UInt64(1 << 30).littleEndian) { Array($0) })
        #expect(problem(header, limit: 1024) == .larger(than: 1024))
        var huge = Data([0x28, 0xB5, 0x2F, 0xFD, 0xE0])
        huge.append(contentsOf: withUnsafeBytes(of: UInt64(1 << 60).littleEndian) { Array($0) })
        #expect(problem(huge, limit: 256 << 20) == .larger(than: 256 << 20))
        #expect(ZstdProblem.larger(than: 256 << 20).message == "The stored model is larger than 256 MB.")
    }

    @Test func unknownSizeStopsAtTheLimit() throws {
        let frame = frame(ZstdFixtures.samestdin)
        #expect(problem(frame, limit: 100_000) == .larger(than: 100_000))
        #expect(try decode(frame, limit: 200_000).count == 200_000)
        #expect(problem(frame, limit: 199_999) == .larger(than: 199_999))
    }

    @Test func blockAndOffsetLimitsFollowTheWindow() {
        // Window descriptor 0x00: 1 KB. A raw block of 2,000 bytes is larger than the window.
        var big = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00, 0x81, 0x3E, 0x00])
        big.append(Data(repeating: 1, count: 2000))
        #expect(problem(big) == .damaged)
        var small = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00, 0x19, 0x00, 0x00, 1, 2, 3])
        #expect((try? decode(small)) == Data([1, 2, 3]))
        small.removeLast()
        #expect(problem(small) == .damaged)
    }

    @Test func aHugeLimitCannotOverflow() throws {
        #expect(try decode(frame(ZstdFixtures.tiny), limit: Int.max) == Data(ZstdFixtureInputs.tiny))
        #expect(problem(frame(ZstdFixtures.samestdin), limit: Int.max - 5) == nil)
    }

    @Test func aHugeWindowIsRefused() {
        // Window descriptor 0xF0: exponent 30, so a window of 2^40.
        let bytes = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0xF0, 0x01, 0x00, 0x00])
        #expect(problem(bytes) == .window)
    }

    @Test func cancellationIsAskedPerBlock() {
        var asked = 0
        let frame = frame(ZstdFixtures.mixed300)
        #expect(throws: CancellationError.self) {
            try ZstdDecoder.decode(frame, limit: 1 << 24, isCancelled: {
                asked += 1
                return asked > 1
            })
        }
        #expect(asked == 2)
    }

    @Test func everyTruncationAndBitFlipOfASmallFrameGivesTheTextOrAProblem() throws {
        let original = frame(ZstdFixtures.small)
        let plain = Data(ZstdFixtureInputs.text(seed: 9, size: 3_000))
        let start = ContinuousClock.now
        func check(_ mutated: Data) {
            do {
                let result = try ZstdDecoder.decode(mutated, limit: 1 << 20, isCancelled: { false })
                #expect(result == plain)
            } catch {
                #expect(error is ZstdProblem)
            }
        }
        for length in 0..<original.count { check(original.prefix(length)) }
        for index in 0..<original.count {
            for bit in 0..<8 {
                var mutated = original
                mutated[index] ^= 1 << UInt8(bit)
                check(mutated)
            }
        }
        #expect(start.duration(to: .now) < .seconds(10))
    }

    @Test func seededFuzzNeverTraps() {
        var generator = ZstdFixtureInputs.Generator(state: 77)
        let originals = [frame(ZstdFixtures.small), frame(ZstdFixtures.repetitive), frame(ZstdFixtures.tiny)]
        for caseIndex in 0..<2_000 {
            var bytes: [UInt8]
            if caseIndex % 2 == 0 {
                bytes = [0x28, 0xB5, 0x2F, 0xFD] + (0..<generator.below(300)).map { _ in UInt8(truncatingIfNeeded: generator.next()) }
            } else {
                bytes = Array(originals[caseIndex % 3])
                for _ in 0..<1 + generator.below(6) where !bytes.isEmpty {
                    bytes[generator.below(bytes.count)] = UInt8(truncatingIfNeeded: generator.next())
                }
            }
            do {
                _ = try ZstdDecoder.decode(Data(bytes), limit: 1 << 20, isCancelled: { false })
            } catch {
                #expect(error is ZstdProblem)
            }
        }
    }

    @Test func defaultDistributionsAreWholeTables() throws {
        #expect(ZstdSequenceTables.predefinedLiteralLengths.entries.count == 64)
        #expect(ZstdSequenceTables.predefinedMatchLengths.entries.count == 64)
        #expect(ZstdSequenceTables.predefinedOffsets.entries.count == 32)
    }
}
