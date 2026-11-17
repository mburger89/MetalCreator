#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorOCCT
import Foundation
import Testing
@testable import CreatorNodes

/// Import Model (NURBS spec, Task 8) through the real evaluator on OpenCascade.
struct ImportModelNodeTests {
    let folder = TempFolderForNodes()

    /// The bytes of a STEP file holding a 10 x 6 x `height` box, written by OpenCascade.
    func stepBox(height: Double = 4, _ kernel: OCCTKernel) async throws -> Data {
        let rectangle = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 6)),
            .line(Vector2(10, 6), Vector2(0, 6)), .line(Vector2(0, 6), Vector2(0, 0)),
        ])
        let solid = try await kernel.extrude(rectangle, distance: height, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let url = folder.url.appending(path: "made-\(UUID().uuidString).step")
        try await kernel.export([solid], format: .step, to: url)
        return try Data(contentsOf: url)
    }

    func linked(_ data: Data, name: String = "part.step", _ values: [SocketName: ConstantValue] = [:]) throws -> (Harness, Node, URL) {
        let file = try folder.write(data, to: name)
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportModelNode.self, values.merging([NodeSetting.modelFile: .modelFile(reference)]) { _, new in new })
        return (h, node, file)
    }

    @Test func outputsAndFacts() async throws {
        let kernel = OCCTKernel()
        let (h, node, _) = try linked(try await stepBox(kernel))
        let report = try await h.run([node], kernel: kernel)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let solid = try onlySolid(report, node, "solids")
        #expect(isClose(try await volume(solid, kernel), 240))
        #expect(report.value(node, "sheets")?.items.isEmpty == true)
        #expect(report.value(node, "curves")?.items.isEmpty == true)
        let facts = try #require(report.results[node.id]?.facts)
        #expect(facts == [
            PayloadFact("Format", "STEP"), PayloadFact("File units", "mm"), PayloadFact("Solids", "1"),
            PayloadFact("Sheets", "0"), PayloadFact("Curves", "0"),
        ])
        #expect(ImportModelNode.factsTitle == "Model")
    }

    @Test func facesAreNamedForTheNode() async throws {
        let kernel = OCCTKernel()
        let (h, node, _) = try linked(try await stepBox(kernel))
        let solid = try onlySolid(try await h.run([node], kernel: kernel), node, "solids")
        for (index, face) in solid.topology.faces.enumerated() {
            #expect(face.tags == [TopoTag(node: node.id, item: 0, role: .imported(face: index))])
        }
    }

    @Test func centimetresOnAMillimetreFileScaleByTen() async throws {
        let kernel = OCCTKernel()
        let (h, node, _) = try linked(try await stepBox(kernel), ["units": .integer(ImportUnits.centimetres.rawValue)])
        let solid = try onlySolid(try await h.run([node], kernel: kernel), node, "solids")
        #expect(isClose(solid.bounds.max, Vector3(100, 60, 40), tolerance: 1e-6))
        for (index, face) in solid.topology.faces.enumerated() {
            #expect(face.tags == [TopoTag(node: node.id, item: 0, role: .imported(face: index))])
        }
    }

    @Test func editedFileIsReadAgainAtTheNextEvaluation() async throws {
        let kernel = OCCTKernel()
        let (h, node, file) = try linked(try await stepBox(height: 4, kernel))
        let first = try onlySolid(try await h.run([node], kernel: kernel), node, "solids")
        #expect(isClose(first.bounds.max.z, 4))
        try await stepBox(height: 9, kernel).write(to: file)
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
        let second = try onlySolid(try await h.run([node], kernel: kernel), node, "solids")
        #expect(isClose(second.bounds.max.z, 9))
    }

    @Test func anEmbeddedCopyReadsTheSame() async throws {
        let kernel = OCCTKernel()
        let data = try await stepBox(kernel)
        var h = Harness()
        let hash = ImageHash(of: data)
        let node = h.add(ImportModelNode.self, [NodeSetting.modelFile: .modelFile(.embedded(hash))])
        let report = try await h.run([node], kernel: kernel, images: ImageResolver(embedded: [hash: data]))
        let solid = try onlySolid(report, node, "solids")
        #expect(isClose(try await volume(solid, kernel), 240))
        #expect(report.results[node.id]?.facts.first == PayloadFact("Format", "STEP"))
    }

    @Test func aFileReadOnceServesTwoNodes() async throws {
        let kernel = OCCTKernel()
        let (h, first, file) = try linked(try await stepBox(height: 5, kernel), name: "shared.step")
        var graph = h
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let second = graph.add(ImportModelNode.self, [NodeSetting.modelFile: .modelFile(reference)])
        let before = await ImportedModelCache.shared.readCount
        let report = try await graph.run([first, second], kernel: kernel)
        let after = await ImportedModelCache.shared.readCount
        #expect(after - before <= 2)
        let a = try onlySolid(report, first, "solids"), b = try onlySolid(report, second, "solids")
        #expect(a.topology.faces[0].tags != b.topology.faces[0].tags)
    }

    @Test func refusalsAreSentences() async throws {
        let kernel = OCCTKernel()
        var none = Harness()
        let unset = none.add(ImportModelNode.self)
        #expect(try await none.run([unset], kernel: kernel).error(unset) == "Choose a STEP or IGES file.")

        let (h, text, _) = try linked(Data("hello".utf8), name: "notes.step")
        #expect(try await h.run([text], kernel: kernel).error(text) == "This isn't a STEP or IGES file.")

        let emptyStep = Data("ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n".utf8)
        let (h2, empty, _) = try linked(emptyStep, name: "empty.step")
        #expect(try await h2.run([empty], kernel: kernel).error(empty) == "The model contains no shapes.")

        var h3 = Harness()
        let gone = ImageReference.linked(relativePath: nil, absolutePath: "/nowhere/x.step")
        let missing = h3.add(ImportModelNode.self, [NodeSetting.modelFile: .modelFile(gone)])
        #expect(try await h3.run([missing], kernel: kernel).error(missing)?.contains("wasn't found") == true)
    }

    @Test func aFileOver256MegabytesIsRefusedWithoutBeingRead() throws {
        let file = try folder.write(Data(), to: "huge.step")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ImageResolver.maxModelFileBytes + 1))
        try handle.close()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        #expect(throws: ModelImportProblem.tooLarge) { try ImageResolver().modelFileBytes(of: reference) }
        #expect(ModelImportProblem.tooLarge.message == "The model file is larger than 256 MB.")
    }

    @Test func theCacheRemembersADamagedFileUnderItsStamp() async throws {
        let cache = ImportedModelCache()
        let stamp = ImageStamp.file(path: "/x/a.step", modified: Date(timeIntervalSince1970: 1), size: 5)
        let failing: @Sendable () async throws -> ImportedModel = { throw ImportedModelProblem(message: "This isn't a STEP or IGES file.") }
        for _ in 0..<2 { await #expect(throws: ImportedModelProblem.self) { try await cache.model(for: stamp, read: failing) } }
        let (problems, reads) = (await cache.problemCount, await cache.readCount)
        #expect(problems == 1 && reads == 1)
        // A path with nothing at it has no stamp worth keeping.
        let missing = ImageStamp.missing(path: "/x/b.step")
        for _ in 0..<2 { await #expect(throws: ImportedModelProblem.self) { try await cache.model(for: missing, read: failing) } }
        let (problemsAfter, readsAfter) = (await cache.problemCount, await cache.readCount)
        #expect(problemsAfter == 1 && readsAfter == 3)
    }
}
#endif
