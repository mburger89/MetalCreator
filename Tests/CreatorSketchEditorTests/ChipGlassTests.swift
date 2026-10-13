import CreatorSketch
import CreatorStyle
import CreatorViewport
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// The sketch editor's chips are glass like the panels (gap C10-a, adopted with MetalUI C21): a blurring material over the
/// viewport under the theme's tint, in the chip's own box. The look is human check C21-1.
@MainActor
struct ChipGlassTests {
    func readoutScene(_ store: ThemeStore? = nil) throws -> (scene: Scene, chip: ReadoutChip) {
        let chip = try #require(ReadoutChip(text: "12.5 mm", pointer: ScreenPoint(600, 350), in: ViewportSize(width: 1200, height: 700),
                measuring: .fake))
        let scene = renderHeadless {
            ZStack(alignment: .topLeading) { ReadoutChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(store)
        }
        return (scene, chip)
    }

    func inferenceScene() throws -> (scene: Scene, chip: InferenceChip) {
        let chip = try #require(InferenceChip(kinds: [.coincident, .tangent], pointer: ScreenPoint(300, 300),
                                              in: ViewportSize(width: 1200, height: 700), measuring: .fake))
        let scene = renderHeadless {
            ZStack(alignment: .topLeading) { InferenceChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        return (scene, chip)
    }

    @Test func theReadoutChipBlursWhatIsBeneathItInItsOwnBox() throws {
        let (scene, chip) = try readoutScene()
        let backdrop = try #require(scene.backdrops.first)
        #expect(scene.backdrops.count == 1)
        #expect(Double(backdrop.bounds.origin.x) == chip.origin.x * 2 && Double(backdrop.bounds.origin.y) == chip.origin.y * 2)
        #expect(Double(backdrop.bounds.size.width) == chip.size.width * 2 && Double(backdrop.bounds.size.height) == chip.size.height * 2)
        #expect(backdrop.cornerRadii.topLeft == 12, "6 pt at 2x")
    }

    @Test func theInferenceChipBlursWhatIsBeneathItInItsOwnBox() throws {
        let (scene, chip) = try inferenceScene()
        let backdrop = try #require(scene.backdrops.first)
        #expect(scene.backdrops.count == 1)
        #expect(Double(backdrop.bounds.origin.x) == chip.origin.x * 2 && Double(backdrop.bounds.origin.y) == chip.origin.y * 2)
        #expect(Double(backdrop.bounds.size.width) == chip.size.width * 2)
    }

    @Test func theChipsTintIsTheThemesGlassAtTheChipSurfacesOpacity() throws {
        let store = ThemeStore()
        store.select("alucard")
        for themes in [nil, store] {
            let want = GlassStyle(themes: themes, surface: .chip).tint
            let scene = try readoutScene(themes).scene
            let tint = try #require(scene.rects.first { $0.background.a > 0 }).background
            let got = Hsla(h: tint.h, s: tint.s, l: tint.l, a: tint.a).toRgba()
            #expect(abs(got.a - Float(want.opacity)) < 0.01 && abs(got.r - want.rgba.x) < 0.01, "\(themes == nil ? "Dracula" : "Alucard")")
        }
    }
}
