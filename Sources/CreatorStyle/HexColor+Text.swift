import Foundation
import MetalUI

extension HexColor {
    /// Reads `#rrggbb`, or `#rrggbbaa` with an opacity byte: the form a `.mctheme` file writes. The `#` is optional,
    /// either case is read and surrounding spaces are ignored. Anything else is `nil`, never a guess.
    public init?(hex text: String) {
        var digits = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if digits.first == "#" { digits = digits.dropFirst() }
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(value)
        } else {
            self.init(value >> 8, opacity: Double(value & 0xff) / 255)
        }
    }

    /// `#rrggbb`, or `#rrggbbaa` when the colour isn't opaque: lowercase, as the spec's table writes colours.
    public var hex: String {
        let alpha = opacityByte
        if alpha == 255 { return "#" + Self.digits(rgb & 0xffffff, count: 6) }
        return "#" + Self.digits((rgb & 0xffffff) << 8 | UInt32(alpha), count: 8)
    }

    /// This colour with its opacity rounded to one of the 256 steps a `.mctheme` file holds, so a custom theme that
    /// is saved and read back equals itself.
    public var quantized: HexColor { HexColor(rgb & 0xffffff, opacity: Double(opacityByte) / 255) }

    /// The colour MetalUI resolved, each channel and the opacity rounded to its nearest byte.
    public init(_ resolved: Color.Resolved) {
        func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(byte(resolved.red) << 16 | byte(resolved.green) << 8 | byte(resolved.blue),
                  opacity: Double(byte(resolved.opacity)) / 255)
    }

    /// A MetalUI colour literal, such as `ColorPicker` writes (`Color(.sRGB, red:green:blue:opacity:)`), as a
    /// `HexColor`. A literal resolves the same in any environment, so it is resolved in the default one.
    public init(_ color: Color) {
        self.init(color.resolve(in: EnvironmentValues()))
    }

    /// The opacity as a byte, 0…255.
    var opacityByte: UInt8 { UInt8((min(max(opacity, 0), 1) * 255).rounded()) }

    /// `value` in lowercase hexadecimal, zero-padded to `count` digits.
    private static func digits(_ value: UInt32, count: Int) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, count - digits.count)) + digits
    }
}
