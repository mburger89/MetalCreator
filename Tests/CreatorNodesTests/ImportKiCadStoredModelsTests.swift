#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes
@testable import CreatorOCCT

/// Models stored in the board (`kicad-embed://`, KiCad import spec, KI-4) through the real evaluator on OpenCascade.
struct ImportKiCadStoredModelsTests {
    let folder = TempFolderForNodes()
    let kernel = OCCTKernel()
    typealias Part = KiCadBoardText.Part
    typealias Model = KiCadBoardText.Model

    var environment: BoardComponents.Environment {
        BoardComponents.Environment(variables: [:], home: folder.url.appending(path: "home").path(percentEncoded: false))
    }

    func part(_ reference: String, x: Double = 30, models: [Model], stored: [(name: String, base64: String)] = []) -> Part {
        Part(reference: reference, x: x, y: 20, library: "Parts:\(reference)", hasPad: false, models: models, stored: stored)
    }

    func stored(_ name: String) -> Model { Model(path: "kicad-embed://\(name)") }

    func board(_ parts: [Part], embedded: [(name: String, base64: String)] = [],
               values: [SocketName: ConstantValue] = [:]) throws -> (Harness, Node, String) {
        let extra = embedded.isEmpty ? "" : "  (embedded_files" + KiCadBoardText.storedFiles(embedded) + ")\n"
        let text = KiCadBoardText.rectangle(parts: parts, extra: extra)
        let file = try folder.write(Data(text.utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, values.merging([NodeSetting.pcbFile: .pcbFile(reference)]) { _, new in new })
        return (h, node, text)
    }

    func go(_ h: Harness, _ nodes: [Node]) async throws -> EvaluationReport {
        let environment = environment
        return try await BoardComponents.$environment.withValue(environment) { try await h.run(nodes, kernel: kernel) }
    }

    func warnings(_ report: EvaluationReport, _ node: Node) -> [String] {
        report.warning(node)?.split(separator: "\n").map(String.init) ?? []
    }

    func solids(_ report: EvaluationReport, _ node: Node) -> [Solid] { report.value(node, "components")?.solids ?? [] }

    func bounds(_ solid: Solid) throws -> (Vector3, Vector3) {
        let box = try #require(solid.bounds)
        return (box.min, box.max)
    }

    func expectEqual(_ a: (Vector3, Vector3), _ b: (Vector3, Vector3)) {
        #expect(abs(a.0.x - b.0.x) < 1e-6 && abs(a.0.y - b.0.y) < 1e-6 && abs(a.0.z - b.0.z) < 1e-6, "\(a) vs \(b)")
        #expect(abs(a.1.x - b.1.x) < 1e-6 && abs(a.1.y - b.1.y) < 1e-6 && abs(a.1.z - b.1.z) < 1e-6, "\(a) vs \(b)")
    }

    // MARK: Tests

    @Test func storedStepPlacesLikeTheSameStepOnDisk() async throws {
        let step = try await ComponentFixtures.step(kernel)
        try folder.write(step, to: "models/l.step")
        let onDisk = Model(path: "${KIPRJMOD}/models/l.step", offset: (1, 2, 0.5), rotate: (0, 0, 30))
        let inside = Model(path: "kicad-embed://in.step", offset: (1, 2, 0.5), rotate: (0, 0, 30))
        let (diskH, diskNode, _) = try board([part("U1", models: [onDisk])])
        let disk = try await go(diskH, [diskNode])
        let (h, node, _) = try board([part("U1", models: [inside])], embedded: [("in.step", ZstdRawFrame.base64(step))])
        let report = try await go(h, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(warnings(report, node).isEmpty)
        expectEqual(try bounds(try #require(solids(report, node).first)), try bounds(try #require(solids(disk, diskNode).first)))
        #expect(report.results[node.id]?.dependencies.contains { $0.path.hasSuffix(".step") } != true)
    }

    @Test func storedVrmlBecomesAMeshAndAGzippedStepIsUnpackedTwice() async throws {
        let vrml = Data(ImportKiCadMeshComponentsTests.vrml().utf8)
        let step = try await ComponentFixtures.step(kernel)
        let packed = ComponentFixtures.gzip(step)
        let embedded = [("v.wrl", ZstdRawFrame.base64(vrml, checksum: false)), ("s.step.gz", ZstdRawFrame.base64(packed))]
        let (h, node, _) = try board([part("U1", models: [stored("v.wrl")]), part("U2", x: 60, models: [stored("s.step.gz")])],
                                     embedded: embedded)
        let report = try await go(h, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(warnings(report, node).isEmpty)
        #expect(solids(report, node).count == 1)
        #expect(report.value(node, "component meshes")?.items.count == 1)
    }

    @Test func aFootprintsOwnTableBeatsTheBoards() async throws {
        let big = try await ComponentFixtures.step(kernel, scaledBy: 2)
        let small = try await ComponentFixtures.step(kernel)
        let inside = ZstdRawFrame.base64(small)
        let own = [(name: "m.step", base64: ZstdRawFrame.base64(big))]
        let parts = [part("A1", models: [stored("m.step")], stored: own), part("B1", x: 60, models: [stored("m.step")])]
        let (h, node, _) = try board(parts, embedded: [("m.step", inside)])
        let report = try await go(h, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let made = solids(report, node)
        #expect(made.count == 2)
        let widths = try made.map { try bounds($0) }.map { $0.1.x - $0.0.x }
        #expect(widths.contains { abs($0 - 12) < 1e-6 } && widths.contains { abs($0 - 6) < 1e-6 }, "\(widths)")
    }

    @Test func aMissingNameIsNotFound() async throws {
        let (h, node, _) = try board([part("U1", models: [stored("gone.step")])])
        let report = try await go(h, [node])
        #expect(warnings(report, node) == ["1 model wasn't found: kicad-embed://gone.step."])
    }

    @Test func emptyDataIsEmpty() async throws {
        let (h, node, _) = try board([part("U1", models: [stored("m.step")])], embedded: [("m.step", "")])
        let report = try await go(h, [node])
        #expect(warnings(report, node) == ["1 model couldn't be read: m.step (it is empty)."])
    }

    @Test func damagedFramesAreDamaged() async throws {
        let step = try await ComponentFixtures.step(kernel)
        let embedded = [
            ("badsum.step", ZstdRawFrame.base64(step, corruptingChecksum: true)),
            ("junk.step", "!!not base64!!"),
            ("short.step", ZstdRawFrame.encode(step).prefix(40).base64EncodedString()),
        ]
        let models = embedded.map { stored($0.0) }
        let (h, node, _) = try board([part("U1", models: models)], embedded: embedded)
        let lines = warnings(try await go(h, [node]), node)
        #expect(lines == ["3 models couldn't be read: badsum.step (it is damaged), junk.step (it is damaged), short.step (it is damaged)."])
    }

    @Test func twoNodesReadOneStoredModelOnce() async throws {
        let step = try await ComponentFixtures.step(kernel, scaledBy: 1.37)
        let base64 = ZstdRawFrame.base64(step)
        let hash = ImageHash(of: Data(base64.utf8)).hex
        let (h, first, _) = try board([part("U1", models: [stored("m.step")])], embedded: [("m.step", base64)])
        let report = try await go(h, [first])
        #expect(report.isOK(first), "\(String(describing: report.state(first)))")
        let (h2, second, _) = try board([part("U9", models: [stored("m.step")])], embedded: [("m.step", base64)])
        let again = try await go(h2, [second])
        #expect(solids(again, second).count == 1)
        #expect(await ComponentModelCache.shared.reads(containing: hash) == 1)
    }

    @Test func oneBoardLevelModelNamedByTwoFootprintsIsReadOnceAndHashedOnce() async throws {
        let step = try await ComponentFixtures.step(kernel, scaledBy: 1.53)
        let base64 = ZstdRawFrame.base64(step)
        let hash = ImageHash(ofUTF8: base64).hex
        let parts = [part("U1", models: [stored("m.step")]), part("U2", x: 60, models: [stored("m.step")])]
        let (h, node, text) = try board(parts, embedded: [("m.step", base64)])
        let cache = KiCadBoardCache()
        for _ in 0..<2 {
            let report = try await KiCadBoardCache.$current.withValue(cache) { try await go(h, [node]) }
            #expect(solids(report, node).count == 2)
        }
        #expect(await ComponentModelCache.shared.reads(containing: hash) == 1)
        // The parsed board is kept between evaluations, with its hash: the second evaluation hashed nothing.
        let file = folder.url.appending(path: "board.kicad_pcb")
        let kept = try await cache.board(for: ImageResolver.stamp(ofFileAt: file.path(percentEncoded: false))) {
            try ImportKiCadBoardNode.parse(Data(text.utf8))
        }
        #expect(kept.storedHashes.computed == 1)
    }

    @Test func aHashIsMadeOncePerOwnerAndName() {
        let hashes = StoredModelHashes()
        let file = EmbeddedFile(name: "m.step", base64: "QUJD")
        let first = hashes.hash(of: file, owner: nil)
        #expect(hashes.hash(of: file, owner: nil) == first)
        #expect(hashes.computed == 1)
        #expect(hashes.hash(of: file, owner: 3) == first)
        #expect(hashes.computed == 2)
        #expect(first == ImageHash(of: Data("QUJD".utf8)))
    }

    @Test func aWrappedFrameWithBarsAcrossLinesReads() async throws {
        let step = try await ComponentFixtures.step(kernel, scaledBy: 1.61)
        let (h, node, _) = try board([part("U1", models: [stored("m.step")])],
                                     embedded: [("m.step", ZstdRawFrame.base64(step, wrapped: true))])
        let report = try await go(h, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(warnings(report, node).isEmpty)
        #expect(solids(report, node).count == 1)
    }

    @Test func tooLargeAndDictionaryFramesSaySo() async throws {
        let step = try await ComponentFixtures.step(kernel)
        let bigText = String(repeating: "AAAA", count: 6_000_000) // 18 MB of bytes, over an IDF's 16 MB
        let embedded = [
            ("huge.idf", bigText),
            ("claims.step", ZstdRawFrame.base64(step, claiming: 0x7FFF_FFFF)),
            ("dict.step", ZstdRawFrame.base64(step, dictionary: 7)),
        ]
        let (h, node, _) = try board([part("U1", models: embedded.map { stored($0.0) })], embedded: embedded)
        let lines = warnings(try await go(h, [node]), node)
        let sentence = "3 models couldn't be read: huge.idf (it is larger than 16 MB), claims.step (it is larger than 256 MB), "
            + "dict.step (it uses a zstd dictionary)."
        #expect(lines == [sentence])
    }

    @Test func everyFootprintHasItsIdentityWhenParsed() throws {
        let parts = [part("U1", models: []), part("U1", x: 50, models: [])]
        let parsed = try ImportKiCadBoardNode.parse(Data(KiCadBoardText.rectangle(parts: parts).utf8))
        #expect(parsed.board.footprints.allSatisfy { !$0.identity.isEmpty })
        #expect(Set(parsed.board.footprints.map(\.identity)).count == 2)
    }

    @Test func componentsOffDecodesNothing() async throws {
        let step = try await ComponentFixtures.step(kernel, scaledBy: 1.41)
        let base64 = ZstdRawFrame.base64(step)
        let hash = ImageHash(of: Data(base64.utf8)).hex
        let (h, node, _) = try board([part("U1", models: [stored("m.step")])], embedded: [("m.step", base64)],
                                     values: ["components": .bool(false)])
        let report = try await go(h, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(solids(report, node).isEmpty)
        #expect(await ComponentModelCache.shared.reads(containing: hash) == 0)
    }
}
#endif
