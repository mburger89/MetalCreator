import MetalUI

/// An sRGB colour written as `0xRRGGBB` plus an opacity, so palette tokens read like the spec's
/// table (spec §6.6) and tests can compare them exactly.
public struct HexColor: Hashable, Sendable {
    public var rgb: UInt32
    public var opacity: Double

    public init(_ rgb: UInt32, opacity: Double = 1) {
        self.rgb = rgb
        self.opacity = opacity
    }

    /// The same colour at another opacity.
    public func opacity(_ opacity: Double) -> HexColor { HexColor(rgb, opacity: opacity) }

    /// The MetalUI colour for drawing.
    public var color: Color {
        Color(red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255,
              blue: Double(rgb & 0xff) / 255,
              opacity: opacity)
    }
}
