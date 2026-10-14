import MetalUI

extension AppModel {
    /// Runs `action` with the window's file picker, from a button or menu command.
    public func withFilePicker(_ action: @escaping @MainActor (any FilePicker) async -> Void) {
        guard let filePicker else { return }
        Task { await action(filePicker) }
    }

    /// Routes the window's close request through the model (gap M6-b, MetalUI S1): the system button, ⌘W, ⌘Q and the Close
    /// button MetalUI draws on Linux and Windows all end in `onCloseRequest`, so unsaved changes ask first on every
    /// platform. A colour dragged just now is saved before the window can go (`flushTheme`).
    public func installCloseHandling(on window: Window, flushTheme: @escaping @MainActor () -> Void) {
        window.onCloseRequest = { [weak self] in
            flushTheme()
            return self?.closeRequested() ?? .now
        }
        replyToCloseRequest = { [weak window] in window?.replyToCloseRequest($0) }
    }
}
