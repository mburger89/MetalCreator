import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import Foundation

/// Templates and logos in the app (DR-5 R10, R11): the store of templates is an app preference, so nothing here is an undo step
/// except the sheet or the logo the document takes. A logo is untrusted input: read bounded, checked before a pixel is decoded and
/// decoded off the main actor (`DrawingSession+Logos`), and a refusal reaches the person as an alert that says what failed.
extension AppModel {
    /// Shows the sheet inspector and the "+" menu the store's templates and the last problem it had.
    func syncTemplateChoices() {
        drawing.editor.templateChoices = templates.templates.map { DrawingTemplateChoice(id: $0.id, name: $0.name) }
        drawing.editor.templateProblem = templates.saveProblem
    }

    /// Carries out what the editor asks of the host.
    func handleDrawingRequest(_ request: DrawingEditorRequest) {
        switch request {
        case .newSheetFromTemplate(let id):
            Task { await addSheet(fromTemplate: id) }
        case .saveSheetAsTemplate(let id):
            saveSheetAsTemplate(id)
        case .chooseLogo(let id):
            guard let filePicker else { return }
            Task { await chooseLogo(for: id, using: filePicker) }
        case .renameTemplate(let id, let name):
            templates.rename(id, to: name)
            syncTemplateChoices()
        case .deleteTemplate(let id):
            templates.remove(id)
            syncTemplateChoices()
        }
    }

    /// Save Sheet as Template: the open sheet's paper, the drawing's standard, its owner, drawn by, material, density and logo bytes,
    /// named after the owner (else "Template") and made unique. Not an undo step.
    func saveSheetAsTemplate(_ id: SheetID) {
        let drawings = drawing.editor.document
        guard let sheet = drawings.sheet(id) else { return }
        var logo: Data?
        if let hex = sheet.titleBlock.logo, let hash = ImageHash(hex: hex) { logo = document.images[hash] }
        let owner = sheet.titleBlock.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        templates.add(
            DrawingTemplate.made(
                from: sheet, standard: drawings.settings.standard, logo: logo, name: owner.isEmpty ? "Template" : owner,
                id: UUID().uuidString))
        syncTemplateChoices()
    }

    /// New Sheet from Template: the sheet is made as one undo step with the template's logo embedded in the document, or made without
    /// the logo, with an alert saying why, when the logo can't be used.
    public func addSheet(fromTemplate id: String) async {
        guard let template = templates.template(id) else { return }
        commitPendingEntries()
        var hash: String?
        var failure: String?
        if let bytes = template.logo {
            failure = await drawing.vetLogo(bytes)
            if failure == nil { hash = document.addImage(bytes).hex }
        }
        drawing.editor.addSheet(from: template, logo: hash)
        // After the sheet: an alert up would have refused it.
        if let failure {
            alert = .problem(AppProblem("The template's logo couldn't be used", failure + " The sheet was made without it."))
        }
    }

    /// Choose Logo…: a PNG or JPEG, read bounded and checked, embedded in the document and set on the sheet as one undo step.
    public func chooseLogo(for sheet: SheetID, using picker: any FilePicker) async {
        let picker = tracked(picker)
        commitPendingEntries()
        let url: URL
        do {
            guard let chosen = try await picker.chooseFileToOpen(Self.imageTypes) else { return }
            url = chosen
        } catch {
            report(error, title: "The logo couldn't be chosen")
            return
        }
        let data: Data
        do {
            data = try RegularFile.read(url, limit: LogoLimits.maximumBytes)
        } catch {
            alert = .problem(AppProblem("The logo couldn't be used", Self.sentence(for: error)))
            return
        }
        if let problem = await drawing.vetLogo(data) {
            alert = .problem(AppProblem("The logo couldn't be used", problem))
            return
        }
        guard drawing.editor.document.sheet(sheet) != nil else { return }
        drawing.editor.setLogo(document.addImage(data).hex, of: sheet)
    }

    private static func sentence(for problem: RegularFileProblem) -> String {
        switch problem {
        case .notAFile: "The logo isn't a file."
        case .tooLarge: LogoLimits.fileTooLargeSentence
        case .unreadable(let reason): "The logo couldn't be read: \(reason)"
        }
    }
}
