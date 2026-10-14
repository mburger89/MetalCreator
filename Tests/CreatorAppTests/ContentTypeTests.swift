import MetalUI
import Testing
@testable import CreatorApp

/// SDL's file dialogs filter by filename extension only (MetalUI divergence 129, gap XP-G6), so every type the app's panels use
/// declares its extensions.
struct ContentTypeTests {
    @Test(arguments: [
        (ContentType.mcgraph, "mcgraph"), (ContentType.step, "step"), (ContentType.stl, "stl"),
        (ContentType.png, "png"), (ContentType.jpeg, "jpg"), (ContentType.mctheme, "mctheme"),
    ])
    func everyTypeTheFilePanelsFilterByNamesItsExtension(_ type: ContentType, _ fileExtension: String) {
        #expect(type.preferredFilenameExtension == fileExtension)
    }
}
