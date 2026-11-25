import CreatorGeometry

/// The rows of the title block (plan R15), in order.
public enum TitleBlockKey: String, CaseIterable, Sendable {
    case owner, drawnBy, date, title, material, mass, scale, projection, drawingNumber, revision, size, sheet, tolerance

    /// Whether the value is typed (in `TitleBlock`, or `DrawingSettings.generalTolerance`) rather than automatic.
    public var isTyped: Bool {
        switch self {
        case .owner, .drawnBy, .date, .title, .material, .drawingNumber, .revision, .tolerance: true
        case .mass, .scale, .projection, .size, .sheet: false
        }
    }
}

public struct TitleBlockField: Hashable, Sendable {
    public var key: TitleBlockKey
    /// Millimetres from the block's bottom left.
    public var rect: Rect2D
    public var valueHeight: Double
    public var label: String

    public init(key: TitleBlockKey, rect: Rect2D, valueHeight: Double, label: String) {
        self.key = key
        self.rect = rect
        self.valueHeight = valueHeight
        self.label = label
    }
}

public enum TitleBlockLayout {
    public static let width = 180.0
    public static let height = 40.0
    static let inset = 1.5
    static let labelBaseline = 2.5
    static let symbolHeight = 2.5

    /// R15's table: rects from the block's bottom left, with each standard's labels.
    public static func fields(for standard: DrawingStandard) -> [TitleBlockField] {
        let iso = standard == .iso
        return rows.map { row in
            TitleBlockField(
                key: row.key, rect: Rect2D(min: Vector2(row.x0, row.y0), max: Vector2(row.x1, row.y1)),
                valueHeight: row.height, label: iso ? row.isoLabel : row.asmeLabel)
        }
    }

    private struct Row {
        var key: TitleBlockKey
        var x0, x1, y0, y1, height: Double
        var isoLabel, asmeLabel: String
    }

    private static let rows: [Row] = [
        Row(key: .owner, x0: 0, x1: 110, y0: 30, y1: 40, height: 3.5, isoLabel: "Owner", asmeLabel: "COMPANY"),
        Row(key: .drawnBy, x0: 110, x1: 145, y0: 30, y1: 40, height: 2.5, isoLabel: "Drawn by", asmeLabel: "DRAWN"),
        Row(key: .date, x0: 145, x1: 180, y0: 30, y1: 40, height: 2.5, isoLabel: "Date", asmeLabel: "DATE"),
        Row(key: .title, x0: 0, x1: 110, y0: 10, y1: 30, height: 7, isoLabel: "Title", asmeLabel: "TITLE"),
        Row(key: .material, x0: 110, x1: 180, y0: 20, y1: 30, height: 2.5, isoLabel: "Material", asmeLabel: "MATERIAL"),
        Row(key: .mass, x0: 110, x1: 140, y0: 10, y1: 20, height: 2.5, isoLabel: "Mass", asmeLabel: "WEIGHT"),
        Row(key: .scale, x0: 140, x1: 162, y0: 10, y1: 20, height: 2.5, isoLabel: "Scale", asmeLabel: "SCALE"),
        Row(key: .projection, x0: 162, x1: 180, y0: 10, y1: 20, height: 0, isoLabel: "", asmeLabel: ""),
        Row(
            key: .drawingNumber, x0: 0, x1: 80, y0: 0, y1: 10, height: 5, isoLabel: "Drawing number", asmeLabel: "DWG NO."),
        Row(key: .revision, x0: 80, x1: 100, y0: 0, y1: 10, height: 3.5, isoLabel: "Revision", asmeLabel: "REV"),
        Row(key: .size, x0: 100, x1: 120, y0: 0, y1: 10, height: 2.5, isoLabel: "Size", asmeLabel: "SIZE"),
        Row(key: .sheet, x0: 120, x1: 145, y0: 0, y1: 10, height: 2.5, isoLabel: "Sheet", asmeLabel: "SHEET"),
        Row(
            key: .tolerance, x0: 145, x1: 180, y0: 0, y1: 10, height: 2.5, isoLabel: "General tolerances",
            asmeLabel: "TOLERANCES"),
    ]

