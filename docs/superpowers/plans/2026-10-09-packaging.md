# MetalCreator Track D: Packaging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command, `scripts/package-app.sh`, builds a signed `dist/MetalCreator.app` that runs on this Mac with Homebrew off the dynamic loader's path — OCCT and its Homebrew dependencies bundled in `Contents/Frameworks`, MetalUI's shader bundle in `Contents/Resources`, `.mcgraph` declared as its document type — and proves it with `scripts/verify-app.sh`.

**Architecture:**
- **The app tells the script about itself.** `CreatorApp` gains `AppBundleInfo` (the version's one source and the `Info.plist` content, tested), `LaunchCommand` (the command line, tested) and `SelfTest` (OCCT modelling, STEP/STL export and MetalUI's shader compile, tested on OCCT and `FakeKernel`). `MetalCreatorApp/main.swift` dispatches on `LaunchCommand`: `--version`, `--self-test` and `--info-plist <minimum macOS>` print and exit without a window; anything else opens the window exactly as before.
- **Packaging is a post-build bash script** (bash 3.2, Xcode command-line tools only). It walks `otool -L` from the release binary, copies every non-system library (31 on this Mac), rewrites install names to `@rpath/<name>` with the executable's single rpath `@executable_path/../Frameworks`, copies the kegs' licences, writes `Info.plist` through `--info-plist`, signs inside-out (ad hoc, or `METALCREATOR_SIGN_IDENTITY` with the hardened runtime), verifies in a temporary folder, and only then moves the app into `dist/`.
- **Verification is a separate script** so it can be re-run on a moved copy: plist, `codesign --verify --deep --strict`, no Homebrew link or rpath in any Mach-O, `LSMinimumSystemVersion` covers every binary, and `--self-test` passes under `env -i` + `sandbox-exec` with `/opt/homebrew` and `/usr/local` unreadable while `DYLD_PRINT_LIBRARIES` shows nothing loaded from outside the bundle and the system.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, MetalUI (`../MetalUI`, by path, master `c62d6ba`), OpenCascade 7.9.3 (Homebrew), bash 3.2, `otool`, `install_name_tool`, `codesign`, `plutil`, `sandbox-exec`.

