import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// MetalUI S1 (gap XP-G3, record §112): on SDL the window is borderless, MetalUI draws minimise, zoom and close at the
/// window's top right (a 138-point cluster in a 32-point band, `HeadlessPlatformWindow.Options.sdlChrome`), and the
/// layout clears them. macOS keeps its traffic lights at the left and its layout untouched. The numbers are the
/// platform's own as MetalUI documents them; where the buttons really are is human check group XP.
@MainActor
struct SDLChromeWindowTests {
    let width: Float = 1440
    let drawnLabels = ["Minimise", "Zoom", "Close"]
    /// The sketch bar's invisible Escape carrier: zero-size, opacity 0, not hit-testable (`EscapeKey`), so it is no control.
    let invisible = ["Escape"]

    /// The rectangle of an element, as a `CanvasRect`.
    func rect(_ element: TestElement) -> CanvasRect {
        let frame = element.frame
        return CanvasRect(origin: Vector2(Double(frame.origin.x.value), Double(frame.origin.y.value)),
                          size: Vector2(Double(frame.size.width.value), Double(frame.size.height.value)))
    }

    /// The three drawn buttons' union: the cluster as MetalUI actually placed it.
    func cluster(_ app: AppWindow) throws -> CanvasRect {
        let buttons = try drawnLabels.map { rect(try app.window.element(label: $0)) }
        return buttons.dropFirst().reduce(buttons[0]) { $0.union($1) }
    }

    /// Every accessible element whose frame touches `cluster`, other than the drawn buttons themselves.
    func intruders(_ app: AppWindow, into cluster: CanvasRect) throws -> [String] {
        try app.window.elements(where: { _ in true })
            .filter { rect($0).intersects(cluster) && $0.role != .group && !drawnLabels.contains($0.label ?? "")
                      && !invisible.contains($0.label ?? "") }
            .map { "\($0.role) \($0.label ?? "-") \(rect($0))" }
    }

    /// The top bar's content, left to right: the label then its controls, without the buttons MetalUI draws.
    func barControls(_ app: AppWindow) throws -> [TestElement] {
        try app.topBarControls().filter { !drawnLabels.contains($0.label ?? "") && !invisible.contains($0.label ?? "") }
            .sorted { $0.frame.origin.x.value < $1.frame.origin.x.value }
    }

