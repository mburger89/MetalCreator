import CreatorDrawing
import CreatorStyle
import MetalUI

/// One line of sheet lettering, each glyph its own `Text` (plan R13). The em size is the cap height over Helvetica's 718/1000,
/// times the zoom; a glyph's left edge is its Helvetica offset, and its baseline is the text's baseline because each glyph is
/// an `HStack(alignment: .firstTextBaseline)` of a zero-width clear child `B` tall (B is twice the em, above any ascent) and
/// the `Text`: the stack's top is then `B` above the baseline, whatever the screen face's ascent or leading. Nothing here
/// measures the screen font.
///
/// The view is placed in paper space (sheet millimetres times `zoom`, y down from the sheet's top): its top left is at the text's
/// origin x and at the baseline minus `lift`.
struct SheetTextView: Component, Equatable {
    let text: SheetText
    let zoom: Double
    let paperHeight: Double
    let color: HexColor

    /// The em size in points.
    static func em(height: Double, zoom: Double) -> Double { height / Double(HelveticaMetrics.capHeight) * 1000 * zoom }

    /// How far above its baseline the view's top is, in points.
    static func lift(height: Double, zoom: Double) -> Double { 2 * em(height: height, zoom: zoom) }

    var content: some ElementGroup {
        let em = Self.em(height: text.height, zoom: zoom)
        let lift = 2 * em
        let characters = Array(text.run.shown)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(characters.indices), id: \.self) { index in
                if characters[index] != " " {
                    HStack(alignment: .firstTextBaseline, spacing: Pixels(0)) {
                        Color.clear.frame(width: Pixels(0), height: lift.px)
                        Text(String(characters[index])).font(.system(size: em)).foregroundStyle(color.color)
                    }
                    .fixedSize()
                    .offset(x: (index < text.run.offsets.count ? text.run.offsets[index] * zoom : 0).px, y: Pixels(0))
                }
            }
        }
        .frame(width: (text.run.width * zoom).px, height: lift.px, alignment: .topLeading)
        .offset(x: (text.origin.x * zoom).px, y: ((paperHeight - text.origin.y) * zoom - lift).px)
    }
}