**Spec:** `docs/superpowers/specs/2026-10-09-packaging-design.md` (written in Task 1; the decisions below are its decisions), under the binding spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` — §3.1 (platform; Errata (M0–M1): `.macOS(.v26)`), §4.5 (`.mcgraph`), §5.2 and §11 (bundling OCCT deferred — this track), §9 (MetalUI gaps), and every Errata section. Also read `docs/metalui-gaps.md` (M6-d) and `../MetalUI/docs/packaging.md` (where MetalUI's resource bundle goes, `ShaderLibrary.candidateDirectories`).

**Verified against master `d48d757` (901 tests) and MetalUI master `c62d6ba`.** Every code block below was extracted from this file into a fresh copy of master (with `../MetalUI` a link to the real MetalUI checkout) and applied task by task, in order. After each task the whole package built with no new warnings (only the expected OCCT "built for newer version 27.0" linker notes and M4's existing `ContextMenuTests` capture warning), `swift test` passed, and `swiftlint lint --strict` reported zero violations. Cumulative test counts per task: 904, 907, 913, 914, 914 (master + 13). `scripts/package-app.sh` was run end to end (about 90 s, 68 s of it the cold release build): 31 libraries, LSMinimumSystemVersion 27.0, verify passed with dyld loading 613 images, all from the bundle or the system; the bundle, copied with `ditto` to a folder whose name has a space, verified again and its window stayed up for 6 s with Homebrew unreadable. After review (temporary folder for Step 7, awk reading `otool -l` to the end, versions compared as numbers so a minimum written `27` passes against `27.0`), the revised scripts were re-extracted into the same copy and re-run: build, 914 tests, zero lint violations, package end to end, and Steps 7–9 with the outputs given there; the old verifier fails the `27` case, the new one passes it.

**Prerequisites:**
- Master at `d48d757` or later; `../MetalUI` at `c62d6ba` or later (C7 merged). The working tree is clean.
- Homebrew's `opencascade` 7.9 (it pulls in `tbb`, `freetype`, `libpng`), Xcode command-line tools, SwiftLint.

**Files shared with other tracks** (editor-polish, sketcher-s4, viewport-input run in parallel; keep edits to these minimal and at the places named, so merges are mechanical):
- `Sources/MetalCreatorApp/main.swift` — replaced whole in Task 3 (the window code is unchanged, moved into `runApp(opening:)`). If another track changes `runApp`, merge by hand: their body, this file's `switch`.
- `CLAUDE.md` — three insertions (Task 5): one sentence after the M6 status line, three lines after the `MetalCreatorApp` module paragraph, three lines in Commands after `CreatorStyleTests`.
- `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` — one new section appended at the end of each (Task 5). If another track also appends, keep both sections.
- `.gitignore` — two lines appended (Task 4).
- `docs/superpowers/roadmap.md` — the one "Packaging" row replaced (Task 5).
- Not touched: `Package.swift` (nothing in it changes; its MetalUI path stays) and every other track's sources.

## Decisions made in this plan

1. **A script, not an Xcode project or SwiftPM plugin; no third-party tools** (user decision). `Package.swift` stays the one build description and is not edited: the `/opt/homebrew` rpath its linker flags embed is deleted by the script.
2. **The version's one source is `AppBundleInfo`** (`com.metalcreator.MetalCreator`, version `0.1.0`, build `1`). The bundle's `Info.plist` is generated by the binary (`--info-plist`), so `swift test` pins its keys.
3. **Headless flags** (`LaunchCommand`): `--version`, `--self-test` (exit 0 or 1), `--info-plist <version>`; an unknown `--flag` prints the usage and exits 64; any other `-…` argument is the system's (`-psn_…`, `-NSSomeDefault value`) and opens an empty window; any other first argument is still the file to open (M6-d's stopgap).
4. **`--self-test` exercises what a missing library breaks**: a 10 mm cube on OCCT (volume, mesh), STEP and STL export, and MetalUI's shader bundle found and compiled (`ShaderLibrary.make`). It runs in a main-actor `Task` drained by `RunLoop.main` from synchronous top-level code, keeping MetalUI's rule that `app.run()` is called from synchronous `main.swift` code.
5. **`LSMinimumSystemVersion` is the newest `minos` among the bundled binaries: 27.0 today**, because Homebrew's bottles are built for macOS 27 while `Package.swift` says 26 (the script prints a note). A plist claiming 26 would launch into a dyld failure on macOS 26.
6. **Ad hoc by default; `METALCREATOR_SIGN_IDENTITY` adds the hardened runtime and a timestamp** (user decision). Ad hoc never turns the hardened runtime on: library validation then refuses the ad-hoc libraries (measured: "different Team IDs"). No entitlements are needed.
7. **No notarization** (user decision): the manual `notarytool`/`stapler` steps are in `docs/packaging.md`, marked unverified.
8. **`.mcgraph` is declared now** (document type: Editor, Owner; exported UTI `com.metalcreator.mcgraph` conforming to `public.json`), ready for MetalUI C8's open-document events (gap M6-d). Until then a double-click launches the app without opening the file (human check P2).
9. **No icon** (`CFBundleIconFile` omitted; the generic icon shows). MetalUI's `docs/packaging.md` has the `.icns` recipe for later.
10. **Artefacts in `dist/`** (git-ignored; `METALCREATOR_DIST_DIR` overrides). The app is assembled and verified in a temporary folder and replaces `dist/MetalCreator.app` only when it passes.
11. **Licences travel with the libraries** (`Contents/Resources/Licenses/<formula>/`); a keg without a licence file stops the script. The stb_image notice for code MetalUI compiles into the binary is MetalUI's to list: new gap **P-a**.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- `@Observable` classes are `@MainActor` (this plan adds none). Behaviour lives in `CreatorApp` types; `main.swift` only dispatches.
- One type per Swift file, named after the type. Avoid force unwraps and force `try`. No GCD (`DispatchQueue`, `dispatchMain`). Numbers shown with `FormatStyle`. Swift-native APIs (`URL.temporaryDirectory`, `appending(path:)`, `URL(filePath:)`).
- Only `CreatorOCCT` touches OCCT; `CreatorApp` reaches it through `any Kernel`. `main.swift` keeps calling `app.run()` from synchronous top-level code.
- **Do not edit `Package.swift`**, and never its MetalUI path. Do not touch other tracks' code.
- No third-party tools: the scripts use bash 3.2 (`/bin/bash`), the Xcode command-line tools and macOS's own utilities. Homebrew's `opencascade` is needed to build, never to run.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around.
- **SwiftLint gates every commit**: `swiftlint lint --strict` must report zero violations.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected noise: OCCT dylib "built for newer version 27.0" linker warnings, and M4's `'underPointer' mutated after capture by sendable closure` warning in `ContextMenuTests`.

## Review Focus

1. **The app (or the verifier's argument) somewhere else** — moved with `ditto`, a folder name with a space, a relative path given to `verify-app.sh`: it still verifies and launches. (Replay found the relative-path case failing — dyld reports absolute, symlink-free paths — so `verify-app.sh` resolves its argument with `pwd -P`.) Pinned by Task 4 Step 7.
2. **LaunchServices' or Xcode's own launch arguments** (`-psn_0_…`, `-NSDocumentRevisionsDebugMode YES`, `-AppleLanguages (de)`): the app opens its window, not a usage error and not a "file". Pinned by `LaunchCommandTests.theSystemsOwnArgumentsOpenAnEmptyWindow` (Task 3).
3. **The hardened runtime with an ad-hoc signature** (or libraries signed by another team): dyld refuses every bundled library. The script never combines them, and `verify-app.sh` catches it if someone does. Pinned by Task 4 Step 8 (re-sign a copy that way: verify fails, "different Team IDs").
4. **A plist that claims an older macOS than a bundled library needs**: the app would be offered to macOS 26 and die in dyld. `verify-app.sh` refuses it. Pinned by Task 4 Step 8 (set a copy's minimum to 26.0 and re-sign: verify fails naming the library; set it to `27` and re-sign: verify passes, since versions are compared as numbers, not strings).
5. **A run that fails half-way** (an unknown signing identity, a missing licence, a failed check): `dist/` keeps the previous good app rather than a half-signed one that macOS would kill on launch. Pinned by Task 4 Step 9.

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-10-09-packaging-design.md` | 1 | The design: goal, approach, decisions, out of scope, testing |
| `Sources/CreatorApp/AppBundleInfo.swift` | 1 | Name, bundle id, version, build; the `Info.plist` dictionary and its XML |
| `Tests/CreatorAppTests/AppBundleInfoTests.swift` | 1 | The plist's keys, the version line, the `.mcgraph` declarations |
| `Sources/CreatorApp/SelfTestResult.swift` | 2 | One check's outcome and its printed line |
| `Sources/CreatorApp/SelfTestReport.swift` | 2 | All outcomes, `passed`, the printed text |
| `Sources/CreatorApp/SelfTest.swift` | 2 | The checks: kernel, STEP, STL, shaders |
| `Tests/CreatorAppTests/SelfTestTests.swift` | 2 | OCCT passes and cleans up; failures are worded |
| `Sources/CreatorApp/LaunchCommand.swift` | 3 | The command line → what to do |
| `Sources/MetalCreatorApp/main.swift` | 3 | Dispatch: window, or a headless flag |
| `Tests/CreatorAppTests/LaunchCommandTests.swift` | 3 | Every flag, usage errors, the system's arguments |
| `scripts/package-app.sh` | 4 | Build, assemble, bundle libraries and licences, plist, sign, verify, move to `dist/` |
| `scripts/verify-app.sh` | 4 | Check a finished bundle |
| `Tests/CreatorAppTests/PackagingScriptTests.swift` | 4 | Both scripts are executable and parse |
| `.gitignore` | 4 | `/dist` |
| `docs/packaging.md` | 4 | How to build, check, sign with a Developer ID and notarize by hand |
| `CLAUDE.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, the binding spec, `docs/superpowers/roadmap.md` | 5 | Commands and state, gap P-a, group P, Errata (Packaging), the roadmap row |

---

### Task 1: The design doc and the version's one source

**Files:**
- Create: `docs/superpowers/specs/2026-10-09-packaging-design.md`
- Create: `Sources/CreatorApp/AppBundleInfo.swift`
- Test: `Tests/CreatorAppTests/AppBundleInfoTests.swift`

**Interfaces:**
- Consumes: `ContentType.mcgraph` (`Sources/CreatorApp/ContentType+MetalCreator.swift`: identifier `com.metalcreator.mcgraph`, conforming to `.json`, extension `mcgraph`); MetalUI's `ContentType.json`, `identifier`, `conformance`, `preferredFilenameExtension`.
- Produces: `public enum AppBundleInfo` with `static let name = "MetalCreator"`, `identifier = "com.metalcreator.MetalCreator"`, `executableName = "MetalCreator"`, `version = "0.1.0"`, `build = "1"`, `documentTypeName = "MetalCreator Graph"`; `static var versionLine: String` (`"MetalCreator 0.1.0 (1)"`); `static func infoPlist(minimumSystemVersion: String) -> [String: Any]`; `static func infoPlistData(minimumSystemVersion: String) throws -> Data` (XML).

- [ ] **Step 1: Check the starting point**

Run: `git log --oneline -1 && git -C ../MetalUI log --oneline -1 && git status --short && ls scripts dist 2>&1 | head -2`
Expected: master `d48d757` (or later), MetalUI `c62d6ba` (or later), a clean tree, and `scripts`/`dist` don't exist. If master moved, rerun `swift test` and use its total in place of 901 below.

- [ ] **Step 2: Write the design doc**

**File:** `docs/superpowers/specs/2026-10-09-packaging-design.md`

````markdown
# MetalCreator — Packaging Design (Track D)

**Date:** 2026-10-09. **Status:** approved for planning. **Binding spec:** `2026-10-07-metalcreator-vertical-slice-design.md`
(§5.2 and §11 deferred "Bundling OCCT into a signed, distributable `.app`"; this document takes that item on).
**Plan:** `docs/superpowers/plans/2026-10-09-packaging.md`.

## Goal

One command builds `dist/MetalCreator.app`: a release build of the app that runs on this Mac with Homebrew off the
dynamic loader's path, signed, with `.mcgraph` registered as its document type, and checked by a script before
anyone opens it. The app's code doesn't change, apart from three headless flags the script needs.

## Approach

`scripts/package-app.sh` (bash 3.2, Xcode command-line tools only):

1. `swift build -c release --product MetalCreatorApp`, then `--show-bin-path` for the products directory (Swift 6.4's
   default build system writes `.build/out/Products/Release`; the script never hard-codes it).
2. Lay out `MetalCreator.app/Contents/{MacOS,Frameworks,Resources}`. The binary is copied as `MacOS/MetalCreator`;
   every SwiftPM resource bundle in the products directory (today only MetalUI's `MetalUI_MetalUIRender.bundle`, the
   shader sources) goes into `Resources`, where MetalUI's `ShaderLibrary.candidateDirectories` looks first in an app.
3. Walk `otool -L` from the binary. Every library outside `/usr/lib` and `/System` is copied (the real file, not
   Homebrew's symlink) into `Frameworks` under its install name's file name, and walked in turn; `@rpath`,
   `@loader_path` and `@executable_path` names are resolved against the original file's location. On this Mac that is
   31 libraries: OCCT's 19 linked toolkits plus the 8 that its STEP toolkit pulls in (`TKXCAF`, `TKVCAF`, `TKCAF`,
   `TKLCAF`, `TKCDF`, `TKV3d`, `TKService`, `TKHLR` — the visualisation and document frameworks), TBB (`libtbb`,
   `libtbbmalloc`), FreeType and libpng.
4. `install_name_tool`: every bundled library's id becomes `@rpath/<name>`, every reference to a bundled library
   becomes `@rpath/<name>`, every `LC_RPATH` is deleted, and the executable gains the one rpath
   `@executable_path/../Frameworks`. `Package.swift` is unchanged; the `/opt/homebrew` rpath its linker flags embed is
   one of the rpaths deleted.
5. Copy each Homebrew keg's licence files into `Resources/Licenses/<formula>/`; a keg without one stops the script.
6. Write `Info.plist` by running the built binary: `MetalCreatorApp --info-plist <minimum macOS>`.
7. Sign inside-out: each library in `Frameworks`, then the app.
8. Run `scripts/verify-app.sh` on it, and only then move it to `dist/MetalCreator.app`. The app is assembled in a
   temporary folder, so a failed run (a missing licence, an unknown signing identity, a failed check) leaves the
   previous app in `dist/` untouched.

`scripts/verify-app.sh [app]` checks a finished bundle, so it can be run again on a moved copy: the plist lints and
names an executable that exists; `codesign --verify --deep --strict` passes; no Mach-O file in the bundle links or
searches `/opt/homebrew` or `/usr/local`, and every `@rpath` library it links is in `Frameworks`;
`LSMinimumSystemVersion` is no older than any bundled binary's `minos`; and `MetalCreator --self-test` passes with
an empty environment (`env -i`, so no `DYLD_*` variable) under `sandbox-exec` with a profile that denies every read of
`/opt/homebrew` and `/usr/local` — the script first proves the profile bites (`ls /opt/homebrew` must fail) — while
`DYLD_PRINT_LIBRARIES` shows that every image dyld loaded came from the bundle or the system.

## Decisions

1. **A script, not an Xcode project or a SwiftPM plugin.** The package stays the single build description; packaging
   is a post-build step. No tool beyond the Xcode command-line tools (`otool`, `install_name_tool`, `codesign`,
   `plutil`) and macOS's own `sandbox-exec`, `find`, `awk` (user decision: no third-party tools).
2. **The version has one source: `AppBundleInfo` in `CreatorApp`** (name, bundle identifier
   `com.metalcreator.MetalCreator`, version `0.1.0`, build `1`, the document type's name). The bundle's `Info.plist`
   is generated from it by the binary (`--info-plist`), never written by hand, so `swift test` pins its content.
3. **Three headless flags, parsed by `LaunchCommand` (tested):** `--version`, `--self-test` (exit 0 or 1) and
   `--info-plist <version>`; an unknown `--flag` prints the usage and exits 64. Anything else starting with `-` is the
   system's (`-psn_…`, `-NSSomeDefault value`) and opens an empty window, as before; any other first argument is still
   the file to open (gap M6-d's stopgap).
4. **`--self-test` runs the code paths a missing library would break**, without a window: a 10 mm cube on OCCT
   (volume and mesh), STEP and STL export into a temporary folder (OCCT's data-exchange toolkits; they need none of
   OCCT's resource files — measured with Homebrew unreadable), and MetalUI's shader bundle found and compiled on the
   Metal device (`ShaderLibrary.make`, what `App()` does). It runs from synchronous top-level code in a main-actor task
   drained by `RunLoop.main`, so `main.swift` keeps MetalUI's rule that `app.run()` is called from synchronous code.
5. **`LSMinimumSystemVersion` is the newest `minos` among the bundled binaries.** `Package.swift` says macOS 26, but
   Homebrew's bottles on this Mac are built for macOS 27, so the plist says 27.0 and the script prints a note. A
   plist claiming 26 would let macOS 26 launch the app into a dyld failure. Shipping to macOS 26 needs OCCT and its
   dependencies built with a macOS 26 deployment target, which is out of scope.
6. **Ad-hoc signing by default; a real identity through `METALCREATOR_SIGN_IDENTITY`** (user decision). With an
   identity, every library and the app are signed with the hardened runtime and a secure timestamp, as notarization
   requires. Ad hoc never turns the hardened runtime on: its library validation refuses ad-hoc libraries (measured:
   "mapping process and mapped file (non-platform) have different Team IDs"). No entitlements are needed: Metal
   compiles shaders from source without JIT, and OCCT needs none.
7. **No notarization** (user decision: it needs the user's Apple credentials). `docs/packaging.md` documents the
   manual `notarytool` and `stapler` steps; they are unverified here.
8. **`.mcgraph` is declared now**: a `CFBundleDocumentTypes` entry (role Editor, rank Owner) and an exported type
   declaration (`com.metalcreator.mcgraph`, conforming to `public.json`, extension `mcgraph`) — the identifier
   `ContentType.mcgraph` already uses. Finder then names the kind and opens the app on a double-click, but the file
   itself isn't opened until MetalUI delivers open-document events (gap M6-d, MetalUI C8).
9. **No app icon yet.** `CFBundleIconFile` is omitted and Finder shows the generic app icon. An icon is a design task
   of its own; MetalUI's `docs/packaging.md` has the `.icns` recipe for when one exists.
10. **The artefacts go to `dist/`** (`METALCREATOR_DIST_DIR` overrides it), which is git-ignored. Each run that
    passes replaces the app; one that fails leaves it alone.
11. **Licences travel with the libraries** (OCCT's LGPL 2.1 and its exception, TBB's Apache 2.0, FreeType's FTL,
    libpng's licence). The stb_image notice for code MetalUI compiles into the binary is MetalUI's to list (gap P-a).

## Out of scope

Notarization and stapling (manual, documented); a disk image or installer; an app icon; universal (x86_64) builds —
Homebrew's arm64 bottles are arm64 only; shipping to macOS 26 (decision 5); building OCCT from source; open-document
events (MetalUI C8).

## Testing

`swift test`: `AppBundleInfoTests` (the plist's keys, the version line, the `.mcgraph` type against
`ContentType.mcgraph`), `LaunchCommandTests` (every flag, usage errors, the system's own arguments), `SelfTestTests`
(all checks pass on OCCT and the scratch folder is removed; failures are worded and fail the run) and
`PackagingScriptTests` (both scripts are executable and parse with `bash -n`). The packaged bundle is checked by
`scripts/verify-app.sh`, and a person runs human-check group P (Finder launch, a moved copy, the document type,
optionally a Developer ID build).
````

- [ ] **Step 3: Write the failing test**

**File:** `Tests/CreatorAppTests/AppBundleInfoTests.swift`

```swift
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// The packaged app's `Info.plist` (packaging): the version's one source, and the `.mcgraph` type it declares.
struct AppBundleInfoTests {
    @Test func theVersionLineNamesTheMarketingVersionAndTheBuild() {
        #expect(AppBundleInfo.version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
        #expect(AppBundleInfo.build.wholeMatch(of: /\d+/) != nil)
        #expect(AppBundleInfo.versionLine == "MetalCreator \(AppBundleInfo.version) (\(AppBundleInfo.build))")
    }

