import MetalUI

extension AppModel {
    /// The window's `onCloseRequest` (close button, ⌘W, and ⌘Q, which asks each window in turn). With unsaved changes
    /// it shows the Save / Don't Save / Cancel alert and answers `.later`; the answer reaches the window through
    /// `replyToCloseRequest`. A typed but uncommitted inspector value counts as a change, so it is committed first. A
    /// request that arrives while the question is open answers `.later` again and puts the alert back if another alert
    /// replaced it.
    public func closeRequested() -> CloseRequestReply {
        guard closeRequest == .idle else {
            // A question is already open. If something else took the alert's place, ask again: MetalUI's close request
            // stays open until the model answers it, and without the buttons nothing could.
            if closeRequest == .asking, alert != .saveChanges(name: displayName) {
                alert = .saveChanges(name: displayName)
            }
            return .later
        }
        editor.commitPendingEntry()
        let reply = CloseDecision.reply(isEdited: isEdited)
        guard reply == .later else { return reply }
        closeRequest = .asking
        pendingDiscard = nil
        alert = .saveChanges(name: displayName)
        return reply
    }

    /// The alert's answer. Save runs the existing save flow (Save As… for an untitled document) and replies `true`
    /// only once it worked; a cancelled panel or a failed write replies `false`, and the failure's own alert shows.
    /// Only the first answer to a question counts.
    public func answerSaveChanges(_ answer: SaveChangesAnswer) async {
        guard closeRequest == .asking else { return }
        alert = nil
        var saved = false
        if answer == .save {
            closeRequest = .saving
            if let filePicker { saved = await saveDocument(using: filePicker) }
        }
        closeRequest = .idle
        replyToCloseRequest?(CloseDecision.shouldClose(after: answer, saved: saved))
    }
}
