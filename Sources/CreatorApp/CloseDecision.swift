import MetalUI

/// What closing the window, or quitting, does about unsaved changes (spec §6.1, gap M6-b). Pure, so every answer is
/// tested without a window. ⌘Q asks through the same path: MetalUI asks each window's `onCloseRequest` in turn when
/// the app sets no `onTerminateRequest`, and this app has one window.
public enum CloseDecision {
    /// The reply to MetalUI's close request: close now when nothing is unsaved, otherwise `.later` (the alert asks).
    public static func reply(isEdited: Bool) -> CloseRequestReply {
        isEdited ? .later : .now
    }

    /// Whether the window closes once the person has answered. Save closes only if the save worked: a cancelled
    /// Save As… panel or a failed write keeps the window, so the changes are never lost by a failure.
    public static func shouldClose(after answer: SaveChangesAnswer, saved: Bool) -> Bool {
        switch answer {
        case .save: saved
        case .dontSave: true
        case .cancel: false
        }
    }
}
