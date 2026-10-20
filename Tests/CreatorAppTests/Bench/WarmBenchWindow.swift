// Test fixture file: one window and its Frame kept alive across steps, for the warm benchmark rows and the work-count pin.
import CreatorGeometry
import CreatorViewport
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The app's real window root in a `TestWindow` that lives for the whole run, so every frame after the first is warm: the
/// `Frame` is retained, and MetalUI's skip and graft (C14b, C14b-2, C14-c, C14b-3) can pay off. `BenchRenderer.windowScene`
/// builds a fresh `Frame` per call (a first frame: window open, resize, theme switch), which is what the cold rows time.
/// Steady interaction (a drag, a pan, a zoom) is the warm case, and the 60 fps budget is judged on it.
@MainActor
final class WarmBenchWindow {
    let model: AppModel
    let window: TestWindow
    private let testApp: TestApp
    private let input: AppInput
    private let themeEditor: ThemeEditorModel

    /// Opens a 1440 × 900 window on `model` (the size the benchmarks draw, `Bench.windowWidth` × `Bench.windowHeight`) and
    /// runs it until its first frames, including the panel's and the viewport's geometry reports, are done.
    init(model: AppModel) async throws {
        self.model = model
        themeEditor = ThemeEditorModel(themes: model.themes)
        input = AppInput(model: model)
        testApp = try TestApp(textSystem: { testTextSystem() })
        AppCommands.install(on: testApp.app, model: model, themeEditor: themeEditor)
        let model = model, input = input, themeEditor = themeEditor
        window = try testApp.openWindow(
            title: "MetalCreator", size: Size(width: Pixels(1440), height: Pixels(900)),
            windowStyle: AppLayout.windowStyle, options: nil, recordsLayout: false
        ) {
            ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        input.install(on: window.window)
        try await window.runUntilIdle()
    }

    /// One warm frame: the window redrawn, and the work MetalUI did for it (the sum of the frames it presented).
    @discardableResult
    func frame() -> FrameWork {
        window.resetFrameWork()
        window.window.setNeedsRedraw()
        window.tick()
        return window.frameWork.reduce(FrameWork(), +)
    }

    /// One warm frame timed, in milliseconds.
    func timedFrame(clock: ContinuousClock = ContinuousClock()) -> Double {
        window.resetFrameWork()
        window.window.setNeedsRedraw()
        let start = clock.now
        window.tick()
        return (clock.now - start) / .milliseconds(1)
    }
}
