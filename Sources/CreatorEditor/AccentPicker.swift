import CreatorGraph
import MetalUI

/// The accent roles as a row of swatches in the current theme's colours; the chosen one is ringed.
struct AccentPicker: Component {
    let selected: AccentRole
    let choose: @MainActor (AccentRole) -> Void

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            ForEach(AccentRole.allCases, id: \.rawValue) { role in
                AccentSwatch(role: role, isSelected: role == selected) { choose(role) }
            }
        }
    }
}
