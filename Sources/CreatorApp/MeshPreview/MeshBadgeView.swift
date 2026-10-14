import CreatorEditor
import CreatorStyle
import MetalUI

/// The badge on a mesh preview (implicit spec §5.1): "Preview 0.4 mm", and MetalUI's spinner while the passes are still refining it.
/// All behaviour is `MeshRefinementModel`'s; this only draws its `badge`.
struct MeshBadgeView: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        if let badge = model.meshRefinement.badge {
            GlassPanel(.chip) {
                HStack(spacing: Pixels(6)) {
                    if badge.isRefining { ProgressView().controlSize(.small) }
                    Text(badge.text)
                        .font(.caption)
                        .foregroundStyle(Palette(themes).primaryText.color)
                }
            }
        }
    }
}
