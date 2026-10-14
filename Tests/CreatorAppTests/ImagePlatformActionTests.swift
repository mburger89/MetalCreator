#if !canImport(ImageIO)
import CreatorGraph
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Choosing a picture where pictures cannot be decoded yet (cross-platform spec 2.2, MetalUI gap XP-G4): the person is told in
/// the spec's sentence, and the Image Field keeps its setting. MetalUI's public decode will replace the stopgap.
@MainActor
struct ImagePlatformActionTests {
    @Test func choosingAPictureSaysImagesNeedANewerMetalUIAndChangesNothing() async throws {
        var builder = GraphBuilder()
        let node = builder.add(ImageFieldNode.self)
        let app = await makeApp(builder.graph)
        let folder = AppTempFolder()
        let file = try folder.write(Data("any bytes".utf8), to: "vent.png")
        await app.performImage(.chooseImage, on: node.id, using: ScriptedPicker([file]))
        #expect(app.alert == .problem(AppProblem("“vent.png” can't be used as an image", "Images need a newer MetalUI on this platform.")))
        #expect(!app.isEdited)
    }
}
#endif
