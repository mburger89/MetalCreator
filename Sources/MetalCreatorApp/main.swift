import CreatorApp
import CreatorOCCT
import Foundation
import MetalUI

/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It opens the window over the OCCT kernel,
/// installs the menu bar and the window's input hooks, and opens the file named on the command line, if any.
/// `app.run()` is called from synchronous top-level code, as MetalUI requires.
@MainActor
func runApp(opening path: String?) throws {
    let app = try App()
    app.preferredColorScheme = .dark
    let model = AppModel(kernel: OCCTKernel())
    let input = AppInput(model: model)
    AppCommands.install(on: app, model: model)
    let window = try app.openWindow(title: "MetalCreator", size: Size(width: Pixels(1440), height: Pixels(900)),
                                    minSize: Size(width: Pixels(1000), height: Pixels(640))) {
        // A window's root must be an Element, and a Component is a group, so it's wrapped.
        ZStack { AppRoot(model: model, input: input) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    input.install(on: window)
    model.filePicker = WindowFilePicker(window: window)
    if let path {
        do {
            try model.open(URL(fileURLWithPath: path))
        } catch {
            model.alert = .problem(error)
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

switch LaunchCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
case .run(let path):
    try runApp(opening: path)
case .version:
    print(AppBundleInfo.versionLine)
case .selfTest:
    runSelfTest()
case .infoPlist(let minimum):
    FileHandle.standardOutput.write(try AppBundleInfo.infoPlistData(minimumSystemVersion: minimum))
case .usageError(let message):
    printError(message + "\n" + LaunchCommand.usage)
    exit(64)
}
