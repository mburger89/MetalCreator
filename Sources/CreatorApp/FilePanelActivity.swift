import Foundation
import MetalUI

/// Counts the document's file panels (open, save, import, choose or relink a picture, export destination) that are up, so the
/// MCP server can refuse edits while one is (MCP-1b R5). The theme editor's panels aren't counted: they cannot change the document.
@MainActor @Observable
public final class FilePanelActivity {
    public private(set) var open = 0
    public var isOpen: Bool { open > 0 }

    func begin() { open += 1 }
    func end() { open -= 1 }
}

/// A picker that tells `activity` while one of its panels is up; a thrown or cancelled panel releases it.
struct ActivityFilePicker: FilePicker {
    let base: any FilePicker
    let activity: FilePanelActivity

    func chooseFileToOpen(_ types: [ContentType]) async throws -> URL? {
        activity.begin()
        defer { activity.end() }
        return try await base.chooseFileToOpen(types)
    }

    func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL? {
        activity.begin()
        defer { activity.end() }
        return try await base.chooseDestination(types, defaultName: defaultName)
    }
}

extension AppModel {
    /// `picker`, counted in `filePanels`. Every entry point that takes a picker starts with this.
    func tracked(_ picker: any FilePicker) -> any FilePicker {
        if picker is ActivityFilePicker { return picker }
        return ActivityFilePicker(base: picker, activity: filePanels)
    }
}
