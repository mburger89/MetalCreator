#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorOCCT
import Foundation
import Testing
@testable import CreatorNodes

/// Import KiCad Board (KiCad import spec, KI-1) through the real evaluator on OpenCascade.
struct ImportKiCadBoardNodeTests {
    let folder = TempFolderForNodes()

    func node(_ text: String, name: String = "board.kicad_pcb", _ values: [SocketName: ConstantValue] = [:]) throws -> (Harness, Node) {
        let file = try folder.write(Data(text.utf8), to: name)
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let board = h.add(ImportKiCadBoardNode.self, values.merging([NodeSetting.pcbFile: .pcbFile(reference)]) { _, new in new })
        return (h, board)
    }

    func run(_ h: Harness, _ node: Node, _ kernel: OCCTKernel) async throws -> EvaluationReport {
        try await h.run([node], kernel: kernel)
    }

    func near(_ a: Vector3, _ x: Double, _ y: Double, _ z: Double, tolerance: Double = 1e-6) -> Bool {
        isClose(a, Vector3(x, y, z), tolerance: tolerance)
    }

    @Test func rectangleBoardBuilds() async throws {
        let kernel = OCCTKernel()
        let (h, board) = try node(KiCadBoardText.rectangle())
        let report = try await run(h, board, kernel)
        #expect(report.isOK(board), "\(String(describing: report.state(board)))")
        let solid = try onlySolid(report, board, "board")
        #expect(isClose(try await volume(solid, kernel), (100 * 80 - 4 * Double.pi * 1.6 * 1.6) * 1.6))
        #expect(near(solid.bounds.min, -50, -40, 0) && near(solid.bounds.max, 50, 40, 1.6))
        let holes = try #require(report.value(board, "mounting holes")?.planes)
        let expected = [(-46.0, 36.0), (46, 36), (46, -36), (-46, -36)]
        #expect(holes.count == 4)
        for (plane, point) in zip(holes, expected) {
            #expect(near(plane.origin, point.0, point.1, 1.6) && near(plane.normal, 0, 0, 1))
        }
        #expect(report.value(board, "mounting hole diameters")?.numbers == [3.2, 3.2, 3.2, 3.2])
        #expect(report.value(board, "components")?.items.isEmpty == true)
        #expect(report.value(board, "component meshes")?.items.isEmpty == true)
        let outline = try #require(report.value(board, "outline")?.profiles?.first)
        #expect(outline.plane.origin.z == 1.6 && outline.outer.count == 4 && outline.holes.isEmpty)
    }

    @Test func mountingHolesAreOrderedNaturally() async throws {
        let parts = ["H10", "H2", "J1", "H1"].enumerated().map {
            KiCadBoardText.Part(reference: $0.element, x: 10 + Double($0.offset) * 10, y: 20,
                                library: $0.element == "J1" ? "Connector:Hole" : "MountingHole:MH",
                                drill: 3.2, plated: false)
        }
        let (h, board) = try node(KiCadBoardText.rectangle(parts: parts))
        let report = try await run(h, board, OCCTKernel())
        let xs = try #require(report.value(board, "mounting holes")?.planes).map { $0.origin.x + 50 }
        // H1 (x 40), H2 (x 20), H10 (x 10), then J1 (x 30): a lone non-plated 3.2 mm hole counts too.
        #expect(xs == [40, 20, 10, 30])
    }

    @Test func originPageAndDrillPlace() async throws {
        let kernel = OCCTKernel()
        let text = KiCadBoardText.rectangle(aux: (10, 5))
        let (hp, page) = try node(text, ["origin": .integer(BoardOrigin.page.rawValue)])
        let onPage = try onlySolid(try await run(hp, page, kernel), page, "board")
        #expect(near(onPage.bounds.min, 0, -80, 0) && near(onPage.bounds.max, 100, 0, 1.6))
        let (hd, drill) = try node(text, ["origin": .integer(BoardOrigin.drillPlace.rawValue)])
        let onDrill = try onlySolid(try await run(hd, drill, kernel), drill, "board")
        #expect(near(onDrill.bounds.min, -10, -75, 0))
        let (hn, none) = try node(KiCadBoardText.rectangle(), ["origin": .integer(BoardOrigin.drillPlace.rawValue)])
        let report = try await run(hn, none, kernel)
        #expect(report.warning(none) == "This board has no drill/place origin, so the board centre is used.")
        #expect(near(try onlySolid(report, none, "board").bounds.min, -50, -40, 0))
    }

