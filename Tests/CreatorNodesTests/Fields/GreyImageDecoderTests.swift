#if canImport(ImageIO)
import CreatorGraph
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CreatorNodes

/// `GreyImageDecoder` (fields spec §5, D10): grey and colour pictures, and every way an untrusted file can be wrong.
struct GreyImageDecoderTests {
    @Test func aGrey8BitPictureReadsBackAsItsValuesScaledTo16Bits() async throws {
        let png = TestImages.grey(4, 2) { x, y in x * 60 + y * 10 }
        let image = try await GreyImageDecoder.decode(png)
        #expect(image.width == 4 && image.height == 2)
        #expect(image.pixels == [0, 60, 120, 180, 10, 70, 130, 190].map { $0 * 257 }, "row 0 is the top row")
    }

    @Test func aGrey16BitPictureKeepsItsPrecision() async throws {
        let png = TestImages.grey(3, 1, bits: 16) { x, _ in [0, 4_660, 65_535][x] }
        #expect(try await GreyImageDecoder.decode(png).pixels == [0, 4_660, 65_535])
    }

    @Test func colourBecomesRec709LuminanceOfTheColour() async throws {
        let expected: [(Int, Int, Int, Int)] = [
            (255, 0, 0, 13_932), (0, 255, 0, 46_870), (0, 0, 255, 4_732), (255, 255, 255, 65_535), (0, 0, 0, 0),
        ]
        for (red, green, blue, grey) in expected {
            let image = try await GreyImageDecoder.decode(TestImages.colour(2, 2, red: red, green: green, blue: blue))
            for pixel in image.pixels { #expect(abs(Int(pixel) - grey) <= 2, "(\(red), \(green), \(blue)) gave \(pixel), not \(grey)") }
        }
    }

    @Test func transparencyIsCompositedAgainstBlack() async throws {
        let clear = try await GreyImageDecoder.decode(TestImages.colour(2, 2, red: 255, green: 255, blue: 255, alpha: 0))
        #expect(clear.pixels.allSatisfy { $0 == 0 }, "a see-through white is black")
        let half = try await GreyImageDecoder.decode(TestImages.colour(2, 2, red: 255, green: 255, blue: 255, alpha: 128))
        #expect(half.pixels.allSatisfy { abs(Int($0) - 32_896) <= 4 })
    }

    @Test func aJPEGDecodesToItsGreyWithinCompressionError() async throws {
        let jpeg = TestImages.flatGrey(16, 16, 128, type: .jpeg)
        let image = try await GreyImageDecoder.decode(jpeg)
        #expect(image.width == 16 && image.pixels.allSatisfy { abs(Int($0) - 128 * 257) <= 600 })
        #expect(try GreyImageDecoder.inspect(jpeg).format == .jpeg)
    }

    @Test func inspectReadsTheHeaderAndNamesTheFormat() throws {
        let info = try GreyImageDecoder.inspect(TestImages.flatGrey(30, 20, 9))
        #expect(info == GreyImageDecoder.Info(width: 30, height: 20, format: .png))
        #expect(info.format.fileExtension == "png" && GreyImageDecoder.Format.jpeg.fileExtension == "jpg")
    }

    // MARK: Damaged, foreign and hostile files

    @Test func bytesThatAreNotAnImageAreRefused() async throws {
        var state: UInt32 = 7
        let noise = Data((0..<1_000).map { _ in state = state &* 1_664_525 &+ 1_013_904_223; return UInt8(state >> 24) })
        for bytes in [Data(), Data("hello, this is a text file".utf8), noise, Data("%PDF-1.4\n%%EOF".utf8)] {
            await #expect(throws: ImageProblem.self) { try await GreyImageDecoder.decode(bytes) }
            #expect(throws: ImageProblem.self) { try GreyImageDecoder.inspect(bytes) }
        }
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(Data("hello".utf8)) }
    }

