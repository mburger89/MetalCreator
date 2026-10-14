import CreatorEditor
import CreatorStyle
import MetalUI

/// The export sheet (implicit spec §5.3): what is being exported, a bar for how far the meshing has got, and Cancel. All behaviour is
/// `ExportRun`'s; this draws it.
struct ExportSheetView: Component {
    let run: ExportRun
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The card's inner width in points.
    static let width = 320.0

    var content: some ElementGroup {
        GlassPanel(.exportSheet) {
            VStack(alignment: .leading, spacing: Pixels(10)) {
                Text(run.title)
                    .font(.headline)
                    .foregroundStyle(Palette(themes).primaryText.color)
                ProgressView(value: run.fraction)
                Text(run.isCancelling ? "Cancelling…" : "Meshing at full resolution")
                    .font(.caption)
                    .foregroundStyle(Palette(themes).secondaryText.color)
                HStack(spacing: Pixels(0)) {
                    Spacer()
                    Button("Cancel") { run.cancel() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .disabled(run.isCancelling)
                }
            }
            .frame(width: Self.width.px)
        }
    }
}
