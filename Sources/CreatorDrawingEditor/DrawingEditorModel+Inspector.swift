import CreatorDrawing
import CreatorGeometry

extension DrawingEditorModel {
    public func setSheetSize(_ size: SheetSize) {
        commitSheet(DrawingStepName.changeSheetSize) { $0.size = size }
    }

    public func setSheetOrientation(_ orientation: SheetOrientation) {
        commitSheet(DrawingStepName.changeSheetSize) { $0.orientation = orientation }
    }

    /// The sheet's own scale, which every view without an override uses.
    public func setSheetScale(_ scale: DrawingScale) {
        guard scale.isValid else {
            refuse("A scale is two whole numbers from 1 to 1000.")
            return
        }
        commitSheet(DrawingStepName.changeScale) { $0.scale = scale }
    }

    /// Edits a typed title-block field of the current sheet and the defaults new sheets start with; an automatic key does nothing.
    public func setTitleField(_ key: TitleBlockKey, to value: String) {
        guard key.isTyped, let id = currentSheet else { return }
        commit(DrawingStepName.editTitleBlock) { document in
            guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
            func write(_ block: inout TitleBlock) {
                switch key {
                case .owner: block.owner = value
                case .drawnBy: block.drawnBy = value
                case .date: block.date = value
                case .title: block.title = value
                case .material: block.material = value
                case .drawingNumber: block.drawingNumber = value
                case .revision: block.revision = value
                case .mass, .scale, .projection, .size, .sheet, .tolerance: break
                }
            }
            write(&document.sheets[index].titleBlock)
            write(&document.settings.titleBlockDefaults)
        }
    }

    /// Sets the density from typed text: empty clears it; anything but a positive finite number is refused in words.
    public func setDensity(text: String) {
        let trimmed = String(text.drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
        if trimmed.isEmpty {
            setDensity(nil)
        } else if let value = Double(trimmed), value.isFinite, value > 0 {
            setDensity(value)
        } else {
            refuse("A density is a positive number in g/cm³, such as 7.85.")
        }
    }

    public func setDensity(_ density: Double?) {
        guard let id = currentSheet else { return }
        commit(DrawingStepName.editTitleBlock) { document in
            guard let index = document.sheets.firstIndex(where: { $0.id == id }) else { return }
            document.sheets[index].titleBlock.density = density
            document.settings.titleBlockDefaults.density = density
        }
    }

    /// Changes the drawing's standard; every sheet's projected views mirror across their parents (plan R6).
    public func setStandard(_ standard: DrawingStandard) {
        guard standard != document.settings.standard else { return }
        commit(DrawingStepName.changeStandard) { document in
            let old = document.settings
            document.settings.standard = standard
            if old.generalTolerance == GeneralTolerance.standardDefault(for: old.standard, inches: self.standardUnitsAreInches) {
                document.settings.generalTolerance = GeneralTolerance.standardDefault(
                    for: standard, inches: self.standardUnitsAreInches)
            }
            document.sheets = document.sheets.map(ViewPlacement.mirroredForStandardChange)
        }
    }
}
