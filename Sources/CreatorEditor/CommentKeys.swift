import MetalUI

/// Keys that end the editing of a comment, shared by the inspector's note box and the canvas's editor.
enum CommentKeys {
    /// ⌘↩ (⌃↩ off macOS) commits a note's text (canvas comments spec 2026-10-09 §7). MetalUI C9 (KF-Z) leaves ⌘↩ out of a
    /// `TextEditor`'s editing keys, so an `onKeyPress` for Return that answers `.handled` for it runs before the editor
    /// and plain Return still breaks the line.
    static func commitsNote(_ modifiers: Modifiers) -> Bool { modifiers.contains(commitModifier) }

    /// The platform's shortcut modifier, as MetalUI documents it for `TextEditor` (it exposes no constant for it).
    #if os(macOS)
    static let commitModifier: Modifiers = .command
    #else
    static let commitModifier: Modifiers = .control
    #endif
}
