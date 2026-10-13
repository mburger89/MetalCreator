import Testing
@testable import CreatorGraph

/// The sentences an unusable picture shows (fields spec §4): pinned, with numbers written the way messages write them.
struct ImageProblemTests {
    @Test func everyProblemHasItsSentence() {
        #expect(ImageProblem.notChosen.message == "Image Field needs an image: choose one in the inspector.")
        #expect(ImageProblem.tooManyBytes(18_000_000).message == "That image file is 17.2 MB; images are limited to 16 MB.")
        #expect(ImageProblem.tooManyPixels(width: 9_000, height: 100).message
            == "That image is 9,000 × 100 px; a side can be at most 8,192 px.")
        #expect(ImageProblem.unsupportedType.message == "Only PNG and JPEG images can be used.")
        #expect(ImageProblem.undecodable.message == "That file isn't a readable PNG or JPEG image, or it is damaged.")
        #expect(ImageProblem.notAFile(name: "maps").message == "Image 'maps' isn't a file.")
        #expect(ImageProblem.unreadable(name: "a.png", reason: "Permission denied.").message
            == "Image 'a.png' couldn't be read: Permission denied.")
        #expect(ImageProblem.notFound(name: "vent-mask.png", folder: "/Users/me/textures/").message
            == "Image 'vent-mask.png' wasn't found at /Users/me/textures/. Relink it in the inspector.")
        #expect(ImageProblem.embeddedMissing.message
            == "This embedded image's data is missing from the file, or damaged. Choose the image again in the inspector.")
    }

    @Test func theLimitsAreTheSpecsD10() {
        #expect(ImageLimits.maxBytes == 16 * 1_048_576 && ImageLimits.maxSide == 8_192)
    }
}