    @Test func aPictureCutShortOrWithADamagedBodyIsRefused() async throws {
        let png = TestImages.noisy(64)
        #expect(png.count > 2_000, "the fixture must have a body to cut")
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(png.prefix(png.count * 6 / 10)) }
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(png.dropLast(4)) }
        await #expect(throws: ImageProblem.self) { try await GreyImageDecoder.decode(png.prefix(20)) }
        var damaged = png
        for offset in stride(from: 100, to: 400, by: 7) { damaged[offset] ^= 0xFF }
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(damaged) }
        let jpeg = TestImages.noisy(64, type: .jpeg)
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(jpeg.prefix(jpeg.count / 2)) }
    }

    @Test func trailingBytesAfterAWholePictureAreIgnored() async throws {
        var png = TestImages.flatGrey(4, 4, 200)
        png.append(Data(repeating: 0, count: 100))
        #expect(try await GreyImageDecoder.decode(png).pixels.allSatisfy { $0 == 200 * 257 })
    }

    @Test func formatsThatAreNotPNGOrJPEGAreRefusedEvenWhenImageIOReadsThem() async throws {
        for type in [UTType.gif, .tiff] {
            let data = TestImages.flatGrey(8, 8, 90, type: type)
            #expect(!data.isEmpty, "\(type) fixture")
            await #expect(throws: ImageProblem.unsupportedType) { try await GreyImageDecoder.decode(data) }
        }
    }

    @Test func aSideBeyond8192PixelsIsRefusedFromTheHeaderAlone() async throws {
        for (width, height) in [(8_193, 1), (1, 8_193), (100_000, 1)] {
            let data = TestImages.flatGrey(width, height, 5)
            let expected = ImageProblem.tooManyPixels(width: width, height: height)
            #expect(throws: expected) { try GreyImageDecoder.inspect(data) }
            await #expect(throws: expected) { try await GreyImageDecoder.decode(data) }
        }
        for (width, height) in [(8_192, 1), (1, 8_192)] {
            let image = try await GreyImageDecoder.decode(TestImages.flatGrey(width, height, 5))
            #expect(image.width == width && image.height == height)
        }
    }

    @Test func aHeaderClaimingAHugePictureIsRefusedWithoutDecoding() async throws {
        for (width, height) in [(UInt32(0x7FFF_FFFF), UInt32(0x7FFF_FFFF)), (100_000, 100_000), (0, 0)] {
            let bomb = TestImages.pngHeader(claiming: width, height)
            await #expect(throws: ImageProblem.self) { try await GreyImageDecoder.decode(bomb) }
        }
    }

    @Test func moreThanSixteenMegabytesIsRefusedBeforeImageIOSeesIt() async throws {
        let over = Data(count: ImageLimits.maxBytes + 1)
        #expect(throws: ImageProblem.tooManyBytes(ImageLimits.maxBytes + 1)) { try GreyImageDecoder.inspect(over) }
        await #expect(throws: ImageProblem.tooManyBytes(ImageLimits.maxBytes + 1)) { try await GreyImageDecoder.decode(over) }
        var padded = TestImages.flatGrey(4, 4, 1)
        padded.append(Data(count: ImageLimits.maxBytes))
        await #expect(throws: ImageProblem.self) { try await GreyImageDecoder.decode(padded) }
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(Data(count: ImageLimits.maxBytes)) }
    }

    @Test(.timeLimit(.minutes(2))) func theLargestAllowedPictureDecodesInBands() async throws {
        let big = TestImages.flatGrey(8_192, 8_192, 77)
        #expect(big.count < ImageLimits.maxBytes)
        let image = try await GreyImageDecoder.decode(big)
        #expect(image.width == 8_192 && image.height == 8_192 && image.byteCount == 128 * 1_024 * 1_024)
        #expect(image.pixels.first == 77 * 257 && image.pixels.last == 77 * 257 && image.pixels[8_192 * 4_096 + 5] == 77 * 257)
    }

    /// A picture in which no two rows are alike, taken in bands of 1, 3 and 4 rows (and one smaller than a row), must come out
    /// exactly as one taken in a single band: a band placed a row off, in the wrong order or cropped wrongly cannot hide in a
    /// flat picture, but it shows in this one at its first, middle and last rows.
    @Test func severalBandsGiveTheSameRowsAsOneBand() async throws {
        let width = 37, height = 30  // a grey row is 74 bytes of 16-bit bitmap, a colour row 296
        let grey = TestImages.grey(width, height) { x, y in (x * 7 + y * 13) % 256 }
        let whole = try await GreyImageDecoder.decode(grey, bandBytes: GreyImageDecoder.defaultBandBytes)
        for y in [0, 1, 14, 15, 28, 29] {
            for x in [0, 1, 20, 36] { #expect(whole.pixels[y * width + x] == UInt16((x * 7 + y * 13) % 256 * 257), "grey (\(x), \(y))") }
        }
        for rows in [4, 3, 1] {
            let banded = try await GreyImageDecoder.decode(grey, bandBytes: 74 * rows)
            #expect(banded.pixels == whole.pixels, "grey in bands of \(rows) rows")
        }
        #expect(try await GreyImageDecoder.decode(grey, bandBytes: 1).pixels == whole.pixels, "a band smaller than a row is one row")

        let colour = TestImages.colourRows(width, height)
        let wholeColour = try await GreyImageDecoder.decode(colour, bandBytes: GreyImageDecoder.defaultBandBytes)
        for y in [0, 1, 14, 15, 28, 29] {
            let (red, green, blue) = TestImages.pixel(5, y)
            let expected = (2126 * red + 7152 * green + 722 * blue) * 257 / 10_000
            #expect(abs(Int(wholeColour.pixels[y * width + 5]) - expected) <= 4, "colour row \(y)")
        }
        for rows in [4, 3, 1] {
            let banded = try await GreyImageDecoder.decode(colour, bandBytes: 296 * rows)
            #expect(banded.pixels == wholeColour.pixels, "colour in bands of \(rows) rows")
        }
        #expect(Set(wholeColour.pixels[0..<width]) != Set(wholeColour.pixels[(height - 1) * width..<height * width]))
    }

    // MARK: EXIF/TIFF orientation (decision U11 (b))

    /// The upright grid for a stored `width` × `height` picture with `value(x, y)`, written out from the tag's definition:
    /// returns the oriented width, height and row-major values.
    private func oriented(_ tag: Int, _ width: Int, _ height: Int, _ value: (Int, Int) -> Int) -> (Int, Int, [Int]) {
        let swaps = tag >= 5
        let outWidth = swaps ? height : width, outHeight = swaps ? width : height
        var values: [Int] = []
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                let source: (Int, Int)
                switch tag {
                case 2: source = (width - 1 - x, y)
                case 3: source = (width - 1 - x, height - 1 - y)
                case 4: source = (x, height - 1 - y)
                case 5: source = (y, x)
                case 6: source = (y, height - 1 - x)
                case 7: source = (width - 1 - y, height - 1 - x)
                case 8: source = (width - 1 - y, x)
                default: source = (x, y)
                }
                values.append(value(source.0, source.1))
            }
        }
        return (outWidth, outHeight, values)
    }

    @Test(arguments: 1...8) func everyOrientationGivesThePictureAsPreviewShowsIt(tag: Int) async throws {
        let value: (Int, Int) -> Int = { x, y in 10 + x * 25 + y * 60 }  // 5 × 3, every pixel different
        let expected = oriented(tag, 5, 3) { x, y in value(x, y) * 257 }
        for type in [UTType.png, .jpeg] {
            let data = TestImages.grey(5, 3, type: type, orientation: tag, value)
            let info = try GreyImageDecoder.inspect(data)
            #expect(info.width == expected.0 && info.height == expected.1, "\(type) header, orientation \(tag)")
            let image = try await GreyImageDecoder.decode(data)
            #expect(image.width == expected.0 && image.height == expected.1, "\(type) size, orientation \(tag)")
            if type == .png {
                #expect(image.pixels.map(Int.init) == expected.2, "PNG orientation \(tag)")
            } else {
                #expect(zip(image.pixels, expected.2).allSatisfy { abs(Int($0) - $1) <= 1_500 }, "JPEG orientation \(tag)")
            }
        }
    }

    @Test(arguments: [5, 7]) func aColourPictureWithATransposingOrientationIsGreyAsPreviewShowsIt(tag: Int) async throws {
        let data = TestImages.colourRows(7, 4, orientation: tag)
        let expected = oriented(tag, 7, 4) { x, y in
            let (red, green, blue) = TestImages.pixel(x, y)
            return Int(((0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) * 257).rounded())
        }
        let image = try await GreyImageDecoder.decode(data)
        #expect(image.width == expected.0 && image.height == expected.1 && image.width == 4)
        let worst = zip(image.pixels, expected.2).map { abs(Int($0) - $1) }.max() ?? .max
        #expect(worst <= 600, "orientation \(tag): largest difference \(worst)")
        let banded = try await GreyImageDecoder.decode(data, bandBytes: 4 * 8)
        #expect(banded.pixels == image.pixels)
    }

    @Test func theSideLimitAppliesToTheOrientedSize() async throws {
        // 8,193 wide and 2 tall as stored; a quarter turn makes it 2 wide and 8,193 tall, still over the limit.
        let data = TestImages.flatGrey(8_193, 2, 5, orientation: 6)
        #expect(throws: ImageProblem.tooManyPixels(width: 2, height: 8_193)) { try GreyImageDecoder.inspect(data) }
    }

    @Test func aBandedLargePictureWithOrientation6EqualsTheUnbandedOne() async throws {
        let value: (Int, Int) -> Int = { x, y in (x * 5 + y * 11) % 256 }
        let data = TestImages.grey(70, 50, orientation: 6, value)
        let whole = try await GreyImageDecoder.decode(data, bandBytes: GreyImageDecoder.defaultBandBytes)
        let expected = oriented(6, 70, 50) { x, y in value(x, y) * 257 }
        #expect(whole.width == 50 && whole.height == 70 && whole.pixels.map(Int.init) == expected.2)
        for rows in [1, 3, 8] {
            let banded = try await GreyImageDecoder.decode(data, bandBytes: 50 * 2 * rows)
            #expect(banded.pixels == whole.pixels, "grey in bands of \(rows) rows")
        }
        let colour = TestImages.colourRows(70, 50, orientation: 6)
        let wholeColour = try await GreyImageDecoder.decode(colour, bandBytes: GreyImageDecoder.defaultBandBytes)
        #expect(wholeColour.width == 50 && wholeColour.height == 70)
        for rows in [1, 3] {
            let banded = try await GreyImageDecoder.decode(colour, bandBytes: 50 * 8 * rows)
            #expect(banded.pixels == wholeColour.pixels, "colour in bands of \(rows) rows")
        }
    }

    @Test func aCancelledDecodeStopsWithCancellationNotAnImageProblem() async throws {
        let png = TestImages.flatGrey(64, 64, 3)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await GreyImageDecoder.decode(png)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif
