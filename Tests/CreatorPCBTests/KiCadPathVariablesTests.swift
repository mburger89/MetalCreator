import Foundation
import Testing
@testable import CreatorPCB

struct KiCadPathVariablesTests {
    @Test func parsesVars() {
        let json = #"{"environment":{"vars":{"MYLIB":"/libs","A":"b"}}}"#
        let parsed = KiCadPathVariables.parsingCommonSettings(Data(json.utf8))
        #expect(parsed.values == ["MYLIB": "/libs", "A": "b"])
    }

    @Test func nullAbsentAndJunkAreEmpty() {
        #expect(KiCadPathVariables.parsingCommonSettings(Data(#"{"environment":{"vars":null}}"#.utf8)).values.isEmpty)
        #expect(KiCadPathVariables.parsingCommonSettings(Data(#"{"environment":{}}"#.utf8)).values.isEmpty)
        #expect(KiCadPathVariables.parsingCommonSettings(Data("not json".utf8)).values.isEmpty)
        #expect(KiCadPathVariables.parsingCommonSettings(Data("[1]".utf8)).values.isEmpty)
    }

    @Test func precedence() {
        let settings = KiCadPathVariables(values: ["KICAD8_3DMODEL_DIR": "/s", "X": "s", "ONLY": "s"])
        let merged = KiCadPathVariables.merged(environment: ["X": "e"], settings: settings, platform: .linux)
        #expect(merged.values["X"] == "e")
        #expect(merged.values["KICAD8_3DMODEL_DIR"] == "/s")
        #expect(merged.values["ONLY"] == "s")
        #expect(merged.values["KICAD6_3DMODEL_DIR"] == "/usr/share/kicad/3dmodels")
        #expect(merged.values["KICAD10_3DMODEL_DIR"] == "/usr/share/kicad/3dmodels")
    }

    @Test func folders() {
        #expect(KiCadPlatform.windows.libraryFolder(version: 9) == "C:\\Program Files\\KiCad\\9.0\\share\\kicad\\3dmodels")
        #expect(KiCadPlatform.macOS.settingsFolder(version: "9.0", environment: [:], home: "/h") == "/h/Library/Preferences/kicad/9.0")
        #expect(KiCadPlatform.linux.settingsFolder(version: "9.0", environment: [:], home: "/h") == "/h/.config/kicad/9.0")
        let xdg = ["XDG_CONFIG_HOME": "/x"]
        #expect(KiCadPlatform.linux.settingsFolder(version: "9.0", environment: xdg, home: "/h") == "/x/kicad/9.0")
        let appData = ["APPDATA": "C:\\A"]
        #expect(KiCadPlatform.windows.settingsFolder(version: "9.0", environment: appData, home: "C:\\h") == "C:\\A\\kicad\\9.0")
    }

    @Test func environmentBeatsADefault() {
        let merged = KiCadPathVariables.merged(environment: ["KICAD9_3DMODEL_DIR": "/env"], settings: KiCadPathVariables(),
                                               platform: .macOS)
        #expect(merged.values["KICAD9_3DMODEL_DIR"] == "/env")
    }

    @Test func nonStringValuesAreDropped() {
        let json = #"{"environment":{"vars":{"A":"x","B":3,"C":null,"D":["y"]}}}"#
        #expect(KiCadPathVariables.parsingCommonSettings(Data(json.utf8)).values == ["A": "x"])
    }
}
