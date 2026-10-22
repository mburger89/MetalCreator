// Test fixture file: reading the cube label atlas's ink back.
@testable import CreatorViewport

/// A box of atlas pixels, inclusive.
struct PixelBox {
    var minX: Int
    var maxX: Int
    var minY: Int
    var maxY: Int
}

extension CubeLabelAtlas {
    /// The pixel columns and rows `rect` covers.
    func pixelRanges(of rect: CubeLabelRect) -> (xs: Range<Int>, ys: Range<Int>) {
        let xs = Int((rect.u0 * Float(width)).rounded())..<Int((rect.u1 * Float(width)).rounded())
        let ys = Int((rect.v0 * Float(height)).rounded())..<Int((rect.v1 * Float(height)).rounded())
        return (xs, ys)
    }

    /// Pixels with any ink inside `rect`.
    func inkCount(in rect: CubeLabelRect) -> Int {
        let (xs, ys) = pixelRanges(of: rect)
        return ys.reduce(0) { count, y in count + xs.count { pixel(x: $0, y: y) > 0 } }
    }

    /// The smallest box holding every half-covered pixel inside `rect`, or `nil` if it has none.
    func inkBox(in rect: CubeLabelRect) -> PixelBox? {
        let (xs, ys) = pixelRanges(of: rect)
        var box: PixelBox?
        for y in ys {
            for x in xs where pixel(x: x, y: y) > 127 {
                if var found = box {
                    found.minX = min(found.minX, x)
                    found.maxX = max(found.maxX, x)
                    found.minY = min(found.minY, y)
                    found.maxY = max(found.maxY, y)
                    box = found
                } else {
                    box = PixelBox(minX: x, maxX: x, minY: y, maxY: y)
                }
            }
        }
        return box
    }
}
