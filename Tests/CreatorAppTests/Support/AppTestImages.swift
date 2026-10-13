// Test fixture file: small PNGs for the tests that choose, link and embed pictures through the app.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AppTestImages {
    /// A `width` × `height` PNG of one grey level (0…255).
    static func png(_ width: Int = 4, _ height: Int = 4, level: Double = 128, type: UTType = .png) -> Data {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let image = { () -> CGImage? in
                  context.setFillColor(gray: level / 255, alpha: 1)
                  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                  return context.makeImage()
              }() else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
