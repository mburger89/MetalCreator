import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorPCB
import Foundation
import Synchronization
import Testing
@testable import CreatorNodes

/// The reasons a reader's refusal gives for a model that couldn't be read (KiCad import spec, KI-3).
struct ModelReasonTests {
    @Test func readerSentencesBecomePhrases() {
        #expect(ModelFiles.readerReason("This VRML file uses a shape before it is defined.") == "it uses a shape before it is defined")
        #expect(ModelFiles.readerReason("This X3D file is damaged.") == "it is damaged")
        #expect(ModelFiles.readerReason("This IDF file is a whole board, not a part.") == "it is a whole board, not a part")
        #expect(ModelFiles.readerReason("This VRML file's units are odd.") == "its units are odd")
        #expect(ModelFiles.readerReason("This X3D file's scene is empty.") == "its scene is empty")
        #expect(ModelFiles.readerReason("Something else entirely.") == "something else entirely")
        #expect(ModelFiles.readerReason("This file isn't a VRML 1 or VRML 2 file.") == "the file isn't a VRML model")
        #expect(ModelFiles.readerReason("This file isn't an X3D file.") == "the file isn't an X3D model")
        #expect(ModelFiles.meshReason(.vrml("This file isn't a VRML 1 or VRML 2 file.")) == "the file isn't a VRML model")
        #expect(ModelFiles.meshReason(.x3d("This file isn't an X3D file.")) == "the file isn't an X3D model")
    }

    @Test func meshProblemsReadInKiCadsWords() {
        #expect(ModelFiles.meshReason(.noTriangles) == "it has no triangles")
        #expect(ModelFiles.meshReason(.tooManyTriangles(11_000_000)) == "it has more than 10,000,000 triangles")
        #expect(ModelFiles.meshReason(.overTriangleLimit) == "it has more than 10,000,000 triangles")
        #expect(ModelFiles.meshReason(.tooLarge) == "it is larger than 64 MB")
        #expect(ModelFiles.meshReason(.vrml("This VRML file ends early.")) == "it ends early")
        #expect(ModelFiles.meshReason(.malformedModel("it stops inside a tag.")) == "it stops inside a tag")
        #expect(ModelFiles.meshReason(.x3d("This X3D file nests too deeply.")) == "it nests too deeply")
    }
}

#if canImport(CreatorOCCT)
@testable import CreatorOCCT

/// VRML, compressed VRML, X3D and IDF components through the real evaluator on OpenCascade (KiCad import spec, KI-3).
struct ImportKiCadMeshComponentsTests {
    let folder = TempFolderForNodes()
    let kernel = OCCTKernel()
    typealias Part = KiCadBoardText.Part
    typealias Model = KiCadBoardText.Model

    var key: String { folder.url.lastPathComponent }
    var environment: BoardComponents.Environment {
        BoardComponents.Environment(variables: [:], home: folder.url.appending(path: "home").path(percentEncoded: false))
    }

    func part(_ reference: String, x: Double = 30, y: Double = 20, models: [Model] = [], angle: Double = 0, back: Bool = false) -> Part {
        Part(reference: reference, x: x, y: y, library: "Parts:\(reference)", angle: angle, back: back, hasPad: false, models: models)
    }

    func model(_ name: String, offset: (Double, Double, Double) = (0, 0, 0), scale: (Double, Double, Double) = (1, 1, 1),
               rotate: (Double, Double, Double) = (0, 0, 0)) -> Model {
        Model(path: "${KIPRJMOD}/models/\(name)", offset: offset, scale: scale, rotate: rotate)
    }

    func write(_ data: Data, _ name: String) throws { try folder.write(data, to: "models/\(name)") }
    func write(_ text: String, _ name: String) throws { try write(Data(text.utf8), name) }