    /// The block's bottom-left corner: its bottom right sits on the frame's inside bottom right.
    public static func origin(for sheet: DrawingSheet, standard: DrawingStandard) -> Vector2 {
        let frame = SheetFrame.rect(for: sheet, standard: standard)
        return Vector2(frame.max.x - width, frame.min.y)
    }

    /// The block's strokes and texts. `sheetIndex` counts from 0 and is shown from 1.
    public static func picture(
        sheet: DrawingSheet, settings: DrawingSettings, facts: TitleBlockFacts, sheetIndex: Int, sheetCount: Int
    ) -> SheetPicture {
        let standard = settings.standard
        let style = DrawingStyle.of(standard)
        let origin = origin(for: sheet, standard: standard)
        var picture = SheetPicture(size: sheet.paperSize)
        let outline = Rect2D(min: origin, max: Vector2(origin.x + width, origin.y + height))
        picture.strokes.append(
            SheetStroke(segments: [.polyline(SheetFrame.closedPoints(of: outline))], width: style.frame, layer: .frame))

        let values = Values(
            sheet: sheet, settings: settings, facts: facts, position: "\(sheetIndex + 1)", count: "\(sheetCount)")
        for field in fields(for: standard) {
            let rect = Rect2D(min: field.rect.min + origin, max: field.rect.max + origin)
            picture.strokes.append(
                SheetStroke(segments: [.polyline(SheetFrame.closedPoints(of: rect))], width: style.zone, layer: .frame))
            if !field.label.isEmpty { picture.texts.append(labelText(field.label, in: rect, style: style)) }
            if field.key == .projection {
                picture.strokes.append(
                    contentsOf: DrawingSymbols.projectionSymbol(
                        firstAngle: standard.isFirstAngle, center: rect.center, h: symbolHeight, thin: style.thin))
            } else if let text = valueText(values.value(of: field.key), field: field, in: rect) {
                picture.texts.append(text)
            }
        }
        return picture
    }

    private static func labelText(_ label: String, in rect: Rect2D, style: DrawingStyle) -> SheetText {
        SheetText(
            run: DrawingText.layout(label, height: style.fieldLabelHeight), original: label,
            origin: Vector2(rect.min.x + inset, rect.max.y - labelBaseline), height: style.fieldLabelHeight, layer: .frame)
    }

    private static func valueText(_ value: String, field: TitleBlockField, in rect: Rect2D) -> SheetText? {
        guard !value.isEmpty else { return nil }
        let fit = DrawingText.fitted(value, height: field.valueHeight, width: rect.width - 2 * inset)
        return SheetText(
            run: fit.run, original: value, origin: Vector2(rect.min.x + inset, rect.min.y + inset), height: fit.height,
            layer: .text)
    }

    private struct Values {
        var sheet: DrawingSheet
        var settings: DrawingSettings
        var facts: TitleBlockFacts
        var position: String
        var count: String

        func value(of key: TitleBlockKey) -> String {
            key.isTyped ? typedValue(of: key) : automaticValue(of: key)
        }

        private func typedValue(of key: TitleBlockKey) -> String {
            let block = sheet.titleBlock
            switch key {
            case .owner: return block.owner
            case .drawnBy: return block.drawnBy
            case .date: return block.date
            case .title: return block.title
            case .material: return block.material
            case .drawingNumber: return block.drawingNumber
            case .revision: return block.revision
            default: return settings.generalTolerance
            }
        }

        private func automaticValue(of key: TitleBlockKey) -> String {
            switch key {
            case .mass: return facts.massText ?? ""
            case .scale: return sheet.scale.text(for: settings.standard)
            case .size: return sheet.size.title
            case .sheet: return settings.standard == .iso ? "\(position) / \(count)" : "\(position) OF \(count)"
            default: return ""
            }
        }
    }
}
