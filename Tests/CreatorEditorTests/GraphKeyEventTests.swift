import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorEditor

/// `GraphPanelInput.keyPressed(_:)` builds its `KeyEvent` with `keyEvent(key:characters:modifiers:isRepeat:)`. A
/// `KeyPress` can be made only by MetalUI, so the conversion is pinned here on its own parts: a wrong mapping would break
/// every graph key and no `handleKey` test would notice.
@MainActor
struct GraphKeyEventTests {
    func command(_ key: KeyEquivalent, _ characters: String? = nil, _ modifiers: EventModifiers = [],
                 isRepeat: Bool = false) -> GraphKeyCommand? {
        let event = GraphPanelInput.keyEvent(key: key, characters: characters ?? String(key.character),
                                             modifiers: modifiers, isRepeat: isRepeat)
        return GraphKeyBindings.command(for: event, paletteOpen: false)
    }

    @Test func theEventCarriesTheKeysPartsUnchanged() {
        let event = GraphPanelInput.keyEvent(key: KeyEquivalent("n"), characters: "N", modifiers: [.command, .shift], isRepeat: true)
        #expect(event.charactersIgnoringModifiers == "n" && event.characters == "N")
        #expect(event.modifiers == [.command, .shift] && event.isRepeat)
        let plain = GraphPanelInput.keyEvent(key: .space, characters: " ", modifiers: [], isRepeat: false)
        #expect(plain.charactersIgnoringModifiers == " " && plain.modifiers.isEmpty && !plain.isRepeat)
    }

    @Test func theArrowsAreNudgesTheWayTheyPoint() {
        #expect(command(.upArrow) == .nudge(Vector2(0, -1), isRepeat: false))
        #expect(command(.downArrow) == .nudge(Vector2(0, 1), isRepeat: false))
        #expect(command(.leftArrow) == .nudge(Vector2(-1, 0), isRepeat: false))
        #expect(command(.rightArrow, nil, .shift) == .nudge(Vector2(10, 0), isRepeat: false))
    }

    /// A held arrow's auto-repeat joins the undo step its first press began, so `isRepeat` must reach the command.
    @Test func theRepeatFlagReachesTheNudge() {
        #expect(command(.rightArrow, nil, [], isRepeat: true) == .nudge(Vector2(1, 0), isRepeat: true))
        #expect(command(.rightArrow, nil, [], isRepeat: false) == .nudge(Vector2(1, 0), isRepeat: false))
    }

    @Test func deleteTabReturnEscapeAndSpaceAreTheirCommands() {
        #expect(command(.delete) == .deleteSelection)
        #expect(command(.deleteForward) == .deleteSelection)
        #expect(command(.tab) == .tab)
        #expect(command(.space) == .openPalette)
        #expect(command(.escape) == .cancel)
        #expect(command(.return) == nil, "Return is no graph key outside the palette")
        #expect(command(KeyEquivalent("q")) == nil)
    }

    @Test func theCommandChordsKeepTheirModifiers() {
        #expect(command(KeyEquivalent("a"), nil, .command) == .selectAll)
        #expect(command(KeyEquivalent("N"), "N", [.command, .shift]) == .addNote, "AppKit reports a shifted letter upper-case")
        #expect(command(KeyEquivalent("n"), "N", [.command, .shift]) == .addNote)
        #expect(command(KeyEquivalent("c"), nil, [.command, .shift]) == .addFrame)
        #expect(command(.downArrow, nil, .command) == .enterGroup)
        #expect(command(.upArrow, nil, .command) == .exitGroup)
        #expect(command(KeyEquivalent("a"), nil, .option) == nil)
    }
}
