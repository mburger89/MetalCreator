import CreatorDrawing
import CreatorStyle
import Foundation
import MetalUI

/// The zoom upright sheet lettering is laid out at (drawings zoom-text plan R1, R2). Text is built at `reference(for:)`, the power
/// of two nearest the current zoom, and drawn under a scale of `zoom / reference`, so a zoom step inside one octave band
/// re-evaluates no text and MetalUI re-rasterises it on its own ladder (TZ-A).
enum SheetTextZoom {
    /// `2^round(log2(zoom))`: the applied scale `zoom / reference` stays within [2^-0.5, 2^0.5].
    static func reference(for zoom: Double) -> Double {
        guard zoom > 0, zoom.isFinite else { return 1 }
        return pow(2, log2(zoom).rounded())
    }

    /// Whether the text's angle is a whole number of turns. Only upright text is scaled: MetalUI resamples text under a scale
    /// outside a rotation (divergence 106 (1)).
    static func isUpright(_ text: SheetText) -> Bool {
        text.angle.remainder(dividingBy: 2 * .pi) == 0
    }
}

/// The upright texts of one layer, laid out at a reference zoom. `==` never reads the true zoom, so a zoom step within a band
/// skips it.
struct SheetUprightTexts: Component, Equatable {
    let texts: [SheetText]
    let reference: Double
    let paperHeight: Double
    let ink: HexColor
    let warning: HexColor

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(texts.indices, id: \.self) { index in
                SheetTextView(
                    text: texts[index], zoom: reference, paperHeight: paperHeight,
                    color: texts[index].isNotice || texts[index].isLost ? warning : ink)
            }
        }
    }
}
