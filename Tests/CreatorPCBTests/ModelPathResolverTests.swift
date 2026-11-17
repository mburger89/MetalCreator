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
}
