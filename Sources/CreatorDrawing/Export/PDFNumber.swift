/// Numbers for PDF and DXF text, written from integers so no platform formatter or locale can change a byte (plan R23).
public enum PDFNumber {
    /// `value` with at most `decimals` decimals (0 to 9), trailing zeros dropped, "-0" written "0".
    public static func format(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "0" }
        let places = Swift.max(0, Swift.min(9, decimals))
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        let scaled = (Swift.abs(value) * scale).rounded()
        guard scaled < 9.0e15 else { return "0" }
        let units = UInt64(scaled)
        if units == 0 { return "0" }
        var divisor: UInt64 = 1
        for _ in 0..<places { divisor *= 10 }
        let whole = units / divisor
        var fraction = String(units % divisor)
        if places > 0 {
            fraction = String(repeating: "0", count: places - fraction.count) + fraction
            while fraction.hasSuffix("0") { fraction.removeLast() }
        }
        let sign = value < 0 ? "-" : ""
        return fraction.isEmpty || places == 0 ? sign + String(whole) : sign + String(whole) + "." + fraction
    }
}
