import MetalUI

/// Keys that end the editing of a comment, shared by the inspector's note box and the canvas's editor.
enum CommentKeys {
    /// ⌘↩ (⌃↩ off macOS: the primary modifier) commits a note's text (canvas comments spec 2026-10-09 §7). MetalUI C9 (KF-Z) leaves ⌘↩ out of a
    /// `TextEditor`'s editing keys, so an `onKeyPress` for Return that answers `.handled` for it runs before the editor
    /// and plain Return still breaks the line.
    static func commitsNote(_ modifiers: Modifiers) -> Bool { modifiers.contains(commitModifier) }

    /// The platform's shortcut modifier: MetalUI's `Modifiers.primary` (⌘ on macOS, ⌃ elsewhere; MetalUI C12, `SG-B`).
    static let commitModifier: Modifiers = .primary
}
