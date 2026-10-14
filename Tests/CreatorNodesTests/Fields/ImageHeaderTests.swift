import Foundation
import Testing
@testable import CreatorNodes

/// `ImageHeader`: the size and orientation read from a picture's first bytes, before any pixel is decoded.
struct ImageHeaderTests {
    /// The `eXIf` chunk's bytes for orientation `tag`, as `PNGWriter` writes them.
    private func exif(_ tag: Int) -> Data {
        PNGWriter.chunk("eXIf", [0x4D, 0x4D, 0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, UInt8(tag), 0, 0, 0, 0, 0, 0])
    }

    /// A 2 × 1 grey PNG split into its chunks, so a test can put an `eXIf` chunk where it likes.
    private func chunks() -> [Data] {
        let png = PNGWriter.encode(width: 2, height: 1, color: .grey) { x, _ in [UInt8(x)] }
        var result: [Data] = [], offset = 8
        while offset < png.count {
            let length = png[offset..<(offset + 4)].reduce(0) { $0 << 8 | Int($1) }
            result.append(png[offset..<(offset + 12 + length)])
            offset += 12 + length
        }
        return result  // IHDR, IDAT, IEND
    }

    private func assemble(_ parts: [Data]) -> Data {
        parts.reduce(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) { $0 + $1 }
    }

    @Test func aPNGTagBeforeTheDataOrAfterTheLastDataChunkIsRead() {
        let parts = chunks()
        #expect(ImageHeader.read(assemble([parts[0], exif(3), parts[1], parts[2]]))?.orientation == 3, "before IDAT")
        #expect(ImageHeader.read(assemble([parts[0], parts[1], exif(8), parts[2]]))?.orientation == 8, "after the last IDAT")
        #expect(ImageHeader.read(assemble([parts[0], parts[1], parts[1], exif(8), parts[2]]))?.orientation == 8)
        #expect(ImageHeader.read(assemble([parts[0], parts[1], exif(8), parts[1], parts[2]]))?.orientation == 1, "between IDATs is ignored")
        #expect(ImageHeader.read(assemble([parts[0], exif(3), exif(6), parts[1], parts[2]]))?.orientation == 3, "the first one wins")
        #expect(ImageHeader.read(assemble([parts[0], exif(9), parts[1], parts[2]]))?.orientation == 1, "out of range is upright")
    }

    @Test func aPNGWithAZeroSideOrNoHeaderChunkHasNoHeader() {
        #expect(ImageHeader.read(TestImages.pngHeader(claiming: 0, 5)) == nil)
        #expect(ImageHeader.read(TestImages.pngHeader(claiming: 5, 0)) == nil)
        #expect(ImageHeader.read(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 7, count: 40))) == nil)
    }

    @Test func aPNGHeaderClaimingHugeSidesIsReadAsClaimed() {
        let header = ImageHeader.read(TestImages.pngHeader(claiming: 0x7FFF_FFFF, 100_000))
        #expect(header == ImageHeader(kind: .png, width: 0x7FFF_FFFF, height: 100_000, orientation: 1))
    }

    @Test func aJPEGCutAtEveryLengthNeverTraps() throws {
        let jpeg = try #require(GreyImageDecoderPinnedTests.colourJPEGTurned.data as Data?)
        #expect(ImageHeader.read(jpeg) == ImageHeader(kind: .jpeg, width: 8, height: 4, orientation: 6))
        var found = 0
        for length in 0..<jpeg.count where ImageHeader.read(jpeg.prefix(length)) != nil { found += 1 }
        #expect(found > 0 && found < jpeg.count, "only a cut after the frame header has a size")
        for length in stride(from: 0, to: jpeg.count, by: 3) {
            var damaged = jpeg
            damaged[length] ^= 0xFF
            _ = ImageHeader.read(damaged)
        }
    }

    @Test func otherPictureFormatsAreRecognisedByTheirSignatures() {
        #expect(ImageHeader.read(Data("GIF89a".utf8) + Data(count: 10))?.kind == .other)
        #expect(ImageHeader.read(Data("hello, not a picture".utf8)) == nil)
        #expect(ImageHeader.read(Data()) == nil)
    }
}
