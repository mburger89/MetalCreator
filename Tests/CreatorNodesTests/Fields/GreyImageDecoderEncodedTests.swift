#if canImport(CoreGraphics)
import CreatorGraph
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CreatorNodes

/// The decoder tests whose pictures need an encoder this repository does not have in plain Swift (JPEG, GIF, TIFF, and a large
/// compressed PNG), so they are macOS-only. `GreyImageDecoderPinnedTests` carries JPEGs as bytes for every other platform.
struct GreyImageDecoderEncodedTests {
    @Test func aJPEGDecodesToItsGreyWithinCompressionError() async throws {
        let jpeg = TestImages.flatGrey(16, 16, 128, type: .jpeg)
        let image = try await GreyImageDecoder.decode(jpeg)
        #expect(image.width == 16 && image.pixels.allSatisfy { abs(Int($0) - 128 * 257) <= 600 })
        #expect(try GreyImageDecoder.inspect(jpeg).format == .jpeg)
    }

    @Test(.timeLimit(.minutes(2))) func theLargestAllowedPictureDecodesInBands() async throws {
        let big = TestImages.flatGrey(8_192, 8_192, 77)
        #expect(big.count < ImageLimits.maxBytes)
        let image = try await GreyImageDecoder.decode(big)
        #expect(image.width == 8_192 && image.height == 8_192 && image.byteCount == 128 * 1_024 * 1_024)
        #expect(image.pixels.first == 77 * 257 && image.pixels.last == 77 * 257 && image.pixels[8_192 * 4_096 + 5] == 77 * 257)
    }

    @Test func aJPEGCutShortIsRefused() async throws {
        let jpeg = TestImages.noisy(64, type: .jpeg)
        await #expect(throws: ImageProblem.undecodable) { try await GreyImageDecoder.decode(jpeg.prefix(jpeg.count / 2)) }
    }

    @Test func aGIFAndATIFFMadeByImageIOAreRefused() async throws {
        for type in [UTType.gif, .tiff] {
            let data = TestImages.flatGrey(8, 8, 90, type: type)
            #expect(!data.isEmpty, "\(type) fixture")
            await #expect(throws: ImageProblem.unsupportedType) { try await GreyImageDecoder.decode(data) }
        }
    }

    @Test(arguments: 1...8) func aJPEGOfEveryOrientationIsUprightAndItsHeaderSaysTheOrientedSize(tag: Int) async throws {
        let value: (Int, Int) -> Int = { x, y in 10 + x * 25 + y * 60 }
        let data = TestImages.grey(5, 3, type: .jpeg, orientation: tag, value)
        let png = TestImages.grey(5, 3, orientation: tag, value)
        let expected = try await GreyImageDecoder.decode(png)
        let image = try await GreyImageDecoder.decode(data)
        #expect(try GreyImageDecoder.inspect(data) == GreyImageDecoder.Info(width: expected.width, height: expected.height, format: .jpeg))
        #expect(image.width == expected.width && image.height == expected.height)
        #expect(zip(image.pixels, expected.pixels).allSatisfy { abs(Int($0) - Int($1)) <= 1_500 }, "JPEG orientation \(tag)")
    }
}
#endif
