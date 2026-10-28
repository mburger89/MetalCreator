import CreatorGeometry
import MetalUI

/// View ▸ Units and View ▸ Precision (DIM-1): the length units, then the decimals, each with a checkmark on the one the
/// document shows. Choosing one changes the document's units (one undo step). Rebuilt each time the menu opens.
enum UnitsMenu {
    /// The titles of the precision items, in order: 1 to 0.0001 (0 to 4 decimals).
    static let precisionTitles = DocumentUnits.precisionRange.map { digits in
        digits == 0 ? "1" : "0." + String(repeating: "0", count: digits - 1) + "1"
    }

    @MainActor
    @MenuContentBuilder
    static func unitItems(_ model: AppModel) -> MenuItems {
        for unit in LengthUnit.allCases {
            // Choosing the checked unit writes `false`; setting it again changes nothing.
            Toggle(unit.title, isOn: Binding(get: { model.units.length == unit }, set: { _ in model.setUnits(unit) }))
        }
    }

    @MainActor
    @MenuContentBuilder
    static func precisionItems(_ model: AppModel) -> MenuItems {
        for (digits, title) in precisionTitles.enumerated() {
            Toggle(title, isOn: Binding(get: { model.units.fractionDigits == digits }, set: { _ in model.setPrecision(digits) }))
        }
    }
}
