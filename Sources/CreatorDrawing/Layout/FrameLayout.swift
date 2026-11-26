import CreatorGeometry

/// The feature control frame in sheet millimetres (plan R4): rows 2h tall, compartments left to right.
public enum FrameLayout {
    /// What a compartment holds, left to right.
    enum Piece: Equatable {
        case text(String)
        case circled(String)
    }

    /// The pieces of a tolerance compartment: "Ø" and the value, then Ⓜ or Ⓛ, Ⓕ, Ⓣ, Ⓟ and its length.
    static func pieces(of row: ToleranceRow, format: NumberFormat) -> [Piece] {
        var pieces: [Piece] = [.text((row.zone == .diameter ? "Ø" : "") + GDTNumber.tolerance(row.value, format: format))]
        if let material = row.material { pieces.append(.circled(material == .maximum ? "M" : "L")) }
        if row.freeState { pieces.append(.circled("F")) }
        if row.tangentPlane { pieces.append(.circled("T")) }
        if let projected = row.projected {
            pieces.append(.circled("P"))
            if let length = projected.length { pieces.append(.text(GDTNumber.tolerance(length, format: format))) }
        }
        return pieces
    }

    /// The pieces of a datum compartment: its letter, then Ⓜ or Ⓛ.
    static func pieces(of reference: DatumReference) -> [Piece] {
        var pieces: [Piece] = [.text(reference.letter)]
        if let material = reference.material { pieces.append(.circled(material == .maximum ? "M" : "L")) }
        return pieces
    }

    static func width(of pieces: [Piece], h: Double) -> Double {
        let style = SymbolStyle.of(.iso)
        var total = 0.0
        for (index, piece) in pieces.enumerated() {
            if index > 0 { total += style.modifierGap * h }
            switch piece {
            case .text(let text): total += DrawingText.layout(text, height: h).width
            case .circled: total += style.circledAdvance * h
            }
        }
        return total
    }

    /// Each column's width, shared by the rows: the characteristic's, the tolerance's, then one per datum position.
    static func columns(of frame: FeatureControlFrame, h: Double, format: NumberFormat) -> [Double] {
        let style = SymbolStyle.of(.iso)
        let pad = style.framePadding * h
        var widths = [style.frameHeight * h, 0]
        for row in frame.rows {
            widths[1] = Swift.max(widths[1], width(of: pieces(of: row, format: format), h: h) + 2 * pad)
            for (index, datum) in row.datums.enumerated() {
                let cell = Swift.max(style.datumCellMinimum * h, width(of: pieces(of: datum), h: h) + 2 * pad)
                if widths.count <= 2 + index { widths.append(0) }
                widths[2 + index] = Swift.max(widths[2 + index], cell)
            }
        }
        return widths
    }

    private static func isStackedAsme(_ frame: FeatureControlFrame, standard: DrawingStandard) -> Bool {
        frame.isComposite && standard == .asme
    }

    /// The width of row `row`: the columns it has.
    private static func rowWidth(_ frame: FeatureControlFrame, row: Int, columns: [Double]) -> Double {
        columns.prefix(2 + frame.rows[row].datums.count).reduce(0, +)
    }

    /// The frame's size: its widest row by its rows' height.
    public static func size(of frame: FeatureControlFrame, h: Double, format: NumberFormat, standard: DrawingStandard) -> Vector2 {
        let columns = columns(of: frame, h: h, format: format)
        let widest = frame.rows.indices.map { rowWidth(frame, row: $0, columns: columns) }.max() ?? columns[0]
        return Vector2(widest, SymbolStyle.of(standard).frameHeight * h * Double(Swift.max(frame.rows.count, 1)))
    }

    /// The frame drawn with its top left at `topLeft`.
    public static func draw(
        _ frame: FeatureControlFrame, topLeft: Vector2, h: Double, format: NumberFormat, standard: DrawingStandard
    ) -> AnnotationDrawing {
        let style = SymbolStyle.of(standard)
        let rowHeight = style.frameHeight * h
        let columns = columns(of: frame, h: h, format: format)
        let stacked = isStackedAsme(frame, standard: standard)
        var builder = DrawingBuilder(style: .of(standard), height: h)
        var edges = [topLeft.x]
        for width in columns { edges.append(edges[edges.count - 1] + width) }
        var previousEnd: Double?
        for (index, row) in frame.rows.enumerated() {
            let top = topLeft.y - Double(index) * rowHeight, bottom = top - rowHeight
            let startColumn = stacked ? 1 : 0
            let end = edges[2 + row.datums.count]
            outline(&builder, from: edges[startColumn], to: end, top: top, bottom: bottom, omitTop: index > 0, omitLeft: stacked)
            if index > 0, let previous = previousEnd, end > previous { builder.line(Vector2(previous, top), Vector2(end, top)) }
            previousEnd = end
            for boundary in (startColumn + 1)..<(2 + row.datums.count) {
                builder.line(Vector2(edges[boundary], top), Vector2(edges[boundary], bottom))
            }
            if !stacked || index == 0 {
                let cellHeight = stacked ? 2 * rowHeight : rowHeight
                let centre = Vector2(edges[0] + columns[0] / 2, top - cellHeight / 2)
                let origin = Vector2(centre.x - h / 2, centre.y - h / 2)
                builder.drawing.segments += DrawingSymbols.characteristic(frame.characteristic, origin: origin, h: h)
            }
            place(
                pieces(of: row, format: format), in: edges[1]..<edges[2], baseline: bottom, h: h, builder: &builder)
            for (position, datum) in row.datums.enumerated() {
                place(pieces(of: datum), in: edges[2 + position]..<edges[3 + position], baseline: bottom, h: h, builder: &builder)
            }
        }
        if stacked {
            let bottom = topLeft.y - 2 * rowHeight
            builder.drawing.segments.append(
                .polyline([
                    Vector2(edges[1], topLeft.y), Vector2(edges[0], topLeft.y), Vector2(edges[0], bottom),
                    Vector2(edges[1], bottom), Vector2(edges[1], topLeft.y),
                ]))
        }
        return builder.finish()
    }

