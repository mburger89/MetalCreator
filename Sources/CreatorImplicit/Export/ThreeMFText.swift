import Foundation

/// The text of a 3MF model (implicit spec §5.3): numbers with six significant digits, written by hand because `FormatStyle` takes
/// microseconds a number and a part has millions, and names made safe for XML.
enum ThreeMFText {
    private static let powers: [Double] = (0...30).map { pow(10, Double($0)) }

    /// Appends `value` to six significant digits, as plain decimal text with no exponent and no trailing zeros ("0.000123457",
    /// "12.3457", "123457", "-5"). A value that is not finite is written as 0.
    static func append(_ value: Float, to bytes: inout [UInt8]) {
        let number = Double(value)
        guard number.isFinite, number != 0 else {
            bytes.append(UInt8(ascii: "0"))
            return
        }
        if number < 0 { bytes.append(UInt8(ascii: "-")) }
        let magnitude = abs(number)
        var exponent = Int(floor(log10(magnitude)))
        // Six digits: 100000 ... 999999.
        var digits = (magnitude * scale(5 - exponent)).rounded()
        if digits >= 1_000_000 {
            exponent += 1
            digits = (magnitude * scale(5 - exponent)).rounded()
        }
        var text = Array(String(Int(digits)).utf8)
        let pointAt = exponent + 1  // digits before the point
        if pointAt <= 0 {
            text = [UInt8(ascii: "0"), UInt8(ascii: ".")] + [UInt8](repeating: UInt8(ascii: "0"), count: -pointAt) + text
        } else if pointAt >= text.count {
            text += [UInt8](repeating: UInt8(ascii: "0"), count: pointAt - text.count)
        } else {
            text.insert(UInt8(ascii: "."), at: pointAt)
        }
        if text.contains(UInt8(ascii: ".")) {
            while text.last == UInt8(ascii: "0") { text.removeLast() }
            if text.last == UInt8(ascii: ".") { text.removeLast() }
        }
        bytes += text
    }

    /// 10^power, exactly for the powers in the table and by `pow` beyond.
    private static func scale(_ power: Int) -> Double {
        if power >= 0 { return power < powers.count ? powers[power] : pow(10, Double(power)) }
        return 1 / (-power < powers.count ? powers[-power] : pow(10, Double(-power)))
    }

    static func append(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes += Array(String(value).utf8)
    }

    /// `name` for an XML attribute: the five characters XML reserves become entities, control characters go, and a blank name is "Part".
    static func attribute(_ name: String) -> String {
        var result = ""
        for character in name.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                if character.value >= 0x20 && character.value != 0x7F { result.unicodeScalars.append(character) }
            }
        }
        return result.trimmingCharacters(in: .whitespaces).isEmpty ? "Part" : result
    }
}