    @Test func thePlistNamesTheBundleItsVersionAndTheMinimumMacOS() throws {
        let plist = try roundTripped(minimumSystemVersion: "27.0")
        #expect(plist["CFBundleExecutable"] as? String == "MetalCreator")
        #expect(plist["CFBundleIdentifier"] as? String == "com.metalcreator.MetalCreator")
        #expect(plist["CFBundleName"] as? String == "MetalCreator")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["CFBundleShortVersionString"] as? String == AppBundleInfo.version)
        #expect(plist["CFBundleVersion"] as? String == AppBundleInfo.build)
        #expect(plist["LSMinimumSystemVersion"] as? String == "27.0")
        #expect(plist["NSHighResolutionCapable"] as? Bool == true)
    }

    /// Ready for open-document events (gap M6-d): Finder knows `.mcgraph` files are this app's, under the identifier
    /// the file panels already use.
    @Test func itOwnsAndExportsTheMcgraphType() throws {
        let plist = try roundTripped(minimumSystemVersion: "26.0")
        let documentTypes = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(documentTypes.count == 1)
        #expect(documentTypes.first?["LSItemContentTypes"] as? [String] == [ContentType.mcgraph.identifier])
        #expect(documentTypes.first?["CFBundleTypeRole"] as? String == "Editor")
        #expect(documentTypes.first?["LSHandlerRank"] as? String == "Owner")

        let exported = try #require((plist["UTExportedTypeDeclarations"] as? [[String: Any]])?.first)
        #expect(exported["UTTypeIdentifier"] as? String == ContentType.mcgraph.identifier)
        #expect(exported["UTTypeConformsTo"] as? [String] == [ContentType.json.identifier])
        #expect(ContentType.mcgraph.conformance.contains(ContentType.json.identifier))
        let tags = try #require(exported["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == ["mcgraph"])
        #expect(ContentType.mcgraph.preferredFilenameExtension == "mcgraph")
    }

    private func roundTripped(minimumSystemVersion: String) throws -> [String: Any] {
        let data = try AppBundleInfo.infoPlistData(minimumSystemVersion: minimumSystemVersion)
        #expect(String(bytes: data, encoding: .utf8)?.hasPrefix("<?xml") == true)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
```

- [ ] **Step 4: Run it to see it fail**

Run: `swift test --filter AppBundleInfoTests 2>&1 | grep -E "error:" | head -3`
Expected: compile errors, `cannot find 'AppBundleInfo' in scope`.

- [ ] **Step 5: Write `AppBundleInfo`**

**File:** `Sources/CreatorApp/AppBundleInfo.swift`

```swift
import Foundation
import MetalUI

/// What the packaged `MetalCreator.app` says about itself (docs/superpowers/specs/2026-10-09-packaging-design.md):
/// its name, bundle identifier, version and the `.mcgraph` document type. This is the version's one source:
/// `scripts/package-app.sh` writes the bundle's `Info.plist` with `MetalCreator --info-plist <minimum macOS>`, so the
/// plist is never edited by hand.
public enum AppBundleInfo {
    /// The bundle's name, `CFBundleName`, and the `.app`'s file name.
    public static let name = "MetalCreator"
    /// `CFBundleIdentifier`, in the reverse-DNS domain of the `.mcgraph` type (`ContentType.mcgraph`).
    public static let identifier = "com.metalcreator.MetalCreator"
    /// The executable's name in `Contents/MacOS`, `CFBundleExecutable`.
    public static let executableName = "MetalCreator"
    /// The marketing version, `CFBundleShortVersionString`.
    public static let version = "0.1.0"
    /// The build number, `CFBundleVersion`: raise it for every packaged build that is handed to someone.
    public static let build = "1"
    /// How Finder names a `.mcgraph` file's kind.
    public static let documentTypeName = "MetalCreator Graph"

    /// What `--version` prints, e.g. `MetalCreator 0.1.0 (1)`.
    public static var versionLine: String { "\(name) \(version) (\(build))" }

    /// The bundle's `Info.plist`. `minimumSystemVersion` is `LSMinimumSystemVersion`: the packaging script passes the
    /// newest minimum among the binaries it bundles, which is Package.swift's unless a bundled library needs newer.
    public static func infoPlist(minimumSystemVersion: String) -> [String: Any] {
        let document = ContentType.mcgraph
        return [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": name,
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "LSApplicationCategoryType": "public.app-category.graphics-design",
            "LSMinimumSystemVersion": minimumSystemVersion,
            "NSHighResolutionCapable": true,
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeName": documentTypeName,
                    "CFBundleTypeRole": "Editor",
                    "LSHandlerRank": "Owner",
                    "LSItemContentTypes": [document.identifier],
                ] as [String: Any],
            ],
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeIdentifier": document.identifier,
                    "UTTypeDescription": documentTypeName,
                    "UTTypeConformsTo": [ContentType.json.identifier],
                    "UTTypeTagSpecification": ["public.filename-extension": [document.preferredFilenameExtension ?? "mcgraph"]],
                ] as [String: Any],
            ],
        ]
    }

    /// ``infoPlist(minimumSystemVersion:)`` as an XML property list, as `Info.plist` is written.
    public static func infoPlistData(minimumSystemVersion: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: infoPlist(minimumSystemVersion: minimumSystemVersion),
                                           format: .xml, options: 0)
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter AppBundleInfoTests 2>&1 | grep -E "Test run|✘"`
Expected: `Test run with 3 tests in 1 suite passed`.

Run: `swift test 2>&1 | grep -E "Test run with" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc`
Expected: `904` (master + 3), and no `✘` in the full output.

- [ ] **Step 7: Lint and commit**

Run: `swiftlint lint --strict --quiet` — Expected: no output.

```bash
git add docs/superpowers/specs/2026-10-09-packaging-design.md Sources/CreatorApp/AppBundleInfo.swift Tests/CreatorAppTests/AppBundleInfoTests.swift
git commit -m "feat(app): AppBundleInfo, the packaged app's version and Info.plist; packaging design"
```

---

### Task 2: The self-test

**Files:**
- Create: `Sources/CreatorApp/SelfTestResult.swift`
- Create: `Sources/CreatorApp/SelfTestReport.swift`
- Create: `Sources/CreatorApp/SelfTest.swift`
- Test: `Tests/CreatorAppTests/SelfTestTests.swift`

**Interfaces:**
- Consumes: `AppBundleInfo.versionLine` (Task 1); `Kernel` (`extrude(_:distance:mode:tag:)`, `properties(of:)`, `tessellate(_:tolerance:)`, `export(_:format:to:)`), `KernelError.userMessage`, `ExportFormat.allCases` (`.step`, `.stl`), `NodeTag(node:item:)`, `NodeID()`, `Profile2D.rectangle(width:height:plane:)`, `Plane.xy`; MetalUI's `ShaderLibrary.make(device:)` (re-exported from `MetalUIRender`) and `AppError.noMetalDevice`.
- Produces: `public struct SelfTestResult: Equatable, Sendable` (`name: String`, `passed: Bool`, `detail: String`, `init(name:passed:detail:)`, `var line: String` — `"ok   name: detail"` / `"FAIL name: detail"`); `public struct SelfTestReport: Equatable, Sendable` (`results: [SelfTestResult]`, `init(results:)`, `var passed: Bool` — false when empty, `var text: String` — heading `"<versionLine> self-test"` then a line per result); `@MainActor public enum SelfTest` with `static func run(kernel: any Kernel, scratch: URL, compileShaders: @MainActor () throws -> Void = SelfTest.compileShaders) async -> SelfTestReport` (checks named `"kernel"`, `"STEP export"`, `"STL export"`, `"shaders"`, in that order; `scratch` created and removed) and `static func compileShaders() throws`.

- [ ] **Step 1: Write the failing test**

**File:** `Tests/CreatorAppTests/SelfTestTests.swift`

```swift
import CreatorKernel
import CreatorOCCT
import Foundation
import Testing
@testable import CreatorApp

