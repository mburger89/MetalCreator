import CoreGraphics
import CoreText
import Foundation

/// The view cube's six face names, rasterized once into a single-channel coverage bitmap (spec §6.3: "Faces are
/// labelled TOP, BOTTOM, FRONT, BACK, LEFT and RIGHT"). The renderer uploads it to an `r8Unorm` texture with
/// mipmaps, and the cube's fragment shader paints it on the faces, so the names tilt and turn with the cube.
/// Pure CoreText and CoreGraphics, so it's tested without a GPU.
///
/// The names are stacked one per row in `ViewCubeRegion.faces` order. Each row is a cell inset by a gutter, so
/// mip levels don't bleed one name into the next, and each name is centred in its rect in the system font,
/// semibold, all at one size. Row 0 of `pixels` is the top of the atlas (v = 0), and the text is drawn upright.
struct CubeLabelAtlas: Sendable {
    /// Atlas pixels per cell. A face is about 53 points (107 Retina pixels) across, and the text box spans 80% of
    /// it, so 256 pixels is more than twice what a Retina screen shows. Mipmaps take it down from there.
    static let cellWidth = 256
    static let cellHeight = 96
    /// Empty pixels around each rect, so linear filtering and the smaller mip levels stay inside a name.
    static let gutter = 4
    /// Empty pixels between a rect's edge and its text.
    static let margin = 10
    static let width = cellWidth
    static let height = cellHeight * 6

    let width: Int
    let height: Int
    /// Coverage, 0 (no ink) to 255, row by row from the top.
    let pixels: [UInt8]

    /// The rect a face's name fills, or `nil` for an edge or corner (they have no name).
    static func rect(for face: ViewCubeRegion) -> CubeLabelRect? {
        guard face.label != nil, let row = ViewCubeRegion.faces.firstIndex(of: face) else { return nil }
        let top = row * cellHeight + gutter
        return CubeLabelRect(u0: Float(gutter) / Float(width), v0: Float(top) / Float(height),
                             u1: Float(cellWidth - gutter) / Float(width), v1: Float(top + cellHeight - 2 * gutter) / Float(height))
    }

    /// A rect's height over its width: the text box on a face has the same shape, so the text isn't stretched.
    static var rectAspect: Double { Double(cellHeight - 2 * gutter) / Double(cellWidth - 2 * gutter) }

    /// An atlas with no ink, for when rasterizing fails: the cube still draws, unlabelled.
    static var blank: CubeLabelAtlas {
        CubeLabelAtlas(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height))
    }

    func pixel(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    /// The six names, or `nil` if CoreGraphics can't make the bitmap.
    static func rasterize() -> CubeLabelAtlas? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        let names = ViewCubeRegion.faces.map { $0.label ?? "" }
        let size = fittingFontSize(for: names)
        let font = semiboldSystemFont(size: size)
        for (face, name) in zip(ViewCubeRegion.faces, names) {
            guard let rect = rect(for: face) else { continue }
            let line = line(name, font: font)
            let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // CoreGraphics' y runs up from the bitmap's last row, so a rect `v0` from the top sits this far up.
            let rectLeft = Double(rect.u0) * Double(width)
            let rectWidth = Double(rect.u1 - rect.u0) * Double(width)
            let rectBottom = Double(height) - Double(rect.v1) * Double(height)
            let rectHeight = Double(rect.v1 - rect.v0) * Double(height)
            let capHeight = Double(CTFontGetCapHeight(font))
            context.textPosition = CGPoint(x: rectLeft + (rectWidth - glyphs.width) / 2 - glyphs.minX,
                                           y: rectBottom + (rectHeight - capHeight) / 2)
            CTLineDraw(line, context)
        }
        guard let data = context.data else { return nil }
        let pixels = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
        return CubeLabelAtlas(width: width, height: height, pixels: pixels)
    }

    /// The largest size at which every name fits its rect inside the margin, so all six share one size.
    static func fittingFontSize(for names: [String]) -> Double {
        let reference = 100.0
        let font = semiboldSystemFont(size: reference)
        let widest = names.map { Double(CTLineGetBoundsWithOptions(line($0, font: font), .useGlyphPathBounds).width) }.max() ?? 1
        let roomWidth = Double(cellWidth - 2 * gutter - 2 * margin)
        let roomHeight = Double(cellHeight - 2 * gutter - 2 * margin)
        let capHeight = max(Double(CTFontGetCapHeight(font)), 1)
        return reference * min(roomWidth / max(widest, 1), roomHeight / capHeight)
    }

    /// The system font (SF), semibold.
    static func semiboldSystemFont(size: Double) -> CTFont {
        let system = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontTraitsAttribute: [kCTFontWeightTrait: 0.3]] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system), traits)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func line(_ text: String, font: CTFont) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
