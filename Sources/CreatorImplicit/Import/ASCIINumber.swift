/// Reads a decimal number from bytes. `strtod` depends on the locale, so ASCII STL is read with this instead.
enum ASCIINumber {
    /// A finite number with an optional sign, fraction and exponent, as a `Float`. `nil` for anything else, including "nan", "inf" and
    /// an empty token. Up to 19 significant digits are kept; the rest only move the decimal point.
    static func parse(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Float? {
        guard let value = parseDouble(bytes, range) else { return nil }
        let narrowed = Float(value)
        return narrowed.isFinite ? narrowed : nil
    }

    /// `parse` as a `Double`, for values that are computed with before they are narrowed (a 3MF's transforms).
    static func parseDouble(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Double? {
        var index = range.lowerBound
        let end = range.upperBound
        let negative = readSign(bytes, &index, end)
        guard let mantissa = readMantissa(bytes, &index, end) else { return nil }
        var exponent = mantissa.exponent
        if index < end, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            let exponentNegative = readSign(bytes, &index, end)
            guard let written = readInteger(bytes, &index, end) else { return nil }
            exponent += exponentNegative ? -written : written
        }
        guard index == end else { return nil }
        let value = scaled(Double(mantissa.value), exponent: exponent) * (negative ? -1 : 1)
        return value.isFinite ? value : nil
    }

    private static func readSign(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) -> Bool {
        guard index < end, bytes[index] == 0x2B || bytes[index] == 0x2D else { return false }
        index += 1
        return bytes[index - 1] == 0x2D
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    /// The digits of an integer, capped so a hostile exponent cannot overflow.
    private static func readInteger(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int, _ end: Int) -> Int? {
        var value = 0
        var sawDigit = false
        while index < end, isDigit(bytes[index]) {
            sawDigit = true
            value = min(value * 10 + Int(bytes[index] - 0x30), 100_000)
            index += 1
        }
        return sawDigit ? value : nil
    }

    /// The digits before and after the point as one integer and the power of ten it must be scaled by.
    private static func readMantissa(_ bytes: UnsafeBufferPointer<UInt8>, _ index: inout Int,
                                     _ end: Int) -> (value: UInt64, exponent: Int)? {
        var value: UInt64 = 0
        var significant = 0
        var exponent = 0
        var sawDigit = false
        var afterPoint = false
        while index < end, isDigit(bytes[index]) || (bytes[index] == 0x2E && !afterPoint) {
            defer { index += 1 }
            if bytes[index] == 0x2E { afterPoint = true; continue }
            sawDigit = true
            if significant < 19 {
                value = value * 10 + UInt64(bytes[index] - 0x30)
                if value > 0 { significant += 1 }
                if afterPoint { exponent -= 1 }
            } else if !afterPoint {
                exponent += 1
            }
        }
        return sawDigit ? (value, exponent) : nil
    }

    /// `value × 10^exponent`; exact when both are small, within a few ulps otherwise, which a `Float` hides.
    private static func scaled(_ value: Double, exponent: Int) -> Double {
        guard value != 0 else { return 0 }
        if exponent >= 0 { return exponent > 400 ? .infinity : value * power(exponent) }
        return exponent < -400 ? 0 : value / power(-exponent)
    }

    private static func power(_ exponent: Int) -> Double {
        var result = 1.0
        for _ in 0..<exponent { result *= 10 }
        return result
    }
}
