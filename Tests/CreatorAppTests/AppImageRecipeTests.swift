import Foundation
import Testing
@testable import CreatorApp

/// The Linux AppImage is packed by `scripts/package-appimage.sh` from the tarball's tree (plan xp-2, Task 7, user decision 2).
/// Building it needs the network and a Linux machine, so these tests hold the recipe's text: what AppRun runs, which tools are
/// fetched and how they are pinned, what the AppDir holds, and that nothing needs FUSE. That the result runs is
/// `scripts/linux-test.sh package` (a clean ubuntu:24.04, `--appimage-extract-and-run --self-test`); that a desktop shows its icon and
/// opens `.mcgraph` files is human check XP-19.
struct AppImageRecipeTests {
    @Test func appRunStartsTheBundledExecutableWithItsArgumentsAndSetsNoApplicationID() throws {
        let appRun = try Self.text("packaging/appimage/AppRun")
        #expect(appRun.hasPrefix("#!/bin/bash\n"))
        #expect(appRun.contains("\nexec \"$HERE/usr/metalcreator/\(AppBundleInfo.executableName)\" \"$@\"\n"))
        let code = appRun.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: "\n")
        #expect(!code.contains("SDL_APP_ID") && !code.contains("export ") && !code.contains("LD_LIBRARY_PATH"),
                "the app hands its id to MetalUI (gap XP-G13) and the executable's RUNPATH finds its libraries: no workaround here")
    }

    /// appimagetool and the runtime are third-party tools fetched while packaging: a version (never `latest` or `continuous`, which
    /// move) and a sha256 per architecture for each, checked before anything runs.
    @Test func theToolAndTheRuntimeArePinnedByVersionAndHash() throws {
        let script = try Self.text("scripts/package-appimage.sh")
        #expect(script.firstMatch(of: /\nAPPIMAGETOOL_VERSION=[0-9]+\.[0-9]+\.[0-9]+\n/) != nil)
        #expect(script.firstMatch(of: /\nRUNTIME_TAG=[0-9]{8}\n/) != nil)
        for name in ["APPIMAGETOOL_SHA256", "RUNTIME_SHA256"] {
            for arch in ["x86_64", "aarch64"] {
                let hash = try Regex("\n\(name)_\(arch)=[0-9a-f]{64}\n")
                #expect(script.firstMatch(of: hash) != nil, "\(name)_\(arch)")
            }
        }
        #expect(script.contains("releases/download/$APPIMAGETOOL_VERSION/appimagetool-$ARCH.AppImage"))
        #expect(script.contains("releases/download/$RUNTIME_TAG/runtime-$ARCH"))
        #expect(script.contains("sha256sum -c"), "every download is verified before it runs")
        #expect(!script.contains("/latest/") && !script.contains("/continuous/"))
    }

    @Test func theAppDirHoldsTheSharedEntryAndIconAtItsRootAndTheTarballsTreeUnderUsr() throws {
        let script = try Self.text("scripts/package-appimage.sh")
        #expect(script.contains("ID=\(AppBundleInfo.identifier)\n"))
        #expect(script.contains(#"cp "$ROOT/packaging/linux/$ID.desktop" "$ROOT/packaging/linux/$ID.png" "$APPDIR/""#),
                "the tarball's own entry and icon, not copies that can drift")
        #expect(script.contains(#"mv "$WORK/$NAME" "$APPDIR/usr/metalcreator""#), "AppRun execs usr/metalcreator/MetalCreator")
        #expect(script.contains(#"rm "$APPDIR/usr/metalcreator/install.sh""#), "an AppImage is not unpacked into a folder")
        let entry = try Self.text("packaging/linux/\(AppBundleInfo.identifier).desktop")
        #expect(entry.contains("\nIcon=\(AppBundleInfo.identifier)\n"), "an AppDir needs <Icon>.png at its root")
        #expect(entry.contains("\nExec=\(AppBundleInfo.executableName) %F\n"))
        #expect(entry.contains("\nMimeType=\(AppBundleInfo.mimeType);\n"))
    }

    /// CI has no FUSE, nor has the clean Ubuntu: appimagetool runs extracted, and so does the check of the result.
    @Test func nothingNeedsFUSE() throws {
        let script = try Self.text("scripts/package-appimage.sh")
        #expect(script.contains("--appimage-extract-and-run"), "appimagetool is itself an AppImage")
        let linuxTest = try Self.text("scripts/linux-test.sh")
        #expect(linuxTest.contains("--appimage-extract-and-run --self-test"))
        #expect(linuxTest.contains("test ! -e /dev/fuse"), "the clean Ubuntu has no FUSE, so passing there proves none is needed")
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(!workflow.contains("libfuse") && !workflow.contains("fuse3"))
    }

    /// A file of the repository as text, "\r\n" read as "\n" (see `DesktopEntryTests`).
    private static func text(_ path: String) throws -> String {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }
}
