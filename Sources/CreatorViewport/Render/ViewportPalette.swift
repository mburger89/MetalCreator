/// The viewport's Dracula colours (spec §6.6), as gamma-space RGBA for the GPU. MetalUI composites in gamma
/// space, so these are the hex values divided by 255.
public enum ViewportPalette {
    static func color(_ hex: UInt32, alpha: Float = 1) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, alpha)
    }

    static let backgroundTop = color(0x3A3D4E)
    static let backgroundBottom = color(0x191A21)
    static let shadeLight = color(0xC5C8DE)
    static let shadeDark = color(0x6F739A)
    static let edge = color(0xF8F8F2, alpha: 0.9)
    static let hover = color(0x8BE9FD)
    static let selection = color(0xFF79C6)
    static let solid = color(0xBD93F9)
    static let feature = color(0xFFB86C)
    static let gridMinor = color(0x44475A)
    static let gridMajor = color(0x6272A4)
    static let cubeFace = color(0x44475A)
    static let cubeRim = color(0x343746)
    /// The face names painted on the view cube: the viewport's label colour (`labelColor`, #f8f8f2).
    static let cubeLabel = color(0xF8F8F2)
    static let axisX = color(0xFF5555)
    static let axisY = color(0x50FA7B)
    static let axisZ = color(0x8BE9FD)
}
