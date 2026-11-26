import CreatorDrawing
@testable import CreatorDrawingEditor
import CreatorGeometry
@testable import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// Templates and logos in the app (DR-5 R10, R11): the store, the sheet a template makes, and the logo as untrusted input.
@MainActor
struct DrawingTemplateAppTests {
    func app(templates: DrawingTemplateStore = DrawingTemplateStore()) async -> AppModel {
        await AppModel.inDrawing(DrawingBox().graph, templates: templates)
    }

    func template(logo: Data? = nil, name: String = "Acme") -> DrawingTemplate {
        DrawingTemplate(
            id: UUID().uuidString, name: name, size: .a3, orientation: .landscape, standard: .iso,
            titleBlock: TitleBlock(owner: "Acme", material: "Steel", drawnBy: "Max", density: 7.85), logo: logo)
    }

    var logoBytes: Data { AppTestImages.png(40, 20, level: 90) }

    // MARK: Saving and making

    @Test func savingASheetAsATemplate() async throws {
        let app = await app()
        let editor = app.drawing.editor
        let sheet = try #require(editor.currentSheet)
        editor.setTitleField(.owner, to: "Acme Ltd")
        let hash = app.document.addImage(logoBytes)
        editor.setLogo(hash.hex, of: sheet)
        app.handleDrawingRequest(.saveSheetAsTemplate(sheet))
        let saved = try #require(app.templates.templates.first)
        #expect(saved.name == "Acme Ltd" && saved.titleBlock.owner == "Acme Ltd")
        #expect(saved.size == editor.document.sheets[0].size && saved.logo == logoBytes, "the logo's bytes from `images`")
        #expect(app.drawing.editor.templateChoices.map(\.name) == ["Acme Ltd"])
        #expect(app.templates.templates.count == 1)
        app.handleDrawingRequest(.saveSheetAsTemplate(sheet))
        #expect(app.templates.templates.map(\.name).sorted() == ["Acme Ltd", "Acme Ltd 2"], "unique")
    }

    @Test func aSheetFromATemplateEmbedsItsLogo() async throws {
        let store = DrawingTemplateStore()
        let made = template(logo: logoBytes)
        store.add(made)
        let app = await app(templates: store)
        let before = app.drawing.editor.document.sheets.count
        await app.addSheet(fromTemplate: made.id)
        let sheet = try #require(app.drawing.editor.document.sheets.last)
        #expect(app.drawing.editor.document.sheets.count == before + 1)
        let hash = ImageHash(of: logoBytes)
        #expect(app.document.images[hash] == logoBytes, "the bytes are in the document's images")
        #expect(sheet.titleBlock.logo == hash.hex && sheet.titleBlock.owner == "Acme")
        #expect(app.undoTitle == "Undo Add Sheet", "one undo step: \(app.undoTitle)")
        app.undo()
        #expect(app.drawing.editor.document.sheets.count == before)
        #expect(app.alert == nil)
    }

    // MARK: Refusals

    @Test func oversizedLogosAreRefused() async throws {
        let app = await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        let wide = temporaryURL("wide.png")
        let big = temporaryURL("big.png")
        defer { for url in [wide, big] { try? FileManager.default.removeItem(at: url) } }
        try AppTestImages.png(2_000, 10).write(to: wide)
        try Data(count: 3 * 1_024 * 1_024).write(to: big)
        await app.chooseLogo(for: sheet, using: ScriptedPicker([wide]))
        #expect(app.alert == .problem(AppProblem("The logo couldn't be used", LogoLimits.sideSentence(width: 2_000, height: 10) ?? "")))
        app.alert = nil
        await app.chooseLogo(for: sheet, using: ScriptedPicker([big]))
        #expect(app.alert == .problem(AppProblem("The logo couldn't be used", "A logo file is at most 2 MB.")))
        #expect(app.drawing.editor.document.sheets[0].titleBlock.logo == nil && app.document.images.isEmpty)
    }

    @Test func theLogoSizeUsesMessageNumbers() async throws {
        let app = await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        let url = temporaryURL("wide.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try AppTestImages.png(2_000, 10).write(to: url)
        await app.chooseLogo(for: sheet, using: ScriptedPicker([url]))
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.message == "A logo is at most 1,024 pixels on a side; this picture is 2,000 × 10.", "\(problem.message)")
    }

