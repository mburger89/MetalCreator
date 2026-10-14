// Test fixture file: the two measures the tests place labels and chips with.
import CreatorViewport
import MetalUI

/// Captures the measurer a component reads from its environment.
@MainActor
final class MeasurerBox {
    var measurer: TextMeasurer?
}

private struct MeasurerProbe: Component {
    let box: MeasurerBox
    @Environment(\.textMeasurer) var measurer

    var content: some ElementGroup {
        box.measurer = measurer
        return Spacer()
    }
}

extension TextMeasure {
    /// A deterministic measure for model tests: 6 points a character and 12 points tall, which differs from the removed
    /// 7-points-a-character estimate, so a test that passes proves the measure was used.
    static var fake: TextMeasure { TextMeasure { text in ViewportSize(width: Double(text.count) * 6, height: 12) } }

    /// MetalUI's real measure, as `MetalUI.TextMeasurer` gives it in a frame over CoreText (the text system the window
    /// draws with). For tests that compare a model's boxes with the text a rendered frame draws.
    @MainActor
    static func real() throws -> TextMeasure {
        let box = MeasurerBox()
        _ = renderFrame({ ZStack { MeasurerProbe(box: box) } }, size: Size(width: Pixels(100), height: Pixels(100)),
                        scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 256, height: 256))
        guard let measurer = box.measurer else { throw MeasurerNotCaptured() }
        return TextMeasure(measurer)
    }
}

struct MeasurerNotCaptured: Error {}