    @Test func missingThicknessAndNewerVersionWarn() async throws {
        let text = KiCadBoardText.rectangle(thickness: nil).replacingOccurrences(of: "20260206", with: "20270101")
        let (h, board) = try node(text)
        let report = try await run(h, board, OCCTKernel())
        let warning = try #require(report.warning(board))
        #expect(warning.contains("This board has no thickness, so 1.6 mm is used."))
        #expect(warning.contains("This board is from a newer KiCad than MetalCreator knows. Check the result."))
        #expect(near(try onlySolid(report, board, "board").bounds.max, 50, 40, 1.6))
    }

    @Test func placementPlaneMovesTheBoard() async throws {
        let kernel = OCCTKernel()
        let (h, board) = try node(KiCadBoardText.rectangle(), ["placement": .plane(.xz)])
        let report = try await run(h, board, kernel)
        let solid = try onlySolid(report, board, "board")
        #expect(near(solid.bounds.min, -50, -1.6, -40, tolerance: 1e-5) && near(solid.bounds.max, 50, 0, 40, tolerance: 1e-5))
        #expect(isClose(try await volume(solid, kernel), (100 * 80 - 4 * Double.pi * 1.6 * 1.6) * 1.6))
        let first = try #require(report.value(board, "mounting holes")?.planes?.first)
        #expect(near(first.origin, -46, -1.6, 36, tolerance: 1e-9) && near(first.normal, 0, -1, 0))
        let outline = try #require(report.value(board, "outline")?.profiles?.first)
        #expect(near(outline.plane.origin, 0, -1.6, 0, tolerance: 1e-9))
    }

    @Test func roundedBoardWithBezierAndCutoutBuilds() async throws {
        let kernel = OCCTKernel()
        let (h, board) = try node(KiCadBoardText.rounded())
        let report = try await run(h, board, kernel)
        let solid = try onlySolid(report, board, "board")
        let area = 100.0 * 80 - (4 - Double.pi) * 25 - Double.pi * 100
        #expect(isClose(try await volume(solid, kernel), area * 1.6, relative: 1e-6))
        // Two caps, eight sides (four lines or curves, four corners) and the cutout's wall.
        #expect(solid.topology.faces.count == 11)
        let outline = try #require(report.value(board, "outline")?.profiles?.first)
        #expect(outline.outer.count == 8 && outline.holes.count == 1)
        #expect(outline.outer.contains { $0.isSpline })
    }

    @Test func ovalSlotIsCut() async throws {
        let kernel = OCCTKernel()
        let slot = KiCadBoardText.Part(reference: "J1", x: 30, y: 40, library: "Connector:Slot", drill: 1.5, slot: 4, plated: true)
        let (h, board) = try node(KiCadBoardText.rectangle(parts: [slot]))
        let solid = try onlySolid(try await run(h, board, kernel), board, "board")
        let cut = (4.0 - 1.5) * 1.5 + Double.pi * 0.75 * 0.75
        #expect(isClose(try await volume(solid, kernel), (8000 - cut) * 1.6))
    }

    @Test func viasToggle() async throws {
        let kernel = OCCTKernel()
        let text = KiCadBoardText.rectangle(parts: [], extra: KiCadBoardText.via(x: 20, y: 20))
        let (off, a) = try node(text)
        let without = try await volume(try onlySolid(try await run(off, a, kernel), a, "board"), kernel)
        #expect(isClose(without, 8000 * 1.6))
        let (on, b) = try node(text, ["vias": .bool(true)])
        let with = try await volume(try onlySolid(try await run(on, b, kernel), b, "board"), kernel)
        #expect(isClose(with, (8000 - Double.pi * 0.2 * 0.2) * 1.6))
    }

    @Test func noFileIsASentence() async throws {
        var h = Harness()
        let board = h.add(ImportKiCadBoardNode.self)
        #expect(try await run(h, board, OCCTKernel()).error(board) == "Choose a KiCad board file.")
    }

