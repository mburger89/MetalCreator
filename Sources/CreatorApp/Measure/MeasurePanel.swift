import CreatorEditor
import CreatorGeometry
import CreatorStyle
import MetalUI

/// What the Measure panel says (measure spec, part A): the rows for a measurement and their text in the document's units.
enum MeasurePanelText {
    static let title = "Measure"
    static let prompt = "Click a face, edge or corner."
    static let measuring = "Measuring…"
    static let keep = "Keep"
    static let clearAll = "Clear All"
    static let lost = "No longer found"

    /// A kept measurement in one line: its distance, else the first reading in the panel's order; `lost` when its anchors don't resolve.
    static func keptSummary(_ entry: MeasureBook.Entry, units: DocumentUnits) -> String {
        guard entry.picks != nil else { return lost }
        let rows = rows(readings: entry.readings, distance: entry.distance?.distance, units: units)
        guard let first = rows.first else { return entry.isMeasuring ? measuring : "" }
        return entry.isApproximate ? approximate(first.text, meshResolution: entry.meshResolution, units: units) : first.text
    }

    /// A number that came from a mesh or a polyline: "≈ 12.3 mm", with the mesh's resolution when known.
    static func approximate(_ text: String, meshResolution: Double?, units: DocumentUnits) -> String {
        var result = "≈ " + text
        if let meshResolution { result += " · mesh " + units.fieldText(meshResolution, quantity: .length) }
        return result
    }

    /// The rows in the panel's fixed order. The distance lives on the session, not in its readings.
    static func rows(readings: [MeasureReading], distance: Double?, units: DocumentUnits) -> [(label: String, text: String)] {
        var all = readings
        if let distance { all.append(MeasureReading(quantity: .distance, value: distance)) }
        var rows: [(label: String, text: String)] = []
        for quantity in order {
            for reading in all where reading.quantity == quantity {
                rows.append((label(of: quantity), text(of: reading, units: units)))
            }
        }
        return rows
    }

    private static let order: [MeasureQuantity] = [.distance, .angle, .radius, .diameter, .length, .area, .centreDistance, .position]

    private static func label(of quantity: MeasureQuantity) -> String {
        switch quantity {
        case .distance: "Distance"
        case .angle: "Angle"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .length: "Length"
        case .area: "Area"
        case .centreDistance: "Centre distance"
        case .position: "Position"
        }
    }

    static func text(of reading: MeasureReading, units: DocumentUnits) -> String {
        switch reading.quantity {
        case .distance, .length, .centreDistance: units.fieldText(reading.value, quantity: .length)
        case .radius: units.fieldText(reading.value, quantity: .radius)
        case .diameter: units.fieldText(reading.value, quantity: .diameter)
        case .angle: units.fieldText(reading.value, quantity: .angle)
        case .area: areaText(reading.value, units: units)
        case .position:
            [reading.point?.x, reading.point?.y, reading.point?.z]
                .map { units.fieldText($0 ?? 0, quantity: .length) }
                .joined(separator: ", ")
        }
    }

    /// Square millimetres as the unit squared, with the length's digits (millimetres drop trailing zeros, as `fieldText` does).
    static func areaText(_ squareMillimetres: Double, units: DocumentUnits) -> String {
        let factor = units.length.millimetresPerUnit
        let shown = squareMillimetres / (factor * factor)
        let digits = units.fractionDigits
        let number = units.length == .inches
            ? DocumentUnits.number(shown, minimum: digits, maximum: digits)
            : DocumentUnits.number(shown, minimum: 0, maximum: digits)
        return number + units.suffix(for: .length) + "²"
    }
}

/// The Measure tool's panel: the readings of the picks, Clear and Done. It shows while Measure runs and no sketch is open.
struct MeasurePanel: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The card's inner width in points.
    static let width = SectionPanel.width

    var content: some ElementGroup {
        if model.sketch == nil, model.measure != nil || !model.measureBook.entries.isEmpty {
            let palette = Palette(themes)
            GlassPanel(.measurePanel) {
                VStack(alignment: .leading, spacing: Pixels(8)) {
                    Text(MeasurePanelText.title)
                        .font(.headline)
                        .foregroundStyle(palette.primaryText.color)
                    if let session = model.measure {
                    let rows = MeasurePanelText.rows(readings: session.readings, distance: session.distance?.distance, units: model.units)
                    let isApproximate = session.picks.contains(where: \.isApproximate)
                    if session.picks.isEmpty {
                        Text(MeasurePanelText.prompt)
                            .font(.callout)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: Pixels(6)) {
                            Text(rows[index].label).font(.callout).foregroundStyle(palette.secondaryText.color)
                            Spacer()
                            Text(isApproximate
                                 ? MeasurePanelText.approximate(rows[index].text, meshResolution: nil, units: model.units)
                                 : rows[index].text)
                                .font(.callout).foregroundStyle(palette.primaryText.color)
                        }
                    }
                    if session.isMeasuring {
                        Text(MeasurePanelText.measuring)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                    if let problem = session.problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(palette.statusWarning.color)
                    }
                    HStack(spacing: Pixels(8)) {
                        Button(MeasurePanelText.keep) { session.keepCurrent() }
                            .disabled(session.picks.isEmpty || session.isLost)
                        Button("Clear") { session.clear() }
                            .disabled(session.picks.isEmpty)
                        Button("Done") { model.setMeasure(false) }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                    }
                    ForEach(model.measureBook.entries) { entry in
                        let isLost = entry.picks == nil
                        HStack(spacing: Pixels(6)) {
                            Text(MeasurePanelText.keptSummary(entry, units: model.units))
                                .font(.callout)
                                .foregroundStyle((isLost ? palette.secondaryText : palette.primaryText).color)
                            Spacer()
                            Button("×") { model.measureBook.remove(entry.id) }
                        }
                    }
                    if !model.measureBook.entries.isEmpty {
                        Button(MeasurePanelText.clearAll) { model.measureBook.removeAll() }
                    }
                }
                .frame(width: Self.width.px)
            }
        }
    }
}
