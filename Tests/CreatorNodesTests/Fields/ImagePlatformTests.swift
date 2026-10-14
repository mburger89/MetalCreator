import CreatorGraph
import Foundation
import Testing
@testable import CreatorNodes

/// Where pictures cannot be decoded yet (cross-platform spec 2.2, MetalUI gap XP-G4): off macOS the Image Field says so in the
/// sentence below, in place of a crash or a blank field. MetalUI's public decode will replace the stopgap.
struct ImagePlatformTests {
    static let message = "Images need a newer MetalUI on this platform."

    @Test func theProblemReadsAsTheSpecSays() {
        #expect(ImageProblem.platformUnsupported.message == Self.message)
    }

    #if !canImport(ImageIO)
    @Test func theDecoderRefusesEveryPictureWithThatProblem() async {
        let png = TestImages.flatGrey(4, 4, 100)
        #expect(throws: ImageProblem.platformUnsupported) { try GreyImageDecoder.inspect(png) }
        await #expect(throws: ImageProblem.platformUnsupported) { try await GreyImageDecoder.decode(png) }
    }

    @Test func anImageFieldReportsItOnItsBadge() async throws {
        let png = TestImages.flatGrey(4, 4, 100)
        let hash = ImageHash(of: png)
        var h = Harness()
        let node = h.add(ImageFieldNode.self, [NodeSetting.image: .image(.embedded(hash))])
        let report = try await h.run([node], images: ImageResolver(embedded: [hash: png]))
        #expect(report.error(node) == Self.message)
    }
    #endif
}
