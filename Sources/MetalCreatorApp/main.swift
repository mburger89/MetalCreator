import CreatorApp
import CreatorGraph
import CreatorKernel
import Foundation
import MetalUI
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
#if canImport(MetalUISDL)
import MetalUIPortableText
@_spi(Checks) import MetalUISDL
import MetalUISystemFonts
#endif

/// The app over the platform's own backend, chosen at compile time as `metalui new --cross-platform` generates it:
/// AppKit and Metal on macOS, SDL3 with MetalUI's portable text over the installed fonts on Linux and Windows.
/// With `offscreen` (the smoke test) every window is hidden and draws into an offscreen target, so it builds frames without a
/// display; elsewhere than SDL the flag has no meaning and the app opens as usual.
@MainActor
func makeApp(offscreen: Bool = false) throws -> App {
    #if canImport(MetalUISDL)
    let resolver = try SystemFonts.resolver()
    let platform = offscreen ? try SDLPlatform(hiddenWindows: true, offscreenRenderers: true) : try SDLPlatform()
    return App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    #else
    return try App()
    #endif
}

/// OpenCascade where the package has it (macOS until xp-2); elsewhere a kernel that says geometry isn't available.
func makeKernel() -> any Kernel {
    #if canImport(CreatorOCCT)
    OCCTKernel()
    #else
    KernelUnavailable()
    #endif
}

/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It loads the app's themes (the remembered
/// one and the person's own), opens the window over the platform's kernel, installs the menu bar and the window's input
/// hooks, and opens the file named on the command line, if any. With a `smoke` (CI) the window is offscreen and the process
/// exits when the smoke's time is up, with the verdict.
/// `app.run()` is called from synchronous top-level code, as MetalUI requires.
@MainActor
func runApp(opening path: String?, smoke: LaunchSmoke? = nil) throws {
    let app = try makeApp(offscreen: smoke != nil)
    app.preferredColorScheme = .dark
    let model = AppModel(kernel: makeKernel(), themes: AppThemes.store(), implicitEngine: .automatic)
    let themeEditor = ThemeEditorModel(themes: model.themes)
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model, themeEditor: themeEditor)
    let window = try app.openWindow(title: "MetalCreator", size: Size(width: Pixels(1440), height: Pixels(900)),
                                    minSize: Size(width: Pixels(1000), height: Pixels(640)),
                                    windowStyle: AppLayout.windowStyle) {
        // A window's root must be an Element, and a Component is a group, so it's wrapped.
        ZStack {
            AppWindowRoot(model: model, input: input, themeEditor: themeEditor)
            // The smoke test's mark: MetalUI starts a `.task` inside the first frame.
            if let smoke { Spacer().task { smoke.frameReached() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    input.install(on: window)
    // Close and quit (gap M6-b): ⌘Q asks each window's `onCloseRequest` in turn when the app sets no
    // `onTerminateRequest`, and this app has one window, so one handler and one reply route serve both.
    window.onCloseRequest = {
        themeEditor.flush()   // a colour dragged just now is saved before the window can go
        return model.closeRequested()
    }
    model.replyToCloseRequest = { window.replyToCloseRequest($0) }
    // Title, edited dot and proxy icon (gap M6-a) follow the document. The task lives as long as the app.
    let chrome = WindowChromeSync(model: model, chrome: window)
    Task { await chrome.follow() }
    model.filePicker = WindowFilePicker(window: window)
    themeEditor.filePicker = model.filePicker
    // Opening documents (gap M6-d): Finder, the Dock and `open -a` reach `App.onOpenURL` while the app runs, so it is
    // set before `app.run()`. AppKit delivers no command-line path, so the path argument is handed over the same way.
    app.onOpenURL = { model.openRequested($0) }
    if let path {
        app.open([URL(fileURLWithPath: path)])
    }
    if let smoke {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(smoke.seconds))
            print(smoke.report)
            exit(smoke.passed ? 0 : 1)
        }
    }
    app.run()
}

/// `--self-test` (packaging): the checks run in a main-actor task, which the main run loop drains because this is
/// called from synchronous top-level code; the task exits the process.
@MainActor
func runSelfTest() -> Never {
    Task { @MainActor in
        let scratch = URL.temporaryDirectory.appending(path: "MetalCreator-self-test-\(UUID().uuidString)")
        let report = await SelfTest.run(kernel: makeKernel(), scratch: scratch)
        print(report.text)
        exit(report.passed ? 0 : 1)
    }
    while true {
        RunLoop.main.run()
    }
}

/// Writes `text` and a newline to standard error.
func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Prints why a launch step failed and exits 1, in place of the crash report an uncaught top-level error makes.
func fail(_ action: String, _ error: any Error) -> Never {
    printError("\(action): \(error.localizedDescription)")
    exit(1)
}

switch LaunchCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
case .run(let path):
    do {
        try runApp(opening: path)
    } catch {
        fail("MetalCreator couldn't start", error)
    }
case .version:
    print(AppBundleInfo.versionLine)
case .help:
    print(LaunchCommand.usage)
case .selfTest:
    runSelfTest()
case .smokeTest(let seconds):
    #if canImport(MetalUISDL)
    do {
        try runApp(opening: nil, smoke: LaunchSmoke(seconds: seconds))
    } catch {
        fail("MetalCreator couldn't start", error)
    }
    #else
    printError("--smoke-test needs the SDL backend (a Linux or Windows build).")
    exit(64)
    #endif
case .infoPlist(let minimum):
    do {
        FileHandle.standardOutput.write(try AppBundleInfo.infoPlistData(minimumSystemVersion: minimum))
    } catch {
        fail("The Info.plist couldn't be written", error)
    }
case .usageError(let message):
    printError(message + "\n" + LaunchCommand.usage)
    exit(64)
}
