import MetalUI
import Testing
@testable import CreatorApp

/// The unsaved-changes alert's buttons, which `AppRoot` builds from `SaveChangesAnswer.allCases`: a button's label and
/// role come from its answer, so these pin what the sheet offers (the sheet itself is human check AS-1).
struct SaveChangesAnswerTests {
    @Test func theAlertOffersSaveDontSaveAndCancelInThatOrder() {
        #expect(SaveChangesAnswer.allCases == [.save, .dontSave, .cancel])
        #expect(SaveChangesAnswer.allCases.map(\.title) == ["Save", "Don't Save", "Cancel"])
    }

    @Test func onlyCancelHasTheCancelRoleAndNothingIsDestructive() {
        #expect(SaveChangesAnswer.cancel.role == .cancel, "Escape presses it")
        #expect(SaveChangesAnswer.save.role == nil)
        #expect(SaveChangesAnswer.dontSave.role == nil, "a destructive button would take Return away from Save")
    }
}
