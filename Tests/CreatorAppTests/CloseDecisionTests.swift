import MetalUI
import Testing
@testable import CreatorApp

/// The close and quit decision (spec §6.1, gap M6-b), as pure functions: what to answer MetalUI's close request, and
/// whether the window then closes.
struct CloseDecisionTests {
    @Test func aDocumentWithoutChangesClosesAtOnceAndOneWithChangesAsks() {
        #expect(CloseDecision.reply(isEdited: false) == .now)
        #expect(CloseDecision.reply(isEdited: true) == .later, "the window waits for the alert's answer")
    }

    @Test(arguments: [
        (SaveChangesAnswer.save, true, true),
        (.save, false, false),
        (.dontSave, true, true),
        (.dontSave, false, true),
        (.cancel, true, false),
        (.cancel, false, false),
    ])
    func theWindowClosesOnlyAfterASaveThatWorkedOrADontSave(_ answer: SaveChangesAnswer, _ saved: Bool, _ closes: Bool) {
        #expect(CloseDecision.shouldClose(after: answer, saved: saved) == closes)
    }
}
