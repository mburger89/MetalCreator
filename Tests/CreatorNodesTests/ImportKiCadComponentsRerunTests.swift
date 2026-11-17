#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes
@testable import CreatorOCCT

/// The components through one persistent Evaluator, and the finer points of reading, placing and naming (KiCad import spec, KI-2).
struct ImportKiCadComponentsRerunTests {
    let folder = TempFolderForNodes()
    let kernel = OCCTKernel()
    typealias Part = KiCadBoardText.Part
    typealias Model = KiCadBoardText.Model

    var key: String { folder.url.lastPathComponent }
    var home: String { folder.url.appending(path: "home").path(percentEncoded: false) }
    var environment: BoardComponents.Environment { BoardComponents.Environment(variables: [:], home: home) }

    func part(_ reference: String, x: Double = 30, y: Double = 20, models: [Model] = [], angle: Double = 0, back: Bool = false) -> Part {
        Part(reference: reference, x: x, y: y, library: "Parts:\(reference)", angle: angle, back: back, hasPad: false, models: models)
    }

    func model(_ name: String = "l.step", offset: (Double, Double, Double) = (0, 0, 0),
               rotate: (Double, Double, Double) = (0, 0, 0)) -> Model {
        Model(path: "${KIPRJMOD}/models/\(name)", offset: offset, rotate: rotate)
    }

    func boardNode(_ parts: [Part], in h: inout Harness, file name: String = "board.kicad_pcb",
                   _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
        let file = try folder.write(Data(KiCadBoardText.rectangle(parts: parts).utf8), to: name)
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        return h.add(ImportKiCadBoardNode.self, values.merging([NodeSetting.pcbFile: .pcbFile(reference)]) { _, new in new })
    }

    func evaluate(_ evaluator: Evaluator, _ graph: Graph, _ demand: [Node]) async throws -> EvaluationReport {
        let environment = environment
        return try await BoardComponents.$environment.withValue(environment) {
            try await evaluator.evaluate(graph, demand: Set(demand.map(\.id)), images: ImageResolver())
        }
    }

    func width(_ report: EvaluationReport, _ node: Node) throws -> Double {
        let solid = try #require(report.value(node, "components")?.solids?.first)
        return solid.bounds.max.x - solid.bounds.min.x
    }

    @Test func aPersistentEvaluatorRerunsOnlyWhenAFileChanges() async throws {
        let modelFile = try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        var h = Harness()
        let board = try boardNode([part("U1", models: [model()])], in: &h)
        let output = h.add(OutputNode.self, output: true)
        h.wire(board, "components", to: output, "solid")
        let number = h.add(NumberNode.self, ["value": .number(1)])
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)

        let first = try await evaluate(evaluator, h.graph, [output, number])
        #expect(first.evaluatedNodes.contains(board.id))
        let narrow = try width(first, board)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        // (a) Nothing changed: the node's result is reused and nothing is read.
        let second = try await evaluate(evaluator, h.graph, [output, number])
        #expect(!second.evaluatedNodes.contains(board.id))
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        // (b) Only the model rewritten, twice as large: the node runs again and the component is twice as wide.
        try await ComponentFixtures.step(kernel, scaledBy: 2).write(to: modelFile)
        try folder.touch(modelFile, Date(timeIntervalSinceNow: 60))
        let third = try await evaluate(evaluator, h.graph, [output, number])
        #expect(third.evaluatedNodes.contains(board.id) && third.evaluatedNodes.contains(output.id))
        #expect(abs(try width(third, board) - 2 * narrow) < 1e-6)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 2)

        // (c) The model deleted.
        try FileManager.default.removeItem(at: modelFile)
        let fourth = try await evaluate(evaluator, h.graph, [output, number])
        #expect(fourth.evaluatedNodes.contains(board.id))
        #expect(fourth.warning(board)?.contains("1 model wasn't found") == true)
        #expect(fourth.value(board, "components")?.items.isEmpty == true)

        // (d) The model written back.
        try await ComponentFixtures.step(kernel).write(to: modelFile)
        try folder.touch(modelFile, Date(timeIntervalSinceNow: 120))
        let fifth = try await evaluate(evaluator, h.graph, [output, number])
        #expect(fifth.evaluatedNodes.contains(board.id))
        #expect(abs(try width(fifth, board) - narrow) < 1e-6)
        let readsBefore = await ComponentModelCache.shared.reads(containing: key)

