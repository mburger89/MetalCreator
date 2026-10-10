import Foundation

extension AppModel {
    /// A file the system asks the app to open (gap M6-d): a Finder double-click, a drop on the Dock icon, `open -a`,
    /// and the path on `swift run MetalCreatorApp file.mcgraph`. MetalUI delivers it through `App.onOpenURL`.
    ///
    /// A URL that isn't a file, the file that is already open, and any URL while the close question is up are
    /// ignored. A typed but uncommitted inspector value counts as a change (it is committed first, as when closing).
    /// With unsaved changes it asks the New and Open… question first (`alert`, then `discardChanges()`);
    /// otherwise the file replaces the document, or an alert says why it couldn't be opened. Several files in one
    /// drop arrive one at a time, so the last one stays open.
    public func openRequested(_ url: URL) {
        guard url.isFileURL, closeRequest == .idle else { return }
        if let current = fileURL, current.standardizedFileURL == url.standardizedFileURL { return }
        editor.commitPendingEntry()
        guard !isEdited else {
            pendingDiscard = .openURL(url)
            alert = .discardChanges
            return
        }
        openReportingFailure(url)
    }

    /// Opens `url`, or shows why it couldn't be.
    func openReportingFailure(_ url: URL) {
        do {
            try open(url)
        } catch {
            alert = .problem(error)
        }
    }
}
