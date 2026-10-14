import CreatorGraph
import Foundation
import Testing
@testable import CreatorNodes

/// Values taken from ImageIO's output before `GreyImageDecoder+ImageIO.swift` was removed (adopt-s2): the decoder must still give
/// them, within 1/255 of the range (257 of 65,535), on every platform. The PNG pins are closed-form (written out in
/// `GreyImageDecoderTests`) and exact; the three JPEGs below are ImageIO-encoded files carried as bytes, so Linux and Windows
/// check JPEG decoding and its EXIF orientation too, and the grids are what ImageIO decoded from them. The decoders differ by
/// at most 43 of 65,535 here (stb's IDCT and chroma upsampling are not ImageIO's).
struct GreyImageDecoderPinnedTests {
    struct Fixture: Sendable {
        let bytes: String
        let width: Int
        let height: Int
        /// ImageIO's grey grid, row 0 first, upright.
        let grid: [UInt16]

        var data: Data { Data(base64Encoded: bytes, options: .ignoreUnknownCharacters) ?? Data() }
    }

    /// A 5 x 3 grey JPEG with EXIF orientation 6 (a quarter turn): upright it is 3 x 5.
    static let greyJPEGTurned = Fixture(
        bytes: """
        /9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAgESAAMAAAABAAYAAIdpAAQAAAABAAAAJgAAAAAAAqACAAQA
        AAABAAAABaADAAQAAAABAAAAAwAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmA
        CZjs+EJ+/8AACwgAAwAFAQERAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQEC
        AwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVm
        Z2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq
        8fLz9PX29/j5+v/bAEMAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB
        AQEBAf/dAAQAAf/aAAgBAQAAPwD9gv8Agnd+wl+yF/wo+3/4sF4D/wCYb/y6Xv8Az7z/APT9X//Z
        """,
        width: 3, height: 5, grid: [
            33410, 17990, 2570, 39835, 24415, 8995, 46260, 30840,
            15420, 52685, 37265, 21845, 59110, 43690, 28270,
        ])

    /// An 8 x 4 colour JPEG (`TestImages.colourRows`), upright.
    static let colourJPEG = Fixture(
        bytes: """
        /9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQA
        AAABAAAACKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmA
        CZjs+EJ+/8AAEQgABAAIAwERAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQE
        AAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldY
        WVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk
        5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMR
        BAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdo
        aWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz
        9PX29/j5+v/bAEMAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB
        Af/bAEMBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAf/dAAQA
        Af/aAAwDAQACEQMRAD8A/jJ8HeDNA/d/6J/c7r7f9M6+RjmmMVl7S12u+v4v9F5H1HCuLrfu/e6/pfuv67fEf//Z
        """,
        width: 8, height: 4, grid: [
            0, 751, 932, 1683, 2288, 2910, 3404, 3916,
            2019, 2532, 3026, 3483, 4271, 4985, 5166, 5954,
            3781, 4515, 4917, 5631, 6253, 6820, 7260, 7936,
            5912, 6480, 6974, 7558, 8200, 8914, 9150, 9958,
        ])

    /// The same colours stored 8 x 4 with EXIF orientation 6: upright it is 4 x 8.
    static let colourJPEGTurned = Fixture(
        bytes: """
        /9j/4AAQSkZJRgABAQAASABIAAD/4QBYRXhpZgAATU0AKgAAAAgAAgESAAMAAAABAAYAAIdpAAQAAAABAAAAJgAAAAAAA6ABAAMA
        AAABAAEAAKACAAQAAAABAAAACKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAA
        ABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAIAwERAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQ
        AAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNE
        RUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS
        09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQH
        BQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNU
        VVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ
        2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB
        AQEBAQEBAQEBAQEBAf/bAEMBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB
        AQEBAQEBAf/dAAQAAf/aAAwDAQACEQMRAD8A/jJ8HeDNA/d/6J/c7r7f9M6+RjmmMVl7S12u+v4v9F5H1HCuLrfu/e6/pfuv67fE
        f//Z
        """,
        width: 4, height: 8, grid: [
            5912, 3781, 2019, 0, 6480, 4515, 2532, 751,
            6974, 4917, 3026, 932, 7558, 5631, 3483, 1683,
            8200, 6253, 4271, 2288, 8914, 6820, 4985, 2910,
            9150, 7260, 5166, 3404, 9958, 7936, 5954, 3916,
        ])

