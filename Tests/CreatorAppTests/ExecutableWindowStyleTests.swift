import Foundation
import Testing
@testable import CreatorApp

/// `main.swift` is an executable no test can import, so its one `windowStyle:` line is read from the source: the app
/// opens with the style the tests' window uses (`AppLayout.windowStyle`, hidden), and not the standard title bar.
struct ExecutableWindowStyleTests {
    @Test func theExecutableOpensItsWindowWithTheHiddenTitleBar() throws {
        let main = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/MetalCreatorApp/main.swift")
        let source = try String(contentsOf: main, encoding: .utf8)
        #expect(source.contains("windowStyle: AppLayout.windowStyle"))
    }
}
