import CreatorGeometry
import Foundation
import Testing
@testable import CreatorPCB

struct IDFReaderTests {
    static func file(unit: String = "MM", height: String = "5", body: String) -> Data {
        Data("""
        .HEADER
        LIBRARY_FILE 3.0 "KiCad" 2026/11/17.00:00:00 1
        .END_HEADER
        .ELECTRICAL
        "PART" "P1" \(unit) \(height)
        \(body)
        .END_ELECTRICAL

        """.utf8)
    }

    static let square = "0 0 0 0\n0 4 0 0\n0 4 2 0\n0 0 2 0\n0 0 0 0"

    static func read(_ data: Data) throws(KiCadProblem) -> IDFOutline {
        try IDFReader.read(data, isCancelled: { false })
    }

    @Test func rectangle() throws {
        let outline = try Self.read(Self.file(body: Self.square))
        #expect(outline.height == 5)
        #expect(outline.profile.outer.count == 4)
        #expect(outline.profile.holes.isEmpty)
        #expect(outline.profile.plane == .xy)
        #expect(abs(ArcGeometry.signedArea(outline.profile.outer) - 8) < 1e-9)
        #expect(outline.profile.isClosed)
    }

    @Test func clockwiseOuterIsReversed() throws {
        let outline = try Self.read(Self.file(body: "0 0 0 0\n0 0 2 0\n0 4 2 0\n0 4 0 0\n0 0 0 0"))
        #expect(ArcGeometry.signedArea(outline.profile.outer) > 0)
        #expect(outline.profile.isClosed)
    }

    @Test func thouUnits() throws {
        let outline = try Self.read(Self.file(unit: "THOU", height: "100", body: "0 0 0 0\n0 1000 0 0\n0 1000 500 0\n0 0 0 0"))
        #expect(abs(outline.height - 2.54) < 1e-12)
        guard case .line(_, let end) = outline.profile.outer[0] else { Issue.record("not a line"); return }
        #expect(abs(end.x - 25.4) < 1e-9)
        #expect(abs((outline.profile.bounds?.max.x ?? 0) - 25.4) < 1e-9)
    }

    @Test func quarterArcCorner() throws {
        // (0,0) -> (4,0) -> (4,2) -> arc 90 deg ccw to (2,4)? use a quarter arc from (4,0) to (6,2): centre (4,2).
        let outline = try Self.read(Self.file(body: "0 0 0 0\n0 4 0 0\n0 6 2 90\n0 6 4 0\n0 0 4 0\n0 0 0 0"))
        let arcs = outline.profile.outer.compactMap { segment -> (Vector2, Double)? in
            if case .arc(let centre, let radius, _, _) = segment { (centre, radius) } else { nil }
        }
        #expect(arcs.count == 1)
        #expect(abs(arcs[0].0.x - 4) < 1e-9 && abs(arcs[0].0.y - 2) < 1e-9)
        #expect(abs(arcs[0].1 - 2) < 1e-9)
        #expect(outline.profile.isClosed)
    }

    @Test func counterClockwiseArcCentre() throws {
        // From (2,0) to (0,2) turning +90: centre (0,0), radius 2, a convex corner of a quadrant.
        let outline = try Self.read(Self.file(body: "0 0 0 0\n0 2 0 0\n0 0 2 90\n0 0 0 0"))
        let arc = outline.profile.outer.compactMap { segment -> (Vector2, Double, Double, Double)? in
            if case .arc(let c, let r, let s, let e) = segment { (c, r, s.radians, e.radians) } else { nil }
        }
        #expect(arc.count == 1)
        #expect(abs(arc[0].0.x) < 1e-9 && abs(arc[0].0.y) < 1e-9)
        #expect(abs(arc[0].1 - 2) < 1e-9)
        #expect(abs((arc[0].3 - arc[0].2).magnitude - .pi / 2) < 1e-9)
        #expect(abs(ArcGeometry.signedArea(outline.profile.outer) - .pi) < 1e-9)
    }

