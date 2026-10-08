import Foundation
import MetalUI

/// The window's open and save panels (MetalUI `FileDialogs`, an `NSOpenPanel` or `NSSavePanel` sheet).
public struct WindowFilePicker: FilePicker {
    let dialogs: FileDialogs

    public init(window: Window) {
        dialogs = window.fileDialogs
    }

    public func chooseFileToOpen(_ types: [ContentType]) async throws -> URL? {
        try await dialogs.openFiles(allowedContentTypes: types).first
    }

    public func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL? {
        try await dialogs.saveFile(contentTypes: types, defaultFilename: defaultName)
    }
}
