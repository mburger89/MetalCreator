// Test fixture file: what a window's frames did with MetalUI's content memo, and what they drew.
import CreatorStyle
import MetalUI
import MetalUITesting
@testable import CreatorApp

extension AppWindow {
    /// The work of every frame presented since the last ``resetWork()``, added up. `contentEvaluations`, `contentSkips`
    /// and `contentRefusals` count the `.equatable()` components of the canvas (C14 slice 1) and nothing else.
    var work: FrameWork {
        window.frameWork.reduce(FrameWork(), +)
    }

    func resetWork() {
        window.resetFrameWork()
    }

    /// One more frame with nothing changed, and its work.
    func steadyWork() -> FrameWork {
        resetWork()
        redraw()
        return work
    }

    /// What the last frame drew on the canvas, as numbers: every rect's bounds, fill and border, every glyph's position and
    /// colour, for what lies from the canvas's top edge down (the viewport above it and its cube are drawn from the
    /// viewport's own theme, which a live theme switch reaches by another path). Sorted, because two windows on the same graph
    /// may build its nodes in different orders (the graph's nodes are a dictionary); two equal summaries are the same picture.
    var picture: [[Float]] {
        let top = Float(canvasFrame.origin.y)
        let scene = window.scene
        let rects = scene.rects.filter { $0.bounds.origin.y >= top }.map { rect in
            let bounds = [rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width, rect.bounds.size.height]
            let fill = [rect.background.h, rect.background.s, rect.background.l, rect.background.a]
            let border = [rect.borderColor.h, rect.borderColor.s, rect.borderColor.l, rect.borderColor.a, rect.borderWidths.top]
            return bounds + fill + border
        }
        let glyphs = scene.glyphs.filter { $0.bounds.origin.y >= top }.map { glyph in
            [glyph.bounds.origin.x, glyph.bounds.origin.y, glyph.color.h, glyph.color.s, glyph.color.l, glyph.color.a]
        }
        return (rects + glyphs).sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// Makes every canvas view evaluate its content afresh by showing another theme and then the one it had, and
    /// returns the picture of the last frame: what the window should look like if no skipped view were stale. The
    /// themes' palettes differ in every `Palette`-carrying view, so each of those re-evaluates twice.
    func pictureAfterRebuildingEverything() -> [[Float]] {
        let theme = model.themes.current.id
        model.themes.select(theme == "alucard" ? "dracula" : "alucard")
        redraw()
        model.themes.select(theme)
        redraw()
        return picture
    }
}