    @Test func aBrokenTemplateLogoMakesTheSheetWithoutIt() async throws {
        let store = DrawingTemplateStore()
        let cut = AppTestImages.png(40, 20).prefix(60)
        let made = template(logo: Data(cut))
        store.add(made)
        let app = await app(templates: store)
        await app.addSheet(fromTemplate: made.id)
        let sheet = try #require(app.drawing.editor.document.sheets.last)
        #expect(sheet.titleBlock.logo == nil && sheet.titleBlock.owner == "Acme", "the sheet was made, without the logo")
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "The template's logo couldn't be used")
        #expect(problem.message == ImageProblem.undecodable.message + " The sheet was made without it.", "\(problem.message)")
        #expect(app.document.images.isEmpty)
    }

    @Test func logoAlertsSayWhatFailed() async throws {
        let app = await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        let gif = temporaryURL("logo.png")
        defer { try? FileManager.default.removeItem(at: gif) }
        try AppTestImages.gif().write(to: gif)
        await app.chooseLogo(for: sheet, using: ScriptedPicker([gif]))
        #expect(app.alert == .problem(AppProblem("The logo couldn't be used", ImageProblem.unsupportedType.message)))
        // From a template: the other title, and the body ends with what happened to the sheet.
        let store = DrawingTemplateStore()
        let bad = template(logo: AppTestImages.gif())
        store.add(bad)
        let second = await self.app(templates: store)
        await second.addSheet(fromTemplate: bad.id)
        guard case .problem(let problem)? = second.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "The template's logo couldn't be used")
        #expect(problem.message.hasSuffix(" The sheet was made without it."))
    }

    @Test func aLogoFileIsReadBounded() async throws {
        let app = await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        let sparse = temporaryURL("logo.png")
        defer { try? FileManager.default.removeItem(at: sparse) }
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1 << 30)
        try handle.close()
        await app.chooseLogo(for: sheet, using: ScriptedPicker([sparse]))
        #expect(app.alert == .problem(AppProblem("The logo couldn't be used", "A logo file is at most 2 MB.")), "refused from its size")
        app.alert = nil
        let folder = temporaryURL("logo.png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        await app.chooseLogo(for: sheet, using: ScriptedPicker([folder]))
        #expect(app.alert == .problem(AppProblem("The logo couldn't be used", "The logo isn't a file.")))
    }

    // MARK: Decoding

    @Test func aTransparentLogoIsWhite() async throws {
        let app = await app()
        let bytes = AppTestImages.rgbaPNG(4, 4, alpha: 0)
        let hash = app.document.addImage(bytes)
        guard case .picture(let pixels) = await app.drawing.logo(forHash: hash.hex) else {
            Issue.record("not decoded")
            return
        }
        #expect(pixels.bytes.allSatisfy { $0 == 255 }, "paper, not black")
        #expect(pixels.key == hash.hex && pixels.width == 4 && pixels.height == 4)
    }

    @Test func logosDecodeOffTheMainActor() async throws {
        let app = await app()
        let gate = HookGate()
        defer { gate.open() }
        app.drawing.logoDecoder = { data in
            await gate.hold()
            return try await GreyImageDecoder.decode(data, background: .white)
        }
        let hash = app.document.addImage(logoBytes)
        let task = Task { await app.drawing.logo(forHash: hash.hex) }
        await gate.waitUntilEntered()
        // The decode is waiting in its hook and the main actor is ours again.
        #expect(app.drawing.logoCache[hash.hex] == nil)
        gate.open()
        guard case .picture(let pixels) = await task.value else {
            Issue.record("not decoded")
            return
        }
        #expect(pixels.width == 40 && pixels.height == 20)
    }

    @Test func aLogoOnTheSheetIsDrawnInTheTitleBlock() async throws {
        let app = await app()
        let sheet = try #require(app.drawing.editor.currentSheet)
        let url = temporaryURL("logo.png")
        defer { try? FileManager.default.removeItem(at: url) }
        try logoBytes.write(to: url)
        await app.chooseLogo(for: sheet, using: ScriptedPicker([url]))
        await app.settle()
        #expect(app.drawing.editor.document.sheets[0].titleBlock.logo == ImageHash(of: logoBytes).hex)
        #expect(app.undoTitle == "Undo Change Logo")
        #expect(app.drawing.editor.picture?.images.count == 1, "the picture is on the sheet")
    }
}
