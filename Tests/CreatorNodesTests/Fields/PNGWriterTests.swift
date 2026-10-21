import Foundation
import MetalUI
import Testing
@testable import CreatorNodes

/// `PNGWriter`, the test fixtures' own PNG encoder for platforms without CoreGraphics: its chunks are the standard ones, and
/// MetalUI's decoder reads what it writes.
struct PNGWriterTests {
    @Test func theCRCOfTheStandardCheckStringIsTheStandardOne() {
        #expect(PNGWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func anEmptyChunkNamedIENDIsTheEndOfEveryPNG() {
        #expect([UInt8](PNGWriter.chunk("IEND", [])) == [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }

    @Test func aWrittenPictureIsWholeAndSaysItsSize() {
        let png = PNGWriter.encode(width: 5, height: 3, color: .grey) { x, y in [UInt8(x * 10 + y)] }
        #expect(PNGStructure.isWhole(png))
        #expect([UInt8](png[16..<24]) == [0, 0, 0, 5, 0, 0, 0, 3], "IHDR's width and height")
    }

    @Test func aPictureOfMoreThanOneStoredBlockIsStillWhole() {
        let png = PNGWriter.encode(width: 300, height: 300, color: .grey) { _, _ in [7] }
        #expect(png.count > 90_000, "300 rows of 301 bytes do not fit one 65,535-byte stored block")
        #expect(PNGStructure.isWhole(png))
    }

    @Test func aSixteenBitPictureAndAnOrientationTagAreWholeAndSaySo() throws {
        let png = PNGWriter.encode(width: 3, height: 2, color: .grey16, orientation: 6) { x, _ in [UInt8(x), 0xFF] }
        #expect(PNGStructure.isWhole(png))
        let info = try #require(ImageInfo(data: png))
        #expect(info.format == .png && info.width == 3 && info.height == 2 && info.orientation.exifValue == 6)
    }

    @Test func theDecoderReadsWhatTheWriterWrote() async throws {
        let grey = PNGWriter.encode(width: 4, height: 2, color: .grey) { x, y in [UInt8(x * 60 + y * 10)] }
        #expect(try await GreyImageDecoder.decode(grey).pixels == [0, 60, 120, 180, 10, 70, 130, 190].map { $0 * 257 })
        let colour = PNGWriter.encode(width: 2, height: 1, color: .rgba) { x, _ in x == 0 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        let image = try await GreyImageDecoder.decode(colour)
        #expect(image.width == 2 && image.height == 1)
        #expect(image.pixels[0] == 65_535 && image.pixels[1] == 0)
    }
}