    // swiftlint:disable function_parameter_count
    /// A row's outline as one open or closed polyline, leaving out the sides another line already draws.
    private static func outline(
        _ builder: inout DrawingBuilder, from left: Double, to right: Double, top: Double, bottom: Double, omitTop: Bool,
        omitLeft: Bool
    ) {
        let topLeft = Vector2(left, top), topRight = Vector2(right, top)
        let bottomRight = Vector2(right, bottom), bottomLeft = Vector2(left, bottom)
        let points: [Vector2]
        switch (omitTop, omitLeft) {
        case (false, false): points = [topLeft, topRight, bottomRight, bottomLeft, topLeft]
        case (true, false): points = [topRight, bottomRight, bottomLeft, topLeft]
        case (false, true): points = [topLeft, topRight, bottomRight, bottomLeft]
        case (true, true): points = [topRight, bottomRight, bottomLeft]
        }
        builder.drawing.segments.append(.polyline(points))
    }
    // swiftlint:enable function_parameter_count

    /// Lays `pieces` centred in the compartment `span`, baselines `h / 2` above `baseline`.
    private static func place(_ pieces: [Piece], in span: Range<Double>, baseline: Double, h: Double, builder: inout DrawingBuilder) {
        let style = SymbolStyle.of(.iso)
        var x = (span.lowerBound + span.upperBound) / 2 - width(of: pieces, h: h) / 2
        for (index, piece) in pieces.enumerated() {
            if index > 0 { x += style.modifierGap * h }
            switch piece {
            case .text(let text):
                let run = DrawingText.layout(text, height: h)
                builder.drawing.texts.append(
                    PlacedText(run: run, original: text, origin: Vector2(x, baseline + h / 2), height: h, angle: 0))
                x += run.width
            case .circled(let letter):
                let advance = style.circledAdvance * h
                let circle = DrawingSymbols.circled(letter, center: Vector2(x + advance / 2, baseline + h), h: h)
                builder.drawing.segments += circle.segments
                builder.drawing.texts.append(circle.text)
                x += advance
            }
        }
    }

    /// A leader from `foot` to the middle of the first row's nearer side (plan R4): an arrowhead at the foot, a line and a
    /// shoulder ending on the frame.
    public static func leader(from foot: Vector2, toFrameAt rect: Rect2D, rowHeight: Double, style: AnnotationStyle) -> AnnotationDrawing {
        let y = rect.max.y - rowHeight / 2
        if foot.x < (rect.min.x + rect.max.x) / 2 {
            let knee = Vector2(rect.min.x - style.shoulder, y)
            return SheetDimensionLayout.leader(tip: foot, knee: knee, side: .right, style: style)
        }
        let knee = Vector2(rect.max.x + style.shoulder, y)
        return SheetDimensionLayout.leader(tip: foot, knee: knee, side: .left, style: style)
    }
}

extension FeatureControlFrame {
    /// A text for lists and warnings, never drawn (plan R11, in the sheet's number format): "Position Ø0.1 (M) | A | B (M)", rows joined " / ".
    public func plainText(format: NumberFormat) -> String {
        func modifier(_ condition: MaterialCondition?) -> String {
            switch condition {
            case .maximum: " (M)"
            case .least: " (L)"
            case nil: ""
            }
        }
        let rowTexts = rows.map { row -> String in
            var tolerance = (row.zone == .diameter ? "Ø" : "") + GDTNumber.tolerance(row.value, format: format)
            tolerance += modifier(row.material)
            if row.freeState { tolerance += " (F)" }
            if row.tangentPlane { tolerance += " (T)" }
            if let projected = row.projected {
                tolerance += " (P)"
                if let length = projected.length { tolerance += " " + GDTNumber.tolerance(length, format: format) }
            }
            return ([tolerance] + row.datums.map { $0.letter + modifier($0.material) }).joined(separator: " | ")
        }
        return characteristic.title + " " + rowTexts.joined(separator: " / ")
    }
}
