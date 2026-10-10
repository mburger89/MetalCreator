import CreatorApp
import CreatorOCCT
import Foundation
import MetalUI

/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It loads the app's themes (the remembered
/// one and the person's own), opens the window over the OCCT kernel, installs the menu bar and the window's input
/// hooks, and opens the file named on the command line, if any.
/// `app.run()` is called from synchronous top-level code, as MetalUI requires.
@MainActor
func runApp(opening path: String?) throws {
    let app = try App()
    app.preferredColorScheme = .dark
    let model = AppModel(kernel: OCCTKernel(), themes: AppThemes.store())
    let themeEditor = ThemeEditorModel(themes: model.themes)
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model, themeEditor: themeEditor)
    let window = try app.openWindow(title: "MetalCreator", size: Size(width: Pixels(1440), height: Pixels(900)),
                                    minSize: Size(width: Pixels(1000), height: Pixels(640))) {
        // A window's root must be an Element, and a Component is a group, so it's wrapped.
        ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
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
    app.run()
}

/// `--self-test` (packaging): the checks run in a main-actor task, which the main run loop drains because this is
/// called from synchronous top-level code; the task exits the process.
@MainActor
func runSelfTest() -> Never {
    Task { @MainActor in
        let scratch = URL.temporaryDirectory.appending(path: "MetalCreator-self-test-\(UUID().uuidString)")
        let report = await SelfTest.run(kernel: OCCTKernel(), scratch: scratch)
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
