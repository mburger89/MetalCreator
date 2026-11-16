import CreatorGeometry
import Foundation
import Testing
@testable import CreatorPCB

struct KiCadBoardReaderTests {
    private func read(_ text: String, limits: KiCadLimits = .standard) throws -> KiCadBoard {
        try KiCadBoardReader.read(Data(text.utf8), limits: limits)
    }

    private func message(_ text: String, limits: KiCadLimits = .standard) -> String? {
        do {
            _ = try read(text, limits: limits)
            return nil
        } catch let problem as KiCadProblem {
            return problem.message
        } catch {
            return "other"
        }
    }

    private func close(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length < 1e-9 }

    @Test func readsTheRectangleBoard() throws {
        let board = try read(BoardFixtures.rectangleWithFourM3)
        #expect(board.version == 20_260_206)
        #expect(board.thickness == 1.6)
        #expect(board.edgeItems.count == 5)
        #expect(board.footprints.map(\.reference) == ["H1", "H2", "H3", "H4"])
        let expected = [Vector2(4, -4), Vector2(96, -4), Vector2(96, -76), Vector2(4, -76)]
        for (footprint, centre) in zip(board.footprints, expected) {
            #expect(footprint.libraryID == "MountingHole:MountingHole_3.2mm_M3")
            #expect(footprint.holes.count == (footprint.reference == "H2" ? 2 : 1))
            #expect(footprint.holes[0].diameter == 3.2 && !footprint.holes[0].isPlated)
            #expect(close(footprint.holes[0].center, centre))
        }
        #expect(board.auxAxisOrigin == Vector2(0, 0))
        guard case .line(let start, let end) = board.edgeItems[1].shape else { Issue.record("not a line"); return }
        #expect(start == Vector2(100, 0) && end == Vector2(100, -80))
        #expect(board.edgeItems[0].identity == "edge:00000000-0000-0000-0000-000000000000")
    }

    private let rotatedPad = """
    (kicad_pcb (version 20240108)
      (footprint "L:F" (layer "%@") (at 50 40 90)
        (property "Reference" "J1" (at 0 0))
        (pad "1" thru_hole oval (at 2 0 90) (size 2 3) (drill oval 1 2 (offset 0.5 0)))))
    """

    @Test(arguments: ["F.Cu", "B.Cu"])
    func rotatedFootprintPadWithDrillOffset(layer: String) throws {
        let board = try read(String(format: rotatedPad, layer))
        let hole = try #require(board.footprints.first?.holes.first)
        #expect(close(hole.center, Vector2(50, -37.5)))
        #expect(hole.slotLength == 2 && hole.diameter == 1 && hole.angle == 180 && hole.isPlated)
        #expect(hole.padNumber == "1")
        #expect(board.footprints[0].isBack == (layer == "B.Cu"))
    }

    @Test func transformFootprintPadAngle() throws {
        // The pad's angle is in the library frame in a transform footprint: absolute = 0 + 90 (ruling, facts §9).
        let board = try read("""
        (kicad_pcb (version 20261031)
          (footprint "L:F" (transform (translate 50 40) (rotate 90) (scale 1 1))
            (pad "1" thru_hole oval (at 2 0 0) (size 2 3) (drill oval 1 2 (offset 0.5 0)))))
        """)
        let hole = try #require(board.footprints.first?.holes.first)
        #expect(close(hole.center, Vector2(50, -37.5)))
        #expect(hole.angle == 180)
    }

    @Test func badTransformScaleIsOne() throws {
        let board = try read("""
        (kicad_pcb (version 20261031)
          (footprint "L:F" (transform (translate 0 0) (rotate 0) (scale -2 0))
            (pad "1" thru_hole circle (at 3 1) (size 2 2) (drill 1))))
        """)
        #expect(board.footprints[0].place.scale == Vector2(1, 1))
        #expect(close(board.footprints[0].holes[0].center, Vector2(3, -1)))
    }

    @Test func legacyArcConvertsToStartMidEnd() throws {
        let board = try read("""
        (kicad_pcb (version 20171130)
          (gr_arc (start 0 0) (end 1 0) (angle 90) (layer Edge.Cuts))
          (gr_arc (start 0 0) (end 1 0) (angle -90) (layer Edge.Cuts)))
        """)
        let half = 0.5.squareRoot()
        guard case .arc(let start, let mid, let end) = board.edgeItems[0].shape else { Issue.record("not an arc"); return }
        #expect(close(start, Vector2(1, 0)) && close(mid, Vector2(half, -half)) && close(end, Vector2(0, -1)))
        guard case .arc(let start2, let mid2, let end2) = board.edgeItems[1].shape else { Issue.record("not an arc"); return }
        #expect(close(start2, Vector2(0, 1)) && close(mid2, Vector2(half, half)) && close(end2, Vector2(1, 0)))
    }

