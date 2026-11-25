import CreatorGeometry

/// How a drawing writes numbers: the document's unit and precision, the standard's leading-zero habit and the decimal sign (plan R9).
public struct NumberFormat: Hashable, Sendable {
    public var units: DocumentUnits
    public var standard: DrawingStandard
    public var decimalSign: DecimalSign

    public init(units: DocumentUnits, standard: DrawingStandard, decimalSign: DecimalSign) {
        self.units = units
        self.standard = standard
        self.decimalSign = decimalSign
    }

    public init(units: DocumentUnits, settings: DrawingSettings) {
        self.init(units: units, standard: settings.standard, decimalSign: settings.decimalSign)
    }

    /// ISO may write a comma; ASME always writes a point.
    var usesComma: Bool { standard == .iso && decimalSign == .comma }

    /// ASME drops the leading zero of an inch value under one.
    var dropsLeadingZero: Bool { standard == .asme && units.length == .inches }

    /// Millimetres drop trailing zeros; inches keep them.
    var dropsTrailingZeros: Bool { units.length == .millimetres }
}
