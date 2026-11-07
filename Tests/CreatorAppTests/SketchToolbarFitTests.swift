import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// The sketch toolbar is a `ViewThatFits` over rows that move tools into a "More" menu from the end (gap TB-a, human check
/// UP-2): no label is ever cut short ("Dimensi…"), a More menu exists exactly when some tools don't fit and holds exactly
/// those, and every key fires once whichever row is chosen (the keys are invisible buttons outside the `ViewThatFits`).
@MainActor
struct SketchToolbarFitTests {
    private let tools = SketchTool.allCases

    private func openSketch() async throws -> AppModel {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        return app
    }

    private func openWindow(width: Float = 1440) async throws -> (app: AppWindow, editor: SketchEditorModel) {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        let editor = try #require(app.model.sketch).editor
        try await resize(app, to: width)
        return (app, editor)
    }

    private func resize(_ app: AppWindow, to width: Float) async throws {
        app.window.resize(to: Size(width: Pixels(width), height: Pixels(900)))
        try await app.window.runUntilIdle()
    }

    /// The labels of the buttons the bar shows (the toolbar is the top row; the invisible key buttons are hidden from accessibility).
    private func shownLabels(_ app: AppWindow) throws -> [String] {
        try app.window.elements(where: { $0.role == .button || $0.role == .menuButton })
            .filter { $0.frame.origin.y < Pixels(60) }.compactMap(\.label)
    }

    private func name(_ label: String) -> String {
        label.hasSuffix(" ✓") ? String(label.dropLast(2)) : label
    }

    /// How many tools the bar shows as buttons, as a prefix of `tools`; the rest must be in More.
    private func shownTools(_ app: AppWindow) throws -> [SketchTool] {
        let labels = Set(try shownLabels(app).map(name))
        return tools.filter { labels.contains($0.title) }
    }

    private func moreMenuTitles(_ app: AppWindow) throws -> [String]? {
        let labels = try shownLabels(app)
        guard let more = labels.first(where: { $0 == "More" || $0 == "More ✓" }) else { return nil }
        try app.window.click(app.window.element(label: more))
        let titles = app.window.presentedMenu?.items.map(\.title)
        try app.window.dismissMenu()
        return titles
    }

    // MARK: Fit

