#if canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation

extension CubeLabelAtlas {
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
#endif
