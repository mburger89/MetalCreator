#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorOCCT
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes

/// A pick on an imported board's faces follows the pad or the outline piece it was made on (KiCad import spec, Topology names).
struct ImportKiCadBoardPickTests {
    let folder = TempFolderForNodes()

    func node(_ text: String) throws -> (Harness, Node, URL) {
        let file = try folder.write(Data(text.utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let board = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        return (h, board, file)
    }

    func rewrite(_ file: URL, _ text: String) throws {
        try Data(text.utf8).write(to: file)
        try folder.touch(file, Date(timeIntervalSinceNow: 60))
    }

    func solid(_ h: Harness, _ board: Node) async throws -> Solid {
        let report = try await h.run([board], kernel: OCCTKernel())
        return try onlySolid(report, board, "board")
    }

    @Test func holeWallPickSurvivesAnAddedPart() async throws {
        let (h, board, file) = try node(KiCadBoardText.rectangle())
        let before = try await solid(h, board)
        let item = KiCadKey.item(for: "pad:H2:")
        let wall = try #require(before.topology.faces.first { face in
            face.kind == .cylinder && face.tags.contains { $0.item == item }
        })
        let pick = FacePick(tags: wall.tags, normal: wall.normal, centroid: wall.centroid)
        #expect(before.topology.faces(matching: pick).count == 1)

        var parts = KiCadBoardText.fourMounting()
        parts[2].x = 80
        parts.insert(KiCadBoardText.Part(reference: "H0", x: 50, y: 40), at: 0)
        try rewrite(file, KiCadBoardText.rectangle(parts: parts))
        let after = try await solid(h, board)
        let found = after.topology.faces(matching: pick)
        #expect(found.count == 1)
        let centre = try #require(found.first).centroid
        #expect(abs(centre.x - wall.centroid.x) < 1e-6 && abs(centre.y - wall.centroid.y) < 1e-6)
        #expect(after.topology.faces.count == before.topology.faces.count + 1)
    }

    @Test func outlineSidePickSurvivesRedrawingAnotherCutout() async throws {
        let (h, board, file) = try node(KiCadBoardText.twoCutouts(secondX: 70))
        let before = try await solid(h, board)
        // The first cutout's wall: a cylinder whose axis is at file (25, 40), board frame (-25, 0).
        let wall = try #require(before.topology.faces.first { face in
            face.kind == .cylinder && abs((face.axisPoint?.x ?? 0) + 25) < 1e-6
        })
        let pick = FacePick(tags: wall.tags, normal: wall.normal, centroid: wall.centroid)
        #expect(before.topology.faces(matching: pick).count == 1)

        try rewrite(file, KiCadBoardText.twoCutouts(secondX: 60, secondID: 502))
        let after = try await solid(h, board)
        let found = after.topology.faces(matching: pick)
        #expect(found.count == 1)
        let centre = try #require(found.first).centroid
        #expect(abs(centre.x + 25) < 1e-6, "the pick stayed on the first cutout: \(centre)")
    }

    @Test func holeWallKeepsItsTagAfterAPlacementPlane() async throws {
        let (h, board, file) = try node(KiCadBoardText.rectangle())
        let flat = try await solid(h, board)
        let item = KiCadKey.item(for: "pad:H2:")
        let wall = try #require(flat.topology.faces.first { $0.kind == .cylinder && $0.tags.contains { $0.item == item } })
        var moved = h
        moved.set(board, "placement", .plane(.xz))
        let turned = try await solid(moved, board)
        let found = turned.topology.faces(matching: FacePick(tags: wall.tags))
        #expect(found.count == 1)
        // H2 is at (46, 36) on the board, so (46, y, 36) on the xz plane.
        let centre = try #require(found.first).centroid
        #expect(abs(centre.x - 46) < 1e-5 && abs(centre.z - 36) < 1e-5)
        _ = file
    }
}
#endif
