import CreatorGeometry
import Foundation

/// The sheet's frame, zone ticks and labels, and centring marks (plan R14).
public enum SheetFrame {
    /// The frame's rectangle: ISO 20 mm on the left and 10 mm elsewhere, ASME 12.7 mm all round.
    public static func rect(for sheet: DrawingSheet, standard: DrawingStandard) -> Rect2D {
        let paper = sheet.paperSize
        switch standard {
        case .iso:
            return Rect2D(min: Vector2(20, 10), max: Vector2(paper.x - 10, paper.y - 10))
        case .asme:
            let margin = 12.7
            return Rect2D(min: Vector2(margin, margin), max: Vector2(paper.x - margin, paper.y - margin))
        }
    }

    /// The number of zone fields along a side of `length` millimetres: 2 × max(1, round(length / 100)).
    public static func zoneCount(forSide length: Double) -> Int {
        2 * max(1, Int((length / 100).rounded()))
    }

    private static let tickLength = 5.0
    private static let labelOffset = 3.5
    private static let centringMarkInside = 5.0

    public static func picture(for sheet: DrawingSheet, standard: DrawingStandard) -> SheetPicture {
        let style = DrawingStyle.of(standard)
        let paper = sheet.paperSize
        let frame = rect(for: sheet, standard: standard)
        var picture = SheetPicture(size: paper)

        picture.strokes.append(
            SheetStroke(
                segments: [.polyline(closedPoints(of: frame))], width: style.frame, layer: .frame))

        let columns = zoneCount(forSide: frame.width)
        let rows = zoneCount(forSide: frame.height)
        let columnWidth = frame.width / Double(columns)
        let rowHeight = frame.height / Double(rows)

        var ticks: [SheetSegment] = []
        for i in 1..<columns {
            let x = frame.min.x + Double(i) * columnWidth
            ticks.append(.line(Vector2(x, frame.max.y), Vector2(x, frame.max.y + tickLength)))
            ticks.append(.line(Vector2(x, frame.min.y), Vector2(x, frame.min.y - tickLength)))
        }
        for i in 1..<rows {
            let y = frame.min.y + Double(i) * rowHeight
            ticks.append(.line(Vector2(frame.min.x, y), Vector2(frame.min.x - tickLength, y)))
            ticks.append(.line(Vector2(frame.max.x, y), Vector2(frame.max.x + tickLength, y)))
        }
        for tick in ticks {
            picture.strokes.append(SheetStroke(segments: [tick], width: style.zone, layer: .frame))
        }

        picture.texts += zoneLabels(frame: frame, columns: columns, rows: rows, standard: standard)

        if standard == .iso {
            let middle = Vector2(paper.x / 2, paper.y / 2)
            let marks: [SheetSegment] = [
                .line(Vector2(middle.x, 0), Vector2(middle.x, frame.min.y + centringMarkInside)),
                .line(Vector2(middle.x, paper.y), Vector2(middle.x, frame.max.y - centringMarkInside)),
                .line(Vector2(0, middle.y), Vector2(frame.min.x + centringMarkInside, middle.y)),
                .line(Vector2(paper.x, middle.y), Vector2(frame.max.x - centringMarkInside, middle.y)),
            ]
            for mark in marks {
                picture.strokes.append(SheetStroke(segments: [mark], width: style.frame, layer: .frame))
            }
        }
        return picture
    }

    private static func zoneLabels(frame: Rect2D, columns: Int, rows: Int, standard: DrawingStandard) -> [SheetText] {
        var texts: [SheetText] = []
        let h = DrawingStyle.of(standard).zoneLabelHeight
        let columnWidth = frame.width / Double(columns)
        let rowHeight = frame.height / Double(rows)
        for column in 0..<columns {
            let label = columnLabel(column, count: columns, standard: standard)
            let x = frame.min.x + (Double(column) + 0.5) * columnWidth
            texts.append(zoneText(label, centre: Vector2(x, frame.max.y + labelOffset), height: h))
            texts.append(zoneText(label, centre: Vector2(x, frame.min.y - labelOffset), height: h))
        }
        for row in 0..<rows {
            let label = rowLabel(row, count: rows, standard: standard)
            let y = frame.min.y + (Double(row) + 0.5) * rowHeight
            texts.append(zoneText(label, centre: Vector2(frame.min.x - labelOffset, y), height: h))
            texts.append(zoneText(label, centre: Vector2(frame.max.x + labelOffset, y), height: h))
        }
        return texts
    }

    /// ISO numbers the columns left to right, ASME right to left.
    static func columnLabel(_ column: Int, count: Int, standard: DrawingStandard) -> String {
        String(standard == .iso ? column + 1 : count - column)
    }

    /// Row 0 is the lowest. ISO letters run from the top down, ASME from the bottom up.
    static func rowLabel(_ row: Int, count: Int, standard: DrawingStandard) -> String {
        let index = standard == .iso ? count - 1 - row : row
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String(letters[index % letters.count])
    }

    /// A label whose middle (width and cap height) sits on `centre`.
    private static func zoneText(_ text: String, centre: Vector2, height: Double) -> SheetText {
        let run = DrawingText.layout(text, height: height)
        return SheetText(
            run: run, original: text, origin: Vector2(centre.x - run.width / 2, centre.y - height / 2), height: height,
            layer: .frame)
    }

    static func closedPoints(of rect: Rect2D) -> [Vector2] {
        [
            rect.min, Vector2(rect.max.x, rect.min.y), rect.max, Vector2(rect.min.x, rect.max.y), rect.min,
        ]
    }
}
