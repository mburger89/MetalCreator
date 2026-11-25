import CreatorDrawing
import MetalUI

/// The inspector for one dimension (plan R20): kind, the value it shows (or why it is lost and how to attach it again), precision,
/// tolerance with its fields, the general tolerance the size would get, prefix and suffix.
struct DimensionInspector: Component {
    let model: DrawingEditorModel
    let id: AnnotationID
    let dimension: DrawingDimension
    let report: AnnotationReport?
    let colors: DrawingColors

    static let reattachSentence = "Click a line to attach it again."

    /// The kinds the Kind menu offers for this dimension, as (title, kind) pairs; empty for a kind with no choice.
    static func kindChoices(of kind: DrawingDimensionKind) -> [(title: String, kind: DrawingDimensionKind)] {
        switch kind {
        case .linear: [("Horizontal", .linear(.horizontal)), ("Vertical", .linear(.vertical)), ("Aligned", .linear(.aligned))]
        case .baseline: [("Horizontal", .baseline(.horizontal)), ("Vertical", .baseline(.vertical))]
        case .chain: [("Horizontal", .chain(.horizontal)), ("Vertical", .chain(.vertical))]
        case .radius, .diameter: [("Radius", .radius), ("Diameter", .diameter)]
        case .ordinate, .angle, .chamfer: []
        }
    }

    static func title(of kind: DrawingDimensionKind) -> String {
        switch kind {
        case .linear(let direction), .baseline(let direction), .chain(let direction):
            direction == .horizontal ? "Horizontal" : direction == .vertical ? "Vertical" : "Aligned"
        case .ordinate: "Ordinate"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .angle: "Angle"
        case .chamfer: "Chamfer"
        }
    }

    /// The "General" row: what the drawing's general tolerance gives this size (R10); "—" when none applies.
    var generalText: String {
        let use: GeneralToleranceUse
        switch dimension.kind {
        case .radius, .chamfer: use = .brokenEdge
        case .angle: use = .angle
        default: use = .length
        }
        let size = report?.current?.values.first ?? 0
        let places = dimension.precision ?? model.units.fractionDigits
        return model.document.settings.generalTolerance.summary(for: size, use: use, places: places) ?? "—"
    }

    var lostReason: String? {
        if case .lost(let reason)? = report?.status { return reason.sentence }
        return nil
    }

    var content: some ElementGroup {
        let choices = Self.kindChoices(of: dimension.kind)
        VStack(alignment: .leading, spacing: Pixels(8)) {
            Text("Dimension").font(.headline).foregroundStyle(colors.primary.color)
            DrawingRow("Kind", colors: colors) {
                if choices.isEmpty {
                    Text(Self.title(of: dimension.kind)).font(.callout).foregroundStyle(colors.primary.color)
                } else {
                    DrawingMenu(
                        options: choices.map(\.title), selected: choices.firstIndex { $0.kind == dimension.kind }) {
                        model.setDimensionKind(choices[$0].kind, of: id)
                    }
                }
            }
            DrawingRow("Value", colors: colors) {
                Text(report?.label ?? "?").font(.callout).foregroundStyle(
                    (lostReason == nil ? colors.primary : colors.warning).color)
            }
            if let lostReason {
                Text(lostReason).font(.caption).foregroundStyle(colors.warning.color)
                Text(Self.reattachSentence).font(.caption).foregroundStyle(colors.secondary.color)
            }
            DrawingRow("Precision", colors: colors) {
                DrawingMenu(
                    options: ["Document (\(model.units.fractionDigits))", "0", "1", "2", "3", "4"],
                    selected: dimension.precision.map { $0 + 1 } ?? 0) { index in
                    model.setPrecision(index == 0 ? nil : index - 1, of: id)
                }
            }
            ToleranceControls(model: model, id: id, dimension: dimension, colors: colors)
            DrawingRow("General", colors: colors) {
                Text(generalText).font(.callout).foregroundStyle(colors.secondary.color)
            }
            DrawingRow("Prefix", colors: colors) {
                DrawingField(model: model, text: dimension.prefix, width: 150) { model.setPrefix($0, of: id) }
            }
            DrawingRow("Suffix", colors: colors) {
                DrawingField(model: model, text: dimension.suffix, width: 150) { model.setSuffix($0, of: id) }
            }
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning.color)
            }
        }
        .frame(width: drawingInspectorWidth.px)
    }
}
