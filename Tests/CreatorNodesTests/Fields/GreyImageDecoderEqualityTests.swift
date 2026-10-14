#if canImport(ImageIO)
import CreatorGraph
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CreatorNodes

/// The proof that MetalUI's decode (S2) gives the grids ImageIO gave (adopt-s2, constraint 5): every image fixture the decoder tests
/// use, decoded by both paths, must agree within 1/255 of the range (257 of 65,535). Exists only while `GreyImageDecoder+ImageIO.swift`
/// does; `GreyImageDecoderPinnedTests` holds the values taken from this comparison.
struct GreyImageDecoderEqualityTests {
    static let tolerance = 257
    /// A colour JPEG differs more: stb's chroma upsampling and IDCT are not ImageIO's (measured: 441, under two levels).
    static let jpegTolerance = 3 * 257

    /// Every fixture the decoder, loader and Image Field tests make, by name.
    static func fixtures() -> [(String, Data)] {
        var all: [(String, Data)] = [
            ("grey 4x2", TestImages.grey(4, 2) { x, y in x * 60 + y * 10 }),
            ("grey 16-bit", TestImages.grey(3, 1, bits: 16) { x, _ in [0, 4_660, 65_535][x] }),
            ("grey 16-bit ramp", TestImages.grey(64, 4, bits: 16) { x, y in (x * 1_021 + y * 4_093) % 65_536 }),
            ("flat 100", TestImages.flatGrey(4, 4, 100)),
            ("flat 255", TestImages.flatGrey(2, 2, 255)),
            ("flat 0", TestImages.flatGrey(2, 2, 0)),
            ("grey ramp", TestImages.grey(256, 3) { x, _ in x }),
            ("noisy png", TestImages.noisy(64)),
            ("noisy jpeg", TestImages.noisy(64, type: .jpeg)),
            ("flat jpeg", TestImages.flatGrey(16, 16, 128, type: .jpeg)),
            ("colour rows", TestImages.colourRows(37, 30)),
            ("colour rows large", TestImages.colourRows(70, 50)),
            ("colour rows jpeg", TestImages.colourRows(40, 24, type: .jpeg)),
        ]
        for (red, green, blue) in [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255), (0, 0, 0), (12, 200, 99)] {
            all.append(("colour \(red),\(green),\(blue)", TestImages.colour(2, 2, red: red, green: green, blue: blue)))
        }
        for alpha in [0, 1, 64, 128, 200, 254] {
            all.append(("white alpha \(alpha)", TestImages.colour(2, 2, red: 255, green: 255, blue: 255, alpha: alpha)))
            all.append(("colour alpha \(alpha)", TestImages.colour(2, 2, red: 200, green: 90, blue: 30, alpha: alpha)))
        }
        for tag in 1...8 {
            let value: (Int, Int) -> Int = { x, y in 10 + x * 25 + y * 60 }
            all.append(("grey png orientation \(tag)", TestImages.grey(5, 3, type: .png, orientation: tag, value)))
            all.append(("grey jpeg orientation \(tag)", TestImages.grey(5, 3, type: .jpeg, orientation: tag, value)))
            all.append(("colour png orientation \(tag)", TestImages.colourRows(7, 4, orientation: tag)))
            all.append(("colour jpeg orientation \(tag)", TestImages.colourRows(16, 8, type: .jpeg, orientation: tag)))
        }
        all.append(("grey 70x50 orientation 6", TestImages.grey(70, 50, orientation: 6) { x, y in (x * 5 + y * 11) % 256 }))
        return all
    }

    @Test func everyFixtureGivesTheSameInfoAndGreyGridAsImageIOWithinOneLevel() async throws {
        var worstPNG = 0, worstJPEG = 0
        for (name, data) in Self.fixtures() {
            #expect(!data.isEmpty, "\(name) fixture")
            let old = try await GreyImageDecoder.decodeWithImageIO(data, bandBytes: GreyImageDecoder.defaultBandBytes)
            let new = try await GreyImageDecoder.decode(data)
            #expect(try GreyImageDecoder.inspect(data) == GreyImageDecoder.inspectWithImageIO(data), "\(name): header")
            #expect(old.width == new.width && old.height == new.height, "\(name): size")
            let difference = zip(old.pixels, new.pixels).map { abs(Int($0) - Int($1)) }.max() ?? .max
            let isJPEG = try GreyImageDecoder.inspect(data).format == .jpeg
            if isJPEG { worstJPEG = max(worstJPEG, difference) } else { worstPNG = max(worstPNG, difference) }
            #expect(difference <= (isJPEG ? Self.jpegTolerance : Self.tolerance), "\(name): largest difference \(difference) of 65,535")
        }
        print("EQUALITY worst PNG \(worstPNG), worst JPEG \(worstJPEG) of 65,535")
    }
}
#endif
