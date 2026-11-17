import Foundation
import Testing
@testable import CreatorPCB

struct ModelPathResolverTests {
    private func vars(_ platform: KiCadPlatform, _ extra: [String: String] = [:]) -> KiCadPathVariables {
        .merged(environment: [:], settings: KiCadPathVariables(values: extra), platform: platform)
    }

    private func locate(_ path: String, _ platform: KiCadPlatform = .linux, _ extra: [String: String] = [:]) -> ModelLocation {
        ModelPathResolver.locate(path, boardFolder: "/b", variables: vars(platform, extra), platform: platform)
    }

    @Test func projectVariable() {
        #expect(locate("${KIPRJMOD}/3dmodels/sw.step") == .files(["/b/3dmodels/sw.step"]))
        #expect(locate("$(KIPRJMOD)/x.step") == .files(["/b/x.step"]))
    }

    @Test func relative() {
        #expect(locate("models/a.step") == .files(["/b/models/a.step"]))
    }

    @Test func vrmlGetsStepTwinsFirst() {
        #expect(locate("${KICAD8_3DMODEL_DIR}/Button_Switch_SMD.3dshapes/SW.wrl") == .files([
            "/usr/share/kicad/3dmodels/Button_Switch_SMD.3dshapes/SW.step",
            "/usr/share/kicad/3dmodels/Button_Switch_SMD.3dshapes/SW.stp",
            "/usr/share/kicad/3dmodels/Button_Switch_SMD.3dshapes/SW.wrl",
        ]))
    }

    @Test func macPathOnWindows() {
        let path = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels/A.3dshapes/a.step"
        var expected = [path]
        for version in (6...10).reversed() {
            expected.append("C:\\Program Files\\KiCad\\\(version).0\\share\\kicad\\3dmodels\\A.3dshapes\\a.step")
        }
        #expect(locate(path, .windows) == .files(expected))
    }

    @Test func windowsPathOnMac() {
        let path = "C:\\Program Files\\KiCad\\9.0\\share\\kicad\\3dmodels\\A.3dshapes\\a.step"
        #expect(locate(path, .macOS) == .files([
            path, "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels/A.3dshapes/a.step"
        ]))
    }

    @Test func embedded() {
        #expect(locate("kicad-embed://sw.step") == .embedded(name: "sw.step"))
    }

    @Test func unknownVariableStaysAsWritten() {
        #expect(locate("${NOPE}/a.step") == .files(["/b/${NOPE}/a.step"]))
    }

    @Test func settingsVariable() {
        #expect(locate("${MYLIB}/x.step", .linux, ["MYLIB": "/libs"]) == .files(["/libs/x.step"]))
    }

    @Test func trailingSeparatorOfBoardFolder() {
        #expect(ModelPathResolver.locate("x.step", boardFolder: "/b/", variables: vars(.linux), platform: .linux)
            == .files(["/b/x.step"]))
        #expect(ModelPathResolver.locate("${KIPRJMOD}/x.step", boardFolder: "/b/", variables: vars(.linux), platform: .linux)
            == .files(["/b/x.step"]))
    }

    @Test func dotSegmentsCollapse() {
        #expect(locate("./a/../models/./a.step") == .files(["/b/models/a.step"]))
        #expect(locate("../../../a.step") == .files(["/a.step"]))
        #expect(locate("..\\a.step") == .files(["/a.step"]))
    }

    @Test func backslashIsASeparatorOnUnix() {
        #expect(locate("models\\a.step") == .files(["/b/models/a.step"]))
        #expect(locate("models\\a.step", .macOS) == .files(["/b/models/a.step"]))
    }

    @Test func windowsBoardFolder() {
        let result = ModelPathResolver.locate("models/a.step", boardFolder: "C:\\b\\", variables: vars(.windows), platform: .windows)
        #expect(result == .files(["C:\\b\\models\\a.step"]))
        let up = ModelPathResolver.locate("../../../a.step", boardFolder: "C:\\b", variables: vars(.windows), platform: .windows)
        #expect(up == .files(["C:\\a.step"]))
    }

    @Test func windowsVariablesIgnoreCase() {
        #expect(locate("${mylib}/x.step", .windows, ["MYLIB": "C:\\libs"]) == .files(["C:\\libs/x.step"]))
        #expect(locate("${mylib}/x.step", .linux, ["MYLIB": "/libs"]) == .files(["/b/${mylib}/x.step"]))
    }

    @Test func wrzAndUppercaseWrlTwins() {
        #expect(locate("/m/a.wrz") == .files(["/m/a.step", "/m/a.stp", "/m/a.wrz"]))
        #expect(locate("/m/A.WRL") == .files(["/m/A.step", "/m/A.stp", "/m/A.WRL"]))
    }

    @Test func forwardSlashAndMixedCaseWindowsPrefix() {
        let path = "c:/program files/kicad/8.0/SHARE/kicad/3dmodels/A.3dshapes/a.step"
        let result = locate(path, .macOS)
        #expect(result == .files([
            path, "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels/A.3dshapes/a.step",
        ]))
    }

    @Test func linuxLibraryPathOnWindows() {
        let result = locate("/usr/share/kicad/3dmodels/A.3dshapes/a.step", .windows)
        guard case .files(let files) = result else { Issue.record("not files"); return }
        #expect(files.count == 6)
        #expect(files[1] == "C:\\Program Files\\KiCad\\10.0\\share\\kicad\\3dmodels\\A.3dshapes\\a.step")
        #expect(files[5].contains("\\6.0\\"))
    }

    @Test func otherAbsolutePathsAreNotJoined() {
        #expect(locate("D:\\x.step", .macOS) == .files(["D:\\x.step"]))
        #expect(locate("\\\\server\\share\\x.step", .macOS) == .files(["\\\\server\\share\\x.step"]))
    }

    @Test func unknownAndUnterminatedVariables() {
        #expect(locate("$(NOPE)/a.step") == .files(["/b/$(NOPE)/a.step"]))
        #expect(locate("${KICAD8_3DMODEL_DIR}/a.step", .linux, [:]) != .files([]))
        let bare = ModelPathResolver.locate("${KICAD8_3DMODEL_DIR}/a.step", boardFolder: "/b", variables: KiCadPathVariables(),
                                            platform: .windows)
        #expect(bare == .files(["/b/${KICAD8_3DMODEL_DIR}/a.step"]))
        let mac = ModelPathResolver.locate("${KICAD8_3DMODEL_DIR}/a.step", boardFolder: "/b", variables: KiCadPathVariables(),
                                           platform: .macOS)
        #expect(mac == .files(["/b/${KICAD8_3DMODEL_DIR}/a.step"]))
        #expect(locate("${abc/a.step") == .files(["/b/${abc/a.step"]))
    }

    @Test func uppercaseEmbedScheme() {
        #expect(locate("KICAD-EMBED://sw.step") == .embedded(name: "sw.step"))
    }
}