    func board(_ parts: [Part], _ values: [SocketName: ConstantValue] = [:]) throws -> (Harness, Node, String) {
        let text = KiCadBoardText.rectangle(parts: parts)
        let file = try folder.write(Data(text.utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, values.merging([NodeSetting.pcbFile: .pcbFile(reference)]) { _, new in new })
        return (h, node, text)
    }

    func go(_ h: Harness, _ node: Node, limits: MeshLimits = MeshLimits()) async throws -> EvaluationReport {
        let environment = environment
        return try await BoardComponents.$meshLimits.withValue(limits) {
            try await BoardComponents.$environment.withValue(environment) { try await h.run([node], kernel: kernel) }
        }
    }

    func warnings(_ report: EvaluationReport, _ node: Node) -> [String] {
        report.warning(node)?.split(separator: "\n").map(String.init) ?? []
    }

    func meshes(_ report: EvaluationReport, _ node: Node) -> [TriangleMesh] {
        (report.value(node, "component meshes")?.items ?? []).compactMap { item in
            if case .mesh(let payload) = item { payload as? TriangleMesh } else { nil }
        }
    }

    func solids(_ report: EvaluationReport, _ node: Node) -> [Solid] { report.value(node, "components")?.solids ?? [] }

    func facts(_ report: EvaluationReport, _ node: Node) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try #require(report.results[node.id]).facts.map { ($0.label, $0.value) })
    }

    // MARK: Tests

    @Test func vrmlLandsWhereTheStepOfTheSamePartLands() async throws {
        let rotated = (offset: (1.5, -2.0, 0.7), rotate: (20.0, 35.0, 50.0))
        try write(try await ComponentFixtures.step(kernel), "l.step")
        try write(Self.vrml(), "v.wrl")
        let placed = { (name: String) in
            self.part("U1", x: 40, y: 25, models: [self.model(name, offset: rotated.offset, rotate: rotated.rotate)], angle: 30, back: true)
        }
        let (stepH, stepNode, text) = try board([placed("l.step")])
        let stepReport = try await go(stepH, stepNode)
        let solid = try #require(solids(stepReport, stepNode).first)
        let (vrmlH, vrmlNode, _) = try board([placed("v.wrl")])
        let vrmlReport = try await go(vrmlH, vrmlNode)
        #expect(vrmlReport.isOK(vrmlNode), "\(String(describing: vrmlReport.state(vrmlNode)))")
        #expect(solids(vrmlReport, vrmlNode).isEmpty)
        let mesh = try #require(meshes(vrmlReport, vrmlNode).first)
        try expect(mesh.bounds, try expectedBox(text: text))
        try expect(mesh.bounds, (solid.bounds.min, solid.bounds.max))
        // A turn, not a mirror: the block is 6 x 5 x 3 less its 4 x 3 x 3 notch, 54 cubic millimetres.
        #expect(abs(mesh.signedVolume - 54) < 1e-3, "\(mesh.signedVolume)")
    }

