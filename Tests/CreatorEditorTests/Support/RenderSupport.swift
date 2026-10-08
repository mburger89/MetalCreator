// Test fixture file: the headless frame helper shared by the render tests.
import MetalUI
import MetalUIText

/// A headless frame of `panel` (MetalUI's `renderFrame`, its `ImageRenderer` analogue), wrapped
/// in a `ZStack` because a frame's root must be an `Element` and a `Component` is a group.
@MainActor
func renderHeadless<Panel: ElementGroup>(_ panel: () -> Panel) -> Scene {
    let content = panel()
    return renderFrame({ ZStack { content } }, size: Size(width: Pixels(900), height: Pixels(600)), scaleFactor: 2,
                       textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
}
