import MetalUI

/// Puts the export sheet in the middle of the window while an export runs (`AppModel.exportRun`); nothing when none does. It fills
/// the window so the card can stand in the middle; only the card itself is drawn.
struct ExportSheetDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        if let run = model.exportRun {
            VStack(spacing: Pixels(0)) {
                Spacer()
                HStack(spacing: Pixels(0)) {
                    Spacer()
                    ExportSheetView(run: run)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
