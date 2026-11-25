import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Sheet frame")
struct SheetFrameTests {
    private func sheet(_ size: SheetSize, _ orientation: SheetOrientation = .landscape) -> DrawingSheet {
        DrawingSheet(name: "Sheet 1", size: size, orientation: orientation)
    }

    private func frameStroke(_ picture: SheetPicture, width: Double) -> SheetStroke? {
        picture.strokes.first { $0.width == width }
    }

    @Test func isoFrameMargins() throws {
        let picture = SheetFrame.picture(for: sheet(.a3), standard: .iso)
        let stroke = try #require(frameStroke(picture, width: 0.7))
        #expect(stroke.bounds == Rect2D(min: Vector2(20, 10), max: Vector2(410, 287)))
        #expect(picture.size == Vector2(420, 297))
    }

    @Test func zoneCountsMatchISO5457() {
        func counts(_ size: SheetSize, _ o: SheetOrientation = .landscape) -> (Int, Int) {
            let frame = SheetFrame.rect(for: sheet(size, o), standard: .iso)
            return (SheetFrame.zoneCount(forSide: frame.width), SheetFrame.zoneCount(forSide: frame.height))
        }
        #expect(counts(.a0) == (24, 16))
        #expect(counts(.a1) == (16, 12))
        #expect(counts(.a2) == (12, 8))
        #expect(counts(.a3) == (8, 6))
        #expect(counts(.a4, .portrait) == (4, 6))
    }

    @Test func isoZoneLabels() {
        let picture = SheetFrame.picture(for: sheet(.a3), standard: .iso)
        let frame = SheetFrame.rect(for: sheet(.a3), standard: .iso)
        let top = picture.texts.filter { $0.origin.y > frame.max.y }.sorted { $0.origin.x < $1.origin.x }.map(\.original)
        #expect(top == ["1", "2", "3", "4", "5", "6", "7", "8"])
        let left = picture.texts.filter { $0.origin.x < frame.min.x }.sorted { $0.origin.y > $1.origin.y }.map(\.original)
        #expect(left == ["A", "B", "C", "D", "E", "F"])
    }

    @Test func asmeZoneLabels() {
        let paper = sheet(.ansiB)
        let picture = SheetFrame.picture(for: paper, standard: .asme)
        let frame = SheetFrame.rect(for: paper, standard: .asme)
        let top = picture.texts.filter { $0.origin.y > frame.max.y }.sorted { $0.origin.x < $1.origin.x }.map(\.original)
        #expect(top.first == String(top.count) && top.last == "1")
        let left = picture.texts.filter { $0.origin.x < frame.min.x }.sorted { $0.origin.y < $1.origin.y }.map(\.original)
        #expect(left.first == "A" && left.last == String(UnicodeScalar(UInt8(64 + left.count))))
    }

    @Test func centringMarksAreISOOnly() {
        let iso = SheetFrame.picture(for: sheet(.a3), standard: .iso)
        let asme = SheetFrame.picture(for: sheet(.a3), standard: .asme)
        let isoMarks = iso.strokes.filter { $0.width == 0.7 }.count
        let asmeMarks = asme.strokes.filter { $0.width == 0.7 }.count
        #expect(isoMarks == 5)  // the frame and four marks
        #expect(asmeMarks == 1)
    }

    @Test func asmeMarginsAreHalfAnInch() {
        let frame = SheetFrame.rect(for: sheet(.ansiB), standard: .asme)
        #expect(frame.min == Vector2(12.7, 12.7))
        #expect(abs(frame.max.x - (431.8 - 12.7)) < 1e-12 && abs(frame.max.y - (279.4 - 12.7)) < 1e-12)
        let area = DrawingArea.rect(for: sheet(.ansiB), standard: .asme)
        #expect(area.min.y == 12.7 + 40 && area.max == frame.max)
    }
}
