import CreatorApp
import CreatorOCCT
import Foundation
import MetalUI

/// `swift run MetalCreatorApp [path.mcgraph]`: the app (spec §6.1, M6). It opens the window over the OCCT kernel,
/// installs the menu bar and the window's input hooks, and opens the file named on the command line, if any.
/// `app.run()` is called from synchronous top-level code, as MetalUI requires.
@MainActor
func runApp() throws {
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
    if let path = CommandLine.arguments.dropFirst().first {
        do {
            try model.open(URL(fileURLWithPath: path))
        } catch {
            model.alert = .problem(error)
        }
    }
    app.run()
}

try runApp()
