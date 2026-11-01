import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Foundation
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The zebra stripes in the app: settings on the document, the viewport's stripes and mesh angle, the panel and the lock.
@MainActor
struct ZebraAppTests {
    func boxApp() async -> AppModel {
        var builder = GraphBuilder()
        _ = builder.box()
        return await makeApp(builder.graph)
    }

    @Test func theToggleMenuAndKeyTurnZebraOn() async throws {
        let app = await boxApp()
        #expect(app.viewport.zebra == nil)
        app.setZebra(true)
        await app.settle()
        #expect(app.document.zebra?.isOn == true && app.viewport.zebra != nil)
        let input = AppInput(model: app)
        #expect(input.handleAction(ZebraKeyAction()))
        await app.settle()
        #expect(app.document.zebra?.isOn == false && app.viewport.zebra == nil)
        #expect(input.handleAction(ZebraKeyAction()))
        await app.settle()
        #expect(app.document.zebra?.isOn == true && app.viewport.zebra != nil)

        let window = try await AppWindow.open()
        let toggle = try #require(try window.window.elements { $0.label == "Zebra" && $0.role != .staticText }.first)
        try window.window.click(toggle)
        try await window.window.runUntilIdle()
        #expect(window.model.document.zebra?.isOn == true)
        #expect(try window.window.elements { $0.role == .button && $0.label == "Done" }.count == 1)
    }

    @Test func zebraIsNoEdit() async {
        let app = await boxApp()
        app.setZebra(true)
        app.setZebraStripes(20)
        app.setZebraDirection(.vertical)
        app.setZebraBlackShare(0.4)
        await app.settle()
        #expect(app.document.zebra?.stripes == 20 && app.document.zebra?.direction == .vertical)
        #expect(!app.document.canUndo && !app.isEdited)
    }

    @Test func sketchModeHidesZebra() async {
        var builder = GraphBuilder()
        _ = builder.box()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 300))
        let app = await makeApp(builder.graph)
        app.setZebra(true)
        await app.settle()
        #expect(app.viewport.zebra != nil)
        app.beginSketch(for: sketch.id)
        await app.settle()
        #expect(app.sketch != nil && app.viewport.zebra == nil && app.viewport.displayAngle == DisplayAngle.standard)
        #expect(!AppInput(model: app).handleAction(ZebraKeyAction()), "Z falls through while sketching")
        app.sketch?.stop()
        app.sketch = nil
        await app.settle()
        #expect(app.viewport.zebra != nil)
    }

    @Test func zebraRefinesTheMeshes() async {
        let app = await boxApp()
        #expect(app.viewport.displayAngle == 0.5)
        app.setZebra(true)
        await app.settle()
        #expect(app.viewport.displayAngle == 0.05)
        app.setZebra(false)
        await app.settle()
        #expect(app.viewport.displayAngle == 0.5)
    }

    @Test func lockCapturesTheCameraAndReopens() async throws {
        let app = await boxApp()
        app.setZebra(true)
        let pose = app.viewport.pose
        app.setZebraLock(true)
        let frame = try #require(app.document.zebra?.lock)
        #expect(frame == ZebraFrame(right: pose.right, up: pose.up, toEye: pose.toEye))
        app.viewport.pose.yaw += 0.7
        await app.settle()
        #expect(app.document.zebra?.lock == frame, "orbiting leaves the lock")
        #expect(app.viewport.zebra?.lock == ViewportZebra.Frame(right: frame.right, up: frame.up, toEye: frame.toEye))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }
        try app.save(to: url)
        let reopened = AppModel(kernel: FakeKernel())
        try reopened.open(url)
        await reopened.settle()
        #expect(reopened.viewport.zebra?.lock == app.viewport.zebra?.lock && reopened.viewport.zebra?.lock != nil)
        reopened.setZebraLock(false)
        await reopened.settle()
        #expect(reopened.document.zebra?.lock == nil && reopened.viewport.zebra?.lock == nil)
    }

    @Test func thePanelStacksBelowMeasure() {
        let all = SectionPanelDock.gaps(sectionOn: true, measureShows: true, zebraShows: true)
        #expect(all.measure == 8 && all.zebra == 8)
        let alone = SectionPanelDock.gaps(sectionOn: false, measureShows: false, zebraShows: true)
        #expect(alone.measure == 0 && alone.zebra == 0)
        let belowMeasure = SectionPanelDock.gaps(sectionOn: false, measureShows: true, zebraShows: true)
        #expect(belowMeasure.measure == 0 && belowMeasure.zebra == 8)
    }

    @Test func thePanelShowsItsCopy() async throws {
        let window = try await AppWindow.open()
        window.model.setZebra(true)
        try await window.window.runUntilIdle()
        let all = try window.window.elements { _ in true }
        let labels = Set(all.compactMap(\.label) + all.compactMap(\.value))
        for text in ["Zebra", "Direction", "Horizontal", "Vertical", "Stripes", "Black share", "Lock stripes to the part", "Done"] {
            #expect(labels.contains(text), "\(text) in \(labels.sorted())")
        }
        #expect(ZebraPanel.percentText(0.5) == "50%")
        try window.window.click(try #require(try window.window.elements { $0.role == .button && $0.label == "Done" }.first))
        try await window.window.runUntilIdle()
        #expect(window.model.document.zebra?.isOn == false)
    }

    @Test func zKeyFallsThroughOverTheCanvas() async {
        let app = await boxApp()
        let input = AppInput(model: app)
        app.editor.pointerLocation = Vector2(40, 40)
        #expect(!input.handleAction(ZebraKeyAction()) && app.document.zebra == nil)
        #expect(AppInput.keymap.bindings.contains { $0.spelling == "z" && $0.context == AppKeyContext.viewport })
    }
}
