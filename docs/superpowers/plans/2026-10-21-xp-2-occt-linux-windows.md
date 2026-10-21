# xp-2: OpenCascade 7.9 on Linux and Windows, with packaging — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** MetalCreator uses OpenCascade 7.9 on Linux and Windows as it does on macOS (Mesh to Solid, STEP/STL export, `--self-test`'s OCCT checks, the OCCT and acceptance tests), and ships as a Linux tarball (with `install.sh`), a Linux AppImage and a Windows zip that carry their libraries and `MetalUISDLShaders`; a `.mcgraph` file opens from a Linux file manager or Windows Explorer.

**Architecture:** `COCCT`, `CreatorOCCT` and `CreatorOCCTTests` move to `Package.swift`'s portable list; the OpenCascade prefix comes from `OCCT_PREFIX` (a per-OS default) and the linker flags are per-OS `.unsafeFlags(…, .when(platforms:))` (an `$ORIGIN/lib` rpath on Linux, `-L` on Windows, `debug/lib` for a debug build and `lib` for a release one, whose DLLs come from `PATH` or sit beside the executable). Linux OpenCascade is built from a pinned commit in its own stage of `scripts/linux/Dockerfile` (cached by Docker locally and by buildx in CI); Windows OpenCascade is vcpkg's `opencascade` 7.9.3 port, release and debug libraries, pinned by a vcpkg commit (binary cache restored by `actions/cache/restore` and saved by `actions/cache/save` right after the install). The shim is made MSVC-safe and held there by a source scan, and the text the tests read is held at LF by `.gitattributes`. Packaging is `scripts/package-linux.sh` (run in the image, then in a clean `ubuntu:24.04`), `scripts/package-appimage.sh` (packs the tarball's tree with appimagetool and the type2 runtime, both pinned by version and sha256 and fetched at build time; run in the image, then in a clean `ubuntu:24.04` without FUSE) and `scripts/package-windows.ps1` (CI only). XP-G5 is `LaunchCommand` taking every document argument plus the desktop entry, MIME type, icon and Windows file-type script. SDL's application id (XP-G13) needs no code here: MetalUI sets `SDL_APP_ID` from the id `launchingSingleInstance` already gets.

**Tech Stack:** Swift 6.4 (Swift 6 mode, Swift Testing), SwiftPM unsafe flags per platform, C++17 (clang/GCC/MSVC ABI), CMake + Ninja (OCCT build), Docker (OrbStack), GitHub Actions (buildx cache, `actions/cache/restore` and `/save`), vcpkg, bash, PowerShell, `patchelf`, `desktop-file-utils`, and (CI-time tools, not dependencies) appimagetool 1.9.1 with the type2 runtime 20251108.

**Spec:** `docs/superpowers/specs/2026-10-13-cross-platform-design.md` section 3 (xp-2), the xp-2 rows of section 5 (XP-G5, and the "Linux and Windows packaging" line of section 6), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Errata E1 (`CreatorViewport` is portable) is why the macOS-only list shrinks to `ViewportHarness` and `GraphPanelPreview`.

**Branch / worktree:** `xp-2` in `/Users/maxburger/Developer/MetalCreator-xp-2` (a git worktree). The plan was written against master `11aab8e` (4656 tests on macOS); master has moved since (b7383f9 with S9/S8/S4 has landed, and bracket-speed, 7c-4 and adopt-fh are merging), so **rebase on master at execution start**: Task 1 Step 0 runs `git merge master` and re-measures the baseline test counts. Run every command from that worktree. Never change `Package.swift`'s `../MetalUI` path; never modify `../MetalUI`.

**MetalUI pin.** `METALUI_COMMIT` in `.github/workflows/xp.yml` is **`1bdead8d` or newer, whatever master pins at execution time**: Task 8 keeps the value `git merge master` brought in and never lowers it. MetalUI master `b39d68d6` answers gap XP-G13: `SDLPlatform.Options.applicationID: String?` is handed to SDL as `SDL_HINT_APP_ID` before `SDL_Init` and defaults to the id of `launchingSingleInstance(id:)`. MetalCreator already launches with `AppBundleInfo.identifier` (`com.metalcreator.MetalCreator`), so the window carries that id with no code change; a separate adoption track adds the XP-G13 row and entry (marked fixed) to `docs/metalui-gaps.md` on master, and **this plan adds no gap and relies on the fix**. (XP-G12 on master is the image-sniff gap, also fixed and adopted; this plan does not touch it.)

## Files shared with other tracks (the side that merges second must keep both sides)

| File | Shared with | What xp-2 changes | The second merger keeps |
|---|---|---|---|
| `Package.swift` | 7c-4 (target dependency lists), xp-3 (`CreatorViewport` renderer, shaders) | the header comment; `occt` is `["CreatorOCCT"]` on every platform; the OCCT block (prefix, `occtLinkerFlags`, `COCCT`, `CreatorOCCT`, `CreatorOCCTTests`) is outside `#if os(macOS)`; that `#if` holds only `ViewportHarness` and `GraphPanelPreview` | the other track's new targets and dependencies, **and** these three targets staying outside `#if os(macOS)` with `occt` unconditional |
| `Sources/MetalCreatorApp/main.swift` | the small MetalUI adoptions track (it edits `main.swift`) | `import CreatorOCCT` unconditional; `makeKernel()` is `OCCTKernel()`; `runApp(opening paths: [String], …)`, `forwardedDocuments(paths:)`, `app.open(paths.map …)`, `case .run(let paths)` | the adoption's MetalUI calls, **and** `[String]` paths and the unconditional `OCCTKernel()` |
| `Sources/CreatorApp/LaunchCommand.swift`, `Tests/CreatorAppTests/LaunchCommandTests.swift` | the same adoptions track (if it touches the command line) | `.run(paths: [String])` replaces `.run(path: String?)` | `paths`; any new flag stays a flag that ends the document list |
| `Tests/CreatorViewportTests/OffscreenRenderTests.swift`, `GuideRenderTests.swift` | xp-3 (it will add an SDL GPU variant of the renderer tests) | the first line becomes `#if canImport(Metal) && canImport(CreatorOCCT)` (OpenCascade now exists on Linux, Metal does not) | a Metal-importing test is gated by `canImport(Metal)`; xp-3's SDL tests are gated separately |
| `scripts/linux-test.sh`, `scripts/linux/Dockerfile` | xp-3 (it runs its renderer tests in the same image) | default count 12; `IMAGE`, `OCCT_IMAGE`, `OCCT_JOBS`, test arguments after `test`, `package` (tarball and AppImage); the Dockerfile gains the `occt` stage and `file` (appimagetool needs it) | xp-3 sets its own `XP_TRACK` and `IMAGE` so it never replaces another track's image; its image additions go in the final stage after `COPY --from=occt-source` |
| `.github/workflows/xp.yml` | xp-3 and any MetalUI adoption (`METALUI_COMMIT`) | `VCPKG_COMMIT`, `EXPECTED_TEST_RUNS: 12`, the OCCT build step, the package steps (the Linux upload takes the tarball and the AppImage), the vcpkg steps (restore, install, save), the release-build step, the Windows `timeout-minutes: 180` | the newest `METALUI_COMMIT` (`1bdead8d` or newer); a new test target raises the count in the **four** pinned places at once (`CIPinTests` names them); the Windows job installs vcpkg's `x64-windows` triplet (both configurations), which `Package.swift`'s `debug/lib` and `lib` flags depend on |
| `.gitattributes` (new; no worktree has one) | every track that adds text a test reads or a script runs | `packaging/**`, `scripts/**`, `.github/**`, `Sources/COCCT/**` and `CLAUDE.md` are `text eol=lf`, and `packaging/**/*.png` is `binary` (the icon) | every other rule; a new directory whose text a test reads or a script runs gets its own `text eol=lf` line (`CIPinTests.gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF` names the patterns), and a test that reads such a file replaces `"\r\n"` with `"\n"` |
| `CLAUDE.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/roadmap.md`, `docs/packaging.md` | every track | the lines the diffs in Task 9 show (`docs/metalui-gaps.md`: XP-G5 only; **XP-G13 is the adoption track's**) | every other track's lines; the gap table keeps one row per gap |
| `Tests/CreatorAppTests/LightweightBracketAcceptanceTests.swift` and the other `#if canImport(CreatorOCCT)` tests | the bracket-test speed-up track | **not edited** — but after xp-2 they run on Linux and Windows | the speed-up must keep them passing on Linux (`scripts/linux-test.sh test --filter LightweightBracket`) |

## Global Constraints

- Swift 6 strict concurrency (`swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`); Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest; `@MainActor @Observable` models; behaviour in models and thin views; one type per file; no force unwraps, no GCD, `FormatStyle` for numbers and dates (CLAUDE.md).
- `swiftlint lint --strict` reports zero violations before every commit.
- Target iOS/macOS floors unchanged: `platforms: [.macOS(.v26)]`. OpenCascade is **7.9** (spec section 3): Homebrew's 7.9.3 on macOS, `V7_9_3` at commit `a016080bf6738d6aeae020badee4e888ad1540a5` on Linux, vcpkg `opencascade` 7.9.3 on Windows.
- Spec section 3: OCCT flags become per-OS (`.when(platforms:)` on `unsafeFlags`), an `$ORIGIN` rpath on Linux, DLLs beside the executable on Windows; the OCCT and acceptance tests run on Linux and Windows; packaging for both includes `MetalUISDLShaders`.
- Spec section 6: signing for Windows is out of scope. Wayland/X11-specific behaviour beyond MetalUI's is out of scope.
- Spec section 2.5 pass rule per platform: exit 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and the stated number of "Test run with" lines: **12 on macOS, Linux and Windows** (the harness text said Linux/Windows would become 12 and macOS stays 12; before xp-2 Linux and Windows printed 11).
- Never `pkill`/`killall` by a broad pattern (`swift-test`, `swift test`, `swift-build`, `xctest`): other sessions run `swift test` on this Mac. Kill only your own processes by captured PID (`$!`) or a pattern that contains your own worktree or scratch path.
- The shim (`Sources/COCCT/cocct_*.cpp`) must compile with GCC/Clang on Linux and with Clang (MSVC ABI) on Windows: no Apple or POSIX-only headers, no `M_PI`, no `std::filesystem`, no `__attribute__`.
- The Swift 6.4 Windows compiler crashes in coroutine splitting on an `async` function that holds a heavy loop across an `await`: keep such loops in non-async helpers. **Nothing in this plan adds an `async` loop** (all new Swift code is synchronous or a one-line `await`).
- OCCT's thread pool (`OSD_Parallel`) and `OCCTKernel.serialized` keep working: no change to the shim's threading, and the 197 OCCT conformance tests (including the distance fast-path suites that use the pool) pass on Linux.
- MetalUI gaps go in `docs/metalui-gaps.md` (the entry and the summary-table row) and are never worked around. This plan adds none: XP-G13 (SDL's application id) is fixed in MetalUI master `b39d68d6` and logged by the adoption track, and the plan relies on it (the window gets `AppBundleInfo.identifier` as its id with no code change; `DesktopEntryTests` pins that nothing overrides it).
- Text a test reads or a script runs is LF on every platform: `.gitattributes` (Task 1) sets `eol=lf`, and the tests that read repository files replace `"\r\n"` with `"\n"` (Swift reads `"\r\n"` as **one** `Character`, so a split on `"\n"` or a match ending in `"\n"` finds nothing in a CRLF file, which is what `actions/checkout` writes on `windows-latest` unless told otherwise).
- On Windows the debug suite links vcpkg's debug OpenCascade and the release zip its release one (user decision 8): one C runtime on both sides of the DLL boundary, no compile flag guessed.
- Never commit secrets; the repository is public. No secret is needed: vcpkg, OCCT and SDL are fetched anonymously.
- appimagetool and the AppImage runtime are third-party tools used only while packaging (user decision 2): fetched by `scripts/package-appimage.sh`, pinned by version and sha256, verified before they run, never linked, never a Swift package or system package dependency of MetalCreator. A version bump changes the pinned hashes in the same commit.
- Commit messages end with the session's `Co-Authored-By` / `Claude-Session` trailer lines.

## Review Focus

The spec is silent on these; each has a test in the task that owns the code.

1. **A document path with spaces, accents or CJK** (a Linux `%F` or Explorer `"%1"` argument): it must stay one document, and the installer must not break the launcher entry. A `%` in the folder's name starts a field code in an `Exec=` line and is written `%%`. Pinned: `LaunchCommandTests.aPathWithSpacesAndAccentsIsOneDocument` (Task 5), `InstallScriptTests.theEntryIsInstalledWithTheFoldersOwnQuotedPath`, `aPercentSignInTheFoldersNameIsWrittenDoubled` and `aFolderNameTheEntryCannotHoldIsRefused` (Task 5).
2. **An export to a file name with spaces, accents or kanji** (the user's own folder names; on Windows OpenCascade must read the UTF-8 path as UTF-8, not the ANSI code page): the file must be written. Pinned: `ExportPathTests` (Task 4; it is the first test CI runs on Windows for this).
3. **A package unpacked on a machine that has none of the build machine** (no Swift, no `/opt/occt`, no SDL, no checkout of MetalUI): `--self-test` must still find OpenCascade and the shaders. Pinned by the package scripts, not by a unit test (the recipe's text is pinned by `AppImageRecipeTests`): `scripts/linux-test.sh package` runs the tarball, and the AppImage with `--appimage-extract-and-run` (no FUSE, as in CI), in a clean `ubuntu:24.04` with no `/opt/occt` and no `/work`; `scripts/package-windows.ps1` runs the zip with only Windows' folders on `PATH` and MetalUI's checkout renamed (Tasks 6, 7 and 8).
4. **One number written in many places** (the "Test run with" count, the vcpkg commit, the OCCT commit): they must agree, and a stale 11 must not survive. Pinned: `CIPinTests` (Task 8).
5. **A shim construct that compiles on this Mac and not on MSVC** (`M_PI`, `<unistd.h>`, `<windows.h>`'s `min`/`max`) and **a C runtime mismatch with OpenCascade's DLLs**: pinned by `ShimPortabilityTests` (Tasks 1 and 3: the scan, `NOMINMAX`, the debug and release link directories) and `CIPinTests` (Task 8: the vcpkg triplet that installs both). The compiler that matters runs only in CI, so the scan is the local guard.
6. **A Windows checkout with CRLF line endings** (`actions/checkout` on `windows-latest`): the tests that read `Sources/COCCT`, `packaging/`, the workflow, the Dockerfile and `CLAUDE.md` must give the same answer, and the scripts must stay runnable. Pinned: `.gitattributes` (`CIPinTests.gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF`) and the `"\r\n"` to `"\n"` replacement in `ShimPortabilityTests`, `DesktopEntryTests` and `CIPinTests`. Measured on this Mac: with CRLF text, `split(separator: "\n")` returns 1 line instead of 4, `contains("…\n")` is false, and the Dockerfile's `ARG OCCT_COMMIT=…\n` regex does not match; after the replacement all three behave as on LF.

## Which steps run where

- **Mac (this worktree's scratch copy):** `swift build --build-tests`, `swift test --filter …`, `swiftlint lint --strict`, and once after the last task one full `swift test`.
- **Linux in Docker (OrbStack), here:** `XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 scripts/linux-test.sh …` — the volume is `xp-2-linux-build`, the container `xp-2-linux`. Verified here: the OpenCascade build, the whole suite (12 "Test run with" lines), `--self-test`, `--smoke-test 20`, the tarball and the AppImage in a clean `ubuntu:24.04` (the AppImage with `--appimage-extract-and-run`: no FUSE), `install.sh`. `scripts/linux-test.sh package` needs the network: `scripts/package-appimage.sh` downloads the two pinned tools (about 16 MB) once into `dist/tools`.
- **CI only (cannot run here):** everything Windows (vcpkg install, the build against OCCT's DLLs, the suite, `--self-test`, `--smoke-test`, `package-windows.ps1`, `register-mcgraph.ps1`), the buildx/`actions/cache` caches, the x86_64 Linux job, the AppImage on a real desktop (human check XP-19), and the GitHub Actions YAML (only parsed here). Windows is verified only by pushing an `xp-*` branch; the Windows job stays `continue-on-error` until it has been green once, and **its first run is expected to need a fix or two** (Task 8 Step 8 lists what to read first; the release build and the packaging each have their own step so one red step leaves the others readable).

## User decisions (decided 2026-10-21)

The user decided these on 2026-10-21. Decision 2 differs from the recommendation the plan was first written for (both packages, not the tarball alone); decisions 1 and 3 to 8 are the recommended options, approved.

1. **OpenCascade source per OS. DECIDED 2026-10-21: Linux (a), Windows (a).** Linux: (a) build from a pinned commit in the image's `occt` stage **[recommended]**; (b) the distro package (Ubuntu 24.04 ships 7.6.3, not 7.9); (c) a prebuilt tarball in a GitHub release. Windows: (a) vcpkg's `opencascade` 7.9.3 port, release and debug libraries (triplet `x64-windows`), pinned by vcpkg commit **[recommended]**; (b) OCCT's official prebuilt installer (needs a login, not scriptable); (c) CMake from source in CI (the vcpkg port does that with patches we would otherwise own).
2. **Linux packaging. DECIDED 2026-10-21: (c) both, a tarball with `install.sh` AND an AppImage.** Options were (a) tarball plus `install.sh`, (b) AppImage only, (c) both. The tarball (Task 6) builds and is verified in Docker and needs no FUSE. The AppImage (Task 7) is packed from the tarball's own tree (executable with `RUNPATH $ORIGIN/lib`, `lib/`, `MetalUISDLShaders`, `share/`, the licences) by `scripts/package-appimage.sh`, with an `AppRun`, the same desktop entry (id `com.metalcreator.MetalCreator`, `Exec=MetalCreator %F`, `MimeType=`) and the icon at the AppDir's root. **Tool: appimagetool 1.9.1 with the type2 runtime 20251108 (`--runtime-file`, so nothing is fetched by the tool itself), each pinned by version and sha256** (checked on 2026-10-21 by downloading the GitHub release assets and hashing them: appimagetool `x86_64` `ed4ce84f…384eb0`, `aarch64` `f0837e74…a9158`; runtime `x86_64` `2fca8b44…260d`, `aarch64` `00cbdfcf…7444`; the full digests are in the script). MetalUI's `docs/packaging.md` recommends no AppImage tool (it names none), so the choice is the AppImage project's own current release. **appimagetool and the runtime are third-party CI/build-time tools, not a package dependency**: nothing links them, the manifest and the app do not change for them, only the runtime's bytes head the output file, and both are MIT licensed. They run without FUSE (`--appimage-extract-and-run`), which is also how CI and the clean-Ubuntu check run the output. **File type for the AppImage: a documented manual step, not `install.sh`.** `install.sh` registers the folder it sits in; an AppImage has no folder that stays put, so serving both would add a mode, a way to register a path that moves, and tests. The AppImage instead carries the same desktop entry and MIME XML, which an AppImage integration tool (AppImageLauncher, appimaged) installs for the entry, and `docs/packaging.md` gives the three commands that register the MIME type by hand. Human check XP-19 runs it on a desktop.
3. **Signing. DECIDED 2026-10-21: (a) none.** Out of scope (spec section 6) **[recommended: none]**; options: (b) a detached GPG signature and `SHA256SUMS` for the tarball and zip (no certificate, one CI secret for the GPG key), (c) Windows Authenticode (certificate, secret in CI).
4. **CI caching. DECIDED 2026-10-21: (a).** (a) buildx `type=gha` cache for the `occt` stage (scope `xp-occt-<arch>`), and for vcpkg's binary-cache folder `actions/cache/restore` before the install and `actions/cache/save` right after it **[recommended]**: `actions/cache`'s own post step saves only when the whole job is green, and the first Windows runs are expected to be red, so with it every retry would repeat the vcpkg build; the save step runs whatever the later steps do, but only after a whole install (a cache entry is never replaced, so a partial one would fill the key for good); (b) a prebuilt OCCT image/archive published to GHCR or a release and pinned by digest/hash (fastest and immune to eviction, but needs a publishing job and a token); (c) no cache (an hour per run). Limits of (a): GitHub evicts an entry unused for seven days (a quiet week costs one slow run) and keeps at most **10 GB per repository**, evicting the least recently used; there are four buildx scopes (portable and occt, each for x86_64 and aarch64) plus the vcpkg folder, and a cache written on a branch is visible to that branch and the default branch only, so every new `xp-*` branch writes its own set. If a run that should have restored the OCCT stage builds it, the entry was evicted: move to (b). `mode=min` does not help here, because the cached targets (MetalUI's portable image and our `occt` stage) are single-stage Dockerfiles, so `min` exports the same layers as `max`. The buildx cache is written by the build step itself, so a later red step does not lose it.
5. **Several documents on the command line. DECIDED 2026-10-21: (a), approved.** (a) open each in turn, the last stays open, as macOS's Finder does **[recommended]**; (b) open the first and ignore the rest (xp-1's behaviour); (c) one window each (needs multi-window).
6. **Windows file type. DECIDED 2026-10-21: (a), approved.** (a) a per-user `register-mcgraph.ps1` in the zip **[recommended]**; (b) wait for an installer (WiX/MSIX).
7. **Linux floor. DECIDED 2026-10-21: (a), approved.** (a) glibc 2.39 (Ubuntu 24.04, where the Swift 6.4 image runs) **[recommended]**; (b) build on an older base for older distributions.
8. **Windows C runtime. DECIDED 2026-10-21: (a), approved.** The suite is a debug build (`swift test`): Swift's and the clang-built shim's C runtime is the debug one (`/MDd`, `_DEBUG`, `_ITERATOR_DEBUG_LEVEL=2` in the headers the shim compiles), while a release-only vcpkg install is `/MD` with level 0; OpenCascade's headers (compiled into the shim) and its DLLs would disagree about the runtime. The green xp-1 run already shows a debug Swift executable running beside release-runtime DLLs (swiftCore, SDL3) across a C interface; the new risk is C++ types and allocations that cross the shim and OpenCascade. Options: (a) **[recommended, decided up front, in the plan from the first run]** build vcpkg's debug libraries too (triplet `x64-windows`): the debug suite links `debug\lib` and finds `debug\bin` on `PATH`, the release zip uses `lib` and `bin`, so each side of the DLL boundary has the same runtime by construction and no compile flag is guessed; the cost is that the first vcpkg build builds OpenCascade twice (the Windows job's timeout is 180 minutes; cached afterwards); (b) keep the release-only install and pass matching flags to both compilers in the Test and Build steps: `-Xswiftc -libc -Xswiftc MD` for Swift (it does not touch the shim's C++) and, for the shim, the release runtime and `_ITERATOR_DEBUG_LEVEL=0` as `-Xcc` flags, which depends on what SwiftPM already passes C++ (`-D_DEBUG`, `--dependent-lib=msvcrtd`) and cannot be read here, so it is untested; (c) run the Windows suite in release (`swift test -c release -Xswiftc -enable-testing`): it changes what the suite tests (the benchmarks, assertions) and runs the release optimiser, which has a known crash on this compiler, on every test run. **If the first run still fails:** (1) `vcpkg did not install: debug\lib\TKernel.lib` with a listing of what exists: the debug libraries are named otherwise than `Package.swift` expects (extend `occtLibraries` or add the postfix to the debug flags); (2) a runtime mismatch shows as lld-link's `error: /failifmismatch: mismatch detected for 'RuntimeLibrary'` or `'_ITERATOR_DEBUG_LEVEL'` at link time, or as the first OCCT test dying with exit code `0xC0000409` or `0xC0000374` (Windows' fail-fast and heap-corruption codes) or a `Debug Assertion Failed` line: try (b), then (c).

## Test counts

macOS: **master + 27** (Task 1 +2, Task 3 +2, Task 4 +1, Task 5 +10, Task 7 +4, Task 8 +8); the plan was written against master `11aab8e` (4656 tests), so that is 4683 there, and Task 1 Step 0 re-measures master's own number after `git merge master` and replaces 4656 (add 27 for the expected final count). **Linux and Windows: the "Test run with" count goes from 11 to 12** (`CreatorOCCTTests` joins them); the 27 new tests are not gated, and every OpenCascade-dependent test that was gated by `canImport(CreatorOCCT)` now runs (the kernel conformance suites, the bracket acceptance, Mesh to Solid, the app acceptance tests). The macOS count note stays as it was (12). See "Measured results" at the end for what was run.

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/COCCT/cocct_internal.hpp`, `cocct_build.cpp`, `cocct_distance_analytic.hpp` | 1 | `cocct::kPi` replaces `M_PI` |
| `.gitattributes` (new) | 1 | LF checkout of the text the tests read and the scripts run (Windows); the icon stays binary |
| `Tests/CreatorOCCTTests/ShimPortabilityTests.swift` (new) | 1, 3 | scan of the shim for non-portable constructs; the manifest defines `NOMINMAX` on Windows and links debug against debug |
| `scripts/linux/Dockerfile` | 2 | `occt` stage (OpenCascade 7.9.3 from a pinned commit), `occt-source`, final stage with `/opt/occt`, `patchelf`, `desktop-file-utils`, `file` |
| `scripts/linux-test.sh` | 2, 6, 7 | count 12; `IMAGE`, `OCCT_IMAGE`, `OCCT_JOBS`; arguments after `test`; `package` (tarball, then AppImage) |
| `Package.swift` | 3 | portable OCCT targets; `OCCT_PREFIX`; per-OS linker flags (Windows: `debug/lib` or `lib` by configuration); `NOMINMAX` |
| `Tests/CreatorViewportTests/OffscreenRenderTests.swift`, `GuideRenderTests.swift` | 3 | gate on `canImport(Metal) && canImport(CreatorOCCT)` |
| `Sources/MetalCreatorApp/main.swift`, `Sources/CreatorKernel/KernelUnavailable.swift`, `Sources/CreatorApp/SelfTest.swift` | 4, 5 | `OCCTKernel` everywhere; stale comments; `paths` |
| `Tests/CreatorOCCTTests/ExportPathTests.swift` (new) | 4 | export to a non-ASCII path |
| `Sources/CreatorApp/LaunchCommand.swift`, `AppBundleInfo.swift` | 5 | `.run(paths:)`, `forwardedDocuments(paths:)`, `AppBundleInfo.mimeType` |
| `packaging/linux/*` (new), `packaging/windows/register-mcgraph.ps1` (new) | 5 | desktop entry (with `Icon=`), MIME type, placeholder icon, `install.sh`, Windows file type |
| `Tests/CreatorAppTests/LaunchCommandTests.swift`, `DesktopEntryTests.swift` (new), `InstallScriptTests.swift` (new) | 5 | XP-G5, the window class, the icon |
| `scripts/package-linux.sh` (new) | 6 | the tarball (the executable's RUNPATH is `$ORIGIN/lib` only) |
| `scripts/package-appimage.sh` (new), `packaging/appimage/AppRun` (new) | 7 | the AppImage, packed from the tarball's tree with pinned appimagetool and runtime |
| `Tests/CreatorAppTests/AppImageRecipeTests.swift` (new) | 7 | pins the AppImage recipe's text |
| `scripts/package-windows.ps1` (new), `packaging/windows/vcpkg.json` (new), `.github/workflows/xp.yml` | 8 | the zip, vcpkg, CI |
| `Tests/CreatorAppTests/CIPinTests.swift` (new), `PackagingScriptTests.swift` | 2, 5, 6, 7, 8 | scripts parse; pinned numbers agree; both Linux packages uploaded |
| `CLAUDE.md`, `docs/packaging.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/roadmap.md` | 9 | documentation (no new gap) |

## Interfaces (what a task hands the next)

- `cocct::kPi` (Task 1) — `inline constexpr double` in `namespace cocct`, `cocct_internal.hpp`.
- `Package.swift` (Task 3): `let occt: [Target.Dependency] = ["CreatorOCCT"]` on every platform; `occtPrefix: String` (env `OCCT_PREFIX`, else `/opt/homebrew/opt/opencascade` | `/opt/occt` | `C:/occt`); `occtLinkerFlags: [LinkerSetting]` (Windows: `-L<prefix>/debug/lib` for a debug build, `-L<prefix>/lib` for a release build, the layout of vcpkg's `x64-windows` triplet).
- Docker (Task 2): image `${IMAGE:-metalcreator-linux:latest}` holds `/opt/occt` (`include/opencascade`, `lib/libTK*.so.7.9[.3]` each with `RUNPATH $ORIGIN`, `share/licenses/*`), env `OCCT_PREFIX=/opt/occt`, `patchelf`, `desktop-file-validate`, `file`. `scripts/linux-test.sh [build|test|smoke|all] [swift test args…]`.
- `LaunchCommand.run(paths: [String])`; `LaunchCommand.forwardedDocuments(paths:exists:) -> [String]`; `AppBundleInfo.mimeType == "application/x-metalcreator-graph"` (Task 5).
- `scripts/linux-test.sh package` (Task 6) writes `dist/MetalCreator-<version>-linux-<arch>.tar.gz` and runs it in a clean Ubuntu; `scripts/package-linux.sh` honours `METALCREATOR_DIST_DIR`, `METALCREATOR_SCRATCH`, `OCCT_PREFIX`.
- `scripts/package-appimage.sh [tarball]` (Task 7) writes `dist/MetalCreator-<version>-linux-<arch>.AppImage` from that tarball and honours `METALCREATOR_DIST_DIR` and `METALCREATOR_TOOLS` (default `dist/tools`); `scripts/linux-test.sh package` runs both scripts and checks both outputs in a clean Ubuntu.
- `scripts\package-windows.ps1 [-NoBuild] -BuildFlags [string[]] -SdlRoot <path> [-OutDir]` (Task 8), env `OCCT_PREFIX` (its release set: `bin`).
- Workflow env `VCPKG_COMMIT`, `EXPECTED_TEST_RUNS` (Task 8).

---
### Task 1: Make the shim MSVC-safe and pin it with a scan

**Files:**
- Modify: `Sources/COCCT/cocct_internal.hpp`, `Sources/COCCT/cocct_build.cpp`, `Sources/COCCT/cocct_distance_analytic.hpp`
- Create: `Tests/CreatorOCCTTests/ShimPortabilityTests.swift`, `.gitattributes`

**What the read of the shim found.** The eight `.cpp`/`.hpp` files include only OCCT's headers and the C++17 standard library (`<algorithm> <atomic> <cmath> <cstdlib> <cstring> <exception> <limits> <memory> <mutex> <new> <numeric> <stdexcept> <string> <unordered_map> <vector>`): no POSIX header, no `std::filesystem`, no `__attribute__`, no Apple header. `std::free` frees memory the shim itself `malloc`ed in the same C runtime. The one portability bug is **`M_PI`** (14 uses): MSVC's `<cmath>` defines it only under `_USE_MATH_DEFINES`. The other Windows hazard, `<windows.h>`'s `min`/`max` macros (the shim calls `std::min`/`std::max`), is a build setting and belongs to Task 3.

**Interfaces:**
- Consumes: nothing.
- Produces: `cocct::kPi` (`inline constexpr double`, in `namespace cocct`); `ShimPortabilityTests.banned` (the list a later author extends).

- [ ] **Step 0: Bring the branch up to master and re-measure the baseline**

The plan was written against master `11aab8e`; master has moved (b7383f9 with S9/S8/S4 has landed, and bracket-speed, 7c-4 and adopt-fh are merging). Rebase on master at execution start, as a merge (xp-2 carries commits, so no history is rewritten):

```bash
cd /Users/maxburger/Developer/MetalCreator-xp-2
git status --short                       # clean
git merge master                         # a conflict in a file the "Files shared with other tracks" table names: keep both sides as it says
git -C ../MetalUI log --oneline -1       # MetalUI must be at 1bdead8d or newer
grep -n "METALUI_COMMIT" .github/workflows/xp.yml     # keep the value master has (1bdead8d or newer); Task 8 never lowers it
swift build --build-tests 2>&1 | grep -E "error:" | head -5          # no output
swift test > /tmp/xp2-baseline.log 2>&1; echo "exit $?"             # 0
grep -c "Test run with" /tmp/xp2-baseline.log                       # 12 on macOS
grep -h "Test run with" /tmp/xp2-baseline.log | grep -oE "with [0-9]+ tests" | awk '{s+=$2} END {print s}'   # the baseline N
XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 scripts/linux-test.sh test       # the Linux baseline: 11 "Test run with" lines (needs Task 2's image only for 12; before Task 2 use xp-1's image)
```

Record N and the Linux line count here and in "Test counts" (this plan's 4656 is the figure at `11aab8e`); the expected final macOS count is N + 27. If `git merge master` brought a newer `METALUI_COMMIT` or a changed workflow, Task 8's diff context lines may differ: apply its changes by meaning, not by hunk. If `docs/metalui-gaps.md` on master does not yet have XP-G13 (the adoption track has not merged), do not add it; this plan never edits that row.

- [ ] **Step 1: Write the failing test**

Create `Tests/CreatorOCCTTests/ShimPortabilityTests.swift`:

```swift
import Foundation
import Testing

/// The COCCT shim (`Sources/COCCT/cocct_*.cpp`) must compile with GCC and Clang on Linux and with Clang targeting MSVC on
/// Windows (cross-platform spec section 3, plan xp-2). This Mac builds only the first and the Linux image only GCC-free
/// Clang, so the constructs that break a compiler we cannot run here are pinned by a scan of the sources. Each entry is a
/// construct that compiled on macOS and failed (or would fail) elsewhere.
struct ShimPortabilityTests {
    /// A construct the shim must not use, and what to write instead.
    struct Banned: Sendable, CustomTestStringConvertible {
        let token: String
        let instead: String
        var testDescription: String { token }
    }

    static let banned: [Banned] = [
        Banned(token: "M_PI", instead: "cocct::kPi (MSVC's <cmath> defines M_PI only under _USE_MATH_DEFINES)"),
        Banned(token: "<unistd.h>", instead: "nothing: POSIX only"),
        Banned(token: "<sys/", instead: "nothing: POSIX only"),
        Banned(token: "<dlfcn.h>", instead: "nothing: POSIX only"),
        Banned(token: "<pthread.h>", instead: "std::mutex or OCCT's Standard_Mutex"),
        Banned(token: "<mach", instead: "nothing: Apple only"),
        Banned(token: "__APPLE__", instead: "nothing: the shim has no platform branches"),
        Banned(token: "__attribute__", instead: "nothing: GCC and Clang only"),
        Banned(token: "__builtin_", instead: "the standard library"),
        Banned(token: "ssize_t", instead: "std::ptrdiff_t"),
        Banned(token: "std::filesystem", instead: "a path from Swift (it arrives as a UTF-8 const char *)"),
        Banned(token: "strcasecmp", instead: "nothing: POSIX only"),
        Banned(token: "alloca", instead: "std::vector"),
    ]

    @Test func theScanFindsTheShimsSources() throws {
        #expect(try Self.sources().count >= 9, "Sources/COCCT holds eight .cpp/.hpp files and cocct.h")
    }

    @Test(arguments: banned)
    func theShimAvoids(_ construct: Banned) throws {
        var offenders: [String] = []
        for (name, text) in try Self.sources() {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.drop(while: { $0 == " " || $0 == "\t" })
                if !code.hasPrefix("//"), code.contains(construct.token) {
                    offenders.append("\(name):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(construct.token) at \(offenders.joined(separator: ", ")); use \(construct.instead)")
    }

    /// `<repo>`, found from this file (`Tests/CreatorOCCTTests/ShimPortabilityTests.swift`).
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every C++ source and header of the shim, with its file name. Line endings are normalised: a Windows checkout that turned
    /// the files into "\r\n" would read as one line (Swift counts "\r\n" as one Character), and the scan would blame a comment's
    /// mention of a banned name. `.gitattributes` keeps the files LF; this keeps the test right if it ever does not.
    private static func sources() throws -> [(name: String, text: String)] {
        let directory = repository.appending(path: "Sources/COCCT")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { ["cpp", "hpp", "h"].contains(URL(filePath: $0).pathExtension) }
            .sorted()
        return try files.map {
            ($0, try String(contentsOf: directory.appending(path: $0), encoding: .utf8).replacing("\r\n", with: "\n"))
        }
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:"; swift test --filter ShimPortabilityTests 2>&1 | grep -E "recorded an issue|Test run"`
Expected: FAIL — `theShimAvoids(_:)` records an issue for `M_PI` (`cocct_build.cpp:241`, `cocct_distance_analytic.hpp:70` and others); the other 12 arguments and `theScanFindsTheShimsSources` pass.

- [ ] **Step 3: Replace `M_PI`**

In `Sources/COCCT/cocct_internal.hpp`, inside `namespace cocct {`, before `set_ok`:

```cpp
namespace cocct {

/// pi. Not `M_PI`: MSVC's <cmath> defines it only under _USE_MATH_DEFINES, and C++17 has no std::numbers.
inline constexpr double kPi = 3.14159265358979323846;

inline void set_ok(occt_status *status) {
```

Then replace every `M_PI` with `kPi` in `cocct_build.cpp` (it has `using namespace cocct;`; two uses, lines 241 and 248) and in `cocct_distance_analytic.hpp` (12 uses; it is inside `namespace cocct` and includes `cocct_internal.hpp` before them):

```bash
sed -i '' 's/M_PI/kPi/g' Sources/COCCT/cocct_build.cpp Sources/COCCT/cocct_distance_analytic.hpp
grep -rn "M_PI" Sources/COCCT || echo "none left"
```

(On Linux use `sed -i` without the empty string.) `kPi` is the same double as `M_PI` (both are the literal `3.14159265358979323846`).

- [ ] **Step 4: Run the test and the shim's own suites**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning: building for macOS"; swift test --filter "ShimPortabilityTests|DistanceConformanceTests|SweepConformanceTests" 2>&1 | grep -E "recorded an issue|Test run"`
Expected: no output from the build line (the `ld: warning … built for newer version 27.0` lines are present on master and are filtered); PASS.

- [ ] **Step 4b: Pin Windows line endings**

Create `.gitattributes` at the repository root (no worktree has one; it changes nothing on a Mac, where these files are already LF):

```
# Files the tests read and the scripts run are checked out with LF on every platform. On windows-latest, actions/checkout writes
# CRLF unless told otherwise (Git for Windows sets core.autocrlf), and Swift reads "\r\n" as ONE Character: a test that splits
# a file on "\n" or matches "...\n" then finds nothing, and bash refuses a script with CRs. CIPinTests names these patterns.
packaging/** text eol=lf
scripts/** text eol=lf
.github/** text eol=lf
Sources/COCCT/** text eol=lf
CLAUDE.md text eol=lf
# The icon is binary: the rule above would rewrite its bytes.
packaging/**/*.png binary
```

Why: on `windows-latest`, `actions/checkout` runs Git for Windows, which sets `core.autocrlf=true`, so the files come out with `\r\n`. Swift reads `"\r\n"` as one `Character`: `split(separator: "\n")` finds one line (measured: a shim file turned CRLF reads as one line that starts with `//`, so the scan above skips the whole file and passes without looking at anything), a match ending in `"\n"` never matches (`DesktopEntryTests`, `CIPinTests`), and bash refuses a script with CRs. The rule makes the checkout LF; the tests also replace `"\r\n"` with `"\n"` themselves, so a checkout that ignores the rule still gives the right answer (`CIPinTests` pins the rule's patterns). This is a Windows-only risk the Mac cannot show; the mechanism was measured here with Swift strings (`"a\r\nb"` splits to 1 element, contains `"a\n"` is false; after `.replacing("\r\n", with: "\n")` 2 and true).

- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet            # no output
git add .gitattributes Sources/COCCT Tests/CreatorOCCTTests/ShimPortabilityTests.swift
git commit -m "fix(occt): cocct::kPi replaces M_PI (MSVC); scan the shim for non-portable constructs" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **+2** (macOS and Linux) — `theScanFindsTheShimsSources`, and `theShimAvoids(_:)` (one parameterised test, 13 arguments).

---

### Task 2: Linux image with OpenCascade 7.9, and the script's new options

**Files:**
- Modify: `scripts/linux/Dockerfile` (rewritten), `scripts/linux-test.sh`
- Modify: `Tests/CreatorAppTests/PackagingScriptTests.swift` (parses `linux-test.sh` too)

**Why a separate stage.** OpenCascade is 4,668 compile steps (about 13 minutes with 6 jobs on this loaded 10-core Mac). The `occt` stage starts from the public `swift:6.4-noble` image, not from MetalUI's `metalui-portable`, so its cache does not depend on MetalUI's image. Locally Docker's layer cache keeps it. In CI buildx builds it alone (`--target occt`) into the GitHub Actions cache and hands the result to the final stage as `OCCT_IMAGE` (a plain `docker build` cannot see buildx's cache). **Two cache keys to know:** the `OCCT_JOBS` build argument is part of the key (a different value rebuilds OpenCascade), so the default is a fixed 6 and the script passes it only when `OCCT_JOBS` is set; and `COPY --from=` takes no variable, so the final stage copies from a stage named by `FROM ${OCCT_IMAGE} AS occt-source`.

**What the toolkit list is.** The nineteen libraries `Package.swift` links (`TKernel … TKDESTL`) are built with every module off and `BUILD_ADDITIONAL_TOOLKITS` naming them; CMake resolves their dependencies (TKDESTEP needs TKXCAF, TKV3d, TKService, TKVCAF, TKLCAF, TKCAF, TKCDF, TKHLR, which is why the image holds 28 libraries). OpenGL, FreeType, Tk, TBB, FreeImage, RapidJSON, Draco, VTK are off.

**RUNPATH.** OCCT's libraries carry no rpath, and an executable's `RUNPATH` is not searched for the libraries its libraries load, so `libTKDESTEP.so` could not find `libTKXCAF.so` (measured: `CreatorViewportTests-test-runner: error while loading shared libraries: libTKXCAF.so.7.9`). The stage ends with `patchelf --set-rpath '$ORIGIN'` on each real library file; the image deliberately has **no** `ld.so.conf` entry, so the tests exercise the rpath that `Package.swift` gives the binaries, as a tarball's do.

**Interfaces:**
- Consumes: `scripts/linux-test.sh` as xp-1 left it (default count 11, `IMAGE` fixed).
- Produces: the image contract in "Interfaces" above; `scripts/linux-test.sh test --filter X` (arguments after the step go to `swift test`, switch the count rule off, and keep `A|B` one word).

- [ ] **Step 1: Write the failing test**

In `Tests/CreatorAppTests/PackagingScriptTests.swift`, replace the suite so it checks every script by repository-relative path (the macOS-only guard stays):

```swift
import Foundation
import Testing

/// The packaging scripts parse and are executable. What they build is checked by running them: `scripts/verify-app.sh`
/// (which `scripts/package-app.sh` ends with), `scripts/linux-test.sh package` (the Linux tarball, run in a clean Ubuntu),
/// CI's Windows job (the zip, `scripts/package-windows.ps1`) and human checks P1, XP-16 and XP-17.
#if !os(Windows)  // bash scripts: Windows has no /bin/bash
struct PackagingScriptTests {
    @Test(arguments: ["scripts/package-app.sh", "scripts/verify-app.sh", "scripts/linux-test.sh"])
    func theScriptParsesAndIsExecutable(_ name: String) throws {
        let script = Self.repository.appending(path: name)
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = ["-n", script.path]
        try bash.run()
        bash.waitUntilExit()
        #expect(bash.terminationStatus == 0, "bash -n \(name)")
    }

    /// `<repo>`, found from this file (`Tests/CreatorAppTests/PackagingScriptTests.swift`).
    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
#endif
```

- [ ] **Step 2: Run it; then check the image does not yet have OpenCascade**

Run: `swift test --filter PackagingScriptTests 2>&1 | grep -E "recorded an issue|Test run"` — PASS (the scripts parse; this step is the harness for the later edits).
Run: `docker run --rm metalcreator-linux:latest ls /opt/occt/lib 2>&1 | head -2`
Expected: `ls: cannot access '/opt/occt/lib'` (or no such image yet).

- [ ] **Step 3: Replace the Dockerfile**

Write `scripts/linux/Dockerfile`:

```dockerfile
# MetalCreator's Linux test image (cross-platform spec 2.6, xp-2 section 3): MetalUI's portable image plus OpenCascade 7.9,
# a font and the packaging tools.
#
# The base is MetalUI's own image (Swift 6.4, SDL 3.4 built from source, Mesa lavapipe for Vulkan on the CPU, AccessKit's
# C bindings; recipe: ../MetalUI/Backends/SDL/linux/Dockerfile), built by scripts/linux-test.sh when it is not on the machine.
#
# Stage `occt` builds OpenCascade from a pinned commit into /opt/occt: only the toolkits the COCCT shim links, plus the ones
# CMake resolves they need (about 4,700 compile steps; 13 minutes with 6 jobs on a loaded 10-core Mac, longer on a 4-core CI
# runner). It starts from the public Swift image, not from BASE, so its cache does not depend on MetalUI's image. It is its own
# stage so that Docker's layer cache (locally) and buildx's cache (CI, .github/workflows/xp.yml) skip it until OCCT_COMMIT,
# OCCT_JOBS or the flags change. CI builds it alone (`--target occt`) and hands the result to the final stage as OCCT_IMAGE.
ARG BASE=metalui-portable:latest
ARG OCCT_IMAGE=occt

FROM swift:6.4-noble AS occt
# V7_9_3 (peeled commit). A commit is pinned, not the tag: a tag can be moved.
ARG OCCT_COMMIT=a016080bf6738d6aeae020badee4e888ad1540a5
# Part of the cache key: a different value rebuilds OpenCascade. The script passes it only when OCCT_JOBS is set.
ARG OCCT_JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build patchelf ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN git init -q /tmp/occt \
    && git -C /tmp/occt fetch -q --depth 1 https://github.com/Open-Cascade-SAS/OCCT.git ${OCCT_COMMIT} \
    && git -C /tmp/occt checkout -q FETCH_HEAD
RUN cmake -S /tmp/occt -B /tmp/occt/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/occt \
         -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DBUILD_LIBRARY_TYPE=Shared \
         -DBUILD_MODULE_FoundationClasses=OFF -DBUILD_MODULE_ModelingData=OFF -DBUILD_MODULE_ModelingAlgorithms=OFF \
         -DBUILD_MODULE_Visualization=OFF -DBUILD_MODULE_ApplicationFramework=OFF -DBUILD_MODULE_DataExchange=OFF \
         -DBUILD_MODULE_Draw=OFF -DBUILD_DOC_Overview=OFF \
         "-DBUILD_ADDITIONAL_TOOLKITS=TKernel;TKMath;TKG2d;TKG3d;TKGeomBase;TKGeomAlgo;TKBRep;TKTopAlgo;TKPrim;TKBO;TKBool;TKFillet;TKOffset;TKMesh;TKShHealing;TKXSBase;TKDE;TKDESTEP;TKDESTL" \
         -DUSE_FREETYPE=OFF -DUSE_TK=OFF -DUSE_OPENGL=OFF -DUSE_GLES2=OFF -DUSE_XLIB=OFF -DUSE_TBB=OFF -DUSE_FREEIMAGE=OFF \
         -DUSE_RAPIDJSON=OFF -DUSE_DRACO=OFF -DUSE_VTK=OFF -DUSE_FFMPEG=OFF -DUSE_OPENVR=OFF \
    && cmake --build /tmp/occt/build --parallel ${OCCT_JOBS} && cmake --install /tmp/occt/build \
    && mkdir -p /opt/occt/share/licenses \
    && cp /tmp/occt/LICENSE_LGPL_21.txt /tmp/occt/OCCT_LGPL_EXCEPTION.txt /opt/occt/share/licenses/ \
    && rm -rf /tmp/occt
# OCCT's libraries carry no rpath, and an executable's RUNPATH is not searched for the libraries its libraries load, so
# libTKDESTEP could not find libTKXCAF. Each library names its own folder, which also makes /opt/occt/lib and a tarball's lib/
# work the same way.
RUN for library in /opt/occt/lib/*.so.*.*.*; do patchelf --set-rpath '$ORIGIN' "$library"; done

# COPY --from takes no variable, so the stage or image to copy from is named by a FROM line.
FROM ${OCCT_IMAGE} AS occt-source

FROM ${BASE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core patchelf desktop-file-utils file \
    && rm -rf /var/lib/apt/lists/*
COPY --from=occt-source /opt/occt /opt/occt
# No ld.so.conf entry: the binaries must find /opt/occt/lib through the rpath Package.swift gives them, as a tarball's do.
ENV OCCT_PREFIX=/opt/occt
# patchelf and desktop-file-utils serve scripts/package-linux.sh and its checks; `file` is needed by appimagetool, which scripts/package-appimage.sh
# runs (measured: it stops with "file command is missing but required" without it). The render tests draw text with MetalUI's
# portable text system over the machine's installed fonts, so the image names one.
WORKDIR /work/MetalCreator
```

- [ ] **Step 4: Edit `scripts/linux-test.sh`**

Write it as follows (the whole file; the only changes from xp-1's are the usage block, the count 12, `IMAGE`/`OCCT_IMAGE`/`OCCT_JOBS`, `TEST_ARGS`, and the `%q` quoting in `do_test`):

```bash
#!/bin/bash
# Builds and tests MetalCreator on Linux in Docker (OrbStack on this Mac runs aarch64 containers; CI runs the same script
# on x86_64 and aarch64 runners). Cross-platform spec 2.5, 2.6.
#
#   scripts/linux-test.sh [build|test|smoke|all] [swift test arguments]    default: all
#     build   swift build
#     test    swift test, judged by the pass rule below. Arguments after `test` (for example `--filter CreatorOCCTTests`) go to
#             swift test and switch the count rule off: only the exit code and the issue lines are judged.
#     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s)
#     all     the three, in that order
#   scripts/linux-test.sh clean                     removes this track's build volume
#
# Needs MetalUI checked out beside this repository (../MetalUI), which Package.swift's path dependency expects. The repository
# is mounted read-write and MetalUI read-only; build products live in a named volume, so macOS's .build is untouched and a
# rerun is incremental.
#
# Pass rule for `test` (spec 2.5): exit 0, no "recorded an issue" or "failed after" line, and EXPECTED_TEST_RUNS lines
# "Test run with" (one per test target that has tests: twelve on Linux, Windows and macOS since xp-2 put CreatorOCCTTests on
# every platform).
#
# Environment: XP_TRACK names the track (default xp-1), which names the container and the volume, so a script run kills only
# its own container. EXPECTED_TEST_RUNS overrides the count (12 today). IMAGE names the image this script builds and runs
# (default metalcreator-linux:latest; a track that must not replace another's image sets its own). OpenCascade is built from
# source in an image stage, which is the slow part: OCCT_IMAGE names an image that already holds /opt/occt (CI builds the
# stage alone with buildx and its layer cache and passes the result), else the stage is built here and Docker's layer cache
# keeps it. OCCT_JOBS sets the parallelism of
# that OpenCascade build (default 6; a different value is a different Docker cache key and rebuilds OpenCascade).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$PWD
if [ ! -d ../MetalUI ]; then
    echo "scripts/linux-test.sh: MetalUI must be checked out beside this repository (../MetalUI)." >&2
    exit 2
fi
METALUI=$(cd ../MetalUI && pwd -P)

TRACK=${XP_TRACK:-xp-1}
EXPECTED_TEST_RUNS=${EXPECTED_TEST_RUNS:-12}
BASE_IMAGE=metalui-portable:latest
IMAGE=${IMAGE:-metalcreator-linux:latest}
NAME=$TRACK-linux
VOLUME=$TRACK-linux-build
LOG=${TMPDIR:-/tmp}/$TRACK-linux-test.log

step=${1:-all}
shift || true
TEST_ARGS=("$@")
if [ "$step" = clean ]; then
    docker volume rm "$VOLUME" >/dev/null 2>&1 || true
    exit 0
fi

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "Building $BASE_IMAGE from MetalUI's recipe (once; it builds SDL3 from source)..."
    docker build -t "$BASE_IMAGE" -f "$METALUI/Backends/SDL/linux/Dockerfile" "$METALUI/Backends/SDL"
fi
if [ "${METALCREATOR_IMAGE_PREBUILT:-}" != 1 ]; then
    docker build -q -t "$IMAGE" --build-arg "BASE=$BASE_IMAGE" ${OCCT_IMAGE:+--build-arg "OCCT_IMAGE=$OCCT_IMAGE"} \
        ${OCCT_JOBS:+--build-arg "OCCT_JOBS=$OCCT_JOBS"} - < scripts/linux/Dockerfile >/dev/null
fi

# Runs `$1` in the image, from the repository, with the build volume; stops only this track's own container.
in_container() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run --rm --name "$NAME" \
        -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build \
        "$IMAGE" bash -ec "$1"
}

do_build() {
    in_container 'swift build --scratch-path /build'
}

do_smoke() {
    in_container 'bin=$(swift build --scratch-path /build --show-bin-path)/MetalCreatorApp
        "$bin" --self-test
        "$bin" --smoke-test 20'
}

do_test() {
    local status=0 quoted=""
    # printf %q keeps a filter like 'A|B' one word through the container's shell.
    if [ "${#TEST_ARGS[@]}" -gt 0 ]; then printf -v quoted ' %q' "${TEST_ARGS[@]}"; fi
    in_container "swift test --scratch-path /build$quoted" 2>&1 | tee "$LOG" || status=$?
    local clean runs tests
    clean=$(sed $'s/\x1b\\[[0-9;]*m//g' "$LOG")
    runs=$(grep -c "Test run with" <<<"$clean" || true)
    tests=$({ grep "Test run with" <<<"$clean" || true; } | sed -E 's/.*Test run with ([0-9]+) tests.*/\1/' | awk '{ total += $1 } END { print total + 0 }')
    # A filtered run has no fixed number of "Test run with" lines.
    if [ "${#TEST_ARGS[@]}" -gt 0 ]; then EXPECTED_TEST_RUNS=$runs; fi
    if [ "$status" -ne 0 ] || grep -qE "recorded an issue|failed after" <<<"$clean" || [ "$runs" -ne "$EXPECTED_TEST_RUNS" ]; then
        echo "Linux: FAIL (exit $status, $runs of $EXPECTED_TEST_RUNS 'Test run with' lines; log: $LOG)" >&2
        return 1
    fi
    echo "Linux: PASS ($runs 'Test run with' lines, ${tests:-0} tests; log: $LOG)"
}

case $step in
    build) do_build ;;
    test) do_test ;;
    smoke) do_smoke ;;
    all) do_build && do_test && do_smoke ;;
    *) echo "usage: scripts/linux-test.sh [build|test|smoke|all|clean]" >&2; exit 64 ;;
esac
```

- [ ] **Step 5: Build the image and the app on Linux, then run the OCCT suites**

```bash
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh build            # the first run builds OpenCascade (about 13 minutes with 6 jobs here); Task 3 makes the package use it
docker run --rm "$IMAGE" sh -c 'ls /opt/occt/lib/libTKDESTEP.so.7.9.3 /opt/occt/share/licenses; ldconfig -p | grep -c TKernel; readelf -d /opt/occt/lib/libTKDESTEP.so.7.9.3 | grep RUNPATH'
```
Expected: the library and the two licence files are listed; `ldconfig -p | grep -c` prints `0` (no ld.so entry: the check that rpaths do the work); `RUNPATH … [$ORIGIN]`.
(The OCCT tests themselves cannot run on Linux until Task 3 declares the targets there.)

Also check CI's route works here: build the stage alone and hand it over —

```bash
docker build -q --target occt -t metalcreator-occt:xp2 -f scripts/linux/Dockerfile scripts/linux   # a cache hit
OCCT_IMAGE=metalcreator-occt:xp2 IMAGE=metalcreator-linux:xp-2-prebuilt scripts/linux-test.sh build
docker run --rm metalcreator-linux:xp-2-prebuilt ls /opt/occt/lib | head -3
```
Expected: `cmake`, `libTKBO.so`, `libTKBO.so.7.9` (measured: both builds took about 20 s from the cache).

- [ ] **Step 6: Lint, commit**

```bash
swiftlint lint --strict --quiet; bash -n scripts/linux-test.sh
git add scripts/linux scripts/linux-test.sh Tests/CreatorAppTests/PackagingScriptTests.swift
git commit -m "build(linux): image with OpenCascade 7.9.3 built from a pinned commit; linux-test.sh takes IMAGE, OCCT_IMAGE and test arguments, expects 12 runs" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **0** (the parameterised `theScriptParsesAndIsExecutable` gains an argument).

---

### Task 3: Per-OS OpenCascade in the manifest; `CreatorOCCT` everywhere

**Files:**
- Modify: `Package.swift`
- Modify: `Tests/CreatorOCCTTests/ShimPortabilityTests.swift` (the `NOMINMAX` test and the debug/release link test)
- Modify: `Tests/CreatorViewportTests/OffscreenRenderTests.swift`, `Tests/CreatorViewportTests/GuideRenderTests.swift` (line 1)

**Design.** `occtPrefix` is `Context.environment["OCCT_PREFIX"]` or a per-OS default (macOS Homebrew's, Linux `/opt/occt`, Windows `C:/occt`; verified: `OCCT_PREFIX=/zzz/occt swift package dump-package` shows `/zzz/occt` in all six flag lists). `COCCT`'s `cxxSettings` and `linkerSettings` carry the flags; the linker flags are three `unsafeFlags(…, .when(platforms:))`: macOS `-L<prefix>/lib -rpath <prefix>/lib` (as before); Linux `-L<prefix>/lib -rpath $ORIGIN/lib -rpath <prefix>/lib` (the first so a tarball finds its `lib/`, the second so `swift test` finds the image's OpenCascade; measured `RUNPATH […:$ORIGIN/lib:/opt/occt/lib]`); Windows `-L<prefix>/debug/lib` for a debug build and `-L<prefix>/lib` for a release build (`.when(platforms: [.windows], configuration: …)`; vcpkg's `x64-windows` triplet installs both sets, so the debug suite meets OpenCascade built with the same C runtime, user decision 8; no rpath exists, the DLLs come from `PATH` (`debug\bin`) or sit beside the executable). Verified here: `swift package dump-package` shows the four lists with their conditions (`macos`; `linux`; `windows` + `debug`; `windows` + `release`). `.define("NOMINMAX", .when(platforms: [.windows]))` stops `<windows.h>` (pulled in by OCCT's headers) from defining `min`/`max`, which the shim's `std::min`/`std::max` calls would not survive. `ViewportHarness` and `GraphPanelPreview` stay in the macOS block.

**A finding from running it on Linux.** Two viewport tests were gated only by `canImport(CreatorOCCT)` but `import Metal`. That was true only on macOS; on Linux, once OpenCascade exists, they fail to compile. They become `canImport(Metal) && canImport(CreatorOCCT)`. Every other `canImport(CreatorOCCT)` test (bracket acceptance, Mesh to Solid, the kernel and app acceptance tests, the benches' fixtures) compiled and passed unchanged on Linux.

**Interfaces:**
- Consumes: the image from Task 2 (`/opt/occt`).
- Produces: `occt` (`["CreatorOCCT"]`), `occtPrefix`, `occtLibraries`, `occtLinkerFlags` in `Package.swift`; the OCCT suites run on Linux (`CreatorOCCTTests` is the twelfth "Test run with" line).

- [ ] **Step 1: Write the failing test**

Append to `Tests/CreatorOCCTTests/ShimPortabilityTests.swift`, before the `repository` property:

```swift
    /// OCCT's headers pull in <windows.h> on Windows, whose `min` and `max` macros break `std::min(a, b)`.
    @Test func theManifestDefinesNOMINMAXOnWindows() throws {
        let manifest = try String(contentsOf: Self.repository.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains(#".define("NOMINMAX", .when(platforms: [.windows]))"#))
    }

    /// A debug build (`swift test`) links vcpkg's debug libraries and a release build its release ones, so the C runtime of the
    /// shim and of OpenCascade's DLLs is the same one in each (user decision 8). The workflow installs both sets (`CIPinTests`).
    @Test func theManifestLinksAWindowsDebugBuildAgainstTheDebugLibraries() throws {
        let manifest = try String(contentsOf: Self.repository.appending(path: "Package.swift"), encoding: .utf8)
        #expect(manifest.contains(#".unsafeFlags(["-L\(occtPrefix)/debug/lib"], .when(platforms: [.windows], configuration: .debug))"#))
        #expect(manifest.contains(#".unsafeFlags(["-L\(occtPrefix)/lib"], .when(platforms: [.windows], configuration: .release))"#))
    }

```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter ShimPortabilityTests 2>&1 | grep -E "recorded an issue|Test run"`
Expected: FAIL — `theManifestDefinesNOMINMAXOnWindows` (the manifest has no such define) and `theManifestLinksAWindowsDebugBuildAgainstTheDebugLibraries`.
Run: `scripts/linux-test.sh test --filter CreatorOCCTTests 2>&1 | tail -3` (with `IMAGE`/`XP_TRACK` as in Task 2)
Expected: `Linux: FAIL` (the filter matches no test: the target is not declared on Linux).

- [ ] **Step 3: Edit `Package.swift`**

```diff
diff --git a/Package.swift b/Package.swift
index df5d8b7..13aa021 100644
--- a/Package.swift
+++ b/Package.swift
@@ -2,8 +2,8 @@
 import PackageDescription
 
 // Two lists, like MetalUI's manifest (cross-platform spec §2.1, PC-A). The first holds the targets that import no Apple
-// framework (a file that needs Metal gates itself with `#if canImport(Metal)`); they are declared on every platform. The
-// second holds what needs OpenCascade (Homebrew's, macOS only until xp-2) and the two dev windows, declared on macOS only.
+// framework (a file that needs Metal gates itself with `#if canImport(Metal)`) and, since xp-2, the OpenCascade shim and its
+// kernel; they are declared on every platform. The second holds the two dev windows, declared on macOS only.
 
 /// MetalUI's SDL backend and AccessKit are traits, asked for on Linux and Windows only (MetalUI `getting-started.md`,
 /// "Linux and Windows"): a macOS build never needs SDL.
@@ -29,12 +29,21 @@ let metalUISystemFonts: Target.Dependency = .product(name: "MetalUISystemFonts",
 /// The SDL3 backend, on Linux and Windows only.
 let metalUISDL: Target.Dependency = .product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))
 
-/// The OpenCascade kernel, a dependency only where the target is declared (macOS, until xp-2).
-#if os(macOS)
+/// The OpenCascade kernel (xp-2): a dependency on every platform.
 let occt: [Target.Dependency] = ["CreatorOCCT"]
+
+/// Where OpenCascade 7.9 is installed on this machine: `include/opencascade` and `lib`, under one prefix. Set `OCCT_PREFIX` to
+/// use another. The defaults are Homebrew's `opencascade` formula (macOS, which ships CMake configs but no pkg-config file, so
+/// the shim is pointed at it directly), the prefix the Linux test image builds into (`scripts/linux/Dockerfile`), and vcpkg's
+/// `x64-windows` install root as `.github/workflows/xp.yml` makes it (`packaging/windows/vcpkg.json`; `debug/lib` beside `lib`).
+#if os(macOS)
+let occtDefaultPrefix = "/opt/homebrew/opt/opencascade"
+#elseif os(Windows)
+let occtDefaultPrefix = "C:/occt"
 #else
-let occt: [Target.Dependency] = []
+let occtDefaultPrefix = "/opt/occt"
 #endif
+let occtPrefix = Context.environment["OCCT_PREFIX"] ?? occtDefaultPrefix
 
 var targets: [Target] = [
     .target(name: "CreatorGeometry"),
@@ -117,25 +126,46 @@ var targets: [Target] = [
     ),
 ]
 
-#if os(macOS)
-/// Homebrew's OpenCascade install. The bottle ships CMake configs but no pkg-config file,
-/// so the shim is pointed at it directly. Only the COCCT target uses these flags.
-let occtPrefix = "/opt/homebrew/opt/opencascade"
+/// The OpenCascade toolkits the shim and the data exchange link, in the same order on every platform.
 let occtLibraries = [
     "TKernel", "TKMath", "TKG2d", "TKG3d", "TKGeomBase", "TKGeomAlgo", "TKBRep", "TKTopAlgo",
     "TKPrim", "TKBO", "TKBool", "TKFillet", "TKOffset", "TKMesh", "TKShHealing",
     "TKXSBase", "TKDE", "TKDESTEP", "TKDESTL",
 ]
 
+/// The linker flags per target platform (xp-2, spec section 3). macOS and Linux add the install's `lib` to the run-time search
+/// path, so `swift run` and `swift test` find the libraries; Linux also searches `lib` beside the executable first
+/// (`$ORIGIN/lib`, where `scripts/package-linux.sh` puts them). Windows has no rpath: the DLLs are found on `PATH` (CI adds the
+/// install's `debug/bin`, or `bin` for a release build) or beside the executable (`scripts/package-windows.ps1`).
+let occtLinkerFlags: [LinkerSetting] = [
+    .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"], .when(platforms: [.macOS])),
+    .unsafeFlags(
+        ["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"],
+        .when(platforms: [.linux])
+    ),
+    // vcpkg's `x64-windows` triplet installs the release libraries in `lib` and `bin` and the debug ones in `debug/lib` and
+    // `debug/bin`. A debug build (`swift test`) links the debug set, so Swift's and the shim's debug C runtime meets OpenCascade
+    // built with the same one; a release build (the zip) links the release set.
+    .unsafeFlags(["-L\(occtPrefix)/debug/lib"], .when(platforms: [.windows], configuration: .debug)),
+    .unsafeFlags(["-L\(occtPrefix)/lib"], .when(platforms: [.windows], configuration: .release)),
+]
+
 targets += [
     .target(
         name: "COCCT",
-        cxxSettings: [.unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"])],
-        linkerSettings: [
-            .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"]),
-        ] + occtLibraries.map { .linkedLibrary($0) }
+        cxxSettings: [
+            .unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"]),
+            // OCCT's headers include <windows.h>, whose min and max macros break std::min and std::max.
+            .define("NOMINMAX", .when(platforms: [.windows])),
+        ],
+        linkerSettings: occtLinkerFlags + occtLibraries.map { .linkedLibrary($0) }
     ),
     .target(name: "CreatorOCCT", dependencies: ["COCCT", "CreatorKernel", "CreatorGeometry"]),
+    .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
+]
+
+#if os(macOS)
+targets += [
     // A dev window for the viewport's human checks (docs/verification/human-checks.md, group V). Not the app (M6).
     .executableTarget(name: "ViewportHarness",
                       dependencies: ["CreatorViewport", "CreatorOCCT", "CreatorKernel", "CreatorGeometry", metalUI]),
@@ -143,7 +173,6 @@ targets += [
         name: "GraphPanelPreview",
         dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
     ),
-    .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
 ]
 #endif
 
```

- [ ] **Step 4: Fix the two viewport tests' gate**

In `Tests/CreatorViewportTests/OffscreenRenderTests.swift` and `GuideRenderTests.swift`, change line 1 from `#if canImport(CreatorOCCT)` to:

```swift
#if canImport(Metal) && canImport(CreatorOCCT)
```

- [ ] **Step 5: Verify on the Mac**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning: building for macOS"` — expected: no output.
Run: `swift test --filter "ShimPortabilityTests|CreatorOCCTTests|OffscreenRenderTests|GuideRenderTests" 2>&1 | grep -E "recorded an issue|Test run"` — expected: PASS (macOS is unchanged: the manifest resolves `/opt/homebrew/opt/opencascade`).

- [ ] **Step 6: Verify on Linux (Docker)**

```bash
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh build
docker run --rm -v xp-2-linux-build:/build "$IMAGE" bash -c 'b=$(find /build -name MetalCreatorApp -type f | head -1); readelf -d $b | grep RUNPATH; ldd $b | grep -c "TK.*/opt/occt"'
scripts/linux-test.sh test --filter CreatorOCCTTests
```
Expected: `RUNPATH … $ORIGIN/lib:/opt/occt/lib`; the `ldd` count is non-zero; `Linux: PASS (1 'Test run with' lines, 197 tests …)` — all of `CreatorOCCTTests`' 197 tests, including the distance fast-path suites that use OCCT's thread pool, pass on Linux.

- [ ] **Step 7: Lint, commit**

```bash
swiftlint lint --strict --quiet
git add Package.swift Tests/CreatorOCCTTests/ShimPortabilityTests.swift Tests/CreatorViewportTests
git commit -m "build: OpenCascade on every platform; per-OS linker flags, OCCT_PREFIX, NOMINMAX; CreatorOCCT and its tests are portable" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **+2** (`theManifestDefinesNOMINMAXOnWindows`, `theManifestLinksAWindowsDebugBuildAgainstTheDebugLibraries`). `CreatorOCCTTests` becomes a Linux and Windows "Test run with" line: **Linux 11 → 12**.

---

### Task 4: The app uses `OCCTKernel` on every platform

**Files:**
- Modify: `Sources/MetalCreatorApp/main.swift` (imports, `makeKernel`)
- Modify: `Sources/CreatorKernel/KernelUnavailable.swift`, `Sources/CreatorApp/SelfTest.swift` (stale comments)
- Create: `Tests/CreatorOCCTTests/ExportPathTests.swift`

**What changes.** `main.swift` imported `CreatorOCCT` only under `canImport(CreatorOCCT)` and chose `KernelUnavailable()` otherwise. The module now exists everywhere, so the import is unconditional and `makeKernel()` is `OCCTKernel()`. `KernelUnavailable` stays in `CreatorKernel` (its tests and `KernelUnavailableAppTests` pin how the editor behaves without geometry, and a future platform may need it), but no longer ships as the app's kernel. `SelfTest` needs no code change: it takes the kernel as a parameter, and on Linux it now prints `ok kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles`, `ok STEP export: 15,435 bytes`, `ok STL export: 3,052 bytes` instead of three `skipped:` lines. Mesh to Solid works because `occt_mesh_to_solid` (`cocct_mesh_solid.cpp`) is in the shim.

**Review Focus 2.** The export test writes STEP and STL to `Teile Größe <uuid>/Halterung ü 日本.step`. It passes on macOS and Linux; on Windows it is the first check of whether OpenCascade 7.9.3 opens the UTF-8 path as UTF-8.

**Interfaces:**
- Consumes: Task 3 (`CreatorOCCT` builds everywhere).
- Produces: nothing new; `makeKernel() -> any Kernel` is `OCCTKernel()`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CreatorOCCTTests/ExportPathTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

/// The shim writes STEP and STL to the path it is handed as UTF-8 (`URL.withUnsafeFileSystemRepresentation`). OpenCascade opens
/// it as UTF-8 on Linux and macOS; on Windows an old build opened it as the ANSI code page, and a name with an accent or a
/// letter outside it failed (xp-2; CI is the only place that runs this on Windows).
struct ExportPathTests {
    @Test(arguments: ExportFormat.allCases)
    func aFileNamedWithSpacesAccentsAndKanjiIsWritten(_ format: ExportFormat) async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let folder = URL.temporaryDirectory.appending(path: "Teile Größe \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Halterung ü 日本.\(format.rawValue)")
        try await kernel.export([solid], format: format, to: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 0, "\(url.lastPathComponent) is empty or missing")
    }
}
```

(This test passes at once on the Mac and on Linux — it pins behaviour the next steps must not lose; it has no red state here because the shim already passes the UTF-8 path through. Its red state, if any, is Windows' and appears only in CI.)

- [ ] **Step 2: Run it**

Run: `swift test --filter ExportPathTests 2>&1 | grep -E "recorded an issue|Test run"` → PASS (1 test).
Run (Linux): `scripts/linux-test.sh test --filter ExportPathTests` → `Linux: PASS`.

- [ ] **Step 3: Edit `main.swift`**

Replace the conditional import:

```swift
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
#if canImport(MetalUISDL)
```

with

```swift
import CreatorOCCT
#if canImport(MetalUISDL)
```

and replace `makeKernel`:

```swift
/// OpenCascade where the package has it (macOS until xp-2); elsewhere a kernel that says geometry isn't available.
func makeKernel() -> any Kernel {
    #if canImport(CreatorOCCT)
    OCCTKernel()
    #else
    KernelUnavailable()
    #endif
}
```

with

```swift
/// OpenCascade on every platform (macOS's Homebrew, Linux's source build, Windows' vcpkg: `Package.swift`, xp-2).
func makeKernel() -> any Kernel {
    OCCTKernel()
}
```

- [ ] **Step 4: Update the two stale comments**

`Sources/CreatorKernel/KernelUnavailable.swift`, line 4:

```swift
/// The kernel of a build with no OpenCascade (Linux and Windows in xp-1; since xp-2 the app uses `OCCTKernel` everywhere, and
/// this stays for tests of how the editor behaves without geometry): every operation answers
```

`Sources/CreatorApp/SelfTest.swift`, the comment above `let kernelSkipped`:

```swift
        // A kernel that says geometry isn't available (`KernelUnavailable`; the app itself has OpenCascade everywhere since xp-2) skips the checks that need one.
```

- [ ] **Step 5: Build, run the self-test and the app-level suites**

```bash
swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning: building for macOS"      # no output
swift test --filter "SelfTestTests|KernelUnavailable|ExportPathTests" 2>&1 | grep -E "recorded an issue|Test run"
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh build && scripts/linux-test.sh smoke
```
Expected: PASS; the smoke run prints `ok kernel: a 10 mm cube, 1000 mm³, meshed into 12 triangles`, `ok STEP export: 15,435 bytes`, `ok STL export: 3,052 bytes`, `ok shaders: MetalUI's SDL shaders were found`, and `MetalCreator smoke test: reached the first frame, ran 20 s.`

- [ ] **Step 6: The whole suite on Linux (one run)**

Run: `scripts/linux-test.sh test`
Expected: `Linux: PASS (12 'Test run with' lines, N tests …)`. (Measured with Tasks 1 to 6 applied: 12 lines, 4,530 tests. Everything that `canImport(CreatorOCCT)` gated — `AppAcceptanceTests`, the bracket, face-pick and merged-face acceptance suites, `HolePatternNodeTests`, `PlaceBracketTests`, `FieldsAcceptanceTests`, `SelfTestTests`, `LayoutPreviewTests`' OCCT cases — now runs here and passes.)

- [ ] **Step 7: Lint, commit**

```bash
swiftlint lint --strict --quiet
git add Sources/MetalCreatorApp/main.swift Sources/CreatorKernel/KernelUnavailable.swift Sources/CreatorApp/SelfTest.swift Tests/CreatorOCCTTests/ExportPathTests.swift
git commit -m "feat(app): OCCTKernel on Linux and Windows; export to non-ASCII paths pinned" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **+1** (`aFileNamedWithSpacesAccentsAndKanjiIsWritten`, parameterised over STEP and STL).

---

### Task 5: Open documents on Linux and Windows (gap XP-G5)

**Files:**
- Modify: `Sources/CreatorApp/LaunchCommand.swift`, `Sources/CreatorApp/AppBundleInfo.swift`, `Sources/MetalCreatorApp/main.swift`
- Create: `packaging/linux/com.metalcreator.MetalCreator.desktop`, `packaging/linux/com.metalcreator.MetalCreator.xml`, `packaging/linux/com.metalcreator.MetalCreator.png` (a placeholder icon), `packaging/linux/install.sh`, `packaging/windows/register-mcgraph.ps1`
- Modify: `Tests/CreatorAppTests/LaunchCommandTests.swift`, `Tests/CreatorAppTests/PackagingScriptTests.swift`
- Create: `Tests/CreatorAppTests/DesktopEntryTests.swift`, `Tests/CreatorAppTests/InstallScriptTests.swift`

**What MetalUI already answers (XP-G5), and what is left.** `main.swift` already sets `app.onOpenURL` before `app.run()`, so an SDL drop on the application itself (`Platform.onOpenURLs` with window 0, MetalUI routes it to `.onOpenURL`) and a second launch's forwarded documents (MetalUI S7, `SDLPlatform.launchingSingleInstance`, already adopted) both reach `AppModel.openRequested(_:)`; that needs no code. What xp-2 adds: (1) the command line takes every document, because a Linux file manager runs `Exec=… %F` with all selected files and Explorer runs `"%1"`; (2) a desktop entry with `MimeType=` and `Icon=`, a shared-mime-info file mapping `*.mcgraph` and a placeholder icon (the tarball's entry and the AppImage's are this one file); (3) `install.sh` registering all three for the current user; (4) `register-mcgraph.ps1` for Windows. `LaunchCommand` takes the leading run of non-flag arguments (`-psn_…` and `-NS… value` stay the system's: everything from the first `-` argument on is not a document). The run opens each file in turn and the last stays open, as on macOS (user decision 5).

**Interfaces:**
- Consumes: Task 4's `main.swift`.
- Produces: `LaunchCommand.run(paths: [String])`, `LaunchCommand.forwardedDocuments(paths:exists:)`, `AppBundleInfo.mimeType`; the files under `packaging/`.

- [ ] **Step 1: Write the failing tests**

(a) In `Tests/CreatorAppTests/LaunchCommandTests.swift` replace the four uses of `.run(path:)` and the two tests after `helpPrintsTheUsage…`:

```diff
diff --git a/Tests/CreatorAppTests/LaunchCommandTests.swift b/Tests/CreatorAppTests/LaunchCommandTests.swift
index 45f42ca..ff208f8 100644
--- a/Tests/CreatorAppTests/LaunchCommandTests.swift
+++ b/Tests/CreatorAppTests/LaunchCommandTests.swift
@@ -5,6 +5,6 @@ import Testing
 struct LaunchCommandTests {
     @Test func noArgumentsOpensAnEmptyWindowAndAPathOpensThatFile() {
-        #expect(LaunchCommand(arguments: []) == .run(path: nil))
-        #expect(LaunchCommand(arguments: ["bracket.mcgraph"]) == .run(path: "bracket.mcgraph"))
+        #expect(LaunchCommand(arguments: []) == .run(paths: []))
+        #expect(LaunchCommand(arguments: ["bracket.mcgraph"]) == .run(paths: ["bracket.mcgraph"]))
     }
 
@@ -50,5 +50,5 @@ struct LaunchCommandTests {
     @Test(arguments: [["-psn_0_1234567"], ["-NSDocumentRevisionsDebugMode", "YES"], ["-AppleLanguages", "(de)"]])
     func theSystemsOwnArgumentsOpenAnEmptyWindow(_ arguments: [String]) {
-        #expect(LaunchCommand(arguments: arguments) == .run(path: nil))
+        #expect(LaunchCommand(arguments: arguments) == .run(paths: []))
     }
 
@@ -65,14 +65,23 @@ struct LaunchCommandTests {
     }
 
-    /// Only the first file is opened; later arguments (Xcode appends its own after the file) are not files.
-    @Test func argumentsAfterTheFileAreIgnored() {
-        #expect(LaunchCommand(arguments: ["a.mcgraph", "b.mcgraph"]) == .run(path: "a.mcgraph"))
-        #expect(LaunchCommand(arguments: ["a.mcgraph", "-NSDocumentRevisionsDebugMode", "YES"]) == .run(path: "a.mcgraph"))
+    /// A Linux file manager runs `MetalCreator %F` and Explorer `MetalCreator.exe "%1"`: every leading argument is a document
+    /// (xp-2, gap XP-G5). The app opens each in turn and the last stays open. Arguments from the first flag on (Xcode appends
+    /// its own after the file) are not files.
+    @Test func everyLeadingArgumentIsADocumentAndTheFirstFlagEndsThem() {
+        #expect(LaunchCommand(arguments: ["a.mcgraph", "b.mcgraph"]) == .run(paths: ["a.mcgraph", "b.mcgraph"]))
+        #expect(LaunchCommand(arguments: ["a.mcgraph", "-NSDocumentRevisionsDebugMode", "YES"]) == .run(paths: ["a.mcgraph"]))
     }
 
-    @Test func onlyAnExistingDocumentIsForwardedToTheRunningInstance() {
-        #expect(LaunchCommand.forwardedDocuments(path: "a.mcgraph") { _ in true } == ["a.mcgraph"])
-        #expect(LaunchCommand.forwardedDocuments(path: "gone.mcgraph") { _ in false }.isEmpty)
-        #expect(LaunchCommand.forwardedDocuments(path: nil) { _ in true }.isEmpty)
+    /// Review focus: a path with spaces or non-ASCII letters arrives as one argument and stays one document.
+    @Test func aPathWithSpacesAndAccentsIsOneDocument() {
+        let path = "/home/zoë/My Parts/Halterung Größe 2.mcgraph"
+        #expect(LaunchCommand(arguments: [path]) == .run(paths: [path]))
+    }
+
+    @Test func onlyExistingDocumentsAreForwardedToTheRunningInstance() {
+        let existing: Set<String> = ["a.mcgraph", "b.mcgraph"]
+        #expect(LaunchCommand.forwardedDocuments(paths: ["a.mcgraph", "gone.mcgraph", "b.mcgraph"]) { existing.contains($0) }
+            == ["a.mcgraph", "b.mcgraph"])
+        #expect(LaunchCommand.forwardedDocuments(paths: []) { _ in true }.isEmpty)
     }
 }
```

(b) Create `Tests/CreatorAppTests/DesktopEntryTests.swift`:

```swift
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// Linux and Windows open `.mcgraph` files through the files in `packaging/` (cross-platform spec section 5, gap XP-G5): the
/// desktop entry runs `MetalCreator %F` and names the MIME type, the shared-mime-info file maps `*.mcgraph` to it, and the
/// Windows script registers the same extension. They are text, so these tests hold them to the names the app itself declares
/// (`AppBundleInfo`, `ContentType.mcgraph`); what a desktop then does with them is human checks XP-16, XP-17 and XP-19.
struct DesktopEntryTests {
    @Test func theEntryHandsTheFileManagersFilesToTheAppAndNamesTheType() throws {
        let entry = try Self.desktopEntry()
        #expect(entry["Type"] == "Application")
        #expect(entry["Name"] == AppBundleInfo.name)
        #expect(entry["Exec"] == "\(AppBundleInfo.executableName) %F", "%F: every selected file, as local paths")
        #expect(entry["MimeType"] == "\(AppBundleInfo.mimeType);")
        #expect(entry["StartupWMClass"] == AppBundleInfo.identifier)
        #expect(entry["Icon"] == AppBundleInfo.identifier, "an icon theme name: the file in hicolor is named after it")
        #expect(entry["Terminal"] == "false")
    }

    /// XP-G13, fixed in MetalUI master `b39d68d6`: MetalUI hands SDL the id `launchingSingleInstance(id:)` is given as the
    /// `SDL_APP_ID` hint, so the window's Wayland `app_id` / X11 `WM_CLASS` is `AppBundleInfo.identifier` with no code of ours. The
    /// entry's `StartupWMClass` must be that id, and nothing may override or work around it (an `applicationID:` option, a `setenv`,
    /// an `env SDL_APP_ID=` in the entry). A desktop shell showing the right icon and grouping is human check XP-16.
    @Test func theWindowClassIsTheApplicationIDTheAppHandsToMetalUI() throws {
        let entry = try Self.desktopEntry()
        #expect(entry["StartupWMClass"] == AppBundleInfo.identifier)
        #expect(AppBundleInfo.identifier == "com.metalcreator.MetalCreator", "the entry is named after it: com.metalcreator.MetalCreator.desktop")
        let main = try Self.text("Sources/MetalCreatorApp/main.swift")
        #expect(main.contains("launchingSingleInstance(id: AppBundleInfo.identifier"), "the id MetalUI turns into SDL_APP_ID")
        #expect(!main.contains("applicationID:") && !main.contains("SDL_APP_ID") && !main.contains("setenv"), "no override, no workaround")
        #expect(!(entry["Exec"] ?? "").contains("SDL_APP_ID"))
    }

    /// The icon the entry names is a file of the repository: a 256 x 256 PNG, which the tarball puts in hicolor's `256x256/apps` and
    /// the AppImage at its root.
    @Test func theIconIsA256PixelPNGNamedAfterTheEntry() throws {
        let bytes = try Self.bytes("packaging/linux/\(AppBundleInfo.identifier).png")
        #expect(Array(bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "a PNG (and not rewritten by a line-ending rule)")
        func bigEndian(_ range: Range<Int>) -> Int { bytes[range].reduce(0) { $0 << 8 | Int($1) } }
        #expect(bigEndian(16..<20) == 256 && bigEndian(20..<24) == 256, "IHDR: width and height")
    }

    @Test func theMimeTypeGlobsTheDocumentExtensionTheFilePanelsUse() throws {
        let xml = try Self.text("packaging/linux/\(AppBundleInfo.identifier).xml")
        let ext = try #require(ContentType.mcgraph.preferredFilenameExtension)
        #expect(xml.contains(#"<mime-type type="\#(AppBundleInfo.mimeType)">"#))
        #expect(xml.contains(#"<glob pattern="*.\#(ext)"/>"#))
        #expect(xml.contains("<comment>\(AppBundleInfo.documentTypeName)</comment>"))
        #expect(xml.contains(#"<sub-class-of type="application/json"/>"#), "the document is JSON, as its macOS type says")
    }

    @Test func theWindowsScriptRegistersTheSameExtensionAndPassesTheFileAsTheArgument() throws {
        let script = try Self.text("packaging/windows/register-mcgraph.ps1")
        let ext = try #require(ContentType.mcgraph.preferredFilenameExtension)
        #expect(script.contains("\\.\(ext)"))
        #expect(script.contains(#""`"$exe`" `"%1`"""#), "shell\\open\\command is \"MetalCreator.exe\" \"%1\"")
        #expect(script.contains("MetalCreator.exe"))
    }

    /// A file of the repository as bytes.
    private static func bytes(_ path: String) throws -> [UInt8] {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [UInt8](try Data(contentsOf: repository.appending(path: path)))
    }

    /// The entry's `[Desktop Entry]` group as key-value pairs.
    private static func desktopEntry() throws -> [String: String] {
        let text = try Self.text("packaging/linux/\(AppBundleInfo.identifier).desktop")
        var pairs: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("[") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { pairs[String(parts[0])] = String(parts[1]) }
        }
        return pairs
    }

    /// A file of the repository as text (`Tests/CreatorAppTests/DesktopEntryTests.swift` is three levels down), with "\r\n" read as
    /// "\n": Swift counts "\r\n" as one Character, so a Windows checkout with CRLF would never split into lines.
    private static func text(_ path: String) throws -> String {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }
}
```

(c) Create `Tests/CreatorAppTests/InstallScriptTests.swift`:

```swift
import Foundation
import Testing

#if !os(Windows)  // bash scripts: Windows has no /bin/bash
/// `packaging/linux/install.sh` registers an unpacked tarball with the desktop (gap XP-G5). Each test lays out a folder like the
/// tarball's (the script, the desktop entry, the MIME file and the icon), runs the script with `XDG_DATA_HOME` pointed at a scratch folder,
/// and reads what it wrote. The scratch folder's name has a space in it: a folder the person unpacked into "My Parts".
struct InstallScriptTests {
    /// What running the script did.
    struct Run {
        let status: Int32
        let data: URL
        let folder: URL
        var desktopEntry: String? { try? String(contentsOf: data.appending(path: "applications/\(Self.id).desktop"), encoding: .utf8) }
        var mimeFileExists: Bool { FileManager.default.fileExists(atPath: data.appending(path: "mime/packages/\(Self.id).xml").path) }
        var iconExists: Bool {
            FileManager.default.fileExists(atPath: data.appending(path: "icons/hicolor/256x256/apps/\(Self.id).png").path)
        }
        static let id = "com.metalcreator.MetalCreator"
    }

    @Test func theEntryIsInstalledWithTheFoldersOwnQuotedPath() throws {
        let run = try Self.run([], folderName: "My Parts")
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 0)
        let entry = try #require(run.desktopEntry)
        // The script writes the physical path (`pwd -P`), which on a Mac differs from the temporary folder's spelling.
        #expect(entry.contains("\nExec=\"/") && entry.contains("/My Parts/MetalCreator\" %F\n"), "an absolute path, quoted, and %F kept")
        #expect(entry.contains("MimeType=application/x-metalcreator-graph;\n"))
        #expect(run.mimeFileExists)
        #expect(entry.contains("\nIcon=com.metalcreator.MetalCreator\n") && run.iconExists, "the icon the entry names is installed in hicolor")
    }

    /// Review focus: in a quoted Exec argument a percent sign starts a field code, so the path's own one is written `%%`.
    @Test func aPercentSignInTheFoldersNameIsWrittenDoubled() throws {
        let run = try Self.run([], folderName: "100% parts")
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 0)
        let entry = try #require(run.desktopEntry)
        #expect(entry.contains("/100%% parts/MetalCreator\" %F\n"), "%% in the path, the real %F kept")
    }

    @Test func removeTakesTheInstalledFilesAway() throws {
        let installed = try Self.run([], folderName: "Parts")
        defer { try? FileManager.default.removeItem(at: installed.folder.deletingLastPathComponent()) }
        #expect(installed.desktopEntry != nil && installed.mimeFileExists && installed.iconExists)
        let removed = try Self.run(["--remove"], reusing: installed)
        #expect(removed.status == 0)
        #expect(removed.desktopEntry == nil && !removed.mimeFileExists && !removed.iconExists)
    }

    /// Review focus: a folder whose name an Exec line can't hold is refused, not written as a broken entry.
    @Test(arguments: ["a$b", "a&b", "a|b", "a`b"])
    func aFolderNameTheEntryCannotHoldIsRefused(_ name: String) throws {
        let run = try Self.run([], folderName: name)
        defer { try? FileManager.default.removeItem(at: run.folder.deletingLastPathComponent()) }
        #expect(run.status == 1)
        #expect(run.desktopEntry == nil)
    }

    // MARK: Fixture

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Lays out `<scratch>/<folderName>/` like the tarball and runs `install.sh arguments` from it.
    private static func run(_ arguments: [String], folderName: String) throws -> Run {
        let scratch = URL.temporaryDirectory.appending(path: "install-script-\(UUID().uuidString)")
        let folder = scratch.appending(path: folderName)
        let fileManager = FileManager.default
        for directory in ["share/applications", "share/mime/packages", "share/icons/hicolor/256x256/apps"] {
            try fileManager.createDirectory(at: folder.appending(path: directory), withIntermediateDirectories: true)
        }
        let id = Run.id
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/install.sh"), to: folder.appending(path: "install.sh"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).desktop"),
                                 to: folder.appending(path: "share/applications/\(id).desktop"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).xml"),
                                 to: folder.appending(path: "share/mime/packages/\(id).xml"))
        try fileManager.copyItem(at: repository.appending(path: "packaging/linux/\(id).png"),
                                 to: folder.appending(path: "share/icons/hicolor/256x256/apps/\(id).png"))
        return try run(arguments, reusing: Run(status: 0, data: scratch.appending(path: "data"), folder: folder))
    }

    private static func run(_ arguments: [String], reusing previous: Run) throws -> Run {
        let bash = Process()
        bash.executableURL = URL(filePath: "/bin/bash")
        bash.arguments = [previous.folder.appending(path: "install.sh").path] + arguments
        bash.environment = ["XDG_DATA_HOME": previous.data.path, "PATH": "/usr/bin:/bin", "HOME": previous.data.path]
        bash.standardOutput = FileHandle.nullDevice
        bash.standardError = FileHandle.nullDevice
        try bash.run()
        bash.waitUntilExit()
        return Run(status: bash.terminationStatus, data: previous.data, folder: previous.folder)
    }
}
#endif
```

(d) In `Tests/CreatorAppTests/PackagingScriptTests.swift` add `"packaging/linux/install.sh"` to the arguments of `theScriptParsesAndIsExecutable`.

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep "error:" | head -5`
Expected: FAIL to compile — `type 'LaunchCommand' has no member 'run(paths:)'`-style errors and `type 'AppBundleInfo' has no member 'mimeType'` (measured).

- [ ] **Step 3: Implement `LaunchCommand` and `AppBundleInfo`**

```diff
diff --git a/Sources/CreatorApp/LaunchCommand.swift b/Sources/CreatorApp/LaunchCommand.swift
index 2b03af3..426132b 100644
--- a/Sources/CreatorApp/LaunchCommand.swift
+++ b/Sources/CreatorApp/LaunchCommand.swift
@@ -3,8 +3,9 @@
 /// can use the packaged binary headlessly.
 public enum LaunchCommand: Equatable, Sendable {
-    /// Open the window, and the `.mcgraph` file at `path` if one is named (the first argument; any after it are
-    /// ignored). The file is handed to the app as Finder would (`App.open`, then `AppModel.openRequested(_:)`), so it
-    /// gets the same unsaved-changes check.
-    case run(path: String?)
+    /// Open the window, and the `.mcgraph` files at `paths`: every argument up to the first one that starts with "-" (a Linux
+    /// file manager runs `MetalCreator %F` with all the selected files, Explorer `MetalCreator.exe "%1"`; Xcode appends its own
+    /// flags after the file). Each file is handed to the app as Finder would (`App.open`, then `AppModel.openRequested(_:)`), so
+    /// it gets the same unsaved-changes check, and the last one stays open.
+    case run(paths: [String])
     /// `--version`: print ``AppBundleInfo/versionLine``.
     case version
@@ -15,9 +16,8 @@ public enum LaunchCommand: Equatable, Sendable {
     /// `--info-plist <minimum macOS>`: print the bundle's `Info.plist` (``AppBundleInfo``).
     case infoPlist(minimumSystemVersion: String)
-    /// The documents a second launch hands to the running instance (Linux and Windows): the path `run(path:)` names, when
-    /// `exists` says there is a file there, which is what the app opens from its own command line.
-    public static func forwardedDocuments(path: String?, exists: (String) -> Bool) -> [String] {
-        guard let path, exists(path) else { return [] }
-        return [path]
+    /// The documents a second launch hands to the running instance (Linux and Windows): the paths `run(paths:)` names that
+    /// `exists` says are files, in order.
+    public static func forwardedDocuments(paths: [String], exists: (String) -> Bool) -> [String] {
+        paths.filter(exists)
     }
 
@@ -40,5 +40,5 @@ public enum LaunchCommand: Equatable, Sendable {
     public init(arguments: [String]) {
         guard let first = arguments.first else {
-            self = .run(path: nil)
+            self = .run(paths: [])
             return
         }
@@ -63,6 +63,6 @@ public enum LaunchCommand: Equatable, Sendable {
             } else {
                 // Anything else starting with "-" is the system's (a `-psn_…` process serial number, or an
-                // `-NSSomeDefault value` pair), not a file.
-                self = .run(path: first.hasPrefix("-") ? nil : first)
+                // `-NSSomeDefault value` pair), not a file; so is everything after it.
+                self = .run(paths: Array(arguments.prefix { !$0.hasPrefix("-") }))
             }
         }
```

```diff
diff --git a/Sources/CreatorApp/AppBundleInfo.swift b/Sources/CreatorApp/AppBundleInfo.swift
index 87b84ce..04fb18f 100644
--- a/Sources/CreatorApp/AppBundleInfo.swift
+++ b/Sources/CreatorApp/AppBundleInfo.swift
@@ -19,4 +19,7 @@ public enum AppBundleInfo {
     /// How Finder names a `.mcgraph` file's kind.
     public static let documentTypeName = "MetalCreator Graph"
+    /// The `.mcgraph` file's MIME type on Linux: the desktop entry's `MimeType=` and the shared-mime-info file in `packaging/linux`
+    /// (`DesktopEntryTests` holds both to this name).
+    public static let mimeType = "application/x-metalcreator-graph"
 
     /// What `--version` prints, e.g. `MetalCreator 0.1.0 (1)`.
```

- [ ] **Step 4: Create the packaging files**

`packaging/linux/com.metalcreator.MetalCreator.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=MetalCreator
GenericName=Parametric 3D modeller
Comment=Build solid models from a graph of nodes
Exec=MetalCreator %F
Icon=com.metalcreator.MetalCreator
Terminal=false
Categories=Graphics;3DGraphics;Engineering;
MimeType=application/x-metalcreator-graph;
StartupWMClass=com.metalcreator.MetalCreator
```

`packaging/linux/com.metalcreator.MetalCreator.png`: a **placeholder** (a 256 x 256 flat square in the Dracula background colour with a lighter square in its middle; not branding, to be replaced when the app has an icon, under the same file name). It is a committed binary, written once with this generator (`python3 -I`; standard library only; the run that wrote the plan's copy produced a 992-byte file):

```python
import struct, zlib
w = h = 256
rows = b"".join(b"\x00" + b"".join(bytes([189, 147, 249, 255]) if 64 <= x < 192 and 64 <= y < 192 else bytes([40, 42, 54, 255])
                                     for x in range(w)) for y in range(h))
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))
open("packaging/linux/com.metalcreator.MetalCreator.png", "wb").write(png)
```

`packaging/linux/com.metalcreator.MetalCreator.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-metalcreator-graph">
    <comment>MetalCreator Graph</comment>
    <sub-class-of type="application/json"/>
    <glob pattern="*.mcgraph"/>
  </mime-type>
</mime-info>
```

`packaging/linux/install.sh` (then `chmod +x packaging/linux/install.sh`):

```bash
#!/bin/bash
# Registers this MetalCreator folder with the desktop for the current user: a launcher entry that opens .mcgraph files
# (Exec=… %F hands the file manager's files to the app), the .mcgraph MIME type and the icon the entry names. Run it from the
# extracted folder; run it again after moving the folder. `install.sh --remove` undoes it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
ID=com.metalcreator.MetalCreator
DESKTOP="$DATA/applications/$ID.desktop"
MIME="$DATA/mime/packages/$ID.xml"
ICON="$DATA/icons/hicolor/256x256/apps/$ID.png"

refresh() {
    if command -v update-mime-database >/dev/null 2>&1; then update-mime-database "$DATA/mime"; fi
    if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$DATA/applications"; fi
    # Only where the user's hicolor folder is a complete theme (it has an index.theme); otherwise the lookup finds the file itself.
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -f "$DATA/icons/hicolor/index.theme" ]; then
        gtk-update-icon-cache -q -t "$DATA/icons/hicolor" || true
    fi
}

case "${1:-}" in
    "")
        # A desktop entry's Exec line has its own quoting rules; a path with spaces is quoted, and these characters are refused.
        case "$HERE" in
            *[\"\$\\\`\|\&]*)
                echo "install.sh: the folder's path contains one of \" \$ \\ \` | & which a launcher entry can't hold; move it." >&2
                exit 1
                ;;
        esac
        mkdir -p "$DATA/applications" "$DATA/mime/packages" "$DATA/icons/hicolor/256x256/apps"
        # The folder's own path replaces the bare command, so the entry works wherever the folder is. In a quoted Exec argument a
        # percent sign starts a field code, so the path's own are written %%.
        EXEC_PATH="${HERE//%/%%}"
        while IFS= read -r line; do
            case "$line" in
                "Exec=MetalCreator "*) printf 'Exec="%s/MetalCreator" %s\n' "$EXEC_PATH" "${line#Exec=MetalCreator }" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done < "$HERE/share/applications/$ID.desktop" > "$DESKTOP"
        cp "$HERE/share/mime/packages/$ID.xml" "$MIME"
        cp "$HERE/share/icons/hicolor/256x256/apps/$ID.png" "$ICON"
        refresh
        echo "Registered $HERE/MetalCreator for .mcgraph files."
        ;;
    --remove)
        rm -f "$DESKTOP" "$MIME" "$ICON"
        refresh
        echo "Removed MetalCreator's launcher entry, icon and .mcgraph type."
        ;;
    *)
        echo "usage: install.sh [--remove]" >&2
        exit 64
        ;;
esac
```

`packaging/windows/register-mcgraph.ps1`:

```powershell
# Makes Windows open .mcgraph files with the MetalCreator.exe in this folder, for the current user (no administrator rights:
# it writes under HKEY_CURRENT_USER\Software\Classes). Run it from the extracted folder, and again after moving the folder.
# `register-mcgraph.ps1 -Remove` undoes it. Explorer passes the file as the first argument, which the app opens
# (cross-platform spec section 5, gap XP-G5; MetalUI docs/packaging.md, "Windows: a file association").
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

$progId = 'MetalCreator.Graph'
$classes = 'HKCU:\Software\Classes'
$exe = Join-Path $PSScriptRoot 'MetalCreator.exe'

if ($Remove) {
    Remove-Item -Recurse -Force "$classes\.mcgraph", "$classes\$progId" -ErrorAction SilentlyContinue
    Write-Output 'Removed the .mcgraph association.'
    exit 0
}
if (-not (Test-Path $exe)) { throw "MetalCreator.exe isn't beside this script: $exe" }

New-Item -Force -Path "$classes\.mcgraph" -Value $progId | Out-Null
New-Item -Force -Path "$classes\$progId" -Value 'MetalCreator Graph' | Out-Null
New-Item -Force -Path "$classes\$progId\DefaultIcon" -Value "`"$exe`",0" | Out-Null
New-Item -Force -Path "$classes\$progId\shell\open\command" -Value "`"$exe`" `"%1`"" | Out-Null
Write-Output "Registered $exe for .mcgraph files."
```

(`StartupWMClass=com.metalcreator.MetalCreator` matches the window's application id because MetalUI sets SDL's `SDL_APP_ID` hint from the id `launchingSingleInstance(id: AppBundleInfo.identifier, …)` already gets: gap XP-G13, fixed in MetalUI master `b39d68d6` and logged by the adoption track, nothing to add here. `theWindowClassIsTheApplicationIDTheAppHandsToMetalUI` pins the match and that nothing overrides it. `Icon=com.metalcreator.MetalCreator` is an icon theme name: `install.sh` puts the placeholder in the user's hicolor theme, the tarball ships it under `share/icons/hicolor/256x256/apps`, and the AppImage carries it at its root.)

- [ ] **Step 5: Edit `main.swift` to hand over every path**

Replace `forwarding: LaunchCommand.forwardedDocuments(path: path) { … }` and the rest as follows (these are the only remaining differences from Task 4's `main.swift`):

```swift
/// `swift run MetalCreatorApp [path.mcgraph …]`: the app (spec §6.1, M6). It loads the app's themes (the remembered
/// one and the person's own), opens the window over the platform's kernel, installs the menu bar and the window's input
/// hooks, and opens the files named on the command line, if any (a Linux file manager's `%F`, Explorer's `"%1"`).
```
```swift
func runApp(opening paths: [String], smoke: LaunchSmoke? = nil) throws {
    let app = try makeApp(offscreen: smoke != nil,
                          forwarding: LaunchCommand.forwardedDocuments(paths: paths) { FileManager.default.fileExists(atPath: $0) })
```
```swift
    // set before `app.run()`; on Linux and Windows an SDL drop on the application itself (`Platform.onOpenURLs`, gap XP-G5) and
    // a second launch's forwarded documents (MetalUI S7) arrive there too. AppKit and SDL deliver no command-line path, so the
    // path arguments are handed over the same way.
    app.onOpenURL = { model.openRequested($0) }
    if !paths.isEmpty {
        app.open(paths.map { URL(fileURLWithPath: $0) })
    }
```
```swift
case .run(let paths):
    do {
        try runApp(opening: paths)
```
and `try runApp(opening: [], smoke: LaunchSmoke(seconds: seconds))` in the `.smokeTest` case. (The existing comment lines above `app.onOpenURL` that this replaces read "set before `app.run()`. AppKit delivers no command-line path, so the path argument is handed over the same way.")

- [ ] **Step 6: Run the tests on the Mac and on Linux**

```bash
swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning: building for macOS"      # no output
swift test --filter "LaunchCommandTests|DesktopEntryTests|InstallScriptTests|PackagingScriptTests|AppBundleInfoTests" 2>&1 | grep -E "recorded an issue|Test run"
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh test --filter 'LaunchCommandTests|DesktopEntryTests|InstallScriptTests|PackagingScriptTests'
docker run --rm "$IMAGE" desktop-file-validate /work/MetalCreator/packaging/linux/com.metalcreator.MetalCreator.desktop 2>&1 || true
```
Expected: PASS everywhere. (The last line runs in the image with the repo not mounted, so it prints `No such file`; the real validation is in Task 6's `package` step, where the repo is mounted. Measured: `desktop-file-validate` accepts the entry and the entry `install.sh` writes, also for a folder called `100% parts`, which is written `Exec="/tmp/100%% parts/MetalCreator" %F`. Measured again on 2026-10-21 with the entry as it now reads, `Icon=` included, in the xp-2 image (`desktop-file-validate` 0.27): no output.)

- [ ] **Step 7: Lint, commit**

```bash
swiftlint lint --strict --quiet
git add Sources packaging Tests
git commit -m "feat(app): open every document argument; Linux desktop entry, MIME type and install script; Windows file-type script (XP-G5)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **+10** — `LaunchCommandTests` +1 (it replaces two tests with two and adds `aPathWithSpacesAndAccentsIsOneDocument`), `DesktopEntryTests` 5 (the first three, `theWindowClassIsTheApplicationIDTheAppHandsToMetalUI` and `theIconIsA256PixelPNGNamedAfterTheEntry`), `InstallScriptTests` 4 (`removeTakesTheInstalledFilesAway` and the first test also check the icon; `aPercentSignInTheFoldersNameIsWrittenDoubled` and `aFolderNameTheEntryCannotHoldIsRefused`, one parameterised test of four arguments, among them).

---

### Task 6: The Linux tarball

**Files:**
- Create: `scripts/package-linux.sh`
- Modify: `scripts/linux-test.sh` (the `package` step), `Tests/CreatorAppTests/PackagingScriptTests.swift` (`scripts/package-linux.sh` joins the parsed scripts)

**Design.** `scripts/package-linux.sh` builds `MetalCreatorApp` in release, copies it as `MetalCreator` with its RUNPATH set to `$ORIGIN/lib` alone (`patchelf --set-rpath`: the build's `/opt/occt/lib` and the toolchain's `/usr/lib/swift/linux` are dropped, so an unrelated OpenCascade on a user's machine can never be found instead of, or after, the bundled one; measured on the image's real `MetalCreatorApp`, whose RUNPATH was `/usr/lib/swift/linux:$ORIGIN:…/PackageFrameworks:$ORIGIN/lib:/opt/occt/lib`), bundles every non-glibc, non-libstdc++ library `ldd` names (43 here: the Swift runtime, 28 OpenCascade toolkits, `libSDL3.so.0`, `libFoundationICU`) into `lib/` with `patchelf --set-rpath '$ORIGIN'` (RUNPATH is not inherited, so each bundled library names its own folder), copies MetalUI's compiled SDL shaders to `MetalUISDLShaders` beside the executable (MetalUI looks there first, ruling `PX-P`), adds the desktop entry, MIME file, icon (`share/icons/hicolor/256x256/apps`), `install.sh` and the licences (OpenCascade's LGPL 2.1 and exception from the image, MetalUI's `THIRD-PARTY-NOTICES.md` and the licence files it names). **Measured: `--static-swift-stdlib` does not link** (Foundation's ICU symbols such as `swift_unumsys_open` are undefined with Swift 6.4 on Ubuntu 24.04), so the Swift runtime is bundled. The result is a 72 MB `.tar.gz` for aarch64. This tree is also the AppImage's (Task 7 unpacks the tarball into the AppDir), so nothing here is AppImage-specific.

`scripts/linux-test.sh package` runs it in the image (a second volume `$VOLUME-package` holds the release build), validates the desktop entry with `desktop-file-validate`, and then unpacks the tarball in a **clean `ubuntu:24.04`** — no Swift, no `/opt/occt`, no `/work`, no MetalUI checkout — and requires `--version`, `--self-test` (OpenCascade builds, measures, meshes and exports a cube; the SDL shaders are found beside the executable, because the build machine's fallback path does not exist there), the presence of `MetalUISDLShaders/SOURCE.sha256` and `lib/libTKernel.so.7.9`, and, from `LD_DEBUG=libs`, that the loader searched the folder's own `lib` through `RUNPATH from file ./MetalCreator` and never `/opt/occt` (the clean image has no `readelf`; the loader's own trace is the check, and `package-linux.sh` also asserts `patchelf --print-rpath` right after setting it).

**Interfaces:**
- Consumes: Task 2's image (`patchelf`, `desktop-file-validate`, `/opt/occt/share/licenses`), Task 5's `packaging/linux/*`.
- Produces: `dist/MetalCreator-<version>-linux-<arch>.tar.gz` (`dist/` is gitignored); `scripts/linux-test.sh package`.

- [ ] **Step 1: Write the failing test**

In `Tests/CreatorAppTests/PackagingScriptTests.swift` add `"scripts/package-linux.sh"` to the arguments (`"scripts/package-app.sh", "scripts/verify-app.sh", "scripts/linux-test.sh", "scripts/package-linux.sh", "packaging/linux/install.sh"`).

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter PackagingScriptTests 2>&1 | grep -E "recorded an issue|Test run"`
Expected: FAIL — `isExecutableFile` and `bash -n` for the missing `scripts/package-linux.sh`.

- [ ] **Step 3: Create `scripts/package-linux.sh`** (then `chmod +x`)

```bash
#!/bin/bash
# Builds dist/MetalCreator-<version>-linux-<arch>.tar.gz: a release build of MetalCreatorApp, the Swift runtime, OpenCascade, SDL3
# and the other non-system shared libraries it needs in lib/, MetalUI's compiled SDL shaders in
# MetalUISDLShaders beside the executable, the desktop entry, MIME type and icon for .mcgraph files, install.sh, and the licences.
# Unpacked, the folder runs from anywhere: the executable's rpath is $ORIGIN/lib (Package.swift).
#
# usage: scripts/package-linux.sh        (on Linux; scripts/linux-test.sh package runs it in the test image)
#   METALCREATOR_DIST_DIR   where the tarball is written (default: <repo>/dist).
#   METALCREATOR_SCRATCH    SwiftPM's build folder (default: <repo>/.build).
#   OCCT_PREFIX             OpenCascade's install prefix (default /opt/occt), for its licence files.
# Needs MetalUI beside this repository (../MetalUI), patchelf, and the libraries `ldd` names for the built executable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
SCRATCH="${METALCREATOR_SCRATCH:-$ROOT/.build}"
OCCT="${OCCT_PREFIX:-/opt/occt}"
METALUI="$(cd "$ROOT/../MetalUI" && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-linux: %s\n' "$*" >&2; exit 1; }

# Libraries the system provides on every Linux the app runs on (glibc, the C++ runtime): they are never bundled, because a
# bundled glibc breaks against the host's loader. The Swift runtime is bundled: `--static-swift-stdlib` does not link here
# (Foundation's ICU symbols are undefined, measured with Swift 6.4 on Ubuntu 24.04).
is_system() {
    case "$1" in
        linux-vdso.so.*|ld-linux-*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libutil.so.*|libresolv.so.*) return 0 ;;
        libgcc_s.so.*|libstdc++.so.*) return 0 ;;
        *) return 1 ;;
    esac
}

step "Building MetalCreatorApp (release)"
swift build --package-path "$ROOT" -c release --product MetalCreatorApp --scratch-path "$SCRATCH"
BIN_DIR="$(swift build --package-path "$ROOT" -c release --product MetalCreatorApp --scratch-path "$SCRATCH" --show-bin-path)"
BINARY="$BIN_DIR/MetalCreatorApp"
VERSION="$("$BINARY" --version | sed -E 's/^MetalCreator ([0-9][^ ]*) .*/\1/')"
[ -n "$VERSION" ] || fail "couldn't read the version from --version"
NAME="MetalCreator-$VERSION-linux-$(uname -m)"
FOLDER="$WORK/MetalCreator"

step "Assembling $NAME"
mkdir -p "$FOLDER/lib" "$FOLDER/share/applications" "$FOLDER/share/mime/packages" "$FOLDER/share/icons/hicolor/256x256/apps" "$FOLDER/share/doc/metalcreator"
cp "$BINARY" "$FOLDER/MetalCreator"
# The build's search path (/opt/occt/lib, the image's OpenCascade) stays out of the shipped binary: it looks in its own lib/ only,
# so an unrelated OpenCascade on a user's machine can never be found instead (or after) the bundled one.
chmod u+w "$FOLDER/MetalCreator"
patchelf --set-rpath '$ORIGIN/lib' "$FOLDER/MetalCreator"
[ "$(patchelf --print-rpath "$FOLDER/MetalCreator")" = '$ORIGIN/lib' ] || fail "the executable's RUNPATH isn't \$ORIGIN/lib"
cp "$ROOT/packaging/linux/install.sh" "$FOLDER/install.sh"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.desktop" "$FOLDER/share/applications/"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.xml" "$FOLDER/share/mime/packages/"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.png" "$FOLDER/share/icons/hicolor/256x256/apps/"
# MetalUI's SDL backend looks for its compiled shaders in MetalUISDLShaders beside the executable first (ruling PX-P).
SHADERS="$METALUI/Backends/SDL/Shaders/compiled"
[ -f "$SHADERS/SOURCE.sha256" ] || fail "MetalUI's compiled shaders are missing: $SHADERS/SOURCE.sha256"
cp -R "$SHADERS" "$FOLDER/MetalUISDLShaders"

step "Copying the non-system libraries it links, transitively"
ldd "$BINARY" > "$WORK/ldd.txt"
grep -q "not found" "$WORK/ldd.txt" && fail "ldd can't find a library: $(grep 'not found' "$WORK/ldd.txt" | head -n 1)"
count=0
while read -r name arrow path _; do
    [ "$arrow" = "=>" ] || continue
    is_system "$name" && continue
    cp -L "$path" "$FOLDER/lib/$name"
    chmod u+w "$FOLDER/lib/$name"
    # RUNPATH is not inherited, so each bundled library names its own folder for the ones it loads in turn.
    patchelf --set-rpath '$ORIGIN' "$FOLDER/lib/$name"
    count=$((count + 1))
done < "$WORK/ldd.txt"
printf '    %s libraries\n' "$count"
[ -f "$FOLDER/lib/libTKernel.so.7.9" ] || fail "OpenCascade's libTKernel.so.7.9 isn't among the linked libraries"

step "Copying the licences"
DOC="$FOLDER/share/doc/metalcreator"
cp "$OCCT"/share/licenses/* "$DOC/"
cp "$METALUI/THIRD-PARTY-NOTICES.md" "$DOC/MetalUI-THIRD-PARTY-NOTICES.md"
for f in CStbImage/LICENSE CFreeType/FTL.TXT CFreeType/LICENSE.TXT CHarfBuzz/COPYING CUnibreak/LICENCE CSheenBidi/LICENSE; do
    cp "$METALUI/Sources/$f" "$DOC/$(dirname "$f")-$(basename "$f")"
done

step "Writing $DIST/$NAME.tar.gz"
mkdir -p "$DIST"
mv "$FOLDER" "$WORK/$NAME"
tar -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"
printf '%s\n' "$DIST/$NAME.tar.gz"
```

- [ ] **Step 4: Add the `package` step to `scripts/linux-test.sh`**

```diff
--- ../states/linux-test.t2.sh	2026-10-20 22:34:48
+++ scripts/linux-test.sh	2026-10-20 22:34:33
@@ -3,10 +3,12 @@
 # on x86_64 and aarch64 runners). Cross-platform spec 2.5, 2.6.
 #
-#   scripts/linux-test.sh [build|test|smoke|all] [swift test arguments]    default: all
+#   scripts/linux-test.sh [build|test|smoke|package|all] [swift test arguments]    default: all
 #     build   swift build
 #     test    swift test, judged by the pass rule below. Arguments after `test` (for example `--filter CreatorOCCTTests`) go to
 #             swift test and switch the count rule off: only the exit code and the issue lines are judged.
 #     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s)
-#     all     the three, in that order
+#     package scripts/package-linux.sh in the image, then the tarball in dist/ is unpacked in a clean ubuntu:24.04 (no Swift, no
+#             /opt/occt, no MetalUI checkout) and must pass --version and --self-test there; the desktop entry is validated
+#     all     build, test and smoke, in that order (not package: a release build is slow)
 #   scripts/linux-test.sh clean                     removes this track's build volume
 #
@@ -61,9 +63,11 @@
 fi
 
-# Runs `$1` in the image, from the repository, with the build volume; stops only this track's own container.
+# Runs `$1` in the image, from the repository, with the build volume (and `$DOCKER_EXTRA`, if set); stops only this track's own
+# container.
 in_container() {
     docker rm -f "$NAME" >/dev/null 2>&1 || true
+    # shellcheck disable=SC2086
     docker run --rm --name "$NAME" \
-        -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build \
+        -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build ${DOCKER_EXTRA:-} \
         "$IMAGE" bash -ec "$1"
 }
@@ -79,4 +83,27 @@
 }
 
+# The release tarball, built in the image and then run where nothing of the build machine exists.
+do_package() {
+    rm -f dist/MetalCreator-*-linux-"$(uname -m | sed 's/arm64/aarch64/')".tar.gz
+    DOCKER_EXTRA="-v $VOLUME-package:/build-package" in_container '
+        desktop-file-validate packaging/linux/com.metalcreator.MetalCreator.desktop
+        METALCREATOR_SCRATCH=/build-package scripts/package-linux.sh'
+    local tarball
+    tarball=$(ls dist/MetalCreator-*-linux-*.tar.gz | head -n 1)
+    echo "Checking $tarball in a clean ubuntu:24.04..."
+    docker rm -f "$NAME-clean" >/dev/null 2>&1 || true
+    docker run --rm --name "$NAME-clean" -v "$REPO/dist":/dist:ro ubuntu:24.04 bash -ec '
+        test ! -e /opt/occt && test ! -e /work
+        mkdir /tmp/unpacked && tar -xzf /dist/'"$(basename "$tarball")"' -C /tmp/unpacked
+        cd /tmp/unpacked/MetalCreator-*
+        ./MetalCreator --version
+        ./MetalCreator --self-test
+        LD_DEBUG=libs ./MetalCreator --version >/dev/null 2>/tmp/ld.txt
+        grep -q "RUNPATH from file ./MetalCreator" /tmp/ld.txt
+        if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
+        test -f MetalUISDLShaders/SOURCE.sha256 && ls lib | grep -q "^libTKernel.so.7.9$"'
+    echo "Linux package: PASS ($tarball)"
+}
+
 do_test() {
     local status=0 quoted=""
@@ -101,5 +128,6 @@
     test) do_test ;;
     smoke) do_smoke ;;
+    package) do_package ;;
     all) do_build && do_test && do_smoke ;;
-    *) echo "usage: scripts/linux-test.sh [build|test|smoke|all|clean]" >&2; exit 64 ;;
+    *) echo "usage: scripts/linux-test.sh [build|test|smoke|package|all|clean]" >&2; exit 64 ;;
 esac
```

- [ ] **Step 5: Run it**

```bash
swift test --filter PackagingScriptTests 2>&1 | grep -E "recorded an issue|Test run"      # PASS
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh package
```
Expected (measured): `==> Copying the non-system libraries it links, transitively` / `43 libraries`, then in the clean Ubuntu `MetalCreator 0.1.0 (2)`, silently the two `LD_DEBUG` checks (the trace names `search path=…/lib (RUNPATH from file ./MetalCreator)`, measured with a stand-in binary: `patchelf --set-rpath` on the image's Swift executable gave `RUNPATH [$ORIGIN/lib]`), the `--self-test` report (`ok kernel`, `ok STEP export`, `ok STL export`, `ok shaders`), and `Linux package: PASS (dist/MetalCreator-0.1.0-linux-aarch64.tar.gz)`. The first release build of the app takes many minutes (it is cached in `xp-2-linux-build-package` afterwards).

Also run the installer on the real tarball:

```bash
docker run --rm -v "$PWD/dist":/dist:ro "$IMAGE" bash -ec 'mkdir /tmp/u && tar -xzf /dist/*.tar.gz -C /tmp/u && cd /tmp/u/MetalCreator-* && export HOME=/tmp/h && ./install.sh && desktop-file-validate /tmp/h/.local/share/applications/*.desktop && ./install.sh --remove'
```
Expected: `Registered …/MetalCreator for .mcgraph files.` then `Removed MetalCreator's launcher entry and .mcgraph type.`

- [ ] **Step 6: Lint, commit**

```bash
swiftlint lint --strict --quiet; bash -n scripts/package-linux.sh scripts/linux-test.sh
git add scripts Tests/CreatorAppTests/PackagingScriptTests.swift
git commit -m "feat(packaging): Linux tarball with OpenCascade, SDL3, the Swift runtime and MetalUISDLShaders, checked in a clean Ubuntu" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **0**.

---

### Task 7: The Linux AppImage

**Files:**
- Create: `scripts/package-appimage.sh`, `packaging/appimage/AppRun` (both `chmod +x`)
- Modify: `scripts/linux-test.sh` (`package` also builds and checks the AppImage), `Tests/CreatorAppTests/PackagingScriptTests.swift` (the two new files join the parsed scripts)
- Create: `Tests/CreatorAppTests/AppImageRecipeTests.swift`

**Design (user decision 2: both a tarball and an AppImage).** The AppImage is built **from the same staged tree as the tarball**: `scripts/package-appimage.sh` unpacks the tarball Task 6 wrote (the executable with `RUNPATH $ORIGIN/lib`, `lib/`, `MetalUISDLShaders`, `share/`, the licences) into `AppDir/usr/metalcreator` (minus `install.sh`), so nothing is assembled twice and the tarball's clean-Ubuntu run vouches for the tree. The AppDir's root holds `AppRun`, the **same desktop entry** the tarball installs (id `com.metalcreator.MetalCreator`, `Exec=MetalCreator %F`, `MimeType=`, `Icon=`) and the **same icon**, both copied from `packaging/linux` (an AppDir needs `<Icon>.png` at its root), and a `.DirIcon` link. `AppRun` execs `usr/metalcreator/MetalCreator "$@"`; it sets no environment (the executable finds its libraries by RUNPATH, and the window's application id is MetalUI's `SDL_APP_ID` from `AppBundleInfo.identifier`, gap XP-G13). **Tool:** appimagetool 1.9.1 and the type2 runtime 20251108, each pinned by version and sha256 in the script, downloaded when missing into `dist/tools` and verified by `sha256sum -c` before they run (a mismatch deletes the file and stops). The runtime is passed with `--runtime-file`, because appimagetool would otherwise download "the" runtime itself at pack time. These are **third-party build-time tools, not package dependencies** (user decision 2): nothing links them, the manifest and the Dockerfile's package list do not name them (the image gains only `file`, which appimagetool refuses to run without), and the only trace in the output is the runtime at the head of the file. appimagetool is itself an AppImage and runs with `--appimage-extract-and-run`, so the build needs no FUSE, in Docker or on a CI runner.

**Measured on 2026-10-21 in the xp-2 image (aarch64, Docker, no FUSE), with a stub tree instead of the real tarball** (the real release build takes many minutes and Task 6 already covers its tree): the script fetched and verified both tools, wrote a 940 KB AppImage in 1.3 s including the two downloads, and in a clean `ubuntu:24.04` the file ran with `--appimage-extract-and-run --version` and `--appimage-extract` (the MIME XML came out of `usr/metalcreator/share/mime/packages`). `desktop-file-validate` accepted the entry; the sha256 values below were checked by downloading the release assets and hashing them (GitHub's release-asset API lists the same digests for appimagetool 1.9.1 and runtime 20251108; the release page's HTML did not load its asset list). **Not measured:** the real tree's squashfs step (time and size: record both at execution; it is the new cost of `package` and of the Linux CI job, whose 150-minute timeout is untouched), and anything on x86_64 or a desktop.

**File type for the AppImage: a documented manual step.** `install.sh` registers the folder it sits in and an AppImage has no stable folder, so this task does not touch `install.sh`; the same entry and MIME XML travel inside the image and `docs/packaging.md` (Task 9) says how to register the type by hand (the check recipe above extracts the XML the same way). Human check XP-19.

**Interfaces:**
- Consumes: Task 6's tarball in `dist/`; Task 5's `packaging/linux/com.metalcreator.MetalCreator.{desktop,png}`; Task 2's image (`file`, `desktop-file-validate`, `curl`).
- Produces: `dist/MetalCreator-<version>-linux-<arch>.AppImage`; `scripts/linux-test.sh package` builds and checks both Linux packages.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/AppImageRecipeTests.swift`:

```swift
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
```

In `Tests/CreatorAppTests/PackagingScriptTests.swift` add `"scripts/package-appimage.sh"` and `"packaging/appimage/AppRun"` to the arguments of `theScriptParsesAndIsExecutable` (after `"packaging/linux/install.sh"`).

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "AppImageRecipeTests|PackagingScriptTests" 2>&1 | grep -E "recorded an issue|Test run"`
Expected: FAIL — the four recipe tests (no `packaging/appimage/AppRun`, no `scripts/package-appimage.sh`) and `isExecutableFile` / `bash -n` for the two new arguments.

- [ ] **Step 3: Create `packaging/appimage/AppRun` and `scripts/package-appimage.sh`** (then `chmod +x packaging/appimage/AppRun scripts/package-appimage.sh`)

`packaging/appimage/AppRun`:

```bash
#!/bin/bash
# What an AppImage runs. The AppDir holds the Linux tarball's folder as usr/metalcreator, so the executable keeps its $ORIGIN/lib
# RUNPATH and finds MetalUISDLShaders beside it. Whatever the AppImage is started with (a file manager's %F) is the app's
# argument list. The window's application id is not set here: the app hands AppBundleInfo.identifier to MetalUI, which sets
# SDL's SDL_APP_ID hint (MetalUI docs/packaging.md, section 3).
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/metalcreator/MetalCreator" "$@"
```

`scripts/package-appimage.sh`:

```bash
#!/bin/bash
# Builds dist/MetalCreator-<version>-linux-<arch>.AppImage from the Linux tarball (scripts/package-linux.sh), so both carry the
# same staged tree: the executable with RUNPATH $ORIGIN/lib, lib/, MetalUISDLShaders, share/ and the licences. The tarball's
# folder becomes usr/metalcreator in an AppDir that also holds AppRun, the desktop entry and the icon (the same files the tarball
# installs, from packaging/linux), and appimagetool packs the AppDir. install.sh is left out: an AppImage is not unpacked.
#
# usage: scripts/package-appimage.sh [tarball]    default: the newest dist/MetalCreator-*-linux-<arch>.tar.gz
#   METALCREATOR_DIST_DIR   where the tarball is and the AppImage is written (default: <repo>/dist).
#   METALCREATOR_TOOLS      where the downloaded tools are kept (default: <dist>/tools).
# appimagetool and the AppImage runtime are third-party tools fetched here, at build time, pinned by version and sha256 (both
# MIT licensed). They are no dependency of MetalCreator: nothing links them, and only the runtime ends up in the output (it is the
# AppImage's first bytes). The build needs no FUSE: appimagetool is itself an AppImage and runs with --appimage-extract-and-run.
# Needs curl, sha256sum and `file` (appimagetool refuses to run without it).
set -euo pipefail

# Bumping a version means changing its hashes; AppImageRecipeTests checks that every one is present and 64 hex digits.
APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256_x86_64=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
APPIMAGETOOL_SHA256_aarch64=f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158
RUNTIME_TAG=20251108
RUNTIME_SHA256_x86_64=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
RUNTIME_SHA256_aarch64=00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
TOOLS="${METALCREATOR_TOOLS:-$DIST/tools}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-appimage: %s\n' "$*" >&2; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|aarch64) ;;
    arm64) ARCH=aarch64 ;;
    *) fail "no appimagetool for $ARCH" ;;
esac
for tool in curl sha256sum file; do command -v "$tool" >/dev/null || fail "$tool is needed"; done

TARBALL="${1:-$(ls -t "$DIST"/MetalCreator-*-linux-"$ARCH".tar.gz 2>/dev/null | head -n 1)}"
[ -f "$TARBALL" ] || fail "no tarball: run scripts/package-linux.sh first"
NAME="$(basename "$TARBALL" .tar.gz)"

# Downloads $1 to $2 unless $2 is already there, and requires its sha256 to be $3.
fetch() {
    [ -f "$2" ] || curl -fsSL --retry 3 -o "$2" "$1"
    printf '%s  %s\n' "$3" "$2" | sha256sum -c --quiet - || { rm -f "$2"; fail "$1 is not the pinned file (sha256 $3)"; }
}

step "Fetching appimagetool $APPIMAGETOOL_VERSION and the runtime $RUNTIME_TAG (pinned)"
mkdir -p "$TOOLS"
tool_hash="APPIMAGETOOL_SHA256_$ARCH"
runtime_hash="RUNTIME_SHA256_$ARCH"
fetch "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-$ARCH.AppImage" \
    "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage" "${!tool_hash}"
fetch "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_TAG/runtime-$ARCH" \
    "$TOOLS/runtime-$RUNTIME_TAG-$ARCH" "${!runtime_hash}"
chmod +x "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage"

step "Assembling the AppDir from $NAME"
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr"
tar -xzf "$TARBALL" -C "$WORK"
mv "$WORK/$NAME" "$APPDIR/usr/metalcreator"
[ -x "$APPDIR/usr/metalcreator/MetalCreator" ] || fail "the tarball has no MetalCreator executable"
rm "$APPDIR/usr/metalcreator/install.sh"
ID=com.metalcreator.MetalCreator
cp "$ROOT/packaging/appimage/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
cp "$ROOT/packaging/linux/$ID.desktop" "$ROOT/packaging/linux/$ID.png" "$APPDIR/"
ln -s "$ID.png" "$APPDIR/.DirIcon"

step "Writing $DIST/$NAME.AppImage"
rm -f "$DIST/$NAME.AppImage"
ARCH="$ARCH" "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage" --appimage-extract-and-run \
    --runtime-file "$TOOLS/runtime-$RUNTIME_TAG-$ARCH" "$APPDIR" "$DIST/$NAME.AppImage" >"$WORK/appimagetool.log" 2>&1 \
    || { cat "$WORK/appimagetool.log" >&2; fail "appimagetool failed"; }
[ -x "$DIST/$NAME.AppImage" ] || fail "appimagetool wrote no executable AppImage"
printf '%s\n' "$DIST/$NAME.AppImage"
```

- [ ] **Step 4: Extend `scripts/linux-test.sh`'s `package` step**

Apply this on top of Task 6's version (it was generated by applying Task 6's diff to Task 2's file and diffing the result, so it applies with no offset):

```diff
@@ -7,8 +7,10 @@
 #     test    swift test, judged by the pass rule below. Arguments after `test` (for example `--filter CreatorOCCTTests`) go to
 #             swift test and switch the count rule off: only the exit code and the issue lines are judged.
 #     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s)
-#     package scripts/package-linux.sh in the image, then the tarball in dist/ is unpacked in a clean ubuntu:24.04 (no Swift, no
-#             /opt/occt, no MetalUI checkout) and must pass --version and --self-test there; the desktop entry is validated
+#     package scripts/package-linux.sh and scripts/package-appimage.sh in the image (the second downloads appimagetool and the
+#             AppImage runtime, pinned by version and sha256: it needs the network), then the tarball and the AppImage in dist/ are
+#             each run in a clean ubuntu:24.04 (no Swift, no /opt/occt, no MetalUI checkout, no FUSE) and must pass --version and
+#             --self-test there (the AppImage with --appimage-extract-and-run); the desktop entry is validated
 #     all     build, test and smoke, in that order (not package: a release build is slow)
 #   scripts/linux-test.sh clean                     removes this track's build volume
 #
@@ -82,13 +84,17 @@
         "$bin" --smoke-test 20'
 }
 
-# The release tarball, built in the image and then run where nothing of the build machine exists.
+# The release tarball and AppImage, built in the image and then run where nothing of the build machine exists (no Swift, no
+# /opt/occt, no FUSE).
 do_package() {
-    rm -f dist/MetalCreator-*-linux-"$(uname -m | sed 's/arm64/aarch64/')".tar.gz
+    local arch
+    arch=$(uname -m | sed 's/arm64/aarch64/')
+    rm -f dist/MetalCreator-*-linux-"$arch".tar.gz dist/MetalCreator-*-linux-"$arch".AppImage
     DOCKER_EXTRA="-v $VOLUME-package:/build-package" in_container '
         desktop-file-validate packaging/linux/com.metalcreator.MetalCreator.desktop
-        METALCREATOR_SCRATCH=/build-package scripts/package-linux.sh'
-    local tarball
+        METALCREATOR_SCRATCH=/build-package scripts/package-linux.sh
+        scripts/package-appimage.sh'
+    local tarball appimage
     tarball=$(ls dist/MetalCreator-*-linux-*.tar.gz | head -n 1)
     echo "Checking $tarball in a clean ubuntu:24.04..."
     docker rm -f "$NAME-clean" >/dev/null 2>&1 || true
@@ -102,7 +108,22 @@
         grep -q "RUNPATH from file ./MetalCreator" /tmp/ld.txt
         if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
         test -f MetalUISDLShaders/SOURCE.sha256 && ls lib | grep -q "^libTKernel.so.7.9$"'
-    echo "Linux package: PASS ($tarball)"
+    echo "Linux tarball: PASS ($tarball)"
+    appimage=$(ls dist/MetalCreator-*-linux-*.AppImage | head -n 1)
+    echo "Checking $appimage in a clean ubuntu:24.04 (no FUSE: --appimage-extract-and-run)..."
+    docker rm -f "$NAME-clean" >/dev/null 2>&1 || true
+    docker run --rm --name "$NAME-clean" -v "$REPO/dist":/dist:ro ubuntu:24.04 bash -ec '
+        test ! -e /opt/occt && test ! -e /work && test ! -e /dev/fuse
+        cp /dist/'"$(basename "$appimage")"' /tmp/MetalCreator.AppImage && chmod +x /tmp/MetalCreator.AppImage
+        cd /tmp
+        ./MetalCreator.AppImage --appimage-extract-and-run --version
+        ./MetalCreator.AppImage --appimage-extract-and-run --self-test
+        LD_DEBUG=libs ./MetalCreator.AppImage --appimage-extract-and-run --version >/dev/null 2>/tmp/ld.txt
+        grep -q "RUNPATH from file .*/usr/metalcreator/MetalCreator" /tmp/ld.txt
+        if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
+        ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/share/mime/packages/*.xml" >/dev/null
+        test -f squashfs-root/usr/metalcreator/share/mime/packages/com.metalcreator.MetalCreator.xml'
+    echo "Linux AppImage: PASS ($appimage)"
 }
 
 do_test() {
```

- [ ] **Step 5: Run it**

```bash
swift test --filter "AppImageRecipeTests|PackagingScriptTests|DesktopEntryTests" 2>&1 | grep -E "recorded an issue|Test run"      # PASS
export IMAGE=metalcreator-linux:xp-2 XP_TRACK=xp-2
scripts/linux-test.sh package
```
Expected: Task 6's output (the tarball is rebuilt: the release build is cached in `xp-2-linux-build-package`), then `==> Fetching appimagetool 1.9.1 and the runtime 20251108 (pinned)`, `==> Assembling the AppDir from MetalCreator-0.1.0-linux-aarch64`, `==> Writing …/dist/MetalCreator-0.1.0-linux-aarch64.AppImage`, `Linux tarball: PASS (…)`, `Checking … in a clean ubuntu:24.04 (no FUSE: --appimage-extract-and-run)...`, the `--version` line, the `--self-test` report (`ok kernel`, `ok STEP export`, `ok STL export`, `ok shaders`), and `Linux AppImage: PASS (dist/MetalCreator-0.1.0-linux-aarch64.AppImage)`. (Measured with the stub tree: the script's three lines and the `--version`/`--appimage-extract` results; the full `--self-test` run is the one thing not measured.) If `tar` prints `Ignoring unknown extended header keyword 'LIBARCHIVE.xattr…'` the tarball was made on macOS rather than by `package-linux.sh` in the image; harmless.

- [ ] **Step 6: Lint, commit**

```bash
swiftlint lint --strict --quiet; bash -n scripts/package-appimage.sh packaging/appimage/AppRun scripts/linux-test.sh
git add scripts packaging Tests/CreatorAppTests/AppImageRecipeTests.swift Tests/CreatorAppTests/PackagingScriptTests.swift
git commit -m "feat(packaging): Linux AppImage packed from the tarball's tree with a pinned appimagetool, checked in a clean Ubuntu without FUSE" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **+4** — `AppImageRecipeTests`: `appRunStartsTheBundledExecutableWithItsArgumentsAndSetsNoApplicationID`, `theToolAndTheRuntimeArePinnedByVersionAndHash`, `theAppDirHoldsTheSharedEntryAndIconAtItsRootAndTheTarballsTreeUnderUsr`, `nothingNeedsFUSE`. (`PackagingScriptTests` gains two arguments of its parameterised test, no new test.)

---

### Task 8: The Windows zip, vcpkg, CI, and the pinned numbers

**CI-only task.** Nothing in this task's scripts or workflow can run on this Mac. The Mac proves only what the Swift tests prove (`CIPinTests`), that the YAML parses, and that the bash it touches parses. The Windows job is verified by pushing an `xp-*` branch.

**Files:**
- Create: `packaging/windows/vcpkg.json`, `scripts/package-windows.ps1`
- Modify: `.github/workflows/xp.yml`
- Create: `Tests/CreatorAppTests/CIPinTests.swift`

**Windows OpenCascade.** vcpkg's `opencascade` port at `7.9.3` (port-version 1) exists at vcpkg commit `256310531c1e57ee83f8ac01f7bea7c1e56630f5` (its `ports/opencascade/vcpkg.json` says `"version": "7.9.3", "port-version": 1`; master is already 8.0.1, so the commit is pinned, not a baseline of "latest"). The job fetches that one commit, bootstraps vcpkg, and installs the manifest in `packaging/windows` for the triplet **`x64-windows`**: dynamic libraries, **release and debug** (user decision 8: the suite is a debug build and must meet OpenCascade built with the same C runtime, so the release-only community triplet is not used; the first vcpkg build builds OpenCascade twice). The port uses the Unix layout, so the install root has `include/opencascade`, `lib/TK*.lib`, `bin/TK*.dll` and, for debug, `debug/lib` and `debug/bin`; `OCCT_PREFIX` points at the root (forward slashes), `Package.swift` links `debug/lib` for a debug build and `lib` for a release build, and the root's `debug\bin` goes on `PATH` for the suite (the zip takes `bin`). The step checks that `TKernel.lib` and `TKernel.dll` exist in both sets and, if not, lists what vcpkg did install before it fails (the file names are the one thing here that cannot be read without running vcpkg). `default-features: false` drops FreeType. vcpkg's binary cache folder is restored by `actions/cache/restore` and saved by `actions/cache/save` right after the install, keyed by the vcpkg commit and the manifest's hash: `actions/cache`'s own post step saves only when the whole job is green, and the first Windows runs are expected to be red (user decision 4).

**`package-windows.ps1`.** Takes the release build (CI makes it in its own step, `swift build -c release --product MetalCreatorApp`, and passes `-NoBuild`; without the switch the script builds it), names the zip from `--version`, copies the exe as `MetalCreator.exe`, and follows the `DLL Name:` lines of `llvm-objdump -p` (or, when there is none beside `swift.exe` or on `PATH`, `dumpbin /dependents`, found with `vswhere`) transitively through OpenCascade's `bin`, SDL's `lib\x64` and the Swift runtime's folders. Those are **found at run time**, not written down: the script looks for `swiftCore.dll` under the `Swift` folder that `swift.exe`'s and `SDKROOT`'s own folders sit below (and `%ProgramFiles%\Swift`, `%LOCALAPPDATA%\Programs\Swift`), because the setup-swift action and the installer lay the runtime out differently, and it prints the search path it used. Windows' own DLLs and `api-ms-*` are left out; the Visual C++ runtime is copied from `System32`, which is allowed app-local. It adds `MetalUISDLShaders`, `register-mcgraph.ps1` and the licences, zips, then unpacks the zip and runs `--self-test` **with only Windows' folders on `PATH` and MetalUI's checkout renamed aside** (the SDL backend falls back to the shaders in its source tree, which would hide a missing `MetalUISDLShaders`). **CI-only risk:** a release build is a different optimiser pipeline from the debug build the suite uses, nobody has run it on Windows with Swift 6.4, it may hit the known coroutine-splitting crash, and it adds a compile to a job that now also builds vcpkg's OpenCascade cold. So it is its own workflow step (red on its own, the suite and the packaging steps stay readable), the Windows job's timeout is 180 minutes, and the suite's own `--self-test` and `--smoke-test` run on the debug build before it, so that result never depends on the release build. The script was parsed with PowerShell 7 (no errors) and `Find-SwiftRuntimeDirs` was run over a stand-in folder layout (found with and without `SDKROOT`, a clear error when absent); the rest cannot run here.

**Interfaces:**
- Consumes: Tasks 3 and 5; workflow env `SDL3_INCLUDE`, `SDL3_LIB` and the accesskit flags file as xp-1 left them.
- Produces: `VCPKG_COMMIT`, `EXPECTED_TEST_RUNS: 12`, `SDL3_ROOT`, `OCCT_PREFIX` in the Windows job; artifacts `MetalCreator-linux-<arch>` (the tarball and the AppImage) and `MetalCreator-windows-x64`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CreatorAppTests/CIPinTests.swift`:

```swift
import Foundation
import Testing

/// Numbers and hashes that are written in more than one file must agree (cross-platform spec section 2.5, 2.6; plan xp-2).
/// A change to one place that misses another shows up here, not as a red CI run an hour later.
struct CIPinTests {
    /// The "Test run with" lines a full `swift test` prints on every platform since xp-2 put `CreatorOCCTTests` on Linux and
    /// Windows. A new test target raises it everywhere below.
    static let testRuns = 12

    @Test func theWindowsJobExpectsTheCount() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("EXPECTED_TEST_RUNS: \(Self.testRuns)\n"))
        #expect(!workflow.contains("EXPECTED_TEST_RUNS: 11"))
    }

    @Test func theLinuxScriptDefaultsToTheCount() throws {
        let script = try Self.text("scripts/linux-test.sh")
        #expect(script.contains("EXPECTED_TEST_RUNS=${EXPECTED_TEST_RUNS:-\(Self.testRuns)}"))
        #expect(!script.contains("EXPECTED_TEST_RUNS:-11"))
    }

    @Test func theProjectGuideStatesTheCountForEveryPlatform() throws {
        let guide = try Self.text("CLAUDE.md")
        #expect(guide.contains("exit 0 and \(Self.testRuns) \"Test run with\" lines"))
        #expect(!guide.contains("and 11 \"Test run with\""), "the Linux count is no longer eleven")
        #expect(!guide.contains("(11 \"Test run with\" lines)"), "the linux-test.sh line says twelve")
    }

    /// Review focus: the vcpkg manifest and the workflow name the same vcpkg commit, or the cache key and the build disagree.
    @Test func theWindowsManifestsBaselineIsTheWorkflowsVcpkgCommit() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        let commit = try #require(workflow.firstMatch(of: /VCPKG_COMMIT: ([0-9a-f]{40})/)?.1)
        let manifest = try Self.text("packaging/windows/vcpkg.json")
        #expect(manifest.contains("\"builtin-baseline\": \"\(commit)\""))
    }

    /// Package.swift links `debug/lib` for a debug build and `lib` for a release one (`ShimPortabilityTests` pins that), and the
    /// Windows job runs a debug suite and packages a release build: its vcpkg triplet must install both sets, which the
    /// release-only community triplet `x64-windows-release` does not (user decision 8).
    @Test func theWindowsJobInstallsBothTheDebugAndTheReleaseLibraries() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("--triplet x64-windows "))
        #expect(!workflow.contains("x64-windows-release"))
        #expect(workflow.contains(#"\debug\bin" >> $env:GITHUB_PATH"#), "the debug suite finds the debug DLLs")
    }

    /// Review focus: `actions/checkout` on windows-latest writes CRLF unless `.gitattributes` says otherwise, and the tests that
    /// read these files, and the scripts that run, need LF. The tests also read CRLF as LF, but a bash script cannot.
    @Test func gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF() throws {
        let attributes = try Self.text(".gitattributes")
        for pattern in ["packaging/**", "scripts/**", ".github/**", "Sources/COCCT/**", "CLAUDE.md"] {
            #expect(attributes.contains("\n\(pattern) text eol=lf\n"), "\(pattern) must be checked out with LF")
        }
        #expect(attributes.contains("\npackaging/**/*.png binary\n"), "the icon is binary: an eol rule would rewrite its bytes")
    }

    /// Both Linux packages leave the Linux job as artifacts (user decision 2). The packer for the AppImage is fetched and pinned by
    /// `scripts/package-appimage.sh` (`AppImageRecipeTests`), so the workflow names no tool.
    @Test func theLinuxJobUploadsTheTarballAndTheAppImage() throws {
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("MetalCreator/dist/MetalCreator-*-linux-*.tar.gz\n"))
        #expect(workflow.contains("MetalCreator/dist/MetalCreator-*-linux-*.AppImage\n"))
        #expect(!workflow.contains("appimagetool"))
    }

    /// OpenCascade is built from a commit, not a tag (a tag can be moved).
    @Test func theLinuxImageBuildsOpenCascadeFromAFullCommit() throws {
        let dockerfile = try Self.text("scripts/linux/Dockerfile")
        #expect(dockerfile.firstMatch(of: /ARG OCCT_COMMIT=[0-9a-f]{40}\n/) != nil)
    }

    /// A file of the repository as text, "\r\n" read as "\n" (Swift counts "\r\n" as one Character, so a CRLF checkout would
    /// never match a pattern that ends in "\n").
    private static func text(_ path: String) throws -> String {
        let repository = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --filter CIPinTests 2>&1 | grep -E "recorded an issue|Test run"`
Expected: FAIL (measured with the Task 6 tree and xp-1's workflow and guide): `theWindowsJobExpectsTheCount` (the workflow says `EXPECTED_TEST_RUNS: 11`), `theProjectGuideStatesTheCountForEveryPlatform` (CLAUDE.md says Linux 11), `theWindowsManifestsBaselineIsTheWorkflowsVcpkgCommit` (no `VCPKG_COMMIT`, no manifest), and `theLinuxJobUploadsTheTarballAndTheAppImage` (the workflow uploads only the tarball) and `theWindowsJobInstallsBothTheDebugAndTheReleaseLibraries` (xp-1's workflow has no vcpkg step; this test and the next were added by the review revision and their red was not measured separately). `theLinuxScriptDefaultsToTheCount` and `theLinuxImageBuildsOpenCascadeFromAFullCommit` already pass (Task 2), and so does `gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF` (Task 1 created `.gitattributes`).

- [ ] **Step 3: Create the vcpkg manifest**

`packaging/windows/vcpkg.json`:

```json
{
  "name": "metalcreator-occt",
  "version-string": "0",
  "builtin-baseline": "256310531c1e57ee83f8ac01f7bea7c1e56630f5",
  "dependencies": [
    { "name": "opencascade", "default-features": false }
  ]
}
```

- [ ] **Step 4: Create `scripts/package-windows.ps1`**

```powershell
# Builds dist\MetalCreator-<version>-windows-x64.zip: a release build of MetalCreatorApp as MetalCreator.exe, every DLL it
# needs beside it (OpenCascade's, SDL3's, the Swift runtime's, the Visual C++ runtime's), MetalUI's compiled SDL shaders in
# MetalUISDLShaders, the .mcgraph file-type script and the licences. The zip is then unpacked into a scratch folder and
# `MetalCreator.exe --self-test` runs from there with a PATH that holds only Windows' own folders, so a DLL that is missing
# from the zip fails the build instead of the user's machine.
#
# usage (from the repository, in PowerShell on Windows; CI's Windows job runs it):
#   scripts\package-windows.ps1 [-NoBuild] -BuildFlags @(…) -SdlRoot <SDL3 VC package folder>
#   -BuildFlags  the extra swift build arguments the job already passes (SDL's and AccessKit's paths).
#   -SdlRoot     the SDL3-<version> folder of SDL's VC package (SDL3.dll in lib\x64, LICENSE.txt at the top).
#   -OutDir      where the zip is written (default: <repo>\dist).
#   -NoBuild     the release build was made by an earlier step (`swift build -c release --product MetalCreatorApp`, same flags):
#                only look its folder up. CI does this, so that a failed release build is its own red step.
# Environment: OCCT_PREFIX is OpenCascade's install root (bin\*.dll, share\opencascade\copyright); this script uses its release
# set (`bin`), never `debug\bin`.
# Needs MetalUI beside this repository (..\MetalUI). Not run outside CI.
param(
    [string[]]$BuildFlags = @(),
    [Parameter(Mandatory)][string]$SdlRoot,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist'),
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$metalUI = (Resolve-Path (Join-Path $root '..\MetalUI')).Path
if (-not $env:OCCT_PREFIX) { throw 'OCCT_PREFIX must name the OpenCascade install root.' }
$work = Join-Path ([IO.Path]::GetTempPath()) "metalcreator-package-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work | Out-Null

function Step($text) { Write-Output "==> $text" }

Step 'Building MetalCreatorApp (release)'
Push-Location $root
try {
    if (-not $NoBuild) {
        swift build -c release --product MetalCreatorApp @BuildFlags
        if ($LASTEXITCODE) { throw "swift build failed ($LASTEXITCODE)" }
    }
    $bin = (swift build -c release --product MetalCreatorApp @BuildFlags --show-bin-path).Trim()
} finally { Pop-Location }

$exe = Join-Path $bin 'MetalCreatorApp.exe'
if (-not (Test-Path $exe)) { throw "no release build at $exe (run swift build -c release --product MetalCreatorApp first)" }
$versionLine = (& $exe --version)
if ($versionLine -notmatch '^MetalCreator (\S+) ') { throw "can't read the version from: $versionLine" }
$name = "MetalCreator-$($Matches[1])-windows-x64"
$folder = Join-Path $work $name
New-Item -ItemType Directory -Path $folder | Out-Null

Step "Assembling $name"
Copy-Item $exe (Join-Path $folder 'MetalCreator.exe')
Copy-Item (Join-Path $root 'packaging\windows\register-mcgraph.ps1') $folder
$shaders = Join-Path $metalUI 'Backends\SDL\Shaders\compiled'
if (-not (Test-Path (Join-Path $shaders 'SOURCE.sha256'))) { throw "MetalUI's compiled shaders are missing: $shaders" }
Copy-Item -Recurse $shaders (Join-Path $folder 'MetalUISDLShaders')

Step 'Copying the DLLs it needs, transitively'

# The folders that hold the Swift runtime's DLLs, found by looking for swiftCore.dll, not by a path written down here: the
# toolchain installer, the setup-swift action and a side-by-side install all lay the runtime out differently, but under a
# folder named Swift that swift.exe's and SDKROOT's own folders sit below.
function Find-SwiftRuntimeDirs {
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($start in @((Split-Path (Get-Command swift).Source), $env:SDKROOT)) {
        for ($dir = $start; $dir; $dir = [IO.Path]::GetDirectoryName($dir)) {
            if ([IO.Path]::GetFileName($dir) -eq 'Swift') { $roots.Add($dir); break }
        }
    }
    foreach ($known in @((Join-Path $env:ProgramFiles 'Swift'), (Join-Path $env:LOCALAPPDATA 'Programs\Swift'))) {
        if (Test-Path $known) { $roots.Add($known) }
    }
    $found = $roots | Select-Object -Unique | ForEach-Object {
        Get-ChildItem $_ -Recurse -Depth 6 -Filter swiftCore.dll -ErrorAction SilentlyContinue | ForEach-Object DirectoryName
    } | Select-Object -Unique
    if (-not $found) { throw "swiftCore.dll isn't under any of: $($roots -join ', ')" }
    $found
}

# What lists a binary's dependent DLLs: llvm-objdump (beside swift.exe, or on PATH), else dumpbin from Visual Studio.
function Find-DependentsTool {
    $beside = Join-Path (Split-Path (Get-Command swift).Source) 'llvm-objdump.exe'
    if (Test-Path $beside) { return @{ Kind = 'objdump'; Path = $beside } }
    $onPath = Get-Command llvm-objdump.exe -ErrorAction SilentlyContinue
    if ($onPath) { return @{ Kind = 'objdump'; Path = $onPath.Source } }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $dumpbin = & $vswhere -latest -products * -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' | Select-Object -First 1
        if ($dumpbin) { return @{ Kind = 'dumpbin'; Path = $dumpbin } }
    }
    throw 'neither llvm-objdump.exe (beside swift.exe or on PATH) nor Visual Studio''s dumpbin.exe was found'
}

$tool = Find-DependentsTool
function Get-Dependents($file) {
    if ($tool.Kind -eq 'objdump') {
        & $tool.Path -p $file | Select-String 'DLL Name: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
    } else {
        & $tool.Path /nologo /dependents $file | ForEach-Object { if ($_ -match '^\s+(\S+\.dll)\s*$') { $Matches[1] } }
    }
}

# Where a dependency may come from: OpenCascade's release DLLs, SDL3, then the Swift toolchain's and runtime's folders.
$searchDirs = @(
    (Join-Path $env:OCCT_PREFIX 'bin'),
    (Join-Path $SdlRoot 'lib\x64'),
    (Split-Path (Get-Command swift).Source)
) + @(Find-SwiftRuntimeDirs)
Write-Output "    dependents from $($tool.Path); search path:"
$searchDirs | ForEach-Object { "      $_" }
$system = Join-Path $env:SystemRoot 'System32'
# The Visual C++ runtime is redistributable app-local; everything else in System32 is Windows' own.
$redistributable = '^(vcruntime140.*|msvcp140.*|concrt140|vcomp140)\.dll$'

$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $folder 'MetalCreator.exe'))
$bundled = @{}
while ($queue.Count) {
    $file = $queue.Dequeue()
    foreach ($dll in Get-Dependents $file) {
        $key = $dll.ToLowerInvariant()
        if ($bundled.ContainsKey($key) -or $key -like 'api-ms-win-*' -or $key -like 'ext-ms-*') { continue }
        $source = $searchDirs | ForEach-Object { Join-Path $_ $dll } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $source -and $key -match $redistributable) { $source = Join-Path $system $dll }
        if (-not $source) {
            if (Test-Path (Join-Path $system $dll)) { continue }   # Windows' own
            throw "can't find $dll, needed by $file"
        }
        Copy-Item $source (Join-Path $folder $dll)
        $bundled[$key] = $true
        $queue.Enqueue((Join-Path $folder $dll))
    }
}
"    $($bundled.Count) DLLs"
if (-not $bundled.ContainsKey('tkernel.dll')) { throw "OpenCascade's TKernel.dll isn't among the DLLs the executable needs" }
if (-not $bundled.ContainsKey('sdl3.dll')) { throw "SDL3.dll isn't among the DLLs the executable needs" }
if (-not $bundled.ContainsKey('swiftcore.dll')) { throw "swiftCore.dll isn't among the DLLs the executable needs" }

Step 'Copying the licences'
$doc = Join-Path $folder 'licenses'
New-Item -ItemType Directory -Path $doc | Out-Null
Copy-Item (Join-Path $env:OCCT_PREFIX 'share\opencascade\copyright') (Join-Path $doc 'OpenCascade-copyright.txt')
Copy-Item (Join-Path $SdlRoot 'LICENSE.txt') (Join-Path $doc 'SDL3-LICENSE.txt')
Copy-Item (Join-Path $metalUI 'THIRD-PARTY-NOTICES.md') (Join-Path $doc 'MetalUI-THIRD-PARTY-NOTICES.md')
foreach ($f in 'CStbImage/LICENSE', 'CFreeType/FTL.TXT', 'CFreeType/LICENSE.TXT', 'CHarfBuzz/COPYING', 'CUnibreak/LICENCE', 'CSheenBidi/LICENSE') {
    Copy-Item (Join-Path $metalUI "Sources\$f") (Join-Path $doc ((Split-Path $f) + '-' + (Split-Path $f -Leaf)))
}

Step 'Writing the zip'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path (Resolve-Path $OutDir).Path "$name.zip"
Remove-Item -Force $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $folder -DestinationPath $zip

Step 'Checking the zip on its own: --self-test with only Windows on PATH'
$check = Join-Path $work 'check'
Expand-Archive $zip -DestinationPath $check
$savedPath = $env:PATH
$env:PATH = "$system;$env:SystemRoot"
# MetalUI's SDL backend falls back to the shaders in the source tree it was built from, which would hide a zip without
# MetalUISDLShaders; so the checkout is moved aside for the check.
$aside = "$metalUI.aside"
Rename-Item $metalUI $aside
try {
    & (Join-Path $check "$name\MetalCreator.exe") --self-test
    $code = $LASTEXITCODE
} finally {
    Rename-Item $aside $metalUI
    $env:PATH = $savedPath
}
if ($code) { throw "--self-test failed from the unpacked zip (exit $code)" }
Remove-Item -Recurse -Force $work
Write-Output $zip
```

- [ ] **Step 5: Edit `.github/workflows/xp.yml`**

```diff
diff --git a/.github/workflows/xp.yml b/.github/workflows/xp.yml
index 0d0c673..7b45358 100644
--- a/.github/workflows/xp.yml
+++ b/.github/workflows/xp.yml
@@ -6,10 +6,19 @@
 # when MetalCreator adopts a MetalUI change.
 #
 # The Linux jobs run scripts/linux-test.sh, the script a developer runs in Docker on a Mac: build, the suite (exit 0, no
-# "recorded an issue" or "failed after" line, eleven "Test run with" lines), the app's --self-test, and --smoke-test 20.
+# "recorded an issue" or "failed after" line, twelve "Test run with" lines), the app's --self-test, and --smoke-test 20, then
+# scripts/linux-test.sh package: a release tarball and an AppImage (packed from the tarball's tree by scripts/package-appimage.sh,
+# which downloads its pinned packer; no FUSE is needed), each unpacked or extracted and run in a clean Ubuntu.
+#
+# OpenCascade 7.9 (xp-2, spec section 3): on Linux it is built from a pinned commit in the Dockerfile's `occt` stage, which CI
+# builds alone with buildx and caches in the GitHub Actions cache (scope xp-occt-<arch>); the first run on a new key builds it
+# (about an hour on a 4-core runner), later runs restore it. On Windows it is vcpkg's `opencascade` port, pinned by the vcpkg
+# commit below (the one whose port is 7.9.3), built in release and debug (the suite is a debug build, so it links OpenCascade's debug
+# libraries: one C runtime on both sides), and vcpkg's binary cache folder is restored before and saved right after the install, so
+# a red later step does not lose it.
 #
 # The Windows job is modelled on MetalUI's own Windows job (.github/workflows/sdl-gpu-linux.yml). Run 38546048595 was green: it builds, passes the
-# suite (11 "Test run with" lines) and passes the app's --self-test and --smoke-test. It stays continue-on-error, so it does not hide the Linux
+# suite (11 "Test run with" lines; 12 since xp-2 added CreatorOCCTTests) and passes the app's --self-test and --smoke-test. It stays continue-on-error, so it does not hide the Linux
 # result, and the last step marks a red Windows run with a warning and a summary line (the run itself shows green); read its log on every run.
 
 name: XP cross-platform
@@ -28,6 +37,9 @@ concurrency:
 env:
   METALUI_REPOSITORY: mburger89/MetalUI
   METALUI_COMMIT: <the value master has: 1bdead8d or newer, whatever master pins at execution time>
+  # microsoft/vcpkg at the commit whose ports/opencascade is 7.9.3 (port-version 1). packaging/windows/vcpkg.json names the same
+  # commit as its builtin-baseline; CIPinTests checks they agree.
+  VCPKG_COMMIT: 256310531c1e57ee83f8ac01f7bea7c1e56630f5
 
 jobs:
   linux:
@@ -41,7 +53,7 @@ jobs:
           - arch: aarch64
             runner: ubuntu-24.04-arm
     runs-on: ${{ matrix.runner }}
-    timeout-minutes: 90
+    timeout-minutes: 150
     steps:
       - uses: actions/checkout@v7
         with:
@@ -61,9 +73,33 @@ jobs:
           load: true
           cache-from: type=gha,scope=xp-portable-${{ matrix.arch }}
           cache-to: type=gha,mode=max,scope=xp-portable-${{ matrix.arch }}
+      - name: Build OpenCascade 7.9 (cached)
+        uses: docker/build-push-action@v7
+        with:
+          context: MetalCreator/scripts/linux
+          file: MetalCreator/scripts/linux/Dockerfile
+          target: occt
+          tags: metalcreator-occt:latest
+          load: true
+          cache-from: type=gha,scope=xp-occt-${{ matrix.arch }}
+          cache-to: type=gha,mode=max,scope=xp-occt-${{ matrix.arch }}
       - name: Build, test, self-test and launch
         working-directory: MetalCreator
+        env:
+          OCCT_IMAGE: metalcreator-occt:latest
         run: scripts/linux-test.sh all
+      - name: Package (tarball and AppImage), each checked in a clean Ubuntu
+        working-directory: MetalCreator
+        env:
+          OCCT_IMAGE: metalcreator-occt:latest
+        run: scripts/linux-test.sh package
+      - uses: actions/upload-artifact@v4
+        with:
+          name: MetalCreator-linux-${{ matrix.arch }}
+          path: |
+            MetalCreator/dist/MetalCreator-*-linux-*.tar.gz
+            MetalCreator/dist/MetalCreator-*-linux-*.AppImage
+          if-no-files-found: error
 
   windows:
     name: Windows x64 (unverified until it runs)
@@ -71,10 +107,10 @@ jobs:
     # green check); remove this line once the job has been green once.
     continue-on-error: true
     runs-on: windows-latest
-    timeout-minutes: 120
+    timeout-minutes: 180
     env:
       SDL_VERSION: 3.4.16
-      EXPECTED_TEST_RUNS: 11
+      EXPECTED_TEST_RUNS: 12
     defaults:
       run:
         shell: pwsh
@@ -99,7 +135,52 @@ jobs:
           $root = "$env:RUNNER_TEMP\SDL3-$env:SDL_VERSION"
           "SDL3_INCLUDE=$root\include" >> $env:GITHUB_ENV
           "SDL3_LIB=$root\lib\x64" >> $env:GITHUB_ENV
+          "SDL3_ROOT=$root" >> $env:GITHUB_ENV
           "$root\lib\x64" >> $env:GITHUB_PATH   # SDL3.dll at run time
+      - name: Restore vcpkg's binary cache
+        id: vcpkg-cache
+        # Not actions/cache: its post step saves only when the whole job is green, and the first Windows runs are expected to be
+        # red. The save step below runs as soon as the install is done.
+        uses: actions/cache/restore@v4
+        with:
+          path: ${{ runner.temp }}\vcpkg-cache
+          key: vcpkg-occt-${{ env.VCPKG_COMMIT }}-${{ hashFiles('MetalCreator/packaging/windows/vcpkg.json') }}
+      - name: Install OpenCascade 7.9 (vcpkg, release and debug libraries)
+        id: occt
+        # The vcpkg commit is fetched alone and bootstrapped; the port builds with the runner's Visual Studio, twice (release and
+        # debug), tens of minutes the first time. A cache hit restores the built packages, so the step takes about a minute.
+        # OCCT_PREFIX is what Package.swift reads. The suite is a debug build and links `debug\lib`, so `debug\bin` goes on
+        # PATH for the test executables; the zip is a release build and takes `bin`.
+        run: |
+          $vcpkg = "$env:RUNNER_TEMP\vcpkg"
+          git init -q $vcpkg
+          git -C $vcpkg fetch -q --depth 1 https://github.com/microsoft/vcpkg $env:VCPKG_COMMIT
+          git -C $vcpkg checkout -q FETCH_HEAD
+          & "$vcpkg\bootstrap-vcpkg.bat" -disableMetrics
+          if ($LASTEXITCODE) { exit $LASTEXITCODE }
+          New-Item -ItemType Directory -Force "$env:RUNNER_TEMP\vcpkg-cache" | Out-Null
+          $env:VCPKG_BINARY_SOURCES = "clear;files,$env:RUNNER_TEMP\vcpkg-cache,readwrite"
+          & "$vcpkg\vcpkg.exe" install --triplet x64-windows --x-manifest-root="$env:GITHUB_WORKSPACE\MetalCreator\packaging\windows" --x-install-root="$env:RUNNER_TEMP\vcpkg-installed"
+          if ($LASTEXITCODE) { exit $LASTEXITCODE }
+          $prefix = "$env:RUNNER_TEMP\vcpkg-installed\x64-windows"
+          # Package.swift links TKernel.lib from debug\lib (debug builds) and lib (release builds): say what the port really
+          # installed before the build has to guess.
+          $missing = 'lib\TKernel.lib', 'debug\lib\TKernel.lib', 'bin\TKernel.dll', 'debug\bin\TKernel.dll' |
+              Where-Object { -not (Test-Path "$prefix\$_") }
+          if ($missing) {
+            Get-ChildItem $prefix -Recurse -Filter 'TKernel*' | ForEach-Object FullName
+            throw "vcpkg did not install: $($missing -join ', ')"
+          }
+          "OCCT_PREFIX=$($prefix -replace '\\', '/')" >> $env:GITHUB_ENV
+          "$prefix\debug\bin" >> $env:GITHUB_PATH
+      - name: Save vcpkg's binary cache
+        # Only after a whole install (a partial one would fill the key for good: a cache entry is never replaced), and whatever
+        # the later steps do.
+        if: ${{ always() && steps.occt.outcome == 'success' && steps.vcpkg-cache.outputs.cache-hit != 'true' }}
+        uses: actions/cache/save@v4
+        with:
+          path: ${{ runner.temp }}\vcpkg-cache
+          key: ${{ steps.vcpkg-cache.outputs.cache-primary-key }}
       - name: Fetch AccessKit
         working-directory: MetalUI/Backends/SDL
         # One SwiftPM flag per line: -Xcc -I<include> -Xswiftc -L<lib> (MetalUI PX-I item 2).
@@ -149,9 +230,35 @@ jobs:
           if ($LASTEXITCODE) { exit $LASTEXITCODE }
           & "$bin\MetalCreatorApp.exe" --smoke-test 20
           exit $LASTEXITCODE
+      - name: Build release (for the zip)
+        id: release
+        working-directory: MetalCreator
+        # Its own step, so the first release build on Windows (a different optimiser pipeline from the debug build the suite uses,
+        # and twice the compile time) shows red here on its own and leaves the suite's result readable.
+        if: ${{ !cancelled() }}
+        run: |
+          $flags = @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB") +
+                   @(Get-Content "$env:RUNNER_TEMP\accesskit-flags.txt")
+          swift build -c release --product MetalCreatorApp @flags
+          exit $LASTEXITCODE
+      - name: Package (zip), checked on its own
+        id: package
+        working-directory: MetalCreator
+        if: ${{ !cancelled() && steps.release.outcome == 'success' }}
+        # Unpacks the zip and runs --self-test with only Windows' folders on PATH, so a DLL missing from the zip fails here.
+        run: |
+          $flags = @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB") +
+                   @(Get-Content "$env:RUNNER_TEMP\accesskit-flags.txt")
+          scripts\package-windows.ps1 -NoBuild -BuildFlags $flags -SdlRoot $env:SDL3_ROOT
+          exit $LASTEXITCODE
+      - uses: actions/upload-artifact@v4
+        if: ${{ !cancelled() && steps.package.outcome == 'success' }}
+        with:
+          name: MetalCreator-windows-x64
+          path: MetalCreator/dist/MetalCreator-*-windows-x64.zip
       - name: Mark a red Windows suite
         # The job is continue-on-error, so a red Windows run still shows a green check: say so where it is read.
-        if: ${{ !cancelled() && (steps.test.outcome == 'failure' || steps.smoke.outcome == 'failure') }}
+        if: ${{ !cancelled() && (steps.test.outcome == 'failure' || steps.smoke.outcome == 'failure' || steps.release.outcome == 'failure' || steps.package.outcome == 'failure') }}
         run: |
           Write-Output "::warning::Windows suite red (continue-on-error)"
-          "### Windows suite red (continue-on-error)`n`nTest step: ${{ steps.test.outcome }}; self-test and launch smoke: ${{ steps.smoke.outcome }}. The run shows green because this job does not fail it; read the Windows log." >> $env:GITHUB_STEP_SUMMARY
+          "### Windows suite red (continue-on-error)`n`nTest step: ${{ steps.test.outcome }}; self-test and launch smoke: ${{ steps.smoke.outcome }}; release build: ${{ steps.release.outcome }}; package: ${{ steps.package.outcome }}. The run shows green because this job does not fail it; read the Windows log." >> $env:GITHUB_STEP_SUMMARY
```

The `METALUI_COMMIT` line in the first hunk's context is a placeholder for the value master has when this task runs (`1bdead8d` or newer; Step 0 of Task 1 brought it in): leave that line exactly as master has it, apply the rest of the hunks by meaning if the header comments have moved on.

- [ ] **Step 6: Update CLAUDE.md's pins** (the rest of CLAUDE.md is Task 9; do these now so the test goes green)

In CLAUDE.md replace `exit 0 and 12 "Test run with" lines; Linux, exit 0 and 11 (`CreatorOCCTTests` is macOS's twelfth; `CreatorImplicitTests` joined in 7c), and neither may print` with `exit 0 and 12 "Test run with" lines (…)` as Task 9's diff shows, and the `scripts/linux-test.sh` command line's `(11 "Test run with" lines)` with `(12 "Test run with" lines)`.

- [ ] **Step 7: Verify**

```bash
swift test --filter CIPinTests 2>&1 | grep -E "recorded an issue|Test run"      # PASS, 8 tests
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/xp.yml')); print('yaml ok')"
swiftlint lint --strict --quiet
git add .github packaging scripts Tests CLAUDE.md
git commit -m "ci(xp): Windows OpenCascade from vcpkg 7.9.3, DLL-carrying zip, buildx-cached Linux OpenCascade, 12 runs; pinned numbers agree" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

- [ ] **Step 8: Push an `xp-*` branch and read the Windows log (CI only)**

`git push origin xp-2:xp-2-ci` (any `xp-*` name). Read **both** jobs' logs (the Windows job is `continue-on-error`, so a red run shows green; the `::warning::` step and the summary say so). First-run expectations: the vcpkg step builds OpenCascade twice (release and debug: tens of minutes to over an hour the first time, then the cache is saved at once, so a red step after it does not lose it); then `swift build` against `OCCT_PREFIX`; then 12 "Test run with" lines; then the release build and the zip. What to look at first if it is red: (1) the vcpkg step's own `vcpkg did not install: …` listing: the port's file names differ from what `Package.swift` links (user decision 8); (2) a link error naming `TKernel.lib` — `OCCT_PREFIX` or `-L`; or lld-link's `/failifmismatch: mismatch detected for 'RuntimeLibrary'` or `'_ITERATOR_DEBUG_LEVEL'`, or an OCCT test dying at start-up with `0xC0000409` or `0xC0000374` — a C runtime mismatch (user decision 8: try its option (b), then (c)); (3) `ExportPathTests` — the UTF-8 path; (4) a test of `CIPinTests`, `DesktopEntryTests` or `ShimPortabilityTests` red on Windows only — line endings: look at `git ls-files --eol` in the checkout and at `.gitattributes`; (5) the step "Build release (for the zip)": the first release build with Swift 6.4 on Windows, the coroutine-splitting crash, or the timeout; (6) `package-windows.ps1`: `swiftCore.dll isn't under any of: …` (the runtime is elsewhere; the script prints what it searched), `neither llvm-objdump.exe … nor … dumpbin.exe`, or `can't find X.dll, needed by Y` (a DLL outside the search path it printed).

Tests added: **+8** (`CIPinTests`).

---

### Task 9: Documentation and the final checks

**Files:**
- Modify: `CLAUDE.md`, `docs/packaging.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/roadmap.md`

**No new MetalUI gap.** The application-id gap the packaging work would have logged, XP-G13 (SDL's `SDL_APP_ID`, which a Linux shell uses to match a window to its desktop entry), is answered in MetalUI master `b39d68d6` (`SDLPlatform.Options.applicationID`, defaulting to `launchingSingleInstance(id:)`'s id) and a separate adoption track adds its row and entry, marked fixed, to `docs/metalui-gaps.md` on master. This task therefore **adds no gap, no row and no entry** and does not edit the XP-G13 text; it relies on the fix (the window gets `AppBundleInfo.identifier` with no code change; `DesktopEntryTests` pins the match and that nothing overrides it) and its human check (XP-16) looks at the result beside MetalUI's own AP1. XP-G5's entry and row are amended to say xp-2 adopted it. (XP-G12 on master is the image-sniff gap, fixed and adopted; nothing here touches it.)

- [ ] **Step 1: Apply the documentation edits**

The unified diffs below are the edits. `CLAUDE.md`: the manifest paragraph, `KernelUnavailable`, the pass rules (12 everywhere, the `canImport(Metal) && canImport(CreatorOCCT)` rule), the command list (`linux-test.sh` options and `package`), and the toolchain notes (OpenCascade per OS, the portable shim rule). `docs/packaging.md`: new sections "Linux: a tarball", "Linux: an AppImage", "Windows: a zip", "Documents on Linux and Windows", "Signing". `docs/metalui-gaps.md`: XP-G5 amended, nothing for XP-G13. `docs/verification/human-checks.md`: group XP2 with XP-16 (Linux tarball, file type, icon and window grouping), XP-17 (Windows zip and file type), XP-18 (geometry from a Mac file on Linux and Windows), XP-19 (the Linux AppImage). `docs/roadmap.md`: the XP row.

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 131280b..b5be7d6 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -105,11 +105,13 @@ device tests and `PackagingScriptTests` are not run on Windows, and the test exe
 a layout tree overflowed Windows' 1 MB default thread stack).
 `Package.swift` has two lists, like MetalUI's: the targets that import no Apple
 framework are declared everywhere (`CreatorViewport` too: its model, camera and tools are portable and only the Metal renderer files
-are behind `#if canImport(Metal)`); `COCCT`, `CreatorOCCT`, `ViewportHarness`, `GraphPanelPreview` and `CreatorOCCTTests` are
-declared on macOS only until xp-2. On Linux and Windows the MetalUI dependency asks for the `SDL` and `AccessKit` traits and
+are behind `#if canImport(Metal)`); `ViewportHarness` and `GraphPanelPreview` are declared on macOS only, while `COCCT`,
+`CreatorOCCT` and `CreatorOCCTTests` are declared everywhere since xp-2 (OpenCascade 7.9 on every platform: `Package.swift` reads its
+install prefix from `OCCT_PREFIX`, default Homebrew's on macOS, `/opt/occt` on Linux, `C:/occt` on Windows, with per-platform linker
+flags: an `$ORIGIN/lib` rpath on Linux, DLLs on `PATH` or beside the executable on Windows). On Linux and Windows the MetalUI dependency asks for the `SDL` and `AccessKit` traits and
 `MetalCreatorApp` links `MetalUISDL` (`main.swift` picks `SDLPlatform` with `PortableTextSystem` over the installed fonts under
-`canImport(MetalUISDL)`). Off macOS the app runs over `KernelUnavailable` (every operation answers "Geometry isn't available on this
-platform yet.") and the viewport's place shows `ViewportPlaceholder` ("The 3D view isn't available on this platform yet."). The Image
+`canImport(MetalUISDL)`). The app runs over `OCCTKernel` on every platform (xp-2; `KernelUnavailable`, which answers "Geometry isn't available on this
+platform yet.", stays in `CreatorKernel` for tests of a platform without a kernel) and, off macOS, the viewport's place shows `ViewportPlaceholder` ("The 3D view isn't available on this platform yet."). The Image
 Field works everywhere: `GreyImageDecoder` decodes through MetalUI's `DecodedImage` (S2, gap XP-G4) on every platform. Rules
 for new code: no CryptoKit (use `SHA256`/`SHA1` in `CreatorGraph/Hashing`), no CoreGraphics, ImageIO, CoreText or Metal outside a
 `#if canImport(…)` file or block, keyboard shortcuts and modifier checks on MetalUI events say `.primary` (⌘ on macOS, Ctrl
@@ -119,8 +121,9 @@ count, never from macOS's; render tests take their text system from `testTextSys
 `Support/TestTextSystem.swift`; picture fixtures come from `TestImages` (ImageIO on macOS, `PNGWriter` elsewhere; JPEG, GIF and
 TIFF fixtures need ImageIO, so those tests are `#if canImport(CoreGraphics)`, and `GreyImageDecoderPinnedTests` carries JPEGs as
 bytes for every platform) and `AppTestImages` (plain Swift). Pass
-rules: macOS, exit 0 and 12 "Test run with" lines; Linux, exit 0 and 11 (`CreatorOCCTTests` is macOS's twelfth; `CreatorImplicitTests` joined in 7c), and neither
-may print "recorded an issue" or "failed after".
+rules: macOS, Linux and Windows, exit 0 and 12 "Test run with" lines (`CreatorOCCTTests` joined Linux and Windows in xp-2, and a shim, kernel
+or test that needs OpenCascade is no longer gated by `canImport(CreatorOCCT)` alone: one that also needs Metal says `canImport(Metal) &&
+canImport(CreatorOCCT)`), and none may print "recorded an issue" or "failed after".
 
 Module boundaries (dependency order):
 - `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
@@ -731,7 +734,9 @@ scripts/verify-app.sh [path.app]           # re-check a packaged app: signature,
 swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
 scripts/bench.sh [suite]                   # spec §7.3 benchmarks, release build; numbers go in docs/verification/performance.md
 scripts/bench.sh PatternBench              # patterns spec §7: 200 holes in a plate, edit-to-preview (idle Mac only)
-scripts/linux-test.sh [build|test|smoke|all]   # the suite on Linux in Docker (OrbStack): swift build, swift test (11 "Test run with" lines), --self-test, --smoke-test 20
+scripts/linux-test.sh [build|test|smoke|all]   # the suite on Linux in Docker (OrbStack): swift build, swift test (12 "Test run with" lines), --self-test, --smoke-test 20
+scripts/linux-test.sh test --filter CreatorOCCTTests   # one target on Linux (no count rule); XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 keep a track's volume and image apart
+scripts/linux-test.sh package              # the tarball and the AppImage in dist/, each run in a clean ubuntu:24.04 (docs/packaging.md)
 swift run MetalCreatorApp --smoke-test 5   # a Linux or Windows build: the real window over SDL's offscreen renderers; exit 0 if a first frame was drawn
 ```
 
@@ -751,9 +756,18 @@ SwiftLint is configured in `.swiftlint.yml` (each non-default setting is documen
 - Local toolchain: Apple Swift 6.4, arm64 macOS. Linux runs in Docker on this Mac (`scripts/linux-test.sh`: MetalUI's `metalui-portable`
   image, built from `../MetalUI/Backends/SDL/linux/Dockerfile`, plus a font, `scripts/linux/Dockerfile`); build products live in a Docker
   volume named for the track (`XP_TRACK`, default `xp-1`), and a run stops only its own container. MetalUI must be a sibling checkout.
-  Windows cannot be run here: it is CI's job (`.github/workflows/xp.yml`; it builds and launches, two tests are red, see the xp-1 paragraph).
+  The image also holds OpenCascade 7.9 (xp-2); its first build takes minutes, then Docker's layer cache keeps it.
+  Windows cannot be run here: it is CI's job (`.github/workflows/xp.yml`; it builds, tests with OpenCascade from vcpkg, launches and packages).
 - The Windows Swift 6.4 toolchain asserts in LLVM's coroutine splitting (`CoroFrame.cpp`, "Layout->getElementOffset") on an `async` function that holds a loop's locals across an `await` (`DrainHoles.drainPoints` did); keep the synchronous work in a non-async helper.
 - Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
-- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
-  Linker warnings about dylibs built for a newer macOS are expected.
+- OpenCascade 7.9 comes from Homebrew on macOS (`brew install opencascade`, linked from `/opt/homebrew/opt/opencascade`; linker
+  warnings about dylibs built for a newer macOS are expected), from source on Linux (the `occt` stage of `scripts/linux/Dockerfile`,
+  V7_9_3 at a pinned commit, installed in `/opt/occt`) and from vcpkg on Windows (the `opencascade` port at 7.9.3 in CI, release and debug libraries, triplet `x64-windows`: a debug
+  build links `debug/lib`, a release build `lib`, so the C runtime matches; pinned by `VCPKG_COMMIT` in `.github/workflows/xp.yml` and
+  `packaging/windows/vcpkg.json`). The shim (`Sources/COCCT`) must stay portable:
+  no `M_PI` (use `cocct::kPi`), no POSIX headers, no `__attribute__`; `ShimPortabilityTests` scans for them. Release packages:
+  `scripts/package-linux.sh` (tarball), `scripts/package-appimage.sh` (AppImage, packed from the tarball's tree; its appimagetool and runtime are pinned build-time downloads, not dependencies), `scripts/package-windows.ps1` (zip, CI only). Text that a test reads or a script runs
+  (`packaging/`, `scripts/`, `.github/`, `Sources/COCCT/`, `CLAUDE.md`) is checked out with LF on Windows too (`.gitattributes`,
+  pinned by `CIPinTests`): Swift reads "\r\n" as one Character, so a test that splits on "\n" finds nothing in a CRLF file; a test
+  that reads such a file replaces "\r\n" with "\n" first.
 - Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
````

```diff
diff --git a/docs/metalui-gaps.md b/docs/metalui-gaps.md
index f6ff2a1..e4dad6a 100644
--- a/docs/metalui-gaps.md
+++ b/docs/metalui-gaps.md
@@ -66,5 +66,5 @@ stopgap as they were. The sections below keep each gap's full use case.
 | XP-G11 | A window-drag handle above a full-window pointer-taking view gets no SDL drag region (S1, divergence 426) | MetalUI S1b (PR #87, ruling CW-V) | ✅ fixed by MetalUI S1b (PR #87, master `a4ebe288`, ruling CW-V), adopted (branch `xp-adopt-s1b`, CI pin `a4ebe288`): a hitbox carves a `WindowDragGesture` handle only if it ranks strictly above the handle's own hitbox (layer, registration index), and the title band has no element of its own: every blocker carves it except a backdrop (a blocker as wide as the window that reaches below the band), which MetalCreator's full-window viewport is. Buttons, fields and taps in the bar still carve (divergence 426). Divergence 425 is amended: a window-wide pointer-taking view behind the bar loses its presses inside the band to the drag; nothing in MetalCreator relies on a viewport press there. `SDLChromeWindowTests` no longer pins it: the band and the bar's regions are asserted on macOS with the real viewport |
 | XP-G4 | Grey pixels and EXIF orientation from PNG/JPEG without ImageIO | MetalUI S2 (record §113, `IB-`, PR #84) | ✅ fixed by MetalUI S2 (master `dea698ca`), adopted (branch `adopt-s2`): `GreyImageDecoder` decodes through `DecodedImage(data:format: .rgba)` on every platform, so the Image Field works on Linux and Windows; ImageIO is gone from `Sources`, and so are `GreyImageDecoder+ImageIO.swift`, `ImageProblem.platformUnsupported` and its sentence. Left open at MetalUI: XP-G10 (a header-only read) |
-| XP-G5 | Open-document events on SDL (divergence 176) | answered | ✅ answered by MetalUI (`Platform.onOpenURLs` → `.onOpenURL`; command-line files via `app.open(…)` after the first window; `.desktop` `Exec=… %F` + `MimeType=`); xp-2's (packaging), not adopted in xp-1. **Single instance (MetalUI S7, PR #99, CI pin `4d91f27f`, branch `s7-adopt`):** a second launch on Linux and Windows forwards its document to the running instance and exits (`SDLPlatform.launchingSingleInstance`, id `AppBundleInfo.identifier`; the smoke test stays offscreen and claims nothing), human check XP-15 |
+| XP-G5 | Open-document events on SDL (divergence 176) | answered | ✅ adopted by xp-2 (desktop entry, MIME type, icon, tarball and AppImage, `register-mcgraph.ps1`, several command-line documents; `DesktopEntryTests`); ✅ answered by MetalUI (`Platform.onOpenURLs` → `.onOpenURL`; command-line files via `app.open(…)` after the first window; `.desktop` `Exec=… %F` + `MimeType=`); xp-2's (packaging), not adopted in xp-1. **Single instance (MetalUI S7, PR #99, CI pin `4d91f27f`, branch `s7-adopt`):** a second launch on Linux and Windows forwards its document to the running instance and exits (`SDLPlatform.launchingSingleInstance`, id `AppBundleInfo.identifier`; the smoke test stays offscreen and claims nothing), human check XP-15 |
 | XP-G6 | `ContentType` filtering by extension (divergence 129) | answered | ✅ answered and already in use: every `ContentType` the file panels use declares `filenameExtensions` (`ContentType+MetalCreator`, `+Images`, `+Theme`), pinned by `ContentTypeTests`; nothing to change for xp-1 |
 | XP-G7 | Clipboard types beyond text (graph fragments) | MetalUI S3 (queued) | 🔄 queued at MetalUI. Nothing to do in xp-1: MetalCreator's graph-fragment clipboard is in memory (`NodeClipboard`) and never reaches the system pasteboard on any platform; a system clipboard (marked JSON text now, S3's custom types later) is a feature of its own |
@@ -1155,5 +1155,9 @@ Labelled XP-G3 to XP-G8, plus XP-G9 added by this plan and XP-G10 by the S2 adop
   command-line files go through `app.open(…)` after the first window (MetalUI `docs/packaging.md`, "Launch arguments"); the
   `.desktop` file carries `Exec=… %F` and `MimeType=`. Linux and Windows packaging is xp-2, so xp-1 adopts nothing; the
-  command-line path already reaches the app the same way (`MetalCreatorApp [file.mcgraph]`).
+  command-line path already reaches the app the same way (`MetalCreatorApp [file.mcgraph]`). **Adopted by xp-2:** the desktop entry
+  (`packaging/linux/com.metalcreator.MetalCreator.desktop`, `Exec=MetalCreator %F`, `MimeType=application/x-metalcreator-graph;`) and
+  its MIME type XML ship in the Linux tarball with `install.sh` and, with the icon, in the AppImage, `register-mcgraph.ps1` registers the Windows file type, and
+  `LaunchCommand` takes several documents (`%F` passes all the selected files). `Platform.onOpenURLs` needed no code: `App.onOpenURL`
+  is already set before `app.run()`. Pinned by `DesktopEntryTests` and `LaunchCommandTests`; human checks XP-16, XP-17 and XP-19.
 - **XP-G6. `ContentType` filtering by extension.** Answered (`ContentType("…", conformingTo: [.json], filenameExtensions: ["mcgraph"])`
   in `allowedContentTypes`), and MetalCreator had it already: `mcgraph`, `step`, `stl`, `png`, `jpeg` and `mctheme` declare their
```

```diff
diff --git a/docs/verification/human-checks.md b/docs/verification/human-checks.md
index 1e3f1aa..46205a4 100644
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -2021,2 +2021,32 @@ named "Insole").
   a lattice bracket with a solid skin, drain holes in the bottom, and no warnings in the summary (7c-3f: 0 voids and 0 thin places, at the TPMS's default `blend`). Pinned:
   `LightweightBracketAcceptanceTests`. **Observed:**
+
+## Group XP2 — OpenCascade, packaging and documents on Linux and Windows (xp-2)
+
+**Status: NOT RUN.** Plan `2026-10-21-xp-2-occt-linux-windows.md`; spec `docs/superpowers/specs/2026-10-13-cross-platform-design.md` §3 and
+§5 (XP-G5). CI proves the suite (twelve "Test run with" lines), the app's `--self-test` (OpenCascade builds, measures, meshes and
+exports a cube) and, for the tarball and the AppImage, a run in a clean Ubuntu (the AppImage with `--appimage-extract-and-run`, no FUSE); these checks are what needs a desktop.
+
+- [ ] **XP-16 Linux tarball, file type, icon and window grouping.** Unpack `MetalCreator-<version>-linux-<arch>.tar.gz` on a desktop (GNOME and KDE), run
+  `./install.sh`, then double-click a `.mcgraph` file in the file manager: MetalCreator opens with that file; with it running, double-click
+  a second one: no second window, the running one opens it. Select two `.mcgraph` files and Open With MetalCreator: the last one is
+  open. `./MetalCreator --self-test` prints `ok` for the kernel and both exports. Then start MetalCreator from the application grid (not
+  from a terminal), on GNOME (Wayland) and in an X11 session (GNOME on Xorg, or KDE): the window must group under the "MetalCreator"
+  entry with the placeholder icon (a light square on dark grey), not under a generic icon or the executable's name. The window's
+  application id is `com.metalcreator.MetalCreator`: MetalUI sets SDL's `SDL_APP_ID` from the id `launchingSingleInstance` is given
+  (MetalUI master `b39d68d6`, gap XP-G13, fixed) and the entry's `StartupWMClass` names the same id. This is MetalUI's own check AP1
+  for MetalCreator's entry; if the icon or grouping is wrong, start once with `SDL_APP_ID=com.metalcreator.MetalCreator ./MetalCreator`
+  and report both results to MetalUI. `./install.sh --remove` takes the entry, the type and the icon away. **Observed:**
+- [ ] **XP-17 Windows zip and file type.** Unzip `MetalCreator-<version>-windows-x64.zip` on a machine with no Swift, SDL or vcpkg,
+  run `MetalCreator.exe --self-test` (all `ok`), run `register-mcgraph.ps1`, double-click a `.mcgraph` in Explorer: it opens;
+  double-click a second: the running instance opens it. Windows warns about an unsigned download (spec section 6). **Observed:**
+- [ ] **XP-18 Geometry.** On Linux and on Windows, open the §7.2 bracket from a `.mcgraph` saved on a Mac: every node evaluates (no
+  "Geometry isn't available" badge), Mesh to Solid works on a meshed solid, and Export STEP writes a file that opens in a CAD viewer.
+  Pinned: the OCCT conformance suite and `AppAcceptanceTests` on Linux (CI) and Windows (CI). **Observed:**
+- [ ] **XP-19 Linux AppImage.** Copy `MetalCreator-<version>-linux-<arch>.AppImage` to a desktop with FUSE (GNOME and KDE), `chmod +x`
+  it and double-click it (or run it): the window opens with the icon and grouping XP-16 describes (an integration tool such as
+  AppImageLauncher may offer to add it to the menu: accept once and check the entry it makes). `./MetalCreator-….AppImage
+  --appimage-extract-and-run --self-test` prints `ok` for the kernel, both exports and the shaders. `./MetalCreator-….AppImage
+  path/to/part.mcgraph` opens that file. The AppImage does not register the `.mcgraph` type itself (plan decision 2): register it with
+  the three commands in `docs/packaging.md` ("Linux: an AppImage") or through the integration tool, then double-click a `.mcgraph`: it
+  opens, and a second double-click goes to the running instance. **Observed:**
```

```diff
diff --git a/docs/roadmap.md b/docs/roadmap.md
index a10fd81..f8dc782 100644
--- a/docs/roadmap.md
+++ b/docs/roadmap.md
@@ -14,5 +14,5 @@ and its own plans in `docs/superpowers/plans/`. The order below is the build ord
 | 7c | Implicit geometry and lattices | `2026-10-13-implicit-lattices-design.md` | in progress: 7c-1, 7c-1g, 7c-2, 7c-3 and 7c-3f are merged; 7c-3's two known issues (trapped voids and thin walls, erratum M5) are resolved by 7c-3f (erratum D18: a blended skin join and robust checks; merged with the acceptance met: 0 voids, 0 thin walls; human check IL-10 pending); 7c-4 conformal is next |
 | 7d | Surface textures (knurl, hex, voronoi, embossed skins by displacement) | not written | after 7c |
-| XP | Cross-platform: Linux and Windows on MetalUI's SDL backend | `2026-10-13-cross-platform-design.md` | xp-1 (everything but the viewport and OCCT) merged; then xp-2 (OCCT), xp-c (GPU meshing on SDL3) and xp-3 (the viewport on SDL GPU) |
+| XP | Cross-platform: Linux and Windows on MetalUI's SDL backend | `2026-10-13-cross-platform-design.md` | xp-1 (everything but the viewport and OCCT) merged; xp-2 (OpenCascade 7.9 on Linux and Windows, Linux tarball and AppImage and Windows zip, open-document events; plan `2026-10-21-xp-2-occt-linux-windows.md`); then xp-c (GPU meshing on SDL3) and xp-3 (the viewport on SDL GPU) |
 | 8 | Variants and versions UI | not written (graph parameters are already designed for it, slice spec §4.1) | after 7 |
 | 9 | **Class A surfaces** | not written | after 8 (added 2026-10-14) |
```

`docs/packaging.md` (new text appended after "Documents"; the first lines and "Not yet" are edited as shown):

````diff
diff --git a/docs/packaging.md b/docs/packaging.md
index a0ca982..3166203 100644
--- a/docs/packaging.md
+++ b/docs/packaging.md
@@ -1,7 +1,9 @@
-# Packaging MetalCreator.app
+# Packaging MetalCreator
 
-How to build, check and (by hand) notarize the app. The design and its reasons:
-`docs/superpowers/specs/2026-10-09-packaging-design.md`.
+How to build, check and (by hand) notarize the macOS app (`MetalCreator.app`, below), and how the Linux tarball, the Linux AppImage and
+the Windows zip are built (further down, from "Linux: a tarball"). The macOS design and its reasons:
+`docs/superpowers/specs/2026-10-09-packaging-design.md`; Linux and Windows are sub-project xp-2 of
+`docs/superpowers/specs/2026-10-13-cross-platform-design.md` (section 3), plan `docs/superpowers/plans/2026-10-21-xp-2-occt-linux-windows.md`.
 
 ## Build
 
@@ -76,7 +78,7 @@ If the submission is rejected, `xcrun notarytool log <submission id> --keychain-
 
 ## Not yet
 
-No app icon (Finder shows the generic one), no disk image and arm64 only.
+No app icon on macOS (Finder shows the generic one; the Linux files carry a placeholder), no disk image and arm64 only.
 
 ## Documents
 
@@ -88,3 +90,117 @@ open. No `NSDocumentClass` is declared; MetalUI's probe (`docs/probes/appkit-ope
 AppKit's "cannot open files in this format" alert only for an application delegate without `application(_:open:)`,
 which MetalUI's has. A Finder double-click and a Dock drop themselves are human checks AS-6 and AS-7 (MetalUI has not
 measured them either, its AS9).
+
+## Linux: a tarball
+
+```sh
+scripts/linux-test.sh package      # on this Mac, in Docker (OrbStack); CI runs the same on x86_64 and aarch64
+scripts/package-linux.sh           # on a Linux machine with Swift 6.4, SDL 3.4, AccessKit, OpenCascade 7.9 and patchelf
+```
+
+write `dist/MetalCreator-<version>-linux-<arch>.tar.gz`. Unpacked, the folder holds `MetalCreator` (a release build), `lib/` (the Swift
+runtime's libraries, OpenCascade's `libTK*.so.7.9`, `libSDL3.so.0` and whatever else `ldd` names that is not glibc or
+the C++ runtime; linking the Swift runtime statically does not work with Foundation here), `MetalUISDLShaders/` (MetalUI's compiled SDL shaders, which the backend looks for beside the executable first,
+ruling `PX-P`), `share/applications/com.metalcreator.MetalCreator.desktop`, `share/mime/packages/com.metalcreator.MetalCreator.xml`,
+`share/icons/hicolor/256x256/apps/com.metalcreator.MetalCreator.png` (a placeholder icon), `install.sh` and `share/doc/metalcreator/` (the licences: OpenCascade's LGPL 2.1 and its exception, MetalUI's third-party notices and the
+licence files they name). The executable's RUNPATH is set to `$ORIGIN/lib` and each bundled library's to `$ORIGIN` (`patchelf`; the
+build's `/opt/occt/lib` and the toolchain's `/usr/lib/swift/linux` are left out), so the folder runs from anywhere and finds
+only its own libraries. It still needs the machine's glibc (the build image is Ubuntu 24.04, glibc 2.39), libstdc++ and, to draw, a
+Vulkan driver.
+
+`scripts/linux-test.sh package` then unpacks the tarball in a clean `ubuntu:24.04` (no Swift, no `/opt/occt`, no MetalUI checkout) and
+runs `--version` and `--self-test` there: OpenCascade builds, measures, meshes and exports a cube, and the SDL shaders are found beside
+the executable. It also runs `desktop-file-validate` on the entry. The AppImage (next section) is packed from this same tree; both are shipped (user decision 2 of the xp-2 plan).
+
+OpenCascade itself is built from source (commit `a016080b…`, tag `V7_9_3`) in the `occt` stage of `scripts/linux/Dockerfile`; the
+toolkits are listed there. Raising the version means changing `OCCT_COMMIT` and rebuilding the stage (about 13 minutes with 6 jobs on
+this Mac). Locally Docker's layer cache keeps it; in CI buildx's cache in the GitHub Actions cache does (scope `xp-occt-<arch>`;
+GitHub evicts an entry unused for seven days, and the least recently used ones when the repository passes 10 GB, and the next run then
+builds it again; a branch's caches are visible to that branch and the default branch only).
+
+## Linux: an AppImage
+
+```sh
+scripts/linux-test.sh package      # the tarball, then the AppImage from it, each run in a clean ubuntu:24.04
+scripts/package-appimage.sh        # on a Linux machine, after scripts/package-linux.sh
+```
+
+write `dist/MetalCreator-<version>-linux-<arch>.AppImage`. It holds the tarball's tree (so the same libraries, the same `RUNPATH
+$ORIGIN/lib` and `MetalUISDLShaders`) as `usr/metalcreator` in an AppDir whose root has `AppRun`, the same desktop entry and icon the
+tarball installs, and a `.DirIcon` link; appimagetool packs it. The tool is appimagetool 1.9.1 and the runtime the type2 runtime
+20251108, both third-party and both fetched by the script while packaging, pinned by version and sha256 and checked before they run.
+They are no dependency of MetalCreator (nothing links them; a version bump changes the hashes in `scripts/package-appimage.sh`, whose
+presence `AppImageRecipeTests` checks). No FUSE is needed to build or check the file: appimagetool runs with
+`--appimage-extract-and-run`, and so does the clean-Ubuntu run (`./MetalCreator-….AppImage --appimage-extract-and-run --self-test`).
+Running an AppImage normally needs FUSE on the user's machine, as every AppImage does; without it the same flag runs it. The packer
+adds a download of about 16 MB (kept in `dist/tools`) and one squashfs compression of the tarball's tree to `package`; with a stub
+tree the script took 1.3 s, and the time on the real tree is recorded in the plan's measured results once it has been run.
+
+The AppImage does not register the `.mcgraph` type itself (plan decision 2: `install.sh` registers the folder it sits in, and an
+AppImage has no stable folder). An AppImage integration tool such as AppImageLauncher or appimaged installs the image's desktop entry;
+the MIME type can be registered by hand:
+
+```sh
+./MetalCreator-<version>-linux-<arch>.AppImage --appimage-extract 'usr/metalcreator/share/mime/packages/*.xml'
+install -D -m 644 squashfs-root/usr/metalcreator/share/mime/packages/com.metalcreator.MetalCreator.xml \
+    ~/.local/share/mime/packages/com.metalcreator.MetalCreator.xml
+update-mime-database ~/.local/share/mime
+```
+
+Human check XP-19 runs it on a desktop.
+
+## Windows: a zip
+
+CI's Windows job runs `scripts\package-windows.ps1` (nothing here runs on Windows; the job is the only check):
+
+```powershell
+scripts\package-windows.ps1 -BuildFlags @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB", …) -SdlRoot $env:SDL3_ROOT
+```
+
+It writes `dist\MetalCreator-<version>-windows-x64.zip` with `MetalCreator.exe`, every DLL the executable needs beside it (OpenCascade's
+from `OCCT_PREFIX\bin`, `SDL3.dll`, the Swift runtime's and the Visual C++ runtime's, found by following the `DLL Name:` lines of
+`llvm-objdump -p` (or `dumpbin /dependents` when the toolchain has no objdump); Windows' own DLLs are left out), `MetalUISDLShaders\`,
+`register-mcgraph.ps1` and `licenses\`. The Swift runtime's folder is looked up (by `swiftCore.dll`, under the `Swift` folder that
+`swift.exe` and `SDKROOT` sit in), not written down. The script then unpacks the zip and runs `--self-test` with only Windows'
+folders on `PATH` and MetalUI's checkout moved aside (the SDL backend falls back to the shaders in its source tree), so a missing DLL
+or shader directory fails the job. It packages a release build: CI makes it in its own step (`swift build -c release --product
+MetalCreatorApp`, then `-NoBuild`), because the suite is a debug build.
+
+OpenCascade on Windows is vcpkg's `opencascade` port at 7.9.3, release and debug libraries (triplet `x64-windows`), pinned by the
+vcpkg commit in `.github/workflows/xp.yml` (`VCPKG_COMMIT`), which `packaging/windows/vcpkg.json` repeats as its `builtin-baseline`
+(`CIPinTests` checks they agree). Both sets are installed because the suite is a debug build: `Package.swift` links `debug/lib` for a
+debug build and `lib` for a release one, so Swift's and the shim's C runtime is the same as OpenCascade's on each side. To build on your
+own Windows machine: install vcpkg at that commit, run
+`vcpkg install --triplet x64-windows --x-manifest-root=packaging\windows --x-install-root=C:\occt-install`, and set
+`OCCT_PREFIX=C:/occt-install/x64-windows` and `PATH` to its `debug\bin` (for `swift test`) or `bin` (for a release build) before
+`swift build`. CI saves vcpkg's binary cache right after the install, so a later red step does not lose the build.
+
+`Package.swift` reads `OCCT_PREFIX` on every platform; its defaults are Homebrew's prefix on macOS, `/opt/occt` on Linux (the test
+image's) and `C:/occt` on Windows.
+
+## Documents on Linux and Windows
+
+A file manager runs `MetalCreator %F` (the desktop entry's `Exec=`) or `MetalCreator.exe "%1"` (the file type
+`register-mcgraph.ps1` registers). `LaunchCommand` takes every leading non-flag argument as a document; `main.swift` hands them to
+MetalUI as `app.open(…)` after the first window, and MetalUI's single-instance forwarding (S7) sends the paths of a second launch to
+the running instance, which opens them through `App.onOpenURL` and `AppModel.openRequested(_:)`. A file dropped on the application
+itself (SDL's drop with no window) reaches the same handler as `Platform.onOpenURLs` (gap XP-G5). Several files leave the last one open,
+as on macOS.
+
+On Linux, `install.sh` (run from the unpacked folder) copies the desktop entry to `~/.local/share/applications` with `Exec=` pointing
+at the folder's `MetalCreator`, the MIME type `application/x-metalcreator-graph` (glob `*.mcgraph`, a kind of `application/json`)
+to `~/.local/share/mime/packages` and the placeholder icon to `~/.local/share/icons/hicolor/256x256/apps`, then runs
+`update-mime-database` and `update-desktop-database` where they exist. `install.sh --remove` undoes it. The entry says
+`Icon=com.metalcreator.MetalCreator` and `StartupWMClass=com.metalcreator.MetalCreator`. A desktop shell matches the running window to
+the entry by the window's application id, which is that name: MetalUI sets SDL's `SDL_APP_ID` hint from the id
+`SDLPlatform.launchingSingleInstance(id: AppBundleInfo.identifier, …)` is given (MetalUI `docs/packaging.md`, section 3; gap XP-G13,
+fixed), so MetalCreator sets nothing itself. The icon is a placeholder (`packaging/linux/com.metalcreator.MetalCreator.png`).
+The AppImage carries the same entry and icon and leaves the file type to a manual step (see its section).
+
+On Windows, `register-mcgraph.ps1` (run from the unpacked folder, no administrator rights) writes the `.mcgraph` association under
+`HKEY_CURRENT_USER\Software\Classes`; `-Remove` deletes it. The Linux files and the Windows script are not verified on a desktop: human checks XP-16, XP-17 and XP-19.
+
+## Signing
+
+None of the tarball, the AppImage and the zip is signed (user decision 3; spec section 6: Windows signing is out of scope). Windows SmartScreen warns about an
+unsigned download.
````

- [ ] **Step 2: Check the whole tree**

```bash
swiftlint lint --strict --quiet                                  # no output
grep -rn "11 \"Test run with\"\|EXPECTED_TEST_RUNS: 11\|EXPECTED_TEST_RUNS:-11" CLAUDE.md scripts .github || echo "no stale 11"
swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning: building for macOS"      # no output
```

- [ ] **Step 3: One full run on the Mac (after the last task only)**

```bash
swift test > /tmp/xp2-full.log 2>&1; echo "exit $?"
grep -c "Test run with" /tmp/xp2-full.log                         # 12
grep -cE "recorded an issue|failed after" /tmp/xp2-full.log       # 0 (the lines that matter start with the glyph 􀢄)
```
Pass only if the exit code is 0, nothing says "recorded an issue" or "failed after" as a verdict (check lines that begin with `􀢄`, since parameterised test names can contain the words), and 12 "Test run with" lines appear. Kill nothing broadly while it runs.

- [ ] **Step 4: One full run on Linux**

`XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 scripts/linux-test.sh all` → `Linux: PASS (12 'Test run with' lines, N tests …)`, then the self-test and the 20-second smoke test; then `scripts/linux-test.sh package` (the tarball and the AppImage, each checked in a clean Ubuntu; the AppImage step needs the network).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: xp-2 packaging (tarball, AppImage, zip), OpenCascade per OS, XP-G5 adopted, human checks XP-16..XP-19" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
```

Tests added: **0**.

---

## Self-Review

**1. Spec coverage (section 3, errata, xp-2 mentions in section 5/6).**
- OCCT 7.9 on Linux, from source or a pinned build in the CI image: Task 2 (pinned commit, own stage, cache). On Windows, pinned vcpkg: Task 8. DLLs beside the executable: Task 8 (`package-windows.ps1`); on `PATH` for the suite: Task 8's workflow.
- Per-OS flags, `.when(platforms:)`, `$ORIGIN` rpath on Linux: Task 3.
- `COCCT`, `CreatorOCCT`, `CreatorOCCTTests` to the portable list; `ViewportHarness` and `GraphPanelPreview` stay macOS-only: Task 3.
- The app uses `OCCTKernel`; Mesh to Solid, STEP export and `--self-test`'s OCCT checks work: Task 4 (Linux measured; Windows by CI).
- OCCT and acceptance tests on Linux and Windows in CI; the count becomes 12; every pin of 11 updated (the CI log check, `scripts/linux-test.sh`, `CLAUDE.md`, the workflow header comments): Tasks 2, 8, 9, held by `CIPinTests`.
- Packaging: Linux tarball (Task 6), Linux AppImage (Task 7, packed from the tarball's tree), Windows zip (Task 8), all with `MetalUISDLShaders`; `docs/packaging.md` current: Task 9.
- SDL's application id (XP-G13, answered by MetalUI `b39d68d6`): relied on, not worked around; `StartupWMClass` pinned to `AppBundleInfo.identifier` and the absence of an override pinned in `DesktopEntryTests` (Task 5); human check XP-16.
- XP-G5: `Platform.onOpenURLs` (already routed; Task 5 comments it), command-line files (several), the `.desktop` file with `Exec=… %F` and `MimeType=`: Task 5.
- Constraints: shim portability (Task 1 and 3, scan + `NOMINMAX`); the OCCT thread pool and `OCCTKernel.serialized` untouched (the shim's threading is unchanged and the 197 OCCT tests pass on Linux); no async loops added; CI cache proposal and user decision (above); no secrets.
- Out of scope, as the spec says: Windows signing (decision 3), Wayland/X11 specifics, macOS CI.
- Gap: the spec's Errata E1 to E5 touch earlier sub-projects only; none changes xp-2 beyond E1 (named in the header).

**2. Placeholder scan.** No "TBD", "implement later", "similar to Task N". Code is shown whole for new files and as unified diffs for edits to existing files. Honest notes about what is unverified are in "Which steps run where" and Task 8 Step 8.

**3. Type and name consistency.** `cocct::kPi` (Tasks 1, 3); `LaunchCommand.run(paths:)`, `forwardedDocuments(paths:exists:)` (Task 5; `main.swift`, `LaunchCommandTests`); `AppBundleInfo.mimeType` (Task 5; `DesktopEntryTests`); `IMAGE`, `OCCT_IMAGE`, `OCCT_JOBS`, `XP_TRACK` (Tasks 2, 6, 7, 8); `VCPKG_COMMIT` equals the manifest's `builtin-baseline` (Task 8, pinned by `CIPinTests`); the appimagetool and runtime versions and hashes live in `scripts/package-appimage.sh` alone (Task 7, pinned by `AppImageRecipeTests`; the workflow names no tool, `CIPinTests`); `OCCT_PREFIX` read by `Package.swift`, set by the image's `ENV`, by CI and used by both packaging scripts.

**4. Review Focus.** Each of the six items has its pin: 1 → Task 5 tests (the `%` too); 2 → Task 4's `ExportPathTests`; 3 → the clean-Ubuntu runs (Task 6 for the tarball, with the RUNPATH trace; Task 7 for the AppImage, without FUSE) and the PATH-stripped, MetalUI-renamed zip check (Task 8); 4 → `CIPinTests`; 5 → `ShimPortabilityTests` and the vcpkg triplet pin in `CIPinTests`; 6 → `.gitattributes` and the CRLF replacement in the three tests that read repository text.

**5. Order dependency.** Tasks 4 and 5 both edit `main.swift` in disjoint places (kernel/imports vs. paths); in the scratch copy they were applied together and verified together. Task 2's image must be built before Task 3's Linux step; Task 6 needs Task 5's files (now the icon too); Task 7 needs Task 6's tarball and Task 5's entry and icon, and Task 2's `file`; Task 8's `CIPinTests` goes red only while the workflow and `CLAUDE.md` still say 11.

---

## Measured results (scratch copy, in task order)

These are the first authoring's measurements (the tree of Tasks 1 to 6 and 8 as first written (the numbers are today's: the AppImage task, 7, was inserted on 2026-10-21)); the review revision below changes the counts by +4.

- Mac: `swift build --build-tests` with no new warnings (the only warnings are master's `ld: warning: building for macOS-26.0, but linking with dylib … built for newer version 27.0`); each task's filtered tests pass; `swiftlint lint --strict` reports nothing.
- Linux (Docker, aarch64): OpenCascade 7.9.3 builds in 4,668 steps; `CreatorOCCTTests` 197 tests pass; the whole suite passed with 12 "Test run with" lines and 4,530 tests before Tasks 4's export test, 5's install tests and 7's pins (the filtered runs of those pass); `--self-test` and `--smoke-test 20` pass; the tarball (72 MB, 43 libraries) passes in a clean `ubuntu:24.04`; `install.sh` and `desktop-file-validate` pass.
- Not run (CI only): everything Windows, the buildx and `actions/cache` caches, the x86_64 Linux job, the YAML on GitHub.
- Mac, one full `swift test` after the last task: exit 0, 12 "Test run with" lines, no failure line, **4,672 tests = master 4,656 + 16** (Task 1 +2, Task 3 +1, Task 4 +1, Task 5 +7, Task 8 +5).
- Linux: the final tree's full suite was not re-run after Tasks 4 to 6 and 8 (the Mac was saturated); the filtered Linux runs of every test those tasks add pass (30 tests in `ExportPathTests`, `InstallScriptTests`, `DesktopEntryTests`, `LaunchCommandTests`, `CIPinTests`, `PackagingScriptTests`, `ShimPortabilityTests`). Task 9 Step 4 runs it once.

## Revision after review (what changed, what was run)

Seven review findings were checked against the sources: the CRLF checkout on Windows (fixed: `.gitattributes` in Task 1, the `"\r\n"` replacement in `ShimPortabilityTests`, `DesktopEntryTests` and `CIPinTests`, a pin test), the vcpkg cache that is saved only by a green job (fixed: `actions/cache/restore` plus `actions/cache/save` right after the install), the debug/release C runtime (fixed up front: vcpkg `x64-windows`, debug and release libraries, `Package.swift` links by configuration, two pin tests, decision 8 rewritten with the log lines that identify a mismatch), the Windows packaging assumptions (fixed: the runtime folder and the dependents tool are looked up, the release build is its own step, the timeout is 180 minutes, the risk is listed), `%` in the Linux install path (fixed: written `%%`, a test), the 10 GB cache cap (decision 4 states it and names the fallback; `mode=min` rejected: both cached targets are single-stage), and the Linux RUNPATH (fixed: `patchelf --set-rpath '$ORIGIN/lib'` on the shipped binary, asserted in the script and traced in the clean Ubuntu).

Re-verified in a scratch copy of master (a sibling of `../MetalUI`) with the revised code of Task 1 (shim, `ShimPortabilityTests`, `.gitattributes`), Task 3 (`Package.swift`, both manifest tests), Task 5 (packaging files, `AppBundleInfo.mimeType`, `DesktopEntryTests`, `InstallScriptTests`) and a `CIPinTests` cut down to the four tests whose files the scratch copy has: `swift build --build-tests` without new warnings; `ShimPortabilityTests`, `DesktopEntryTests`, `InstallScriptTests` and `CIPinTests` pass; with every one of the files they read converted to CRLF they still pass, and with the `"\r\n"` replacement removed `CIPinTests` fails (12 issues); with the old `install.sh` the `%` test fails; `swift package dump-package` shows the four Windows and Unix linker lists with their conditions; the workflow parses as YAML; `bash -n` accepts both shell scripts; `package-windows.ps1` parses with PowerShell 7 (no errors); `desktop-file-validate` accepts the entry written for a folder called `100% parts`; `patchelf --set-rpath '$ORIGIN/lib'` on the image's real `MetalCreatorApp` leaves `RUNPATH [$ORIGIN/lib]`, and a stand-in binary shows the `LD_DEBUG=libs` line the clean-Ubuntu check greps for. `swiftlint lint --strict` reports nothing. One full `swift test` in the scratch copy: exit 0, 12 "Test run with" lines, no "recorded an issue" or "failed after" line, **4,671 tests = master 4,656 + 15** (`ShimPortabilityTests` 4, `DesktopEntryTests` 3, `InstallScriptTests` 4, the cut-down `CIPinTests` 4).

Not run: everything Windows (the vcpkg debug libraries' file names, the runtime-mismatch outcome, the release build, `package-windows.ps1` beyond its parse and the runtime lookup), `scripts/linux-test.sh package` end to end (the release build of the app in the image was not repeated for a three-line change), and the Linux suite.

(Superseded by the 2026-10-21 revision at the end: +27.) Counts after the review revision: macOS **4,676** = master 4,656 + 20 (the first authoring's 16, measured as 4,672, plus 4: `theManifestLinksAWindowsDebugBuildAgainstTheDebugLibraries`, `aPercentSignInTheFoldersNameIsWrittenDoubled`, `theWindowsJobInstallsBothTheDebugAndTheReleaseLibraries`, `gitattributesKeepsTheTextTheTestsReadAndTheScriptsRunAtLF`). The scratch copy's 4,671 is the subset above (15 of the 20). The other five are `LaunchCommandTests` +1 and `ExportPathTests` +1 (Tasks 5 and 4, unchanged by this revision and measured in the first authoring) and three `CIPinTests` whose files (`scripts/linux-test.sh`, the Dockerfile, the project guide's new text) the scratch copy lacks; Task 9 Step 3 runs the whole tree once.

## Revision 2026-10-21 (the user's decisions and MetalUI's latest work)

What changed: (1) the decisions section records all eight as decided on 2026-10-21; decision 2 is **both a tarball and an AppImage**, so a new **Task 7** packs the AppImage and the Windows and documentation tasks became 8 and 9 (every reference was renumbered: the shared-files table, the file-structure table, the interfaces, the self-review, the measured results). (2) The icon: an AppDir needs one and the tarball's entry named none, so one placeholder PNG (`packaging/linux/com.metalcreator.MetalCreator.png`) is added to Task 5, the shared entry gains `Icon=`, `install.sh` installs and removes the icon in hicolor, the tarball ships it, and the AppImage uses the same two files (the entry is not duplicated); `.gitattributes` marks `packaging/**/*.png` binary. (3) XP-G13 is no longer a gap this plan adds: it relies on MetalUI `b39d68d6`, `StartupWMClass` is pinned to `AppBundleInfo.identifier` with a test that nothing overrides the id, and XP-16 checks icon and grouping on GNOME and X11 beside MetalUI's AP1. (4) The base is "rebase on master at execution start" with a Step 0 in Task 1 that merges master and re-measures the baseline; the MetalUI pin text is "1bdead8d or newer, whatever master pins at execution time". (5) `CIPinTests` pins that both Linux packages are uploaded and that the workflow names no packer.

Counts after this revision: macOS **master + 27** (Task 1 +2, Task 3 +2, Task 4 +1, Task 5 +10, Task 7 +4, Task 8 +8), which is 4683 on `11aab8e`; Linux and Windows go from 11 to 12 "Test run with" lines. Task 5 gained `theWindowClassIsTheApplicationIDTheAppHandsToMetalUI` and `theIconIsA256PixelPNGNamedAfterTheEntry` (the first authoring's +8 is +10), Task 7 adds `AppImageRecipeTests` (+4), Task 8's `CIPinTests` gained `theLinuxJobUploadsTheTarballAndTheAppImage` (+7 is +8). The Swift added in this revision (`AppImageRecipeTests`, the two `DesktopEntryTests`, the `InstallScriptTests` and `CIPinTests` changes) was written but **not compiled or run** (this revision was planning only); the first run of Tasks 5, 7 and 8 is its check.

Run on 2026-10-21 (planning only, no product code): the AppImage recipe end to end with a stub tree in the xp-2 image (aarch64, Docker, no FUSE): the pinned appimagetool 1.9.1 and runtime 20251108 downloaded and matched the hashes in the script (both architectures' hashes also recomputed from fresh downloads), `file` found missing and added to the image's package list, `package-appimage.sh` as written produced a 940 KB AppImage in 1.3 s, a clean `ubuntu:24.04` ran it with `--appimage-extract-and-run` and extracted the MIME XML, and `desktop-file-validate` (0.27) accepted the entry with `Icon=`. `bash -n` accepts the new `linux-test.sh`, whose diff was generated by applying Task 6's diff to Task 2's file and diffing the result. Not run: the real tree's AppImage (size, time, `--self-test`), x86_64, a desktop (XP-16, XP-19), and the licence of the type2 runtime's statically linked parts (the runtime and appimagetool are MIT; the runtime's README was not read for what it embeds: read it at execution and add a notice to the AppImage's `share/doc` if it asks for one).
