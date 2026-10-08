import MetalUI

/// An sRGB colour written as `0xRRGGBB` plus an opacity, so theme colours read like the spec's table
/// (spec §6.6) and tests can compare them exactly. The editor draws `color`; the viewport's GPU passes
/// take `rgba`.
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

    /// Gamma-space RGBA for the GPU: each channel's byte divided by 255. MetalUI composites in gamma
    /// space, so the viewport's shaders take these values as they are.
    public var rgba: SIMD4<Float> {
        SIMD4(Float((rgb >> 16) & 0xff) / 255, Float((rgb >> 8) & 0xff) / 255, Float(rgb & 0xff) / 255, Float(opacity))
    }
}