    @Test func theDrawnButtonsAreTheClusterTheInsetsPromise() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        let cluster = try cluster(app)
        let promised = try #require(AppLayout.buttonCluster(titleBarInsets: app.window.platformWindow.titleBarInsets,
                                                            windowWidth: Double(width)))
        #expect(cluster == promised)
        #expect(promised.size.x == 138 && promised.size.y == 32)
    }

    @Test func theBarsControlsEndLeftOfTheButtons() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        let cluster = try cluster(app)
        let controls = try barControls(app)
        #expect(controls.count == 4, "Preview, Undo, Redo and Export")
        for control in controls { #expect(!rect(control).intersects(cluster), "\(control.label ?? "a control")") }
        let last = try #require(controls.last)
        #expect(Double(last.frame.origin.x.value + last.frame.size.width.value) <= cluster.origin.x - AppLayout.titleBarGap + 0.5,
                "and the gap is kept")
        let under = try intruders(app, into: cluster)
        #expect(under.isEmpty, "nothing else of the bar's is under them: \(under)")
    }

    @Test func theNameStillStartsAtTheGlassPaddingBecauseTheButtonsAreAtTheRight() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        let flush = Float(AppLayout.margin + GraphPanelLayout.glassPadding)
        #expect(abs(try app.topBarLabel().frame.origin.x.value - flush) < 0.5)
    }

    @Test func theThemeDockSitsBelowTheBand() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        app.themeEditor.open()
        app.redraw()
        let cluster = try cluster(app)
        #expect(ThemeEditorLayout.top >= cluster.maxY, "the dock starts below the band")
        let under = try intruders(app, into: cluster)
        #expect(under.isEmpty, "\(under)")
        let dock = try app.window.elements(where: {
            $0.frame.origin.y.value >= Float(ThemeEditorLayout.top) - 1 && $0.frame.origin.x.value > width - 400
        })
        #expect(!dock.isEmpty, "the editor is open at the top right")
    }

    @Test func theSketchToolbarClearsTheButtons() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph, options: .sdlChrome)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        let cluster = try cluster(app)
        let controls = try barControls(app)
        #expect(controls.count > 5, "the sketch tools, Finish and the rest")
        for control in controls { #expect(!rect(control).intersects(cluster), "\(control.label ?? "a control")") }
        let finish = try app.window.element(label: "Finish")
        #expect(Double(finish.frame.origin.x.value + finish.frame.size.width.value) <= cluster.origin.x - AppLayout.titleBarGap + 0.5)
        let under = try intruders(app, into: cluster)
        #expect(under.isEmpty, "\(under)")
    }

    @Test func theMinimumWindowWidthStillFits() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        app.window.resize(to: Size(width: Pixels(1000), height: Pixels(640)))
        let cluster = try cluster(app)
        #expect(cluster.origin.x == 1000 - 138)
        let label = try app.topBarLabel()
        var edge = label.frame.origin.x.value + label.frame.size.width.value
        for control in try barControls(app) {
            #expect(control.frame.origin.x.value >= edge, "\(control.label ?? "a control") starts after what is left of it")
            edge = control.frame.origin.x.value + control.frame.size.width.value
        }
        #expect(Double(edge) <= cluster.origin.x, "the last control ends left of the buttons")
    }

    // MARK: Dragging

    @Test func theEmptySpaceBetweenTheNameAndTheControlsIsADragRegionAndTheControlsAreNot() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        app.window.tick()
        let regions = app.window.windowDragRegions
        func covered(_ point: Point<Pixels>) -> Bool {
            regions.contains { $0.contains(point) }
        }
        // The viewport under the whole window takes the pointer (its orbit and pick gestures) on macOS; since MetalUI S1b
        // (gap XP-G11) a hitbox carves a handle only if it ranks above the handle, and a window-wide blocker reaching
        // below the band does not carve the band, so the regions are published with the viewport behind the bar.
        #expect(!regions.isEmpty, "the drag regions are published")
        #expect(covered(app.point(600, 34)), "the bar's empty space")
        #expect(covered(app.point(600, 5)), "the strip above the bar")
        #expect(covered(app.point(30, 34)), "and the document's name")
        for control in try barControls(app) {
            #expect(!covered(app.centre(of: control)), "\(control.label ?? "a control") takes its own press (divergence 426)")
        }
        for label in drawnLabels {
            #expect(!covered(app.centre(of: try app.window.element(label: label))), "\(label) is a button")
        }
    }

    @Test func aHandleHoldingControlsDragsAroundThemInTheSketchBarToo() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph, options: .sdlChrome)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        let regions = app.window.windowDragRegions
        for control in try barControls(app) {
            #expect(!regions.contains { $0.contains(app.centre(of: control)) }, "\(control.label ?? "a control")")
        }
        #expect(regions.contains { $0.contains(app.point(600, 5)) }, "the strip is still a handle")
    }

    // MARK: Close

    @Test func theDrawnCloseButtonGoesThroughTheClosingModel() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        app.model.installCloseHandling(on: app.window.window) {}
        try app.window.click(try app.window.element(label: "Close"))
        #expect(app.window.platformWindow.isClosed, "a document with no changes closes at once")
    }

    @Test func withUnsavedChangesTheDrawnCloseButtonAsksFirst() async throws {
        let app = try await AppWindow.open(options: .sdlChrome)
        app.model.installCloseHandling(on: app.window.window) {}
        try app.model.document.perform(.addNode(BuiltInNodes.registry.makeNode(NumberNode.typeID)))
        #expect(app.model.isEdited)
        try app.window.click(try app.window.element(label: "Close"))
        #expect(!app.window.platformWindow.isClosed, "the veto kept the window")
        #expect(app.model.alert == .saveChanges(name: app.model.displayName))
        #expect(app.model.closeRequest == .asking)
    }

    // MARK: macOS

    /// The frames the bar had before S1, read from master (8a943eb) with the traffic lights' insets (left 69, top 32):
    /// the name, then Preview, Undo, Redo and Export, as x, y, width, height. Nothing moves on macOS but Preview, which the Section toggle
    /// (a switch is not one of `topBarControls`, between Preview and Undo) pushes it left.
    @Test func macLayoutIsWhatItWas() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        #if canImport(Metal)
        let expected: [[Float]] = [[77, 26, 52, 16], [1001, 22, 124, 24], [1211, 22, 57, 24], [1278, 22, 55, 24], [1343, 22, 75, 24]]
        let found = try [app.topBarLabel()] + app.topBarControls().sorted { $0.frame.origin.x.value < $1.frame.origin.x.value }
        #expect(found.map { [$0.frame.origin.x.value, $0.frame.origin.y.value, $0.frame.size.width.value, $0.frame.size.height.value] }
                == expected)
        #endif
        #expect(abs(try app.topBarLabel().frame.origin.x.value - Float(69 + AppLayout.titleBarGap)) < 0.5, "text metrics aside, the name")
        #expect(app.window.platformWindow.titleBarInsets.right.value == 0, "the traffic lights are at the left only")
        #expect(try app.window.elements(where: { _ in true }).allSatisfy { !drawnLabels.contains($0.label ?? "") },
                "AppKit has its own buttons: MetalUI draws none")
    }

    /// With the traffic lights' band (32) the bar still starts at the margin, as before: it was always under the band, and
    /// only its content clears the buttons sideways.
    @Test func theBarStillStartsAtTheMarginUnderTheMacBand() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        let top = try app.topBarControls().map(\.frame.origin.y.value).min()
        #expect(try #require(top) == Float(AppLayout.margin + GraphPanelLayout.glassPadding))
    }
}
