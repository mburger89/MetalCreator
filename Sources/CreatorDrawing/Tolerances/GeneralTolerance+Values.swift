/// What a general tolerance is asked about.
public enum GeneralToleranceUse: Sendable {
    case length, brokenEdge, angle
}

extension GeneralTolerance {
    /// The ± deviation in millimetres a size without its own tolerance gets, nil when the table gives none (and for
    /// angles and a typed text).
    public func value(for size: Double, use: GeneralToleranceUse, places: Int) -> Double? {
        switch self {
        case .iso2768(let tolerance, _):
            switch use {
            case .length: return ISO2768.linear(size, class: tolerance)
            case .brokenEdge: return ISO2768.brokenEdge(size, class: tolerance)
            case .angle: return nil
            }
        case .asme(let table):
            guard use != .angle, let row = table.rows.first(where: { $0.places == places }),
                let value = Double(row.text)
            else { return nil }
            return value * table.unit.millimetresPerUnit
        case .text:
            return nil
        }
    }

    /// The inspector's info text: "±0.2 (ISO 2768-m)", "ISO 2768-m" for an angle, nil when none applies.
    public func summary(for size: Double, use: GeneralToleranceUse, places: Int) -> String? {
        switch self {
        case .iso2768(let tolerance, _):
            if use == .angle { return "ISO 2768-\(tolerance.rawValue)" }
            guard let value = value(for: size, use: use, places: places) else { return nil }
            return "±\(Self.plain(value)) (ISO 2768-\(tolerance.rawValue))"
        case .asme(let table):
            guard use != .angle, let row = table.rows.first(where: { $0.places == places }) else { return nil }
            return "±" + row.text
        case .text:
            return nil
        }
    }

    /// A tolerance's digits with no locale: four decimals at most, trailing zeros dropped.
    private static func plain(_ value: Double) -> String {
        let scaled = Int((value * 10_000).rounded())
        var text = String(scaled / 10_000)
        var fraction = String(scaled % 10_000)
        fraction = String(repeating: "0", count: 4 - fraction.count) + fraction
        while fraction.last == "0" { fraction.removeLast() }
        if !fraction.isEmpty { text += "." + fraction }
        return text
    }
}
