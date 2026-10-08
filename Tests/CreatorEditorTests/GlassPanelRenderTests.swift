import MetalUI
import Testing
@testable import CreatorEditor

/// Proves the editor links MetalUI and that a headless frame of the glass chrome builds,
/// lays out and paints text. Colours are a human check (docs/verification/human-checks.md).
@MainActor
struct GlassPanelRenderTests {
    @Test func aGlassPanelDrawsItsContent() {
        let scene = renderHeadless { GlassPanel { Text("Graph") } }
        #expect(!scene.glyphs.isEmpty)
        #expect(!scene.isEmpty)
    }
}
