import Foundation

/// The rules of geometric tolerancing as warnings in words (plan R8). Nothing is refused for a rule; the rules read only what is saved,
/// so a lost frame is still checked.
public enum GDTRules {
    /// What the rules need, made once per compose (plan R18).
    public struct Context: Sendable {
        public var standard: DrawingStandard
        /// Letter to how many datum feature symbols of the document carry it.
        public var definedLetters: [String: Int]
        /// The views of the sheet with a basic dimension.
        public var basicViews: Set<ViewID>

        public init(standard: DrawingStandard, definedLetters: [String: Int], basicViews: Set<ViewID>) {
            self.standard = standard
            self.definedLetters = definedLetters
            self.basicViews = basicViews
        }

        public static func make(document: DrawingDocument, sheet: DrawingSheet) -> Context {
            var counts: [String: Int] = [:]
            for letter in DatumLetters.letters(in: document) { counts[letter, default: 0] += 1 }
            var views = Set<ViewID>()
            for annotation in sheet.annotations {
                if let view = annotation.view, case .dimension(let dimension) = annotation.kind, dimension.tolerance == .basic {
                    views.insert(view)
                }
            }
            return Context(standard: document.settings.standard, definedLetters: counts, basicViews: views)
        }
    }

    public static func formWithDatum(_ characteristic: GeometricCharacteristic) -> String {
        "\(characteristic.title) is a form tolerance and takes no datum."
    }

    public static func needsDatum(_ characteristic: GeometricCharacteristic) -> String {
        "\(characteristic.title) needs a datum reference."
    }

    public static let positionNeedsBasic =
        "A position tolerance's feature should be located by basic (boxed) dimensions, and no dimension in this view is basic."

    public static func undefined(_ letter: String) -> String {
        "Datum \(letter) isn't defined: no datum symbol on this drawing has that letter."
    }

    public static func duplicate(_ letter: String) -> String {
        "Datum \(letter) is defined by more than one datum symbol on this drawing."
    }

    public static let asmeConcentricity = "Concentricity isn't in ASME Y14.5-2018; use position, runout or profile instead."
    public static let asmeSymmetry = "Symmetry isn't in ASME Y14.5-2018; use position or profile instead."
    public static let compositeDatums = "The lower row of a composite frame takes the upper row's datums or fewer, in the same order."

    /// The warnings of one annotation, in R8's order; none for any kind but a datum symbol or a frame.
    public static func warnings(for annotation: DrawingAnnotation, context: Context) -> [String] {
        switch annotation.kind {
        case .datumFeature(let datum):
            return (context.definedLetters[datum.letter] ?? 0) > 1 ? [duplicate(datum.letter)] : []
        case .featureControl(let frame):
            return frameWarnings(frame, view: annotation.view, context: context)
        default:
            return []
        }
    }

    private static func frameWarnings(_ frame: FeatureControlFrame, view: ViewID?, context: Context) -> [String] {
        let characteristic = frame.characteristic
        var result = datumPresence(frame)
        if characteristic == .position, !(view.map { context.basicViews.contains($0) } ?? false) {
            result.append(positionNeedsBasic)
        }
        var seen = Set<String>()
        for reference in frame.rows.flatMap(\.datums) where seen.insert(reference.letter).inserted {
            if (context.definedLetters[reference.letter] ?? 0) == 0 { result.append(undefined(reference.letter)) }
        }
        if context.standard == .asme {
            if characteristic == .concentricity { result.append(asmeConcentricity) }
            if characteristic == .symmetry { result.append(asmeSymmetry) }
        }
        if frame.rows.count == 2 {
            let upper = frame.rows[0].datums.map(\.letter)
            let lower = frame.rows[1].datums.map(\.letter)
            if lower.count > upper.count || Array(upper.prefix(lower.count)) != lower { result.append(compositeDatums) }
        }
        return result
    }

    /// Rules 1 and 2.
    private static func datumPresence(_ frame: FeatureControlFrame) -> [String] {
        let characteristic = frame.characteristic
        switch characteristic.family {
        case .form:
            return frame.rows.contains { !$0.datums.isEmpty } ? [formWithDatum(characteristic)] : []
        case .orientation, .location, .runout:
            return (frame.rows.first?.datums ?? []).isEmpty ? [needsDatum(characteristic)] : []
        case .profile:
            return []
        }
    }
}
