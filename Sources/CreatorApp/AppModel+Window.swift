extension AppModel {
    /// Runs `action` with the window's file picker, from a button or menu command.
    public func withFilePicker(_ action: @escaping @MainActor (any FilePicker) async -> Void) {
        guard let filePicker else { return }
        Task { await action(filePicker) }
    }
}
