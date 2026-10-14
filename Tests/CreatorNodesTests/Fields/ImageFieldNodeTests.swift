import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// Image Field (fields spec §3.1, §5) through the real evaluator: the field it makes and every way it refuses.
struct ImageFieldNodeTests {
    let folder = TempFolderForNodes()
    /// 4 × 2 px, 8-bit: the top row 0, 85, 170, 255 and the bottom row its mirror.
    let ramp = TestImages.grey(4, 2) { x, y in y == 0 ? x * 85 : (3 - x) * 85 }

    /// An Image Field with `data` embedded, and the resolver that holds it.
    func embedded(_ data: Data, _ values: [SocketName: ConstantValue] = [:]) -> (Harness, Node, ImageResolver) {
        var h = Harness()
        let hash = ImageHash(of: data)
        let node = h.add(ImageFieldNode.self, values.merging([NodeSetting.image: .image(.embedded(hash))]) { _, new in new })
        return (h, node, ImageResolver(embedded: [hash: data]))
    }

    // The tests that read a picture's grey need a decoder, which only macOS has until MetalUI's public decode lands (gap XP-G4).
    #if canImport(ImageIO)
    @Test func itMakesAFieldOfThePicturesGreyCentredOnThePlane() async throws {
        let (h, node, images) = embedded(ramp, ["width": .number(8), "height": .number(4)])
        let report = try await h.run([node], images: images)
        #expect(report.field(node)?.description == "image(4 × 2 px over 8 × 4 mm, tile)")
        let points = [Vector3(-3, 1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(3, 1, 0), Vector3(-3, -1, 0), Vector3(3, -1, 0)]
        let found = try await sampled(report.field(node), at: points)
        #expect(found == [0, 85.0 / 255, 170.0 / 255, 1, 1, 0])
    }

    @Test func theEdgeSettingChoosesBetweenTilingAndClamping() async throws {
        let outside = [Vector3(5, 1, 0), Vector3(-5, 1, 0)]
        let (tile, tileNode, images) = embedded(ramp, ["width": .number(8), "height": .number(4), "edges": .integer(0)])
        let tiled = try await sampled(tile.run([tileNode], images: images).field(tileNode), at: outside)
        #expect(tiled == [0, 1], "x 5 is a pixel past the right edge, which wraps to column 0; x −5 is a pixel before the left one")
        let (clamp, clampNode, _) = embedded(ramp, ["width": .number(8), "height": .number(4), "edges": .integer(1)])
        let held = try await sampled(clamp.run([clampNode], images: images).field(clampNode), at: outside)
        #expect(held == [1, 0], "the nearest edge pixel on each side")
        #expect(try await clamp.run([clampNode], images: images).field(clampNode)?.description.hasSuffix(", clamp)") == true)
    }

    @Test func itFollowsAWiredPlane() async throws {
        var h = Harness()
        let data = ramp
        let plane = h.add(PlaneNode.self, ["offset": .number(30)])
        let reference = ConstantValue.image(.embedded(ImageHash(of: data)))
        let node = h.add(ImageFieldNode.self, ["width": .number(8), "height": .number(4), NodeSetting.image: reference])
        h.wire(plane, "plane", to: node, "plane")
        let report = try await h.run([node], images: ImageResolver(embedded: [ImageHash(of: data): data]))
        let found = try await sampled(report.field(node), at: [Vector3(3, 1, 30), Vector3(3, 1, -5)])
        #expect(found == [1, 1], "projected along the normal")
    }

    @Test func aLinkedFileIsReadRelativeToTheDocumentAndAChangeOnDiskIsSeenNextTime() async throws {
        let file = try folder.write(TestImages.flatGrey(2, 2, 51), to: "maps/vent.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        var h = Harness()
        let reference = ImageReference.linked(relativePath: "maps/vent.png", absolutePath: "/gone/vent.png")
        let node = h.add(ImageFieldNode.self, [NodeSetting.image: .image(reference)])
        let images = ImageResolver(documentFolder: folder.url)
        #expect(try await sampled(h.run([node], images: images).field(node), at: [Vector3.zero]) == [0.2])
        try folder.write(TestImages.flatGrey(2, 2, 255), to: "maps/vent.png")
        try folder.touch(file, Date(timeIntervalSince1970: 2_000))
        #expect(try await sampled(h.run([node], images: images).field(node), at: [Vector3.zero]) == [1])
    }

    // MARK: Refusals
    #endif

    @Test func noImageChosenIsAnErrorThatSaysWhatToDo() async throws {
        var h = Harness()
        let node = h.add(ImageFieldNode.self)
        #expect(try await h.run([node]).error(node) == "Image Field needs an image: choose one in the inspector.")
    }

    @Test func aMissingLinkNamesTheFileAndTheFolderAndAnAbsentEmbeddedImageSaysSo() async throws {
        var h = Harness()
        let path = folder.url.appending(path: "textures/vent-mask.png").path(percentEncoded: false)
        let linked = h.add(ImageFieldNode.self, [NodeSetting.image: .image(.linked(relativePath: nil, absolutePath: path))])
        let absent = h.add(ImageFieldNode.self, [NodeSetting.image: .image(.embedded(ImageHash(of: Data("x".utf8))))])
        let report = try await h.run([linked, absent])
        let message = try #require(report.error(linked))
        #expect(message.hasPrefix("Image 'vent-mask.png' wasn't found at ") && message.hasSuffix("/textures/. Relink it in the inspector."))
        #expect(report.error(absent) == ImageProblem.embeddedMissing.message)
    }

    #if canImport(ImageIO)
    @Test func aFileThatIsNotAnImageIsAnErrorNotACrash() async throws {
        let junk = Data("this is not a picture".utf8)
        let (h, node, images) = embedded(junk)
        #expect(try await h.run([node], images: images).error(node) == ImageProblem.undecodable.message)
        let (hg, gif, gifImages) = embedded(TestImages.flatGrey(8, 8, 3, type: .gif))
        #expect(try await hg.run([gif], images: gifImages).error(gif) == ImageProblem.unsupportedType.message)
        let (hw, wide, wideImages) = embedded(TestImages.flatGrey(9_000, 1, 3))
        #expect(try await hw.run([wide], images: wideImages).error(wide) == ImageProblem.tooManyPixels(width: 9_000, height: 1).message)
    }

    @Test func aColourPictureIsUsedAsItsLuminance() async throws {
        let (h, node, images) = embedded(TestImages.colour(2, 2, red: 255, green: 255, blue: 255))
        #expect(try await sampled(h.run([node], images: images).field(node), at: [Vector3.zero]) == [1])
    }
    #endif

    @Test func aBadSizeEdgeOrPlaneIsRefusedWithItsOwnSentence() async throws {
        let cases: [(SocketName, ConstantValue, String)] = [
            ("width", .number(0), "“width” must be greater than 0 mm."),
            ("height", .number(-3), "“height” must be greater than 0 mm."),
            ("width", .number(.infinity), "“width” must be greater than 0 mm."),
            ("edges", .integer(2), "“edges” must be Tile or Clamp."),
            ("plane", .plane(Plane(origin: .zero, normal: .zero, xAxis: .unitX)), "“plane” has no direction."),
            ("plane", .plane(Plane(origin: .zero, normal: .unitZ, xAxis: .unitZ)), "“plane” has no direction."),
        ]
        for (socket, value, message) in cases {
            let (h, node, images) = embedded(ramp, [socket: value])
            #expect(try await h.run([node], images: images).error(node) == message, "\(socket)")
        }
    }

    @Test func theNodeIsAFieldsSourceWithItsOwnSettingAndASegmentedEdgeControl() throws {
        #expect(ImageFieldNode.category == .fields && ImageFieldNode.outputs.map(\.type) == [.field])
        #expect(ImageFieldNode.defaultSettings.isEmpty, "no picture until one is chosen")
        #expect(BuiltInNodes.registry[ImageFieldNode.typeID] != nil)
    }
}