/// `MetalCreator --self-test` (packaging): every check runs and is reported, a failure is worded, and the exports'
/// scratch folder is removed. The packaged run, with Homebrew unreadable, is `scripts/verify-app.sh`.
@MainActor
struct SelfTestTests {
    @Test func onOCCTEveryCheckPassesAndTheScratchFolderIsRemoved() async {
        let scratch = Self.scratch()
        let report = await SelfTest.run(kernel: OCCTKernel(), scratch: scratch)
        #expect(report.results.map(\.name) == ["kernel", "STEP export", "STL export", "shaders"])
        #expect(report.passed, "\(report.text)")
        #expect(report.results.first?.detail.hasPrefix("a 10 mm cube, 1000 mm³, meshed into ") == true)
        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }

    @Test func aFailingCheckIsReportedInWordsAndFailsTheRun() async {
        struct NoBundle: Error, CustomStringConvertible {
            var description: String { "no shader bundle" }
        }
        let report = await SelfTest.run(kernel: FakeKernel(), scratch: Self.scratch()) { throw NoBundle() }
        #expect(!report.passed)
        #expect(report.results == [
            SelfTestResult(name: "kernel", passed: true, detail: "a 10 mm cube, 1000 mm³, meshed into 12 triangles"),
            SelfTestResult(name: "STEP export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "STL export", passed: false, detail: "Export isn't supported by this kernel yet."),
            SelfTestResult(name: "shaders", passed: false, detail: "no shader bundle"),
        ])
        #expect(report.text == """
            MetalCreator \(AppBundleInfo.version) (\(AppBundleInfo.build)) self-test
            ok   kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles
            FAIL STEP export: Export isn't supported by this kernel yet.
            FAIL STL export: Export isn't supported by this kernel yet.
            FAIL shaders: no shader bundle
            """)
    }

    @Test func aReportWithNoChecksHasNotPassed() {
        #expect(!SelfTestReport(results: []).passed)
    }

    private static func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "SelfTestTests-\(UUID().uuidString)")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter SelfTestTests 2>&1 | grep -E "error:" | head -3`
Expected: compile errors, `cannot find 'SelfTest' in scope`.

- [ ] **Step 3: Write `SelfTestResult`**

**File:** `Sources/CreatorApp/SelfTestResult.swift`

```swift
/// One line of a ``SelfTestReport``: what was checked, and what it found or why it failed.
public struct SelfTestResult: Equatable, Sendable {
    public var name: String
    public var passed: Bool
    /// What a passed check found, or why a failed one failed.
    public var detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }

    /// `ok   kernel: …` or `FAIL STEP export: …`, as `--self-test` prints it.
    public var line: String { "\(passed ? "ok  " : "FAIL") \(name): \(detail)" }
}
```

- [ ] **Step 4: Write `SelfTestReport`**

**File:** `Sources/CreatorApp/SelfTestReport.swift`

```swift
/// What `MetalCreator --self-test` found: one ``SelfTestResult`` per check, in the order they ran.
public struct SelfTestReport: Equatable, Sendable {
    public var results: [SelfTestResult]

    public init(results: [SelfTestResult]) {
        self.results = results
    }

    /// Whether every check passed; the process exits 0 when it did and 1 otherwise.
    public var passed: Bool { !results.isEmpty && results.allSatisfy(\.passed) }

    /// The report as printed: a heading naming the version, then a line per check.
    public var text: String {
        (["\(AppBundleInfo.versionLine) self-test"] + results.map(\.line)).joined(separator: "\n")
    }
}
```

- [ ] **Step 5: Write `SelfTest`**

`check` runs each body and turns a thrown error into a failed result; the cube made by the kernel check is reused by the exports, which say "skipped" if there is none. `FakeKernel` meshes its box into 12 triangles and refuses export, which is what the second test pins.

**File:** `Sources/CreatorApp/SelfTest.swift`

```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Metal
import MetalUI

/// `MetalCreator --self-test` (docs/superpowers/specs/2026-10-09-packaging-design.md): proves, without opening a
/// window, that the app reaches everything it ships. The kernel check models, measures and meshes a cube on OCCT; the
/// exports write STEP and STL, which run OCCT's data-exchange libraries; the shader check finds MetalUI's shader
/// resource bundle and compiles it on the Metal device. The packaging script runs it on the finished `.app` with
/// Homebrew's directories unreadable.
@MainActor
public enum SelfTest {
    /// Runs every check in order. Exports are written into `scratch`, which is created and then removed.
    /// `compileShaders` is ``compileShaders()`` unless a test stands in for it.
    public static func run(kernel: any Kernel, scratch: URL,
                           compileShaders: @MainActor () throws -> Void = SelfTest.compileShaders) async -> SelfTestReport {
        var results: [SelfTestResult] = []
        var cube: Solid?
        results.append(await check("kernel") {
            let solid = try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10,
                                                 mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
            let volume = try await kernel.properties(of: solid).volume
            guard abs(volume - 1000) < 1e-6 else {
                throw Failure("a 10 mm cube measured \(volume.formatted()) mm³, not 1000 mm³.")
            }
            let triangles = try await kernel.tessellate(solid, tolerance: 0.1).indices.count / 3
            guard triangles > 0 else { throw Failure("the 10 mm cube meshed into no triangles.") }
            cube = solid
            return "a 10 mm cube, 1000 mm³, meshed into \(triangles) triangles"
        })
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            results.append(SelfTestResult(name: "scratch folder", passed: false, detail: describe(error)))
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        for format in ExportFormat.allCases {
            results.append(await check("\(format.rawValue.uppercased()) export") {
                guard let cube else { throw Failure("skipped: the kernel check made no cube.") }
                let url = scratch.appending(path: "self-test.\(format.rawValue)")
                try await kernel.export([cube], format: format, to: url)
                let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
                guard size > 0 else { throw Failure("the file is empty.") }
                return "\(size.formatted()) bytes"
            })
        }
        results.append(await check("shaders") {
            try compileShaders()
            return "MetalUI's shader bundle compiled"
        })
        return SelfTestReport(results: results)
    }

    /// Finds MetalUI's shader resource bundle and compiles it on the system's Metal device, as `App()` does.
    public static func compileShaders() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw AppError.noMetalDevice }
        _ = try ShaderLibrary.make(device: device)
    }

    private static func check(_ name: String, _ body: @MainActor () async throws -> String) async -> SelfTestResult {
        do {
            return SelfTestResult(name: name, passed: true, detail: try await body())
        } catch {
            return SelfTestResult(name: name, passed: false, detail: describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? KernelError)?.userMessage ?? String(describing: error)
    }

    /// A check's own failure, worded for the report.
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter SelfTestTests 2>&1 | grep -E "Test run|✘"`
Expected: `Test run with 3 tests in 1 suite passed` (the OCCT test also compiles MetalUI's shaders, found through the debug build directories).

Run: `swift test 2>&1 | grep -E "Test run with" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc`
Expected: `907` (master + 6).

- [ ] **Step 7: Lint and commit**

Run: `swiftlint lint --strict --quiet` — Expected: no output.

```bash
git add Sources/CreatorApp/SelfTest.swift Sources/CreatorApp/SelfTestReport.swift Sources/CreatorApp/SelfTestResult.swift Tests/CreatorAppTests/SelfTestTests.swift
git commit -m "feat(app): SelfTest, headless proof that OCCT, STEP/STL export and MetalUI's shaders load"
```

---

### Task 3: The command line

**Files:**
- Create: `Sources/CreatorApp/LaunchCommand.swift`
- Modify (replace whole): `Sources/MetalCreatorApp/main.swift`
- Test: `Tests/CreatorAppTests/LaunchCommandTests.swift`

**Interfaces:**
- Consumes: `AppBundleInfo.versionLine`, `AppBundleInfo.infoPlistData(minimumSystemVersion:)` (Task 1); `SelfTest.run(kernel:scratch:)`, `SelfTestReport.text`, `.passed` (Task 2); `OCCTKernel()`.
- Produces: `public enum LaunchCommand: Equatable, Sendable` — `.run(path: String?)`, `.version`, `.selfTest`, `.infoPlist(minimumSystemVersion: String)`, `.usageError(String)`; `init(arguments: [String])` (the arguments after the program name); `static let usage: String`. The executable's flags `--version`, `--self-test`, `--info-plist <version>` (Task 4's script calls the last two).

- [ ] **Step 1: Write the failing test**

**File:** `Tests/CreatorAppTests/LaunchCommandTests.swift`

```swift
import Testing
@testable import CreatorApp

/// The executable's command line (packaging): a file to open, or a headless flag the packaging script uses.
struct LaunchCommandTests {
    @Test func noArgumentsOpensAnEmptyWindowAndAPathOpensThatFile() {
        #expect(LaunchCommand(arguments: []) == .run(path: nil))
        #expect(LaunchCommand(arguments: ["bracket.mcgraph"]) == .run(path: "bracket.mcgraph"))
    }

    @Test func theHeadlessFlags() {
        #expect(LaunchCommand(arguments: ["--version"]) == .version)
        #expect(LaunchCommand(arguments: ["--self-test"]) == .selfTest)
        #expect(LaunchCommand(arguments: ["--info-plist", "27.0"]) == .infoPlist(minimumSystemVersion: "27.0"))
    }

    @Test(arguments: ["26", "26.0", "26.0.1"])
    func infoPlistTakesAMacOSVersion(_ version: String) {
        #expect(LaunchCommand(arguments: ["--info-plist", version]) == .infoPlist(minimumSystemVersion: version))
    }

    @Test(arguments: [["--info-plist"], ["--info-plist", "latest"], ["--info-plist", "26.0", "27.0"]])
    func infoPlistWithoutOneVersionIsAUsageError(_ arguments: [String]) {
        #expect(LaunchCommand(arguments: arguments) == .usageError("--info-plist takes one macOS version, like 26.0."))
    }

    @Test func anUnknownFlagOrAStrayValueIsAUsageError() {
        #expect(LaunchCommand(arguments: ["--open", "a.mcgraph"]) == .usageError("Unknown option --open."))
        #expect(LaunchCommand(arguments: ["--version", "2"]) == .usageError("--version takes no value."))
        #expect(LaunchCommand(arguments: ["--self-test", "now"]) == .usageError("--self-test takes no value."))
    }

    /// Review focus: LaunchServices and Xcode may pass their own arguments (`-psn_…`, `-NSSomeDefault value`); the
    /// app opens its window rather than refusing them or opening one as a file.
    @Test(arguments: [["-psn_0_1234567"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-AppleLanguages", "(de)"]])
    func theSystemsOwnArgumentsOpenAnEmptyWindow(_ arguments: [String]) {
        #expect(LaunchCommand(arguments: arguments) == .run(path: nil))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter LaunchCommandTests 2>&1 | grep -E "error:" | head -3`
Expected: compile errors, `cannot find 'LaunchCommand' in scope`.

- [ ] **Step 3: Write `LaunchCommand`**

**File:** `Sources/CreatorApp/LaunchCommand.swift`

```swift
/// What the `MetalCreator` executable was asked to do by its command line (arguments after the program's name).
/// Everything but ``run(path:)`` prints and exits without opening a window, so the packaging script and a terminal
/// can use the packaged binary headlessly.
public enum LaunchCommand: Equatable, Sendable {
    /// Open the window, and the `.mcgraph` file at `path` if one is named.
    case run(path: String?)
    /// `--version`: print ``AppBundleInfo/versionLine``.
    case version
    /// `--self-test`: run ``SelfTest`` and exit 0 when every check passes, 1 otherwise.
    case selfTest
    /// `--info-plist <minimum macOS>`: print the bundle's `Info.plist` (``AppBundleInfo``).
    case infoPlist(minimumSystemVersion: String)
    /// A flag this program doesn't take, or one missing its value: print the message and ``usage``, exit 64.
    case usageError(String)

    /// The flags, as `--help` would list them.
    public static let usage = """
        usage: MetalCreator [file.mcgraph]
               MetalCreator --version
               MetalCreator --self-test
               MetalCreator --info-plist <minimum macOS, e.g. 26.0>
        """

    public init(arguments: [String]) {
        guard let first = arguments.first else {
            self = .run(path: nil)
            return
        }
        switch first {
        case "--version":
            self = arguments.count == 1 ? .version : .usageError("--version takes no value.")
        case "--self-test":
            self = arguments.count == 1 ? .selfTest : .usageError("--self-test takes no value.")
        case "--info-plist":
            guard arguments.count == 2, let minimum = arguments.last, minimum.wholeMatch(of: /\d+(\.\d+){0,2}/) != nil else {
                self = .usageError("--info-plist takes one macOS version, like 26.0.")
                return
            }
            self = .infoPlist(minimumSystemVersion: minimum)
        default:
            if first.hasPrefix("--") {
                self = .usageError("Unknown option \(first).")
            } else {
                // Anything else starting with "-" is the system's (a `-psn_…` process serial number, or an
                // `-NSSomeDefault value` pair), not a file.
                self = .run(path: first.hasPrefix("-") ? nil : first)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter LaunchCommandTests 2>&1 | grep -E "Test run|✘"`
Expected: `Test run with 6 tests in 1 suite passed`.

- [ ] **Step 5: Dispatch on it in `main.swift`**

The window code is master's, moved unchanged into `runApp(opening:)`. `runSelfTest()` starts a main-actor task and runs the main run loop, which drains it because this is synchronous top-level code (MetalUI's `App.run()` rule, ruling `SV-H`); the task exits the process. Nothing here uses GCD.

**File:** `Sources/MetalCreatorApp/main.swift`

```swift
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
```

- [ ] **Step 6: Try the flags**

Run:
```bash
swift build --product MetalCreatorApp 2>&1 | grep -E "error|warning: " | grep -v "ld: warning"
BIN=$(swift build --show-bin-path)
"$BIN/MetalCreatorApp" --version
"$BIN/MetalCreatorApp" --self-test; echo "exit $?"
"$BIN/MetalCreatorApp" --info-plist 27.0 | plutil -lint -
"$BIN/MetalCreatorApp" --bogus; echo "exit $?"
```
Expected: no compiler output; `MetalCreator 0.1.0 (1)`; the self-test report —
```
MetalCreator 0.1.0 (1) self-test
ok   kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles
ok   STEP export: 15,435 bytes
ok   STL export: 3,052 bytes
ok   shaders: MetalUI's shader bundle compiled
exit 0
```
(byte counts may differ by OCCT version); `<stdin>: OK`; then `Unknown option --bogus.`, the usage, `exit 64`. `swift run MetalCreatorApp` with no argument still opens the window (close it).

- [ ] **Step 7: Run everything, lint and commit**

Run: `swift test 2>&1 | grep -E "Test run with" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc`
Expected: `913` (master + 12).

Run: `swiftlint lint --strict --quiet` — Expected: no output.

```bash
git add Sources/CreatorApp/LaunchCommand.swift Sources/MetalCreatorApp/main.swift Tests/CreatorAppTests/LaunchCommandTests.swift
git commit -m "feat(app): --version, --self-test and --info-plist for the packaging script"
```

---

### Task 4: The packaging and verification scripts

**Files:**
- Create: `scripts/package-app.sh` (executable)
- Create: `scripts/verify-app.sh` (executable)
- Create: `docs/packaging.md`
- Modify: `.gitignore` (append)
- Test: `Tests/CreatorAppTests/PackagingScriptTests.swift`

**Interfaces:**
- Consumes: the executable's `--info-plist <version>` and `--self-test` (Task 3); `AppBundleInfo.executableName` = `MetalCreator` (the script copies the binary under that name; `verify-app.sh` reads `CFBundleExecutable`).
- Produces: `scripts/package-app.sh` (env `METALCREATOR_SIGN_IDENTITY`, default `-`; `METALCREATOR_DIST_DIR`, default `<repo>/dist`) → `dist/MetalCreator.app`; `scripts/verify-app.sh [app]` (exit 0 when every check passes, else `verify-app: FAILED: <why>` and exit 1).

- [ ] **Step 1: Write the failing test**

**File:** `Tests/CreatorAppTests/PackagingScriptTests.swift`

```swift
import Foundation
import Testing

/// The packaging scripts parse and are executable. What they build is checked by running them: `scripts/verify-app.sh`
/// (which `scripts/package-app.sh` ends with) and human check P1.
struct PackagingScriptTests {
    @Test(arguments: ["package-app.sh", "verify-app.sh"])
    func theScriptParsesAndIsExecutable(_ name: String) throws {
        let script = Self.scripts.appending(path: name)
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = ["-n", script.path]
        try bash.run()
        bash.waitUntilExit()
        #expect(bash.terminationStatus == 0, "bash -n \(name)")
    }

    /// `<repo>/scripts`, found from this file (`Tests/CreatorAppTests/PackagingScriptTests.swift`).
    private static let scripts = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts")
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter PackagingScriptTests 2>&1 | grep -E "✘" | head -4`
Expected: both cases fail (`isExecutableFile` is false and `bash -n` exits 127: no such file).

- [ ] **Step 3: Write `scripts/verify-app.sh`**

**File:** `scripts/verify-app.sh`

```bash
#!/bin/bash
# Checks a packaged MetalCreator.app (scripts/package-app.sh runs it last; run it again on a copy you moved):
#   1. Info.plist is well formed and names the executable;
#   2. the signature verifies, deep and strict;
#   3. no Mach-O file in the bundle links or searches Homebrew (/opt/homebrew, /usr/local), and every @rpath library
#      it links is in Contents/Frameworks;
#   4. LSMinimumSystemVersion is no older than any bundled binary's minimum macOS;
#   5. `MetalCreator --self-test` passes with the environment emptied (no DYLD_* variables) and Homebrew's directories
#      unreadable (sandbox-exec), and dyld loads nothing from outside the bundle and the system.
# usage: scripts/verify-app.sh [path/to/MetalCreator.app]   (default: <repo>/dist/MetalCreator.app)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/MetalCreator.app}"
[ -d "$APP" ] || { printf 'verify-app: FAILED: no app at %s\n' "$APP" >&2; exit 1; }
# Absolute and without symlinks, as dyld reports the paths it loads.
APP="$(cd "$APP" && pwd -P)"
CONTENTS="$APP/Contents"
PLIST="$CONTENTS/Info.plist"
NO_HOMEBREW='(version 1) (allow default) (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local"))'

step() { printf '==> verify: %s\n' "$*"; }
fail() { printf 'verify-app: FAILED: %s\n' "$*" >&2; exit 1; }

# The minimum macOS a Mach-O file was built for (LC_BUILD_VERSION). awk reads to the end: an early exit could kill otool
# with SIGPIPE, which pipefail and set -e would turn into a silent stop.
minimum_os() { otool -l "$1" | awk '$1 == "cmd" { want = ($2 == "LC_BUILD_VERSION") } want && $1 == "minos" && !found { v = $2; found = 1 } END { print v }'; }
# A macOS version as one comparable number, so 27, 27.0 and 27.0.0 are equal.
version_number() { printf '%s\n' "$1" | awk -F. '{ printf "%d\n", $1 * 1000000 + $2 * 1000 + $3 }'; }

step "Info.plist"
plutil -lint "$PLIST" > /dev/null || fail "Info.plist is not a valid property list"
executable="$(plutil -extract CFBundleExecutable raw "$PLIST")"
[ -x "$CONTENTS/MacOS/$executable" ] || fail "CFBundleExecutable $executable is not in Contents/MacOS"

step "signature"
codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict rejects the bundle"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Signature|Authority|TeamIdentifier)=' | sed 's/^/    /'

step "links"
minimum="$(plutil -extract LSMinimumSystemVersion raw "$PLIST")"
count=0
while IFS= read -r -d '' file; do
    file -b "$file" | grep -q 'Mach-O' || continue
    count=$((count + 1))
    if otool -L "$file" | grep -E '/opt/homebrew|/usr/local' > /dev/null; then
        fail "$file links a Homebrew library: $(otool -L "$file" | grep -E '/opt/homebrew|/usr/local' | head -n 1)"
    fi
    if otool -l "$file" | grep -E '^ +path (/opt/homebrew|/usr/local)' > /dev/null; then
        fail "$file searches a Homebrew directory (LC_RPATH)"
    fi
    for name in $(otool -L "$file" | sed -n '2,$p' | awk '{ print $1 }' | grep '^@rpath/' || true); do
        [ -f "$CONTENTS/Frameworks/${name#@rpath/}" ] || fail "$file links $name, which is not in Contents/Frameworks"
    done
    needs="$(minimum_os "$file")"
    [ "$(version_number "$needs")" -le "$(version_number "$minimum")" ] \
        || fail "$file needs macOS $needs, newer than LSMinimumSystemVersion $minimum"
done < <(find "$CONTENTS" -type f -print0)
printf '    %s Mach-O files, none linking Homebrew; LSMinimumSystemVersion %s\n' "$count" "$minimum"

step "self-test without Homebrew"
if sandbox-exec -p "$NO_HOMEBREW" /bin/ls /opt/homebrew > /dev/null 2>&1; then
    fail "sandbox-exec did not block /opt/homebrew, so this check would prove nothing"
fi
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! env -i HOME="$HOME" PATH=/usr/bin:/bin sandbox-exec -p "$NO_HOMEBREW" \
    /usr/bin/env DYLD_PRINT_LIBRARIES=1 "$CONTENTS/MacOS/$executable" --self-test > "$log" 2>&1; then
    sed 's/^/    /' "$log" >&2
    fail "the self-test failed"
fi
grep -v '^dyld\[' "$log" | sed 's/^/    /'
loaded="$(grep -c '^dyld\[[0-9]*\]: <' "$log" || true)"
outside="$(grep '^dyld\[[0-9]*\]: <' "$log" | sed -E 's/^dyld\[[0-9]+\]: <[^>]*> //' \
    | grep -v -e "^$CONTENTS/" -e '^/usr/lib/' -e '^/System/' || true)"
[ -z "$outside" ] || fail "dyld loaded libraries from outside the bundle: $outside"
if [ "$loaded" -eq 0 ]; then
    printf '    (dyld printed no load list: the hardened runtime ignores DYLD_PRINT_LIBRARIES; the links check stands)\n'
else
    printf '    dyld loaded %s images, all from the bundle or the system\n' "$loaded"
fi
step "passed: $APP"
```

- [ ] **Step 4: Write `scripts/package-app.sh`, make both executable, ignore `dist/`**

**File:** `scripts/package-app.sh`

```bash
#!/bin/bash
# Builds dist/MetalCreator.app: a release build of MetalCreatorApp with the OpenCascade libraries it links (and theirs,
# from Homebrew) copied into Contents/Frameworks and re-pointed there, MetalUI's resource bundles in Contents/Resources,
# an Info.plist written by the app itself (`--info-plist`), signed inside-out, then checked by scripts/verify-app.sh.
# The app is assembled in a temporary folder and replaces dist/MetalCreator.app only once it has passed, so a failed
# run leaves the previous app alone.
# Design: docs/superpowers/specs/2026-10-09-packaging-design.md.
#
# usage: scripts/package-app.sh
#   METALCREATOR_SIGN_IDENTITY  codesign identity; "-" (the default) signs ad hoc. A "Developer ID Application: …"
#                               identity also turns on the hardened runtime and a secure timestamp.
#   METALCREATOR_DIST_DIR       where the .app is written (default: <repo>/dist).
# Needs only the Xcode command-line tools and Homebrew's opencascade (the build links it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
IDENTITY="${METALCREATOR_SIGN_IDENTITY:--}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/MetalCreator.app"
CONTENTS="$APP/Contents"
FRAMEWORKS="$CONTENTS/Frameworks"

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-app: %s\n' "$*" >&2; exit 1; }

# Dependencies the system provides; everything else is bundled.
is_system() { case "$1" in /usr/lib/*|/System/*) return 0 ;; *) return 1 ;; esac; }

# The install names a Mach-O file links, without its own id.
linked_libraries() {
    local own
    own="$(otool -D "$1" | sed -n '2p')"
    otool -L "$1" | sed -n '2,$p' | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//' \
        | while IFS= read -r name; do [ "$name" = "$own" ] || printf '%s\n' "$name"; done
}

# The LC_RPATH entries of a Mach-O file.
rpaths() { otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" { want = 1 } want && $1 == "path" { print $2; want = 0 }'; }

# The minimum macOS a Mach-O file was built for (LC_BUILD_VERSION). awk reads to the end: an early exit could kill otool
# with SIGPIPE, which pipefail and set -e would turn into a silent stop.
minimum_os() { otool -l "$1" | awk '$1 == "cmd" { want = ($2 == "LC_BUILD_VERSION") } want && $1 == "minos" && !found { v = $2; found = 1 } END { print v }'; }

# Resolves install name $1, linked by the file at original path $2, to a file on disk (Homebrew's, before copying).
resolve() {
    local name="$1" loader_dir candidate rpath
    loader_dir="$(dirname "$2")"
    case "$name" in
        @rpath/*)
            while IFS= read -r rpath; do
                rpath="${rpath/@loader_path/$loader_dir}"
                rpath="${rpath/@executable_path/$(dirname "$BINARY")}"
                candidate="$rpath/${name#@rpath/}"
                if [ -f "$candidate" ]; then printf '%s\n' "$candidate"; return; fi
            done < <(rpaths "$2"; [ "$2" = "$BINARY" ] || rpaths "$BINARY")
            ;;
        @loader_path/*) candidate="$loader_dir/${name#@loader_path/}"; [ -f "$candidate" ] && printf '%s\n' "$candidate" && return ;;
        @executable_path/*) candidate="$(dirname "$BINARY")/${name#@executable_path/}"; [ -f "$candidate" ] && printf '%s\n' "$candidate" && return ;;
        /*) [ -f "$name" ] && printf '%s\n' "$name" && return ;;
    esac
    fail "can't find $name, linked by $2"
}

step "Building MetalCreatorApp (release)"
swift build --package-path "$ROOT" -c release --product MetalCreatorApp
BIN_DIR="$(swift build --package-path "$ROOT" -c release --product MetalCreatorApp --show-bin-path)"
BINARY="$BIN_DIR/MetalCreatorApp"

step "Assembling MetalCreator.app"
mkdir -p "$CONTENTS/MacOS" "$FRAMEWORKS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/MetalCreator"
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then cp -R "$bundle" "$CONTENTS/Resources/"; fi
done

step "Copying the non-system libraries it links, transitively"
# $WORK/seen holds "<file name> <real path>" per bundled library; $WORK/queue the files still to scan.
: > "$WORK/seen"
printf '%s\n' "$BINARY" > "$WORK/queue"
while [ -s "$WORK/queue" ]; do
    file="$(head -n 1 "$WORK/queue")"
    sed -i '' '1d' "$WORK/queue"
    while IFS= read -r name; do
        is_system "$name" && continue
        library="$(basename "$name")"
        source="$(resolve "$name" "$file")"
        real="$(realpath "$source")"
        known="$(awk -v library="$library" '$1 == library { print $2 }' "$WORK/seen")"
        if [ -n "$known" ]; then
            [ "$known" = "$real" ] || fail "two different libraries are both named $library: $known and $real"
            continue
        fi
        printf '%s %s\n' "$library" "$real" >> "$WORK/seen"
        cp "$real" "$FRAMEWORKS/$library"
        chmod u+w "$FRAMEWORKS/$library"
        printf '%s\n' "$source" >> "$WORK/queue"
    done < <(linked_libraries "$file")
done
printf '    %s libraries\n' "$(wc -l < "$WORK/seen" | tr -d ' ')"

step "Copying their licences into Contents/Resources/Licenses"
# Each library comes from a Homebrew keg, <prefix>/Cellar/<formula>/<version>; its licence files sit at the keg's top
# level or in share/doc/<formula>.
for keg in $(awk '{ print $2 }' "$WORK/seen" | sed -nE 's#^(.*/Cellar/[^/]+/[^/]+)/.*#\1#p' | sort -u); do
    formula="$(basename "$(dirname "$keg")")"
    mkdir -p "$CONTENTS/Resources/Licenses/$formula"
    find "$keg" "$keg/share/doc/$formula" -maxdepth 1 -type f \
        \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname '*EXCEPTION*' \) \
        -exec cp {} "$CONTENTS/Resources/Licenses/$formula/" \; 2> /dev/null || true
    [ -n "$(ls -A "$CONTENTS/Resources/Licenses/$formula")" ] || fail "found no licence file for $formula in $keg"
    printf '    %s: %s\n' "$formula" "$(ls "$CONTENTS/Resources/Licenses/$formula" | tr '\n' ' ')"
done
[ "$(awk '{ print $2 }' "$WORK/seen" | grep -vc '/Cellar/' || true)" -eq 0 ] \
    || fail "a bundled library isn't from a Homebrew keg, so its licence is unknown: $(awk '{ print $2 }' "$WORK/seen" | grep -v '/Cellar/' | head -n 1)"

step "Pointing every link at Contents/Frameworks"
repoint() {
    local file="$1" name
    local args=()
    codesign --remove-signature "$file"
    while IFS= read -r name; do
        is_system "$name" || args+=(-change "$name" "@rpath/$(basename "$name")")
    done < <(linked_libraries "$file")
    while IFS= read -r name; do args+=(-delete_rpath "$name"); done < <(rpaths "$file")
    install_name_tool ${args[@]+"${args[@]}"} "${@:2}" "$file"
}
for library in "$FRAMEWORKS"/*.dylib; do
    repoint "$library" -id "@rpath/$(basename "$library")"
done
repoint "$CONTENTS/MacOS/MetalCreator" -add_rpath "@executable_path/../Frameworks"

step "Writing Info.plist"
minimum="$(for file in "$CONTENTS/MacOS/MetalCreator" "$FRAMEWORKS"/*.dylib; do minimum_os "$file"; done \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
declared="$(minimum_os "$CONTENTS/MacOS/MetalCreator")"
[ "$minimum" = "$declared" ] \
    || printf '    note: the bundled libraries need macOS %s; Package.swift asks for %s\n' "$minimum" "$declared"
"$BINARY" --info-plist "$minimum" > "$CONTENTS/Info.plist"

step "Signing ($([ "$IDENTITY" = "-" ] && echo "ad hoc" || echo "$IDENTITY"))"
sign_options=(--force --sign "$IDENTITY")
[ "$IDENTITY" = "-" ] || sign_options+=(--options runtime --timestamp)
for library in "$FRAMEWORKS"/*.dylib; do
    codesign "${sign_options[@]}" "$library"
done
codesign "${sign_options[@]}" "$APP"

"$ROOT/scripts/verify-app.sh" "$APP"

mkdir -p "$DIST"
rm -rf "$DIST/MetalCreator.app"
mv "$APP" "$DIST/MetalCreator.app"
step "Wrote $(cd "$DIST" && pwd -P)/MetalCreator.app"
```

Run: `chmod +x scripts/package-app.sh scripts/verify-app.sh`

**Append to:** `.gitignore` (after one blank line)

```text
# scripts/package-app.sh writes the packaged app here.
/dist
```

- [ ] **Step 5: Run the test**

Run: `swift test --filter PackagingScriptTests 2>&1 | grep -E "Test run|✘"`
Expected: `Test run with 1 test in 1 suite passed` (2 cases).

- [ ] **Step 6: Package the app**

Run: `scripts/package-app.sh 2>&1 | grep -v "ld: warning" | grep -v "^\["`
Expected (paths shortened):
```
==> Building MetalCreatorApp (release)
Building for production...
Build complete! (… sec)
==> Assembling MetalCreator.app
==> Copying the non-system libraries it links, transitively
    31 libraries
==> Copying their licences into Contents/Resources/Licenses
    freetype: LICENSE.TXT
    libpng: LICENSE
    opencascade: LICENSE_LGPL_21.txt OCCT_LGPL_EXCEPTION.txt
    tbb: LICENSE.txt
==> Pointing every link at Contents/Frameworks
==> Writing Info.plist
    note: the bundled libraries need macOS 27.0; Package.swift asks for 26.0
==> Signing (ad hoc)
==> verify: Info.plist
==> verify: signature
    Identifier=com.metalcreator.MetalCreator
    Signature=adhoc
    TeamIdentifier=not set
==> verify: links
    32 Mach-O files, none linking Homebrew; LSMinimumSystemVersion 27.0
==> verify: self-test without Homebrew
    MetalCreator 0.1.0 (1) self-test
    ok   kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles
    ok   STEP export: 15,435 bytes
    ok   STL export: 3,052 bytes
    ok   shaders: MetalUI's shader bundle compiled
    dyld loaded 613 images, all from the bundle or the system
==> verify: passed: /private/var/folders/…/MetalCreator.app
==> Wrote …/dist/MetalCreator.app
```
`git status --short` lists no `dist/` (ignored). As a control, the unpackaged build fails under the same sandbox:
`sandbox-exec -p '(version 1) (allow default) (deny file-read* (subpath "/opt/homebrew"))' "$(swift build -c release --product MetalCreatorApp --show-bin-path)/MetalCreatorApp" --version`
Expected: `dyld[…]: Library not loaded: /opt/homebrew/opt/opencascade/lib/libTKernel.7.9.dylib … (blocked by sandbox)`.

- [ ] **Step 7: Review focus 1 — a moved copy, a space, a relative path**

Run:
```bash
R="$PWD"; T="$(mktemp -d)/pkg check"; mkdir -p "$T"   # a folder with a space, outside every worktree
ditto dist/MetalCreator.app "$T/MetalCreator.app"
(cd "$(dirname "$T")" && "$R/scripts/verify-app.sh" "pkg check/MetalCreator.app" 2>&1 | tail -2)
(cd "$(dirname "$T")" && exec env -i HOME="$HOME" sandbox-exec -p '(version 1) (allow default) (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local"))' "pkg check/MetalCreator.app/Contents/MacOS/MetalCreator") & echo $! > "$T/pid"
perl -e "select(undef, undef, undef, 6)"   # wait 6 s
kill -0 "$(cat "$T/pid")" && echo "still running" && kill "$(cat "$T/pid")"
rm -rf "$(dirname "$T")"
```
Both the verifier and the launch are given the relative path `pkg check/MetalCreator.app`, from a subshell in the temporary folder.
Expected: `dyld loaded … images, all from the bundle or the system`, `==> verify: passed: /private/var/folders/…/pkg check/MetalCreator.app`, then a window opens briefly and `still running`.

- [ ] **Step 8: Review focus 3 and 4 — the verifier refuses a broken bundle**

Run:
```bash
T=$(mktemp -d); ditto dist/MetalCreator.app "$T/MetalCreator.app"
plutil -replace LSMinimumSystemVersion -string 26.0 "$T/MetalCreator.app/Contents/Info.plist"
codesign --force --sign - "$T/MetalCreator.app" 2> /dev/null
scripts/verify-app.sh "$T/MetalCreator.app" 2>&1 | tail -1
plutil -replace LSMinimumSystemVersion -string 27 "$T/MetalCreator.app/Contents/Info.plist"
codesign --force --sign - "$T/MetalCreator.app" 2> /dev/null
scripts/verify-app.sh "$T/MetalCreator.app" 2>&1 | tail -1; rm -rf "$T"
T=$(mktemp -d); ditto dist/MetalCreator.app "$T/MetalCreator.app"
for l in "$T"/MetalCreator.app/Contents/Frameworks/*.dylib; do codesign --force --sign - --options runtime "$l" 2> /dev/null; done
codesign --force --sign - --options runtime "$T/MetalCreator.app" 2> /dev/null
scripts/verify-app.sh "$T/MetalCreator.app" 2>&1 | grep -o "different Team IDs" | head -1; rm -rf "$T"
```
Expected: `verify-app: FAILED: …/Contents/Frameworks/lib….dylib needs macOS 27.0, newer than LSMinimumSystemVersion 26.0`, then `==> verify: passed: …` (a minimum written `27`, which `--info-plist` accepts, equals the binaries' `27.0`), then `different Team IDs` (the self-test's dyld failure under the hardened runtime).

- [ ] **Step 9: Review focus 5 — a failed run keeps the previous app**

Run:
```bash
METALCREATOR_SIGN_IDENTITY="No Such Identity" scripts/package-app.sh > /dev/null 2>&1; echo "exit $?"
scripts/verify-app.sh 2>&1 | tail -1
```
Expected: `exit 1` (codesign: `No Such Identity: no identity found`), then `==> verify: passed: …/dist/MetalCreator.app` — Step 6's app, untouched.

- [ ] **Step 10: Write `docs/packaging.md`**

**File:** `docs/packaging.md`

````markdown
# Packaging MetalCreator.app

How to build, check and (by hand) notarize the app. The design and its reasons:
`docs/superpowers/specs/2026-10-09-packaging-design.md`.

## Build

```sh
scripts/package-app.sh
```

writes `dist/MetalCreator.app` (about 50 MB), signed ad hoc, and ends by running `scripts/verify-app.sh` on it. It
needs the Xcode command-line tools and Homebrew's `opencascade` (the build links it; the app then carries its own
copy). `METALCREATOR_DIST_DIR=/some/folder` writes the app there instead. A run that passes replaces the app; one
that fails (for example an unknown signing identity) prints why and leaves the previous app alone.

An ad-hoc signature is enough to run the app on this Mac. A copy downloaded or AirDropped to another Mac is
quarantined, and Gatekeeper refuses an ad-hoc app: open it with Control-click ▸ Open, or allow it in System
Settings ▸ Privacy & Security.

## Check

```sh
scripts/verify-app.sh [path/to/MetalCreator.app]
```

re-checks a bundle, for example after moving it: the plist, the signature (`codesign --verify --deep --strict`), that
no binary in it links or searches `/opt/homebrew` or `/usr/local`, that `LSMinimumSystemVersion` covers every bundled
binary, and that `MetalCreator --self-test` passes with an empty environment and Homebrew's folders unreadable
(`sandbox-exec`). The bundled libraries come from Homebrew bottles built for macOS 27, so the app needs macOS 27 even
though `Package.swift` says 26; the script prints a note saying so.

The binary's headless flags also work on their own:

```sh
dist/MetalCreator.app/Contents/MacOS/MetalCreator --version     # MetalCreator 0.1.0 (1)
dist/MetalCreator.app/Contents/MacOS/MetalCreator --self-test   # OCCT, STEP/STL export, MetalUI's shaders
swift run MetalCreatorApp --self-test                           # the same checks, unpackaged
```

## The version

`AppBundleInfo` (`Sources/CreatorApp/AppBundleInfo.swift`) is the one source: `version` is the marketing version,
`build` the build number. Raise `build` for every build handed to someone. The bundle's `Info.plist` is generated from
it; never edit a packaged plist by hand (it would also break the signature).

## Signing with a Developer ID

```sh
security find-identity -v -p codesigning       # the identities in your keychain
METALCREATOR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-app.sh
```

signs every library and the app with that identity, the hardened runtime and a secure timestamp (needs the network).
Under the hardened runtime dyld ignores `DYLD_PRINT_LIBRARIES`, so `verify-app.sh` says it has no load list and relies
on its link check. **Unverified**: no Developer ID build was made while writing this.

## Notarizing (manual, unverified)

Notarization needs your Apple ID, so it isn't scripted. Once, store an app-specific password in the keychain:

```sh
xcrun notarytool store-credentials metalcreator --apple-id you@example.com --team-id TEAMID
```

Then, after a Developer ID build:

```sh
ditto -c -k --keepParent dist/MetalCreator.app dist/MetalCreator.zip
xcrun notarytool submit dist/MetalCreator.zip --keychain-profile metalcreator --wait
xcrun stapler staple dist/MetalCreator.app
spctl --assess --type execute --verbose dist/MetalCreator.app    # "accepted, source=Notarized Developer ID"
```

If the submission is rejected, `xcrun notarytool log <submission id> --keychain-profile metalcreator` says why.

## Not yet

No app icon (Finder shows the generic one), no disk image, arm64 only, and a double-clicked `.mcgraph` opens the app
without opening the file until MetalUI delivers open-document events (`docs/metalui-gaps.md` M6-d).
````

- [ ] **Step 11: Run everything, lint and commit**

Run: `swift test 2>&1 | grep -E "Test run with" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc`
Expected: `914` (master + 13).

Run: `swiftlint lint --strict --quiet` — Expected: no output.

```bash
git add scripts/package-app.sh scripts/verify-app.sh docs/packaging.md .gitignore Tests/CreatorAppTests/PackagingScriptTests.swift
git commit -m "feat(packaging): scripts/package-app.sh builds a signed MetalCreator.app with OCCT bundled; verify-app.sh proves it runs without Homebrew"
```

---

### Task 5: Record it — CLAUDE.md, the gap, human checks, Errata, roadmap

**Files:**
- Modify: `CLAUDE.md` (three insertions)
- Modify: `docs/metalui-gaps.md` (append)
- Modify: `docs/verification/human-checks.md` (append)
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (append)
- Modify: `docs/superpowers/roadmap.md` (one row)

**Interfaces:**
- Consumes: Tasks 1–4's names (`AppBundleInfo`, `LaunchCommand`, `SelfTest`, the two scripts, `docs/packaging.md`, the design doc).
- Produces: gap **P-a**, human-check group **P** (P1–P4), "Errata (Packaging)".

- [ ] **Step 1: CLAUDE.md — the project state**

**In `CLAUDE.md`, replace:**

```text
M6 (app shell) code is done; its human checks (group M6) are pending.
```

**with:**

```text
M6 (app shell) code is done; its human checks (group M6) are pending.
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
```

- [ ] **Step 2: CLAUDE.md — the app's module paragraph**

**In `CLAUDE.md`, replace:**

```text
  to every view with `.environment(model.themes)`.
```

**with:**

```text
  to every view with `.environment(model.themes)`. `LaunchCommand` parses its command line: a file to open, or the
  headless `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
  `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.
```

- [ ] **Step 3: CLAUDE.md — the commands**

**In `CLAUDE.md`, replace:**

```text
swift test --filter CreatorStyleTests      # colour themes: the built-ins, legibility, ThemeStore
```

**with:**

```text
swift test --filter CreatorStyleTests      # colour themes: the built-ins, legibility, ThemeStore
scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
```

- [ ] **Step 4: Log gap P-a**

**Append to:** `docs/metalui-gaps.md` (after one blank line)

````markdown
## Hit by packaging, 2026-10-09

Labelled P-a… so they don't clash with the C7 items, M4-a…, M5-a…, M6-a… or PERF-a….

- **P-a. No list of the third-party code a MetalUI app links.** A packaged app has to carry the notices of the code
  compiled into it. MetalCreator's release binary contains MetalUI's vendored stb_image (`CStbImage`, MIT or public
  domain; `nm` finds 92 `stbi_` symbols), and other products or traits could add FreeType, HarfBuzz, SheenBidi or
  libunibreak. Which vendored code each MetalUI product links on macOS isn't written down, so
  `scripts/package-app.sh` bundles the licences of the Homebrew libraries only. Wanted: in MetalUI's
  `docs/packaging.md`, or a `THIRD-PARTY-NOTICES` file, a list per platform and trait of the vendored code each
  product links and where its licence file is. Stopgap: none; the packaged app lacks the stb_image notice until then.
- **M6-d, now visible.** The packaged app declares `.mcgraph` (owner, exported type), so a double-click in Finder
  opens MetalCreator, but not the file: no open-document event reaches the app (human check P2).
````

- [ ] **Step 5: Human checks, group P**

**Append to:** `docs/verification/human-checks.md` (after one blank line)

````markdown
## Group P — the packaged app (packaging)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `scripts/package-app.sh` first; it ends with `==> Wrote …/dist/MetalCreator.app`. How-to: `docs/packaging.md`.

- [ ] **P1 Finder launch, moved.** Copy `dist/MetalCreator.app` to `~/Applications` in Finder and double-click it
  there. The window opens in Dracula, as with `swift run MetalCreatorApp`. Wire a Rectangle into an Extrude and the
  Extrude into an Output, then File ▸ Export STEP…: the file is written and opens in a STEP viewer
  (FreeCAD or any other; without one, `head -c 12` on it prints `ISO-10303-21`). In Activity Monitor,
  select MetalCreator ▸ ⓘ ▸ Open Files and Ports: no path starts with `/opt/homebrew`. Pinned headless:
  `scripts/verify-app.sh` (the self-test with Homebrew unreadable) and `SelfTestTests`. **Observed:**
- [ ] **P2 The document type.** Save a graph as `test.mcgraph` and choose File ▸ Get Info on it in Finder: Kind reads
  "MetalCreator Graph" and "Open with" names MetalCreator. Double-click it: MetalCreator comes to the front with an
  empty document, not the file (known: gap M6-d, MetalUI C8; use File ▸ Open…). Pinned:
  `AppBundleInfoTests.itOwnsAndExportsTheMcgraphType`. **Observed:**
- [ ] **P3 Another Mac (optional).** On a second Apple-silicon Mac with macOS 27 and no Homebrew, unzip a copy made
  with `ditto -c -k --keepParent dist/MetalCreator.app MetalCreator.zip`. Gatekeeper refuses the ad-hoc app at first;
  Control-click ▸ Open (or System Settings ▸ Privacy & Security ▸ Open Anyway) opens it, and P1's export works.
  **Observed:**
- [ ] **P4 Developer ID (optional, needs your identity).**
  `METALCREATOR_SIGN_IDENTITY="Developer ID Application: …" scripts/package-app.sh` passes; `codesign -dv
  dist/MetalCreator.app` shows your TeamIdentifier and `flags=0x10000(runtime)`, and the verify step says dyld printed
  no load list. Then notarize by hand (`docs/packaging.md`): `spctl --assess --type execute --verbose
  dist/MetalCreator.app` reads "accepted, source=Notarized Developer ID". **Observed:**
````

- [ ] **Step 6: Errata (Packaging)**

**Append to:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (after one blank line)

````markdown
## Errata (Packaging)

- §5.2's "Bundling OCCT's dylibs into a signed `.app` is **deferred**" and §11's "Bundling OCCT into a signed,
  distributable `.app`" are done by `scripts/package-app.sh` (design: `2026-10-09-packaging-design.md`; how-to:
  `docs/packaging.md`). It builds `dist/MetalCreator.app` with OCCT and its Homebrew dependencies in
  `Contents/Frameworks`, signs it ad hoc (or with `METALCREATOR_SIGN_IDENTITY`), and `scripts/verify-app.sh` proves
  it runs with Homebrew unreadable. Notarization stays a manual step, and the app has no icon yet.
- §3.1's platform floor holds for the build (`.macOS(.v26)`), but the packaged app's `LSMinimumSystemVersion` is the
  newest minimum among its bundled binaries: 27.0, because Homebrew's bottles are built for macOS 27.
- §4.5's `.mcgraph` is registered by the packaged app (`com.metalcreator.mcgraph`, conforming to `public.json`).
  Opening a double-clicked file waits for MetalUI's open-document events (gap M6-d).
````

- [ ] **Step 7: The roadmap row**

**In `docs/superpowers/roadmap.md`, replace:**

```text
| — | Packaging: bundle OCCT dylibs into a signed `.app` | ⏳ after M6 | Spec §11 |
```

**with:**

```text
| — | Packaging: bundle OCCT dylibs into a signed `.app` | ✅ code done; human checks P pending | Spec §11, Errata (Packaging); `scripts/package-app.sh`, `docs/packaging.md`. Ad hoc by default, Developer ID via `METALCREATOR_SIGN_IDENTITY`; notarization is manual; no icon yet; needs macOS 27 while Homebrew's bottles do; MetalUI gap P-a (vendored-code notices) |
```

- [ ] **Step 8: Check and commit**

Run: `swift test 2>&1 | grep -E "Test run with" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc` — Expected: `914`.
Run: `swiftlint lint --strict --quiet` — Expected: no output.
Run: `git diff --stat HEAD` — Expected: only the five files above.

```bash
git add CLAUDE.md docs/metalui-gaps.md docs/verification/human-checks.md docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md docs/superpowers/roadmap.md
git commit -m "docs(packaging): CLAUDE.md commands, MetalUI gap P-a, human checks P, Errata (Packaging), roadmap"
```

Gap P-a is forwarded to the MetalUI session by whoever merges.

---

## Self-review

**Spec coverage** (the design doc and the task's brief):
- Release build of `MetalCreatorApp`, `Contents/{MacOS,Frameworks,Resources,Info.plist}` → Task 4 (`package-app.sh`).
- OCCT dylibs and their transitive non-system dependencies (`otool -L` recursion), install names and rpaths → `@executable_path/../Frameworks` → Task 4 (31 libraries; `@rpath/<name>`, one exe rpath).
- SwiftPM resource bundles (MetalUI's shaders; MetalCreator has none of its own) → Task 4 (every `*.bundle` in the products directory).
- Inside-out signing, ad hoc by default, Developer ID through an environment variable → Task 4 (`METALCREATOR_SIGN_IDENTITY`; hardened runtime + timestamp only with an identity).
- No notarization; documented manual step → Task 4 (`docs/packaging.md`), human check P4.
- Verify: `codesign --verify --deep --strict`; no `/opt/homebrew` in `otool`; launching with DYLD paths unset proves load via a `--self-test` → Task 4 (`verify-app.sh`; stronger than unsetting DYLD: `env -i` plus a sandbox that makes Homebrew unreadable, checked to bite first), Task 2 and 3 (the flag).
- Info.plist: bundle id, version from one source, `.mcgraph` document type and UTI, `LSMinimumSystemVersion` → Task 1 (`AppBundleInfo`), Task 4 (minimum computed: Decision 5 — 27.0, not 26.0, because the bundled bottles need it; recorded in Errata).
- App icon → skipped with a note (Decision 9, design doc, `docs/packaging.md`).
- Tests in `swift test` (self-test entry point, version source) → Tasks 1–4 (13 tests); the script's verify step and a human check → Task 4, Task 5 (group P).
- `.gitignore` for the artefacts → Task 4. Design doc first → Task 1.

**Placeholder scan:** every code step carries the complete file; the only elided text is in expected output (`…` in paths and byte counts that vary).

**Type consistency:** `AppBundleInfo.versionLine` / `infoPlistData(minimumSystemVersion:)` (Task 1) are used by `SelfTestReport.text` (Task 2) and `main.swift` (Task 3); `SelfTest.run(kernel:scratch:compileShaders:)` and `SelfTestReport.passed`/`.text` (Task 2) by `main.swift`; `LaunchCommand` cases (Task 3) by `main.swift`; the flags `--info-plist`, `--self-test` and the executable name `MetalCreator` (Tasks 1, 3) by both scripts (Task 4). Check names `kernel`, `STEP export`, `STL export`, `shaders` match between `SelfTest` and `SelfTestTests`.

**Review Focus:** each of the five lines has its pin: 1 → Task 4 Step 7; 2 → `theSystemsOwnArgumentsOpenAnEmptyWindow` (Task 3); 3 and 4 → Task 4 Step 8; 5 → Task 4 Step 9.
