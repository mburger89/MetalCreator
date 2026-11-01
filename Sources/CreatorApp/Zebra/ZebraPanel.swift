import CreatorEditor
import CreatorGraph
import CreatorStyle
import MetalUI

/// The zebra stripes panel: direction, how many stripes, how much is black, Lock and Done. It shows while the stripes are on and no
/// sketch is open. All behaviour is `AppModel`'s (`setZebraDirection`, `setZebraStripes`, `setZebraBlackShare`, `setZebraLock`, `setZebra`).
struct ZebraPanel: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The card's inner width in points.
    static let width = 220.0
    static let directions: [ZebraDirection] = [.horizontal, .vertical]

    /// The black share as the panel shows it, "50%".
    static func percentText(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    var content: some ElementGroup {
        if let settings = model.document.zebra, model.showsZebra {
            let palette = Palette(themes)
            GlassPanel(.zebraPanel) {
                VStack(alignment: .leading, spacing: Pixels(8)) {
                    Text("Zebra")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText.color)
                    Text("Direction").font(.callout).foregroundStyle(palette.primaryText.color)
                    Picker("Direction", selection: Binding(get: { Self.directions.firstIndex(of: settings.direction) ?? 0 }, set: { index in
                        if Self.directions.indices.contains(index) { model.setZebraDirection(Self.directions[index]) }
                    })) {
                        Text("Horizontal").tag(0)
                        Text("Vertical").tag(1)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: Pixels(6)) {
                        Text("Stripes").font(.callout).foregroundStyle(palette.primaryText.color)
                        Spacer()
                        Text("\(settings.stripes)").font(.callout).foregroundStyle(palette.secondaryText.color)
                    }
                    Slider(value: Binding(get: { Double(settings.stripes) }, set: { model.setZebraStripes(Int($0.rounded())) }),
                           in: Double(ZebraSettings.stripeRange.lowerBound)...Double(ZebraSettings.stripeRange.upperBound), step: 1)
                    HStack(spacing: Pixels(6)) {
                        Text("Black share").font(.callout).foregroundStyle(palette.primaryText.color)
                        Spacer()
                        Text(Self.percentText(settings.blackShare)).font(.callout).foregroundStyle(palette.secondaryText.color)
                    }
                    Slider(value: Binding(get: { settings.blackShare * 100 },
                                          set: { model.setZebraBlackShare(($0 / 5).rounded() * 5 / 100) }),
                           in: 20...80, step: 5)
                    Toggle("Lock stripes to the part", isOn: Binding(get: { settings.lock != nil }, set: { model.setZebraLock($0) }))
                    Button("Done") { model.setZebra(false) }
                }
                .frame(width: Self.width.px)
            }
        }
    }
}
