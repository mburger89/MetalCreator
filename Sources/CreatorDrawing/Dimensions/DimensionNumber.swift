import CreatorGeometry

/// Numbers in dimension text, written from integers so no platform formatter or locale can change a byte (plan R9).
public enum DimensionNumber {
    /// A length in millimetres as the document's unit: `precision ?? units.fractionDigits` decimals, half away from zero.
    public static func length(_ mm: Double, precision: Int?, format: NumberFormat) -> String {
        let value = format.units.value(fromMillimetres: mm)
        let places = precision.map(clamped) ?? format.units.fractionDigits
        return render(value, places: places, keepZeros: !format.dropsTrailingZeros, format: format).text
    }

    /// An angle in radians as degrees: up to `precision ?? 1` decimals, trailing zeros dropped, then "°".
    public static func angle(_ radians: Double, precision: Int?, format: NumberFormat) -> String {
        let places = precision.map(clamped) ?? 1
        return render(degrees(radians), places: places, keepZeros: false, format: format, leadingZero: true).text + "°"
    }

    /// How many digits follow the decimal mark in `text`.
    public static func places(of text: String) -> Int {
        guard let mark = text.lastIndex(where: { $0 == "." || $0 == "," }) else { return 0 }
        return text[text.index(after: mark)...].prefix { $0.isNumber }.count
    }

    /// A deviation in millimetres with a sign and exactly `places` decimals (plan R10). A zero is "0" in millimetres; in inches it keeps
    /// its decimals and takes the sign its bit says, so a lower deviation passes `-0.0`.
    public static func signed(_ mm: Double, places: Int, format: NumberFormat) -> String {
        let value = format.units.value(fromMillimetres: mm)
        let made = render(value, places: clamped(places), keepZeros: true, format: format, sign: .always)
        if made.isZero, format.units.length == .millimetres { return "0" }
        return made.text
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    static func clamped(_ places: Int) -> Int { Swift.max(0, Swift.min(9, places)) }

    /// The fewest decimals (up to `limit`) that write `value` exactly enough.
    static func neededPlaces(_ value: Double, limit: Int) -> Int {
        var scale = 1.0
        for places in 0...limit {
            if Swift.abs((value * scale).rounded() / scale - value) <= 1e-9 { return places }
            scale *= 10
        }
        return limit
    }

    enum SignMode { case minusOnly, always }

    struct Rendered { var text: String; var isZero: Bool }

    /// The one writer: `value` rounded half away from zero to `places`, from integers.
    static func render(
        _ value: Double, places: Int, keepZeros: Bool, format: NumberFormat, sign: SignMode = .minusOnly, leadingZero: Bool? = nil
    ) -> Rendered {
        guard value.isFinite else { return Rendered(text: "0", isZero: true) }
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        let scaled = (Swift.abs(value) * scale * (1 + 1e-12)).rounded()
        guard scaled < 9.0e15 else { return Rendered(text: "0", isZero: true) }
        let units = UInt64(scaled)
        var divisor: UInt64 = 1
        for _ in 0..<places { divisor *= 10 }
        let whole = units / divisor
        var fraction = String(units % divisor)
        if places > 0 { fraction = String(repeating: "0", count: places - fraction.count) + fraction }
        if !keepZeros { while fraction.hasSuffix("0") { fraction.removeLast() } }
        let mark = format.usesComma ? "," : "."
        let drops = leadingZero.map { !$0 } ?? format.dropsLeadingZero
        var body: String
        if fraction.isEmpty {
            body = String(whole)
        } else {
            body = (whole == 0 && drops ? "" : String(whole)) + mark + fraction
        }
        let isZero = units == 0
        let prefix: String
        switch sign {
        case .minusOnly: prefix = value < 0 && !isZero ? "-" : ""
        case .always: prefix = value.sign == .minus ? "-" : "+"
        }
        body = prefix + body
        return Rendered(text: body, isZero: isZero)
    }
}
