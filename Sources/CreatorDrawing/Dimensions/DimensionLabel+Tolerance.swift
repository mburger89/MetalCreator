import CreatorGeometry

extension DimensionLabel {
    static let fitsOnSizesOnly = "Fits apply to sizes: a diameter or a distance between two faces."

    // swiftlint:disable function_parameter_count
    // Reason: the plan's interface fixes this function's seven parameters.
    /// A size (a distance, radius or diameter) with its tolerance (plan R10); a fit is refused on a radius.
    public static func size(
        _ mm: Double, symbol: SizeSymbol, tolerance: DimensionTolerance, precision: Int?, prefix: String, suffix: String,
        format: NumberFormat
    ) throws(DrawingRefusal) -> DimensionLabel {
        let mark =
            switch symbol {
            case .none: ""
            case .radius: "R"
            case .diameter: "Ø"
            }
        if case .fit = tolerance, symbol == .radius { throw DrawingRefusal(sentence: fitsOnSizesOnly) }
        let number = DimensionNumber.length(mm, precision: precision, format: format)
        let label: DimensionLabel
        switch tolerance {
        case .general: label = DimensionLabel(lines: [[.text(mark + number)]])
        case .reference: label = DimensionLabel(lines: [[.text("(" + mark + number + ")")]])
        case .basic: label = DimensionLabel(lines: [[.text(mark + number)]], isBoxed: true)
        case .symmetric, .deviation: label = toleranced(mm, mark: mark, number: number, tolerance: tolerance, format: format)
        case .limits(let upper, let lower): label = limited(mm, mark: mark, upper: upper, lower: lower, number: number, format: format)
        case .fit(let designation, let showsDeviations):
            let limits = try ISO286.limits(of: designation, size: mm)
            let upper = fitDeviation(limits.upper, format: format)
            let lower = fitDeviation(limits.lower, format: format)
            let trailing = showsDeviations ? "(" + upper + "/" + lower + ")" : ""
            label = DimensionLabel(lines: [[.text(mark + number + " " + designation.text)]], trailing: trailing)
        }
        return label.typed(prefix: prefix, suffix: suffix)
    }
    // swiftlint:enable function_parameter_count

    private static let toleranceLimit = 4

    private static func toleranceD(_ value: Double, _ format: NumberFormat) -> Double { format.units.value(fromMillimetres: value) }

    /// A symmetric tolerance written beside the value, or a deviation stacked beside it.
    private static func toleranced(
        _ mm: Double, mark: String, number: String, tolerance: DimensionTolerance, format: NumberFormat
    ) -> DimensionLabel {
        let base = format.dropsTrailingZeros ? 0 : DimensionNumber.places(of: number)
        switch tolerance {
        case .symmetric(let value):
            let size = toleranceD(Swift.abs(value), format)
            let places = Swift.max(base, DimensionNumber.neededPlaces(size, limit: toleranceLimit))
            let text = DimensionNumber.render(size, places: places, keepZeros: !format.dropsTrailingZeros, format: format).text
            return DimensionLabel(lines: [[.text(mark + number + " ±" + text)]])
        case .deviation(let upper, let lower):
            let places = Swift.max(
                base, DimensionNumber.neededPlaces(toleranceD(upper, format), limit: toleranceLimit),
                DimensionNumber.neededPlaces(toleranceD(lower, format), limit: toleranceLimit))
            let stack = StackedText(
                upper: DimensionNumber.signed(upper, places: places, format: format),
                lower: DimensionNumber.signed(lower == 0 ? -0.0 : lower, places: places, format: format))
            return DimensionLabel(lines: [[.text(mark + number)]], stack: stack)
        default:
            return DimensionLabel(lines: [[.text(mark + number)]])
        }
    }

