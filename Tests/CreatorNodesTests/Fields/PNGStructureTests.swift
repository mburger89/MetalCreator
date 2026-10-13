import Foundation
import Testing
@testable import CreatorNodes

/// `PNGStructure`: ImageIO decodes a PNG cut short as a black picture without complaint, so completeness is checked here.
struct PNGStructureTests {
    @Test func aWholePNGPasses() {
        let png = TestImages.noisy(32)
        #expect(PNGStructure.isWhole(png))
        #expect(PNGStructure.isWhole(png + Data(repeating: 7, count: 50)), "bytes after IEND are ignored")
    }

    @Test func aPNGCutAnywhereBeforeItsEndFails() {
        let png = TestImages.noisy(32)
        for length in [0, 7, 8, 20, 33, png.count / 2, png.count - 13, png.count - 1] {
            #expect(!PNGStructure.isWhole(png.prefix(length)), "cut to \(length) of \(png.count) bytes")
        }
    }

    @Test func notAPNGFailsAndAHugeChunkLengthCannotTrap() {
        #expect(!PNGStructure.isWhole(Data("hello, this is not a picture at all".utf8)))
        var forged = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFF, 0xFF, 0xFF])
        forged.append(Data("IDAT".utf8))
        forged.append(Data(count: 8))
        #expect(!PNGStructure.isWhole(forged), "a length of 4 GB runs past the data")
    }
}