    @Test func compressedVrmlAndX3dPlaceAsTheStepDoes() async throws {
        try write(ComponentFixtures.gzip(Data(Self.vrml().utf8)), "v.wrz")
        try write(Self.x3d(), "x.x3d")
        for name in ["v.wrz", "x.x3d"] {
            let (h, node, text) = try board([part("U1", models: [model(name, offset: (1, 2, 0.5), scale: (2, 1, 1))])])
            let report = try await go(h, node)
            #expect(report.isOK(node), "\(name): \(String(describing: report.state(node)))")
            try expect(try #require(meshes(report, node).first).bounds, try expectedBox(text: text, scale: (2, 1, 1)))
        }
    }

    @Test func millimetreVrmlTakesNoUnitFactor() async throws {
        try write(Self.vrml(scale: "2 2 2", unit: 1), "mm.wrl")
        let (h, node, _) = try board([part("U1", models: [model("mm.wrl")])])
        let report = try await go(h, node)
        let mesh = try #require(meshes(report, node).first)
        let box = try #require(mesh.bounds)
        // The file's own scale (2) is the Transform's; the points are millimetres, so the block is 2 x 6 mm wide.
        #expect(abs((box.max.x - box.min.x) - 12) < 1e-4)
    }

    @Test func idfRectangleIsAnExtrudedSolidWithImportedTags() async throws {
        try write(Self.idf(), "r.idf")
        let corners = [0.0, 4.0].flatMap { x in [0.0, 2.0].flatMap { y in [0.0, 5.0].map { Vector3(x, y, $0) } } }
        let (h, node, text) = try board([part("U1", models: [model("r.idf", offset: (1, 2, 0.5), rotate: (0, 0, 30))])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        let solid = try #require(solids(report, node).first)
        try expect(solid.bounds, try expectedBox(text: text, corners: corners), tolerance: 1e-6)
        #expect(solid.topology.faces.count == 6)
        let item = KiCadKey.item(for: "fp:U1")
        var numbers = Set<Int>()
        for face in solid.topology.faces {
            #expect(face.tags.count == 1)
            for tag in face.tags {
                #expect(tag.item == item && tag.node.isInstanceQualified)
                if case .imported(let number) = tag.role { numbers.insert(number) } else { Issue.record("not an imported tag") }
            }
        }
        #expect(numbers == Set(0..<6))
        #expect(try facts(report, node)["Components"] == "1 placed, 1 as solids, 0 as meshes, 0 without a 3D model")
    }

    @Test func aWholeBoardIdfIsRefused() async throws {
        try write(".HEADER\nBOARD_FILE 3.0 \"x\" 2026/11/17.00:00:00 1\n.END_HEADER\n.BOARD_OUTLINE ECAD\n10\n0 0 0 0\n", "b.idf")
        let (h, node, _) = try board([part("U1", models: [model("b.idf")])])
        let report = try await go(h, node)
        #expect(warnings(report, node) == ["1 model couldn't be read: b.idf (it is a whole board, not a part)."])
    }

    @Test func aFootprintWithStepAndVrmlGivesOneSolidAndOneMesh() async throws {
        try write(try await ComponentFixtures.step(kernel), "l.step")
        try write(Self.vrml(), "v.wrl")
        let (h, node, text) = try board([part("U1", models: [model("l.step"), model("v.wrl", offset: (10, 0, 0))])])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(report.warning(node) == nil)
        #expect(solids(report, node).count == 1)
        #expect(meshes(report, node).count == 1)
        try expect(meshes(report, node).first?.bounds, try expectedBox(text: text, modelIndex: 1))
        #expect(try facts(report, node)["Components"] == "1 placed, 1 as solids, 1 as meshes, 0 without a 3D model")
    }

    @Test func aFootprintsVrmlModelsJoinIntoOneMesh() async throws {
        try write(Self.vrml(), "v.wrl")
        let (h, node, _) = try board([part("U1", models: [model("v.wrl"), model("v.wrl", offset: (10, 0, 0))])])
        let report = try await go(h, node)
        let all = meshes(report, node)
        #expect(all.count == 1)
        let box = try #require(all.first?.bounds)
        #expect(abs((box.max.x - box.min.x) - 16) < 1e-4)
        #expect(all.first?.triangleCount == 2 * (4 + 4 + 12))
    }

    @Test func aSphereWarnsOncePerFile() async throws {
        try write(Self.vrml(extra: Self.sphere), "s.wrl")
        try write("#VRML V2.0 utf8\n" + Self.sphere, "only.wrl")
        let parts = [
            part("U1", models: [model("s.wrl")]), part("U2", x: 60, models: [model("s.wrl")]),
            part("U3", x: 80, models: [model("only.wrl")]),
        ]
        let (h, node, _) = try board(parts)
        let report = try await go(h, node)
        let lines = warnings(report, node)
        #expect(lines.filter { $0 == "s.wrl has shapes that aren't read (spheres, cylinders and the like)." }.count == 1)
        #expect(lines.filter { $0 == "only.wrl has shapes that aren't read (spheres, cylinders and the like)." }.count == 1)
        #expect(meshes(report, node).count == 2)
        #expect(try facts(report, node)["Components"] == "3 placed, 0 as solids, 2 as meshes, 1 without a 3D model")
    }

    @Test func aDamagedVrmlIsOneWarningWithTheReadersReason() async throws {
        try write("#VRML V2.0 utf8\nShape {", "bad.wrl")
        let (h, node, _) = try board([part("U1", models: [model("bad.wrl")])])
        let report = try await go(h, node)
        let lines = warnings(report, node)
        #expect(lines.count == 1 && lines[0].hasPrefix("1 model couldn't be read: bad.wrl (it ") && lines[0].hasSuffix(")."), "\(lines)")
        #expect(report.value(node, "board")?.solids?.count == 1)
        #expect(meshes(report, node).isEmpty)
    }

    @Test func aTruncatedX3dDoesNotSayItIsA3mf() async throws {
        try write("<?xml version=\"1.0\"?><X3D><Scene><Shape", "t.x3d")
        let (h, node, _) = try board([part("U1", models: [model("t.x3d")])])
        let lines = warnings(try await go(h, node), node)
        #expect(lines == ["1 model couldn't be read: t.x3d (it stops inside a tag)."], "\(lines)")
    }

    @Test func anOversizedIdfIsRefusedBeforeItIsRead() async throws {
        try write(Data(repeating: 0x20, count: (17 << 20)), "big.idf")
        let (h, node, _) = try board([part("U1", models: [model("big.idf")])])
        let lines = warnings(try await go(h, node), node)
        #expect(lines == ["1 model couldn't be read: big.idf (it is larger than 16 MB)."], "\(lines)")
    }

    @Test func anIdfSharedByTwoFootprintsIsReadOnce() async throws {
        try write(Self.idf(), "r.idf")
        let (h, node, _) = try board([part("U1", models: [model("r.idf")]), part("U2", x: 60, models: [model("r.idf")])])
        let report = try await go(h, node)
        #expect(solids(report, node).count == 2)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)
    }

    @Test func aFootprintsMeshesAreLimitedTogether() async throws {
        try write(Self.vrml(), "v.wrl")  // 20 triangles each
        let (h, node, _) = try board([part("U1", models: [model("v.wrl"), model("v.wrl")]), part("U2", x: 60, models: [model("v.wrl")])])
        let report = try await go(h, node, limits: MeshLimits(footprint: 30, board: 1_000))
        #expect(warnings(report, node) == ["U1's component meshes were left out: they have more than 30 triangles together."])
        #expect(meshes(report, node).count == 1)
        #expect(try facts(report, node)["Components"] == "2 placed, 0 as solids, 1 as meshes, 0 without a 3D model")
    }

    @Test func aBoardsMeshesAreLimitedInNaturalOrder() async throws {
        try write(Self.vrml(), "v.wrl")
        let parts = ["C10", "C2", "C1", "C3"].enumerated().map { part($1, x: 10 + Double($0) * 20, models: [model("v.wrl")]) }
        let (h, node, _) = try board(parts)
        let tight = MeshLimits(footprint: 1_000, board: 50)
        let report = try await go(h, node, limits: tight)
        // C1 and C2 fit (40 triangles); C3 and C10 are past the budget.
        #expect(warnings(report, node) == ["2 component meshes were left out: a board's meshes are limited to 50 triangles."])
        #expect(meshes(report, node).count == 2)
        let (single, one, _) = try board(Array(parts.prefix(3)))
        let alone = warnings(try await go(single, one, limits: tight), one)
        #expect(alone == ["1 component mesh was left out: a board's meshes are limited to 50 triangles."])
    }

    @Test func componentsOffReadsNothing() async throws {
        try write(Self.vrml(), "v.wrl")
        try write(Self.idf(), "r.idf")
        let (h, node, _) = try board([part("U1", models: [model("v.wrl"), model("r.idf")])], ["components": .bool(false)])
        let report = try await go(h, node)
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(meshes(report, node).isEmpty && solids(report, node).isEmpty)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 0)
    }

    @Test func aPersistentEvaluatorRerunsWhenTheVrmlChanges() async throws {
        let file = try folder.write(Data(Self.vrml().utf8), to: "models/v.wrl")
        let parts = [part("U1", models: [model("v.wrl")])]
        let boardFile = try folder.write(Data(KiCadBoardText.rectangle(parts: parts).utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: boardFile.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        let output = h.add(OutputNode.self, output: true)
        h.wire(node, "components", to: output, "solid")
        let number = h.add(NumberNode.self, ["value": .number(1)])
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        let run = { () async throws -> EvaluationReport in
            let environment = self.environment
            return try await BoardComponents.$environment.withValue(environment) {
                try await evaluator.evaluate(h.graph, demand: [node.id, output.id, number.id], images: ImageResolver())
            }
        }
        func width(_ report: EvaluationReport) throws -> Double {
            let box = try #require(meshes(report, node).first?.bounds)
            return box.max.x - box.min.x
        }
        let first = try await run()
        #expect(first.evaluatedNodes.contains(node.id))
        let narrow = try width(first)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        let second = try await run()
        #expect(!second.evaluatedNodes.contains(node.id))
        #expect(await ComponentModelCache.shared.reads(containing: key) == 1)

        try Data(Self.vrml(unit: 1.27).utf8).write(to: file)  // the same points over a smaller unit: twice as large
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
        let third = try await run()
        #expect(third.evaluatedNodes.contains(node.id))
        #expect(abs(try width(third) - 2 * narrow) < 1e-4)
        #expect(await ComponentModelCache.shared.reads(containing: key) == 2)
    }
}

extension ImportKiCadMeshComponentsTests {
    /// Where the hand chain of `ModelPlacement` puts `corners` (scaled first) for the first model of the first footprint of `text`.
    func expectedBox(text: String, corners: [Vector3] = ComponentFixtures.corners, modelIndex: Int = 0,
                     scale: (Double, Double, Double) = (1, 1, 1)) throws -> (Vector3, Vector3) {
        let parsed = try ImportKiCadBoardNode.parse(Data(text.utf8))
        let box = try #require(BoardFrame.bounds(of: parsed.outline.outer))
        let origin = Vector2((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2)
        let footprint = parsed.board.footprints[0]
        let frame = ModelPlacement.frame(of: footprint.models[modelIndex], on: footprint, boardOrigin: origin, thickness: 1.6)
        let points = corners.map { frame.apply(Vector3($0.x * scale.0, $0.y * scale.1, $0.z * scale.2)) }
        let low = points.dropFirst().reduce(points[0]) { Vector3(min($0.x, $1.x), min($0.y, $1.y), min($0.z, $1.z)) }
        let high = points.dropFirst().reduce(points[0]) { Vector3(max($0.x, $1.x), max($0.y, $1.y), max($0.z, $1.z)) }
        return (low, high)
    }

    func expect(_ bounds: BoundingBox?, _ expected: (Vector3, Vector3), tolerance: Double = 1e-4) throws {
        let box = try #require(bounds)
        #expect(isClose(box.min, expected.0, tolerance: tolerance), "min \(box.min) vs \(expected.0)")
        #expect(isClose(box.max, expected.1, tolerance: tolerance), "max \(box.max) vs \(expected.1)")
    }

    // MARK: Fixtures: the L block of `ComponentFixtures`, in each format

    /// The block's twelve points (2 per outline point, z = 0 then 3) and triangles, as VRML's `coordIndex` fans from point 0.
    static let faces: [[Int]] = {
        let n = ComponentFixtures.outline.count
        var result: [[Int]] = []
        for i in 1..<(n - 1) { result.append([0, 2 * (i + 1), 2 * i]) }  // bottom, seen from below
        for i in 1..<(n - 1) { result.append([1, 2 * i + 1, 2 * (i + 1) + 1]) }  // top
        for i in 0..<n {
            let j = (i + 1) % n
            result.append([2 * i, 2 * j, 2 * j + 1, 2 * i + 1])
        }
        return result
    }()

    static func points(dividedBy unit: Double) -> String {
        ComponentFixtures.outline.flatMap { p in [0.0, 3.0].map { "\(p.x / unit) \(p.y / unit) \($0 / unit)" } }.joined(separator: ", ")
    }

    static func vrml(scale: String = "1 1 1", unit: Double = 2.54, extra: String = "") -> String {
        let indices = faces.map { $0.map(String.init).joined(separator: ", ") + ", -1" }.joined(separator: ", ")
        return """
        #VRML V2.0 utf8
        Transform { scale \(scale) children [
          Shape { geometry IndexedFaceSet { coord Coordinate { point [ \(points(dividedBy: unit)) ] } coordIndex [ \(indices) ] } }
          \(extra)
        ] }
        """
    }

    static func x3d() -> String {
        let indices = faces.map { $0.map(String.init).joined(separator: " ") + " -1" }.joined(separator: " ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <X3D version="3.0"><Scene><Shape><IndexedFaceSet coordIndex="\(indices)">
        <Coordinate point="\(points(dividedBy: 2.54))"/></IndexedFaceSet></Shape></Scene></X3D>
        """
    }

    static let sphere = "Shape { geometry Sphere { radius 1 } }"

    static func idf(_ body: String = "0 0 0 0\n0 4 0 0\n0 4 2 0\n0 0 2 0\n0 0 0 0", height: String = "5") -> String {
        ".HEADER\nLIBRARY_FILE 3.0 \"KiCad\" 2026/11/17.00:00:00 1\n.END_HEADER\n.ELECTRICAL\n\"PART\" \"P1\" MM \(height)\n"
            + body + "\n.END_ELECTRICAL\n"
    }
}
#endif