    /// The two limit sizes stacked, to the same decimals.
    private static func limited(
        _ mm: Double, mark: String, upper: Double, lower: Double, number: String, format: NumberFormat
    ) -> DimensionLabel {
        let base = format.dropsTrailingZeros ? 0 : DimensionNumber.places(of: number)
        let values = [toleranceD(mm, format), toleranceD(mm + upper, format), toleranceD(mm + lower, format)]
        let places = values.reduce(base) { Swift.max($0, DimensionNumber.neededPlaces($1, limit: toleranceLimit)) }
        func fixed(_ value: Double) -> String { DimensionNumber.render(value, places: places, keepZeros: true, format: format).text }
        let stack = StackedText(upper: fixed(values[1]), lower: fixed(values[2]))
        return DimensionLabel(lines: mark.isEmpty ? [[]] : [[.text(mark)]], stack: stack)
    }

    /// An angle with its tolerance, in radians; fits are refused.
    public static func angle(
        _ radians: Double, tolerance: DimensionTolerance, precision: Int?, prefix: String, suffix: String, format: NumberFormat
    ) throws(DrawingRefusal) -> DimensionLabel {
        if case .fit = tolerance { throw DrawingRefusal(sentence: fitsOnSizesOnly) }
        let number = DimensionNumber.angle(radians, precision: precision, format: format)
        let degrees = DimensionNumber.degrees(radians)
        func plain(_ value: Double, places: Int) -> String {
            DimensionNumber.render(value, places: places, keepZeros: true, format: format, leadingZero: true).text + "°"
        }
        func signedDegrees(_ value: Double, places: Int) -> String {
            let made = DimensionNumber.render(value, places: places, keepZeros: true, format: format, sign: .always, leadingZero: true)
            return (made.isZero ? "0" : made.text) + "°"
        }
        let limit = 3
        let label: DimensionLabel
        switch tolerance {
        case .general, .fit:
            label = DimensionLabel(lines: [[.text(number)]])
        case .reference:
            label = DimensionLabel(lines: [[.text("(" + number + ")")]])
        case .basic:
            label = DimensionLabel(lines: [[.text(number)]], isBoxed: true)
        case .symmetric(let value):
            let size = DimensionNumber.degrees(Swift.abs(value))
            let text = DimensionNumber.render(
                size, places: DimensionNumber.neededPlaces(size, limit: limit), keepZeros: false, format: format, leadingZero: true
            ).text
            label = DimensionLabel(lines: [[.text(number + " ±" + text + "°")]])
        case .deviation(let upper, let lower):
            let high = DimensionNumber.degrees(upper)
            let low = DimensionNumber.degrees(lower)
            let places = Swift.max(DimensionNumber.neededPlaces(high, limit: limit), DimensionNumber.neededPlaces(low, limit: limit))
            label = DimensionLabel(
                lines: [[.text(number)]],
                stack: StackedText(upper: signedDegrees(high, places: places), lower: signedDegrees(low == 0 ? -0.0 : low, places: places)))
        case .limits(let upper, let lower):
            let high = degrees + DimensionNumber.degrees(upper)
            let low = degrees + DimensionNumber.degrees(lower)
            let places = Swift.max(
                DimensionNumber.neededPlaces(degrees, limit: limit), DimensionNumber.neededPlaces(high, limit: limit),
                DimensionNumber.neededPlaces(low, limit: limit))
            label = DimensionLabel(lines: [[]], stack: StackedText(upper: plain(high, places: places), lower: plain(low, places: places)))
        }
        return label.typed(prefix: prefix, suffix: suffix)
    }

    /// One fit deviation: millimetres to 3 decimals (4 when it needs them), inches to 4; a zero is "0".
    private static func fitDeviation(_ mm: Double, format: NumberFormat) -> String {
        let value = format.units.value(fromMillimetres: mm)
        let places = format.units.length == .inches ? 4 : Swift.max(3, DimensionNumber.neededPlaces(value, limit: 4))
        let made = DimensionNumber.render(value, places: places, keepZeros: true, format: format, sign: .always)
        return made.isZero ? "0" : made.text
    }
}
