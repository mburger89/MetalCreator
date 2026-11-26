import CreatorDrawing

/// Logos, sheets from templates and what only the host can do (DR-5 R10, R16).
extension DrawingEditorModel {
    /// Passes a request to the host.
    public func request(_ request: DrawingEditorRequest) {
        events.requested(request)
    }

    /// Sets the sheet's logo by the hash of its bytes in the document's image table (the host put them there); `nil` removes it.
    public func setLogo(_ hash: String?, of sheet: SheetID) {
        commitSheet(sheet, DrawingStepName.changeLogo) { $0.titleBlock.logo = hash }
    }

    /// Adds a sheet from `template`: its size, orientation and title block defaults, today's date, the logo the host stored, named as
    /// `addSheet()` names it. The template's standard applies only to a drawing's first sheet.
    public func addSheet(from template: DrawingTemplate, logo: String?) {
        var block = template.titleBlock
        block.title = ""
        block.drawingNumber = ""
        block.revision = ""
        block.date = today()
        block.logo = logo
        let sheet = DrawingSheet(
            name: nextSheetName(), size: template.size, orientation: template.orientation, titleBlock: block)
        let first = document.sheets.isEmpty
        commit(DrawingStepName.addSheet) { document in
            if first { document.settings.standard = template.standard }
            document.sheets.append(sheet)
            if document.settings.generalTolerance.isEmpty {
                document.settings.generalTolerance = GeneralTolerance.standardDefault(
                    for: document.settings.standard, inches: self.standardUnitsAreInches)
            }
        }
        show(sheet: sheet.id)
    }
}
