#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes
@testable import CreatorOCCT

/// A pick on an imported board's component follows its footprint (KiCad import spec, Names that picks follow).
struct ImportKiCadComponentPickTests {
    let folder = TempFolderForNodes()
    let kernel = OCCTKernel()

    func part(_ reference: String, x: Double, y: Double) -> KiCadBoardText.Part {
        KiCadBoardText.Part(reference: reference, x: x, y: y, library: "Parts:\(reference)", hasPad: false,
                            models: [KiCadBoardText.Model(path: "${KIPRJMOD}/models/l.step")])
    }

    func components(_ parts: [KiCadBoardText.Part], _ h: Harness, _ node: Node, file: URL) async throws -> [Solid] {
        try Data(KiCadBoardText.rectangle(parts: parts).utf8).write(to: file)
        try folder.touch(file, Date(timeIntervalSinceNow: 60 + Double(parts.count)))
        let report = try await h.run([node], kernel: kernel)
        return try #require(report.value(node, "components")?.solids)
    }

    func solid(of reference: String, in solids: [Solid]) throws -> Solid {
        let item = KiCadKey.item(for: "fp:\(reference)")
        return try #require(solids.first { $0.topology.faces.contains { face in face.tags.contains { $0.item == item } } })
    }

    @Test func facePickSurvivesAnAddedFootprintAndAMovedOne() async throws {
        try folder.write(try await ComponentFixtures.step(kernel), to: "models/l.step")
        let file = try folder.write(Data(KiCadBoardText.rectangle(parts: [part("J1", x: 30, y: 20)]).utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        let parts = [part("J1", x: 30, y: 20), part("R1", x: 60, y: 50)]
        let before = try solid(of: "J1", in: try await components(parts, h, node, file: file))
        let face = try #require(before.topology.faces.first { ($0.normal?.z ?? 0) > 0.9 })
        let pick = FacePick(tags: face.tags, normal: face.normal, centroid: face.centroid)
        #expect(before.topology.faces(matching: pick).count == 1)

        // J2 is added ahead of J1 in the file, and R1 moves.
        let edited = [part("J2", x: 10, y: 10), part("J1", x: 30, y: 20), part("R1", x: 75, y: 40)]
        let after = try solid(of: "J1", in: try await components(edited, h, node, file: file))
        let found = after.topology.faces(matching: pick)
        #expect(found.count == 1)
        #expect(isClose(try #require(found.first).centroid, face.centroid, tolerance: 1e-6))
    }
}
#endif
