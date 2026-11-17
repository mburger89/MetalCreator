#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes
@testable import CreatorOCCT

/// The Import KiCad Board node's components (KiCad import spec, KI-2) through the real evaluator on OpenCascade.
struct ImportKiCadComponentsTests {
    let folder = TempFolderForNodes()
    let kernel = OCCTKernel()
    typealias Part = KiCadBoardText.Part
    typealias Model = KiCadBoardText.Model

    var key: String { folder.url.lastPathComponent }

    func part(_ reference: String, x: Double = 30, y: Double = 20, models: [Model] = [], angle: Double = 0, back: Bool = false) -> Part {
        Part(reference: reference, x: x, y: y, library: "Parts:\(reference)", angle: angle, back: back, hasPad: false, models: models)
    }

    func model(_ name: String = "l.step", offset: (Double, Double, Double) = (0, 0, 0), scale: (Double, Double, Double) = (1, 1, 1),
               rotate: (Double, Double, Double) = (0, 0, 0)) -> Model {
        Model(path: "${KIPRJMOD}/models/\(name)", offset: offset, scale: scale, rotate: rotate)
    }

    /// No variables but the board's own and settings under a temporary home, so the person's KiCad installation never matters.
    var environment: BoardComponents.Environment {
        BoardComponents.Environment(variables: [:], home: folder.url.appending(path: "home").path(percentEncoded: false))
    }

    func go(_ h: Harness, _ node: Node) async throws -> EvaluationReport {
        let environment = environment
        return try await BoardComponents.$environment.withValue(environment) { try await h.run([node], kernel: kernel) }
    }

    /// The warning's sentences, one per line (the evaluator sorts and joins them with newlines).
    func warnings(_ report: EvaluationReport, _ node: Node) -> [String] {
        report.warning(node)?.split(separator: "\n").map(String.init) ?? []
    }

    func write(_ data: Data, _ name: String) throws {
        try folder.write(data, to: "models/\(name)")
    }

