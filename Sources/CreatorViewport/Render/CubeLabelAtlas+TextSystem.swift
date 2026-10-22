import MetalUI

extension CubeLabelAtlas {
    /// The six names, rasterized through `textSystem` (MetalUI's `TextSystem`: CoreText's on macOS, the portable FreeType one over the
    /// installed fonts elsewhere), or `nil` if it draws no ink at all (no usable font).
    ///
    /// All six share one size, the largest at which the widest name fits its rect inside the margin. Each name's ink is centred across
    /// its rect and its capitals centred up and down, so the six share a baseline. The font is the system face at weight 0.3, the
    /// semibold of CoreText's weight scale.
    @MainActor
    static func rasterize(using textSystem: any TextSystem) -> CubeLabelAtlas? {
        let names = ViewCubeRegion.faces.map { $0.label ?? "" }
        let size = fittingFontSize(for: names, using: textSystem)
        guard size.isFinite, size > 0 else { return nil }
        let font = textSystem.resolveFont(semibold(size: size))
        let capHeight = capitalHeight(in: font, using: textSystem)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for (face, name) in zip(ViewCubeRegion.faces, names) {
            guard let rect = rect(for: face), let line = InkLine(name, font: font, using: textSystem) else { continue }
            let rectLeft = Int((Double(rect.u0) * Double(width)).rounded())
            let rectTop = Int((Double(rect.v0) * Double(height)).rounded())
            let rectWidth = Int((Double(rect.u1 - rect.u0) * Double(width)).rounded())
            let rectHeight = Int((Double(rect.v1 - rect.v0) * Double(height)).rounded())
            let originX = rectLeft + (rectWidth - line.inkWidth) / 2 - line.minX
            let baseline = rectTop + (rectHeight + capHeight) / 2
            line.draw(into: &pixels, originX: originX, baselineRow: baseline, width: width, height: height)
        }
        guard pixels.contains(where: { $0 > 0 }) else { return nil }
        return CubeLabelAtlas(width: width, height: height, pixels: pixels)
    }

    /// The largest size at which every name fits its rect inside the margin, so all six share one size.
    @MainActor
    static func fittingFontSize(for names: [String], using textSystem: any TextSystem) -> Double {
        let reference = 100.0
        let font = textSystem.resolveFont(semibold(size: reference))
        let widest = names.compactMap { InkLine($0, font: font, using: textSystem)?.inkWidth }.max() ?? 0
        let capHeight = capitalHeight(in: font, using: textSystem)
        guard widest > 0, capHeight > 0 else { return 0 }
        let roomWidth = Double(cellWidth - 2 * gutter - 2 * margin)
        let roomHeight = Double(cellHeight - 2 * gutter - 2 * margin)
        return reference * min(roomWidth / Double(widest), roomHeight / Double(capHeight))
    }

    /// The system face, semibold (0.3 on CoreText's weight scale), at `size` points.
    static func semibold(size: Double) -> FontDescriptor {
        FontDescriptor(family: nil, size: size, weight: 0.3)
    }

    /// The rows of ink in a capital H of `font`: the height capitals stand at, which centres every name the same way.
    @MainActor
    static func capitalHeight(in font: FontKey, using textSystem: any TextSystem) -> Int {
        guard let line = InkLine("H", font: font, using: textSystem) else { return 0 }
        return line.inkHeight
    }
}

/// One line of text as glyph coverage images placed relative to the pen origin and the baseline.
private struct InkLine {
    struct Piece {
        var image: GlyphImage
        /// Columns from the pen origin to the image's left edge.
        var x: Int
        /// Rows from the baseline down to the image's top edge (negative above it).
        var y: Int
    }

    var pieces: [Piece] = []

    /// The line, or `nil` if none of its glyphs has ink.
    @MainActor
    init?(_ text: String, font: FontKey, using textSystem: any TextSystem) {
        let glyphs = textSystem.placeGlyphs(text, font: font, wrappingAt: nil, origin: (x: 0, y: 0), scaleFactor: 1)
        guard let baseline = glyphs.first?.baselineY else { return nil }
        for glyph in glyphs {
            let image = textSystem.rasterize(glyph.key)
            if image.isEmpty { continue }
            pieces.append(Piece(image: image, x: glyph.pixelX + image.left, y: glyph.baselineY - baseline - image.top))
        }
        if pieces.isEmpty { return nil }
    }

    /// The leftmost column holding any ink, from the pen origin.
    var minX: Int { pieces.map { $0.x + $0.image.firstInkColumn }.min() ?? 0 }
    var maxX: Int { pieces.map { $0.x + $0.image.lastInkColumn + 1 }.max() ?? 0 }
    var inkWidth: Int { maxX - minX }
    var inkHeight: Int {
        let top = pieces.map { $0.y + $0.image.firstInkRow }.min() ?? 0
        let bottom = pieces.map { $0.y + $0.image.lastInkRow + 1 }.max() ?? 0
        return bottom - top
    }

    /// Paints the coverage into a `width` × `height` bitmap whose first row is the top, with the pen origin at column `originX`
    /// and the baseline at row `baselineRow`. Overlapping coverage keeps the larger; what falls outside the bitmap is dropped.
    func draw(into pixels: inout [UInt8], originX: Int, baselineRow: Int, width: Int, height: Int) {
        for piece in pieces {
            for row in 0..<piece.image.height {
                let destinationRow = baselineRow + piece.y + row
                guard destinationRow >= 0, destinationRow < height else { continue }
                for column in 0..<piece.image.width {
                    let destinationColumn = originX + piece.x + column
                    guard destinationColumn >= 0, destinationColumn < width else { continue }
                    let coverage = piece.image.bytes[row * piece.image.width + column]
                    let index = destinationRow * width + destinationColumn
                    pixels[index] = max(pixels[index], coverage)
                }
            }
        }
    }
}

private extension GlyphImage {
    var firstInkColumn: Int { (0..<width).first { column in (0..<height).contains { bytes[$0 * width + column] > 0 } } ?? 0 }
    var lastInkColumn: Int { (0..<width).last { column in (0..<height).contains { bytes[$0 * width + column] > 0 } } ?? 0 }
    var firstInkRow: Int { (0..<height).first { row in (0..<width).contains { bytes[row * width + $0] > 0 } } ?? 0 }
    var lastInkRow: Int { (0..<height).last { row in (0..<width).contains { bytes[row * width + $0] > 0 } } ?? 0 }
}
