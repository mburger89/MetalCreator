import CreatorDrawingEditor

/// The app's drawing templates (DR-5 R10): the person's own, in `~/Library/Application Support/MetalCreator/Drawing Templates`
/// (`$XDG_DATA_HOME` or `%APPDATA%` elsewhere). Only the app makes this store; tests make theirs with no folder.
public enum AppDrawingTemplates {
    @MainActor
    public static func store() -> DrawingTemplateStore {
        DrawingTemplateStore(folder: .applicationSupport)
    }
}
