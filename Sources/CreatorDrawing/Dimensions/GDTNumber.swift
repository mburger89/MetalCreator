import CreatorGeometry

/// Numbers in tolerance frames and surface symbols (plan R4, R6): written from integers like `DimensionNumber`.
public enum GDTNumber {
    /// The most decimals a tolerance value may need.
    static let tolerancePlaces = 4
    /// The most decimals a roughness value in micrometres may need.
    static let roughnessPlaces = 3
    /// Micrometres per microinch: one micrometre is 1 / 0.0254 microinches. The editor reads typed microinches with it too.
    public static let micrometresPerMicroinch = 0.0254

    /// A tolerance in millimetres as the document's unit, with as many decimals as it needs (up to 4), never rounded to the
    /// document's precision; inches keep at least the document's precision (".005" in ASME).
    public static func tolerance(_ mm: Double, format: NumberFormat) -> String {
        let value = format.units.value(fromMillimetres: mm)
        guard value.isFinite else { return "?" }
        var places = DimensionNumber.neededPlaces(Swift.abs(value), limit: tolerancePlaces)
        if format.units.length == .inches { places = Swift.max(places, format.units.fractionDigits) }
        return DimensionNumber.render(value, places: places, keepZeros: !format.dropsTrailingZeros, format: format).text
    }

    /// A roughness in micrometres: the same number with up to 3 decimals in a millimetre document, microinches rounded to a
    /// whole number in an inch document; the unit is never written.
    public static func roughness(_ micrometres: Double, format: NumberFormat) -> String {
        guard micrometres.isFinite else { return "?" }
        if format.units.length == .inches {
            return DimensionNumber.render(
                micrometres / micrometresPerMicroinch, places: 0, keepZeros: false, format: format, leadingZero: true
            ).text
        }
        let places = DimensionNumber.neededPlaces(Swift.abs(micrometres), limit: roughnessPlaces)
        return DimensionNumber.render(micrometres, places: places, keepZeros: false, format: format).text
    }
}