        // (e) An unrelated node edited: the import does not run again and reads nothing.
        h.set(number, "value", .number(2))
        let sixth = try await evaluate(evaluator, h.graph, [output, number])
        #expect(sixth.evaluatedNodes.contains(number.id) && !sixth.evaluatedNodes.contains(board.id))
        #expect(await ComponentModelCache.shared.reads(containing: key) == readsBefore)
    }

    @Test func twoImportNodesOnOneBoardReadEachModelOnce() async throws {
        try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        var h = Harness()
        let parts = [part("U1", models: [model()])]
        let first = try boardNode(parts, in: &h)
        let second = try boardNode(parts, in: &h)
        let report = try await evaluate(Evaluator(registry: BuiltInNodes.registry, kernel: kernel), h.graph, [first, second])
        #expect(report.isOK(first) && report.isOK(second))
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)
        let tags = [first, second].map { node in
            Set(report.value(node, "components")?.solids?.first?.topology.faces.flatMap(\.tags).map(\.node) ?? [])
        }
        #expect(tags[0].isDisjoint(with: tags[1]) && !tags[0].isEmpty)
        #expect(tags.allSatisfy { !$0.contains(ComponentModelCache.sentinel) })
    }

    @Test func aPathVariableFromKiCadsSettingsFindsTheModel() async throws {
        let data = try await ComponentFixtures.step(kernel)
        try folder.write(data, to: "shared/l.step")
        let settingsFolder = KiCadPlatform.current.settingsFolder(version: "10.0", environment: [:], home: home)
        let shared = folder.url.appending(path: "shared").path(percentEncoded: false)
        let json = "{\"environment\": {\"vars\": {\"MYMODELS\": \"\(shared)\"}}}"
        let settingsFile = try folder.write(Data(json.utf8), to: "home" + settingsFolder.dropFirst(home.count) + "/kicad_common.json")
        var h = Harness()
        let node = try boardNode([part("U1", models: [Model(path: "${MYMODELS}/l.step")])], in: &h)
        let report = try await evaluate(Evaluator(registry: BuiltInNodes.registry, kernel: kernel), h.graph, [node])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(report.value(node, "components")?.solids?.count == 1)
        let dependencies = try #require(report.results[node.id]).dependencies.map(\.path)
        #expect(dependencies.contains { URL(filePath: $0).resolvingSymlinksInPath() == settingsFile.resolvingSymlinksInPath() })
        #expect(dependencies.contains { $0.hasSuffix("shared/l.step") })
    }

    @Test func aTiltedPlacementCarriesTheComponentWithTheBoard() async throws {
        try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        let tilted = Plane(origin: Vector3(5, -3, 7), normal: Vector3(1, 2, 2), xAxis: Vector3(0, 0, 1))
        var h = Harness()
        let footprints = [part("U1", x: 40, y: 25, models: [model(offset: (1.5, -2, 0.7), rotate: (20, 35, 50))], angle: 30, back: true)]
        let node = try boardNode(footprints, in: &h, ["placement": .plane(tilted)])
        let report = try await evaluate(Evaluator(registry: BuiltInNodes.registry, kernel: kernel), h.graph, [node])
        let solid = try #require(report.value(node, "components")?.solids?.first)

        let text = KiCadBoardText.rectangle(parts: footprints)
        let parsed = try ImportKiCadBoardNode.parse(Data(text.utf8))
        let box = try #require(BoardFrame.bounds(of: parsed.outline.outer))
        let origin = Vector2((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        let footprint = parsed.board.footprints[0]
        let chain = ModelPlacement.frame(of: footprint.models[0], on: footprint, boardOrigin: origin, thickness: 1.6)
        let normal = try #require(tilted.normal.normalized)
        let across = try #require((tilted.xAxis - normal * tilted.xAxis.dot(normal)).normalized)
        let up = normal.cross(across)
        let world = ComponentFixtures.corners.map { corner -> Vector3 in
            let local = chain.apply(corner)
            return tilted.origin + across * local.x + up * local.y + normal * local.z
        }
        let low = world.dropFirst().reduce(world[0]) { Vector3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
        let high = world.dropFirst().reduce(world[0]) { Vector3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
        #expect(isClose(solid.bounds.min, low, tolerance: 1e-5), "\(solid.bounds.min) vs \(low)")
        #expect(isClose(solid.bounds.max, high, tolerance: 1e-5), "\(solid.bounds.max) vs \(high)")
    }

    @Test func problemsAreNamedInTheOrderOfTheFootprints() async throws {
        try folder.write(TestImages.pngHeader(claiming: 4, 4), to: "models/bad1.step")
        try folder.write(TestImages.pngHeader(claiming: 4, 4), to: "models/bad2.step")
        var h = Harness()
        let node = try boardNode([part("C10", models: [model("bad2.step")]), part("C2", models: [model("bad1.step")])], in: &h)
        let report = try await evaluate(Evaluator(registry: BuiltInNodes.registry, kernel: kernel), h.graph, [node])
        #expect(report.warning(node) == "2 models couldn't be read: bad1.step (the file isn't a STEP model), "
            + "bad2.step (the file isn't a STEP model).")
    }

    @Test func aDeletedFootprintsFacePickSaysItIsGone() async throws {
        try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        var h = Harness()
        let node = try boardNode([part("J1", models: [model()]), part("R1", x: 70, y: 50, models: [model()])], in: &h)
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        let before = try await evaluate(evaluator, h.graph, [node])
        let item = KiCadKey.item(for: "fp:J1")
        let solids = try #require(before.value(node, "components")?.solids)
        let j1 = try #require(solids.first { $0.topology.faces.contains { face in face.tags.contains { $0.item == item } } })
        let face = try #require(j1.topology.faces.first { ($0.normal?.z ?? 0) > 0.9 })
        let pick = FacePick(tags: face.tags, normal: face.normal, centroid: face.centroid)
        let plane = h.add(PlaneFromFaceNode.self, [NodeSetting.face: .facePick(pick)])
        h.wire(node, "components", to: plane, "solid")
        // J1 is deleted from the board; R1's component is all that is left to pick on.
        let file = folder.url.appending(path: "board.kicad_pcb")
        try Data(KiCadBoardText.rectangle(parts: [part("R1", x: 70, y: 50, models: [model()])]).utf8).write(to: file)
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
        let after = try await evaluate(evaluator, h.graph, [plane])
        let message = after.error(plane) ?? after.warning(plane) ?? ""
        #expect(message.contains(InstancePath.importedFeatureVanished), "\(message)")
    }
}
#endif
