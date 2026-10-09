// Test fixture file: the headless frame helper for the sketch editor's view tests.
import MetalUI
import MetalUIText

/// A headless frame of `view` (MetalUI's `renderFrame`), wrapped in a `ZStack` because a frame's root must be an
/// `Element` and a `Component` is a group.
@MainActor
func renderHeadless<View: ElementGroup>(_ view: () -> View) -> Scene {
    let content = view()
    return renderFrame({ ZStack { content } }, size: Size(width: Pixels(1200), height: Pixels(700)), scaleFactor: 2,
                       textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
}
