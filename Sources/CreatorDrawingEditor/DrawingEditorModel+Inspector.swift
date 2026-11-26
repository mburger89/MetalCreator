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
        if key == .revision, let rows = sheet?.revisionTable?.table.rows, !rows.isEmpty {
            refuse(Self.revisionFromTableSentence)
            return
        }
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

    // MARK: General tolerance and number format

    /// Sets the drawing's general tolerance; an ASME row that isn't a positive number is refused (plan R10).
    public func setGeneralTolerance(_ tolerance: GeneralTolerance) {
        var written = tolerance
        if case .asme(var table) = tolerance {
            for index in table.rows.indices {
                guard let text = Self.toleranceMagnitude(table.rows[index].text) else {
                    refuse(Self.generalToleranceSentence)
                    return
                }
                table.rows[index].text = text
            }
            written = .asme(table)
        }
        commit(DrawingStepName.editTitleBlock) { $0.settings.generalTolerance = written }
    }

    /// One ASME row from the inspector's field: the magnitude as typed, trimmed (plan R10).
    public func setASMEToleranceRow(places: Int, text: String) {
        guard case .asme(var table) = document.settings.generalTolerance else { return }
        guard let magnitude = Self.toleranceMagnitude(text) else {
            refuse(Self.generalToleranceSentence)
            return
        }
        if let index = table.rows.firstIndex(where: { $0.places == places }) {
            table.rows[index].text = magnitude
        } else {
            table.rows.append(ASMEToleranceRow(places: places, text: magnitude))
            table.rows.sort { $0.places < $1.places }
        }
        setGeneralTolerance(.asme(table))
    }

    public func setDecimalSign(_ sign: DecimalSign) {
        commit(DrawingStepName.changeNumberFormat) { $0.settings.decimalSign = sign }
    }

    /// The trimmed text when it is a positive number of digits and at most one point, else `nil`.
    static func toleranceMagnitude(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
            trimmed.filter({ $0 == "." }).count <= 1, let value = Double(trimmed), value.isFinite, value > 0
        else { return nil }
        return trimmed
    }
}
