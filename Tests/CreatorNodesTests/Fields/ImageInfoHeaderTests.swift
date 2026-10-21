import CreatorGraph
import Foundation
import MetalUI
import Testing
@testable import CreatorNodes

/// MetalUI's `ImageInfo` (S9) as `GreyImageDecoder.inspect` relies on it: the size and orientation read from a picture's first
/// bytes, before any pixel is decoded, and `ImageInfo.sniffedFormat(of:)` (XP-G12) for the formats it does not read.
struct ImageInfoHeaderTests {
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

    private func tag(_ data: Data) -> Int? { ImageInfo(data: data)?.orientation.exifValue }

    @Test func aPNGTagBeforeTheDataOrAfterTheLastDataChunkIsRead() {
        let parts = chunks()
        #expect(tag(assemble([parts[0], exif(3), parts[1], parts[2]])) == 3, "before IDAT")
        #expect(tag(assemble([parts[0], parts[1], exif(8), parts[2]])) == 8, "after the last IDAT")
        #expect(tag(assemble([parts[0], parts[1], parts[1], exif(8), parts[2]])) == 8)
        #expect(tag(assemble([parts[0], exif(3), exif(6), parts[1], parts[2]])) == 3, "the first one wins")
        #expect(tag(assemble([parts[0], exif(9), parts[1], parts[2]])) == 1, "out of range is upright")
    }

    @Test func aPNGWithAZeroSideOrNoHeaderChunkHasNoHeader() {
        #expect(ImageInfo(data: TestImages.pngHeader(claiming: 0, 5)) == nil)
        #expect(ImageInfo(data: TestImages.pngHeader(claiming: 5, 0)) == nil)
        #expect(ImageInfo(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 7, count: 40))) == nil)
    }

    @Test func aPNGHeaderClaimingHugeSidesIsReadAsClaimed() throws {
        let info = try #require(ImageInfo(data: TestImages.pngHeader(claiming: 0x7FFF_FFFF, 100_000)))
        #expect(info.format == .png && info.width == 0x7FFF_FFFF && info.height == 100_000 && info.orientation.exifValue == 1)
    }

    /// The JPEG fixtures carry their bytes, so this runs on every platform: stored 8 × 4 with tag 6 is 4 × 8 once turned.
    @Test func aJPEGReportsItsStoredSizeAndItsOrientationAndSurvivesEveryCut() throws {
        let jpeg: Data = GreyImageDecoderPinnedTests.colourJPEGTurned.data
        let info = try #require(ImageInfo(data: jpeg))
        #expect(info.format == .jpeg && info.width == 8 && info.height == 4 && info.orientation.exifValue == 6)
        #expect(info.orientedSize.width == 4 && info.orientedSize.height == 8)
        let upright = try #require(ImageInfo(data: GreyImageDecoderPinnedTests.colourJPEG.data))
        #expect(upright.orientation.exifValue == 1)
        var found = 0
        for length in 0..<jpeg.count where ImageInfo(data: jpeg.prefix(length)) != nil { found += 1 }
        #expect(found > 0 && found < jpeg.count, "only a cut after the frame header has a size")
        for length in stride(from: 0, to: jpeg.count, by: 3) {
            var damaged = jpeg
            damaged[length] ^= 0xFF
            _ = ImageInfo(data: damaged)
        }
    }

    @Test func inspectReportsTheOrientedSizeOfEveryPinnedFixture() throws {
        for (name, fixture) in GreyImageDecoderPinnedTests.all {
            let info = try #require(ImageInfo(data: fixture.data), "\(name)")
            let inspected = try GreyImageDecoder.inspect(fixture.data)
            #expect(inspected.width == info.orientedSize.width && inspected.height == info.orientedSize.height, "\(name)")
        }
    }

    /// A `BM` file with a 40-byte DIB header (BITMAPINFOHEADER), the shortest prefix MetalUI's sniff names a BMP from.
    private static let bmpPrefix: [UInt8] = Array("BM".utf8) + [UInt8](repeating: 0, count: 12) + [40, 0, 0, 0]

    /// The `ftyp` box of an AVIF (`avif` major brand), eight bytes of box header and the brand.
    private static let avifPrefix: [UInt8] = [0, 0, 0, 0x1C] + Array("ftypavif".utf8)

    @Test func otherPictureFormatsAreNamedByTheSniffAndRefusedAsUnsupported() throws {
        let formats: [(String, [UInt8], ImageFileFormat)] = [
            ("GIF", Array("GIF89a".utf8) + [8, 0, 8, 0, 0, 0, 0x3B], .gif),
            ("TIFF", [0x49, 0x49, 0x2A, 0, 8, 0, 0, 0, 0, 0], .tiff),
            ("BMP", Self.bmpPrefix, .bmp),
            ("WebP", Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBPVP8 ".utf8), .webp),
            ("HEIF", [0, 0, 0, 0x18] + Array("ftypheic".utf8), .heif),
            ("AVIF", Self.avifPrefix, .avif),
        ]
        for (name, bytes, format) in formats {
            let data = Data(bytes)
            #expect(ImageInfo(data: data) == nil, "\(name)")
            #expect(ImageInfo.sniffedFormat(of: data) == format, "\(name)")
            #expect(throws: ImageProblem.unsupportedType, "\(name)") { try GreyImageDecoder.inspect(data) }
        }
    }

    @Test func notAPictureAndADamagedPNGOrJPEGAreUndecodable() {
        let garbage: [(String, Data)] = [
            ("text", Data("hello, not a picture".utf8)), ("empty", Data()), ("a lone BM", Data("BM".utf8)),
            ("a cut PNG signature", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])),
            ("a JPEG signature alone", Data([0xFF, 0xD8, 0xFF])),
        ]
        for (name, data) in garbage {
            #expect(throws: ImageProblem.undecodable, "\(name)") { try GreyImageDecoder.inspect(data) }
        }
        #expect(ImageInfo.sniffedFormat(of: Data("hello, not a picture".utf8)) == .unknown)
        #expect(ImageInfo.sniffedFormat(of: Data()) == .unknown)
    }
}
