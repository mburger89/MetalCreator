import Foundation
import MetalUI

/// Chooses files for opening, saving and exporting. The app's window provides one (`WindowFilePicker`); tests
/// provide their own answers. Both return `nil` when the person cancels.
@MainActor
public protocol FilePicker {
    func chooseFileToOpen(_ types: [ContentType]) async throws -> URL?
    func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL?
}
