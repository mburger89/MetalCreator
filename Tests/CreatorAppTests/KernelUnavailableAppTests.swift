import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// A document made on a Mac and opened where there is no OpenCascade (cross-platform spec 2.3, "the same files"): the nodes that
/// need geometry show the sentence, the others work, and saving writes what an app with a kernel would write, so the file can go
/// back to the Mac unchanged.
@MainActor
struct KernelUnavailableAppTests {
    static let message = "Geometry isn't available on this platform yet."

    @Test func aDocumentOpenedWithoutAKernelShowsTheSentenceAndSavesTheSameFile() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let file = GraphFile(graph: builder.graph)
        let without = AppModel(kernel: KernelUnavailable(), file: file)
        let with = AppModel(kernel: FakeKernel(), file: file)
        await without.settle()
        await with.settle()
        #expect(without.document.results[box.extrude.id]?.state == .error(Self.message))
        #expect(with.document.results[box.extrude.id]?.state.isSuccess == true)
        #expect(without.document.results[box.sketch.id]?.state.isSuccess == true, "the sketch needs no kernel")
        #expect(try without.document.fileData() == with.document.fileData())
    }

    @Test func anEmbeddedPictureIsKeptWhetherOrNotAnythingCanDecodeIt() async throws {
        let picture = Data("the bytes of a picture, whatever they are".utf8)
        let hash = ImageHash(of: picture)
        var builder = GraphBuilder()
        _ = builder.add(ImageFieldNode.self, [NodeSetting.image: .image(.embedded(hash))])
        let file = GraphFile(graph: builder.graph, images: [hash: picture])
        let app = AppModel(kernel: KernelUnavailable(), file: file)
        await app.settle()
        let saved = try GraphFileIO.decode(app.document.fileData(), registry: BuiltInNodes.registry)
        #expect(saved.images == [hash: picture])
    }

    /// The Output has no result, because the Extrude upstream has the sentence on its badge: the export says so and asks nothing.
    @Test func exportingWhereThereIsNoKernelAsksNothingAndWritesNothing() async throws {
        var builder = GraphBuilder()
        _ = builder.sketchedBox(rectangleSketch())
        let app = await makeApp(builder.graph, kernel: KernelUnavailable())
        let folder = AppTempFolder()
        let picker = ScriptedPicker([folder.url.appending(path: "part.step")])
        await app.exportDocument(.step, using: picker)
        let reason = "Waiting on “solid”: the node wired into it has no result."
        #expect(app.alert == .problem(AppProblem("“Output” can't be exported", reason)))
        #expect(picker.asked.isEmpty, "it says what is wrong before asking where")
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "part.step").path(percentEncoded: false)))
    }
}
