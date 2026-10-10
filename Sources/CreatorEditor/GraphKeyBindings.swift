import CreatorGeometry
import MetalUI

/// The graph panel's keys (spec §6.2). Pure, so the mapping is tested without a window.
public enum GraphKeyBindings {
    /// How far one arrow press nudges the selection, in canvas points (spec 2026-10-09 §3).
    public static let nudgeStep = 1.0
    /// How far one ⇧-arrow press nudges it.
    public static let largeNudgeStep = 10.0

    /// The command for `key`, or `nil` to let it through. While the palette is open only its
    /// navigation keys are taken, so typing reaches its search field.
    public static func command(for key: KeyEvent, paletteOpen: Bool) -> GraphKeyCommand? {
        let modifiers = key.modifiers.subtracting(.shift)
        let character = key.charactersIgnoringModifiers
        let shifted = key.modifiers.contains(.shift)
        if paletteOpen {
            return modifiers.isEmpty ? paletteCommand(for: character) : nil
        }
        if modifiers.isEmpty, let delta = nudge(for: character, shifted: shifted) {
            return .nudge(delta, isRepeat: key.isRepeat)
        }
        if modifiers == .command {
            return commandChord(for: character.lowercased(), shifted: shifted)
        }
        return modifiers.isEmpty ? plainCommand(for: character, shifted: shifted) : nil
    }

    /// The palette's navigation keys (no modifiers but Shift).
    static func paletteCommand(for character: String) -> GraphKeyCommand? {
        switch character {
        case "\u{1b}": .cancel
        case "\u{f700}": .paletteUp
        case "\u{f701}": .paletteDown
        case "\r": .paletteConfirm
        default: nil
        }
    }

    /// An arrow key's nudge in display canvas points, the way it points on screen; `nil` for any other key.
    static func nudge(for character: String, shifted: Bool) -> Vector2? {
        let step = shifted ? largeNudgeStep : nudgeStep
        switch character {
        case "\u{f700}": return Vector2(0, -step)
        case "\u{f701}": return Vector2(0, step)
        case "\u{f702}": return Vector2(-step, 0)
        case "\u{f703}": return Vector2(step, 0)
        default: return nil
        }
    }

    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo and ⌘G into ungroup.
    static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "c": .copy
        case "v": .paste
        case "d": .duplicate
        case "a": shifted ? nil : .selectAll
        case "g": shifted ? .ungroup : .group
        case "z": shifted ? .redo : .undo
        default: nil
        }
    }

    /// Keys with no modifier but Shift. ⇧⇥ isn't Tab's job (it's reverse focus traversal).
    static func plainCommand(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "\t": shifted ? nil : .tab
        case " ": .openPalette
        case "\u{7f}", "\u{f728}": .deleteSelection
        case "=", "+": .zoomIn
        case "-": .zoomOut
        case "f": shifted ? nil : .frameSelection
        case "\u{1b}": .cancel
        default: nil
        }
    }
}
