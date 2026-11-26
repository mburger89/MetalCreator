import CreatorDrawing
import MetalUI

/// The bitmaps of the sheet's pictures, made once per image and kept by the editor model (DR-5 R12): a grey picture becomes RGBA
/// the first time it is drawn, never on a later frame. Not observed. Equal by identity, so a layer that holds one compares it free.
@MainActor
final class SheetBitmaps: Equatable {
    private var made: [String: ImageBitmap] = [:]

    /// How many bitmaps are kept.
    var count: Int { made.count }

    func bitmap(for pixels: GreyPixels) -> ImageBitmap {
        let key = "\(pixels.key):\(pixels.width)x\(pixels.height)"
        if let kept = made[key] { return kept }
        var rgba = [UInt8](repeating: 255, count: pixels.bytes.count * 4)
        for (index, grey) in pixels.bytes.enumerated() {
            rgba[index * 4] = grey
            rgba[index * 4 + 1] = grey
            rgba[index * 4 + 2] = grey
        }
        let bitmap = ImageBitmap(width: pixels.width, height: pixels.height, rgba: rgba)
        made[key] = bitmap
        return bitmap
    }

    nonisolated static func == (left: SheetBitmaps, right: SheetBitmaps) -> Bool { left === right }
}

/// The pictures of a sheet (the title block's logo), drawn under the ink in paper space: each fills its rectangle, sheet
/// millimetres times `zoom`, y down from the paper's top (DR-5 R12). `.equatable()`, `==` over every stored property.
struct SheetImageLayer: Component, Equatable {
    let images: [SheetImage]
    let bitmaps: SheetBitmaps
    let zoom: Double
    let paperHeight: Double

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(images.indices, id: \.self) { index in
                let image = images[index]
                Image(decorative: bitmaps.bitmap(for: image.pixels), scale: 1)
                    .resizable()
                    .frame(width: (image.rect.width * zoom).px, height: (image.rect.height * zoom).px)
                    .offset(x: (image.rect.min.x * zoom).px, y: ((paperHeight - image.rect.max.y) * zoom).px)
            }
        }
    }
}
