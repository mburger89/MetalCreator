import Observation

/// Keeps a window's title, edited dot and represented file in step with the open document (gap M6-a): `follow()` runs
/// for the life of the window and pushes the model's `windowChrome` whenever it changes.
@MainActor
public final class WindowChromeSync {
    let model: AppModel
    let chrome: any WindowChrome

    public init(model: AppModel, chrome: any WindowChrome) {
        self.model = model
        self.chrome = chrome
    }

    /// Pushes what the model shows now; a value that is already shown is not written again.
    public func apply() {
        let state = model.windowChrome
        if chrome.title != state.title { chrome.title = state.title }
        if chrome.isDocumentEdited != state.isEdited { chrome.isDocumentEdited = state.isEdited }
        if chrome.representedURL != state.fileURL { chrome.representedURL = state.fileURL }
    }

    /// Applies the model's state now, then again after every change of it, until the task is cancelled.
    public func follow() async {
        let states = Observations { [model] in model.windowChrome }
        for await _ in states {
            apply()
        }
    }
}