    @Test func damagedFileIsASentence() async throws {
        let (h, board) = try node("(not_a_board)")
        #expect(try await run(h, board, OCCTKernel()).error(board) == "This isn't a KiCad board file.")
        let (h2, empty) = try node(KiCadBoardText.header + ")\n", name: "empty.kicad_pcb")
        #expect(try await run(h2, empty, OCCTKernel()).error(empty) == "The board has no outline on Edge.Cuts.")
        var h3 = Harness()
        let gone = ImageReference.linked(relativePath: nil, absolutePath: "/nowhere/x.kicad_pcb")
        let missing = h3.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(gone)])
        #expect(try await run(h3, missing, OCCTKernel()).error(missing)?.contains("wasn't found") == true)
    }

    @Test func editedFileRerunsAtNextEvaluation() async throws {
        let kernel = OCCTKernel()
        let (h, board) = try node(KiCadBoardText.rectangle())
        let first = try #require(try await run(h, board, kernel).value(board, "mounting holes")?.planes)
        #expect(near(first[0].origin, -46, 36, 1.6))
        var moved = KiCadBoardText.fourMounting()
        moved[0].x = 10
        let file = try folder.write(Data(KiCadBoardText.rectangle(parts: moved).utf8), to: "board.kicad_pcb")
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
        let second = try #require(try await run(h, board, kernel).value(board, "mounting holes")?.planes)
        #expect(near(second[0].origin, -40, 36, 1.6))
    }

    @Test func drillPlaceOriginWithAnXZPlacement() async throws {
        let (h, board) = try node(KiCadBoardText.rectangle(aux: (10, 5)),
                                  ["origin": .integer(BoardOrigin.drillPlace.rawValue), "placement": .plane(.xz)])
        let report = try await run(h, board, OCCTKernel())
        let first = try #require(report.value(board, "mounting holes")?.planes?.first)
        // H1 is at file (4, 4), board (4, -4); minus the drill origin (10, -5) is (-6, 1); on xz that is (x, -1.6, y).
        #expect(near(first.origin, -6, -1.6, 1, tolerance: 1e-9) && near(first.normal, 0, -1, 0))
    }

    @Test func viasAreNotCountedAsDrilledPads() async throws {
        let text = KiCadBoardText.rectangle(extra: KiCadBoardText.via(x: 20, y: 20))
        let (off, a) = try node(text)
        let plain = try await run(off, a, OCCTKernel())
        #expect(plain.results[a.id]?.facts.contains(PayloadFact("Holes", "4 drilled, 4 mounting")) == true)
        let (on, b) = try node(text, ["vias": .bool(true)])
        let withVias = try await run(on, b, OCCTKernel())
        #expect(withVias.results[b.id]?.facts.contains(PayloadFact("Holes", "4 drilled, 4 mounting, 1 vias")) == true)
    }

    @Test func facts() async throws {
        let (h, board) = try node(KiCadBoardText.rectangle())
        let report = try await run(h, board, OCCTKernel())
        let facts = Dictionary(uniqueKeysWithValues: try #require(report.results[board.id]?.facts).map { ($0.label, $0.value) })
        #expect(facts["File"] == "board.kicad_pcb")
        #expect(facts["KiCad version"] == "KiCad 10 (20260206)")
        #expect(facts["Size"] == "100 × 80 mm")
        #expect(facts["Thickness"] == "1.6 mm")
        #expect(facts["Holes"] == "4 drilled, 4 mounting")
        #expect(facts["Components"] == "4 placed")
        #expect(ImportKiCadBoardNode.factsTitle == "Board")
        #expect(BoardFacts.versionName(4) == "KiCad 4 (4)")
        #expect(BoardFacts.versionName(20_171_130) == "KiCad 5 (20171130)")
        #expect(BoardFacts.versionName(20_250_101) == "KiCad 9 (20250101)")
        #expect(BoardFacts.versionName(20_261_031) == "KiCad 11 development (20261031)")
    }

    @Test func naturalOrder() {
        #expect(BoardHoles.naturallyOrdered("H2", before: "H10"))
        #expect(!BoardHoles.naturallyOrdered("H10", before: "H2"))
        #expect(BoardHoles.naturallyOrdered("J1", before: "MH1"))
        #expect(BoardHoles.naturallyOrdered("H", before: "H1"))
    }
}
#endif
