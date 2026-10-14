import MetalUI
import Testing
@testable import CreatorViewport

/// How MetalUI's modifiers become the viewport model's. The platform's shortcut key (`.primary`: ⌘ on macOS, Ctrl on Linux and
/// Windows) is the model's `.command` on every platform; Control is a key of its own only where it is not that key. The graph
/// canvas maps the same way (`GraphPanelInputTests`). These run on every platform, so on Linux and Windows they pin the Ctrl mapping.
struct ViewportModifiersMappingTests {
    @Test func theShortcutKeyIsCommandAlone() {
        #expect(ViewportModifiers(.primary) == [.command])
        #expect(ViewportModifiers([.primary, .shift, .option]) == [.command, .shift, .option])
    }

    @Test func shiftAndOptionMapToThemselves() {
        #expect(ViewportModifiers([.shift]) == [.shift])
        #expect(ViewportModifiers([.option, .shift]) == [.option, .shift])
        #expect(ViewportModifiers([]) == [])
    }

    @Test func controlIsItsOwnKeyOnlyWhereItIsNotTheShortcutKey() {
        let expected: ViewportModifiers = Modifiers.primary == .control ? [.command] : [.control]
        #expect(ViewportModifiers(.control) == expected)
    }

    @Test func theHoverMaskIsTheShortcutKey() {
        #expect(ViewportModifiers.hoverMask == .primary)
    }
}
