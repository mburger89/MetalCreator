import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘↩ commits a note's text, in the inspector's box and on the canvas (canvas comments spec 2026-10-09 §7); plain
/// Return, ⇧↩ and ⌥↩ keep breaking the line (MetalUI C9's KF-Z leaves them to the editor).
struct CommentKeysTests {
    @Test func commandReturnCommitsANote() {
        #expect(CommentKeys.commitsNote(.command))
        #expect(CommentKeys.commitsNote([.command, .shift]))
    }

    @Test func otherReturnsBreakTheLine() {
        for modifiers: Modifiers in [[], .shift, .option, .control] {
            #expect(!CommentKeys.commitsNote(modifiers))
        }
    }
}
