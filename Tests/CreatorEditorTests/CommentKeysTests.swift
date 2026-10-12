import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘↩ commits a note's text, in the inspector's box and on the canvas (canvas comments spec 2026-10-09 §7); plain
/// Return, ⇧↩ and ⌥↩ keep breaking the line (MetalUI C9's KF-Z leaves them to the editor).
struct CommentKeysTests {
    @Test func theCommitModifierIsMetalUIsPrimaryModifier() {
        #expect(CommentKeys.commitModifier == .primary)
    }

    @Test func commandReturnCommitsANote() {
        #expect(CommentKeys.commitsNote(.primary))
        #expect(CommentKeys.commitsNote([.primary, .shift]))
    }

    @Test func otherReturnsBreakTheLine() {
        let others: [Modifiers] = [[], .shift, .option, .control, .command]
        for modifiers in others where modifiers != .primary {
            #expect(!CommentKeys.commitsNote(modifiers))
        }
    }
}