    /// The size of every glyph the bar draws, in order.
    private func glyphCount(_ app: AppModel, width: Double) -> Int {
        let bar = TopBar(model: app, clearance: Pixels(56))
        let scene = renderFrame({ ZStack { bar } }, size: Size(width: Pixels(Float(width)), height: Pixels(100)), scaleFactor: 2,
                                textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.glyphs.count
    }

    /// Glyphs of the labels one row shows, a glyph for each character but spaces.
    private func expectedGlyphs(inMore: Int, editor: SketchEditorModel) -> Int {
        let shown = tools.dropLast(inMore)
        let hidden = tools.suffix(inMore)
        var labels = shown.map { editor.tool == $0 ? "\($0.title) ✓" : $0.title }
        if !hidden.isEmpty { labels.append(hidden.contains(editor.tool) ? "More ✓" : "More") }
        labels.append(editor.isConstruction ? "Construction ✓" : "Construction")
        labels += ["Delete", "Finish"]
        // The More menu's button draws one more glyph, its pull-down arrow.
        return labels.reduce(hidden.isEmpty ? 0 : 1) { $0 + $1.filter { !$0.isWhitespace }.count }
    }

    /// No width cuts a label: the glyphs drawn are exactly those of one candidate row (a cut label swaps letters for an
    /// ellipsis and draws fewer), and a narrower bar never shows more tools.
    @Test func noLabelIsCutAtAnyWidth() async throws {
        let app = try await openSketch()
        let editor = try #require(app.sketch).editor
        editor.press(.arcThreePoint)
        editor.toggleConstruction()
        let base = glyphCount(app, width: 6000) - expectedGlyphs(inMore: 0, editor: editor)
        var previous = 0
        for width in stride(from: 1440.0, through: 1000.0, by: -40) {
            let drawn = glyphCount(app, width: width - 2 * AppLayout.margin) - base
            let rows = (0...tools.count).filter { expectedGlyphs(inMore: $0, editor: editor) == drawn }
            #expect(!rows.isEmpty, "a label is cut short at \(width) pt: \(drawn) glyphs match no row")
            if let row = rows.first {
                #expect(row >= previous, "a narrower window shows more tools at \(width) pt")
                previous = row
            }
        }
        #if canImport(CoreText)
        // Macs only: the portable text system's fonts on Linux and Windows are wider, so more tools sit in More there.
        let widest = glyphCount(app, width: 1440 - 2 * AppLayout.margin) - base
        #expect(widest == expectedGlyphs(inMore: 0, editor: editor), "candidate 0 isn't chosen at 1440 pt")
        #endif
    }

    @Test func theMoreMenuHoldsExactlyTheToolsMissingFromTheRow() async throws {
        let (app, editor) = try await openWindow()
        editor.press(.arcThreePoint)
        editor.toggleConstruction()
        var sawMore = false
        var previousShown = tools.count
        for width: Float in [1440, 1250, 1100, 1000, 900] {
            try await resize(app, to: width)
            let shown = try shownTools(app)
            #expect(shown == Array(tools.prefix(shown.count)), "tools leave the row from the end at \(width) pt")
            #expect(shown.count <= previousShown, "a narrower window shows more tools at \(width) pt")
            previousShown = shown.count
            let missing = tools.dropFirst(shown.count).map(\.title)
            let menu = try moreMenuTitles(app)
            if missing.isEmpty {
                #expect(menu == nil, "a More menu with every tool in the row at \(width) pt")
            } else {
                sawMore = true
                #expect(menu?.map(name) == missing, "More holds \(String(describing: menu)), not \(missing), at \(width) pt")
            }
            let labels = try shownLabels(app)
            #expect(labels.contains("Construction ✓") && labels.contains("Delete") && labels.contains("Finish"), "\(labels)")
        }
        #expect(sawMore, "no width of the sweep needed a More menu")
    }

    /// The frame widths of the bar's buttons by label.
    private func buttonWidths(_ app: AppWindow) throws -> [String: Float] {
        let found = try app.window.elements(where: { $0.role == .button || $0.role == .menuButton })
            .filter { $0.frame.origin.y < Pixels(60) }
        return Dictionary(found.compactMap { element in element.label.map { ($0, element.frame.size.width.value) } },
                          uniquingKeysWith: max)
    }

    /// The flexible drag gap is no share-taker: every button keeps at least the width it has with all the room there is,
    /// so a label is never cut while the gap still has slack (the stack offers a greedy child a share before it sizes
    /// the buttons).
    private func expectButtonsKeepTheirIdealWidth(construction: Bool, tool: SketchTool) async throws {
        let (app, editor) = try await openWindow(width: 3000)
        editor.press(tool)
        if construction { editor.toggleConstruction() }
        try await resize(app, to: 3000)
        let ideal = try buttonWidths(app)
        #expect(ideal["Finish"] != nil && ideal["Delete"] != nil)
        for width: Float in [1440, 1250, 1100, 1000] {
            try await resize(app, to: width)
            for (label, actual) in try buttonWidths(app) {
                guard let wanted = ideal[label] else { continue }
                #expect(actual >= wanted - 1.5, "\(label) is \(actual) pt wide, not \(wanted), at \(width) pt")
            }
        }
    }

    @Test func buttonsKeepTheirLabelsWidthBesideTheDragGapWidest() async throws {
        try await expectButtonsKeepTheirIdealWidth(construction: true, tool: .arcThreePoint)
    }

    @Test func buttonsKeepTheirLabelsWidthBesideTheDragGapPlain() async throws {
        try await expectButtonsKeepTheirIdealWidth(construction: false, tool: .line)
    }

    // MARK: Keys

    private let keys: [(SketchTool, KeyEquivalent)] = SketchTool.allCases.compactMap { tool in tool.key.map { (tool, $0) } }

    @Test func eachToolKeySelectsItsToolAtEveryWidth() async throws {
        let (app, editor) = try await openWindow()
        for width: Float in [1440, 1000, 700] {
            try await resize(app, to: width)
            for (tool, key) in keys {
                editor.press(.select)
                app.window.typeKey(key)
                #expect(editor.tool == tool, "\(String(key.character)) at \(width) pt selected \(editor.tool)")
            }
        }
    }

    /// A is the one tool key whose second fire shows: Arc turns into the 3-point arc and back. Once per press, at any width.
    @Test func aKeyFiresOnce() async throws {
        let (app, editor) = try await openWindow()
        for width: Float in [1440, 1000, 700] {
            try await resize(app, to: width)
            editor.press(.select)
            app.window.typeKey("a")
            #expect(editor.tool == .arc, "A at \(width) pt: \(editor.tool)")
            app.window.typeKey("a")
            #expect(editor.tool == .arcThreePoint, "A again at \(width) pt: \(editor.tool)")
        }
    }

    @Test func constructionDeleteAndFinishActOnceAtEveryWidth() async throws {
        let (app, editor) = try await openWindow()
        var finished = 0
        var committed = 0
        editor.events.finished = { finished += 1 }
        editor.events.committed = { _ in committed += 1 }
        for width: Float in [1440, 1000, 700] {
            try await resize(app, to: width)
            let before = editor.isConstruction
            app.window.typeKey("x")
            #expect(editor.isConstruction != before, "X at \(width) pt fired an even number of times")
            editor.toggleConstruction()
            committed = 0
            editor.selection = Set(editor.sketch.entities.keys.sorted().prefix(1))
            app.window.typeKey(.delete)
            #expect(committed == 1, "Delete at \(width) pt committed \(committed) times")
            finished = 0
            app.window.typeKey(.return)
            #expect(finished == 1, "Return at \(width) pt finished \(finished) times")
        }
    }

    // MARK: Menu

    @Test func choosingFromMoreSelectsTheToolAndMarksTheMenu() async throws {
        let (app, editor) = try await openWindow(width: 1000)
        let shown = try shownTools(app)
        let hidden = try #require(tools.dropFirst(shown.count).first, "nothing is in More at 1000 pt")
        editor.press(.select)
        #expect(try shownLabels(app).contains("More"))
        try app.window.click(app.window.element(label: "More"))
        #expect(app.window.presentedMenu?.items.map(\.title).contains(hidden.title) == true)
        try app.window.chooseMenuItem(hidden.title)
        try await app.window.runUntilIdle()
        #expect(editor.tool == hidden)
        #expect(try shownLabels(app).contains("More ✓"))
        // The item shows the mark while the tool is active.
        try app.window.click(app.window.element(label: "More ✓"))
        #expect(app.window.presentedMenu?.items.map(\.title).contains("\(hidden.title) ✓") == true)
        try app.window.dismissMenu()
    }

    /// A tool key with the More menu open does nothing: the headless window swallows typed keys while a natively
    /// presented menu is open (MetalUI #217), as AppKit's modal pull-down does, and Escape dismisses the menu. So A, which
    /// would toggle Arc to 3-Point Arc if it fired, leaves the tool alone and never fires twice.
    @Test func aKeyWithTheMoreMenuOpenDoesNotChangeTheTool() async throws {
        let (app, editor) = try await openWindow(width: 1000)
        editor.press(.select)
        try app.window.click(app.window.element(label: "More"))
        #expect(app.window.presentedMenu != nil)
        app.window.typeKey("a")
        #expect(editor.tool == .select, "A with the menu open: \(editor.tool)")
        #expect(app.window.presentedMenu != nil, "the menu is still open")
        if app.window.presentedMenu != nil { try app.window.dismissMenu() }
    }
}
