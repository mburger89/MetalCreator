import Foundation
import Testing
@testable import CreatorGraph

/// The node library's visibility is saved in the view state. It is an added optional key, which older readers
/// ignore, so it needed no format bump (CLAUDE.md: bump only for changes older readers can't decode). The version is 4
/// because sketcher S4 added `ConstantValue.sketch`, not because of this key.
struct ViewStateLibraryTests {
    @Test func theLibraryIsShownUnlessHidden() throws {
        #expect(ViewState().showsLibrary)
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"bottom"}"#.utf8))
        #expect(decoded.showsLibrary, "files from before the library show it")
    }

    @Test func aHiddenLibraryRoundTrips() throws {
        let state = ViewState(dock: .bottom, showsLibrary: false)
        #expect(try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func anOlderReaderStillDecodesTheViewState() throws {
        let data = try JSONEncoder().encode(ViewState(dock: .bottom, canvasZoom: 2, showsLibrary: false))
        let older = try JSONDecoder().decode(FormatThreeViewState.self, from: data)
        #expect(older.dock == .bottom)
        #expect(older.canvasZoom == 2)
        #expect(GraphFile.currentFormatVersion == 5, "S4's and groups' bumps only; the library's key added none")
    }
}