    @Test func negativeArcBendsTheOtherWay() throws {
        // From (2,0) to (0,2) turning -90: centre (2,2), so the bulge faces the origin.
        let outline = try Self.read(Self.file(body: "0 0 0 0\n0 2 0 0\n0 0 2 -90\n0 0 0 0"))
        let centres = outline.profile.outer.compactMap { segment -> Vector2? in
            if case .arc(let c, _, _, _) = segment { c } else { nil }
        }
        #expect(centres.count == 1)
        #expect(abs(centres[0].x - 2) < 1e-9 && abs(centres[0].y - 2) < 1e-9)
    }

    @Test func fullCircle() throws {
        let outline = try Self.read(Self.file(body: "0 1 1 0\n0 3 1 360"))
        #expect(outline.profile.outer.count == 1)
        guard case .arc(let centre, let radius, _, _) = outline.profile.outer[0] else { Issue.record("not an arc"); return }
        #expect(centre == Vector2(1, 1))
        #expect(abs(radius - 2) < 1e-9)
        #expect(ArcGeometry.signedArea(outline.profile.outer) > 0)
    }

    @Test func holeLoop() throws {
        let hole = "1 1 0.5 0\n1 3 0.5 0\n1 3 1.5 0\n1 1 1.5 0\n1 1 0.5 0"
        let outline = try Self.read(Self.file(body: Self.square + "\n" + hole))
        #expect(outline.profile.holes.count == 1)
        #expect(ArcGeometry.signedArea(outline.profile.holes[0]) < 0)
        #expect(ArcGeometry.signedArea(outline.profile.outer) > 0)
    }

    @Test func bareNamesAndLowercase() throws {
        let text = ".header\nLIBRARY_FILE 3.0 x\n.end_header\n.mechanical\nGEOM PN MM 3\n"
            + "0 0 0 0\n0 1 0 0\n0 1 1 0\n0 0 0 0\n.end_mechanical\n"
        let data = Data(text.utf8)
        let outline = try Self.read(data)
        #expect(outline.height == 3)
    }

    @Test func boardFileIsRefused() {
        let text = ".HEADER\nBOARD_FILE 3.0 \"x\" 2026/11/17.00:00:00 1\n.END_HEADER\n"
            + ".BOARD_OUTLINE UNOWNED\n1.6\n0 0 0 0\n.END_BOARD_OUTLINE\n"
        let data = Data(text.utf8)
        #expect(throws: KiCadProblem("This IDF file is a whole board, not a part.")) { try Self.read(data) }
    }

    @Test func openLoopIsRefused() {
        #expect(throws: KiCadProblem("This IDF file has an outline that doesn't close.")) {
            try Self.read(Self.file(body: "0 0 0 0\n0 4 0 0\n0 4 2 0"))
        }
    }

    @Test func junkIsRefused() {
        #expect(throws: KiCadProblem.self) { try Self.read(Data("hello world".utf8)) }
        #expect(throws: KiCadProblem.self) { try Self.read(Self.file(body: "0 a b c")) }
        #expect(throws: KiCadProblem.self) { try Self.read(Self.file(unit: "FURLONG", body: Self.square)) }
        #expect(throws: KiCadProblem.self) { try Self.read(Self.file(height: "0", body: Self.square)) }
    }

    @Test func oversizeIsRefused() {
        #expect(throws: KiCadProblem("This IDF file is larger than 16 MB.")) {
            try Self.read(Data(count: IDFReader.maximumBytes + 1))
        }
    }

    @Test func cancellationIsAsked() {
        let lines = String(repeating: "\n", count: 70_000)
        let data = Data((".HEADER\n.END_HEADER\n" + lines).utf8)
        #expect(throws: KiCadProblem.self) { try IDFReader.read(data, isCancelled: { true }) }
    }
}