    @Test func modelAtIsInches() throws {
        let board = try read("""
        (kicad_pcb (version 20171130)
          (module "L:F" (at 0 0)
            (model a.wrl (at (xyz 0.1 0 0)) (scale (xyz 1 1 1)) (rotate (xyz 0 0 90)))
            (model b.wrl (offset (xyz 1 2 3)) (scale (xyz 2 2 2)) (rotate (xyz 0 0 0)) (hide))))
        """)
        let models = board.footprints[0].models
        #expect(models[0].offset == Vector3(2.54, 0, 0) && models[0].rotation == Vector3(0, 0, 90) && !models[0].isHidden)
        #expect(models[1].offset == Vector3(1, 2, 3) && models[1].scale == Vector3(2, 2, 2) && models[1].isHidden)
    }

    @Test func flagsInAllForms() throws {
        for flag in ["(hide)", "hide", "(hide yes)"] {
            let board = try read("(kicad_pcb (footprint \"L:F\" (model a.wrl \(flag))))")
            #expect(board.footprints[0].models[0].isHidden, "\(flag)")
        }
        let shown = try read("(kicad_pcb (footprint \"L:F\" (model a.wrl (hide no)) (model b.wrl)))")
        #expect(shown.footprints[0].models.allSatisfy { !$0.isHidden })
    }

    @Test func rectanglePolygonAndCurveBecomeShapes() throws {
        let board = try read("""
        (kicad_pcb (version 20240108)
          (gr_rect (start 0 0) (end 10 5) (layer "Edge.Cuts") (uuid "r"))
          (gr_poly (pts (xy 0 0) (xy 4 0) (arc (start 4 0) (mid 5 1) (end 4 2)) (xy 0 2)) (layer "Edge.Cuts"))
          (gr_curve (pts (xy 0 0) (xy 1 0) (xy 2 1) (xy 3 1)) (layer "Edge.Cuts"))
          (gr_circle (center 5 5) (end 7 5) (layer "Edge.Cuts"))
          (gr_line (start 0 0) (end 1 1) (layer "F.SilkS")))
        """)
        #expect(board.edgeItems.count == 4 + 4 + 1 + 1)
        #expect(board.edgeItems[3].identity == "edge:r:3")
        #expect(board.edgeItems[4].identity.hasPrefix("edge:poly:") && board.edgeItems[4].identity.hasSuffix(":0"))
        #expect(board.edgeItems[8].shape == .bezier(Vector2(0, 0), Vector2(1, 0), Vector2(2, -1), Vector2(3, -1)))
        #expect(board.edgeItems[9].shape == .circle(center: Vector2(5, -5), radius: 2))
    }

    @Test func footprintGraphicsArePlaced() throws {
        let board = try read("""
        (kicad_pcb (version 20240108)
          (footprint "L:F" (at 10 10 90)
            (fp_line (start 0 0) (end 1 0) (layer "Edge.Cuts"))))
        """)
        guard case .line(let start, let end) = board.edgeItems[0].shape else { Issue.record("not a line"); return }
        #expect(close(start, Vector2(10, -10)) && close(end, Vector2(10, -9)))
    }

    @Test func viasAreRead() throws {
        let board = try read("""
        (kicad_pcb (version 20240108)
          (via (at 5 10) (size 0.8) (drill 0.4) (layers "F.Cu" "B.Cu") (net 1) (uuid "v")))
        """)
        #expect(board.vias.count == 1)
        #expect(board.vias[0].center == Vector2(5, -10) && board.vias[0].diameter == 0.4 && board.vias[0].isPlated)
        #expect(board.vias[0].padNumber.isEmpty && board.vias[0].identity.isEmpty)
    }

    @Test func padsWithoutADrillMakeNoHole() throws {
        let board = try read("""
        (kicad_pcb (footprint "L:F" (pad "1" smd rect (at 0 0) (size 1 1))
          (pad "2" thru_hole circle (at 1 0) (size 1 1) (drill 0))))
        """)
        #expect(board.footprints[0].holes.isEmpty)
    }