    static let all: [(String, Fixture)] = [
        ("grey JPEG, orientation 6", greyJPEGTurned), ("colour JPEG", colourJPEG), ("colour JPEG, orientation 6", colourJPEGTurned),
    ]

    @Test(arguments: all) func aJPEGGivesImageIOsGridWithinOneLevel(name: String, fixture: Fixture) async throws {
        let data = fixture.data
        #expect(!data.isEmpty, "\(name) fixture")
        let info = try GreyImageDecoder.inspect(data)
        #expect(info == GreyImageDecoder.Info(width: fixture.width, height: fixture.height, format: .jpeg), "\(name)")
        let image = try await GreyImageDecoder.decode(data)
        #expect(image.width == fixture.width && image.height == fixture.height, "\(name)")
        let worst = zip(image.pixels, fixture.grid).map { abs(Int($0) - Int($1)) }.max() ?? .max
        #expect(image.pixels.count == fixture.grid.count && worst <= 257, "\(name): largest difference \(worst)")
    }

    /// A straight-alpha RGBA pixel (what a PNG stores) is composited against black and weighted by Rec. 709; each premultiplied
    /// component is rounded to the nearest 16-bit value first. Written out by hand from that rule, on every platform.
    @Test(arguments: [
        (200, 90, 30, 64, 7034), (200, 90, 30, 200, 21982), (12, 200, 99, 128, 19704), (255, 255, 255, 128, 32_896), (255, 255, 255, 0, 0),
        (10, 20, 30, 255, 4779),
    ]) func straightAlphaIsCompositedAgainstBlack(red: Int, green: Int, blue: Int, alpha: Int, grey: Int) async throws {
        let png = PNGWriter.encode(width: 1, height: 1, color: .rgba) { _, _ in [red, green, blue, alpha].map { UInt8($0) } }
        #expect(Int(try await GreyImageDecoder.decode(png).pixels[0]) == grey)
        #expect(Int(GreyImageDecoder.grey(red: UInt8(red), green: UInt8(green), blue: UInt8(blue), alpha: UInt8(alpha))) == grey)
    }

    #if canImport(CoreGraphics)
    /// ImageIO's values for CoreGraphics' premultiplied fixtures (`TestImages.colour` stores them through a premultiplied context, so
    /// the PNG holds the 8-bit round trip of the colour, not the colour itself): exact in both decoders.
    @Test(arguments: [
        (200, 90, 30, 64, 7_122), (200, 90, 30, 200, 22_141), (12, 200, 99, 128, 19_621),
    ]) func transparencyGivesImageIOsGrey(red: Int, green: Int, blue: Int, alpha: Int, grey: Int) async throws {
        let image = try await GreyImageDecoder.decode(TestImages.colour(1, 1, red: red, green: green, blue: blue, alpha: alpha))
        #expect(Int(image.pixels[0]) == grey)
    }
    #endif

    /// ImageIO read these 16-bit samples exactly (0, 1, 4,660, 32,768, 40,000, 65,535); MetalUI rounds them to 8 bits, so each moves
    /// by at most 128 of 65,535, under 1/255 (adopt-s2, constraint 4).
    @Test func sixteenBitSamplesMoveByAtMostHalfAnEightBitLevel() async throws {
        let samples = [0, 1, 4_660, 32_768, 40_000, 65_535]
        let image = try await GreyImageDecoder.decode(TestImages.grey(6, 1, bits: 16) { x, _ in samples[x] })
        #expect(image.pixels == [0, 0, 4_626, 32_896, 40_092, 65_535])
        #expect(zip(image.pixels, samples).allSatisfy { abs(Int($0) - $1) <= 128 })
    }

    /// ImageIO's grey grid for the 7 x 4 colour picture `TestImages.colourRows(7, 4)`.
    @Test func aColourPNGGivesImageIOsGrid() async throws {
        let image = try await GreyImageDecoder.decode(TestImages.colourRows(7, 4))
        #expect(image.pixels == [
            0, 567, 1_135, 1_702, 2_269, 2_837, 3_404, 1_965, 2_532, 3_099, 3_666, 4_234, 4_801, 5_368,
            3_929, 4_496, 5_064, 5_631, 6_198, 6_766, 7_333, 5_894, 6_461, 7_028, 7_596, 8_163, 8_730, 9_297,
        ])
    }
}