    func board(_ parts: [Part], _ values: [SocketName: ConstantValue] = [:], thickness: Double = 1.6) throws -> (Harness, Node, String) {
        let text = KiCadBoardText.rectangle(parts: parts, thickness: thickness)
        let file = try folder.write(Data(text.utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, values.merging([NodeSetting.pcbFile: .pcbFile(reference)]) { _, new in new })
        return (h, node, text)
    }

    func components(_ report: EvaluationReport, _ node: Node) -> [Solid] {
        report.value(node, "components")?.solids ?? []
    }

    /// Where the hand chain of `ModelPlacement` puts the model's corners (scaled first) for footprint `index` of `text`.
    func expectedBox(text: String, footprint index: Int = 0, model modelIndex: Int = 0,
                     thickness: Double = 1.6) throws -> (Vector3, Vector3) {
        let parsed = try ImportKiCadBoardNode.parse(Data(text.utf8))
        let box = try #require(BoardFrame.bounds(of: parsed.outline.outer))
        let origin = Vector2((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        let footprint = parsed.board.footprints[index]
        let reference = footprint.models[modelIndex]
        let frame = ModelPlacement.frame(of: reference, on: footprint, boardOrigin: origin, thickness: thickness)
        let points = ComponentFixtures.corners.map {
            frame.apply(Vector3($0.x * reference.scale.x, $0.y * reference.scale.y, $0.z * reference.scale.z))
        }
        let low = points.dropFirst().reduce(points[0]) { Vector3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
        let high = points.dropFirst().reduce(points[0]) { Vector3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
        return (low, high)
    }

    func expectBounds(_ solid: Solid, _ expected: (Vector3, Vector3), tolerance: Double = 1e-6) {
        #expect(isClose(solid.bounds.min, expected.0, tolerance: tolerance), "min \(solid.bounds.min) vs \(expected.0)")
        #expect(isClose(solid.bounds.max, expected.1, tolerance: tolerance), "max \(solid.bounds.max) vs \(expected.1)")
    }

    @Test func placesTopComponent() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let (h, node, text) = try board([part("U1", models: [model(offset: (1, 2, 0.5))])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let solid = try #require(components(report, node).first)
        expectBounds(solid, try expectedBox(text: text))
        // The model sits on the board's top face (z = 1.6) plus its own offset.
        #expect(abs(solid.bounds.min.z - 2.1) < 1e-6)
        let item = KiCadKey.item(for: "fp:U1")
        #expect(solid.topology.faces.count == 8)
        #expect(solid.topology.faces.allSatisfy { face in
            face.tags.allSatisfy { $0.item == item && $0.node.isInstanceQualified }
        })
        let result = try #require(report.results[node.id])
        #expect(result.dependencies.contains { $0.path.hasSuffix("models/l.step") })
        let facts = Dictionary(uniqueKeysWithValues: (result.facts).map { ($0.label, $0.value) })
        #expect(facts["Components"] == "1 placed, 1 as solids, 0 as meshes, 0 without a 3D model")
    }

    @Test func placesBackComponentRotated() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let rotated = model(offset: (1.5, -2, 0.7), rotate: (20, 35, 50))
        let (h, node, text) = try board([part("U1", x: 40, y: 25, models: [rotated], angle: 30, back: true)])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let solid = try #require(components(report, node).first)
        expectBounds(solid, try expectedBox(text: text))
    }

    @Test func scalesBeforePlacing() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let (h, node, text) = try board([part("U1", models: [model(scale: (2, 1, 1))])])
        let report = try await go(h, node)
        let solid = try #require(components(report, node).first)
        expectBounds(solid, try expectedBox(text: text))
        #expect(abs((solid.bounds.max.x - solid.bounds.min.x) - 12) < 1e-6)
    }

    @Test func readsCompressedStep() async throws {
        try write(ComponentFixtures.gzip(try await ComponentFixtures.step(kernel)), "l.stp.gz")
        let (h, node, text) = try board([part("U1", models: [model("l.stp.gz")])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        expectBounds(try #require(components(report, node).first), try expectedBox(text: text))
    }

    @Test func readsIges() async throws {
        try write(try await ComponentFixtures.iges(kernel), "l.igs")
        let (h, node, text) = try board([part("U1", models: [model("l.igs")])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        expectBounds(try #require(components(report, node).first), try expectedBox(text: text), tolerance: 1e-5)
    }

    @Test func twoModelsOneCompound() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let both = [model(), model(offset: (10, 0, 0))]
        let (h, node, _) = try board([part("U1", models: both)])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let all = components(report, node)
        #expect(all.count == 1)
        let solid = try #require(all.first)
        let faces = solid.topology.faces.compactMap { face in
            face.tags.compactMap { tag -> Int? in
                if case .imported(let number) = tag.role { number } else { nil }
            }.first
        }
        #expect(faces.count == 16 && Set(faces).count == 16)
        #expect(faces.filter { $0 >> 32 == 0 }.count == 8)
        #expect(Set(faces.filter { $0 >> 32 == 1 }.map { $0 - (1 << 32) }) == Set(faces.filter { $0 >> 32 == 0 }))
        #expect(abs((solid.bounds.max.x - solid.bounds.min.x) - 16) < 1e-6)
    }

    @Test func sixtyCopiesReadOnce() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let parts = (0..<60).map { part("C\($0 + 1)", x: 5 + Double($0 % 10) * 9, y: 5 + Double($0 / 10) * 11,
                                        models: [model(scale: (1.5, 1.5, 1.5))]) }
        let (h, node, _) = try board(parts)
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(components(report, node).count == 60)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)
        #expect(await ComponentModelCache.shared.scales(containing: key) == 1)
        // Natural order: C1, C2, … C60, so the third is C3.
        let third = KiCadKey.item(for: "fp:C3")
        #expect(components(report, node)[2].topology.faces.allSatisfy { $0.tags.allSatisfy { $0.item == third } })
    }

    @Test func warnsMissingAndUnreadable() async throws {
        try write(TestImages.pngHeader(claiming: 4, 4), "bad.step")
        let parts = [part("A1", models: [model("gone.step")]), part("B1", models: [model("bad.step")])]
        let (h, node, _) = try board(parts)
        let report = try await go(h, node)
        let lines = warnings(report, node)
        #expect(lines.contains("1 model wasn't found: ${KIPRJMOD}/models/gone.step."))
        #expect(lines.contains("1 model couldn't be read: bad.step (the file isn't a STEP model)."))
        #expect(lines.count == 2)
        #expect(components(report, node).isEmpty)
        let facts = Dictionary(uniqueKeysWithValues: (try #require(report.results[node.id]).facts).map { ($0.label, $0.value) })
        #expect(facts["Components"] == "2 placed, 0 as solids, 0 as meshes, 2 without a 3D model")
    }

    @Test func warnsNoModel() async throws {
        let (h, node, _) = try board([part("H1"), part("H2", x: 50)])
        let report = try await go(h, node)
        #expect(warnings(report, node) == ["2 components have no 3D model: H1, H2."])
        let (h1, one, _) = try board([part("H1")])
        #expect(warnings(try await go(h1, one), one) == ["1 component has no 3D model: H1."])
    }

    @Test func componentsOffReadsNothing() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let (h, node, _) = try board([part("U1", models: [model()]), part("H1")], ["components": .bool(false)])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(components(report, node).isEmpty)
        #expect(report.results[node.id]?.dependencies.isEmpty == true)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 0)
    }

    @Test func hiddenModelSkipped() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        var hidden = model()
        hidden.hidden = true
        let (h, node, _) = try board([part("U1", models: [hidden])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let facts = Dictionary(uniqueKeysWithValues: (try #require(report.results[node.id]).facts).map { ($0.label, $0.value) })
        #expect(facts["Components"] == "1 placed, 0 as solids, 0 as meshes, 0 without a 3D model")
        #expect(await ComponentModelCache.shared.reads(containing: key) == 0)
    }

    @Test func wrlTwinReadAsStep() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        let (h, node, text) = try board([part("U1", models: [model("l.wrl")])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        expectBounds(try #require(components(report, node).first), try expectedBox(text: text))
    }

    @Test func storedModelNotInTheBoardIsNotFound() async throws {
        let embedded = Model(path: "kicad-embed://inside.step")
        let (h, node, _) = try board([part("U2", x: 60, models: [embedded])])
        let lines = warnings(try await go(h, node), node)
        #expect(lines == ["1 model wasn't found: kicad-embed://inside.step."])
    }

    @Test func modelEditedOnDiskReruns() async throws {
        let file = try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        let (h, node, text) = try board([part("U1", models: [model()]), part("U2", x: 70, y: 60)])
        let first = try #require(components(try await go(h, node), node).first)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        // An unrelated edit (the other part moves): the model is not read again.
        let moved = KiCadBoardText.rectangle(parts: [part("U1", models: [model()]), part("U2", x: 75, y: 60)])
        try folder.write(Data(moved.utf8), to: "board.kicad_pcb")
        _ = try await go(h, node)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        // The model rewritten twice as large: the next evaluation's component is larger.
        try Data(try await ComponentFixtures.step(kernel, scaledBy: 2)).write(to: file)
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
        let second = try #require(components(try await go(h, node), node).first)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 2)
        #expect(abs((second.bounds.max.x - second.bounds.min.x) - 2 * (first.bounds.max.x - first.bounds.min.x)) < 1e-6)
        _ = text
    }

    @Test func damagedCompressedStepIsOneWarning() async throws {
        var bytes = ComponentFixtures.gzip(try await ComponentFixtures.step(kernel))
        bytes[bytes.count - 6] ^= 0xFF
        try write(bytes, "l.stp.gz")
        let (h, node, _) = try board([part("U1", models: [model("l.stp.gz")])])
        let report = try await go(h, node)
        #expect(warnings(report, node) == ["1 model couldn't be read: l.stp.gz (the compressed file is damaged)."])
        #expect(report.value(node, "board")?.solids?.count == 1)
    }

    @Test func missingModelAppearing() async throws {
        let (h, node, _) = try board([part("U1", models: [model()])])
        let before = try await go(h, node)
        #expect(warnings(before, node) == ["1 model wasn't found: ${KIPRJMOD}/models/l.step."])
        #expect(components(before, node).isEmpty)
        let missing = try #require(before.results[node.id]).dependencies
        #expect(missing.contains { $0.path.hasSuffix("models/l.step") && $0.stamp == ImageResolver.stamp(ofFileAt: $0.path) })

        try write(try await ComponentFixtures.step(kernel), "l.step")
        let after = try await go(h, node)
        #expect(after.isOK(node), "\(String(describing: after.state(node)))")
        #expect(components(after, node).count == 1)
        let found = try #require(after.results[node.id]).dependencies.first { $0.path.hasSuffix("models/l.step") }
        if case .file = try #require(found).stamp {} else { Issue.record("the found file's stamp is a file's") }
    }
}

/// Without a kernel that reads models, a model is one warning and the board still builds.
struct ImportKiCadComponentsFakeKernelTests {
    let folder = TempFolderForNodes()

    @Test func fakeKernelCannotReadModels() async throws {
        try folder.write(Data("ISO-10303-21;\nHEADER;\n".utf8), to: "models/l.step")
        let part = KiCadBoardText.Part(reference: "U1", x: 30, y: 20, library: "Parts:U1", hasPad: false,
                                       models: [KiCadBoardText.Model(path: "${KIPRJMOD}/models/l.step")])
        let file = try folder.write(Data(KiCadBoardText.rectangle(parts: [part]).utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        let report = try await h.run([node])
        #expect(report.warning(node)?.split(separator: "\n").map(String.init)
            == ["1 model couldn't be read: l.step (reading 3D models isn't supported by this kernel yet)."])
        #expect(report.value(node, "board")?.solids?.count == 1)
        #expect(report.value(node, "components")?.items.isEmpty == true)
    }

    @Test func tooManyDistinctModelsRefuse() async throws {
        let parts = (0...10_000).map { index in
            KiCadBoardText.Part(reference: "U\(index)", x: 10, y: 10, library: "Parts:U", hasPad: false,
                                models: [KiCadBoardText.Model(path: "m\(index).step")])
        }
        let file = try folder.write(Data(KiCadBoardText.rectangle(parts: parts).utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        #expect(try await h.run([node]).error(node) == "This board names more than 10,000 different 3D models.")
    }
}
#endif
