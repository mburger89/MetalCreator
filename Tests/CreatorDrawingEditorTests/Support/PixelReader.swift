#if canImport(MetalUITestingSnapshot)
import CoreGraphics
import MetalUITesting
import MetalUITestingSnapshot

/// A window's last frame as RGBA bytes (the snapshot: device pixels, sRGB, premultiplied).
struct PixelImage {
    let width: Int
    let height: Int
    let scale: Double
    let bytes: [UInt8]

    @MainActor
    init(window: TestWindow, scale: Double = 2) throws {
        let image = try window.snapshot()
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.width = width
        self.height = height
        self.scale = scale
        bytes = data
    }

    /// The pixel at a device pixel (x, y from the top left).
    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return (-1, -1, -1) }
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// The pixel under a point of the window.
    func rgb(atPoint x: Double, _ y: Double) -> (r: Int, g: Int, b: Int) {
        rgb(Int(x * scale), Int(y * scale))
    }

    func luminance(_ x: Int, _ y: Int) -> Int {
        let p = rgb(x, y)
        return (p.r + p.g + p.b) / 3
    }

    /// How many pixels, in points, of the column at `x` points from `y0` to `y1` points are darker than `threshold`.
    func darkLength(column x: Double, from y0: Double, to y1: Double, below threshold: Int = 128) -> Double {
        var count = 0
        for y in Int(y0 * scale)..<Int(y1 * scale) where luminance(Int(x * scale), y) < threshold { count += 1 }
        return Double(count) / scale
    }

    /// The number of separate dark runs along the row at `y` points from `x0` to `x1` points.
    func darkRuns(row y: Double, from x0: Double, to x1: Double, below threshold: Int = 128) -> Int {
        var runs = 0
        var inside = false
        for x in Int(x0 * scale)..<Int(x1 * scale) {
            let dark = luminance(x, Int(y * scale)) < threshold
            if dark && !inside { runs += 1 }
            inside = dark
        }
        return runs
    }
}
#endif
