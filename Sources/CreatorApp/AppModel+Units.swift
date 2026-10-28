import CreatorGeometry
import CreatorGraph

/// The document's units (DIM-1): chosen in View ▸ Units and View ▸ Precision, an undoable setting of the document that
/// changes how lengths are written and read, never the lengths themselves.
extension AppModel {
    /// The open document's display units.
    public var units: DocumentUnits { document.units }

    /// Shows lengths in `length`: one "Change Units" step, remembered for new documents. The same unit changes nothing. A value
    /// box open at the time closes, its text being in the old unit.
    public func setUnits(_ length: LengthUnit) {
        guard length != units.length else { return }
        unitPreference.lastLength = length
        change(DocumentUnits(length: length), name: UndoName.changeUnits)
    }

    /// Shows `digits` decimals (0 to 4): one "Change Precision" step. The unit's default precision stores no key. The same
    /// precision changes nothing.
    public func setPrecision(_ digits: Int) {
        let clamped = min(max(digits, DocumentUnits.precisionRange.lowerBound), DocumentUnits.precisionRange.upperBound)
        var new = units
        new.precision = clamped == new.length.defaultPrecision ? nil : clamped
        change(new, name: UndoName.changePrecision)
    }

    private func change(_ new: DocumentUnits, name: String) {
        guard new != units else { return }
        viewport.closeValueBox()
        do {
            try document.perform(.setUnits(new), name: name)
        } catch {
            alert = .problem(AppProblem("The units couldn't be changed", error.message))
            return
        }
        refreshSketch()
        refreshDimensions()
    }
}
