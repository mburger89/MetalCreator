extension AppModel {
    /// What the window's title, edited dot and represented file should show now. Reading it inside `Observations`
    /// follows the document, so `WindowChromeSync` pushes a change as it happens.
    public var windowChrome: WindowChromeState {
        WindowChromeState(title: displayName, isEdited: isEdited, fileURL: fileURL)
    }
}
