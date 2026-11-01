import MetalUI
import Testing
@testable import CreatorApp

/// MetalUI XP-G34: the SDL file dialogs name a filter "<description> (*.ext)" from `ContentType.localizedDescription`, and show only the
/// extensions when there is none (never the identifier, which the 2026-10-30 Linux check saw as "com.metalcreator.mcgraph"). Every type
/// MetalCreator declares therefore carries a description.
struct ContentTypeDescriptionTests {
    @Test func everyDeclaredTypeIsDescribed() {
        let expected: [(ContentType, String)] = [
            (.mcgraph, "MetalCreator graph"), (.mctheme, "MetalCreator theme"), (.step, "STEP model"), (.stl, "STL mesh"),
            (.threeMF, "3MF model"), (.png, "PNG image"), (.jpeg, "JPEG image"),
        ]
        for (type, description) in expected {
            #expect(type.localizedDescription == description, "\(type.identifier)")
        }
    }

    @Test func theExportFormatsAreDescribed() {
        for kind in ExportKind.allCases {
            #expect(ContentType.exported(kind).localizedDescription?.isEmpty == false, "\(kind)")
        }
    }
}
