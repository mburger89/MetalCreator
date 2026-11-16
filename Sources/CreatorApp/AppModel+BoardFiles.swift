import CreatorEditor

extension AppModel {
    /// "Choose File…" and "Relink…" on an Import KiCad Board node. The file panels arrive with the app's board import (KI-1 task 7),
    /// which replaces this body; until then the buttons do nothing.
    func handleBoardFile(_ request: InspectorRequest) {
        _ = request
    }
}
