import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Foundation
import Testing

/// Image-driven patterns (fields spec §1 purpose 3, §8): a grey picture, projected on the plate, sizes the holes: Image Field →
/// Remap → Sample Field → a Hole Pattern's `diameter`, on OCCT, then the same document saved, reopened, linked and edited on disk.
@MainActor
struct ImageAcceptanceTests {
    let folder = TempFolderForNodes()
    /// 4 × 1 px, black to white left to right. Over the 60 mm plate, clamped, the grey at x is `position / 3` with
    /// `position = clamp((x / 60 + 0.5) × 4 − 0.5, 0, 3)`; Remap turns grey 0…1 into Ø3…Ø5.
    let ramp = TestImages.grey(4, 1) { x, _ in x * 85 }

    struct Part {
        var plate = PatternPlate()
        var sample: Node
        var holes: Node
        var remap: Node
        var image: Node
    }

    func part(_ reference: ImageReference?) -> Part {
        var plate = PatternPlate()
        var values: [SocketName: ConstantValue] = ["width": .number(60), "height": .number(40), "edges": .integer(1)]
        if let reference { values[NodeSetting.image] = .image(reference) }
        let image = plate.h.add(ImageFieldNode.self, values)
        let remap = plate.h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(1), "toLow": .number(3), "toHigh": .number(5),
        ])
        let sample = plate.h.add(SampleFieldNode.self)
        let holes = plate.h.add(HolePatternNode.self, ["depth": .number(6)], output: true)
        plate.h.wire(image, "field", to: remap, "field")
        plate.h.wire(remap, "field", to: sample, "field")
        plate.h.wire(plate.placements, "placements", to: sample, "at")
        plate.h.wire(sample, "values", to: holes, "diameter")
        plate.h.wire(plate.plate, "solid", to: holes, "part")
        plate.h.wire(plate.placements, "placements", to: holes, "placements")
        return Part(plate: plate, sample: sample, holes: holes, remap: remap, image: image)
    }

    func diameter(atX x: Double, reversed: Bool = false) -> Double {
        let position = min(max((x / 60 + 0.5) * 4 - 0.5, 0), 3)
        return 3 + 2 * (reversed ? 1 - position / 3 : position / 3)
    }

    func origins(_ placements: Value?) -> [Vector3] {
        (placements?.items ?? []).compactMap { item in if case .plane(let plane) = item { plane.origin } else { nil } }
    }

    #if canImport(CreatorOCCT)
    @Test func aPictureSizesTheHolesAndTheHolesCutAreThoseSizes() async throws {
        let kernel = OCCTKernel()
        let hash = ImageHash(of: ramp)
        let part = part(.embedded(hash))
        let report = try await part.plate.h.run([part.holes], kernel: kernel, images: ImageResolver(embedded: [hash: ramp]))
        #expect(report.isOK(part.image) && report.isOK(part.sample) && report.isOK(part.holes),
                "\(String(describing: report.state(part.holes)))")
        let at = origins(report.value(part.plate.placements, "placements"))
        let sizes = try #require(report.value(part.sample, "values")?.numbers)
        #expect(at.count == 4 && sizes.count == 4)
        #expect(zip(sizes, at).allSatisfy { abs($0 - diameter(atX: $1.x)) < 1e-9 }, "got \(sizes)")
        let rounded = sizes.sorted().map { ($0 * 1000).rounded() / 1000 }
        #expect(rounded == [3.111, 3.111, 4.889, 4.889], "darker on the left, lighter on the right")
        let want = sizes.reduce(0) { $0 + PatternPlate.cylinderVolume($1, 6) }
        let removed = PatternPlate.plateVolume - (try await volume(try onlySolid(report, part.holes), kernel))
        #expect(isClose(removed, want), "removed \(removed), wanted \(want)")
    }

    @Test func theSavedDocumentReopensToTheSameHolesOnASecondRun() async throws {
        let kernel = OCCTKernel()
        let hash = ImageHash(of: ramp)
        let part = part(.embedded(hash))
        let document = DocumentModel(file: GraphFile(graph: part.plate.h.graph, images: [hash: ramp]),
                                     registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let first = try #require(document.results[part.sample.id]?.outputs?["values"]?.numbers)
        let data = try document.fileData()
        #expect(try #require(String(bytes: data, encoding: .utf8)).contains("\"formatVersion\" : 7"))
        let reopened = try DocumentModel(data: data, registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        #expect(reopened.results[part.sample.id]?.outputs?["values"]?.numbers == first, "identical on a second run")
        #expect(reopened.results[part.holes.id]?.state.isSuccess == true)
        let solid = try #require(reopened.results[part.holes.id]?.outputs?["solid"]?.solids?.first)
        let want = first.reduce(0) { $0 + PatternPlate.cylinderVolume($1, 6) }
        #expect(isClose(PatternPlate.plateVolume - (try await volume(solid, kernel)), want))
    }

    @Test func aLinkedPictureEditedOnDiskResizesTheHolesAtTheNextEvaluation() async throws {
        let kernel = OCCTKernel()
        let file = try folder.write(ramp, to: "maps/ramp.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        let part = part(.linked(relativePath: "maps/ramp.png", absolutePath: "/no/such/ramp.png"))
        let document = DocumentModel(file: GraphFile(graph: part.plate.h.graph), registry: BuiltInNodes.registry, kernel: kernel,
                                     documentURL: folder.url.appending(path: "Plate.mcgraph"))
        await document.waitForEvaluation()
        let before = try #require(document.results[part.sample.id]?.outputs?["values"]?.numbers)
        let at = origins(document.results[part.plate.placements.id]?.outputs?["placements"])
        #expect(zip(before, at).allSatisfy { abs($0 - diameter(atX: $1.x)) < 1e-9 })

        try folder.write(TestImages.grey(4, 1) { x, _ in 255 - x * 85 }, to: "maps/ramp.png")
        try folder.touch(file, Date(timeIntervalSince1970: 2_000))
        try document.perform(.setInput(part.remap.id, "toHigh", .number(5)), name: "Change To High")  // any edit evaluates again
        await document.waitForEvaluation()
        let after = try #require(document.results[part.sample.id]?.outputs?["values"]?.numbers)
        #expect(zip(after, at).allSatisfy { abs($0 - diameter(atX: $1.x, reversed: true)) < 1e-9 }, "the picture on disk is read again")
    }

    @Test func aMissingPictureStopsTheChainAtTheImageWithoutHarmingAnythingElse() async throws {
        let kernel = OCCTKernel()
        let path = folder.url.appending(path: "textures/vent-mask.png").path(percentEncoded: false)
        let part = part(.linked(relativePath: nil, absolutePath: path))
        let report = try await part.plate.h.run([part.holes], kernel: kernel)
        let message = try #require(report.error(part.image))
        #expect(message.hasPrefix("Image 'vent-mask.png' wasn't found at ") && message.hasSuffix("/textures/. Relink it in the inspector."))
        #expect(report.isOK(part.plate.plate) && report.isOK(part.plate.placements))
        #expect(report.value(part.holes, "solid") == nil, "no holes without sizes")
        let healed = try folder.write(ramp, to: "textures/vent-mask.png")
        #expect(FileManager.default.fileExists(atPath: healed.path(percentEncoded: false)))
        let again = try await part.plate.h.run([part.holes], kernel: kernel)
        #expect(again.isOK(part.holes), "the file appeared: the next evaluation uses it")
    }
    #endif
}
