import MetalUI
import MetalUITesting
import Testing
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// MetalUI C23's `@Environment(\.textMeasurer)` through a real window (MetalUI's `docs/testing.md`, "Measuring text"): a
/// component reads the measurer in its body, `TextMeasure` wraps it, and the box the models place equals the frame the
/// laid-out text gets, where the removed 7-points-a-character estimate was too narrow for wide letters and too wide for
/// narrow ones (gap S5-c).
@MainActor
struct TextMeasureWindowTests {
    /// Reads the measurer from its environment, as a component does, and lays out the two strings the tests compare with.
    struct Probe: Component {
        let box: MeasurerBox
        @Environment(\.textMeasurer) var measurer

        var content: some ElementGroup {
            box.measurer = measurer
            return VStack(spacing: Pixels(0)) {
                Text("WWWWWWWWWW").font(.caption).id("wide")
                Text("iiiiiiiiii").font(.caption).id("narrow")
            }
        }
    }

    /// What the removed stopgap gave a label box: 7 points a character and 6 at each side.
    func oldLabelEstimate(_ text: String) -> Double { Double(text.count) * 7 + 2 * 6 }

    /// What the removed stopgap gave a readout chip: 7 points a character and 8 at each side.
    func oldChipEstimate(_ text: String) -> Double { Double(text.count) * 7 + 2 * 8 }

    func open() throws -> (window: TestWindow, measure: TextMeasure) {
        let box = MeasurerBox()
        let window = try TestWindow(textSystem: { testTextSystem() }, content: { ZStack { Probe(box: box) } })
        guard let measurer = box.measurer else { throw MeasurerNotCaptured() }
        return (window, TextMeasure(measurer))
    }

    @Test func aMeasuredTextIsTheFrameALaidOutTextGets() throws {
        let (window, measure) = try open()
        for (id, text) in [("wide", "WWWWWWWWWW"), ("narrow", "iiiiiiiiii")] {
            let laid = try window.frame(ofID: id)
            #expect(abs(measure(text).width - Double(laid.size.width.value)) < 1, "\(text): the measure is the frame (rounded)")
            // The boxes' heights are fixed (user decision U1): a font change that made a line taller must fail here, not clip.
            #expect(measure(text).height <= HandleLabel.height, "\(text): a line fits the handle label's fixed box")
            #expect(measure(text).height <= PlacedLabel.height, "\(text): a line fits the dimension label's fixed box")
        }
    }

    @Test func aWideStringGetsAWiderLabelBoxThanTheOldEstimateGave() throws {
        let (_, measure) = try open()
        let wide = PlacedLabel.box(of: "WWWWWWWWWW", measuring: measure)
        #expect(wide.width > oldLabelEstimate("WWWWWWWWWW"), "ten capital Ws advance more than 7 points each")
        let narrow = PlacedLabel.box(of: "iiiiiiiiii", measuring: measure)
        #expect(narrow.width < oldLabelEstimate("iiiiiiiiii"), "ten narrow letters need less than 7 points each")
        #expect(wide.width > narrow.width)
    }

    @Test func theChipsAreSizedByTheSameMeasure() throws {
        let (_, measure) = try open()
        let wide = ReadoutChip.size(of: "WWWWWWWWWW", measuring: measure)
        #expect(wide.width > oldChipEstimate("WWWWWWWWWW"))
        #expect(wide.height == ReadoutChip.height)
        #expect(measure("WWWWWWWWWW").height <= ReadoutChip.height, "a line fits the chip's fixed box")
        let chip = try #require(ReadoutChip(text: "WWWWWWWWWW", pointer: ScreenPoint(600, 350),
                                            in: ViewportSize(width: 1200, height: 700), measuring: measure))
        #expect(chip.size == wide)
    }
}