    @Test func refusesLegacyBrd() {
        #expect(message("PCBNEW-BOARD Version 1 date 2012\n") ==
                "This is an old KiCad board (.brd). Open it in KiCad and save it as a .kicad_pcb, then try again.")
    }

    @Test func refusesNotABoard() {
        #expect(message("(kicad_sch (version 1))") == "This isn't a KiCad board file.")
    }

    @Test func refusesTooManyFootprints() {
        var limits = KiCadLimits()
        limits.maxFootprints = 2
        let text = message("(kicad_pcb (footprint a) (footprint b) (footprint c))", limits: limits)
        #expect(text?.contains("more than 2 footprints") == true)
    }

    @Test func refusesTooManyPads() {
        var limits = KiCadLimits()
        limits.maxPads = 1
        #expect(message("(kicad_pcb (footprint a (pad 1) (pad 2)))", limits: limits)?.contains("more than 1 pads") == true)
    }

    @Test func missingThicknessIsNil() throws {
        #expect(try read("(kicad_pcb (version 20240108))").thickness == nil)
    }

    @Test func stackupThicknessIsSummed() throws {
        let board = try read("""
        (kicad_pcb (version 20240108)
          (setup (stackup (layer "F.Cu" (type "copper") (thickness 0.035))
            (layer "dielectric 1" (type "core") (thickness 1.51))
            (layer "F.SilkS" (type "Top Silk Screen"))
            (layer "B.Cu" (type "copper") (thickness 0.035)))))
        """)
        let thickness = try #require(board.thickness)
        #expect(abs(thickness - 1.58) < 1e-9)
    }

    @Test func legacyArcInARotatedFootprint() throws {
        let board = try read("""
        (kicad_pcb (version 20171130)
          (module "L:F" (at 10 10 90)
            (fp_arc (start 0 0) (end 1 0) (angle 90) (layer Edge.Cuts) (width 0.15))))
        """)
        let half = 0.5.squareRoot()
        guard case .arc(let start, let mid, let end) = board.edgeItems[0].shape else { Issue.record("not an arc"); return }
        #expect(close(start, Vector2(10, -9)) && close(mid, Vector2(10 + half, -10 + half)) && close(end, Vector2(11, -10)))
    }

    @Test func holeAnglesAreNormalised() throws {
        let board = try read("""
        (kicad_pcb (version 20240108)
          (footprint "L:F" (at 0 0 -90)
            (pad "1" thru_hole oval (at 0 0 -90) (size 2 3) (drill oval 1 2))
            (pad "2" thru_hole oval (at 0 0 450) (size 3 2) (drill oval 2 1))))
        """)
        #expect(board.footprints[0].holes.map(\.angle) == [0, 90])
    }

    @Test func hostileNumbersAreRefusedInWords() {
        let sentence = "The board file has a number out of range."
        #expect(message("(kicad_pcb (version 1e30))") == sentence)
        #expect(message("(kicad_pcb (version 1.5))") == sentence)
        #expect(message("(kicad_pcb (version -3))") == sentence)
        #expect(message("(kicad_pcb (gr_line (start 1e30 0) (end 1 1) (layer Edge.Cuts)))") == sentence)
        #expect(message("(kicad_pcb (gr_line (start inf 0) (end 1 1) (layer Edge.Cuts)))") == sentence)
        #expect(message("(kicad_pcb (gr_line (start nan 0) (end 1 1) (layer Edge.Cuts)))") == sentence)
        #expect(message("(kicad_pcb (footprint a (transform (translate 0 0) (rotate 0) (scale 1e300 1))"
            + " (fp_line (start 1e6 0) (end 0 0) (layer Edge.Cuts))))") == sentence)
        #expect(message("(kicad_pcb (footprint a (at 0 0) (pad 1 thru_hole circle (at 0 0) (drill 1e30))))") == sentence)
    }

    @Test func badScalesAreOne() throws {
        let board = try read("(kicad_pcb (footprint a (transform (translate 0 0) (rotate 0) (scale inf nan))))")
        #expect(board.footprints[0].place.scale == Vector2(1, 1))
    }

    @Test func numericMutationsNeverCrash() {
        var random = SeededRandom(seed: 2026)
        let original = BoardFixtures.rectangleWithFourM3
        let replacements = ["1e30", "-1e30", "1e-30", "0", "nan", "inf"]
        for round in 0..<2_000 {
            var tokens = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            let numeric = tokens.indices.filter { Double(tokens[$0].trimmingCharacters(in: CharacterSet(charactersIn: "()"))) != nil }
            for _ in 0..<(1 + round % 3) {
                let index = numeric[Int(random.next() % UInt64(numeric.count))]
                let trailing = tokens[index].reversed().prefix { $0 == ")" }
                tokens[index] = replacements[Int(random.next() % UInt64(replacements.count))] + String(trailing)
            }
            let outcome = Result { try read(tokens.joined(separator: " ")) }
            if case .failure(let error) = outcome { #expect(error is KiCadProblem) }
        }
    }
}
