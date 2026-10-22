# xp-3: The 3D Viewport on SDL GPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `CreatorViewport` draws the real 3D view on Linux and Windows, over MetalUI's SDL GPU layer, with the passes the Metal renderer draws; macOS is unchanged in look, behaviour and test count.

**Architecture:** `ViewportModel` stops knowing which GPU API draws for it: it talks to a `ViewportBackend` (draw count, pick, pending pick). `MetalViewportBackend` wraps the existing `ViewportRenderer` and `ViewportPicker` untouched. `SDLViewportBackend` wraps a new `SDLViewportRenderer`, which plans a frame (every buffer made and every copy recorded, because SDL_GPU cannot copy inside a render pass), records the 4x-MSAA colour+depth pass into the surface's own command buffer, and an `SDLViewportPicker`, which renders the ID pass in a batch after the draw that follows a change and reads the `r32Uint` words back with `SDLGPUDevice.download`. Picking is user decision U4, **hybrid**: a hover answers from the latest landed buffer (it may lag, it never stalls) and a click is always exact, from a buffer for its own view (see U4 for the one case that still waits asynchronously, until MetalUI gap XP-G22). The shaders are HLSL (`Shaders/viewport`), **compiled at build time on Linux and Windows** (user decision U1(b)) by **MetalUI's `MetalUICompileShaders` tool** (MetalUI S12, `d995f4b4`) through a pinned SDL_shadercross into SPIR-V, DXIL and MSL files and a reflection JSON each in `Shaders/viewport/compiled`, which is generated, git-ignored and never checked in; the SDL renderer finds it beside the executable as `MetalUIAppShaders` or in the source tree. `scripts/build-shaders.sh` (Linux; `scripts/build-shaders.ps1` on Windows) runs the tool, built from the `../MetalUI` checkout with `swift run --package-path ../MetalUI --scratch-path …`, and `scripts/linux-test.sh` and the CI jobs run the script before `swift build`. What the typed layer lacked for the viewport (MetalUI gaps XP-G14 to XP-G19) **MetalUI answered in S11 (`11dca65e`)**, and XP-G20 (a build-time shader path) in S12 (`d995f4b4`); both are in master's MetalUI pin `5f03ab7b`, so no task waits for MetalUI and xp-3 does not bump the pin. One new gap, **XP-G22** (a blocking batch submit, so a click can render its own ID pass synchronously), is logged by task 0 and blocks nothing.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, MetalUI at `5f03ab7b` (`MetalUI`, `MetalUISDLGPU`, `MetalUIPortableText`, `MetalUISystemFonts`, and the `MetalUICompileShaders` executable), HLSL through SDL_shadercross (a build tool on Linux and Windows, pinned to `libsdl-org/SDL_shadercross` commit `1ff05bec573988a98ef9e0260b4da44f512b8367`, the pin MetalUI `docs/packaging.md` section 4a documents; macOS needs none), Mesa lavapipe (Linux, a CPU Vulkan driver) and Direct3D 12 WARP (Windows) for the render tests.

**Spec:** `docs/superpowers/specs/2026-10-13-cross-platform-design.md` section 4 (the viewport on SDL GPU) and erratum E1 (`CreatorViewport` is declared everywhere; only its renderers are fenced), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. This plan adds erratum **E7** to the cross-platform spec (task 9; E6 is adopt-s9's `ImageInfo` erratum, already on master).

**Revision of 2026-10-21 (user decisions).** U1 is now option (b): the HLSL is **compiled at build time** on Linux and Windows by a pinned SDL_shadercross, and **no compiled shader, hash file or blob is checked in** (Task 4, Task 9). U2, U3, U4, U5, U6, U7 and U8 are decided as recommended. XP-G14 to XP-G19 were forwarded to MetalUI on 2026-10-21; **XP-G20** (MetalUI has no build-time shader path) is new. The tests that used to recompute checked-in hashes are replaced by tests that the build produced every shader and that `--self-test` fails plainly without them; test counts, the CI time, the Risks and the shared-files rows follow.

**Revision of 2026-10-22 (start of execution).** The branch is rebased on master `1aad412` (xp-2 merged: OpenCascade on Linux and Windows, the tarball, AppImage and zip, 12 "Test run with" lines on every platform). MetalUI answered XP-G14 to XP-G19 (S11, `11dca65e`) and XP-G20 (S12, `d995f4b4`): task 0 logs them answered; tasks 10 to 12 no longer wait and use the real API (`setViewport(…) -> Bool`, `maxAnisotropy:`, `writesColor:`, `r32Float`); pipelines are made with `compileGraphicsPipeline(_:)`, whose `SDLGPUError` is the reason in `ViewportRenderError.deviceRefused`; the appendix that patched MetalUI is gone. `compile-app-shaders.py` is deleted from MetalUI, so the scripts run `MetalUICompileShaders` (task 4), and the Linux shadercross stage is now a native build per MetalUI section 4a (the libsdl-org DXC fork from source, measured there on Linux aarch64), copied into the test image the way xp-2's OpenCascade is, with no amd64 emulation. U4 is now **hybrid** (decided 2026-10-22). The human checks are XP-20 to XP-26 (xp-2 took XP-16 to XP-19) and the erratum is E7. Task 0, task 4's CI and Docker steps and task 9 are rewritten against master's `xp.yml`, `linux-test.sh`, Dockerfile and packaging scripts, and task 9 makes the packages ship the compiled shaders, which master's do not. The Windows compiler rules xp-2 learned are in the Global Constraints.

**Branch:** `xp-3` (worktree `../MetalCreator-xp-3`), rebased on master `1aad412` on 2026-10-22 (also `origin/main`). Baselines on that master: macOS full suite **4822 tests, 12 "Test run with" lines**; Linux and Windows **12 lines**; macOS `CreatorViewportTests` **304 tests in 41 suites** (re-measured on `1aad412`). MetalUI is the sibling `../MetalUI`, **read-only**; master pins `METALUI_COMMIT` `5f03ab7b0c591468bfa5d59edb5da1d5277e015e` (MetalUI S11, S12 and the XP-G21 Windows release-build fix), and every MetalUI name in this plan was checked against `5f03ab7b` (`git -C ../MetalUI show 5f03ab7b:<path>`).

## Global Constraints

- **The rebase is done** (2026-10-22, onto `1aad412`). If master moves again before a task, rebase again and take its counts as the baseline.
- **MetalUI answered XP-G14 to XP-G20** (S11 `11dca65e`, S12 `d995f4b4`; both in the pin `5f03ab7b`). No task waits for MetalUI; xp-3 needs MetalUI `5f03ab7b` or later and does not change `METALUI_COMMIT`, except in task 7 step 6, which adopts XP-G22 if MetalUI answers it. XP-G22 (task 0) blocks nothing: until it is answered, a click whose ID buffer has not landed waits for it asynchronously (U4).
- Swift 6 strict concurrency; Swift Testing; `@MainActor @Observable` models; behaviour in models and thin views; one type per file; no force unwraps or force `try`; no GCD; no `String(format:)` or legacy formatters (`CLAUDE.md`, `AGENTS.md`).
- `swiftlint lint --strict` reports zero violations before every commit.
- **The compiled shaders are never committed.** `Shaders/viewport/compiled` is git-ignored and made by `scripts/build-shaders.sh` (`.ps1` on Windows) through MetalUI's `MetalUICompileShaders`; `git status` after a build shows nothing new. macOS never runs the script and its 12 test lines do not change.
- Portability (`CLAUDE.md`, "Cross-platform"): no Metal outside `#if canImport(Metal)`, no SDL_GPU outside `#if canImport(MetalUISDLGPU)`, no CoreText, CoreGraphics, ImageIO, CryptoKit or `simd` outside a `#if canImport(…)` file or block.
- **The Windows Swift 6.4 compiler (learned in xp-1 and xp-2).** (1) Keep heavy loops out of `async` functions: put them in synchronous helpers (an `async` function that holds a loop's locals across an `await` asserts in coroutine splitting, `CoroFrame.cpp`). (2) Do not pass typed-throws closures to generic helpers. (3) In a release build, an `async` function that takes a closure and gets closure-specialised can crash the coroutine split: mark such a thin `async` wrapper `@_optimize(none)` with a comment saying why (master's `OccupancyGrid.fill(lipschitz:awaiting:)`, commit `42d1612`), and keep the heavy work in optimised synchronous helpers. (4) **Every task that changes code Windows compiles must pass CI's `swift build -c release` ("Build release (for the zip)" step), not only the debug build**; the Windows job is `continue-on-error`, so read its log. (5) The local check for Windows-sensitive portable code is the 6.4 asserts snapshot on this Mac, which reproduces these crashes: `TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release` (it compiles what macOS compiles; the `RenderSDL` files are Linux and Windows only, so CI is their check).
- A MetalUI gap goes in `docs/metalui-gaps.md` (the entry and the summary-table row) and is never worked around. **MetalUI is never modified**: no edit, no commit, and no build products written into `../MetalUI` (MetalUI's tool is built with `--scratch-path` outside it); `Package.swift`'s `.package(path: "../MetalUI", …)` line is never edited.
- A full `swift test` passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing uses glyphs, not ✘), and the number of "Test run with" lines is **12 on macOS, Linux and Windows** (xp-3 adds no test target). **The hard checks are the exit code, the issue lines and that line count.** Test totals are not: every "Test run with N tests" figure in this plan was measured on master `11aab8e` and is given with what the task adds (`baseline + n`); take the baselines in task 0 (step 3) and compare the delta. Master `1aad412`'s macOS figures: full suite 4822 tests, `CreatorViewportTests` 304 in 41 suites.
- Linux is verified with `scripts/linux-test.sh` in Docker (OrbStack), `XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3` (the build volume and the image are this track's own; a run never replaces another track's image); Windows is verified only in CI on `xp-*` branches (`.github/workflows/xp.yml`).
- **Processes.** Never `pkill`, `killall` or `xargs kill` swift, swift-test, swift-build, swift-frontend or xctest: other sessions (MetalUI's among them) run `swift test` on this Mac. Kill only PIDs you started yourself (captured with `$!`), and stop a Docker run only by this track's container names (`xp-3-linux`, `xp-3-linux-clean`; `scripts/linux-test.sh` does that).
- **Line endings.** A text file a test reads must read the same with CRLF (a Windows checkout): split lines with `split(whereSeparator: \.isNewline)` (`"\r\n"` is one `Character` and `isNewline`), or replace `"\r\n"` with `"\n"` first, never `split(separator: "\n")`.
- No third-party code without asking (`AGENTS.md`): the one tool this plan adds, SDL_shadercross, is the one MetalUI requires (MetalUI publishes no binary of it, ruling `BS-H`). It is a **build dependency of Linux and Windows** (not of the package, and never of macOS): user decision U1(b), decided 2026-10-21, pinned in `scripts/shadercross.env`, built in the Linux image and in Windows CI, and a missing or failing one stops the build or test step with a message naming it and its pinned commit. Every new `uses:` in the workflow is pinned to a full commit SHA, as master's are.

## Review Focus

The inputs this plan's tasks would not meet unless asked, most likely to bite first. Each has a test in the task that owns the code.

1. **A mesh with no triangles, no edges, or a great many triangles.** A Mesh node can come out empty or bare, and 7c's previews run to millions of triangles. Nothing traps; what is there draws; 100,352 triangles draw with every corner kept. Task 6, `SDLRenderTests.aMeshWithNoTrianglesOrNoEdgesDrawsWhatItHasAndDoesNotTrap` and `aLargeMeshDrawsAndKeepsAllItsCorners`.
2. **A theme change while edge, overlay and handle buffers are cached.** The buffers bake the theme's colours in; the next frame must draw the new ones. Task 6, `SDLRenderTests.aNewPaletteRebuildsTheCachedEdgesInItsColours`.
3. **A new camera or a resize while an ID pass is wanted, and a click right after it (U4, hybrid).** An orbit asks for a pass every frame: a newer request replaces an older one that has not started, a resize is a view of its own, an older view can be asked for again, nothing waits forever, and a pick outside a smaller view is empty space. A hover meanwhile keeps its face (it answers from the latest landed buffer and never stalls); a click is never answered from another view's buffer: it is answered from the buffer for its own view, waiting for it when it has not landed, and goes to the tool and the projector of its press. Task 7, `SDLPickerTests.aNewCameraOrSizeSupersedesOlderRequestsAndAnOlderViewCanBeAskedForAgain` (and `theQuietBeforeAPassIsShortAndStartsItWithoutAnyoneAsking`); task 2, `ViewportBackendTests.aClickWaitsForAPendingPickAndIsThenDeliveredOnTheLandedTarget` and `aWaitingClickGoesToTheToolItWasMadeWithAndNotTheOneSetWhileItWaited` (task 7 step 6 replaces the waiting with a synchronous render once MetalUI answers XP-G22, and its tests with `aClickIsAnsweredAtOnceFromItsOwnIDPassWhileTheHoverBufferIsPending` and `SDLPickerTests.aClickRendersItsOwnIDPassWhenNoBufferHasLanded`).
4. **More than 256 solids in the scene.** `PickID` holds 256 (8 bits); a solid past that is drawn and simply not pickable, and the others keep working. Task 7, `SDLPickerTests.aSolidPastTheTwoHundredFiftyFifthIsDrawnButNotPickable`.
5. **A machine with no installed font.** A minimal container or Windows Server Core has nothing to rasterize the cube's names with: the cube still draws, unlabelled, and the app starts. Task 10, `SDLWidgetTests.aBlankAtlasLeavesTheCubeDrawnButUnlabelled` (the fallback itself, `CubeLabelFonts.atlas()`, is task 3).
6. **A checkout whose shaders were never built, or were built before an HLSL edit.** `swift build` alone compiles no shader (U1(b)), so the tree can compile and then draw nothing. The SDL tests and `--self-test` fail with a message that names the script and the pinned tool; a stale build fails `ShaderSourceTests`. Task 4 `ShaderSourceTests.theBuildCompiledEveryStageIntoTheDirectoryTheRendererReads`, task 8 `ViewportShaderDirectoryTests.aMissingDirectoryFailsTheSelfTestCheckWithAMessageThatSaysWhatToRun`.
7. **A packaged app away from the tree it was built in.** A shipped app has no source tree to fall back to, so the compiled shaders must be in the package as `MetalUIAppShaders`; master's packaging copies only MetalUI's own `MetalUISDLShaders`. The tarball and the AppImage run `--self-test` in a clean Ubuntu and the zip with the checkout's shader directories moved aside, so a package without them fails there. Task 9, step 2 (`scripts/linux-test.sh package`, `scripts/package-windows.ps1`).

---

## Shared files

xp-2 is merged (master `fa1288d`, then `1aad412`), so its versions of these files are the base every diff below applies to. Other tracks still open (xp-c, the MetalUI adoption track, 7c follow-ups) may edit the same files; the side that merges second keeps everything listed.

| File | Master already has (xp-2 and earlier) | Edited by xp-3 | The second merge must keep |
|---|---|---|---|
| `Package.swift` | OpenCascade on every platform (`occt` everywhere, per-OS linker flags), `metalUISDL` for the app | a `metalUISDLGPU` constant after `metalUISDL`; `CreatorViewport`'s dependency list (`metalUIPortableText`, `metalUISystemFonts`, `metalUISDL`, `metalUISDLGPU`); `CreatorViewportTests`' list (`metalUISDL`, `metalUISDLGPU`, `"CreatorGraph"`) | all of these lines and master's OCCT blocks. No xp-3 line is inside an `#if os(…)` block. |
| `.github/workflows/xp.yml` | every `uses:` pinned by SHA, `permissions: contents: read`, the OCCT buildx step, `scripts/linux-test.sh all` then `package`, the SDL3 zip's sha256, the vcpkg key, restore and save steps, `EXPECTED_TEST_RUNS: 12`, the release build and zip steps | the Linux job's shadercross buildx step and `SHADERCROSS_IMAGE` on its two script steps (task 4); on Windows the shadercross restore, build and save steps and the `scripts/build-shaders.ps1` step before `Build` (task 4); `XP_REQUIRE_GPU: 1` and comments (task 9) | master's jobs and steps unchanged around xp-3's; every new `uses:` SHA-pinned with its tag as a comment; the shadercross cache has its own key, apart from vcpkg's. `METALUI_COMMIT` stays `5f03ab7b…`. |
| `scripts/linux-test.sh` | `test [swift test args]` (count rule off, at least one run), `IMAGE`, `OCCT_IMAGE`, `OCCT_JOBS`, `DOCKER_EXTRA`, the `package` step with its clean-Ubuntu checks, count 12 | `-e XP_REQUIRE_GPU=1` and the lavapipe paragraph (task 0); `SHADERCROSS_IMAGE` and `SHADERCROSS_JOBS` passed as build arguments, `compile_shaders` before build, test, smoke and package (task 4); the package checks look for `MetalUIAppShaders` (task 9) | master's text for everything it has; xp-3 adds lines, it rewrites none of master's verbs. |
| `scripts/linux/Dockerfile` | the `occt` stage (`swift:6.4-noble`), `FROM ${OCCT_IMAGE} AS occt-source`, `/opt/occt` copied into the final stage, `patchelf`, `desktop-file-utils`, `file` | a `shadercross` stage (`swift:6.4-noble`, native, the pinned SDL_shadercross with its vendored DXC into `/opt/shadercross`), `FROM ${SHADERCROSS_IMAGE} AS shadercross-source` and one `COPY` of `/opt/shadercross` into the final stage (task 4), the same pattern as OpenCascade | both stages, each a layer set of its own (a change of the OCCT pin never rebuilds shadercross, nor the reverse); `ARG SHADERCROSS_COMMIT` equals `scripts/shadercross.env` (`ShaderToolchainTests`); the final stage stays last. |
| `scripts/package-linux.sh`, `scripts/package-windows.ps1`, `docs/packaging.md` | the tarball, the AppImage (packed from the tarball's tree) and the zip, each shipping MetalUI's own `MetalUISDLShaders` and nothing of the viewport's | copy `Shaders/viewport/compiled` to `MetalUIAppShaders` beside the executable and stop, naming `scripts/build-shaders.sh`, if it is missing; the zip's self-test also moves the source tree's compiled directory aside (task 9) | both directories in every package. |
| `CLAUDE.md` | the xp-2 text (OpenCascade everywhere, `KernelUnavailable` kept for tests, packaging, the Windows toolchain notes, the `linux-test.sh` lines, "exit 0 and 12 \"Test run with\" lines", pinned by `CIPinTests`) | the xp-3 paragraph after the xp-1 paragraph and short edits (task 9) | both sides' paragraphs; the xp-3 edits are independent sentences and keep `CIPinTests`' phrases. |
| `docs/metalui-gaps.md` | rows XP-G3 to XP-G13 and XP-G21 (the Windows release-build crash, fixed by MetalUI `5f03ab7b`, adopted by xp-2; a row with no section) | rows XP-G1, XP-G2, XP-G14 to XP-G20 (answered) and XP-G22 (open), between XP-G13 and XP-G21, and one section at the end (task 0) | every row, xp-3's between XP-G13 and XP-G21. **Numbers:** XP-G21 is taken; a gap any branch finds next takes XP-G23. |
| `docs/verification/human-checks.md` | group XP (xp-1, XP-1 to XP-15) and group XP2 (xp-2, XP-16 to XP-19, XP-19 being the AppImage) | XP-2 and XP-9 reworded in group XP; a new group XP3 after XP2 with **XP-20 to XP-26** (task 9) | all of them; a check either branch adds next takes XP-27. |
| `docs/superpowers/specs/2026-10-13-cross-platform-design.md` | errata E1 to E6 (E6: adopt-s9's `ImageInfo`) | erratum **E7** (task 9) | E7, or renumber if another branch took the number first. |
| `Sources/MetalCreatorApp/main.swift` | xp-2's and the adoption track's changes | one line, `smoke?.viewport = { … }` after the `AppModel` is made (task 8) | that line and the others' changes. |
| `Sources/CreatorApp/SelfTest.swift`, `LaunchSmoke.swift` | xp-2's packaging self-test | the viewport's shader check; the viewport report (task 8) | both. |

Not shared: `CreatorImplicit` and the lattice nodes (7c), the bracket tests; xp-3 touches none of them.

---

## User decisions

Product and process choices the spec leaves open. **All eight were decided on 2026-10-21**: U1 is option (b), the others are the recommended option (a). **U4 was decided again on 2026-10-22: hybrid.** U5 no longer applies (MetalUI answered the gaps it was about). Each entry says what was decided and keeps the alternatives that were not taken, for the record.

**U1. The shader source language and build path. DECIDED 2026-10-21: option (b).**
- (a) *Not taken.* HLSL, built once with MetalUI's `compile-app-shaders.py` through SDL_shadercross; the SPIR-V, DXIL and MSL blobs and `SOURCE.sha256` checked in; a test recomputes the hashes with no shadercross. (It was this plan's first recommendation: it is the path MetalUI documents and tests, `packaging.md` section 4a, `GA-F`, and CI needs no extra tool. The user preferred no generated binaries in the repository.)
- (b) **DECIDED. The same HLSL compiled at build time, in CI and by every developer on Linux and Windows. No compiled blob is checked in, and SDL_shadercross becomes a build dependency of the platforms that use the SDL renderer (Linux and Windows; macOS builds Metal only, U6(a), and needs none).** What follows from it, all in Task 4 and Task 9:
  - **Where compilation happens: a script step before `swift build`, through MetalUI's own tool.** When U1(b) was decided MetalUI had no build-time path (gap **XP-G20**). **MetalUI S12 (`d995f4b4`, 2026-10-21, in the pin `5f03ab7b`) answered it:** the root package exports the executable **`MetalUICompileShaders`** and the command plugin `CompileShaders` (`swift package --allow-writing-to-package-directory compile-shaders --source DIR --out DIR`), both over the portable `MetalUIShaderCompile` target, which replace the deleted `Backends/SDL/scripts/compile-app-shaders.py`. The tool's arguments are `--source DIR --out DIR [--shadercross PATH] [--formats spv,msl,dxil,json] [--no-marker] [--base DIR]` (`CompileArguments.swift`); for each `NAME.<vert|frag|comp>.hlsl` it writes `NAME.<stage>.spv`, `.msl`, `.dxil` and a reflection `.json`, then **`SOURCE.sha256`** (one `<sha256>  <file>` line per stage source, sorted bytewise, LF; `SourceMarker.swift`); shadercross is found by `--shadercross`, then `METALUI_SHADERCROSS`, then `PATH`. MetalUI's ruling `BS-D` still offers no build-tool plugin (its output would not land beside the executable, and a missing shadercross would fail every consumer's build), so the compile stays a script step: **`scripts/build-shaders.sh`** (Linux) and **`scripts/build-shaders.ps1`** (Windows) check the pin, skip a current directory, and run the executable built from the `../MetalUI` checkout, `swift run --package-path ../MetalUI --scratch-path <a directory of ours> MetalUICompileShaders …` (the scratch path keeps every build product out of `../MetalUI`, which is never written to). `scripts/linux-test.sh` runs the first inside the container before `swift build`, `swift test`, the smoke step and packaging; the CI Windows job runs the second before `swift build`; a developer on Windows runs it once and again after editing a `.hlsl` file. The honest consequence stays: **`swift build` alone does not compile shaders**. A checkout that skipped the script finds no shaders and says so: the SDL tests and `--self-test` fail with a message that names the script and the pinned tool (Task 4, `ViewportShaderCheck`), and a stale directory (an `.hlsl` edited after the last build) is caught by `ShaderSourceTests`.
  - **Where shadercross comes from.** `libsdl-org/SDL_shadercross` has **no release and no tag** (checked 2026-10-21), and MetalUI publishes no binary of it (ruling `BS-H`), so the pin is a **full commit**: `1ff05bec573988a98ef9e0260b4da44f512b8367` (2026-09-03, the head of `main` and its latest green `Build` run), recorded once in `scripts/shadercross.env` and the same commit MetalUI `docs/packaging.md` section 4a documents. **Linux:** built in its own stage of `scripts/linux/Dockerfile` with MetalUI's recipe: the four submodules the commit fixes (SPIRV-Cross, SPIRV-Headers, SPIRV-Tools and libsdl-org's DirectXShaderCompiler fork, branch `1.8.2502-SDL`), `-DSDLSHADERCROSS_VENDORED=ON`, clang. That builds natively on x86_64 and aarch64 (MetalUI measured 6 min 45 s at `-j8` on Linux aarch64 and 41 compiled files byte-identical to its own), so the stage runs on the host's architecture with no emulation, and is copied into the test image as OpenCascade's stage is (cached in that layer locally and by buildx in CI). **Windows:** `scripts/install-shadercross.ps1` builds the commit with Microsoft's prebuilt DirectXShaderCompiler `v1.9.2602` (pinned by URL and SHA-256 in the commit's `build-scripts/download-prebuilt-DirectXShaderCompiler.cmake`; Linux x86_64 and Windows only), cached with `actions/cache/restore` and `save` (xp-2's vcpkg pattern).
  - **Failure is loud.** A missing, mispinned or failing shadercross stops `scripts/build-shaders.sh`/`.ps1` (and with it the `linux-test.sh` step and the CI step) with a plain message naming the tool and the pinned commit, e.g. `SDL_shadercross (libsdl-org/SDL_shadercross commit 1ff05bec573988a98ef9e0260b4da44f512b8367, pinned in scripts/shadercross.env) was not found ...`.
  - **Freshness (decided 2026-10-22).** `MetalUICompileShaders` writes `SOURCE.sha256`, so `ShaderSourceTests` keeps its freshness check on that marker (the stage sources' digests), and `scripts/build-shaders.sh` adds `INCLUDES.sha256` for `common.hlsli`, which MetalUI's marker does not cover (it lists only `NAME.<vert|frag|comp>.hlsl`). The marker is MetalUI's own format, so `SDLGPUShaderLibrary(directory:verifyingSources:)` could check it too; the renderer does not need to (`SDLGPUShaderLibrary.locate` accepts the directory by its marker or its reflection files), and the tests are where staleness is caught.
  - **Shipping is U7(a):** the packaging scripts (the tarball, the AppImage and the Windows zip) copy the build output `Shaders/viewport/compiled` to `MetalUIAppShaders`; xp-2 merged without that copy, so xp-3's task 9 adds it. Nothing is read from the repository at run time in a shipped app.
- (c) *Not taken.* Hand-written GLSL/SPIR-V and a separate DXIL: two sources to keep in step, no MetalUI support.
- SDL_shadercross is a third-party tool (`AGENTS.md`: ask first). The user approved it on 2026-10-21 **as a build tool of the Linux and Windows builds** (not a SwiftPM dependency, never linked into the app).

**U2. One HLSL source shared with Metal, or MSL kept separately. DECIDED 2026-10-21: option (a).**
- (a) **Keep the Metal renderer's MSL strings (`ViewportShaders`, `LineShaders`, `FieldShaders`) and add HLSL beside them; pin both to the same Swift structs.** *Recommended:* macOS is untouched (its look, its 12 test lines, no shadercross for a macOS contributor, which U1(b) keeps true), and `GPUDataTests` plus `ShaderSourceTests` catch the struct drift that is the realistic danger. The two sources are about 600 lines each.
- (b) HLSL as the single source, the macOS renderer loading the MSL shadercross generates: no duplicated shading maths, but it rewrites a renderer that works, makes every shader edit need shadercross, and risks a visible change on the Mac.
- (c) (a) now, and a generated-MSL comparison as an oracle test later.

**U3. CI GPU strategy. DECIDED 2026-10-21: option (a).**
- (a) **Linux: the existing Docker image's Mesa lavapipe (a CPU Vulkan driver, x86_64 and aarch64, the way MetalUI's own `sdl-gpu-linux.yml` renders); Windows: Direct3D 12 on WARP. The render and pick suites run on both; `XP_REQUIRE_GPU=1` turns "no device" from a silent skip into a failure.** *Recommended:* no new runner, the tests that matter (the ID pass, the picks, the pixels) run on every push, and the skip policy follows MetalUI's `METALUI_REQUIRE_GPU`.
- (b) Skip the renderer suites in CI and rely on human checks (group XP): fast, but nothing guards the shaders or the picker after this merge.
- (c) A self-hosted GPU runner: real hardware, a machine to look after.

**U4. Picking on SDL. DECIDED 2026-10-22: HYBRID** (it replaces the option (a) decided on 2026-10-21).
- **HYBRID, DECIDED. A hover answers from the latest landed ID buffer and a click is always exact.** The ID buffer is rendered ahead (in a batch after the draw that follows a change of camera or scene, as option (a) did), and a **hover** reads the newest buffer that has landed: while the buffer for the view as it is now is on its way the hover keeps the face it has and looks again when it lands (`onPickReady`), so it may lag a frame or so after an orbit and never stalls a frame. A **click** waits for the GPU, so it is exact, as on Metal: it is answered from a buffer rendered for its own camera and scene, never from another view's, and it goes to the tool and the projector of its press. On SDL that means: a buffer for the click's view has landed (nearly always, since the ahead-of-time pass ran after the last change) and the click is answered at once; or it has not, and the click renders the ID pass for its view and waits for it. MetalUI S11 gave the waiting half (`SDLGPUFence.waitBlocking()`, `SDLGPUDevice.downloadSynchronously(_:region:)`, legal on the main actor outside a draw; XP-G14), but not a render batch that can be submitted without `await` (`submitBatch` is `async`): that is **gap XP-G22** (task 0), so **until MetalUI answers it the click waits asynchronously** (it is delivered when its buffer lands, a few milliseconds later, still exact and still to the press's tool and projector: task 2's `pickWhenReady` path), and once it is answered **task 7 step 6 makes `pickWhenReady` the synchronous path** (render, `waitBlocking()`, `downloadSynchronously`) and deletes the asynchronous click. Nothing is worked around meanwhile.
- (a) *Replaced.* Render ahead and answer from it; while it is on its way a hover keeps its face and a click waits a few milliseconds (decided 2026-10-21). The hybrid keeps (a)'s hover and its interim click, and makes the click synchronous once the typed layer can.
- (b) *Not taken.* Block every pick, hovers included, on a synchronous render and readback, exactly as Metal's picker does: a hover would stall a frame on every pointer move after a change.
- (c) *Not taken.* Call raw `SDL_` functions for a blocking submit: works today, but it is the workaround the project forbids.

**U5. How gap-blocked layers are handled. DECIDED 2026-10-21: option (a); moot since 2026-10-21 (MetalUI S11, `11dca65e`, answered XP-G15 to XP-G18, and master's pin `5f03ab7b` has it).** Tasks 10 to 12 no longer wait; they follow task 9 only to keep the numbering, and until each lands on this branch the SDL viewport lacks its layer, as below. XP-G15 (viewport and scissor), XP-G16 (colour write mask), XP-G17 (`r32Float`) and XP-G18 (anisotropy) were what the view cube and triad, the ghost prepass and the slice needed.
- (a) **Tasks 0 to 9 ship the working viewport first (solids, edges, grid, guides, overlay, handles, field tint, clip, warning faces, ID-pass picking). Tasks 10 to 12 wait for MetalUI to answer and are written against the signatures requested in `docs/metalui-gaps.md` and checked against a local copy of MetalUI that has them** (decided; MetalUI then answered, and tasks 10 to 12 now use its real API). *Recommended:* it respects "never work around" and lands the 90% that does not need MetalUI. Until 10 to 12 land the SDL viewport has no view cube or triad (and, so that nothing invisible acts, the model does not hit-test the cube's corner: hover and click there reach the scene; the cube's arrow buttons and View menu stay), blends ghosts in one pass (an interior can show through) and draws no slice.
- (b) Use the raw escape hatch MetalUI documents (`SDL_SetGPUViewport(pass.raw, …)`, one line) and shader-side imitations (a zero-output ghost prepass, an `r32Uint` bit-cast) now: everything draws today, with code that MetalUI's answer will make obsolete.
- (c) Hold the whole merge until MetalUI answers.

**U6. Does macOS also build the SDL renderer? DECIDED 2026-10-21: option (a).**
- (a) **No: macOS builds Metal only; Linux (Docker, CI) and Windows (CI) verify the SDL renderer.** *Recommended:* macOS needs no SDL3 install, keeps its test count, and avoids the MetalUI `SG-D` module-map hazard of a conditional dependency.
- (b) Also ask for the `SDL` trait on macOS (Homebrew SDL3) so `swift run` can drive the SDL renderer on the Mac's GPU: handy for debugging, but it changes the shared `Package.swift` trait line and every macOS build.

**U7. Where the compiled shaders ship. DECIDED 2026-10-21: option (a).**
- (a) **`MetalUIAppShaders` beside the executable, then the source tree (MetalUI's lookup order); the packaging scripts copy the build output `Shaders/viewport/compiled` there.** *Recommended:* the documented recipe; `--self-test` fails if the directory is missing. xp-2 merged without the copy (its packages ship only MetalUI's `MetalUISDLShaders`), so task 9 adds it to `scripts/package-linux.sh` (the AppImage is packed from the tarball's tree) and `scripts/package-windows.ps1`: each stops, naming `scripts/build-shaders.sh`/`.ps1`, when the directory is missing, and the clean-environment self-tests prove the copy.
- (b) SwiftPM resources (`Bundle.module`): turns `CreatorViewport` into a resource target on macOS too.

**U8. The cube's face names on macOS. DECIDED 2026-10-21: option (a).**
- (a) **One rasterizer for both platforms through MetalUI's `TextSystem`; macOS passes `CoreTextTextSystem()`.** *Recommended:* it is the spec's "through MetalUI's portable text, not CoreText" with no second code path; the names may antialias a hair differently from the old direct `CTLineDraw` (human check XP-26).
- (b) Keep the CoreText rasterizer for macOS and add the portable one beside it: zero macOS change, two paths to keep equal.

---

## Key decisions (made by this plan)

- **Storage buffers for all vertex data.** Meshes, line instances, fills and cube tiles are `StructuredBuffer`s read with `SV_VertexID`/`SV_InstanceID`; no vertex attributes. SDL_GPU's typed layer has no `uint` vertex format, and instancing is a storage-buffer read.
- **Face flags are read in the vertex stage** and reach the fragment stage as a flat interpolant: SDL_GPU's render pass binds storage buffers to the vertex stage only, and a flag is the same for every corner of a face. Not a gap, a design.
- **Every HLSL struct is `float4`/`uint4`/`float2` and scalars, never `float3`**, so one layout serves a constant buffer, a structured buffer and Swift's SIMD types; `ShaderSourceTests` computes the HLSL sizes and compares them with `MemoryLayout.stride`.
- **Plan, then record.** SDL_GPU cannot start a copy pass inside a render pass, so `SDLViewportRenderer.plan` makes and fills every buffer first and `record` only draws.
- **The renderer is not main-actor isolated** (`@unchecked Sendable`, used from one thread at a time) because the tests record into a batch's command buffer on the device's worker thread; the ID pass reads none of its state (`SDLIDPassInputs`).
- **The frame's camera is pushed after every pipeline bind** (`SDLPassRecorder`), so no draw depends on what the previous pipeline left in a uniform slot.
- **Each uniform slot is the cbuffer's register index**, vertex uniforms in `space1`, fragment uniforms in `space3`, fragment samplers in `space2`, vertex storage in `space0` (SDL_GPU's convention, MetalUI `packaging.md` 4a).
- **A fragment stage reads every vertex output it declares** (MetalUI ruling `GA-Q`: Direct3D 12 links stages by register), which is why the ID pass has vertex shaders of its own.
- **No raw `SDL_` call in app code.** Pipelines are made with `SDLGPUDevice.compileGraphicsPipeline(_:)` (MetalUI S11, ruling `GB-G`, gap XP-G19 answered), which throws an `SDLGPUError` naming the stage that failed with SDL's own text; `SDLViewportPipelines` puts that reason and the vertex/fragment pair in `ViewportRenderError.deviceRefused`, so `gpuFailureMessage` and `--smoke-test` say why. No `SDL_GetError()` is read here.
- **The model hit-tests the view cube only while the backend draws it** (`ViewportBackend.drawsWidgets`, `ViewportModel.cubeCatches(_:)`): SDL says `false` until task 10, so no invisible control turns the camera.
- **Picking is hybrid (U4).** A hover answers from the latest landed ID buffer and never stalls; a click is exact, answered from a buffer for its own view. **A click that waits for its buffer is the click of the press**: the tool and the projector it was made with, not those of the moment the buffer lands. The wait is asynchronous until MetalUI answers XP-G22, then synchronous (task 7 step 6), with no change to what a click selects.
- **The device is the window renderer's, borrowed from the first draw** (`SDLGPUDevice(borrowing:)` through `ctx.view`); the viewport model must not outlive its window.
- **`.gitattributes` pins `Shaders/**` to LF** (a CRLF checkout changes the sources' hashes, which the build writes to `SOURCE.sha256` and the freshness test compares; MetalUI section 4a's second Windows rule); `scripts/shadercross.env` is already LF through master's `scripts/** text eol=lf`. The tests that read these files split on `isNewline` all the same.
- **The compiled directory is a build product.** `/Shaders/viewport/compiled` is in `.gitignore`. `MetalUICompileShaders` writes `SOURCE.sha256` there (MetalUI's marker; since S12 `SDLGPUShaderLibrary` also accepts a marker-free directory that holds a reflection `.json`, ruling `BS-E`, but the plan keeps the marker because the freshness check reads it), and `scripts/build-shaders.sh` adds `INCLUDES.sha256` for the shared header, which MetalUI's marker does not list; neither is committed.
- **MetalUI's tool is built from the sibling checkout, never in it.** `swift run --package-path ../MetalUI --scratch-path <ours> MetalUICompileShaders`: the scratch path is `.build/metalui-tools` in this repository (the default) or `/build/metalui-tools` in the Linux container's own volume, so nothing is written into `../MetalUI`, which the container mounts read-only.
- **One pin, in `scripts/shadercross.env`** (`SHADERCROSS_COMMIT`, `SHADERCROSS_REPOSITORY`); the Dockerfile, the Linux and Windows CI steps, both scripts and their error messages read or repeat it, and `ShaderToolchainTests` fails if the Dockerfile or the workflow disagree with it.

## File structure

Each file has one job. New files under `Sources/CreatorViewport/RenderSDL/` are all fenced with `#if canImport(MetalUISDLGPU)` (Linux and Windows only, where Package.swift names the product).

**Portable, in `Sources/CreatorViewport`**

| File | Responsibility |
|---|---|
| `Render/FloatMatrix4.swift` | four `SIMD4<Float>` columns: the GPU's matrix, no `simd` |
| `Render/FrameUniforms.swift` (changed) | per-pass camera data in plain SIMD, 176 bytes, on every platform |
| `Render/ViewportBackend.swift` | what `ViewportModel` needs from a renderer: draw count, `pick`, `isPickPending`, `pickWhenReady`, `onPickReady` |
| `Render/MetalViewportBackend.swift` | the macOS backend: `ViewportRenderer` + `ViewportPicker`, unchanged |
| `Model/ViewportModel+Backend.swift` | `install(_:)` wires picks through a backend; `gpuFailureMessage`, `drawnFrames` |
| `Model/ViewportModel+Input.swift` (changed) | a hover keeps its face while a pick is pending; a click waits for the buffer of its own view (U4, hybrid) |
| `View/ViewportView.swift`, `ViewportView+Parts.swift` (changed) | portable: `MetalView` on macOS, `GPUSurface` elsewhere |
| `View/ViewportModel+Surface.swift` (changed) | the Metal `draw`, now through `MetalViewportBackend` |
| `View/ViewportModel+SDLSurface.swift` | the SDL `draw` (`GPUSurface` closure, `SDLGPUDrawContext`) |
| `Render/CubeLabelAtlas+TextSystem.swift`, `Render/CubeLabelFonts.swift` | the cube's six names rasterized through MetalUI's `TextSystem` (replaces `CubeLabelAtlas+CoreText.swift`) |
| `ViewportShaderCheck.swift` | `--self-test` asks the viewport whether its shaders were built and ship; a missing directory is reported with the script to run |

**SDL renderer, `Sources/CreatorViewport/RenderSDL`**

| File | Responsibility |
|---|---|
| `SDLViewportShaders.swift` | finds `Shaders/viewport/compiled` (beside the executable as `MetalUIAppShaders`, else the source tree); `verify()` |
| `SDLViewportUploader.swift` | makes a storage buffer and records the copy that fills it into a command buffer |
| `SDLViewportMesh.swift` | one mesh on the GPU: vertices, edge instances, face flags, field values, pick edges |
| `SDLViewportPipelines.swift` | every graphics pipeline (SDL puts the depth test in the pipeline) |
| `SDLFramePlan.swift` | everything one main pass draws, with every buffer already made |
| `SDLViewportRenderer.swift`, `+Plan`, `+Record` | caches, `encode`, the plan, the recording in Metal's order |
| `SDLViewportRenderer+IDPass.swift` | the ID pass's inputs, gathered on the main actor, and its recording |
| `SDLViewportPicker.swift` | renders the ID pass in a batch, reads it back, answers hovers from the latest landed buffer and clicks from their own view's |
| `SDLViewportBackend.swift` | the `ViewportBackend` over the renderer and the picker |
| `SDLViewportCube.swift`, `SDLViewportRenderer+Widgets.swift`, `SDLSliceTextures.swift` | the view cube, the triad and the slice (tasks 10, 12) |

**Shaders and scripts**

| File | Responsibility |
|---|---|
| `Shaders/viewport/*.hlsl`, `common.hlsli` | the viewport's vertex and fragment stages and their shared structs |
| `Shaders/viewport/compiled/*` | SPIR-V, DXIL, MSL, reflection JSON, `SOURCE.sha256`, `INCLUDES.sha256` (**generated by the build, git-ignored, not checked in**) |
| `scripts/shadercross.env` | the one pin: SDL_shadercross repository and commit |
| `scripts/build-shaders.sh` | compiles `Shaders/viewport` into `compiled` through MetalUI's `MetalUICompileShaders` (built from `../MetalUI` with `swift run --scratch-path`) and the pinned SDL_shadercross (Linux; run by `linux-test.sh` and CI before `swift build`); skips a current directory; stops with a message naming the tool and its pin when it is missing or fails |
| `scripts/build-shaders.ps1` | the same on Windows (CI and developers), finding shadercross in `-ShaderCross`, `SHADERCROSS` or `PATH` |
| `scripts/install-shadercross.ps1` | builds the pinned SDL_shadercross on Windows (CI, cached; a developer once) |
| `scripts/linux/Dockerfile` (changed) | a `shadercross` stage: SDL3 and the pinned SDL_shadercross with its vendored DXC built natively into `/opt/shadercross`, copied into the test image |
| `scripts/package-linux.sh`, `scripts/package-windows.ps1`, `docs/packaging.md` (changed) | the packages ship `Shaders/viewport/compiled` as `MetalUIAppShaders` (task 9) |
| `.gitattributes`, `.gitignore` (changed) | pin the shader sources' line endings; ignore the compiled directory |

**App**

| File | Responsibility |
|---|---|
| `CreatorApp/ViewportPane.swift` (changed), `ViewportPlaceholder.swift` (deleted) | the real viewport on every platform |
| `CreatorApp/LaunchSmoke.swift`, `SelfTest.swift`, `MetalCreatorApp/main.swift` (changed) | the smoke test passes only if the viewport drew; the self-test checks its shaders |

**Tests, `Tests/CreatorViewportTests`**: `ViewportBackendTests`, `ShaderSourceTests` (struct sizes everywhere; on Linux and Windows also that the build produced every shader and is current), `ShaderToolchainTests` (the pin agrees everywhere it is written), `CubeLabelTests` (now portable), and, SDL-only and skipped without an SDL_GPU device, `SDLGPUAvailabilityTests`, `SDLRenderTests`, `SDLFieldGuideClipTests`, `SDLPickerTests`, `SDLWidgetTests`, `SDLSliceTests`, with `Support/RenderFixtures.swift`, `SDLTestDevice.swift`, `SDLRenderRig.swift`, `TestMeshes+Sheet.swift`. `Tests/CreatorAppTests`: `LaunchSmokeTests`, `ViewportPaneTests`.

---

## Tasks

Every task needs only MetalUI as master pins it, `5f03ab7b` (MetalUI S11 and S12 included); no task waits for MetalUI. Tasks 10 to 12 come last only because the viewport is useful without them. Task 7's step 6 is the one step that waits, for gap XP-G22; if it has not been answered when task 7 is done, go on and come back to it.

### Task 0: Log the MetalUI gaps as answered, log XP-G22; the Linux script's GPU promise; the baselines

MetalUI answered XP-G1 (S5 and S6: `MetalUISDLGPU`), XP-G14 to XP-G19 (S11, `11dca65e`) and XP-G20 (S12, `d995f4b4`), all in master's pin `5f03ab7b`. This task records that in `docs/metalui-gaps.md` (a summary row each, as the file asks, and one section), logs the one new gap, **XP-G22** (a render batch submitted without `await`, which a synchronous click needs; user decision U4), and makes `scripts/linux-test.sh` promise the SDL render suites a GPU (`XP_REQUIRE_GPU=1`). Master's `scripts/linux-test.sh` already has everything else the old plan's task 0 added (xp-2): `test [swift test arguments]` with the count rule off and at least one run, `IMAGE=${IMAGE:-metalcreator-linux:latest}`, `XP_TRACK`, the count 12. No Swift changes. **XP-G22 is to be forwarded to the MetalUI session** (the entry below is the text to send); nothing waits for it but task 7's step 6.

**Files:**
- Modify: `docs/metalui-gaps.md`
- Modify: `scripts/linux-test.sh`

**Interfaces:**
- Consumes: master's `scripts/linux-test.sh` (`test --filter NAME`, `IMAGE`, `XP_TRACK`, `in_container`).
- Produces: `XP_REQUIRE_GPU=1` in every container `in_container` starts, read by task 5's `SDLGPUAvailabilityTests`; the gap rows XP-G1, XP-G2, XP-G14 to XP-G20 (answered) and XP-G22 (open), referenced by tasks 5, 7 and 10 to 12; the baselines every later "Expected" line is a delta from.

- [ ] **Step 1: Record the answers and XP-G22 in `docs/metalui-gaps.md`**

In the summary table, insert these ten rows **between the `| XP-G13 |` row and the `| XP-G21 |` row** (numeric order; XP-G21, the Windows release-build crash MetalUI fixed in `5f03ab7b`, is master's and stays where it is):

```markdown
| XP-G1 | App access to SDL_GPU through `GPUSurface`, a shader build path for apps, MSAA resolve, depth targets, instanced draws, storage buffers, mipmapped r8 textures, texture readback | MetalUI S5 and S6 (`MetalUISDLGPU`, master `34491ff4` and later; record §114, rulings `GA-`) | ✅ answered, and used by xp-3 (plan `2026-10-21-xp-3-sdl-gpu-viewport.md`): every item exists in the typed layer and the viewport draws with them. What it still lacked was XP-G14 to XP-G20, answered by S11 and S12 below |
| XP-G2 | Portable compute (SDL GPU compute) for 7c's implicit engine | MetalUI S5 (`SDLGPUComputePipeline`, `submitBatch`, append buffers) | ✅ answered; not used by xp-3 (xp-c's: implicit evaluation and meshing stay on the CPU off macOS until then) |
| XP-G14 | A synchronous readback of a texture outside a draw (the ID pass the viewport picks from) | MetalUI S11 (record §137, ruling `GB-F`, master `11dca65e`) | ✅ fixed by MetalUI S11 (in the pin `5f03ab7b`): `SDLGPUFence.waitBlocking()` and `SDLGPUDevice.downloadSynchronously(_:region:) -> [UInt8]?`, legal on the main actor outside a draw. xp-3's click uses them once it can also submit its ID pass without `await` (XP-G22); meanwhile a hover answers from the latest landed buffer and a click waits for its own, asynchronously (user decision U4, hybrid) |
| XP-G15 | `setViewport` and `setScissor` on a render pass | MetalUI S11 (ruling `GB-B`, `11dca65e`) | ✅ fixed by MetalUI S11: `SDLGPURenderPass.setViewport(x:y:width:height:minDepth:maxDepth:) -> Bool` and `setScissor(x:y:width:height:) -> Bool` (`@discardableResult`, target pixels from the top left, the scissor clamped to the target); used by xp-3 task 10 (the view cube and the triad) |
| XP-G16 | A colour write mask on a graphics pipeline | MetalUI S11 (ruling `GB-C`, `11dca65e`) | ✅ fixed by MetalUI S11: `SDLGPUGraphicsPipelineDescription(…, writesColor: false)`; used by xp-3 task 11 (the ghosts' depth-only prepass) |
| XP-G17 | `SDLGPUTextureFormat.r32Float` | MetalUI S11 (ruling `GB-D`, `11dca65e`) | ✅ fixed by MetalUI S11: `.r32Float` (4 bytes a texel; linear sampling is optional hardware, so xp-3 samples it with a nearest sampler and blends in the shader); used by xp-3 task 12 (the field slice) |
| XP-G18 | Anisotropic filtering on `SDLGPUSamplerDescription` | MetalUI S11 (ruling `GB-E`, `11dca65e`) | ✅ fixed by MetalUI S11: `SDLGPUSamplerDescription(…, maxAnisotropy:)` (1 is off, capped at 16: `effectiveMaxAnisotropy`); used by xp-3 task 10 at 8 for the cube's face names |
| XP-G19 | The reason `makeGraphicsPipeline` refused | MetalUI S11 (ruling `GB-G`, `11dca65e`) | ✅ fixed by MetalUI S11: `SDLGPUDevice.compileGraphicsPipeline(_:) throws -> SDLGPUGraphicsPipeline` throws an `SDLGPUError` naming the stage that failed with SDL's text (and `lastPipelineFailure` records what `makeGraphicsPipeline` refused); xp-3's `SDLViewportPipelines` puts it in `ViewportRenderError.deviceRefused`, so `gpuFailureMessage` says why. No raw `SDL_GetError()` |
| XP-G20 | A build-time path for an app's SDL_GPU shaders: a plugin or a documented, pinned SDL_shadercross for CI | MetalUI S12 (record §138, rulings `BS-`, master `d995f4b4`) | ✅ fixed by MetalUI S12: the executable `MetalUICompileShaders` and the command plugin `CompileShaders` (`swift package --allow-writing-to-package-directory compile-shaders`) replace `compile-app-shaders.py`, which is deleted; shadercross is found by `--shadercross`, `METALUI_SHADERCROSS`, then `PATH`; `SDLGPUShaderLibrary` opens a directory with `SOURCE.sha256` or a reflection `.json` (`BS-E`), and `init(directory:verifyingSources:)` still refuses a stale marker; the pin `1ff05bec…` is documented in `docs/packaging.md` §4a. ➖ The published shadercross (item 2) was declined (ruling `BS-H`), so xp-3 keeps its Docker stage, `scripts/shadercross.env` and `scripts/install-shadercross.ps1`; `scripts/build-shaders.sh` and `.ps1` run `MetalUICompileShaders` |
| XP-G22 | A render batch submitted without `await`, so a click can render its own ID pass and wait for it (Metal's `waitUntilCompleted` picking) | open (new, 2026-10-22, forward to MetalUI) | 🔄 open at MetalUI, not blocking. `SDLGPUDevice.submitBatch` is `async`, so main-actor code outside a draw cannot render the ID pass and then `downloadSynchronously` it. Needed: `submitBatchSynchronously(_:) throws -> SDLGPUFence`, under `GB-F`'s rules. Meanwhile xp-3's click waits for its own ID buffer asynchronously (exact, delivered a few milliseconds later); xp-3 task 7 step 6 adopts the verb |
```

Then append this section at the **end of the file** (after the "Found by the preview sweep, 2026-10-14" section, with one blank line before it):

````markdown
## Hit by the 3D viewport on SDL GPU (xp-3), 2026-10-21 (answered the same day; XP-G22 added 2026-10-22)

Plan `docs/superpowers/plans/2026-10-21-xp-3-sdl-gpu-viewport.md`, checked against MetalUI `5f03ab7b` (master's `METALUI_COMMIT`, which has MetalUI S11 `11dca65e` and S12 `d995f4b4`). The viewport's SDL renderer draws every pass of the Metal one and uses no raw `SDL_` call and no shader-side imitation of a missing verb.

- **XP-G1. App access to SDL_GPU for the viewport.** Answered by MetalUI S5 and S6 (`MetalUISDLGPU`; record §114, `GA-`): `ctx.view` is the
  surface draw's frame (its own command buffer and target as an `SDLGPUTexture`), `SDLGPUShaderLibrary` loads the compiled HLSL, textures take a
  sample count (4× MSAA resolved into the surface's target by `storeOp: .resolve`), `d32Float` depth, `r32Uint` and a mip chain (`levelCount`,
  `generateMipmaps`), pipelines take a blend, a cull mode and a depth test, a pass draws instanced (`draw(vertexCount:instanceCount:)`) over
  vertex-stage storage buffers, and `SDLGPUDevice.download(_:)` reads a texture back. Nothing was worked around.
- **XP-G14 to XP-G19.** Asked on 2026-10-21 (a synchronous readback; `setViewport` and `setScissor`; a colour write mask; `r32Float`; anisotropy; a refused
  pipeline's reason) and answered the same day by MetalUI S11 (record §137, rulings `GB-B` to `GB-G`, master `11dca65e`) with the verbs the summary rows
  name. xp-3 uses every one: tasks 10 (`setViewport`, `maxAnisotropy`), 11 (`writesColor`), 12 (`r32Float`), 5 (`compileGraphicsPipeline`) and 7
  (`waitBlocking`, `downloadSynchronously`, once XP-G22 is answered).
- **XP-G20. A build-time path for an app's SDL_GPU shaders.** Asked on 2026-10-21 (xp-3's user decision U1(b): no compiled file in the repository,
  SDL_shadercross a build dependency of Linux and Windows) and answered by MetalUI S12 (record §138, rulings `BS-A` to `BS-I`, master `d995f4b4`):
  `MetalUICompileShaders` and the `CompileShaders` command plugin, a marker-free build product accepted by `SDLGPUShaderLibrary`, and the
  shadercross pin documented in `docs/packaging.md` §4a. MetalUI publishes no shadercross (ruling `BS-H`), so MetalCreator builds it: the
  `shadercross` stage of `scripts/linux/Dockerfile` (MetalUI's recipe, natively on x86_64 and aarch64) and `scripts/install-shadercross.ps1` on Windows.
- **XP-G22. A render batch submitted without `await`, so a click can render its own ID pass and wait for it.** `ViewportModel.click(at:modifiers:)` runs
  on the main actor and must deliver the face or edge under the press. On Metal `ViewportPicker` renders the ID buffer for the view as it is and waits
  (`waitUntilCompleted`), so a click is exact and immediate. On SDL xp-3 renders the ID buffer ahead, after the draw that follows a change of camera or
  scene, and a click whose view has a landed buffer is answered at once from it; but a click within the few milliseconds before that buffer lands (right
  after an orbit, a zoom, an edit or a camera animation) has no buffer for its view, and the typed layer cannot render one synchronously:
  `SDLGPUDevice.submitBatch(_:)` is `async`, and `SDLGPUCommandBuffer` exists only inside a batch. `downloadSynchronously` and `waitBlocking`
  (XP-G14) cover the read and the wait, not the render. Needed: `SDLGPUDevice.submitBatchSynchronously(_ record: @escaping @Sendable
  (SDLGPUCommandBuffer) -> Void) throws -> SDLGPUFence`, which records and submits on the submit worker as `submitBatch` does and returns once the buffer is
  submitted (the caller then `waitBlocking()`s the fence or calls `downloadSynchronously`, which the worker orders after it), with `GB-F`'s rules: legal on the
  main actor outside a surface draw, a debug trap inside one (`GA-I`), a precondition on the device's own worker threads. `downloadSynchronously` already
  submits this way inside MetalUI. Meanwhile (not blocking): such a click waits for its buffer asynchronously and is delivered a few milliseconds later,
  still exact and to the tool of its press (`ViewportModel.pickWhenReady`); a hover never waits. xp-3 task 7 step 6 replaces that wait with
  `submitBatchSynchronously`, `waitBlocking()` and `downloadSynchronously` once the verb lands. Not worked around: no raw `SDL_` call, no thread blocked
  on a task.

What the viewport does not need, and so does not ask for: fragment-stage storage buffers (a face's flags are read in the vertex stage and reach
the fragment stage as a flat interpolant), a vertex format of `uint` (every vertex stream is a storage buffer), a sampled `r8Unorm` mip chain
(`generateMipmaps` does it) and a depth readback.
````

- [ ] **Step 2: The GPU promise in `scripts/linux-test.sh`**

`scripts/linux-test.sh` (change against master; apply with `git apply` or by hand):

```diff
--- a/scripts/linux-test.sh
+++ b/scripts/linux-test.sh
@@ -6,7 +6,8 @@
 #     build   swift build
 #     test    swift test, judged by the pass rule below. Arguments after `test` (for example `--filter CreatorOCCTTests`) go to
 #             swift test and switch the count rule off: only the exit code and the issue lines are judged.
-#     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s)
+#     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s,
+#             and the 3D viewport drew in it)
 #     package scripts/package-linux.sh and scripts/package-appimage.sh in the image (the second downloads appimagetool and the
 #             AppImage runtime, pinned by version and sha256: it needs the network), then the tarball and the AppImage in dist/ are
 #             each run in a clean ubuntu:24.04 (no Swift, no /opt/occt, no MetalUI checkout, no FUSE) and must pass --version and
@@ -22,6 +23,11 @@
 # "Test run with" (one per test target that has tests: twelve on Linux, Windows and macOS since xp-2 put CreatorOCCTTests on
 # every platform).
 #
+# The image draws on Mesa's lavapipe, a CPU Vulkan driver, so the SDL_GPU viewport renders here with no GPU in the machine. Every
+# container sets XP_REQUIRE_GPU=1: the viewport's renderer suites skip when no SDL_GPU device answers, and with this set a missing
+# device fails SDLGPUAvailabilityTests instead, so a runner that lost its driver cannot pass by running none of them (MetalUI's
+# METALUI_REQUIRE_GPU).
+#
 # Environment: XP_TRACK names the track (default xp-1), which names the container and the volume, so a script run kills only
 # its own container. EXPECTED_TEST_RUNS overrides the count (12 today). IMAGE names the image this script builds and runs
 # (default metalcreator-linux:latest; a track that must not replace another's image sets its own). OpenCascade is built from
@@ -70,7 +76,7 @@
     docker rm -f "$NAME" >/dev/null 2>&1 || true
     # shellcheck disable=SC2086
     docker run --rm --name "$NAME" \
-        -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build ${DOCKER_EXTRA:-} \
+        -e XP_REQUIRE_GPU=1 -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build ${DOCKER_EXTRA:-} \
         "$IMAGE" bash -ec "$1"
 }
 
```

- [ ] **Step 3: Check the script and take the baselines**

```bash
bash -n scripts/linux-test.sh && echo syntax-ok
swift test --filter CreatorViewportTests 2>&1 | grep -E 'recorded an issue|failed after|Test run with'   # the macOS baseline
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter CreatorViewportTests 2>&1 | grep -E 'recorded an issue|failed after|Test run with|Linux:'   # the Linux baseline
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test 2>&1 | tail -1   # the Linux full-suite baseline
```

Expected: `syntax-ok`, no issue line, one `Test run with N tests in S suites passed` line for each platform's `CreatorViewportTests`, and `Linux: PASS (12 'Test run with' lines, T tests; …)`. **Write them down: they are this branch's baselines**, with master `1aad412`'s macOS full suite, **4822 tests in 12 "Test run with" lines** (not re-run here: one full macOS run comes in task 9). macOS `CreatorViewportTests` was 304 tests in 41 suites on `1aad412` (measured 2026-10-22). The Linux figures in this plan's "Expected" lines were measured on master `11aab8e` (259 tests in 34 suites); judge by the delta (`baseline + n`). (The first Linux run builds the image, OpenCascade's stage and MetalUI in the `xp-3-linux-build` volume: long; later runs are incremental.)

- [ ] **Step 4: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add docs/metalui-gaps.md scripts/linux-test.sh
git commit -m "docs: MetalUI gaps XP-G14 to XP-G20 answered (S11, S12), XP-G22 logged; linux-test.sh promises the GPU suites a device"
```


### Task 1: Plain SIMD types for the GPU: `FloatMatrix4` and `FrameUniforms`

`Matrix4.float` returned a `simd_float4x4` and `FrameUniforms` held two of them, so both existed only where `simd` does (macOS), and `GPUDataTests` pinned `FrameUniforms`' stride under `#if canImport(Metal)`. Both move to plain Swift SIMD types, so the structs the SDL renderer pushes exist everywhere. `FloatMatrix4` is four `SIMD4<Float>` columns: 64 bytes, the bytes `simd_float4x4` was, which is what MSL's `float4x4` reads, so the Metal renderer is unchanged.

**Files:**
- Create: `Sources/CreatorViewport/Render/FloatMatrix4.swift`
- Modify: `Sources/CreatorViewport/Camera/Matrix4.swift`
- Modify: `Sources/CreatorViewport/Render/FrameUniforms.swift`
- Modify: `Sources/CreatorViewport/Render/GPUGeometry.swift`
- Modify: `Tests/CreatorViewportTests/CameraMathTests.swift`
- Modify: `Tests/CreatorViewportTests/GPUDataTests.swift`

**Interfaces:**
- Consumes: `Matrix4`, `GPUGeometry.frameUniforms(_:size:sceneRadius:pixelWidth:pixelHeight:)`.
- Produces: `struct FloatMatrix4: Equatable, Sendable { var c0, c1, c2, c3: SIMD4<Float>; static let identity }`; `Matrix4.float: FloatMatrix4`; `FrameUniforms` (176 bytes: `viewProjection`, `view` at 64, `eye` 128, `forward` 144, `viewportPixels` 160, `isOrthographic` 168, `padding` 172) on every platform.

- [ ] **Step 1: Write the failing tests**

The strides and offsets are pinned for every platform now, not only where Metal is; the float conversion test reads the columns of `FloatMatrix4`.

`Tests/CreatorViewportTests/CameraMathTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/CameraMathTests.swift
+++ b/Tests/CreatorViewportTests/CameraMathTests.swift
@@ -1,8 +1,5 @@
 import CreatorGeometry
 import Foundation
-#if canImport(simd)
-import simd
-#endif
 import Testing
 @testable import CreatorViewport
 
@@ -76,14 +73,13 @@
     }
 
     @Test func floatConversionKeepsTheColumns() {
-        #if canImport(simd)
-        #expect(Matrix4.identity.float == matrix_identity_float4x4)
+        #expect(Matrix4.identity.float == FloatMatrix4.identity)
         let asymmetric = Matrix4(c0: [1, 2, 3, 4], c1: [5, 6, 7, 8], c2: [9, 10, 11, 12], c3: [13, 14, 15, 16])
         let converted = asymmetric.float
-        #expect(converted.columns.0 == SIMD4<Float>(1, 2, 3, 4))
-        #expect(converted.columns.1 == SIMD4<Float>(5, 6, 7, 8))
-        #expect(converted.columns.3 == SIMD4<Float>(13, 14, 15, 16))
-        #endif
+        #expect(converted.c0 == SIMD4<Float>(1, 2, 3, 4))
+        #expect(converted.c1 == SIMD4<Float>(5, 6, 7, 8))
+        #expect(converted.c2 == SIMD4<Float>(9, 10, 11, 12))
+        #expect(converted.c3 == SIMD4<Float>(13, 14, 15, 16))
         let product = Matrix4.identity * Matrix4.identity
         #expect(product == .identity)
     }
```

`Tests/CreatorViewportTests/GPUDataTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/GPUDataTests.swift
+++ b/Tests/CreatorViewportTests/GPUDataTests.swift
@@ -1,8 +1,5 @@
 import CreatorGeometry
 import CreatorKernel
-#if canImport(simd)
-import simd
-#endif
 import Testing
 @testable import CreatorViewport
 
@@ -19,10 +16,13 @@
         #expect(MemoryLayout<CubeVertex>.stride == 64)
         #expect(MemoryLayout<CubeVertex>.offset(of: \CubeVertex.uv) == 32)
         #expect(MemoryLayout<CubeVertex>.offset(of: \CubeVertex.labelRect) == 48)
-        #if canImport(Metal)
+        #expect(MemoryLayout<FloatMatrix4>.stride == 64)
         #expect(MemoryLayout<FrameUniforms>.stride == 176)
+        #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.view) == 64)
+        #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.eye) == 128)
+        #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.forward) == 144)
         #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.viewportPixels) == 160)
-        #endif
+        #expect(MemoryLayout<FrameUniforms>.offset(of: \FrameUniforms.isOrthographic) == 168)
         #expect(MemoryLayout<DrawUniforms>.stride == 16)
         #expect(MemoryLayout<ShadeUniforms>.stride == 80)
         #expect(MemoryLayout<ClipUniforms>.stride == 32)
@@ -131,7 +131,6 @@
         #expect(!turned.contains(where: isCyan), "between regions, nothing is active")
     }
 
-    #if canImport(Metal)
     @Test func frameUniformsCarryTheViewportAndProjection() {
         let pose = CameraPose(target: .zero, distance: 10, yaw: 0, pitch: 0, projection: .orthographic)
         let uniforms = GPUGeometry.frameUniforms(pose, size: ViewportSize(width: 200, height: 100), sceneRadius: 5,
@@ -140,7 +139,6 @@
         #expect(uniforms.isOrthographic == 1)
         #expect(uniforms.forward == SIMD3(0, 1, 0))
     }
-    #endif
 
     @Test func theGridIsCentredOnTheTargetSnappedToMajorLines() {
         var frame = ViewportFrame(pose: CameraPose(target: Vector3(123, -47, 9), distance: 100),
```

- [ ] **Step 2: Run the tests: they fail**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. macOS: `cannot find 'FloatMatrix4' in scope` (in `GPUDataTests.swift` and `CameraMathTests.swift`).

- [ ] **Step 3: Implement**

`Sources/CreatorViewport/Render/FloatMatrix4.swift` (new):

```swift
/// A column-major 4×4 matrix in Float, as the GPU reads it: four columns of `SIMD4<Float>` and nothing from `simd`, so it
/// exists on every platform. Its 64 bytes are what `simd_float4x4` was (MSL's `float4x4`; HLSL reads the columns one by one).
struct FloatMatrix4: Equatable, Sendable {
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>

    static let identity = FloatMatrix4(c0: [1, 0, 0, 0], c1: [0, 1, 0, 0], c2: [0, 0, 1, 0], c3: [0, 0, 0, 1])
}
```

`Sources/CreatorViewport/Camera/Matrix4.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Camera/Matrix4.swift
+++ b/Sources/CreatorViewport/Camera/Matrix4.swift
@@ -1,8 +1,4 @@
-#if canImport(simd)
-import simd
-#endif
-
-/// A column-major 4×4 matrix in Double, converted to `simd_float4x4` for the GPU.
+/// A column-major 4×4 matrix in Double, converted to ``FloatMatrix4`` for the GPU.
 struct Matrix4: Equatable, Sendable {
     var c0: SIMD4<Double>
     var c1: SIMD4<Double>
@@ -19,9 +15,7 @@
         Matrix4(c0: a * b.c0, c1: a * b.c1, c2: a * b.c2, c3: a * b.c3)
     }
 
-    #if canImport(simd)
-    var float: simd_float4x4 {
-        simd_float4x4(columns: (SIMD4<Float>(c0), SIMD4<Float>(c1), SIMD4<Float>(c2), SIMD4<Float>(c3)))
+    var float: FloatMatrix4 {
+        FloatMatrix4(c0: SIMD4<Float>(c0), c1: SIMD4<Float>(c1), c2: SIMD4<Float>(c2), c3: SIMD4<Float>(c3))
     }
-    #endif
 }
```

`Sources/CreatorViewport/Render/FrameUniforms.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/FrameUniforms.swift
+++ b/Sources/CreatorViewport/Render/FrameUniforms.swift
@@ -1,10 +1,8 @@
-#if canImport(Metal)
-import simd
-
-/// Per-pass camera data for every vertex shader.
+/// Per-pass camera data for every vertex shader. Plain SIMD types, so it is the same on every platform: the Metal shaders
+/// (`ViewportShaders`) and the HLSL ones (`Shaders/viewport/common.hlsli`) read these 176 bytes, which `GPUDataTests` pins.
 struct FrameUniforms {
-    var viewProjection: simd_float4x4
-    var view: simd_float4x4
+    var viewProjection: FloatMatrix4
+    var view: FloatMatrix4
     var eye: SIMD3<Float>
     var forward: SIMD3<Float>
     /// The render target's size in pixels (lines are sized in pixels).
@@ -12,4 +10,3 @@
     var isOrthographic: UInt32
     var padding: Float
 }
-#endif
```

`Sources/CreatorViewport/Render/GPUGeometry.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/GPUGeometry.swift
+++ b/Sources/CreatorViewport/Render/GPUGeometry.swift
@@ -109,7 +109,6 @@
         return flags
     }
 
-    #if canImport(Metal)
     static func frameUniforms(_ pose: CameraPose, size: ViewportSize, sceneRadius: Double, pixelWidth: Int,
                               pixelHeight: Int) -> FrameUniforms {
         let view = CameraMath.view(pose)
@@ -118,7 +117,6 @@
                              forward: float3(-pose.toEye), viewportPixels: SIMD2(Float(pixelWidth), Float(pixelHeight)),
                              isOrthographic: pose.projection == .orthographic ? 1 : 0, padding: 0)
     }
-    #endif
 
     /// A grid square around the target, snapped to major lines so it doesn't swim while panning, and large
     /// enough to reach the horizon.
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 304 tests in 41 suites passed` (baseline 304/41 + 0 tests, + 0 suites).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 260 tests in 34 suites passed` (baseline 259/34 + 1 test, + 0 suites).

`FrameUniforms` and `GPUGeometry.frameUniforms` are no longer inside `#if canImport(Metal)`: the Linux run now compiles and runs `frameUniformsCarryTheViewportAndProjection`.
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorViewport/Camera/Matrix4.swift \
  Sources/CreatorViewport/Render/FloatMatrix4.swift \
  Sources/CreatorViewport/Render/FrameUniforms.swift \
  Sources/CreatorViewport/Render/GPUGeometry.swift \
  Tests/CreatorViewportTests/CameraMathTests.swift \
  Tests/CreatorViewportTests/GPUDataTests.swift
git commit -m "viewport: FloatMatrix4 and FrameUniforms in plain SIMD, on every platform"
```


### Task 2: The viewport behind a protocol: `ViewportBackend`, `MetalViewportBackend`, a portable `ViewportView`

`ViewportModel` keeps a `ViewportBackend?` where it kept `ViewportRenderer?`. The protocol is only what the model needs: how many passes were drawn, what is under a point, and, for a renderer whose readback is asynchronous, whether that answer is still on its way (`isPickPending`), a way to wait for it (`pickWhenReady`) and a callback when it lands (`onPickReady`). This is user decision U4, **hybrid**: a hover answers from the latest landed buffer and keeps its face while a pick is pending (never "empty space" for a few milliseconds, never a stalled frame); a click is exact: it waits for the buffer of its own view and is delivered on the target that lands, **to the tool and with the projector the press had** (not whatever a tool change or a camera animation made of them in the milliseconds between; the tool-change test pins it). The wait is asynchronous because MetalUI cannot yet submit a render batch without `await` (gap XP-G22); task 7 step 6 makes `pickWhenReady` synchronous once it can, and this task's waiting-click code and its two tests go then. A backend also says whether it `drawsWidgets` (the view cube and the axis triad): the model hit-tests the cube (hover, click, drag, the context menu's exclusion) only while the backend draws it, through `cubeCatches(_:)`, so on SDL, between this task and task 10, the cube's corner is the scene's and nothing invisible rotates the camera (the cube's arrow buttons and View menu are MetalUI views and stay). `MetalViewportBackend` wraps `ViewportRenderer` and `ViewportPicker` as they are and never reports pending, so macOS behaves exactly as before. `ViewportView` and its parts are no longer fenced by `#if canImport(Metal)`: the surface is `MetalView` on macOS and MetalUI's portable `GPUSurface` elsewhere, with a `draw` overload per context (off Metal it only clears until task 8 installs the SDL renderer).

**Files:**
- Create: `Sources/CreatorViewport/Model/ViewportModel+Backend.swift`
- Create: `Sources/CreatorViewport/Render/MetalViewportBackend.swift`
- Create: `Sources/CreatorViewport/Render/ViewportBackend.swift`
- Create: `Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift`
- Create: `Tests/CreatorViewportTests/ViewportBackendTests.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Input.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift`
- Modify: `Sources/CreatorViewport/View/ViewportModel+Surface.swift`
- Modify: `Sources/CreatorViewport/View/ViewportView+Parts.swift`
- Modify: `Sources/CreatorViewport/View/ViewportView.swift`

**Interfaces:**
- Consumes: `ViewportRenderer`, `ViewportPicker`, `ViewportFrame`, `PickTarget`, `ScreenPoint`.
- Produces: `@MainActor protocol ViewportBackend: AnyObject { var drawnFrames: Int; var onPickReady: (@MainActor () -> Void)?; func pick(at:in:) -> PickTarget?; func isPickPending(for:) -> Bool; func pickWhenReady(at:in:) async -> PickTarget?; var drawsWidgets: Bool }` (the last three default to "never pending", "never pending" and `true`); `ViewportModel.install(_ backend: any ViewportBackend)`, `ViewportModel.drawnFrames: Int`, `ViewportModel.gpuFailureMessage: String?` (portable now), `ViewportModel.isPickPending`, `ViewportModel.pickWhenReady`; `final class MetalViewportBackend: ViewportBackend` (`init(device:) throws`, `renderer`, `picker`).

- [ ] **Step 1: Write the failing tests**

A `FakeBackend` answers as a test tells it to and holds a pick back like an SDL readback that has not landed. The tests are portable (they run on Linux).

`Tests/CreatorViewportTests/ViewportBackendTests.swift` (new):

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// A backend that answers picks as a test tells it to, and holds them back like an SDL_GPU readback that has not landed.
@MainActor
final class FakeBackend: ViewportBackend {
    var drawnFrames = 0
    var onPickReady: (@MainActor () -> Void)?
    var isPending = false
    var answer: PickTarget?
    /// What a real backend answers for ``ViewportBackend/drawsWidgets``.
    var drawsWidgets = true
    private var waiters: [CheckedContinuation<PickTarget?, Never>] = []
    private var registration: CheckedContinuation<Void, Never>?

    /// How many clicks are waiting for the ID buffer.
    var waitersRegistered: Int { waiters.count }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? { isPending ? nil : answer }

    func isPickPending(for frame: ViewportFrame) -> Bool { isPending }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        if !isPending { return answer }
        return await withCheckedContinuation {
            waiters.append($0)
            registration?.resume()
            registration = nil
        }
    }

    /// Returns once a click is waiting (at once if one already is): the model's click `Task` has run and registered.
    func untilAWaiterIsRegistered() async {
        if !waiters.isEmpty { return }
        await withCheckedContinuation { registration = $0 }
    }

    /// The ID buffer lands: pending ends, waiting clicks are answered and the model is told.
    func land(_ target: PickTarget?) {
        isPending = false
        answer = target
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume(returning: target) }
        onPickReady?()
    }
}

/// The model talks to its renderer through `ViewportBackend`: picks go through it, and a pick that is still on its way neither
/// clears the hover nor turns a click into one on empty space (the SDL_GPU backend's readback is asynchronous).
@MainActor
struct ViewportBackendTests {
    let face = PickTarget.face(solid: 0, FaceID(2))
    let edge = PickTarget.edge(solid: 0, EdgeID(3))

    func makeModel(_ backend: FakeBackend) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.install(backend)
        return model
    }

    @Test func aModelWithoutABackendHasDrawnNothingAndNoFailure() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        #expect(model.drawnFrames == 0)
        #expect(model.gpuFailureMessage == nil)
    }

    @Test func drawnFramesAreTheBackendsOwn() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.drawnFrames = 3
        #expect(model.drawnFrames == 3)
    }

    @Test func aHoverIsPickedThroughTheBackend() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: ScreenPoint(200, 200))
        #expect(model.hovered == face)
        backend.answer = nil
        model.pointerHovered(at: ScreenPoint(10, 10))
        #expect(model.hovered == nil)
    }

    @Test func aHoverKeepsItsFaceWhileThePickIsPendingAndTakesTheLandedOne() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: ScreenPoint(200, 200))
        backend.isPending = true
        model.pointerHovered(at: ScreenPoint(210, 200))
        #expect(model.hovered == face, "no answer yet: the face stays, not empty space")
        backend.land(edge)
        #expect(model.hovered == edge, "the landed buffer looks under the pointer again")
    }

    @Test func aClickIsDeliveredAtOnceWhenNothingIsPending() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        var clicked: PickTarget??
        model.events.clicked = { clicked = $0 }
        model.click(at: ScreenPoint(200, 200))
        #expect(clicked == .some(face))
    }

    @Test(.timeLimit(.minutes(1)))
    func aClickWaitsForAPendingPickAndIsThenDeliveredOnTheLandedTarget() async {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.isPending = true
        var landed = false
        var deliveredBeforeLanding = false
        var waitersWhenLanding = 0
        let delivered = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
            model.events.clicked = {
                deliveredBeforeLanding = !landed
                continuation.resume(returning: $0)
            }
            model.click(at: ScreenPoint(200, 200))
            Task {
                await backend.untilAWaiterIsRegistered()
                waitersWhenLanding = backend.waitersRegistered
                landed = true
                backend.land(face)
            }
        }
        #expect(waitersWhenLanding == 1, "the click is waiting for the buffer, not already answered")
        #expect(!deliveredBeforeLanding, "nothing was delivered while the pick was pending")
        #expect(delivered == face, "the click was on the face, not on empty space")
    }

    @Test(.timeLimit(.minutes(1)))
    func aWaitingClickGoesToTheToolItWasMadeWithAndNotTheOneSetWhileItWaited() async {
        let backend = FakeBackend()
        let model = makeModel(backend)
        let first = RecordingTool()
        first.claims = false
        let second = RecordingTool()
        second.claims = false
        model.tool = first
        backend.isPending = true
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
            model.events.clicked = { continuation.resume(returning: $0) }
            model.click(at: ScreenPoint(200, 200))
            model.tool = second   // the tool changes in the milliseconds before the buffer lands
            Task {
                await backend.untilAWaiterIsRegistered()
                backend.land(face)
            }
        }
        #expect(first.modelPicks == [face], "the press belonged to the first tool")
        #expect(second.modelPicks.isEmpty)
    }

    @Test func aBackendThatDrawsNoCubeLeavesItsCornerToTheScene() {
        let backend = FakeBackend()
        backend.drawsWidgets = false
        let model = makeModel(backend)
        backend.answer = face
        let corner = model.cubeLayout.center
        model.pointerHovered(at: corner)
        #expect(model.hoveredCubeRegion == nil, "no cube is drawn there to highlight")
        #expect(model.hovered == face, "the scene under the corner is picked instead")
        var clicked: PickTarget??
        model.events.clicked = { clicked = $0 }
        model.click(at: corner)
        #expect(clicked == .some(face))
        #expect(!model.isAnimating, "a click there does not turn the camera")
        #expect(model.showsViewCube, "the cube's controls (arrows, View menu) stay")
    }

    @Test func aBackendThatDrawsTheCubeLetsItTurnTheCamera() {
        let backend = FakeBackend()
        let model = makeModel(backend)
        backend.answer = face
        model.pointerHovered(at: model.cubeLayout.center)
        #expect(model.hoveredCubeRegion != nil)
        #expect(model.hovered == nil)
        model.click(at: model.cubeLayout.center)
        #expect(model.isAnimating)
    }
}
```

- [ ] **Step 2: Run the tests: they fail**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. `cannot find type 'ViewportBackend' in scope`, `value of type 'ViewportModel' has no member 'install'`.

- [ ] **Step 3: Implement**

`ViewportModel+Surface.swift` is the Metal `draw`, now making and keeping a `MetalViewportBackend`; `ViewportModel+SDLSurface.swift` is the portable `draw` for a build without Metal, a clear until task 8.

`Sources/CreatorViewport/Model/ViewportModel+Backend.swift` (new):

```swift
extension ViewportModel {
    /// Why the viewport's GPU objects couldn't be made, if they couldn't. The surface is then cleared to dark red.
    public var gpuFailureMessage: String? { gpuFailure }

    /// Main passes the backend has drawn (0 before the first draw, or when the GPU objects could not be made).
    public var drawnFrames: Int { backend?.drawnFrames ?? 0 }

    /// Whether `point` is on a view cube that is both wanted (`showsViewCube`) and drawn (``ViewportBackend/drawsWidgets``). Every cube
    /// hit test goes through here, so a backend that draws no cube leaves the top-left corner to the scene. A model with no backend
    /// yet (before the first draw, and in tests that set `pick` directly) counts the cube as drawn.
    func cubeCatches(_ point: ScreenPoint) -> Bool {
        showsViewCube && (backend?.drawsWidgets ?? true) && cubeLayout.contains(point)
    }

    /// Makes `backend` the code that draws and picks for this model: picks go through it, a hover waits out an ID buffer that is
    /// still on its way, and a landed buffer looks under the pointer again.
    func install(_ backend: any ViewportBackend) {
        self.backend = backend
        pick = { [weak self] point in
            guard let self else { return nil }
            return backend.pick(at: point, in: frame(at: clock.now()))
        }
        isPickPending = { [weak self] in
            guard let self else { return false }
            return backend.isPickPending(for: frame(at: clock.now()))
        }
        pickWhenReady = { [weak self] point in
            guard let self else { return nil }
            return await backend.pickWhenReady(at: point, in: frame(at: clock.now()))
        }
        backend.onPickReady = { [weak self] in self?.refreshHover() }
    }
}
```

`Sources/CreatorViewport/Render/MetalViewportBackend.swift` (new):

```swift
#if canImport(Metal)
import Metal

/// The macOS backend: the Metal renderer and the picker that renders and reads back its ID buffer on its own queue. A pick is
/// answered at once (it waits for the GPU, as `ViewportPicker` always did), so nothing is ever pending.
@MainActor
final class MetalViewportBackend: ViewportBackend {
    let renderer: ViewportRenderer
    let picker: ViewportPicker
    var onPickReady: (@MainActor () -> Void)?

    init(device: any MTLDevice) throws {
        renderer = try ViewportRenderer(device: device)
        picker = try ViewportPicker(renderer: renderer)
    }

    var drawnFrames: Int { renderer.encodedPasses }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        picker.pick(at: point, in: frame)
    }
}
#endif
```

`Sources/CreatorViewport/Render/ViewportBackend.swift` (new):

```swift
/// What `ViewportModel` needs from the code that draws and picks for it, whichever GPU API that code speaks (cross-platform
/// spec section 4): `MetalViewportBackend` on macOS, `SDLViewportBackend` on Linux and Windows. The drawing itself is not here: it
/// takes the API's own draw context, so each backend has its own `draw` in `ViewportModel+Surface` and `+SDLSurface`.
///
/// Picking is the part the model sees (user decision U4, hybrid). Metal answers a pick at once, by rendering the ID buffer and waiting
/// for it. The SDL_GPU backend answers a hover from the ID buffer it rendered ahead (``isPickPending(for:)`` says when that buffer is not
/// for the camera and scene of the frame asked about yet) and calls ``onPickReady`` when a new one lands; a click asks
/// ``pickWhenReady(at:in:)``, which answers from a buffer for the click's own view, waiting for it (asynchronously until MetalUI gap
/// XP-G22 lets it render one synchronously).
@MainActor
protocol ViewportBackend: AnyObject {
    /// Main passes drawn so far. Tests and the launch smoke test use it to tell "drew" from "bailed out".
    var drawnFrames: Int { get }

    /// Called after an ID buffer has landed for a frame that had none, so the model can look again under a pointer that
    /// has not moved (`ViewportModel.refreshHover()`). A synchronous backend never calls it.
    var onPickReady: (@MainActor () -> Void)? { get set }

    /// The face or edge under `point` (viewport points) in `frame`, or `nil` for empty space, a point outside the view, a
    /// view with no size yet, or an answer that is not ready (``isPickPending(for:)``).
    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget?

    /// Whether the ID buffer for `frame` is on its way, so ``pick(at:in:)`` would answer `nil` for want of it.
    func isPickPending(for frame: ViewportFrame) -> Bool

    /// The click's pick: ``pick(at:in:)`` from an ID buffer for `frame` itself, once it has landed. Never another view's answer.
    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget?

    /// Whether this backend draws the view cube and the axis triad. The model hit-tests the cube (hover, click, drag, the context menu's
    /// exclusion) only while it is drawn: a cube nobody can see must not rotate the camera. Metal draws them; the SDL backend says
    /// `false` until the cube and triad are drawn there (task 10).
    var drawsWidgets: Bool { get }
}

extension ViewportBackend {
    var drawsWidgets: Bool { true }

    func isPickPending(for frame: ViewportFrame) -> Bool { false }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        pick(at: point, in: frame)
    }
}
```

`Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift` (new):

```swift
#if !canImport(Metal)
import MetalUI

extension ViewportModel {
    /// The `GPUSurface` draw where there is no Metal. Until the SDL renderer is installed (xp-3 task 8) it clears the surface to the
    /// colour a viewport whose GPU objects could not be made shows on macOS.
    func draw(_ context: any GPUSurfaceContext) {
        context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
    }
}
#endif
```

`Sources/CreatorViewport/Model/ViewportModel+Input.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Input.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Input.swift
@@ -60,7 +60,7 @@
         var mode = ViewportInputMap.dragMode(for: modifiers, button: button)
         var pivot: Vector3?
         var handleStart = 0.0
-        if button != .middle, showsViewCube, cubeLayout.contains(point) {
+        if button != .middle, cubeCatches(point) {
             mode = .cube
         } else if button == .primary, let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
             mode = .handle(handle.id)
@@ -128,18 +128,35 @@
         if let state = drag, state.button != .primary { pointerUp(at: state.last) }
         events.pressed()
         stopAnimation()
-        if showsViewCube, cubeLayout.contains(point) {
+        if cubeCatches(point) {
             if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
         } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil,
                   tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
-            let target = pick?(point)
-            if tool?.clickedModel(target, at: point, modifiers: modifiers, projector: projector) != true {
-                events.clicked(target)
+            if isPickPending?() == true, let pickWhenReady {
+                // The ID buffer for this view is still on its way: the click is delivered when it lands, not as a click on empty space.
+                // It is the click of the press: the tool and the projector are those of the press, not of whatever the tool or an
+                // animating camera has become by the time the buffer lands.
+                let pressTool = tool
+                let pressProjector = projector
+                Task { [self] in
+                    let target = await pickWhenReady(point)
+                    deliverClick(on: target, at: point, modifiers: modifiers, tool: pressTool, projector: pressProjector)
+                }
+            } else {
+                deliverClick(on: pick?(point), at: point, modifiers: modifiers, tool: tool, projector: projector)
             }
         }
         pointerReleased(at: point)
     }
 
+    /// Offers a click on `target` (the face or edge under it, or `nil` for empty space) to the tool and, unclaimed, reports it.
+    private func deliverClick(on target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
+                              tool: (any ViewportTool)?, projector: ViewportProjector) {
+        if tool?.clickedModel(target, at: point, modifiers: modifiers, projector: projector) != true {
+            events.clicked(target)
+        }
+    }
+
     /// The pointer is at the release point now. Released outside the view, it's not over it at all.
     private func pointerReleased(at point: ScreenPoint) {
         let inside = !viewSize.isEmpty && (0...viewSize.width).contains(point.x) && (0...viewSize.height).contains(point.y)
@@ -157,8 +174,10 @@
         var newHovered: PickTarget?
         var newCubeRegion: ViewCubeRegion?
         if let point {
-            if showsViewCube, cubeLayout.contains(point) {
+            if cubeCatches(point) {
                 newCubeRegion = cubeLayout.region(at: point, pose: currentPose())
+            } else if isPickPending?() == true {
+                newHovered = hovered   // the ID buffer for this view is on its way: keep the face until it lands (`onPickReady`)
             } else {
                 newHovered = pick?(point)
             }
```

`Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift
@@ -10,7 +10,7 @@
     /// `tool` holds the pointer (a sketch is open) it only navigates: Look At, and nothing that edits or selects; with
     /// planar navigation it's empty, since Look At would turn the camera.
     public func contextMenuItems(at point: ScreenPoint?) -> [ViewportMenuItem] {
-        guard let point, !isPlanar, !cubeLayout.contains(point), let ref = faceRef(for: pick?(point)),
+        guard let point, !isPlanar, !cubeCatches(point), let ref = faceRef(for: pick?(point)),
               let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
         guard tool == nil else { return [.lookAt(ref)] }
         var menu: [ViewportMenuItem] = [.lookAt(ref), .selectEdgesOfFace(ref)]
```

`Sources/CreatorViewport/Model/ViewportModel.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel.swift
@@ -68,8 +68,13 @@
     /// build has been laid out). Tracked, so what is built from it (the handle and overlay labels) is rebuilt after a
     /// resize.
     public internal(set) var viewSize = ViewportSize(width: 0, height: 0)
-    /// Answers "what is under this point?". It's set when the GPU objects are made, and tests set it directly.
+    /// Answers "what is under this point?". It's set when the GPU objects are made (`install(_:)`), and tests set it directly.
     @ObservationIgnored var pick: (@MainActor (ScreenPoint) -> PickTarget?)?
+    /// Whether `pick` has no answer yet because the ID buffer for the view as it is now is on its way (an SDL_GPU backend reads it back
+    /// asynchronously). A hover then keeps the face it had, and a click waits for `pickWhenReady`. `nil` means never.
+    @ObservationIgnored var isPickPending: (@MainActor () -> Bool)?
+    /// `pick`, once the ID buffer for the view as it is now has landed.
+    @ObservationIgnored var pickWhenReady: (@MainActor (ScreenPoint) async -> PickTarget?)?
     @ObservationIgnored var drag: DragState?
     /// The camera when the scroll under way (a trackpad scroll, or a run of wheel steps) began; `nil` between scrolls.
     @ObservationIgnored var scrollStartPose: CameraPose?
@@ -81,10 +86,10 @@
     /// The `ViewportModifiers.hoverMask` modifiers held now, from `ViewportView`'s `onModifierKeysChanged`
     /// (`modifiersChanged(_:)`): what a hover tells the tool beside the pointer.
     @ObservationIgnored var heldModifiers: ViewportModifiers = []
-    #if canImport(Metal)
-    @ObservationIgnored var gpuRenderer: ViewportRenderer?
+    /// The code that draws and picks for this model, made on the first draw (`install(_:)`).
+    @ObservationIgnored var backend: (any ViewportBackend)?
+    /// Why the GPU objects could not be made, if they could not (`gpuFailureMessage`).
     @ObservationIgnored var gpuFailure: String?
-    #endif
     @ObservationIgnored private var meshTask: Task<Void, Never>?
     @ObservationIgnored private var animationTask: Task<Void, Never>?
     @ObservationIgnored private var needsFirstFraming: Bool
```

`Sources/CreatorViewport/View/ViewportModel+Surface.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/View/ViewportModel+Surface.swift
+++ b/Sources/CreatorViewport/View/ViewportModel+Surface.swift
@@ -3,34 +3,26 @@
 import MetalUI
 
 extension ViewportModel {
-    /// Why the viewport's GPU objects couldn't be made, if they couldn't. The surface is then cleared to dark red.
-    public var gpuFailureMessage: String? { gpuFailure }
-
     /// The `MetalView` draw (spec §6.3). It runs on the main actor inside MetalUI's frame, after the tracked build.
     /// It makes the GPU objects on first use and encodes into the frame's own command buffer. It writes only untracked
     /// state (a draw must never dirty the window), and it never commits. The view's size is not recorded here: it
     /// comes from `ViewportView`'s `onGeometryChange`.
     func draw(_ context: MetalDrawContext) {
         let scale = context.scaleFactor > 0 ? Double(context.scaleFactor) : 1
-        guard let renderer = renderer(for: context.device) else {
+        guard let metal = metalBackend(for: context.device) else {
             context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
             return
         }
-        renderer.encode(frame(at: clock.now()), into: context.target, scale: scale, commandBuffer: context.commandBuffer)
+        metal.renderer.encode(frame(at: clock.now()), into: context.target, scale: scale, commandBuffer: context.commandBuffer)
     }
 
-    private func renderer(for device: any MTLDevice) -> ViewportRenderer? {
-        if let gpuRenderer { return gpuRenderer }
+    private func metalBackend(for device: any MTLDevice) -> MetalViewportBackend? {
+        if let existing = backend as? MetalViewportBackend { return existing }
         guard gpuFailure == nil else { return nil }
         do {
-            let renderer = try ViewportRenderer(device: device)
-            let picker = try ViewportPicker(renderer: renderer)
-            gpuRenderer = renderer
-            pick = { [weak self] point in
-                guard let self else { return nil }
-                return picker.pick(at: point, in: frame(at: clock.now()))
-            }
-            return renderer
+            let made = try MetalViewportBackend(device: device)
+            install(made)
+            return made
         } catch {
             gpuFailure = String(describing: error)
             return nil
```

`Sources/CreatorViewport/View/ViewportView+Parts.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/View/ViewportView+Parts.swift
+++ b/Sources/CreatorViewport/View/ViewportView+Parts.swift
@@ -1,4 +1,3 @@
-#if canImport(Metal)
 import MetalUI
 
 extension ViewportView {
@@ -47,9 +46,7 @@
     /// buttons drag in their own arenas (MetalUI `CI-F`).
     @MainActor
     static func surface(model: ViewportModel) -> some Element {
-        MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
-            model.draw(context)
-        }
+        gpuSurface(model: model)
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .pointerStyle(model.cursor?.pointerStyle)
         .onScrollWheel { event in
@@ -76,6 +73,22 @@
                 Button(item.title) { model.choose(item) }
             }
         }
+    }
+
+    /// The GPU surface itself: `MetalView` on macOS (its closure takes the Metal context), MetalUI's portable `GPUSurface` elsewhere
+    /// (its closure takes the backend's context, `SDLGPUDrawContext` on SDL; `ViewportModel+SDLSurface`). Both redraw on demand when
+    /// `renderKey` changes, and continuously while the camera animates.
+    @MainActor
+    private static func gpuSurface(model: ViewportModel) -> some Element {
+        #if canImport(Metal)
+        return MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
+            model.draw(context)
+        }
+        #else
+        return GPUSurface(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
+            model.draw(context)
+        }
+        #endif
     }
 
     /// A drag with `button` that reports its values, and the modifiers held at each, to the model, and its cancellation
@@ -146,4 +159,3 @@
                 y: Pixels(Float(model.cubeLayout.origin.y + model.cubeLayout.side + 6)))
     }
 }
-#endif
```

`Sources/CreatorViewport/View/ViewportView.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/View/ViewportView.swift
+++ b/Sources/CreatorViewport/View/ViewportView.swift
@@ -1,4 +1,3 @@
-#if canImport(Metal)
 import MetalUI
 
 /// The 3D viewport (spec §6.3) as a MetalUI component:
@@ -34,4 +33,3 @@
             }
     }
 }
-#endif
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 313 tests in 42 suites passed` (baseline 304/41 + 9 tests, + 1 suite).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 269 tests in 35 suites passed` (baseline 259/34 + 10 tests, + 1 suite).

On Linux `ViewportView` compiles for the first time (`GPUSurface`); the build is the check.

The click's `Task` and the model's async `pickWhenReady` closure are Windows-sensitive (Global Constraints): build them release with the asserts snapshot too, and read the Windows job's "Build release (for the zip)" step after the next push.

```bash
TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release 2>&1 | grep -E 'error:|Assertion|While splitting|Build complete'
```
Expected: `Build complete!`, no assertion and no `While splitting coroutine`.
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorViewport/Model/ViewportModel+Backend.swift \
  Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift \
  Sources/CreatorViewport/Model/ViewportModel+Input.swift \
  Sources/CreatorViewport/Model/ViewportModel.swift \
  Sources/CreatorViewport/Render/MetalViewportBackend.swift \
  Sources/CreatorViewport/Render/ViewportBackend.swift \
  Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift \
  Sources/CreatorViewport/View/ViewportModel+Surface.swift \
  Sources/CreatorViewport/View/ViewportView+Parts.swift \
  Sources/CreatorViewport/View/ViewportView.swift \
  Tests/CreatorViewportTests/ViewportBackendTests.swift
git commit -m "viewport: ViewportBackend protocol, MetalViewportBackend, portable ViewportView"
```


### Task 3: The cube's face names through MetalUI's text system

`CubeLabelAtlas.rasterize()` used CoreText (`CGContext`, `CTLine`) and so existed on macOS only. `rasterize(using: any TextSystem)` does the same job through MetalUI's `TextSystem`: it asks for the system face at weight 0.3 (CoreText's semibold, which the old code asked for too), measures the six names' ink, takes the largest size at which the widest fits its rect inside the margin, and paints each name centred in its rect on a shared baseline, from `placeGlyphs` and `rasterize(_ key: GlyphKey)`. `CubeLabelFonts.atlas()` chooses the system: `CoreTextTextSystem()` on macOS, MetalUI's `PortableTextSystem` over the installed fonts elsewhere, and a blank atlas (the cube draws unlabelled) when there are no fonts. `CubeLabelTests` stop being macOS-only. `Package.swift` names `MetalUIPortableText` and `MetalUISystemFonts` for `CreatorViewport` on every platform (MetalUI `SG-D`). This is user decision U8: macOS rasterizes through the same path.

**Files:**
- Create: `Sources/CreatorViewport/Render/CubeLabelAtlas+TextSystem.swift`
- Create: `Sources/CreatorViewport/Render/CubeLabelFonts.swift`
- Modify: `Package.swift`
- Modify: `Sources/CreatorViewport/Render/CubeLabelAtlas.swift`
- Modify: `Sources/CreatorViewport/Render/ViewCubeResources.swift`
- Modify: `Tests/CreatorViewportTests/CubeLabelTests.swift`
- Modify: `Tests/CreatorViewportTests/Support/CubeLabelAtlas+Ink.swift`
- Delete: `Sources/CreatorViewport/Render/CubeLabelAtlas+CoreText.swift`

**Interfaces:**
- Consumes: MetalUI `TextSystem` (`resolveFont`, `placeGlyphs`, `rasterize`), `FontDescriptor`, `GlyphImage`; `CubeLabelAtlas.rect(for:)`, `.blank`, `ViewCubeRegion.faces`.
- Produces: `CubeLabelAtlas.rasterize(using:) -> CubeLabelAtlas?` (`@MainActor`); `CubeLabelFonts.atlas() -> CubeLabelAtlas` (`@MainActor`); `Package.swift`: `CreatorViewport` depends on `metalUIPortableText` and `metalUISystemFonts`.

- [ ] **Step 1: Write the failing tests**

The existing atlas tests run on every platform now and a new one pins the six names to one baseline inside their rects, whatever font the machine has.

`Tests/CreatorViewportTests/CubeLabelTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/CubeLabelTests.swift
+++ b/Tests/CreatorViewportTests/CubeLabelTests.swift
@@ -4,12 +4,12 @@
 
 /// The view cube's face names are a texture painted on the faces: the atlas they're rasterized into, and the UVs
 /// that map them onto the cube so each reads upright and unmirrored from outside.
+@MainActor
 struct CubeLabelTests {
-    // MARK: Atlas (rasterized with CoreText, so macOS only)
+    // MARK: Atlas (rasterized through MetalUI's text system: CoreText's on macOS, the portable one elsewhere)
 
-    #if canImport(CoreText)
     @Test func theAtlasHasSixDisjointRectsWithInkInsideEach() throws {
-        let atlas = try #require(CubeLabelAtlas.rasterize())
+        let atlas = try #require(CubeLabelAtlas.rasterize(using: testTextSystem()))
         #expect(atlas.pixels.count == atlas.width * atlas.height)
         let rects = try ViewCubeRegion.faces.map { try #require(CubeLabelAtlas.rect(for: $0)) }
         #expect(rects.count == 6)
@@ -33,7 +33,7 @@
     /// The bitmap's first row is the top of the text (v grows downward, as in a Metal texture) and the text isn't
     /// mirrored: TOP's T has its crossbar at the top, and LEFT's L has its stem on the left.
     @Test func theAtlasTextIsUprightAndUnmirroredInTextureSpace() throws {
-        let atlas = try #require(CubeLabelAtlas.rasterize())
+        let atlas = try #require(CubeLabelAtlas.rasterize(using: testTextSystem()))
         let topRect = try #require(CubeLabelAtlas.rect(for: .top))
         let top = try #require(atlas.inkBox(in: topRect))
         let tWidth = (top.maxX - top.minX) / 3
@@ -47,7 +47,23 @@
         let stem = (left.minY...left.maxY).count { atlas.pixel(x: left.minX + 1, y: $0) > 127 }
         #expect(Double(stem) > 0.8 * Double(left.maxY - left.minY), "the L's stem runs down the left side")
     }
-    #endif
+
+    /// The six names are one size on one baseline, whatever font the platform has: each name's ink ends the same distance
+    /// below the top of its rect (all capitals, so a letter's overshoot is the only difference), and none touches its rect's edge.
+    @Test func allSixNamesShareABaselineAndStayInsideTheirRects() throws {
+        let atlas = try #require(CubeLabelAtlas.rasterize(using: testTextSystem()))
+        var bottoms: [Int] = []
+        for face in ViewCubeRegion.faces {
+            let rect = try #require(CubeLabelAtlas.rect(for: face))
+            let box = try #require(atlas.inkBox(in: rect), "\(face.label ?? "?") has ink")
+            let (xs, ys) = atlas.pixelRanges(of: rect)
+            #expect(box.minX > xs.lowerBound && box.maxX < xs.upperBound - 1, "\(face.label ?? "?") fits across its rect")
+            #expect(box.minY > ys.lowerBound && box.maxY < ys.upperBound - 1, "\(face.label ?? "?") fits down its rect")
+            bottoms.append(box.maxY - ys.lowerBound)
+        }
+        let spread = (bottoms.max() ?? 0) - (bottoms.min() ?? 0)
+        #expect(spread <= 3, "ink bottoms \(bottoms) share a baseline within a few pixels of overshoot")
+    }
 
     // MARK: Mapping onto the cube
 
```

`Tests/CreatorViewportTests/Support/CubeLabelAtlas+Ink.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/Support/CubeLabelAtlas+Ink.swift
+++ b/Tests/CreatorViewportTests/Support/CubeLabelAtlas+Ink.swift
@@ -1,4 +1,3 @@
-#if canImport(CoreText)
 // Test fixture file: reading the cube label atlas's ink back.
 @testable import CreatorViewport
 
@@ -44,4 +43,3 @@
         return box
     }
 }
-#endif
```

- [ ] **Step 2: Run the tests: they fail**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. macOS: `extra argument 'using' in call` (it has the zero-argument `rasterize()`); Linux: `type 'CubeLabelAtlas' has no member 'rasterize'`.

- [ ] **Step 3: Implement**

Delete the CoreText file and take the text system from `CubeLabelFonts`.

Delete `Sources/CreatorViewport/Render/CubeLabelAtlas+CoreText.swift` (`git rm Sources/CreatorViewport/Render/CubeLabelAtlas+CoreText.swift`).

`Sources/CreatorViewport/Render/CubeLabelAtlas+TextSystem.swift` (new):

```swift
import MetalUI

extension CubeLabelAtlas {
    /// The six names, rasterized through `textSystem` (MetalUI's `TextSystem`: CoreText's on macOS, the portable FreeType one over the
    /// installed fonts elsewhere), or `nil` if it draws no ink at all (no usable font).
    ///
    /// All six share one size, the largest at which the widest name fits its rect inside the margin. Each name's ink is centred across
    /// its rect and its capitals centred up and down, so the six share a baseline. The font is the system face at weight 0.3, the
    /// semibold of CoreText's weight scale.
    @MainActor
    static func rasterize(using textSystem: any TextSystem) -> CubeLabelAtlas? {
        let names = ViewCubeRegion.faces.map { $0.label ?? "" }
        let size = fittingFontSize(for: names, using: textSystem)
        guard size.isFinite, size > 0 else { return nil }
        let font = textSystem.resolveFont(semibold(size: size))
        let capHeight = capitalHeight(in: font, using: textSystem)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for (face, name) in zip(ViewCubeRegion.faces, names) {
            guard let rect = rect(for: face), let line = InkLine(name, font: font, using: textSystem) else { continue }
            let rectLeft = Int((Double(rect.u0) * Double(width)).rounded())
            let rectTop = Int((Double(rect.v0) * Double(height)).rounded())
            let rectWidth = Int((Double(rect.u1 - rect.u0) * Double(width)).rounded())
            let rectHeight = Int((Double(rect.v1 - rect.v0) * Double(height)).rounded())
            let originX = rectLeft + (rectWidth - line.inkWidth) / 2 - line.minX
            let baseline = rectTop + (rectHeight + capHeight) / 2
            line.draw(into: &pixels, originX: originX, baselineRow: baseline, width: width, height: height)
        }
        guard pixels.contains(where: { $0 > 0 }) else { return nil }
        return CubeLabelAtlas(width: width, height: height, pixels: pixels)
    }

    /// The largest size at which every name fits its rect inside the margin, so all six share one size.
    @MainActor
    static func fittingFontSize(for names: [String], using textSystem: any TextSystem) -> Double {
        let reference = 100.0
        let font = textSystem.resolveFont(semibold(size: reference))
        let widest = names.compactMap { InkLine($0, font: font, using: textSystem)?.inkWidth }.max() ?? 0
        let capHeight = capitalHeight(in: font, using: textSystem)
        guard widest > 0, capHeight > 0 else { return 0 }
        let roomWidth = Double(cellWidth - 2 * gutter - 2 * margin)
        let roomHeight = Double(cellHeight - 2 * gutter - 2 * margin)
        return reference * min(roomWidth / Double(widest), roomHeight / Double(capHeight))
    }

    /// The system face, semibold (0.3 on CoreText's weight scale), at `size` points.
    static func semibold(size: Double) -> FontDescriptor {
        FontDescriptor(family: nil, size: size, weight: 0.3)
    }

    /// The rows of ink in a capital H of `font`: the height capitals stand at, which centres every name the same way.
    @MainActor
    static func capitalHeight(in font: FontKey, using textSystem: any TextSystem) -> Int {
        guard let line = InkLine("H", font: font, using: textSystem) else { return 0 }
        return line.inkHeight
    }
}

/// One line of text as glyph coverage images placed relative to the pen origin and the baseline.
private struct InkLine {
    struct Piece {
        var image: GlyphImage
        /// Columns from the pen origin to the image's left edge.
        var x: Int
        /// Rows from the baseline down to the image's top edge (negative above it).
        var y: Int
    }

    var pieces: [Piece] = []

    /// The line, or `nil` if none of its glyphs has ink.
    @MainActor
    init?(_ text: String, font: FontKey, using textSystem: any TextSystem) {
        let glyphs = textSystem.placeGlyphs(text, font: font, wrappingAt: nil, origin: (x: 0, y: 0), scaleFactor: 1)
        guard let baseline = glyphs.first?.baselineY else { return nil }
        for glyph in glyphs {
            let image = textSystem.rasterize(glyph.key)
            if image.isEmpty { continue }
            pieces.append(Piece(image: image, x: glyph.pixelX + image.left, y: glyph.baselineY - baseline - image.top))
        }
        if pieces.isEmpty { return nil }
    }

    /// The leftmost column holding any ink, from the pen origin.
    var minX: Int { pieces.map { $0.x + $0.image.firstInkColumn }.min() ?? 0 }
    var maxX: Int { pieces.map { $0.x + $0.image.lastInkColumn + 1 }.max() ?? 0 }
    var inkWidth: Int { maxX - minX }
    var inkHeight: Int {
        let top = pieces.map { $0.y + $0.image.firstInkRow }.min() ?? 0
        let bottom = pieces.map { $0.y + $0.image.lastInkRow + 1 }.max() ?? 0
        return bottom - top
    }

    /// Paints the coverage into a `width` × `height` bitmap whose first row is the top, with the pen origin at column `originX`
    /// and the baseline at row `baselineRow`. Overlapping coverage keeps the larger; what falls outside the bitmap is dropped.
    func draw(into pixels: inout [UInt8], originX: Int, baselineRow: Int, width: Int, height: Int) {
        for piece in pieces {
            for row in 0..<piece.image.height {
                let destinationRow = baselineRow + piece.y + row
                guard destinationRow >= 0, destinationRow < height else { continue }
                for column in 0..<piece.image.width {
                    let destinationColumn = originX + piece.x + column
                    guard destinationColumn >= 0, destinationColumn < width else { continue }
                    let coverage = piece.image.bytes[row * piece.image.width + column]
                    let index = destinationRow * width + destinationColumn
                    pixels[index] = max(pixels[index], coverage)
                }
            }
        }
    }
}

private extension GlyphImage {
    var firstInkColumn: Int { (0..<width).first { column in (0..<height).contains { bytes[$0 * width + column] > 0 } } ?? 0 }
    var lastInkColumn: Int { (0..<width).last { column in (0..<height).contains { bytes[$0 * width + column] > 0 } } ?? 0 }
    var firstInkRow: Int { (0..<height).first { row in (0..<width).contains { bytes[row * width + $0] > 0 } } ?? 0 }
    var lastInkRow: Int { (0..<height).last { row in (0..<width).contains { bytes[row * width + $0] > 0 } } ?? 0 }
}
```

`Sources/CreatorViewport/Render/CubeLabelFonts.swift` (new):

```swift
import MetalUI
#if canImport(MetalUIText)
import MetalUIText
#else
import MetalUIPortableText
import MetalUISystemFonts
#endif

/// Where the view cube's face names get their glyphs: the text system the platform draws the rest of the app with, so the
/// names are in the same system face. CoreText's on macOS; MetalUI's portable text over the installed fonts elsewhere.
@MainActor
enum CubeLabelFonts {
    /// The atlas of the six names, or a blank one (the cube draws, unlabelled) when there is no text system or it draws no ink.
    static func atlas() -> CubeLabelAtlas {
        textSystem().flatMap { CubeLabelAtlas.rasterize(using: $0) } ?? .blank
    }

    private static func textSystem() -> (any TextSystem)? {
        #if canImport(MetalUIText)
        CoreTextTextSystem()
        #else
        (try? SystemFonts.resolver()).map { PortableTextSystem(resolver: $0) }
        #endif
    }
}
```

`Package.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Package.swift
+++ b/Package.swift
@@ -53,7 +53,12 @@
     // the editor's views and the viewport's GPU colours read.
     .target(name: "CreatorStyle", dependencies: [metalUI]),
     // The viewport's model, camera and tools are portable; its Metal renderer is gated with `#if canImport(Metal)`.
-    .target(name: "CreatorViewport", dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
+    // MetalUIPortableText and MetalUISystemFonts only for the view cube's face names off macOS (`CubeLabelFonts`), named on every
+    // platform for the reason above (SG-D).
+    .target(
+        name: "CreatorViewport",
+        dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts]
+    ),
     .target(name: "CreatorEditor", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
     // The in-viewport sketch editor (sketcher spec §8, S5): `SketchEditorModel`, its tools and its views. Graph-free:
     // the app shell turns its commits into graph commands. CreatorStyle for the theme's colours.
```

`Sources/CreatorViewport/Render/CubeLabelAtlas.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/CubeLabelAtlas.swift
+++ b/Sources/CreatorViewport/Render/CubeLabelAtlas.swift
@@ -1,7 +1,8 @@
 /// The view cube's six face names, rasterized once into a single-channel coverage bitmap (spec §6.3: "Faces are
 /// labelled TOP, BOTTOM, FRONT, BACK, LEFT and RIGHT"). The renderer uploads it to an `r8Unorm` texture with
 /// mipmaps, and the cube's fragment shader paints it on the faces, so the names tilt and turn with the cube.
-/// Rasterizing it needs CoreText (`CubeLabelAtlas+CoreText.swift`, macOS); the layout here is portable.
+/// `CubeLabelAtlas+TextSystem.swift` rasterizes it through MetalUI's `TextSystem` (CoreText's on macOS, the portable one
+/// elsewhere); the layout here is portable.
 ///
 /// The names are stacked one per row in `ViewCubeRegion.faces` order. Each row is a cell inset by a gutter, so
 /// mip levels don't bleed one name into the next, and each name is centred in its rect in the system font,
```

`Sources/CreatorViewport/Render/ViewCubeResources.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/ViewCubeResources.swift
+++ b/Sources/CreatorViewport/Render/ViewCubeResources.swift
@@ -30,7 +30,7 @@
     /// `commandBuffer`, so call it before the pass that samples it begins.
     func labelTexture(_ commandBuffer: any MTLCommandBuffer) -> (any MTLTexture)? {
         if let labels { return labels }
-        let atlas = CubeLabelAtlas.rasterize() ?? .blank
+        let atlas = CubeLabelFonts.atlas()
         labels = atlas.makeTexture(device: device, commandBuffer: commandBuffer)
         return labels
     }
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 314 tests in 42 suites passed` (baseline 304/41 + 10 tests, + 1 suite).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 272 tests in 35 suites passed` (baseline 259/34 + 13 tests, + 1 suite).

`OffscreenRenderTests.theFrontLabelIsPaintedOnTheFrontFace` (macOS only) still passes: the Metal cube's label is now rasterized through `CoreTextTextSystem`. Look at it once on a Mac (human check XP-26).
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Package.swift \
  Sources/CreatorViewport/Render/CubeLabelAtlas+CoreText.swift \
  Sources/CreatorViewport/Render/CubeLabelAtlas+TextSystem.swift \
  Sources/CreatorViewport/Render/CubeLabelAtlas.swift \
  Sources/CreatorViewport/Render/CubeLabelFonts.swift \
  Sources/CreatorViewport/Render/ViewCubeResources.swift \
  Tests/CreatorViewportTests/CubeLabelTests.swift \
  Tests/CreatorViewportTests/Support/CubeLabelAtlas+Ink.swift
git commit -m "viewport: cube face names rasterized through MetalUI's TextSystem, on every platform"
```


### Task 4: The HLSL shaders, compiled at build time by a pinned SDL_shadercross, and the checks that keep them honest

The viewport's SDL shaders are 16 HLSL stage files and a shared header, one pair per pipeline: `background`, `mesh` (opaque solids and ghosts), `field_mesh`, `fill`, `line`, `grid`, and the ID pass's own `id_mesh` and `id_line` (they declare only the vertex outputs they read, because Direct3D 12 links stages by register, MetalUI rule `GA-Q`). They are line-for-line the Metal shaders' maths (`ViewportShaders`, `LineShaders`, `FieldShaders`) in HLSL: `mix` is `lerp`, `fract` is `frac`, `discard_fragment()` is `discard`, `[[front_facing]]` is `SV_IsFrontFace`; `fwidth`, `saturate` and `pow` are the same. Differences that are not syntax: vertex data comes from `StructuredBuffer`s read by `SV_VertexID`/`SV_InstanceID`; the face flags are read in the vertex stage and reach the fragment stage as a flat interpolant; a ghost is `ghost == 1` in the same `mesh` fragment; and every vector in a struct is a `float4`/`uint4` so the layout is the Swift one.

**User decision U1(b), decided 2026-10-21: the HLSL is compiled at build time, in CI and by every developer on Linux and Windows. Nothing compiled is checked in.** `scripts/build-shaders.sh` (Linux) and `scripts/build-shaders.ps1` (Windows) run **MetalUI's `MetalUICompileShaders`** (MetalUI S12, `d995f4b4`: HLSL to SPIR-V, then SPIR-V to MSL, DXIL and a reflection JSON each, and `SOURCE.sha256`), built from the `../MetalUI` checkout by `swift run --package-path ../MetalUI --scratch-path <ours> MetalUICompileShaders --shadercross <the pinned tool> --source Shaders/viewport --out Shaders/viewport/compiled`, into `Shaders/viewport/compiled`, which is **git-ignored**. The scripts add what the tool leaves to its caller: the pin check, `INCLUDES.sha256` for the shared header, skipping a current directory, and removing a half-built one. `scripts/linux-test.sh` and the CI jobs run the script before `swift build`; macOS runs nothing (U6(a): Metal only). MetalUI offers no build-tool plugin (ruling `BS-D`), and its command plugin (`swift package --allow-writing-to-package-directory compile-shaders`) is the same tool behind a SwiftPM verb, so **`swift build` alone does not compile shaders**; a checkout that skipped the script finds no shaders, and says so (below).

**The pinned tool.** `scripts/shadercross.env` holds the one pin: `libsdl-org/SDL_shadercross` commit `1ff05bec573988a98ef9e0260b4da44f512b8367`, the commit MetalUI `docs/packaging.md` §4a documents. The repository has no release and no tag (checked 2026-10-21) and MetalUI publishes no binary (ruling `BS-H`), so a full commit is the only pin there is. Linux builds it in a `shadercross` stage of `scripts/linux/Dockerfile` with MetalUI's recipe (the four submodules the commit fixes, among them libsdl-org's DirectXShaderCompiler fork on branch `1.8.2502-SDL`, `-DSDLSHADERCROSS_VENDORED=ON`, clang), natively on x86_64 and aarch64, and the test image copies `/opt/shadercross` from it as it copies `/opt/occt` from xp-2's stage. Windows builds it with `scripts/install-shadercross.ps1` (Microsoft's prebuilt DirectXShaderCompiler `v1.9.2602`, pinned by URL and SHA-256 in the commit's own cmake script), cached by `actions/cache/restore` and `save`.

**What guards what, with no checked-in hashes.** `ShaderSourceTests` has two kinds of check. On every platform it computes each HLSL struct's size and compares it with the Swift struct's `MemoryLayout.stride`, so a struct that drifted fails on macOS too. On Linux and Windows only it checks that **the build produced every expected compiled shader** in the directory the renderer reads at run time (MetalUI's lookup order: `MetalUIAppShaders` beside the executable if one is there, else the source tree's `Shaders/viewport/compiled`; task 5's `ViewportShaderDirectoryTests` ask MetalUI's own `SDLGPUShaderLibrary` the same question), that the build is **current** (the `SOURCE.sha256` MetalUI's tool wrote, and the `INCLUDES.sha256` the script wrote, match the sources now: an `.hlsl` or `.hlsli` edited after the last build fails with "run scripts/build-shaders.sh") and that every message names the script. **Freshness decision (2026-10-22): `MetalUICompileShaders` writes `SOURCE.sha256`, so the check stays on it**; MetalUI's marker lists only the `NAME.<vert|frag|comp>.hlsl` stage sources, so the header keeps its own `INCLUDES.sha256`. `ViewportShaderDirectoryTests` loads each stage for the platform's driver, and a new test there pins that **`--self-test`'s check fails with a plain message when the directory is missing** (`ViewportShaderCheck`, task 8). `ShaderToolchainTests` pins that the pin is written the same everywhere (the env file, the Dockerfile, the workflow, both scripts' messages), that both scripts compile through `MetalUICompileShaders` (and not the deleted `compile-app-shaders.py`), and that the script stops, naming the tool and its commit, when shadercross is missing. (This is user decisions U1(b) and U2(a).)

**Files:**
- Create: `Shaders/viewport/background.frag.hlsl`
- Create: `Shaders/viewport/background.vert.hlsl`
- Create: `Shaders/viewport/common.hlsli`
- Create: `Shaders/viewport/field_mesh.frag.hlsl`
- Create: `Shaders/viewport/field_mesh.vert.hlsl`
- Create: `Shaders/viewport/fill.frag.hlsl`
- Create: `Shaders/viewport/fill.vert.hlsl`
- Create: `Shaders/viewport/grid.frag.hlsl`
- Create: `Shaders/viewport/grid.vert.hlsl`
- Create: `Shaders/viewport/id_line.frag.hlsl`
- Create: `Shaders/viewport/id_line.vert.hlsl`
- Create: `Shaders/viewport/id_mesh.frag.hlsl`
- Create: `Shaders/viewport/id_mesh.vert.hlsl`
- Create: `Shaders/viewport/line.frag.hlsl`
- Create: `Shaders/viewport/line.vert.hlsl`
- Create: `Shaders/viewport/mesh.frag.hlsl`
- Create: `Shaders/viewport/mesh.vert.hlsl`
- Create: `Tests/CreatorViewportTests/ShaderSourceTests.swift`
- Create: `scripts/shadercross.env`
- Create: `scripts/build-shaders.sh`
- Create: `scripts/build-shaders.ps1`
- Create: `scripts/install-shadercross.ps1`
- Create: `Tests/CreatorViewportTests/ShaderToolchainTests.swift`
- Modify: `.gitattributes` (master has it: add `Shaders/**`)
- Modify: `.gitignore`
- Modify: `Package.swift`
- Modify: `scripts/linux/Dockerfile` (the `shadercross` stage and its copy into the final stage)
- Modify: `scripts/linux-test.sh` (`SHADERCROSS_IMAGE`, `SHADERCROSS_JOBS`; run `build-shaders.sh` before `swift build`, `swift test`, the smoke step and packaging)
- Modify: `.github/workflows/xp.yml` (the shadercross steps on the Linux and Windows jobs)

**Generated and never committed:** `Shaders/viewport/compiled/` holds, for each of the 16 stage files, `NAME.{spv,dxil,msl,json}` (`mesh.vert.spv` and so on: MetalUI's tool names every output after the stage file), plus `SOURCE.sha256` (written by `MetalUICompileShaders`) and `INCLUDES.sha256` (written by the script): 66 files, made by `scripts/build-shaders.sh` in step 4. It is in `.gitignore`, so `git add` of the task's files never includes it.

**Interfaces:**
- Consumes: `CreatorGraph`'s `SHA256` (a test-target dependency; `@testable import`), the Swift structs `FrameUniforms`, `MeshVertex`, `DrawUniforms`, `ShadeUniforms`, `LineInstance`, `LineUniforms`, `GridUniforms`, `FillVertex`, `ClipUniforms`, `FieldRampUniforms`.
- Consumes, from MetalUI `5f03ab7b`: the executable product `MetalUICompileShaders` (`--source DIR --out DIR --shadercross PATH`; exit 0, 1 for a failed compile, 2 for a bad command line) and its `SOURCE.sha256` format (`<sha256>  <file>` per stage source, sorted bytewise, LF).
- Produces: `Shaders/viewport/NAME.vert.hlsl` and `NAME.frag.hlsl` for `background`, `mesh`, `field_mesh`, `fill`, `line`, `grid`, `id_mesh`, `id_line`; the binding convention every later task relies on: vertex storage buffers `register(tN, space0)`, vertex uniforms `register(bN, space1)`, fragment samplers `register(tN/sN, space2)`, fragment uniforms `register(bN, space3)`, N in declaration order; `scripts/build-shaders.sh` / `.ps1` (exit 0 and `Shaders/viewport/compiled` with 66 files; 69 and a message naming `SDL_shadercross` and its pinned commit when it is missing or another build; 1 when a shader fails, the directory removed; 2 when MetalUI is not beside the repository); `METALUI_TOOLS_SCRATCH` (where MetalUI's tool is built; default `.build/metalui-tools`); `scripts/shadercross.env` (`SHADERCROSS_REPOSITORY`, `SHADERCROSS_COMMIT`); `compile_shaders`, `SHADERCROSS_IMAGE` and `SHADERCROSS_JOBS` in `scripts/linux-test.sh`; the Dockerfile's `shadercross` stage and `/opt/shadercross` in the test image; `ShaderSourceTests.directory`, `stageSources` and `runtimeDirectory`, used by task 5's tests.

- [ ] **Step 1: Write the failing tests**

The tests read `Shaders/viewport` from the test file's own path, so they need no GPU and no shadercross: they look at what the build left, and at the sources.

`Tests/CreatorViewportTests/ShaderSourceTests.swift` (new):

```swift
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorViewport

/// The HLSL shaders in `Shaders/viewport` and what the build made of them. The HLSL structs the shaders read have the sizes of the
/// Swift structs that fill them (every platform: `GPUDataTests` pins the Swift side, this pins the HLSL side to the same numbers).
/// On Linux and Windows the compiled shaders are a build product (`scripts/build-shaders.sh`, user decision U1(b)), so the tests also
/// check that the build made every one of them where the renderer looks and that it is current. Nothing compiled is checked in.
struct ShaderSourceTests {
    /// `Shaders/viewport`, found from this file: `Tests/CreatorViewportTests/ShaderSourceTests.swift` is three directories below the root.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Shaders/viewport")

    static func hexDigest(of url: URL) throws -> String {
        SHA256.hash(try Data(contentsOf: url)).map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    static var stageSources: [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".vert.hlsl") || $0.hasSuffix(".frag.hlsl") }.sorted().map { directory.appending(path: $0) }
    }

    // MARK: The HLSL structs have the Swift structs' sizes (every platform)

    /// The size in bytes of each HLSL type the header uses. There is no float3: it packs differently in a constant buffer, a
    /// structured buffer and Swift, which is why the header spells every vector as a float4.
    static let typeSizes: [String: Int] = ["float4": 16, "uint4": 16, "float2": 8, "uint2": 8, "float": 4, "uint": 4]

    /// `struct Name { type member; ... };` blocks of the header, as member types in order (array members repeat their element).
    static func structs() throws -> [String: [(type: String, count: Int)]] {
        let text = try String(contentsOf: directory.appending(path: "common.hlsli"), encoding: .utf8)
        var result: [String: [(type: String, count: Int)]] = [:]
        var current: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {   // "\r\n" too: a Windows checkout
            // A `//` comment, whole-line or trailing, is no part of the declaration.
            let code = rawLine.components(separatedBy: "//")[0]
            let line = code.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("struct "), line.hasSuffix("{") {
                current = line.dropFirst("struct ".count).dropLast(1).trimmingCharacters(in: .whitespaces)
                result[current ?? ""] = []
            } else if line.hasPrefix("}") {
                current = nil
            } else if let name = current, line.hasSuffix(";") {
                let words = line.dropLast().split(separator: " ")
                guard words.count == 2 else { continue }
                var count = 1
                if let open = words[1].firstIndex(of: "["), let close = words[1].firstIndex(of: "]") {
                    count = Int(words[1][words[1].index(after: open)..<close]) ?? 1
                }
                result[name, default: []].append((String(words[0]), count))
            }
        }
        return result
    }

    /// The struct's size: members in order, each aligned to its own size (at most 16), the whole rounded up to 16.
    static func size(of members: [(type: String, count: Int)]) -> Int? {
        var offset = 0
        for member in members {
            guard let size = typeSizes[member.type] else { return nil }
            let alignment = min(size, 16)
            offset = (offset + alignment - 1) / alignment * alignment + size * member.count
        }
        return (offset + 15) / 16 * 16
    }

    @Test func theHeadersStructsHaveTheSizesOfTheirSwiftTwins() throws {
        let sizes = try Self.structs().compactMapValues { Self.size(of: $0) }
        let swift: [String: Int] = [
            "FrameUniforms": MemoryLayout<FrameUniforms>.stride, "MeshVertex": MemoryLayout<MeshVertex>.stride,
            "DrawUniforms": MemoryLayout<DrawUniforms>.stride, "ShadeUniforms": MemoryLayout<ShadeUniforms>.stride,
            "LineInstance": MemoryLayout<LineInstance>.stride, "LineUniforms": MemoryLayout<LineUniforms>.stride,
            "GridUniforms": MemoryLayout<GridUniforms>.stride, "FillVertex": MemoryLayout<FillVertex>.stride,
            "ClipUniforms": MemoryLayout<ClipUniforms>.stride, "FieldRampUniforms": MemoryLayout<FieldRampUniforms>.stride,
        ]
        #expect(sizes.count == (try Self.structs().count), "every struct in the header is made of float4, uint4, float2, float and uint")
        for (name, expected) in swift {
            #expect(sizes[name] == expected, "\(name): HLSL \(sizes[name].map(String.init) ?? "missing") against Swift \(expected)")
        }
        #expect(Set(sizes.keys) == Set(swift.keys), "a struct added to the header needs its Swift twin pinned here")
    }

    #if os(Linux) || os(Windows)
    // MARK: The build made the shaders (Linux and Windows)

    /// Where a running app looks for its compiled shaders, in MetalUI's order (`SDLGPUShaderLibrary.locate`, `docs/packaging.md` section
    /// 4a): `MetalUIAppShaders` beside the executable, then the source tree's `Shaders/viewport/compiled`. The first that holds the
    /// `SOURCE.sha256` the build writes is the one. (Task 5's `ViewportShaderDirectoryTests` ask MetalUI's own lookup the same.)
    static var runtimeDirectory: URL? {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments.first ?? ".")
        let candidates = [executable.deletingLastPathComponent().appending(path: "MetalUIAppShaders"), directory.appending(path: "compiled")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "SOURCE.sha256").path) }
    }

    /// What a missing or stale result of the build tells the person who sees it.
    static let remedy = "Run scripts/build-shaders.sh (scripts/build-shaders.ps1 on Windows; scripts/linux-test.sh does it for you): the shaders are compiled at build time by the pinned SDL_shadercross, scripts/shadercross.env."

    /// `<sha256>  <name>` lines of a file the build wrote (`SOURCE.sha256` by MetalUI's `MetalUICompileShaders`, `INCLUDES.sha256` by
    /// `scripts/build-shaders.sh`), as a dictionary of name to digest.
    static func hashes(in file: String, of directory: URL) throws -> [String: String] {
        let text = try String(contentsOf: directory.appending(path: file), encoding: .utf8)
        var table: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2 { table[String(parts[1])] = String(parts[0]) }
        }
        return table
    }

    /// The build produced every stage's four files where the renderer reads them, and the build is current: the `SOURCE.sha256` MetalUI's
    /// tool wrote and the `INCLUDES.sha256` the script wrote match the sources and the header now (the freshness check of user decision
    /// U1(b)). A source edited after the last build fails here and says so.
    @Test func theBuildCompiledEveryStageIntoTheDirectoryTheRendererReads() throws {
        let sources = Self.stageSources
        #expect(sources.count >= 16, "the viewport's vertex and fragment stages are found")
        let compiled = try #require(Self.runtimeDirectory, "no compiled shader directory beside the executable or in the source tree. \(Self.remedy)")
        for source in sources {
            let stem = String(source.lastPathComponent.dropLast(".hlsl".count))
            for blob in ["spv", "dxil", "msl", "json"] {
                let size = (try? Data(contentsOf: compiled.appending(path: "\(stem).\(blob)")).count) ?? 0
                #expect(size > 0, "\(stem).\(blob) is missing or empty in \(compiled.path). \(Self.remedy)")
            }
        }
        let table = try Self.hashes(in: "SOURCE.sha256", of: compiled)
        #expect(Set(table.keys) == Set(sources.map(\.lastPathComponent)), "SOURCE.sha256 lists exactly the stage sources. \(Self.remedy)")
        for source in sources {
            #expect(table[source.lastPathComponent] == (try Self.hexDigest(of: source)),
                    "\(source.lastPathComponent) changed after the last build. \(Self.remedy)")
        }
        let includes = try Self.hashes(in: "INCLUDES.sha256", of: compiled)
        let headers = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".hlsli") }
        #expect(Set(includes.keys) == Set(headers), "INCLUDES.sha256 lists exactly the shared headers. \(Self.remedy)")
        for header in headers {
            #expect(includes[header] == (try Self.hexDigest(of: Self.directory.appending(path: header))),
                    "\(header) changed after the last build. \(Self.remedy)")
        }
    }
    #endif
}
```

`Tests/CreatorViewportTests/ShaderToolchainTests.swift` (new):

```swift
import Foundation
import Testing

/// The shader compiler is pinned once, in `scripts/shadercross.env`, and written again in the Dockerfile, the workflow and the
/// scripts' messages. This pins that they agree, and that the build script stops with a plain message, naming the tool and its pinned
/// commit, when it cannot find it. Read from the source tree (`#filePath`), so macOS runs them too.
struct ShaderToolchainTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// A text file of the repository with Windows line endings read as Unix ones (a CRLF checkout must not change the answer).
    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8).replacing("\r\n", with: "\n")
    }

    static func pin() throws -> (repository: String, commit: String) {
        let env = try text("scripts/shadercross.env")
        let commit = try #require(env.firstMatch(of: /(?m)^SHADERCROSS_COMMIT=([0-9a-f]{40})$/)?.1, "scripts/shadercross.env names a 40-digit commit")
        let repository = try #require(env.firstMatch(of: /(?m)^SHADERCROSS_REPOSITORY=(\S+)$/)?.1, "scripts/shadercross.env names the repository")
        return (String(repository), String(commit))
    }

    @Test func thePinIsWrittenOnceAndTheScriptsCompileThroughMetalUIsTool() throws {
        let pin = try Self.pin()
        #expect(pin.repository == "https://github.com/libsdl-org/SDL_shadercross")
        let dockerfile = try Self.text("scripts/linux/Dockerfile")
        let docker = try #require(dockerfile.firstMatch(of: /(?m)^ARG SHADERCROSS_COMMIT=([0-9a-f]{40})$/)?.1, "the Dockerfile's shadercross stage has the ARG")
        #expect(String(docker) == pin.commit, "scripts/linux/Dockerfile's SHADERCROSS_COMMIT differs from scripts/shadercross.env")
        let workflow = try Self.text(".github/workflows/xp.yml")
        #expect(workflow.contains("scripts/shadercross.env"), "the workflow keys the Windows cache on the env file, not on a copy of the commit")
        #expect(!workflow.contains("SHADERCROSS_COMMIT:"), "the workflow reads the pin from scripts/shadercross.env and does not repeat it")
        let ps = try Self.text("scripts/install-shadercross.ps1")
        #expect(ps.contains("shadercross.env"), "install-shadercross.ps1 reads the pin from the env file")
        // Both scripts compile through MetalUI's own tool (MetalUI S12, gap XP-G20), built with a scratch path outside ../MetalUI.
        for script in ["scripts/build-shaders.sh", "scripts/build-shaders.ps1"] {
            let text = try Self.text(script)
            #expect(text.contains("MetalUICompileShaders"), "\(script) runs MetalUI's MetalUICompileShaders")
            #expect(text.contains("--scratch-path"), "\(script) builds the tool outside ../MetalUI")
            #expect(!text.contains("compile-app-shaders.py"), "\(script) does not name MetalUI's deleted python script")
        }
    }

    /// The scripts' plain failure: no shadercross, exit 69, a line that names the tool, the repository and the pinned commit.
    #if !os(Windows)
    @Test func aMissingShadercrossStopsTheBuildNamingTheToolAndItsPin() throws {
        let pin = try Self.pin()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [Self.root.appending(path: "scripts/build-shaders.sh").path]
        process.environment = ["SHADERCROSS": "/nonexistent/shadercross", "PATH": "/usr/bin:/bin"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 69)
        #expect(message.contains("SDL_shadercross"), "the message names the tool: \(message)")
        #expect(message.contains(pin.commit), "the message names the pinned commit: \(message)")
        #expect(message.contains("scripts/shadercross.env"), "the message says where the pin is written: \(message)")
    }
    #endif
}
```

Both files are portable: macOS runs `ShaderToolchainTests` and the struct-size test (the Linux-and-Windows test looks for a build product macOS never makes, so it is compiled out there).

- [ ] **Step 2: Run the tests: they fail**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. `Unable to find module dependency: 'CreatorGraph'` in `ShaderSourceTests.swift` (the test target does not depend on it yet).

- [ ] **Step 3: Implement**

`Package.swift` gives `CreatorViewportTests` the dependency. The shaders, the build scripts, the pin, the Docker stage, the `linux-test.sh` step and the CI steps follow. **Nothing compiled is added.**

`.gitattributes` (change against master; apply with `git apply` or by hand). Master pins `scripts/**` (so `scripts/shadercross.env` and both build scripts) to LF already; the shader sources join them:

```diff
--- a/.gitattributes
+++ b/.gitattributes
@@ -8,3 +8,7 @@
 CLAUDE.md text eol=lf
 # The icon is binary: the rule above would rewrite its bytes.
 packaging/**/*.png binary
+# The viewport's shader sources are hashed: the build writes their SHA-256s to SOURCE.sha256 and INCLUDES.sha256 and ShaderSourceTests
+# compares them (MetalUI docs/packaging.md section 4a, rule GA-Q: a CRLF checkout on Windows changes the hashes). The compiled files
+# are not in git at all (.gitignore).
+Shaders/** text eol=lf
```

`.gitignore` (change; apply with `git apply` or by hand):

```diff
--- a/.gitignore
+++ b/.gitignore
@@ -13,3 +13,7 @@
 
 # scripts/package-app.sh writes the packaged app here.
 /dist
+
+# The viewport's SDL_GPU shaders are compiled at build time by scripts/build-shaders.sh (.ps1 on Windows) from Shaders/viewport/*.hlsl;
+# nothing compiled is checked in (plan xp-3, user decision U1(b)).
+/Shaders/viewport/compiled
```

`Shaders/viewport/background.frag.hlsl` (new):

```hlsl
cbuffer Colors : register(b0, space3) {
    float4 top;
    float4 bottom;
};

float4 main(float4 position : SV_Position, float v : TEXCOORD0) : SV_Target0 {
    return float4(lerp(top.rgb, bottom.rgb, saturate(v)), 1.0);
}
```

`Shaders/viewport/background.vert.hlsl` (new):

```hlsl
// The background gradient: one oversized triangle drawn with three vertices, `v` running 0 at the top to 1 at the bottom.
struct Out {
    float4 position : SV_Position;
    float v : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 p = float2(vid == 1u ? 3.0 : -1.0, vid == 2u ? 3.0 : -1.0);
    Out output;
    output.position = float4(p, 0.0, 1.0);
    output.v = (1.0 - p.y) * 0.5;
    return output;
}
```

`Shaders/viewport/common.hlsli` (new):

```hlsl
// The viewport's shared HLSL declarations (cross-platform spec section 4, plan xp-3). Mirrors of the Swift structs in
// Sources/CreatorViewport/Render; GPUDataTests pins their strides. Every member is a float4 or uint4 (or a scalar after
// them), never a float3: that is the same layout in a constant buffer, a structured buffer and Swift's SIMD types.
//
// SDL_GPU's binding spaces (SDL_CreateGPUShader): a vertex stage reads storage buffers in space0 and uniforms in space1; a
// fragment stage reads samplers in space2 and uniforms in space3.

/// The camera. `viewProjection` and `view` are column-major as `Matrix4`: four columns, each a float4.
struct FrameUniforms {
    float4 viewProjection[4];
    float4 view[4];
    float4 eye;
    float4 forward;
    /// x, y: the render target's size in pixels; z: asfloat(isOrthographic); w: unused.
    float4 tail;
};

float4 mulColumns(float4 m[4], float4 v) {
    return m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3] * v.w;
}

struct MeshVertex {
    float4 position;
    float4 normal;
    uint4 face;
};

/// pickBase: PickID.base for the solid's faces (ID pass). ghost: 0 opaque, 1 the blended ghost.
struct DrawUniforms {
    uint pickBase;
    uint ghost;
    uint faceCount;
    float padding;
};

struct ShadeUniforms {
    float4 light;
    float4 dark;
    float4 hover;
    float4 selection;
    float4 warning;
};

struct LineInstance {
    float4 a;
    float4 b;
    float4 color;
    float width;
    uint id;
    uint padding0;
    uint padding1;
};

struct LineUniforms {
    float widthOverride;
    float depthBias;
    float padding0;
    float padding1;
};

struct GridUniforms {
    float4 centerExtentSpacing; // x, y: center; z: extent; w: spacing
    float4 minorColor;
    float4 majorColor;
};

struct FillVertex {
    float4 position;
    float4 color;
};

/// The cut view's plane: a point is cut away when dot(plane.xyz, p) + plane.w > 0. `enabled` is 0 for no cut.
struct ClipUniforms {
    float4 plane;
    uint4 enabled;
};

bool clipped(ClipUniforms clip, float3 world) {
    return clip.enabled.x != 0u && dot(clip.plane.xyz, world) + clip.plane.w > 0.0;
}

struct FieldRampUniforms {
    float4 low;
    float4 mid;
    float4 high;
    float4 range;
};

/// FieldRamp.color(at:) in Swift: low to mid up to the middle value, mid to high above it, held beyond the ends.
float3 fieldRamp(FieldRampUniforms ramp, float value) {
    if (value <= ramp.range.y) {
        float span = ramp.range.y - ramp.range.x;
        float t = span > 0.0 ? saturate((value - ramp.range.x) / span) : 1.0;
        return lerp(ramp.low.rgb, ramp.mid.rgb, t);
    }
    float span = ramp.range.z - ramp.range.y;
    float t = span > 0.0 ? saturate((value - ramp.range.y) / span) : 1.0;
    return lerp(ramp.mid.rgb, ramp.high.rgb, t);
}
```

`Shaders/viewport/field_mesh.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Shade : register(b0, space3) { ShadeUniforms shade; };
cbuffer Ramp : register(b1, space3) { FieldRampUniforms ramp; };
cbuffer Clip : register(b2, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
    float value : TEXCOORD3;
};

float4 main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float3 n = normalize(input.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float lit = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = fieldRamp(ramp, input.value) * (0.55 + 0.45 * lit) + rim * 0.06;
    uint flags = input.flags;
    if ((flags & 2u) != 0u) {
        color = lerp(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = lerp(color, shade.hover.rgb, 0.18);
    }
    return float4(saturate(color), 1.0);
}
```

`Shaders/viewport/field_mesh.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The surface coloured by a value per corner (fields spec section 6): `mesh.vert` plus the value.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
StructuredBuffer<uint> faceFlags : register(t1, space0);
StructuredBuffer<float> values : register(t2, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
    float value : TEXCOORD3;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.viewNormal = mulColumns(frame.view, float4(v.normal.xyz, 0.0)).xyz;
    output.world = v.position.xyz;
    output.flags = v.face.x < draw.faceCount ? faceFlags[v.face.x] : 0u;
    output.value = values[vid];
    return output;
}
```

`Shaders/viewport/fill.frag.hlsl` (new):

```hlsl
struct In {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
};

float4 main(In input) : SV_Target0 {
    return float4(input.color.rgb * input.color.a, input.color.a);
}
```

`Shaders/viewport/fill.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// Overlay fills (a sketch region's faint colour, under the overlay's lines).
StructuredBuffer<FillVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };

struct Out {
    float4 position : SV_Position;
    nointerpolation float4 color : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    FillVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.color = v.color;
    return output;
}
```

`Shaders/viewport/grid.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Grid : register(b0, space3) { GridUniforms grid; };

float4 main(float4 position : SV_Position, float2 world : TEXCOORD0) : SV_Target0 {
    float2 center = grid.centerExtentSpacing.xy;
    float extent = grid.centerExtentSpacing.z;
    float spacing = grid.centerExtentSpacing.w;
    float2 minorCoord = world / spacing;
    float2 minorCell = abs(frac(minorCoord - 0.5) - 0.5) / max(fwidth(minorCoord), float2(1e-6, 1e-6));
    float minor = 1.0 - saturate(min(minorCell.x, minorCell.y));
    float2 majorCoord = world / (spacing * 10.0);
    float2 majorCell = abs(frac(majorCoord - 0.5) - 0.5) / max(fwidth(majorCoord), float2(1e-6, 1e-6));
    float major = 1.0 - saturate(min(majorCell.x, majorCell.y));
    float fade = 1.0 - saturate(length(world - center) / (extent * 0.5));
    float alpha = max(minor * 0.35, major * 0.6) * fade;
    float3 color = lerp(grid.minorColor.rgb, grid.majorColor.rgb, major);
    return float4(color * alpha, alpha);
}
```

`Shaders/viewport/grid.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The ground grid: a square on z = 0, four vertices as a strip.
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Grid : register(b1, space1) { GridUniforms grid; };

struct Out {
    float4 position : SV_Position;
    float2 world : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    float2 world = grid.centerExtentSpacing.xy + corner * grid.centerExtentSpacing.z * 0.5;
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(world, 0.0, 1.0));
    output.world = world;
    return output;
}
```

`Shaders/viewport/id_line.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation uint id : TEXCOORD2;
    float3 world : TEXCOORD3;
};

uint main(In input) : SV_Target0 {
    if (clipped(clip, input.world) || abs(input.across) > input.halfWidth) {
        discard;
    }
    return input.id;
}
```

`Shaders/viewport/id_line.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The ID pass's lines: `line.vert` with the edge's pick ID in place of its colour. Always the whole target.
StructuredBuffer<LineInstance> lines : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Style : register(b1, space1) { LineUniforms style; };

struct Out {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation uint id : TEXCOORD2;
    float3 world : TEXCOORD3;
};

Out main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    LineInstance instance = lines[iid];
    float3 a = instance.a.xyz;
    float3 b = instance.b.xyz;
    bool isOrthographic = asuint(frame.tail.z) != 0u;
    if (style.depthBias > 0.0) {
        float3 towardA = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - a);
        float3 towardB = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - b);
        a += towardA * style.depthBias;
        b += towardB * style.depthBias;
    }
    float4 clipA = mulColumns(frame.viewProjection, float4(a, 1.0));
    float4 clipB = mulColumns(frame.viewProjection, float4(b, 1.0));
    Out output;
    output.id = instance.id;
    output.world = float3(0.0, 0.0, 0.0);
    float width = style.widthOverride > 0.0 ? style.widthOverride : instance.width;
    output.halfWidth = width * 0.5;
    if (clipA.w <= 1e-6 || clipB.w <= 1e-6) {
        output.position = float4(0.0, 0.0, 2.0, 1.0);
        output.across = 0.0;
        return output;
    }
    float2 halfViewport = 0.5 * frame.tail.xy;
    float2 screenA = clipA.xy / clipA.w * halfViewport;
    float2 screenB = clipB.xy / clipB.w * halfViewport;
    float2 delta = screenB - screenA;
    float segmentLength = length(delta);
    float2 along = segmentLength > 1e-4 ? delta / segmentLength : float2(1.0, 0.0);
    float2 normal = float2(-along.y, along.x);
    bool atB = (vid & 1u) != 0u;
    float side = (vid & 2u) != 0u ? 1.0 : -1.0;
    float reach = output.halfWidth + 1.0;
    float2 offset = normal * side * reach + along * (atB ? 1.0 : -1.0) * output.halfWidth;
    float4 clip = atB ? clipB : clipA;
    output.position = float4(clip.xy + offset / halfViewport * clip.w, clip.z, clip.w);
    output.across = side * reach;
    output.world = atB ? b : a;
    return output;
}
```

`Shaders/viewport/id_mesh.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    nointerpolation uint id : TEXCOORD1;
};

uint main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    return input.id;
}
```

`Shaders/viewport/id_mesh.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The ID pass's solids: the pick ID of the corner's face (`pickBase | face`) reaches the fragment stage as a flat uint.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 world : TEXCOORD0;
    nointerpolation uint id : TEXCOORD1;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.world = v.position.xyz;
    output.id = draw.pickBase | v.face.x;
    return output;
}
```

`Shaders/viewport/line.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Clip : register(b0, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation float4 color : TEXCOORD2;
    float3 world : TEXCOORD3;
};

float4 main(In input) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float coverage = saturate(input.halfWidth + 0.5 - abs(input.across));
    float alpha = input.color.a * coverage;
    return float4(input.color.rgb * alpha, alpha);
}
```

`Shaders/viewport/line.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// Lines (B-rep edges, handles, the triad, the overlay): one instanced quad per segment, four vertices as a strip, each
// instance read from a storage buffer. `frame.tail.xy` is the size in pixels of the viewport the line is drawn in, which the
// line's width is measured against.
StructuredBuffer<LineInstance> lines : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Style : register(b1, space1) { LineUniforms style; };

struct Out {
    float4 position : SV_Position;
    float across : TEXCOORD0;
    nointerpolation float halfWidth : TEXCOORD1;
    nointerpolation float4 color : TEXCOORD2;
    float3 world : TEXCOORD3;
};

Out main(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    LineInstance instance = lines[iid];
    float3 a = instance.a.xyz;
    float3 b = instance.b.xyz;
    bool isOrthographic = asuint(frame.tail.z) != 0u;
    if (style.depthBias > 0.0) {
        float3 towardA = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - a);
        float3 towardB = isOrthographic ? -frame.forward.xyz : normalize(frame.eye.xyz - b);
        a += towardA * style.depthBias;
        b += towardB * style.depthBias;
    }
    float4 clipA = mulColumns(frame.viewProjection, float4(a, 1.0));
    float4 clipB = mulColumns(frame.viewProjection, float4(b, 1.0));
    Out output;
    output.color = instance.color;
    output.world = float3(0.0, 0.0, 0.0);
    float width = style.widthOverride > 0.0 ? style.widthOverride : instance.width;
    output.halfWidth = width * 0.5;
    if (clipA.w <= 1e-6 || clipB.w <= 1e-6) {
        output.position = float4(0.0, 0.0, 2.0, 1.0);   // behind the eye: outside the clip volume
        output.across = 0.0;
        return output;
    }
    float2 halfViewport = 0.5 * frame.tail.xy;
    float2 screenA = clipA.xy / clipA.w * halfViewport;
    float2 screenB = clipB.xy / clipB.w * halfViewport;
    float2 delta = screenB - screenA;
    float segmentLength = length(delta);
    float2 along = segmentLength > 1e-4 ? delta / segmentLength : float2(1.0, 0.0);
    float2 normal = float2(-along.y, along.x);
    bool atB = (vid & 1u) != 0u;
    float side = (vid & 2u) != 0u ? 1.0 : -1.0;
    float reach = output.halfWidth + 1.0;
    float2 offset = normal * side * reach + along * (atB ? 1.0 : -1.0) * output.halfWidth;
    float4 clip = atB ? clipB : clipA;
    output.position = float4(clip.xy + offset / halfViewport * clip.w, clip.z, clip.w);
    output.across = side * reach;
    output.world = atB ? b : a;
    return output;
}
```

`Shaders/viewport/mesh.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

cbuffer Draw : register(b0, space3) { DrawUniforms draw; };
cbuffer Shade : register(b1, space3) { ShadeUniforms shade; };
cbuffer Clip : register(b2, space3) { ClipUniforms clip; };

struct In {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
};

float4 main(In input, bool front : SV_IsFrontFace) : SV_Target0 {
    if (clipped(clip, input.world)) {
        discard;
    }
    float3 n = normalize(input.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float t = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = lerp(shade.dark.rgb, shade.light.rgb, t) + rim * 0.06;
    uint flags = input.flags;
    if ((flags & 2u) != 0u) {
        color = lerp(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = lerp(color, shade.hover.rgb, 0.18);
    }
    if ((flags & 4u) != 0u) {
        color = lerp(color, shade.warning.rgb, 0.7);
    }
    // Looking into a cut part, the inside of its far wall stands for the cut face: the part's colour, darkened and flat.
    if (clip.enabled.x != 0u && !front) {
        color = lerp(shade.dark.rgb, shade.light.rgb, 0.5) * 0.55;
    }
    color = saturate(color);
    if (draw.ghost != 0u) {
        float grey = dot(color, float3(0.299, 0.587, 0.114));
        color = lerp(color, float3(grey, grey, grey), 0.85);
        return float4(color * 0.4, 0.4);
    }
    return float4(color, 1.0);
}
```

`Shaders/viewport/mesh.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// Solids. The face flags are read here and not in the fragment stage: SDL_GPU's render pass binds storage buffers to the vertex stage
// only, and a flag is the same for every corner of a face, so a flat interpolant carries it to the fragment stage.
StructuredBuffer<MeshVertex> vertices : register(t0, space0);
StructuredBuffer<uint> faceFlags : register(t1, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Draw : register(b1, space1) { DrawUniforms draw; };

struct Out {
    float4 position : SV_Position;
    float3 viewNormal : TEXCOORD0;
    float3 world : TEXCOORD1;
    nointerpolation uint flags : TEXCOORD2;
};

Out main(uint vid : SV_VertexID) {
    MeshVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.viewNormal = mulColumns(frame.view, float4(v.normal.xyz, 0.0)).xyz;
    output.world = v.position.xyz;
    output.flags = v.face.x < draw.faceCount ? faceFlags[v.face.x] : 0u;
    return output;
}
```

`scripts/shadercross.env` (new):

```sh
# The one pin of the shader compiler (plan xp-3, user decision U1(b)), the commit MetalUI docs/packaging.md section 4a documents. Read by
# scripts/build-shaders.sh (in the Linux image) and build-shaders.ps1 and scripts/install-shadercross.ps1; the Dockerfile's ARG repeats
# the commit and ShaderToolchainTests fails if it differs. libsdl-org/SDL_shadercross has no release and no tag and MetalUI publishes no
# binary (ruling BS-H), so the pin is a commit: the head of `main` on 2026-10-21, whose latest `Build` run was green. The commit fixes its
# submodules (SPIRV-Cross, SPIRV-Headers, SPIRV-Tools and libsdl-org's DirectXShaderCompiler fork, which the Linux image builds) and
# Microsoft's prebuilt DirectXShaderCompiler v1.9.2602 (URL and SHA-256 in build-scripts/download-prebuilt-DirectXShaderCompiler.cmake,
# which the Windows build uses). To move the pin: change the commit here and in the Dockerfile, run scripts/linux-test.sh all and a
# Windows CI run.
SHADERCROSS_REPOSITORY=https://github.com/libsdl-org/SDL_shadercross
SHADERCROSS_COMMIT=1ff05bec573988a98ef9e0260b4da44f512b8367
```

`scripts/build-shaders.sh` (new, mode 755):

```bash
#!/bin/bash
# Compiles the viewport's SDL_GPU shaders (cross-platform spec section 4, plan xp-3, user decision U1(b)): the HLSL in Shaders/viewport
# becomes SPIR-V (Vulkan), DXIL (Direct3D 12) and MSL, a reflection JSON each, and SOURCE.sha256, in Shaders/viewport/compiled, through
# MetalUI's MetalUICompileShaders (MetalUI S12, docs/packaging.md section 4a), built from the ../MetalUI checkout; this script adds
# INCLUDES.sha256 for the shared header, which MetalUI's marker does not list. Nothing compiled is checked in (the directory is
# git-ignored): every Linux and Windows build makes it. The one tool outside Swift is SDL_shadercross, pinned in scripts/shadercross.env.
#
#   scripts/build-shaders.sh                  uses $SHADERCROSS, else /opt/shadercross/bin/shadercross (the Linux test image), else PATH
#   SHADERCROSS=/path/to/shadercross scripts/build-shaders.sh
#   METALUI_TOOLS_SCRATCH=DIR                 where MetalUI's tool is built (default .build/metalui-tools here; never inside ../MetalUI)
#
# On Linux scripts/linux-test.sh runs this in the test image before swift build, swift test, the smoke step and packaging; CI does the
# same through it. Windows has scripts/build-shaders.ps1. macOS builds Metal only (MSL strings) and never runs this.
#
# Exit codes: 0 the directory is built (or was already current); 69 shadercross is missing or is not the pinned commit; 1 a shader
# failed to compile (the directory is removed, so the tests and --self-test fail loudly rather than run on a half-built one);
# 2 MetalUI is not beside this repository. A rerun with unchanged sources compiles nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
# shellcheck source=scripts/shadercross.env
. scripts/shadercross.env
TOOL="SDL_shadercross ($SHADERCROSS_REPOSITORY, commit $SHADERCROSS_COMMIT, pinned in scripts/shadercross.env)"
fail() { echo "scripts/build-shaders.sh: $2" >&2; exit "$1"; }

SHADERCROSS=${SHADERCROSS:-}
if [ -z "$SHADERCROSS" ]; then
    for candidate in /opt/shadercross/bin/shadercross "$(command -v shadercross || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then SHADERCROSS=$candidate; break; fi
    done
fi
if [ -z "$SHADERCROSS" ] || [ ! -x "$SHADERCROSS" ]; then
    fail 69 "$TOOL was not found. Set SHADERCROSS=/path/to/shadercross, or on Linux run this through scripts/linux-test.sh, whose Docker image builds it (scripts/linux/Dockerfile, stage shadercross). The viewport's shaders are compiled at build time and cannot be built without it."
fi
# The image records the commit it built beside bin/; any other build is refused, so a stale image cannot pass for the pin.
BUILT=$(cat "$(dirname "$SHADERCROSS")/../COMMIT" 2>/dev/null || true)
if [ -n "$BUILT" ] && [ "$BUILT" != "$SHADERCROSS_COMMIT" ]; then
    fail 69 "$SHADERCROSS was built from commit $BUILT, but $TOOL is required. Rebuild it (scripts/linux-test.sh rebuilds the image when the Dockerfile's ARG changes)."
fi
[ -f "$ROOT/../MetalUI/Package.swift" ] || fail 2 "MetalUI must be checked out beside this repository (../MetalUI), as Package.swift expects."
METALUI=$(cd "$ROOT/../MetalUI" && pwd -P)
SCRATCH=${METALUI_TOOLS_SCRATCH:-$ROOT/.build/metalui-tools}

cd Shaders/viewport
shopt -s nullglob
# sha256sum's "<sha256>  <name>" lines for the named files, sorted bytewise by name: the format of MetalUI's SOURCE.sha256
# (SourceMarker.swift), so the same function says whether the directory is current and writes INCLUDES.sha256.
digests() {
    [ "$#" -gt 0 ] || return 0
    local name
    while read -r name; do sha256sum "$name"; done < <(printf '%s\n' "$@" | LC_ALL=C sort)
}
stages=(*.vert.hlsl *.frag.hlsl *.comp.hlsl)
headers=(*.hlsli)
current() {
    [ -f compiled/SOURCE.sha256 ] && [ -f compiled/INCLUDES.sha256 ] || return 1
    [ "$(digests "${stages[@]}")" = "$(cat compiled/SOURCE.sha256)" ] || return 1
    [ "$(digests "${headers[@]}")" = "$(cat compiled/INCLUDES.sha256)" ] || return 1
    local stage kind
    for stage in "${stages[@]}"; do
        for kind in spv msl dxil json; do [ -s "compiled/${stage%.hlsl}.$kind" ] || return 1; done
    done
}
[ "${#stages[@]}" -gt 0 ] || fail 1 "no NAME.vert.hlsl or NAME.frag.hlsl in Shaders/viewport."
if current; then
    echo "Shaders/viewport/compiled is current."
    exit 0
fi

rm -rf compiled
echo "Compiling Shaders/viewport with MetalUI's MetalUICompileShaders and $TOOL..."
if ! swift run --package-path "$METALUI" --scratch-path "$SCRATCH" MetalUICompileShaders \
        --shadercross "$SHADERCROSS" --source "$ROOT/Shaders/viewport" --out "$ROOT/Shaders/viewport/compiled"; then
    rm -rf compiled
    fail 1 "$TOOL failed to compile a shader of Shaders/viewport, or MetalUICompileShaders did not build (the lines above name the file and the complaint). Shaders/viewport/compiled was removed."
fi
digests "${headers[@]}" > compiled/INCLUDES.sha256
echo "Built Shaders/viewport/compiled ($(find compiled -type f | wc -l | tr -d ' ') files)."
```

`scripts/build-shaders.ps1` (new; the Windows twin, run by CI and by a developer on Windows):

```powershell
<#
.SYNOPSIS
Compiles the viewport's SDL_GPU shaders on Windows (plan xp-3, user decision U1(b)): the HLSL in Shaders\viewport becomes SPIR-V,
DXIL and MSL, a reflection JSON each and SOURCE.sha256, in Shaders\viewport\compiled, through MetalUI's MetalUICompileShaders
(MetalUI S12, docs/packaging.md section 4a), built from ..\MetalUI with a scratch path of ours; this script adds INCLUDES.sha256 for the
shared header. Nothing compiled is checked in; CI runs this before `swift build`, and so does a developer, once and after editing an
.hlsl file.

.DESCRIPTION
SDL_shadercross is pinned in scripts\shadercross.env (scripts\install-shadercross.ps1 builds that commit; CI caches the result). Swift
and MetalUI beside this repository (..\MetalUI) are needed. Exit 69 when shadercross is missing or is not the pinned commit, 1 when a
shader fails to compile (the compiled directory is removed so the tests and --self-test fail loudly), 2 when MetalUI is missing.

    scripts\build-shaders.ps1 -ShaderCross C:\tools\shadercross\bin\shadercross.exe     (or set $env:SHADERCROSS, or put it on PATH)
#>
param([string]$ShaderCross = $env:SHADERCROSS)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pin = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'shadercross.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $pin[$Matches[1]] = $Matches[2].Trim() }
}
$tool = "SDL_shadercross ($($pin.SHADERCROSS_REPOSITORY), commit $($pin.SHADERCROSS_COMMIT), pinned in scripts/shadercross.env)"
function Stop-Build([int]$code, [string]$message) {
    [Console]::Error.WriteLine("scripts/build-shaders.ps1: $message")
    exit $code
}

if (-not $ShaderCross) {
    $found = Get-Command shadercross.exe -ErrorAction SilentlyContinue
    if ($found) { $ShaderCross = $found.Source }
}
if (-not $ShaderCross -or -not (Test-Path $ShaderCross)) {
    Stop-Build 69 "$tool was not found. Pass -ShaderCross C:\path\shadercross.exe or set SHADERCROSS; scripts\install-shadercross.ps1 builds the pinned one. The viewport's shaders are compiled at build time and cannot be built without it."
}
# install-shadercross.ps1 records the commit it built beside bin\; any other build is refused.
$recorded = Join-Path (Split-Path -Parent (Split-Path -Parent $ShaderCross)) 'COMMIT'
if ((Test-Path $recorded) -and ((Get-Content $recorded -Raw).Trim() -ne $pin.SHADERCROSS_COMMIT)) {
    Stop-Build 69 "$ShaderCross was built from another commit than the one required: $tool. Rebuild it with scripts\install-shadercross.ps1."
}
$metalUI = Join-Path $root '..\MetalUI'
if (-not (Test-Path (Join-Path $metalUI 'Package.swift'))) { Stop-Build 2 'MetalUI must be checked out beside this repository (..\MetalUI), as Package.swift expects.' }
$metalUI = (Resolve-Path $metalUI).Path
$scratch = if ($env:METALUI_TOOLS_SCRATCH) { $env:METALUI_TOOLS_SCRATCH } else { Join-Path $root '.build\metalui-tools' }
$source = Join-Path $root 'Shaders\viewport'
$out = Join-Path $source 'compiled'

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
Write-Output "Compiling Shaders\viewport with MetalUI's MetalUICompileShaders and $tool..."
swift run --package-path $metalUI --scratch-path $scratch MetalUICompileShaders --shadercross $ShaderCross --source $source --out $out
if ($LASTEXITCODE) {
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Stop-Build 1 "$tool failed to compile a shader of Shaders\viewport, or MetalUICompileShaders did not build (the lines above name the file). Shaders\viewport\compiled was removed."
}
# INCLUDES.sha256 in MetalUI's marker format: "<sha256>  <name>" per header, sorted by name, LF (ShaderSourceTests reads it as a table).
$lines = Get-ChildItem (Join-Path $source '*.hlsli') | Sort-Object Name | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
}
[IO.File]::WriteAllText((Join-Path $out 'INCLUDES.sha256'), (($lines -join "`n") + "`n"))
Write-Output "Built Shaders\viewport\compiled ($((Get-ChildItem $out -File).Count) files)."
```

`scripts/install-shadercross.ps1` (new; builds the pinned SDL_shadercross on Windows. **CI-only: PowerShell is not installed on the Mac the plan was written on, and nothing here runs a Windows build, so this script is parsed by nobody until the first Windows run; Risk 14**):

```powershell
<#
.SYNOPSIS
Builds the pinned SDL_shadercross for Windows x64 (plan xp-3, user decision U1(b)) into -Prefix, so scripts\build-shaders.ps1 can
compile the viewport's shaders. CI runs it once per pin and caches the prefix with actions/cache; a developer runs it once.

.DESCRIPTION
The repository has no release or tag, so the pin is the commit in scripts\shadercross.env; the commit fixes the SPIRV-Cross,
SPIRV-Headers and SPIRV-Tools submodules and Microsoft's prebuilt DirectXShaderCompiler (downloaded by the commit's own cmake script,
by URL and SHA-256). It needs cmake, ninja and git on PATH (the windows-latest runner has them) and Visual Studio's C++ tools (entered below when cl is not
on PATH). SDL3's development package (its cmake files) is -Sdl3Root.

    scripts\install-shadercross.ps1 -Prefix C:\tools\shadercross -Sdl3Root C:\SDL3-3.4.16

It leaves <Prefix>\bin\shadercross.exe with its DLLs and <Prefix>\COMMIT, which build-shaders.ps1 compares with the pin. Outside a developer
shell it enters one itself (Visual Studio's DevShell module, found with vswhere), for this script's process only, so CI needs no action
for it and the later swift steps see the environment they always saw.
#>
param(
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$Sdl3Root,
    [string]$Work = (Join-Path $env:TEMP 'shadercross-src')
)
$ErrorActionPreference = 'Stop'
$pin = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'shadercross.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $pin[$Matches[1]] = $Matches[2].Trim() }
}
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
    if (-not $vs) { throw 'Visual Studio was not found (vswhere): SDL_shadercross needs its C++ compiler.' }
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
}
function Invoke-Step([string]$what, [scriptblock]$command) {
    & $command
    if ($LASTEXITCODE) {
        [Console]::Error.WriteLine("scripts/install-shadercross.ps1: $what failed (exit $LASTEXITCODE) while building SDL_shadercross $($pin.SHADERCROSS_COMMIT) ($($pin.SHADERCROSS_REPOSITORY), pinned in scripts/shadercross.env).")
        exit 1
    }
}

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory $Work | Out-Null
Invoke-Step 'git init' { git init $Work }
Invoke-Step 'git remote' { git -C $Work remote add origin $pin.SHADERCROSS_REPOSITORY }
Invoke-Step 'git fetch of the pinned commit' { git -C $Work fetch --depth 1 origin $pin.SHADERCROSS_COMMIT }
Invoke-Step 'git checkout' { git -C $Work checkout FETCH_HEAD }
Invoke-Step 'git submodules' { git -C $Work submodule update --init --depth 1 external/SPIRV-Cross external/SPIRV-Headers external/SPIRV-Tools }
Push-Location $Work
try {
    Invoke-Step 'the DirectXShaderCompiler download' { cmake -P build-scripts/download-prebuilt-DirectXShaderCompiler.cmake }
    $spirvPrefix = Join-Path $Work 'spirv_cross_prefix'
    Invoke-Step 'SPIRV-Cross (configure)' { cmake -S external/SPIRV-Cross -B spirv_cross_build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF "-DCMAKE_INSTALL_PREFIX=$spirvPrefix" }
    Invoke-Step 'SPIRV-Cross (build)' { cmake --build spirv_cross_build }
    Invoke-Step 'SPIRV-Cross (install)' { cmake --install spirv_cross_build }
    $dxc = Join-Path $Work 'external/DirectXShaderCompiler-binaries'
    Invoke-Step 'SDL_shadercross (configure)' {
        cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSDLSHADERCROSS_VENDORED=OFF -DSDLSHADERCROSS_CLI=ON `
            -DSDLSHADERCROSS_SHARED=ON -DSDLSHADERCROSS_STATIC=OFF -DSDLSHADERCROSS_INSTALL=ON -DSDLSHADERCROSS_INSTALL_RUNTIME=ON `
            "-DCMAKE_PREFIX_PATH=$Sdl3Root" "-DDirectXShaderCompiler_ROOT=$dxc" `
            "-Dspirv_cross_c_shared_ROOT=$spirvPrefix;$spirvPrefix/share/spirv_cross_c_shared" "-DCMAKE_INSTALL_PREFIX=$Prefix"
    }
    Invoke-Step 'SDL_shadercross (build)' { cmake --build build }
    Invoke-Step 'SDL_shadercross (install)' { cmake --install build }
} finally {
    Pop-Location
}
Set-Content -Path (Join-Path $Prefix 'COMMIT') -Value $pin.SHADERCROSS_COMMIT
Write-Output "SDL_shadercross $($pin.SHADERCROSS_COMMIT) is in $Prefix."
```

`Package.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Package.swift
+++ b/Package.swift
@@ -118,6 +118,7 @@
         name: "CreatorViewportTests",
         dependencies: [
             "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts,
+            "CreatorGraph",   // CreatorGraph's SHA256, which hashes the shader sources for the freshness check against the build's SOURCE.sha256
         ] + occt
     ),
 ]
```

`scripts/linux/Dockerfile` (change against master; apply with `git apply` or by hand). The `shadercross` stage is a layer set of its own, beside xp-2's `occt` stage and built the same way (from the public Swift image, its own cache key, handed to the final stage through an image name), and the final stage copies `/opt/shadercross` as it copies `/opt/occt`:

```diff
--- a/scripts/linux/Dockerfile
+++ b/scripts/linux/Dockerfile
@@ -9,8 +9,16 @@
 # runner). It starts from the public Swift image, not from BASE, so its cache does not depend on MetalUI's image. It is its own
 # stage so that Docker's layer cache (locally) and buildx's cache (CI, .github/workflows/xp.yml) skip it until OCCT_COMMIT,
 # OCCT_JOBS or the flags change. CI builds it alone (`--target occt`) and hands the result to the final stage as OCCT_IMAGE.
+#
+# Stage `shadercross` builds SDL_shadercross, the compiler for the viewport's HLSL shaders (plan xp-3, user decision U1(b)), from the
+# commit pinned in scripts/shadercross.env, with MetalUI's recipe (MetalUI docs/packaging.md section 4a): natively on x86_64 and aarch64,
+# the DirectXShaderCompiler fork built from source (MetalUI measured 6 min 45 s at -j8 on Linux aarch64). Like `occt` it starts from the
+# public Swift image and is a stage of its own, so the caches skip it until SHADERCROSS_COMMIT or SHADERCROSS_JOBS change and a new
+# OpenCascade pin never rebuilds it (nor the reverse); CI builds it alone (`--target shadercross`) and hands it in as SHADERCROSS_IMAGE.
+# The final stage copies /opt/shadercross; scripts/build-shaders.sh runs it through MetalUI's MetalUICompileShaders.
 ARG BASE=metalui-portable:latest
 ARG OCCT_IMAGE=occt
+ARG SHADERCROSS_IMAGE=shadercross
 
 FROM swift:6.4-noble AS occt
 # V7_9_3 (peeled commit). A commit is pinned, not the tag: a tag can be moved.
@@ -39,14 +47,44 @@
 # work the same way.
 RUN for library in /opt/occt/lib/*.so.*.*.*; do patchelf --set-rpath '$ORIGIN' "$library"; done
 
+FROM swift:6.4-noble AS shadercross
+# The value must equal scripts/shadercross.env: ShaderToolchainTests fails if they differ (CI's buildx step builds it with this default).
+ARG SHADERCROSS_COMMIT=1ff05bec573988a98ef9e0260b4da44f512b8367
+ARG SDL_TAG=release-3.4.16
+# Part of the cache key, as OCCT_JOBS is (DirectXShaderCompiler is an LLVM build). The script passes it only when SHADERCROSS_JOBS is set.
+ARG SHADERCROSS_JOBS=6
+RUN apt-get update && apt-get install -y --no-install-recommends git cmake ninja-build python3 pkg-config ca-certificates \
+    && rm -rf /var/lib/apt/lists/*
+# SDL3, which SDL_shadercross links, headless and into the same prefix, so the copy into the final stage carries it.
+RUN git clone -q --depth 1 --branch ${SDL_TAG} https://github.com/libsdl-org/SDL.git /tmp/SDL \
+    && cmake -S /tmp/SDL -B /tmp/SDL/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/shadercross \
+         -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_X11=OFF -DSDL_WAYLAND=OFF \
+         -DSDL_AUDIO=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
+    && cmake --build /tmp/SDL/build --parallel ${SHADERCROSS_JOBS} && cmake --install /tmp/SDL/build && rm -rf /tmp/SDL
+# SDL_shadercross at the pinned commit (no release, no tag) with the four submodules the commit fixes (SPIRV-Cross, SPIRV-Headers,
+# SPIRV-Tools and libsdl-org's DirectXShaderCompiler fork, branch 1.8.2502-SDL), vendored, with clang (gcc refuses DXC's flags).
+# -DSDLSHADERCROSS_INSTALL_RUNTIME stays OFF: it would fetch Vulkan-Loader and the Khronos headers at `main` and build vkd3d, for a
+# Direct3D bytecode path the viewport does not use. The install leaves bin/shadercross with lib/libdxcompiler.so and lib/libdxil.so
+# beside it (MetalUICompileShaders puts that lib first on the loader path); the commit is recorded for build-shaders.sh to check.
+RUN git clone -q https://github.com/libsdl-org/SDL_shadercross.git /tmp/sc \
+    && git -C /tmp/sc checkout -q ${SHADERCROSS_COMMIT} && git -C /tmp/sc submodule update --init --depth 1 \
+    && cmake -S /tmp/sc -B /tmp/sc/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
+         -DCMAKE_PREFIX_PATH=/opt/shadercross -DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_INSTALL=ON \
+         -DSDLSHADERCROSS_INSTALL_RUNTIME=OFF -DSDLSHADERCROSS_CLI=ON "-DCMAKE_INSTALL_RPATH=\$ORIGIN/../lib" \
+    && cmake --build /tmp/sc/build --parallel ${SHADERCROSS_JOBS} && cmake --install /tmp/sc/build --prefix /opt/shadercross \
+    && echo "${SHADERCROSS_COMMIT}" > /opt/shadercross/COMMIT && rm -rf /tmp/sc
+
 # COPY --from takes no variable, so the stage or image to copy from is named by a FROM line.
 FROM ${OCCT_IMAGE} AS occt-source
+FROM ${SHADERCROSS_IMAGE} AS shadercross-source
 
 FROM ${BASE}
 RUN apt-get update \
     && apt-get install -y --no-install-recommends fonts-dejavu-core patchelf desktop-file-utils file \
     && rm -rf /var/lib/apt/lists/*
 COPY --from=occt-source /opt/occt /opt/occt
+# SDL_shadercross for scripts/build-shaders.sh (xp-3); nothing else in the image uses it.
+COPY --from=shadercross-source /opt/shadercross /opt/shadercross
 # No ld.so.conf entry: the binaries must find /opt/occt/lib through the rpath Package.swift gives them, as a tarball's do.
 ENV OCCT_PREFIX=/opt/occt
 # patchelf and desktop-file-utils serve scripts/package-linux.sh and its checks; `file` is needed by appimagetool, which scripts/package-appimage.sh
```

`scripts/linux-test.sh` (change; apply with `git apply` or by hand; it applies after task 0's change to the same file):

```diff
--- a/scripts/linux-test.sh
+++ b/scripts/linux-test.sh
@@ -28,13 +28,20 @@
 # device fails SDLGPUAvailabilityTests instead, so a runner that lost its driver cannot pass by running none of them (MetalUI's
 # METALUI_REQUIRE_GPU).
 #
+# The viewport's HLSL shaders are compiled at build time (plan xp-3, user decision U1(b)): before build, test, smoke and package this
+# script runs scripts/build-shaders.sh in the image, which holds the pinned SDL_shadercross (scripts/shadercross.env; the Dockerfile's
+# `shadercross` stage, built once and cached like OpenCascade's) and builds MetalUI's MetalUICompileShaders into the track's volume. The
+# output, Shaders/viewport/compiled in the worktree, is git-ignored; a run with nothing to recompile takes a second. If shadercross is
+# missing or a shader fails, the step stops with a message that names the tool and its pinned commit.
+#
 # Environment: XP_TRACK names the track (default xp-1), which names the container and the volume, so a script run kills only
 # its own container. EXPECTED_TEST_RUNS overrides the count (12 today). IMAGE names the image this script builds and runs
 # (default metalcreator-linux:latest; a track that must not replace another's image sets its own). OpenCascade is built from
 # source in an image stage, which is the slow part: OCCT_IMAGE names an image that already holds /opt/occt (CI builds the
 # stage alone with buildx and its layer cache and passes the result), else the stage is built here and Docker's layer cache
 # keeps it. OCCT_JOBS sets the parallelism of
-# that OpenCascade build (default 6; a different value is a different Docker cache key and rebuilds OpenCascade).
+# that OpenCascade build (default 6; a different value is a different Docker cache key and rebuilds OpenCascade). SHADERCROSS_IMAGE
+# and SHADERCROSS_JOBS do the same for the `shadercross` stage (CI passes the image it built with buildx).
 set -euo pipefail
 
 cd "$(dirname "$0")/.."
@@ -67,7 +74,8 @@
 fi
 if [ "${METALCREATOR_IMAGE_PREBUILT:-}" != 1 ]; then
     docker build -q -t "$IMAGE" --build-arg "BASE=$BASE_IMAGE" ${OCCT_IMAGE:+--build-arg "OCCT_IMAGE=$OCCT_IMAGE"} \
-        ${OCCT_JOBS:+--build-arg "OCCT_JOBS=$OCCT_JOBS"} - < scripts/linux/Dockerfile >/dev/null
+        ${OCCT_JOBS:+--build-arg "OCCT_JOBS=$OCCT_JOBS"} ${SHADERCROSS_IMAGE:+--build-arg "SHADERCROSS_IMAGE=$SHADERCROSS_IMAGE"} \
+        ${SHADERCROSS_JOBS:+--build-arg "SHADERCROSS_JOBS=$SHADERCROSS_JOBS"} - < scripts/linux/Dockerfile >/dev/null
 fi
 
 # Runs `$1` in the image, from the repository, with the build volume (and `$DOCKER_EXTRA`, if set); stops only this track's own
@@ -80,11 +88,20 @@
         "$IMAGE" bash -ec "$1"
 }
 
+# Compiles Shaders/viewport into Shaders/viewport/compiled in the worktree (git-ignored), MetalUI's tool built in the track's volume;
+# a second when nothing changed. Every step that builds the app runs it first (`|| return 1`: `set -e` is off inside a function
+# called from `&&`, as `all` calls them).
+compile_shaders() {
+    in_container 'METALUI_TOOLS_SCRATCH=/build/metalui-tools scripts/build-shaders.sh'
+}
+
 do_build() {
+    compile_shaders || return 1
     in_container 'swift build --scratch-path /build'
 }
 
 do_smoke() {
+    compile_shaders || return 1
     in_container 'bin=$(swift build --scratch-path /build --show-bin-path)/MetalCreatorApp
         "$bin" --self-test
         "$bin" --smoke-test 20'
@@ -96,6 +113,7 @@
     local arch
     arch=$(uname -m | sed 's/arm64/aarch64/')
     rm -f dist/MetalCreator-*-linux-"$arch".tar.gz dist/MetalCreator-*-linux-"$arch".AppImage
+    compile_shaders || return 1
     DOCKER_EXTRA="-v $VOLUME-package:/build-package" in_container '
         desktop-file-validate packaging/linux/com.metalcreator.MetalCreator.desktop
         METALCREATOR_SCRATCH=/build-package scripts/package-linux.sh
@@ -145,6 +163,7 @@
     local status=0 quoted=""
     # printf %q keeps a filter like 'A|B' one word through the container's shell.
     if [ "${#TEST_ARGS[@]}" -gt 0 ]; then printf -v quoted ' %q' "${TEST_ARGS[@]}"; fi
+    compile_shaders || { echo "Linux: FAIL (the viewport's shaders did not compile; see above)" >&2; return 1; }
     in_container "swift test --scratch-path /build$quoted" 2>&1 | tee "$LOG" || status=$?
     local clean runs tests
     clean=$(sed $'s/\x1b\\[[0-9;]*m//g' "$LOG")
```

`.github/workflows/xp.yml` (change against master; apply with `git apply` or by hand). Every `uses:` is one master already pins by SHA (`docker/build-push-action` v7, `actions/cache/restore` and `save` v4); no new action is added (the Windows build enters Visual Studio's developer shell inside `install-shadercross.ps1`). Task 9 changes the same file again, after this task:

```diff
--- a/.github/workflows/xp.yml
+++ b/.github/workflows/xp.yml
@@ -17,6 +17,13 @@
 # libraries: one C runtime on both sides), and vcpkg's binary cache folder is restored before and saved right after the install, so
 # a red later step does not lose it.
 #
+# The viewport's HLSL shaders are compiled at build time (plan xp-3, user decision U1(b)); nothing compiled is checked in. SDL_shadercross,
+# pinned by commit in scripts/shadercross.env (no release or tag upstream, no binary from MetalUI), is built on Linux by the Dockerfile's
+# `shadercross` stage, natively on each runner, alone with buildx and cached (scope xp-shadercross-<arch>), and on Windows by
+# scripts/install-shadercross.ps1, cached by actions/cache/restore and save under a key of the pin and the script. scripts/linux-test.sh
+# and scripts/build-shaders.ps1 compile through MetalUI's MetalUICompileShaders before `swift build`; a failure stops the job with a
+# message that names the tool and its commit.
+#
 # The Windows job is modelled on MetalUI's own Windows job (.github/workflows/sdl-gpu-linux.yml). Run 38546048595 was green: it builds, passes the
 # suite (11 "Test run with" lines; 12 since xp-2 added CreatorOCCTTests) and passes the app's --self-test and --smoke-test. It stays continue-on-error, so it does not hide the Linux
 # result, and the last step marks a red Windows run with a warning and a summary line (the run itself shows green); read its log on every run.
@@ -88,15 +95,27 @@
           load: true
           cache-from: type=gha,scope=xp-occt-${{ matrix.arch }}
           cache-to: type=gha,mode=max,scope=xp-occt-${{ matrix.arch }}
-      - name: Build, test, self-test and launch
+      - name: Build SDL_shadercross (the commit of scripts/shadercross.env; cached)
+        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7
+        with:
+          context: MetalCreator/scripts/linux
+          file: MetalCreator/scripts/linux/Dockerfile
+          target: shadercross
+          tags: metalcreator-shadercross:latest
+          load: true
+          cache-from: type=gha,scope=xp-shadercross-${{ matrix.arch }}
+          cache-to: type=gha,mode=max,scope=xp-shadercross-${{ matrix.arch }}
+      - name: Compile the shaders, build, test, self-test and launch
         working-directory: MetalCreator
         env:
           OCCT_IMAGE: metalcreator-occt:latest
+          SHADERCROSS_IMAGE: metalcreator-shadercross:latest
         run: scripts/linux-test.sh all
       - name: Package (tarball and AppImage), each checked in a clean Ubuntu
         working-directory: MetalCreator
         env:
           OCCT_IMAGE: metalcreator-occt:latest
+          SHADERCROSS_IMAGE: metalcreator-shadercross:latest
         run: scripts/linux-test.sh package
       - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
         with:
@@ -199,6 +218,26 @@
         with:
           path: ${{ runner.temp }}\vcpkg-cache
           key: ${{ steps.vcpkg-cache.outputs.cache-primary-key }}
+      - name: Restore SDL_shadercross
+        id: shadercross-cache
+        # Not actions/cache, for the vcpkg cache's reason: the save step below runs as soon as the build is done.
+        uses: actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
+        with:
+          path: ${{ runner.temp }}\shadercross
+          key: shadercross-windows-x64-${{ hashFiles('MetalCreator/scripts/shadercross.env', 'MetalCreator/scripts/install-shadercross.ps1') }}
+      - name: Build SDL_shadercross (the pinned commit, once per pin)
+        id: shadercross
+        if: ${{ steps.shadercross-cache.outputs.cache-hit != 'true' }}
+        working-directory: MetalCreator
+        run: |
+          scripts\install-shadercross.ps1 -Prefix "$env:RUNNER_TEMP\shadercross" -Sdl3Root $env:SDL3_ROOT
+          exit $LASTEXITCODE
+      - name: Save SDL_shadercross
+        if: ${{ always() && steps.shadercross.outcome == 'success' && steps.shadercross-cache.outputs.cache-hit != 'true' }}
+        uses: actions/cache/save@0057852bfaa89a56745cba8c7296529d2fc39830 # v4
+        with:
+          path: ${{ runner.temp }}\shadercross
+          key: ${{ steps.shadercross-cache.outputs.cache-primary-key }}
       - name: Fetch AccessKit
         working-directory: MetalUI/Backends/SDL
         # One SwiftPM flag per line: -Xcc -I<include> -Xswiftc -L<lib> (MetalUI PX-I item 2).
@@ -206,6 +245,13 @@
           python scripts/fetch-accesskit.py --print-flags > "$env:RUNNER_TEMP\accesskit-flags.txt"
           if ($LASTEXITCODE) { exit $LASTEXITCODE }
           Get-Content "$env:RUNNER_TEMP\accesskit-flags.txt"
+      - name: Compile the viewport's shaders
+        working-directory: MetalCreator
+        # MetalUI's MetalUICompileShaders through the pinned SDL_shadercross; stops with a message naming the tool and its commit if it
+        # is missing or a shader fails.
+        run: |
+          scripts\build-shaders.ps1 -ShaderCross "$env:RUNNER_TEMP\shadercross\bin\shadercross.exe"
+          exit $LASTEXITCODE
       - name: Build
         working-directory: MetalCreator
         # No pkg-config on Windows: hand SwiftPM SDL's include and library paths.
```

- [ ] **Step 4: Build the shadercross stage and compile the shaders**

macOS needs nothing and builds nothing here (U6(a)); its run in step 5 covers the struct sizes and the toolchain pin. On Linux, `scripts/linux-test.sh` rebuilds the test image with the new `shadercross` stage on first use (natively; MetalUI measured the DXC fork at 6 min 45 s with 8 jobs on Linux aarch64, so budget about 15 minutes with the default 6 and SDL3; Docker caches it) and compiles before it builds, building MetalUI's tool into the volume the first time (seconds):

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh build 2>&1 | grep -v '^20' | tail -4
ls Shaders/viewport/compiled | wc -l
cat Shaders/viewport/compiled/INCLUDES.sha256
git status --short Shaders      # lists the new sources, never compiled/
git -C ../MetalUI status --short   # nothing: MetalUI is never written to
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh build 2>&1 | grep -E 'current|Built'
```

Expected: the first run ends with `Built Shaders/viewport/compiled (66 files).` (`Compiled 16 shader(s) to SPIRV, MSL, DXIL, JSON: /work/MetalCreator/Shaders/viewport/compiled` is `MetalUICompileShaders`' own last line before it, after one `NAME.<stage> {…}` reflection line per stage); `66`; one line, the SHA-256 of `common.hlsli`; `git status` shows the HLSL files and no `compiled` entry; `git -C ../MetalUI status --short` prints nothing (the tool was built in `/build/metalui-tools`, and `../MetalUI` is mounted read-only); the second run prints `Shaders/viewport/compiled is current.` and rebuilds nothing. Each stage's `NAME.*.json` lists its resource counts: for example `mesh.vert.json` says `"storage_buffers": 2, "uniform_buffers": 2` and the cube and slice shaders (tasks 10 and 12) will say `"samplers": 1`. A second compile after `rm -r Shaders/viewport/compiled` gives byte-identical files.

**Measured here: see "Measured here" at the end of this task.**

- [ ] **Step 5: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 317 tests in 44 suites passed` (baseline 304/41 + 13 tests, + 3 suites).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 276 tests in 37 suites passed` (baseline 259/34 + 17 tests, + 3 suites).

The new tests: `ShaderSourceTests` has 1 test on macOS (the HLSL struct sizes against the Swift strides) and 2 on Linux and Windows (plus that the build produced every stage's four files where the renderer reads them and is current); `ShaderToolchainTests` has 2 (the pin agrees everywhere it is written and both scripts run `MetalUICompileShaders` with a scratch path, never the deleted python script; a missing shadercross stops `build-shaders.sh` with exit 69 and a message naming the tool, the repository and the pinned commit; that one is compiled out on Windows, where `build-shaders.ps1` has the same message and CI is its check). The old plan had 3 tests here (the struct sizes and two hash checks), so the macOS figures are the old ones and Linux gains one.

- [ ] **Step 6: Prove the checks bite**

The build step runs by itself in `linux-test.sh`, so these use the image directly to keep it from repairing what is being broken. `$V` and `$I` are this track's volume and image.

```bash
V=xp-3-linux-build; I=metalcreator-linux:xp-3
run() { docker run --rm -e XP_REQUIRE_GPU=1 -v "$PWD":/work/MetalCreator -v "$PWD/../MetalUI":/work/MetalUI:ro -v $V:/build $I bash -ec "$1"; }
# 1. A source edited after the last build is caught, with the remedy in the message.
cp Shaders/viewport/mesh.frag.hlsl /tmp/mesh.frag.hlsl.bak
echo '// edited' >> Shaders/viewport/mesh.frag.hlsl
run 'swift test --scratch-path /build --filter ShaderSourceTests' 2>&1 | grep -E 'changed after the last build|Test run with'
mv /tmp/mesh.frag.hlsl.bak Shaders/viewport/mesh.frag.hlsl
# 2. No build at all is caught, naming the script and the tool.
mv Shaders/viewport/compiled /tmp/compiled.bak
run 'swift test --scratch-path /build --filter ShaderSourceTests' 2>&1 | grep -E 'no compiled shader directory|Test run with'
mv /tmp/compiled.bak Shaders/viewport/compiled
# 3. No shadercross stops the script, exit 69, naming the tool and its commit.
SHADERCROSS=/nonexistent scripts/build-shaders.sh; echo "exit $?"
# 4. A shader the compiler rejects stops it (exit 1) and leaves no half-built directory.
cp Shaders/viewport/grid.frag.hlsl /tmp/grid.bak && echo 'syntax error here' >> Shaders/viewport/grid.frag.hlsl
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh build; echo "exit $?"; ls Shaders/viewport/compiled 2>&1 | head -1
mv /tmp/grid.bak Shaders/viewport/grid.frag.hlsl
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh build 2>&1 | grep -E 'Built|current'
```

Expected: (1) `mesh.frag.hlsl changed after the last build. Run scripts/build-shaders.sh …` and a failed run, (2) `no compiled shader directory beside the executable or in the source tree. Run scripts/build-shaders.sh …`, (3) `scripts/build-shaders.sh: SDL_shadercross (https://github.com/libsdl-org/SDL_shadercross, commit 1ff05bec573988a98ef9e0260b4da44f512b8367, pinned in scripts/shadercross.env) was not found. …` and `exit 69`, (4) the compiler's complaint naming `grid.frag.hlsl`, `SDL_shadercross (…, commit 1ff05bec…) failed to compile a shader of Shaders/viewport`, a non-zero exit, and `No such file or directory` for `compiled`; after the file is restored the build prints `Built Shaders/viewport/compiled (66 files).`.

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
bash -n scripts/build-shaders.sh scripts/linux-test.sh && echo syntax-ok
git status --short                # no Shaders/viewport/compiled line: it is ignored
git add .gitattributes .gitignore \
  Package.swift \
  Shaders/viewport/background.frag.hlsl \
  Shaders/viewport/background.vert.hlsl \
  Shaders/viewport/common.hlsli \
  Shaders/viewport/field_mesh.frag.hlsl \
  Shaders/viewport/field_mesh.vert.hlsl \
  Shaders/viewport/fill.frag.hlsl \
  Shaders/viewport/fill.vert.hlsl \
  Shaders/viewport/grid.frag.hlsl \
  Shaders/viewport/grid.vert.hlsl \
  Shaders/viewport/id_line.frag.hlsl \
  Shaders/viewport/id_line.vert.hlsl \
  Shaders/viewport/id_mesh.frag.hlsl \
  Shaders/viewport/id_mesh.vert.hlsl \
  Shaders/viewport/line.frag.hlsl \
  Shaders/viewport/line.vert.hlsl \
  Shaders/viewport/mesh.frag.hlsl \
  Shaders/viewport/mesh.vert.hlsl \
  Tests/CreatorViewportTests/ShaderSourceTests.swift \
  Tests/CreatorViewportTests/ShaderToolchainTests.swift \
  scripts/shadercross.env \
  scripts/build-shaders.sh \
  scripts/build-shaders.ps1 \
  scripts/install-shadercross.ps1 \
  scripts/linux/Dockerfile \
  scripts/linux-test.sh \
  .github/workflows/xp.yml
chmod +x scripts/build-shaders.sh && git update-index --chmod=+x scripts/build-shaders.sh
git commit -m "viewport: HLSL shaders compiled at build time by a pinned SDL_shadercross; no compiled files in git"
```

**Measured, and what was not.** On 2026-10-21 the old variant of this task (an amd64 `ubuntu:24.04` stage with Microsoft's prebuilt DXC, and MetalUI's python script) was built and run on this Mac under emulation: 16 stage files compiled to 66 files, the "current" rerun, the edit rebuild, exit 69 and exit 1 all behaved as written. On 2026-10-22, for this revision: `MetalUICompileShaders` was built from a read-only copy of MetalUI `5f03ab7b` with `swift run --package-path <copy> --scratch-path <elsewhere>` (6 s, nothing written into the copy), and `scripts/build-shaders.sh` as written here, run on macOS against that copy with a stub shadercross that writes its `-o` file, made `NAME.<stage>.{spv,msl,dxil,json}`, MetalUI's `SOURCE.sha256` (byte-for-byte what `sha256sum` prints for the stage files, so the script's "current" test matched it) and `INCLUDES.sha256`, printed `Shaders/viewport/compiled is current.` on the rerun, and exited 69 with no shadercross and 1, removing the directory, when the compile failed. **Not run:** the native `shadercross` stage (MetalUI measured its recipe on Linux aarch64, not this Dockerfile), a real shadercross through `MetalUICompileShaders` on Linux, the PowerShell scripts, the Windows build and `scripts/linux-test.sh` end to end (see Verification and Risks 13 and 14).



### Task 5: The SDL device layer: shader library, uploads, meshes, pipelines

The building blocks of the SDL renderer, none of which draws yet. `SDLViewportShaders` finds `Shaders/viewport/compiled` the way MetalUI documents (`MetalUIAppShaders` beside the executable, then the source tree, derived from `#filePath`) and can `verify()` that every stage loads for the platform's driver. `SDLViewportUploader` makes a vertex-stage storage buffer and records the copy that fills it into a command buffer (a transfer buffer, `commandBuffer.copy`): the same code serves a surface draw's own buffer and a test's batch. `SDLViewportMesh` is `GPUMesh` for SDL: the de-indexed triangles, edge instances per key (the same cache rules), face flags, field values and the ID pass's edges. `SDLViewportPipelines` builds every graphics pipeline from the blobs; SDL_GPU puts the depth test in the pipeline, so a draw that differs only in its depth test is its own pipeline. `SDLTestDevice` holds the one shared device and the one set of pipelines the render suites use: making pipelines compiles every shader (about a second on a CPU driver) on the main actor, and a test that made its own held the main actor long enough to starve the real-clock `ScrollZoomTests.theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay` in a full Linux run on a loaded machine. `SDLGPUAvailabilityTests` is where the policy of user decision U3 lives: the suites skip without an SDL_GPU device, and where `XP_REQUIRE_GPU=1` this test fails instead of letting them all skip.

Package.swift: `CreatorViewport` and its tests depend on `MetalUISDL` and `MetalUISDLGPU` on Linux and Windows only (`.when(platforms:)`, both constants already exist or are added here). Both are named because `ViewportModel+SDLSurface` imports `MetalUISDL` for `SDLGPUDrawContext` (defined there, not in `MetalUISDLGPU`, which re-exports only `CSDL`); relying on SwiftPM leaking the transitive module is not guaranteed. A conditional product that a **test** target also names is the shape of the SwiftPM defect MetalUI ruled on as `SG-D` (module maps dropped on macOS), so step 4 builds the macOS tests from a clean state right after this change.

**Files:**
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportMesh.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportUploader.swift`
- Create: `Tests/CreatorViewportTests/SDLGPUAvailabilityTests.swift`
- Create: `Tests/CreatorViewportTests/Support/SDLTestDevice.swift`
- Modify: `Package.swift`
- Modify: `Tests/CreatorViewportTests/ShaderSourceTests.swift`

**Interfaces:**
- Consumes: `Shaders/viewport/compiled` (task 4); MetalUI `SDLGPUDevice` (`compileGraphicsPipeline(_:) throws -> SDLGPUGraphicsPipeline`, whose `SDLGPUError` carries SDL's reason, ruling `GB-G`; `makeBuffer`, `makeTransferBuffer`), `SDLGPUShaderLibrary` (`locate(directoryName:sourceTree:)`, `vertex`/`fragment(_:for:)`), `SDLGPUBuffer`, `SDLGPUGraphicsPipelineDescription`; `GPUGeometry.meshVertices/edgeInstances/faceFlags/fieldCorners`; `EdgeInstanceKey`; `ViewportRenderError.deviceRefused`.
- Produces: `SDLViewportShaders.library()`, `.names`, `.verify(driver:) -> Int`, `.platformDriver`; `SDLViewportUploader(device:, commandBuffer:)`, `.storageBuffer(_:) -> SDLGPUBuffer?`; `uniformBytes(_:) -> [UInt8]`; `SDLViewportMesh` (`vertexBuffer`, `vertexCount`, `faceCount`, `edges(_:palette:uploader:)`, `faceFlags(…)`, `fieldValues(…)`, `pickEdges(solid:uploader:)`, `cachedPickEdges`, `hasPickEdges`); `SDLViewportPipelines(device:library:)` with `background, fill, mesh, fieldMesh, ghost, lineTest, lineAlways, lineBehind, grid, idMesh, idLine`; the test support `SDLTestDevice.shared`, `SDLTestDevice.pipelines`, `Handoff`.

- [ ] **Step 1: Write the failing tests**

These are SDL-only: they compile to nothing on macOS.

`Tests/CreatorViewportTests/SDLGPUAvailabilityTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The SDL renderer's suites disable themselves when no SDL_GPU device answers, so a runner without a GPU would pass them by running
/// none. Where the environment promises a GPU (`XP_REQUIRE_GPU=1`: the Linux image runs Mesa's lavapipe, a CPU Vulkan driver, and
/// `scripts/linux-test.sh` sets it; the Windows job runs Direct3D 12 on WARP), this test fails instead, naming why.
@MainActor
struct SDLGPUAvailabilityTests {
    @Test func aDeviceAnswersWhereTheEnvironmentPromisesOne() throws {
        let required = ProcessInfo.processInfo.environment["XP_REQUIRE_GPU"] == "1"
        try #require(!required || SDLTestDevice.isAvailable, "XP_REQUIRE_GPU=1 but no device: \(SDLGPUDevice.lastFailure)")
    }

    @Test(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
    func theShaderLibraryAndEveryPipelineAreMade() throws {
        let device = try #require(SDLTestDevice.shared)
        let library = try SDLViewportShaders.library()
        _ = try SDLViewportPipelines(device: device, library: library)
    }
}
#endif
```

`Tests/CreatorViewportTests/Support/SDLTestDevice.swift` (new):

```swift
// Test fixture file: the SDL_GPU device the renderer tests share, and what a batch's recording closure is handed.
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// A value handed to a batch's recording closure, which runs on the device's worker thread. The test awaits the batch before it
/// touches the value again, so nothing else does meanwhile.
struct Handoff<Value>: @unchecked Sendable {
    let value: Value
}

struct SDLRigError: Error, CustomStringConvertible {
    let description: String
}

/// The device the SDL renderer tests share: Vulkan on Mesa's lavapipe in the Linux image, Direct3D 12 on WARP on Windows runners. `nil`
/// when no GPU or driver answers, which disables the suites (named, not assumed: ``SDLGPUAvailabilityTests`` fails instead where the
/// environment promises a GPU).
enum SDLTestDevice {
    static let shared: SDLGPUDevice? = SDLGPUDevice.make()
    static var isAvailable: Bool { shared != nil }

    /// The viewport's pipelines on the shared device, made once: making them compiles every shader (a CPU driver takes about a second),
    /// and a test that made its own would hold the main actor for that long, long enough to starve the timing tests that share it.
    static let pipelines: SDLViewportPipelines? = shared.flatMap { device in
        (try? SDLViewportShaders.library()).flatMap { try? SDLViewportPipelines(device: device, library: $0) }
    }
}
#endif
```

`Tests/CreatorViewportTests/ShaderSourceTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ShaderSourceTests.swift
+++ b/Tests/CreatorViewportTests/ShaderSourceTests.swift
@@ -1,4 +1,7 @@
 import Foundation
+#if canImport(MetalUISDLGPU)
+import MetalUISDLGPU
+#endif
 import Testing
 @testable import CreatorGraph
 @testable import CreatorViewport
@@ -137,3 +140,18 @@
     }
     #endif
 }
+
+#if canImport(MetalUISDLGPU)
+/// The SDL renderer finds its shaders the way a shipped app does (MetalUI `docs/packaging.md` section 4a): the compiled directory, here
+/// the source tree's, holds every stage for the platform's driver, with its reflection.
+struct ViewportShaderDirectoryTests {
+    @Test func everyStageLoadsForThePlatformsDriver() throws {
+        #expect(try SDLViewportShaders.verify() == 16)
+    }
+
+    @Test func aStageThatIsMissingIsNamed() throws {
+        let library = try SDLViewportShaders.library()
+        #expect(throws: (any Error).self) { try library.vertex("no_such_shader", driver: SDLViewportShaders.platformDriver) }
+    }
+}
+#endif
```

- [ ] **Step 2: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. Linux: `cannot find 'SDLViewportShaders' in scope`, `cannot find 'SDLViewportPipelines' in scope`. (macOS compiles and passes: the tests are `#if canImport(MetalUISDLGPU)`.)

- [ ] **Step 3: Implement**

`Sources/CreatorViewport/RenderSDL/SDLViewportMesh.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

/// One mesh on the GPU: its de-indexed triangles as a storage buffer, plus edge-instance, face-flag and field-value buffers built
/// when first asked for (the same cache rules as `GPUMesh`). Like the renderer it belongs to, it is used from one thread at a time.
final class SDLViewportMesh: @unchecked Sendable {
    let vertexBuffer: SDLGPUBuffer?
    let vertexCount: Int
    /// One more than the highest face ID, so face flags can be indexed by ID.
    let faceCount: Int
    private let polylines: [EdgeID: [Vector3]]
    private var edgeBuffers: [EdgeInstanceKey: (buffer: SDLGPUBuffer, count: Int)] = [:]
    /// The palette `edgeBuffers` were built in; another one (the theme changed) drops them.
    private var edgePalette = ViewportPalette.dracula
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, warning: Set<FaceID>, buffer: SDLGPUBuffer)?
    private var fieldBuffer: (values: [Float], middle: Float, buffer: SDLGPUBuffer)?
    /// The ID pass's edge instances by solid index (the pick IDs name the solid), built by `pickEdges`. An entry of `nil` is a mesh
    /// with no edges.
    private var pickEdgeBuffers: [Int: (buffer: SDLGPUBuffer, count: Int)?] = [:]
    /// Field value buffers made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var fieldUploads = 0

    init(uploader: SDLViewportUploader, mesh: DisplayMesh) {
        let vertices = GPUGeometry.meshVertices(mesh)
        vertexBuffer = uploader.storageBuffer(vertices)
        vertexCount = vertices.count
        faceCount = (mesh.triangleFaces.map(\.rawValue).max() ?? -1) + 1
        polylines = mesh.edgePolylines
    }

    /// The edge instances for `key`, in `palette`'s colours. They're built once and kept: there are only a few keys in use (the
    /// main pass at one scale, and the ID pass), so a fifth key clears the lot, and so does a new palette.
    func edges(_ key: EdgeInstanceKey, palette: ViewportPalette, uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if palette != edgePalette {
            edgeBuffers.removeAll()
            edgePalette = palette
        }
        if let cached = edgeBuffers[key] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: key.solid, selected: key.selected,
                                                  selectedOnly: key.selectedOnly, scale: key.scale, palette: palette,
                                                  hidden: key.hidden)
        guard let buffer = uploader.storageBuffer(instances) else { return nil }
        if edgeBuffers.count >= 4 { edgeBuffers.removeAll() }
        edgeBuffers[key] = (buffer, instances.count)
        return (buffer, instances.count)
    }

    /// The instances the ID pass draws for the solid at `solid`: every edge, with its pick ID. They don't depend on the palette or the
    /// pixel scale (the pass draws edges 6 points wide in one colour), so they are built once per solid index and kept apart from
    /// `edges(_:palette:uploader:)`'s few keys; `nil` for a mesh with no edges.
    func pickEdges(solid: Int, uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = pickEdgeBuffers[solid] { return cached }
        let instances = GPUGeometry.edgeInstances(polylines, solid: solid, selected: [], selectedOnly: false, scale: 1)
        let built = uploader.storageBuffer(instances).map { (buffer: $0, count: instances.count) }
        pickEdgeBuffers[solid] = .some(built)
        return built
    }

    /// The instances `pickEdges(solid:uploader:)` built for `solid`, or `nil` when it has not been asked for it or the mesh has none.
    func cachedPickEdges(solid: Int) -> (buffer: SDLGPUBuffer, count: Int)? {
        pickEdgeBuffers[solid] ?? nil
    }

    /// Whether `pickEdges(solid:uploader:)` has been asked for `solid` (a mesh with no edges counts), so the ID pass can use it
    /// without a command buffer to upload into.
    func hasPickEdges(solid: Int) -> Bool { pickEdgeBuffers[solid] != nil }

    /// The face flags (bit 1 hovered, bit 2 selected, bit 4 warning), rebuilt only when the hover or selection changes. A mesh
    /// with no faces gets a one-entry buffer: a storage buffer cannot be empty, and the shader never reads it.
    func faceFlags(hovered: FaceID?, selected: Set<FaceID>, warning: Set<FaceID>, uploader: SDLViewportUploader) -> SDLGPUBuffer? {
        if let cached = flagBuffer, cached.hovered == hovered, cached.selected == selected, cached.warning == warning {
            return cached.buffer
        }
        let flags = GPUGeometry.faceFlags(count: max(faceCount, 1), hovered: hovered, selected: selected, warning: warning)
        guard let buffer = uploader.storageBuffer(flags) else { return nil }
        flagBuffer = (hovered, selected, warning, buffer)
        return buffer
    }

    /// The tint's value buffer, one float per de-indexed corner, rebuilt only when the values change. `nil` when the values are not
    /// one per vertex of `mesh`. A mesh is one solid and a solid has one tint, so the buffer is a single cached entry.
    func fieldValues(_ values: [Float], mesh: DisplayMesh, ramp: FieldRamp, uploader: SDLViewportUploader) -> SDLGPUBuffer? {
        if let cached = fieldBuffer, cached.middle == ramp.midValue, cached.values == values { return cached.buffer }
        guard let corners = GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp), corners.count == vertexCount,
              let buffer = uploader.storageBuffer(corners) else { return nil }
        fieldBuffer = (values, ramp.midValue, buffer)
        fieldUploads += 1
        return buffer
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The viewport's graphics pipelines, made once per device from the compiled shaders. SDL_GPU puts the depth test in the pipeline
/// (Metal has separate depth states), so a draw that differs only in its depth test is a pipeline of its own. Main-pass pipelines
/// render 4× MSAA `bgra8Unorm` (MetalUI's surface format) with `d32Float`; the ID pipelines render single-sample `r32Uint`. A refused
/// pipeline throws `ViewportRenderError.deviceRefused` with the shader pair and SDL's reason ("The GPU could not create the mesh/mesh
/// pipeline (pipeline: E_INVALIDARG …)."), which `ViewportModel.gpuFailureMessage` and `--smoke-test` show.
struct SDLViewportPipelines: Sendable {
    static let colorFormat = SDLGPUTextureFormat.b8g8r8a8Unorm
    static let idFormat = SDLGPUTextureFormat.r32Uint
    static let sampleCount = SDLGPUSampleCount.four

    /// No depth test or write: the background and the overlay's fills.
    let background: SDLGPUGraphicsPipeline
    let fill: SDLGPUGraphicsPipeline
    /// Opaque solids: test (less) and write.
    let mesh: SDLGPUGraphicsPipeline
    /// The surface coloured by a field's values (`field_mesh`).
    let fieldMesh: SDLGPUGraphicsPipeline
    /// The ghosts' blended colour pass: test against the solids without writing.
    let ghost: SDLGPUGraphicsPipeline
    /// Lines (premultiplied source-over): tested against the solids (less-or-equal) without writing; never tested; and only where
    /// something nearer already wrote depth (a guide's edges behind the part).
    let lineTest: SDLGPUGraphicsPipeline
    let lineAlways: SDLGPUGraphicsPipeline
    let lineBehind: SDLGPUGraphicsPipeline
    /// The ground grid: blended, tested against the solids without writing.
    let grid: SDLGPUGraphicsPipeline
    let idMesh: SDLGPUGraphicsPipeline
    let idLine: SDLGPUGraphicsPipeline

    init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
        func pipeline(_ vertex: String, _ fragment: String, primitive: SDLGPUPrimitiveType = .triangleList,
                      color: SDLGPUTextureFormat = Self.colorFormat, blend: SDLGPUBlend = .none,
                      samples: SDLGPUSampleCount = Self.sampleCount,
                      depth: SDLGPUDepthState) throws -> SDLGPUGraphicsPipeline {
            let description = SDLGPUGraphicsPipelineDescription(
                vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
                primitiveType: primitive, cullMode: .none, colorFormat: color, blend: blend, sampleCount: samples, depth: depth)
            do {
                return try device.compileGraphicsPipeline(description)
            } catch {
                // MetalUI's `SDLGPUError` names the stage that failed with SDL's own text (ruling GB-G, gap XP-G19).
                throw ViewportRenderError.deviceRefused("the \(vertex)/\(fragment) pipeline (\(error))")
            }
        }
        let always = SDLGPUDepthState(compare: .always, write: false)
        let writes = SDLGPUDepthState(compare: .less, write: true)
        let tests = SDLGPUDepthState(compare: .lessOrEqual, write: false)
        let behind = SDLGPUDepthState(compare: .greater, write: false)
        background = try pipeline("background", "background", depth: always)
        fill = try pipeline("fill", "fill", blend: .premultipliedAlpha, depth: always)
        mesh = try pipeline("mesh", "mesh", depth: writes)
        fieldMesh = try pipeline("field_mesh", "field_mesh", depth: writes)
        ghost = try pipeline("mesh", "mesh", blend: .premultipliedAlpha, depth: SDLGPUDepthState(compare: .less, write: false))
        lineTest = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
        lineAlways = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: always)
        lineBehind = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: behind)
        grid = try pipeline("grid", "grid", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
        idMesh = try pipeline("id_mesh", "id_mesh", color: Self.idFormat, samples: .one, depth: writes)
        idLine = try pipeline("id_line", "id_line", primitive: .triangleStrip, color: Self.idFormat, samples: .one, depth: tests)
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Finds the viewport's compiled shaders (cross-platform spec section 4): HLSL in `Shaders/viewport`, compiled at build time by
/// `scripts/build-shaders.sh` (`.ps1` on Windows) through MetalUI's `MetalUICompileShaders` and the pinned SDL_shadercross into
/// `Shaders/viewport/compiled` (SPIR-V for Vulkan, DXIL for Direct3D 12, MSL, a reflection file each, `SOURCE.sha256`). The directory is a
/// build product: git-ignored, never checked in (user decision U1(b)).
enum SDLViewportShaders {
    /// The source tree's compiled directory: this file is `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`, so the
    /// repository root is four directories up. Valid on the machine that built the app; a shipped app carries a copy as
    /// `MetalUIAppShaders` beside the executable (MetalUI `docs/packaging.md` section 4a), which is looked for first.
    static var sourceTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Shaders/viewport/compiled")
    }

    /// The viewport's shader library, or an error naming the directories tried. `sourceTree` is a parameter so a test (and
    /// `ViewportShaderCheck`'s test) can point it at an empty directory.
    static func library(sourceTree: URL = sourceTree) throws -> SDLGPUShaderLibrary {
        try SDLGPUShaderLibrary.locate(sourceTree: sourceTree)
    }

    /// Every shader the viewport builds a pipeline from; each has a vertex stage and a fragment stage of the same name.
    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "id_mesh", "id_line"]

    /// The driver whose blobs this platform's SDL picks: Direct3D 12 (DXIL) on Windows, Vulkan (SPIR-V) elsewhere.
    static var platformDriver: String {
        #if os(Windows)
        "direct3d12"
        #else
        "vulkan"
        #endif
    }

    /// Loads every blob for `driver`, which proves the directory and each stage's file and reflection are there, and returns how many
    /// stages that was.
    static func verify(driver: String = platformDriver, sourceTree: URL = sourceTree) throws -> Int {
        let library = try library(sourceTree: sourceTree)
        for name in names {
            _ = try library.vertex(name, driver: driver)
            _ = try library.fragment(name, driver: driver)
        }
        return names.count * 2
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportUploader.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Makes the GPU buffers one frame (or one test) needs and records the copies that fill them into a command buffer. A copy pass
/// cannot run inside a render pass, so everything a pass reads is made before it begins (`SDLFramePlan`).
struct SDLViewportUploader {
    let device: SDLGPUDevice
    let commandBuffer: SDLGPUCommandBuffer

    /// A buffer the vertex stage reads as a storage buffer, holding `values`, or `nil` for an empty array (SDL_GPU refuses
    /// zero-length buffers) or when SDL refuses. The copy that fills it is recorded in `commandBuffer` now; the buffer is
    /// ready for any pass recorded after it.
    func storageBuffer<T>(_ values: [T]) -> SDLGPUBuffer? {
        guard !values.isEmpty else { return nil }
        let size = values.count * MemoryLayout<T>.stride
        return values.withUnsafeBytes { bytes -> SDLGPUBuffer? in
            guard let base = bytes.baseAddress,
                  let buffer = device.makeBuffer(size: size, usage: [.graphicsStorageRead]),
                  let transfer = device.makeTransferBuffer(size: size, direction: .upload),
                  let memory = transfer.map() else { return nil }
            memory.copyMemory(from: base, byteCount: size)
            transfer.unmap()
            commandBuffer.copy(transfer, to: buffer, size: size)
            return buffer
        }
    }
}

/// The bytes of a uniform struct, as a uniform push takes them.
func uniformBytes<T>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}
#endif
```

`Package.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Package.swift
+++ b/Package.swift
@@ -29,6 +29,10 @@
 /// The SDL3 backend, on Linux and Windows only.
 let metalUISDL: Target.Dependency = .product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))
 
+/// MetalUI's SDL_GPU layer (`SDLGPUDevice`, textures, pipelines, render passes, shader library): the 3D viewport's renderer on Linux
+/// and Windows (xp-3). A dependency of `CreatorViewport` and its tests only.
+let metalUISDLGPU: Target.Dependency = .product(name: "MetalUISDLGPU", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))
+
 /// The OpenCascade kernel (xp-2): a dependency on every platform.
 let occt: [Target.Dependency] = ["CreatorOCCT"]
 
@@ -57,7 +61,9 @@
     // platform for the reason above (SG-D).
     .target(
         name: "CreatorViewport",
-        dependencies: ["CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts]
+        dependencies: [
+            "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts, metalUISDL, metalUISDLGPU,
+        ]
     ),
     .target(name: "CreatorEditor", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
     // The in-viewport sketch editor (sketcher spec §8, S5): `SketchEditorModel`, its tools and its views. Graph-free:
@@ -118,6 +124,7 @@
         name: "CreatorViewportTests",
         dependencies: [
             "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI, metalUIPortableText, metalUISystemFonts,
+            metalUISDL, metalUISDLGPU,
             "CreatorGraph",   // CreatorGraph's SHA256, which hashes the shader sources for the freshness check against the build's SOURCE.sha256
         ] + occt
     ),
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift package clean && swift build --build-tests 2>&1 | grep -E 'error:|warning:|Build complete' | grep -v 'ld: warning'   # SG-D: a clean macOS build of the tests, straight after the Package.swift change
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the clean macOS build ends `Build complete!` with no `error:` and no new `warning:`. If instead it fails with a missing module (`MetalUISDL` or `CSDL`) the conditional products have hit `SG-D` (MetalUI record `89-smk-gaps.md`: SwiftPM drops the module maps of a conditional product that a test target also names). Do not work around it in the manifest: the CreatorViewport suites that import SDL are `#if canImport(MetalUISDLGPU)` and the cure MetalUI chose for its portable products (name the product on every platform) is MetalUI's to give. Stop, log it in `docs/metalui-gaps.md` and move the SDL-only test files to a Linux/Windows-only test target in the same commit. Then
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 317 tests in 44 suites passed` (baseline 304/41 + 13 tests, + 3 suites).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 280 tests in 39 suites passed` (baseline 259/34 + 21 tests, + 5 suites).

On Linux the new tests are `theShaderLibraryAndEveryPipelineAreMade`, `aDeviceAnswersWhereTheEnvironmentPromisesOne` and `ViewportShaderDirectoryTests` (2). `scripts/linux-test.sh` sets `XP_REQUIRE_GPU=1`, so a missing lavapipe fails the first of them.
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Package.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportMesh.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportUploader.swift \
  Tests/CreatorViewportTests/SDLGPUAvailabilityTests.swift \
  Tests/CreatorViewportTests/ShaderSourceTests.swift \
  Tests/CreatorViewportTests/Support/SDLTestDevice.swift
git commit -m "viewport: SDL shader library, uploads, meshes and pipelines"
```


### Task 6: The main pass on SDL_GPU

`SDLViewportRenderer.encode(frame, into: target, scale:, commandBuffer:)` is `ViewportRenderer.encode` for SDL_GPU: the same layers in the same order, into a 4x MSAA `bgra8` colour target and a 4x `d32Float` depth target, resolved (`storeOp: .resolve`) into the target it is given. It is two steps because a copy pass cannot start inside a render pass: `plan` makes and fills every buffer the pass reads (`SDLFramePlan`: solids with their flags and tints, edge, guide, overlay, handle and fill instances) and `record` draws from the plan. Layers: background gradient, opaque solids (field tint where a solid has one, hover, selection and warning tints from the face flags, the cut view's clip and its darkened far wall), the ground grid (unless the overlay has a plane grid), B-rep edges, ghosts (blended; the depth-only prepass is task 11), guides' selected edges (and the faded pass where the part hides them), the overlay's fills, lines and points, and handles. The view cube, the triad and the slice are tasks 10 to 12.

The tests read pixels back from a 400 x 400 target at 2 pixels per point, in the front view the Metal tests use (`RenderFixtures.front`: a 10 x 20 x 30 box fills view x 75 to 125, y 25 to 175), and compare regions and palette colours with a margin, never exact pixels. They run on lavapipe in the Linux image and WARP on Windows. Review Focus 1 and 2 are tests here.

**Files:**
- Create: `Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift`
- Create: `Tests/CreatorViewportTests/SDLFieldGuideClipTests.swift`
- Create: `Tests/CreatorViewportTests/SDLRenderTests.swift`
- Create: `Tests/CreatorViewportTests/Support/RenderFixtures.swift`
- Create: `Tests/CreatorViewportTests/Support/SDLRenderRig.swift`
- Create: `Tests/CreatorViewportTests/Support/TestMeshes+Sheet.swift`

**Interfaces:**
- Consumes: task 5's uploader, meshes and pipelines; `GPUGeometry`, `OverlayGeometry`, `ShadeUniforms`, `ClipUniforms`, `FieldRampUniforms`, `GridUniforms`, `LineUniforms`, `DrawUniforms`, `BackgroundUniforms`; `ViewportFrame`.
- Produces: `final class SDLViewportRenderer: @unchecked Sendable` (`init(device:pipelines:)` and the convenience `init(device:library:) throws`, `encode(_:into:scale:commandBuffer:)`, `prepareMeshes(for:_:)`, `meshes`, `encodedPasses`, `overlayBuffer`, `fillBuffer`, `handleBuffer`, `static edgeDepthBias(_:)`); `SDLFramePlan`; `SDLPassRecorder`; test support `SDLRenderRig` (`draw(_:scale:) async throws -> [UInt8]` BGRA bytes, `color(_:_:_:)`, `bytes(_:)`), `RenderFixtures`, `TestMeshes.sheet`.

- [ ] **Step 1: Write the failing tests**

`SDLRenderTests` (the pass and the tint, hover, selection, warning and ghost looks), `SDLFieldGuideClipTests` (field tint, guides, the cut view), and the fixtures.

`Tests/CreatorViewportTests/SDLFieldGuideClipTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The field tint, the guides and the cut view on SDL_GPU (fields spec §6, spec §6.3 Errata (M6), implicit spec §5.1), as the Metal
/// `FieldTintRenderTests`, `GuideRenderTests` and `ViewportClipRenderTests` read them.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLFieldGuideClipTests {
    typealias Rig = SDLRenderRig
    static let mesh = TestMeshes.box(RenderFixtures.bounds)
    /// Red at x = −5, green at 0, blue at 5.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)
    var xValues: [Float] { Self.mesh.positions.map { Float($0.x) } }

    func tinted(values: [Float]? = nil, isGhost: Bool = false) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        frame.items[0].isGhost = isGhost
        frame.items[0].fieldValues = values
        frame.items[0].fieldRamp = values == nil ? nil : Self.ramp
        return frame
    }

    // MARK: Field tint

    @Test func theFrontFaceTakesTheRampLeftToRight() async throws {
        let bytes = try await Rig().draw(tinted(values: xValues))
        let left = Rig.color(bytes, 80, 100), middle = Rig.color(bytes, 100, 100), right = Rig.color(bytes, 120, 100)
        #expect(left[0] > left[1] + 40 && left[0] > left[2] + 60, "red towards x = −5: \(left)")
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green in the middle: \(middle)")
        #expect(right[2] > right[0] + 60 && right[2] > right[1] + 40, "blue towards x = 5: \(right)")
    }

    @Test func valuesOfTheWrongCountOrNoneDrawThePlainSurfaceAndAGhostIsNeverTinted() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(tinted())
        #expect(plain != (try await rig.draw(tinted(values: xValues))), "the tint changes the pixels")
        #expect(try await rig.draw(tinted(values: [1, 2, 3])) == plain)
        #expect(try await rig.draw(tinted(values: [])) == plain)
        #expect(try await rig.draw(tinted(values: xValues, isGhost: true)) == (try await rig.draw(tinted(isGhost: true))))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleOfTheRamp() async throws {
        let nothing = [Float](repeating: .nan, count: Self.mesh.positions.count)
        let middle = Rig.color(try await Rig().draw(tinted(values: nothing)), 100, 100)
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green: \(middle)")
    }

    @Test func theValueBufferIsKeptUntilTheValuesChange() async throws {
        let rig = try Rig()
        try await rig.draw(tinted(values: xValues))
        try await rig.draw(tinted(values: xValues))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 1, "the same values: one upload")
        try await rig.draw(tinted(values: xValues.map { $0 * 0.5 }))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2)
        try await rig.draw(tinted())
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2, "a plain frame uploads nothing")
    }

    // MARK: Guides

    func guideFrame(withGuide guide: DisplayMesh?) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        if let guide {
            frame.items.append(FrameItem(meshSerial: 2, mesh: guide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                         selectedFaces: [], selectedEdges: Set(guide.edgePolylines.keys), isGuide: true))
        }
        return frame
    }

    @Test func aGuidesEdgesDrawInTheSelectionColourOverEmptySpaceAndItsSurfacesDoNot() async throws {
        let rig = try Rig()
        let wide = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(15, 10, 30)))
        let with = try await rig.draw(guideFrame(withGuide: wide))
        let without = try await rig.draw(guideFrame(withGuide: nil))
        // The guide spans x −15…15 mm: its left edges are at view x = 25, clear of the part (x 75…125).
        let edge = Rig.color(with, 25, 100)
        #expect(edge[0] > 200 && edge[2] > 150 && edge[1] < 170, "pink: \(edge)")
        #expect(Rig.color(without, 25, 100)[0] < 100, "the dark background")
        #expect(Rig.color(with, 40, 100) == Rig.color(without, 40, 100), "inside the guide, off its edges: no surface is drawn")
        // The guide's top front edge runs along the part's, at view y = 25, between x = 75 and 125.
        #expect(Rig.color(without, 100, 25)[1] > 230, "the part's own edge is white")
        let covered = Rig.color(with, 100, 25)
        #expect(covered[0] > 200 && covered[1] < 170, "and the guide's edge glows over it: \(covered)")
    }

    @Test func anEdgeBehindThePartShowsFaintlyThroughIt() async throws {
        let rig = try Rig()
        let inside = TestMeshes.box(BoundingBox(min: Vector3(-2, -2, 0), max: Vector3(2, 2, 10)))
        let with = try await rig.draw(guideFrame(withGuide: inside))
        let without = try await rig.draw(guideFrame(withGuide: nil))
        // The guide's left edges are at view x = 90, 8 mm behind the part's front face.
        let seen = Rig.color(with, 90, 150), plain = Rig.color(without, 90, 150)
        #expect(seen[1] < plain[1] - 10, "pinker than the part's face: \(seen) against \(plain)")
        #expect(seen[1] > 121, "but fainter than the selection pink (green 121): \(seen)")
        #expect(Rig.color(with, 100, 100) == Rig.color(without, 100, 100), "the part's face between the edges is as before")
    }

    // MARK: Cut view

    func clipFrame(clip: ViewportClip? = nil, warning: Set<FaceID> = [], empty: Bool = false) -> ViewportFrame {
        var frame = RenderFixtures.boxFrame()
        if empty { frame.items = [] }
        frame.clip = clip
        if !frame.items.isEmpty { frame.items[0].warningFaces = warning }
        return frame
    }

    /// Cuts away everything at y below `y` (the near half of the box seen from the front for y = 0).
    func nearSide(_ y: Double) -> ViewportClip { ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0)) }

    @Test func aPlaneBehindThePartCutsNothingAndCuttingTheNearHalfShowsTheInsideOfTheFarWallDarkened() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(clipFrame())
        #expect(try await rig.draw(clipFrame(clip: nearSide(-50))) == plain)
        let cut = try await rig.draw(clipFrame(clip: nearSide(0)))
        let palette = ViewportPalette.dracula
        let expected = Rig.bytes((palette.shadeDark + palette.shadeLight) * 0.5 * 0.55)
        let inside = Rig.color(cut, 100, 100)
        #expect(inside != Rig.color(plain, 100, 100))
        for channel in 0..<3 { #expect(abs(inside[channel] - expected[channel]) <= 3, "\(inside) against \(expected)") }
        #expect(Rig.color(cut, 30, 100) == Rig.color(plain, 30, 100), "beside the part nothing changes")
    }

    @Test func cuttingEverythingDrawsWhatAnEmptySceneDraws() async throws {
        let rig = try Rig()
        #expect(try await rig.draw(clipFrame(clip: nearSide(100))) == (try await rig.draw(clipFrame(empty: true))),
                "the faces and the edges both go")
    }
}
#endif
```

`Tests/CreatorViewportTests/SDLRenderTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The main pass on SDL_GPU, as the Metal one in `OffscreenRenderTests`: pixels read back from a 400 × 400 target at 2 pixels per
/// point. `RenderFixtures`' front view (orthographic, 5 points per mm) puts a 10 × 20 × 30 box at view x 75…125, y 25…175. The
/// colours are far apart (a lavender-grey surface, the white edges, the dark background), so the tests compare regions and
/// palette colours with a margin, never exact pixels.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLRenderTests {
    typealias Rig = SDLRenderRig
    let palette = ViewportPalette.dracula

    /// How many pixels of view row `row` (x 5…194) are not `colour`.
    static func pixelsDiffering(from colour: [Int], inRow row: Int, of bytes: [UInt8]) -> Int {
        (5..<195).count { Rig.color(bytes, $0, row) != colour }
    }

    @Test func theBackgroundIsAGradientFromTheTopColourToTheBottomOne() async throws {
        let rig = try Rig()
        let bytes = try await rig.draw(RenderFixtures.emptyFrame())
        let top = Rig.color(bytes, 100, 1), bottom = Rig.color(bytes, 100, 198)
        let expectedTop = Rig.bytes(palette.backgroundTop), expectedBottom = Rig.bytes(palette.backgroundBottom)
        for channel in 0..<3 {
            #expect(abs(top[channel] - expectedTop[channel]) <= 4, "top \(top) against \(expectedTop)")
            #expect(abs(bottom[channel] - expectedBottom[channel]) <= 4, "bottom \(bottom) against \(expectedBottom)")
        }
    }

    @Test func aSolidIsDrawnWhereItStandsAndTheBackgroundIsLeftAroundIt() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let boxed = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(boxed, 100, 100) != Rig.color(plain, 100, 100), "the front face covers the middle")
        let face = Rig.color(boxed, 85, 100)
        #expect(abs(face[0] - face[2]) < 60 && face[0] > 60, "a lavender grey, lit: \(face)")
        #expect(Rig.color(boxed, 30, 100) == Rig.color(plain, 30, 100), "left of the part nothing changes")
        #expect(Rig.color(boxed, 170, 100) == Rig.color(plain, 170, 100), "right of the part nothing changes")
        #expect(Rig.color(boxed, 100, 190) == Rig.color(plain, 100, 190), "below the part nothing changes")
    }

    @Test func theBoxSitsWhereTheCameraPutsItTopEdgeUp() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let boxed = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(boxed, 100, 30) != Rig.color(plain, 100, 30), "just inside the top edge (view y 25)")
        #expect(Rig.color(boxed, 100, 20) == Rig.color(plain, 100, 20), "just above it")
        #expect(Rig.color(boxed, 100, 170) != Rig.color(plain, 100, 170), "just inside the bottom edge (view y 175)")
        #expect(Rig.color(boxed, 100, 180) == Rig.color(plain, 100, 180), "just below it")
    }

    @Test func edgesDrawOverTheSolidInTheEdgeColourAndShadedModeKeepsOnlyTheSelectedOnes() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let edge = try await rig.draw(frame)
        #expect(Rig.color(edge, 100, 25)[1] > 230, "the top front edge is white: \(Rig.color(edge, 100, 25))")
        frame.shading = .shaded
        let shaded = try await rig.draw(frame)
        #expect(Rig.color(shaded, 100, 25)[1] < 200, "Shaded draws no edges: \(Rig.color(shaded, 100, 25))")
        frame.items[0].selectedEdges = [EdgeID(1)]
        let selected = try await rig.draw(frame)
        let pink = Rig.color(selected, 100, 25)
        #expect(pink[0] > 200 && pink[2] > 150 && pink[1] < 170, "a rule's edge still shows, in the selection pink: \(pink)")
    }

    @Test func hoverSelectionAndWarningTintTheFaceTheyNameAndNoOther() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.boxFrame())
        var hovered = RenderFixtures.boxFrame()
        hovered.items[0].hoveredFace = FaceID(2)
        var selected = RenderFixtures.boxFrame()
        selected.items[0].selectedFaces = [FaceID(2)]
        var warned = RenderFixtures.boxFrame()
        warned.items[0].warningFaces = [FaceID(2)]
        let before = Rig.color(plain, 100, 100)
        let hover = Rig.color(try await rig.draw(hovered), 100, 100)
        let pick = Rig.color(try await rig.draw(selected), 100, 100)
        let warn = Rig.color(try await rig.draw(warned), 100, 100)
        #expect(hover != before && hover[1] >= before[1] && hover[2] >= before[2], "cyan creeps in: \(hover) from \(before)")
        #expect(pick[0] > before[0] + 30 && pick[1] < hover[1] + 40, "pink: \(pick) from \(before)")
        let warning = Rig.bytes(palette.warning)
        func distance(_ c: [Int]) -> Int { (0..<3).map { abs(c[$0] - warning[$0]) }.reduce(0, +) }
        #expect(distance(warn) < distance(before) / 2, "the warning colour: \(warn) against \(warning) and \(before)")
        let other = try await rig.draw(selected)
        #expect(Rig.color(other, 30, 100) == Rig.color(plain, 30, 100), "off the part nothing changes")
    }

    @Test func aGhostIsDimmedAndBlendedOverWhatIsBehindIt() async throws {
        let rig = try Rig()
        var ghost = RenderFixtures.boxFrame()
        ghost.items[0].isGhost = true
        let solid = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 85, 100)
        let ghostly = Rig.color(try await rig.draw(ghost), 85, 100)
        let background = Rig.color(try await rig.draw(RenderFixtures.emptyFrame()), 85, 100)
        #expect(ghostly != solid && ghostly != background)
        for channel in 0..<3 {
            let low = min(solid[channel], background[channel]) - 30, high = max(solid[channel], background[channel]) + 30
            #expect((low...high).contains(ghostly[channel]), "the 40% ghost lies between the part and the background: \(ghostly)")
        }
    }

    // MARK: Meshes at the extremes

    /// A Mesh node can come out empty (a scatter of nothing, a failed mesh) or bare of edges; neither may trap, and what is there draws.
    @Test func aMeshWithNoTrianglesOrNoEdgesDrawsWhatItHasAndDoesNotTrap() async throws {
        let rig = try Rig()
        let background = try await rig.draw(RenderFixtures.emptyFrame())
        var nothing = RenderFixtures.boxFrame()
        nothing.items[0].mesh = DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [], edgePolylines: [:])
        #expect(try await rig.draw(nothing) == background, "a mesh with no triangles draws nothing")
        let box = TestMeshes.box(RenderFixtures.bounds)
        var bare = RenderFixtures.boxFrame()
        bare.items[0].mesh = DisplayMesh(positions: box.positions, normals: box.normals, indices: box.indices,
                                         triangleFaces: box.triangleFaces, edgePolylines: [:])
        bare.items[0].meshSerial = 3
        let drawn = try await rig.draw(bare)
        #expect(Rig.color(drawn, 100, 100) != Rig.color(background, 100, 100), "the faces draw")
        #expect(Rig.color(drawn, 100, 25)[1] < 200, "and there is no white edge on the top: \(Rig.color(drawn, 100, 25))")
    }

    /// 7c's previews run to millions of triangles; a hundred thousand is a quick test of the same path (3 × 100,352 corners at 48 bytes).
    @Test func aLargeMeshDrawsAndKeepsAllItsCorners() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        frame.items[0].mesh = TestMeshes.sheet(RenderFixtures.bounds, columns: 224, rows: 224)
        frame.items[0].meshSerial = 4
        let drawn = try await rig.draw(frame)
        #expect(rig.renderer.meshes[4]?.vertexCount == 3 * 2 * 224 * 224)
        let background = try await rig.draw(RenderFixtures.emptyFrame())
        #expect(Rig.color(drawn, 100, 100) != Rig.color(background, 100, 100), "the sheet covers the middle")
        #expect(Rig.color(drawn, 30, 100) == Rig.color(background, 30, 100), "and only that")
    }

    /// Edge and overlay buffers bake the theme's colours in; a theme change must rebuild them, not draw the old colours.
    @Test func aNewPaletteRebuildsTheCachedEdgesInItsColours() async throws {
        let rig = try Rig()
        let before = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 100, 25)
        var light = RenderFixtures.boxFrame()
        light.palette = ViewportPalette(.alucard)
        let after = Rig.color(try await rig.draw(light), 100, 25)
        let alucardEdge = Rig.bytes(ViewportPalette(.alucard).edge)
        func distance(_ colour: [Int]) -> Int { (0..<3).map { abs(colour[$0] - alucardEdge[$0]) }.reduce(0, +) }
        #expect(after != before)
        #expect(distance(after) < distance(before), "nearer the light theme's edge colour \(alucardEdge): \(after) from \(before)")
    }

    @Test func aTargetOfTheWrongFormatOrAnEmptyViewIsLeftAlone() async throws {
        let rig = try Rig()
        let rgba = try #require(rig.device.makeTexture(SDLGPUTextureDescription(
            width: 8, height: 8, format: .r8g8b8a8Unorm, usage: [.colorTarget])))
        let boxed = Handoff(value: RenderFixtures.boxFrame())
        let renderer = rig.renderer
        var fence = try await rig.device.submitBatch { commandBuffer in
            renderer.encode(boxed.value, into: rgba, scale: 1, commandBuffer: commandBuffer)
        }
        await fence.wait()
        #expect(renderer.encodedPasses == 0, "a target in another format")
        var empty = RenderFixtures.boxFrame()
        empty.size = ViewportSize(width: 0, height: 0)
        let emptyBoxed = Handoff(value: empty)
        let target = rig.target
        fence = try await rig.device.submitBatch { commandBuffer in
            renderer.encode(emptyBoxed.value, into: target, scale: 1, commandBuffer: commandBuffer)
        }
        await fence.wait()
        #expect(renderer.encodedPasses == 0, "a view with no size")
        _ = try await rig.draw(RenderFixtures.boxFrame())
        #expect(renderer.encodedPasses == 1)
    }

    @Test func theGroundGridDrawsLinesOnTheGroundAndNotWhenTheOverlayHasAGridOfItsOwn() async throws {
        let rig = try Rig()
        var looking = RenderFixtures.emptyFrame()
        looking.pose = CameraPose(target: .zero, distance: 40 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: -.pi / 2,
                                  projection: .orthographic)
        let withGrid = try await rig.draw(looking)
        let differing = Self.pixelsDiffering(from: Rig.color(withGrid, 12, 112), inRow: 112, of: withGrid)
        #expect(differing >= 3, "grid lines cross a row of a view straight down: \(differing) pixels differ from the gap between them")
        looking.overlay = ViewportOverlay(gridPlane: .xy)
        let overlayGrid = try await rig.draw(looking)
        #expect(overlayGrid != withGrid, "a plane grid in the overlay replaces the ground grid")
    }

    @Test func aFilledOverlayTrianglesTintsThePixelsItCoversAndNoOthers() async throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let filled = try await rig.draw(RenderFixtures.emptyFrame(overlay: ViewportOverlay(fills: [fill])))
        let inside = zip(Rig.color(plain, 100, 100), Rig.color(filled, 100, 100)).map { abs($0 - $1) }
        #expect(inside.contains { $0 >= 3 }, "the view's centre is inside the triangle: \(inside)")
        #expect(Rig.color(plain, 20, 190) == Rig.color(filled, 20, 190), "a corner far from it is untouched")
    }

    @Test func anOverlayLineAndAHandleDrawOverTheScene() async throws {
        let rig = try Rig()
        let plain = try await rig.draw(RenderFixtures.emptyFrame())
        let line = OverlayLine(Vector3(-10, 0, 15), Vector3(10, 0, 15), tint: .construction, isDashed: false)
        let overlay = try await rig.draw(RenderFixtures.emptyFrame(overlay: ViewportOverlay(lines: [line])))
        #expect(Rig.color(overlay, 100, 100) != Rig.color(plain, 100, 100), "the line runs through the middle")
        #expect(Rig.color(overlay, 100, 160) == Rig.color(plain, 100, 160), "and not below it")
        var handled = RenderFixtures.emptyFrame()
        handled.handles = [ViewportHandle(id: "h", anchor: Vector3(0, 0, 0), direction: .unitZ, value: 20, range: 0...50,
                                          style: .linear, tint: .solid),
        ]
        let handle = try await rig.draw(handled)
        #expect(Rig.color(handle, 100, 100) != Rig.color(plain, 100, 100), "the shaft crosses the middle")
        #expect(Rig.color(handle, 100, 75) != Rig.color(plain, 100, 75), "and the knob sits 20 mm up (view y 75)")
        #expect(Rig.color(handle, 100, 40) == Rig.color(plain, 100, 40), "with nothing above it")
    }

    @Test func aLightPaletteChangesWhatIsDrawn() async throws {
        let rig = try Rig()
        var light = RenderFixtures.boxFrame()
        light.palette = ViewportPalette(.alucard)
        let dark = Rig.color(try await rig.draw(RenderFixtures.boxFrame()), 85, 100)
        #expect(Rig.color(try await rig.draw(light), 85, 100) != dark)
    }

    // MARK: Buffers are kept between frames

    @Test func theOverlayHandleAndFillBuffersSurviveAnOrbitAndAreReleasedWhenTheirContentGoes() async throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let line = OverlayLine(.zero, Vector3(10, 0, 10), tint: .construction, isDashed: true)
        var frame = RenderFixtures.emptyFrame(overlay: ViewportOverlay(lines: [line], fills: [fill], gridPlane: .xz))
        frame.handles = [ViewportHandle(id: "h", anchor: .zero, direction: .unitZ, value: 20, range: 0...50, style: .linear, tint: .solid)]
        try await rig.draw(frame)
        let overlay = try #require(rig.renderer.overlayBuffer), fills = try #require(rig.renderer.fillBuffer)
        let handles = try #require(rig.renderer.handleBuffer)
        frame.pose.yaw += 0.2
        try await rig.draw(frame)
        #expect(try #require(rig.renderer.overlayBuffer).buffer === overlay.buffer, "an orbit rebuilds nothing the zoom did not change")
        #expect(try #require(rig.renderer.fillBuffer).buffer === fills.buffer)
        #expect(try #require(rig.renderer.handleBuffer).buffer === handles.buffer)
        frame.pose.distance *= 2
        try await rig.draw(frame)
        #expect(try #require(rig.renderer.overlayBuffer).buffer !== overlay.buffer, "dashes and reach follow the zoom")
        try await rig.draw(RenderFixtures.emptyFrame())
        #expect(rig.renderer.fillBuffer == nil, "leaving sketch mode frees the fills")
    }

    @Test func aReusedRendererDrawsThePixelsAFreshOneDoes() async throws {
        let reused = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        var frame = RenderFixtures.boxFrame()
        frame.overlay = ViewportOverlay(fills: [fill])
        try await reused.draw(frame)
        frame.pose.yaw += 0.2
        let fromReused = try await reused.draw(frame)
        let fromFresh = try await Rig().draw(frame)
        #expect(fromReused == fromFresh)
    }
}
#endif
```

`Tests/CreatorViewportTests/Support/RenderFixtures.swift` (new):

```swift
// Test fixture file: the camera and frames the renderer tests share (the SDL ones run without OpenCascade).
import CreatorGeometry
import CreatorKernel
import Foundation
@testable import CreatorViewport

enum RenderFixtures {
    /// Front view, orthographic, 5 points per mm, centred on (0, 0, 15). A 10 × 20 × 30 box standing on z = 0 fills x 75…125 and
    /// y 25…175 of a 200 × 200 view.
    static let front = CameraPose(target: Vector3(0, 0, 15), distance: 20 / tan(CameraPose.fieldOfView / 2),
                                  yaw: 0, pitch: 0, projection: .orthographic)
    static let size = ViewportSize(width: 200, height: 200)
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))

    /// The box of ``bounds`` (`TestMeshes.box`: faces 0 bottom, 1 top, 2 front, 3 right, 4 back, 5 left) in the front view.
    static func boxFrame() -> ViewportFrame {
        TestFrames.frame(mesh: TestMeshes.box(bounds), pose: front, size: size, bounds: bounds)
    }

    /// A frame with nothing in it, in the front view.
    static func emptyFrame(overlay: ViewportOverlay = ViewportOverlay()) -> ViewportFrame {
        ViewportFrame(pose: front, size: size, sceneBounds: nil, items: [], shading: .shadedEdges, gridSpacing: 10, handles: [],
                      cube: ViewCubeLayout(), hoveredCubeRegion: nil, triad: TriadLayout(), overlay: overlay)
    }
}
```

`Tests/CreatorViewportTests/Support/SDLRenderRig.swift` (new):

```swift
// Test fixture file: a renderer and a target to draw into, and the pixels back.
#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// A renderer and a 400 × 400 target (2 pixels per point, as the 200 × 200 point frames of `RenderFixtures` need).
@MainActor
final class SDLRenderRig {
    static let pixels = 400
    let device: SDLGPUDevice
    let renderer: SDLViewportRenderer
    let target: SDLGPUTexture

    init() throws {
        guard let device = SDLTestDevice.shared, let pipelines = SDLTestDevice.pipelines else {
            throw SDLRigError(description: "no SDL_GPU device: \(SDLGPUDevice.lastFailure)")
        }
        self.device = device
        renderer = SDLViewportRenderer(device: device, pipelines: pipelines)
        guard let target = device.makeTexture(SDLGPUTextureDescription(
            width: Self.pixels, height: Self.pixels, format: .b8g8r8a8Unorm, usage: [.colorTarget, .sampler])) else {
            throw SDLRigError(description: "the target texture could not be made")
        }
        self.target = target
    }

    /// Draws `frame` (`scale` pixels per point) in a batch, waits for the GPU and reads the target back as BGRA bytes.
    @discardableResult
    func draw(_ frame: ViewportFrame, scale: Double = 2) async throws -> [UInt8] {
        let boxed = Handoff(value: frame)
        let renderer = renderer
        let target = target
        let fence = try await device.submitBatch { commandBuffer in
            renderer.encode(boxed.value, into: target, scale: scale, commandBuffer: commandBuffer)
        }
        await fence.wait()
        guard let bytes = await device.download(target) else { throw SDLRigError(description: "the target could not be read back") }
        return bytes
    }

    /// The colour at view point (`x`, `y`) of a 400 × 400 draw at 2 pixels per point, as red, green and blue.
    static func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * pixels + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    /// A palette colour as the bytes the target holds: red, green, blue.
    static func bytes(_ colour: SIMD4<Float>) -> [Int] {
        [colour.x, colour.y, colour.z].map { Int(($0 * 255).rounded()) }
    }
}
#endif
```

`Tests/CreatorViewportTests/Support/TestMeshes+Sheet.swift` (new):

```swift
// Test fixture file: a big flat mesh for the renderer tests.
import CreatorGeometry
import CreatorKernel

extension TestMeshes {
    /// A sheet of `columns` × `rows` quads (two triangles each, 2 × `columns` × `rows` triangles) facing the front (−Y), filling
    /// `bounds`' x and z at `bounds.min.y`. One face (0), no edges.
    static func sheet(_ bounds: BoundingBox, columns: Int, rows: Int) -> DisplayMesh {
        var positions: [Vector3] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            for column in 0...columns {
                positions.append(Vector3(bounds.min.x + (bounds.max.x - bounds.min.x) * Double(column) / Double(columns), bounds.min.y,
                                         bounds.min.z + (bounds.max.z - bounds.min.z) * Double(row) / Double(rows)))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(columns * rows * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let corner = UInt32(row * (columns + 1) + column)
                let across = UInt32(columns + 1)
                indices += [corner, corner + 1, corner + across + 1, corner, corner + across + 1, corner + across]
            }
        }
        return DisplayMesh(positions: positions, normals: Array(repeating: Vector3(0, -1, 0), count: positions.count), indices: indices,
                           triangleFaces: Array(repeating: FaceID(0), count: indices.count / 3), edgePolylines: [:])
    }
}
```

- [ ] **Step 2: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. Linux: `cannot find 'SDLViewportRenderer' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Everything one main pass draws, with every GPU buffer already made and filled. A copy pass cannot run inside a render pass,
/// so the renderer plans the frame first (`SDLViewportRenderer.plan`) and then records the pass from the plan.
struct SDLFramePlan {
    /// A solid: its triangles, its face flags, and the tint when it has one.
    struct Solid {
        var vertices: SDLGPUBuffer
        var vertexCount: Int
        var flags: SDLGPUBuffer
        var faceCount: Int
        var tint: (values: SDLGPUBuffer, ramp: FieldRampUniforms)?
    }

    /// Line instances to draw in one instanced call, the cut view's plane they are clipped by, and their style.
    struct Lines {
        var buffer: SDLGPUBuffer
        var count: Int
        var style: LineUniforms
        var clip: ClipUniforms = .off
    }

    var opaque: [Solid] = []
    var ghosts: [Solid] = []
    var edges: [Lines] = []
    var guides: [Lines] = []
    /// A guide's faded edges, drawn only where the part hides them.
    var hiddenGuides: [Lines] = []
    var fills: (buffer: SDLGPUBuffer, count: Int)?
    var overlay: Lines?
    var handles: Lines?
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

extension SDLViewportRenderer {
    /// Makes every buffer the main pass reads and records the copies that fill them (`commandBuffer` is the uploader's). The layers
    /// are the Metal renderer's, in the order it draws them: solids, edges, guides, overlay, handles.
    func plan(_ frame: ViewportFrame, scale: Float, uploader: SDLViewportUploader) -> SDLFramePlan {
        prepareMeshes(for: frame, uploader)
        var plan = SDLFramePlan()
        let clip = ClipUniforms(frame.clip)
        for item in frame.items where !item.isGuide {
            guard let solid = solid(of: item, uploader) else { continue }
            if item.isGhost { plan.ghosts.append(solid) } else { plan.opaque.append(solid) }
        }
        // B-rep edges of opaque solids. "Shaded" mode still shows the edges a rule selected.
        let edgeStyle = LineUniforms(widthOverride: 0, depthBias: Float(Self.edgeDepthBias(frame)), padding0: 0, padding1: 0)
        let selectedOnly = frame.shading == .shaded
        for item in frame.items where !item.isGhost && !item.isGuide && (!selectedOnly || !item.selectedEdges.isEmpty) {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: selectedOnly, scale: scale)
            guard let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, uploader: uploader) else { continue }
            plan.edges.append(SDLFramePlan.Lines(buffer: edges.buffer, count: edges.count, style: edgeStyle, clip: clip))
        }
        // A guide's selected edges, over the solids; and again faded where the part hides them.
        for item in frame.items where item.isGuide && !item.selectedEdges.isEmpty {
            let key = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale)
            if let edges = meshes[item.meshSerial]?.edges(key, palette: frame.palette, uploader: uploader) {
                plan.guides.append(SDLFramePlan.Lines(buffer: edges.buffer, count: edges.count, style: edgeStyle))
            }
            let hiddenKey = EdgeInstanceKey(solid: item.solidIndex, selected: item.selectedEdges, selectedOnly: true, scale: scale,
                                            hidden: true)
            if let faded = meshes[item.meshSerial]?.edges(hiddenKey, palette: frame.palette, uploader: uploader) {
                plan.hiddenGuides.append(SDLFramePlan.Lines(buffer: faded.buffer, count: faded.count, style: edgeStyle))
            }
        }
        plan.fills = fillVertices(for: frame, uploader)
        plan.overlay = overlayInstances(for: frame, scale: scale, uploader).map {
            SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
        }
        plan.handles = handleInstances(for: frame, scale: scale, uploader).map {
            SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
        }
        return plan
    }

    static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)

    /// `item` as a plan entry: its triangles, its face flags and, for an opaque item with a tint to show (fields spec §6), the field's
    /// values and ramp. `nil` when the mesh has no triangles.
    private func solid(of item: FrameItem, _ uploader: SDLViewportUploader) -> SDLFramePlan.Solid? {
        guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer,
              let flags = gpu.faceFlags(hovered: item.hoveredFace, selected: item.selectedFaces, warning: item.warningFaces,
                                        uploader: uploader) else { return nil }
        var tint: (values: SDLGPUBuffer, ramp: FieldRampUniforms)?
        if !item.isGhost, let values = item.fieldValues, let ramp = item.fieldRamp,
           let buffer = gpu.fieldValues(values, mesh: item.mesh, ramp: ramp, uploader: uploader) {
            tint = (buffer, FieldRampUniforms(ramp))
        }
        return SDLFramePlan.Solid(vertices: vertices, vertexCount: gpu.vertexCount, flags: flags, faceCount: gpu.faceCount, tint: tint)
    }

    /// The frame's handles in its palette, kept until the handles, the scale or the palette change.
    private func handleInstances(for frame: ViewportFrame, scale: Float,
                                 _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = handleBuffer, cached.handles == frame.handles, cached.scale == scale, cached.palette == frame.palette {
            return (cached.buffer, cached.count)
        }
        let instances = GPUGeometry.handleInstances(frame.handles, scale: scale, palette: frame.palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            handleBuffer = nil
            return nil
        }
        handleBuffer = CachedHandles(handles: frame.handles, scale: scale, palette: frame.palette, buffer: buffer, count: instances.count)
        return (buffer, instances.count)
    }

    /// The frame's fill triangles in its palette, kept until the fills or the palette change.
    private func fillVertices(for frame: ViewportFrame, _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        guard !frame.overlay.fills.isEmpty else {
            fillBuffer = nil
            return nil
        }
        let key = FillBufferKey(fills: frame.overlay.fills, palette: frame.palette)
        if let cached = fillBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let vertices = OverlayGeometry.fillVertices(frame.overlay.fills, palette: frame.palette)
        guard let buffer = uploader.storageBuffer(vertices) else {
            fillBuffer = nil
            return nil
        }
        fillBuffer = (key, buffer, vertices.count)
        return (buffer, vertices.count)
    }

    /// The frame's overlay in its palette, kept until what the instances are built from changes: the overlay, the scale, the palette,
    /// and the camera only as far as it reaches them (where the plane grid is centred and how far it reaches, and the zoom the dashes
    /// are cut at). An orbit, or a pan inside one grid cell, reuses the buffer.
    private func overlayInstances(for frame: ViewportFrame, scale: Float,
                                  _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        guard !frame.overlay.isEmpty else { return nil }
        let grid = frame.overlay.gridPlane.flatMap {
            OverlayGeometry.gridExtent(on: $0, pose: frame.pose, size: frame.size, spacing: frame.gridSpacing)
        }
        let dashZoom = frame.overlay.lines.contains(where: \.isDashed)
            ? CameraMath.millimetresPerPoint(frame.pose, size: frame.size) : nil
        let key = OverlayBufferKey(overlay: frame.overlay, grid: grid, dashZoom: dashZoom, scale: scale, palette: frame.palette)
        if let cached = overlayBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let instances = OverlayGeometry.instances(frame.overlay, grid: grid, millimetresPerPoint: dashZoom ?? 1, scale: scale,
                                                  palette: frame.palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            overlayBuffer = nil
            return nil
        }
        overlayBuffer = (key, buffer, instances.count)
        return (buffer, instances.count)
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// A render pass that pushes the frame's camera (vertex uniform slot 0 of every pipeline that reads it) each time it binds a
/// pipeline, so no draw depends on what an earlier pipeline left in the slot.
struct SDLPassRecorder {
    let pass: SDLGPURenderPass
    let camera: [UInt8]

    func bind(_ pipeline: SDLGPUGraphicsPipeline) {
        pass.bind(pipeline)
        pass.pushVertexUniform(camera, at: 0)
    }
}

extension SDLViewportRenderer {
    /// Records the main pass from `plan`, in the Metal renderer's order: the background gradient, opaque solids, the ground grid
    /// (unless the overlay has a plane grid of its own), B-rep edges, ghosts, guides, the overlay's fills, lines and points, handles.
    func record(_ plan: SDLFramePlan, _ frame: ViewportFrame, _ uniforms: FrameUniforms, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(uniforms))
        drawBackground(frame.palette, in: pass)
        let shade = ShadeUniforms(frame.palette)
        let clip = ClipUniforms(frame.clip)
        drawSolids(plan.opaque, ghosts: false, shade: shade, clip: clip, in: recorder)
        if frame.overlay.gridPlane == nil { drawGrid(frame, in: recorder) }
        for edges in plan.edges { drawLines(edges, pipeline: pipelines.lineTest, in: recorder) }
        drawSolids(plan.ghosts, ghosts: true, shade: shade, clip: clip, in: recorder)
        for guide in plan.guides { drawLines(guide, pipeline: pipelines.lineTest, in: recorder) }
        for faded in plan.hiddenGuides { drawLines(faded, pipeline: pipelines.lineBehind, in: recorder) }
        if let fills = plan.fills { drawFills(fills, in: recorder) }
        if let overlay = plan.overlay { drawLines(overlay, pipeline: pipelines.lineAlways, in: recorder) }
        if let handles = plan.handles { drawLines(handles, pipeline: pipelines.lineAlways, in: recorder) }
    }

    /// The background gradient, drawn first and ignoring depth.
    private func drawBackground(_ palette: ViewportPalette, in pass: SDLGPURenderPass) {
        let colors = BackgroundUniforms(top: palette.backgroundTop, bottom: palette.backgroundBottom)
        pass.bind(pipelines.background)
        pass.pushFragmentUniform(uniformBytes(colors), at: 0)
        pass.draw(vertexCount: 3)
    }

    /// Opaque solids, or ghosts (blended, tested against what is already there). A solid with a tint draws with the field pipeline.
    private func drawSolids(_ solids: [SDLFramePlan.Solid], ghosts: Bool, shade: ShadeUniforms, clip: ClipUniforms,
                            in recorder: SDLPassRecorder) {
        let pass = recorder.pass
        for solid in solids {
            let draw = DrawUniforms(pickBase: 0, ghost: ghosts ? 1 : 0, faceCount: UInt32(solid.faceCount), padding: 0)
            if let tint = solid.tint {
                recorder.bind(pipelines.fieldMesh)
                pass.pushFragmentUniform(uniformBytes(shade), at: 0)
                pass.pushFragmentUniform(uniformBytes(tint.ramp), at: 1)
                pass.pushFragmentUniform(uniformBytes(clip), at: 2)
                pass.bindVertexStorageBuffers([solid.vertices, solid.flags, tint.values])
            } else {
                recorder.bind(ghosts ? pipelines.ghost : pipelines.mesh)
                pass.pushFragmentUniform(uniformBytes(draw), at: 0)
                pass.pushFragmentUniform(uniformBytes(shade), at: 1)
                pass.pushFragmentUniform(uniformBytes(clip), at: 2)
                pass.bindVertexStorageBuffers([solid.vertices, solid.flags])
            }
            pass.pushVertexUniform(uniformBytes(draw), at: 1)
            pass.draw(vertexCount: solid.vertexCount)
        }
    }

    private func drawGrid(_ frame: ViewportFrame, in recorder: SDLPassRecorder) {
        let grid = uniformBytes(GPUGeometry.gridUniforms(frame))
        recorder.bind(pipelines.grid)
        recorder.pass.pushVertexUniform(grid, at: 1)
        recorder.pass.pushFragmentUniform(grid, at: 0)
        recorder.pass.draw(vertexCount: 4)
    }

    /// Instanced line quads, four vertices as a strip per instance.
    private func drawLines(_ lines: SDLFramePlan.Lines, pipeline: SDLGPUGraphicsPipeline, in recorder: SDLPassRecorder) {
        guard lines.count > 0 else { return }
        recorder.bind(pipeline)
        recorder.pass.bindVertexStorageBuffers([lines.buffer])
        recorder.pass.pushVertexUniform(uniformBytes(lines.style), at: 1)
        recorder.pass.pushFragmentUniform(uniformBytes(lines.clip), at: 0)
        recorder.pass.draw(vertexCount: 4, instanceCount: lines.count)
    }

    private func drawFills(_ fills: (buffer: SDLGPUBuffer, count: Int), in recorder: SDLPassRecorder) {
        recorder.bind(pipelines.fill)
        recorder.pass.bindVertexStorageBuffers([fills.buffer])
        recorder.pass.draw(vertexCount: fills.count)
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import MetalUISDLGPU

/// Draws a `ViewportFrame` with SDL_GPU (cross-platform spec section 4): the Metal `ViewportRenderer`'s passes, in the same
/// order, over the shaders in `Shaders/viewport`.
/// - The main pass draws the background gradient, opaque solids, the ground grid, B-rep edges, ghosts, guides' selected edges,
///   the overlay's fills, lines and points, and handles. It renders into its own 4× MSAA colour and depth targets, resolved into
///   the target it is given (a `GPUSurface`'s, `bgra8Unorm`).
/// - The ID pass (`SDLViewportRenderer+IDPass`) writes `PickID`s into an `r32Uint` target.
/// GPU meshes are cached by mesh serial and dropped once a frame no longer shows them; the buffers that bake colours in are rebuilt
/// when the palette changes. It records into the command buffer it is given and never submits it.
///
/// Threads: it is not main-actor isolated, because a test records into a batch's command buffer on the device's worker thread
/// (`SDLGPUDevice.submitBatch`). It keeps state, so it is used from one thread at a time: the main actor in the app. The ID pass reads
/// none of it while it runs on the worker (`SDLIDPassInputs`).
final class SDLViewportRenderer: @unchecked Sendable {
    /// The handles' line instances and what they were built from.
    struct CachedHandles {
        var handles: [ViewportHandle]
        var scale: Float
        var palette: ViewportPalette
        var buffer: SDLGPUBuffer
        var count: Int
    }

    let device: SDLGPUDevice
    let pipelines: SDLViewportPipelines
    private(set) var meshes: [Int: SDLViewportMesh] = [:]
    private var multisample: (width: Int, height: Int, color: SDLGPUTexture, depth: SDLGPUTexture)?
    /// The handles' instances, kept until the handles, the scale or the palette change, so a frame of a continuous orbit makes no
    /// buffers (spec §7.3's 60 fps).
    var handleBuffer: CachedHandles?
    /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
    var overlayBuffer: (key: OverlayBufferKey, buffer: SDLGPUBuffer, count: Int)?
    /// The overlay's fill triangles, kept until the fills or the palette change, and dropped once a frame has none.
    var fillBuffer: (key: FillBufferKey, buffer: SDLGPUBuffer, count: Int)?
    /// Main passes encoded so far. Tests use it to tell "drew" from "bailed out".
    private(set) var encodedPasses = 0

    init(device: SDLGPUDevice, pipelines: SDLViewportPipelines) {
        self.device = device
        self.pipelines = pipelines
    }

    /// With pipelines made from `library`. Making them compiles every shader, which a real GPU does in milliseconds and a CPU driver in
    /// a second, on whichever thread asks: make them once per device.
    convenience init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
        self.init(device: device, pipelines: try SDLViewportPipelines(device: device, library: library))
    }

    /// The main pass into `target` (`b8g8r8a8Unorm`, `scale` pixels per point). It does nothing for an empty view or a target in
    /// another format. Everything the pass reads is made first, so the copies that fill it come before the pass in `commandBuffer`.
    func encode(_ frame: ViewportFrame, into target: SDLGPUTexture, scale: Double, commandBuffer: SDLGPUCommandBuffer) {
        let width = target.description.width
        let height = target.description.height
        guard width > 0, height > 0, !frame.size.isEmpty, scale.isFinite, scale > 0,
              target.description.format == SDLViewportPipelines.colorFormat,
              let targets = multisampleTargets(width: width, height: height) else { return }
        let uploader = SDLViewportUploader(device: device, commandBuffer: commandBuffer)
        let plan = plan(frame, scale: Float(scale), uploader: uploader)
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: width, pixelHeight: height)
        let color = SDLGPUColorAttachment(texture: targets.color, loadOp: .clear, clearColor: (0, 0, 0, 1), storeOp: .resolve,
                                          resolveTexture: target)
        let depth = SDLGPUDepthAttachment(texture: targets.depth, loadOp: .clear, clearDepth: 1, storeOp: .dontCare)
        guard let pass = commandBuffer.beginRenderPass(color: color, depth: depth) else { return }
        record(plan, frame, uniforms, in: pass)
        pass.end()
        encodedPasses += 1
    }

    /// How far (mm) edges move towards the camera so they win against the faces they bound.
    static func edgeDepthBias(_ frame: ViewportFrame) -> Double { max(frame.pose.distance * 0.002, 1e-3) }

    // MARK: - Resources

    private func multisampleTargets(width: Int, height: Int) -> (color: SDLGPUTexture, depth: SDLGPUTexture)? {
        if let multisample, multisample.width == width, multisample.height == height {
            return (multisample.color, multisample.depth)
        }
        guard let color = device.makeTexture(SDLGPUTextureDescription(
                  width: width, height: height, format: SDLViewportPipelines.colorFormat, usage: [.colorTarget],
                  sampleCount: SDLViewportPipelines.sampleCount)),
              let depth = device.makeTexture(SDLGPUTextureDescription(
                  width: width, height: height, format: .d32Float, usage: [.depthStencilTarget],
                  sampleCount: SDLViewportPipelines.sampleCount)) else { return nil }
        multisample = (width, height, color, depth)
        return (color, depth)
    }

    /// Uploads meshes the frame shows for the first time (and the ID pass's edges for each), and drops the ones it no longer shows.
    func prepareMeshes(for frame: ViewportFrame, _ uploader: SDLViewportUploader) {
        let shown = Set(frame.items.map(\.meshSerial))
        meshes = meshes.filter { shown.contains($0.key) }
        for item in frame.items {
            let mesh = meshes[item.meshSerial] ?? SDLViewportMesh(uploader: uploader, mesh: item.mesh)
            meshes[item.meshSerial] = mesh
            if !item.isGuide { _ = mesh.pickEdges(solid: item.solidIndex, uploader: uploader) }
        }
    }
}
#endif
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 317 tests in 44 suites passed` (baseline 304/41 + 13 tests, + 3 suites).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 304 tests in 41 suites passed` (baseline 259/34 + 45 tests, + 7 suites).

On Linux the draws render on lavapipe: `SDLRenderTests` and `SDLFieldGuideClipTests`. macOS is unaffected (all new files are `#if canImport(MetalUISDLGPU)`); its count does not change.
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift \
  Tests/CreatorViewportTests/SDLFieldGuideClipTests.swift \
  Tests/CreatorViewportTests/SDLRenderTests.swift \
  Tests/CreatorViewportTests/Support/RenderFixtures.swift \
  Tests/CreatorViewportTests/Support/SDLRenderRig.swift \
  Tests/CreatorViewportTests/Support/TestMeshes+Sheet.swift
git commit -m "viewport: the SDL_GPU renderer's main pass"
```


### Task 7: The ID pass and the picker with its read-back

Picking on SDL. `SDLIDPassInputs` is what the ID pass draws (each solid's vertex buffer and pick base, each solid's edge instances, the camera and the cut plane), gathered on the main actor by `idPassInputs(for:width:height:)`, so the batch that records the pass on the device's worker thread reads none of the renderer's state. `encodeIDs` is static and records into `r32Uint` (one texel per point) with a single-sample depth target: faces write `pickBase | face`, edges their pick ID, 6 points wide and biased towards the camera. `SDLViewportPicker` runs it as a batch (`submitBatch`), awaits the fence, downloads the words and keeps them until the camera or the scene changes (`PickKey`, as Metal's picker does). It works ahead: the draw calls `schedule(frame)`; `pick` reads the landed words with no wait (a hover's answer: the latest landed buffer, never a stall); `isPending` says when they are not for this view; `pickWhenReady` (a click's answer) waits for the buffer of the click's own view; a pass that cannot run counts as landed and empty, so nothing waits forever, and the next draw retries. This is user decision U4, **hybrid**. Steps 1 to 5 build it with the click's wait asynchronous, because MetalUI's typed layer cannot yet submit a render batch without `await` (gap XP-G22, task 0); **step 6, once MetalUI answers XP-G22, makes the click's wait synchronous** (render the ID pass, `SDLGPUFence.waitBlocking()`, `SDLGPUDevice.downloadSynchronously`: MetalUI S11's answer to XP-G14) and deletes the asynchronous click of task 2. Review Focus 3 and 4 are tests here.

The Metal ID-pass test needs OpenCascade (`OffscreenRenderTests`), so the same checks run here on `TestMeshes.box`, which has the same face and edge numbering as the prism OpenCascade builds in the test: the readback needs a test (spec section 4) and gets one on Linux and Windows.

**Files:**
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+IDPass.swift`
- Create: `Tests/CreatorViewportTests/SDLPickerTests.swift`
- Modify: `Tests/CreatorViewportTests/Support/SDLRenderRig.swift`

**Interfaces:**
- Consumes: task 6's renderer and `SDLRenderRig`; `PickID`, `PickKey`, `FrameUniforms`; MetalUI `SDLGPUDevice.submitBatch(_:) async throws -> SDLGPUFence`, `SDLGPUFence.wait() async`, `SDLGPUDevice.download(_:mipLevel:) async -> [UInt8]?`, `makeTexture`; in step 6 also `SDLGPUFence.waitBlocking()`, `SDLGPUDevice.downloadSynchronously(_:region:) -> [UInt8]?` (both in `5f03ab7b`) and the requested `submitBatchSynchronously(_:) throws -> SDLGPUFence` (XP-G22).
- Produces: `SDLIDPassInputs`; `SDLViewportRenderer.idPassInputs(for:width:height:) -> SDLIDPassInputs?`, `static encodeIDs(_:into:depth:commandBuffer:)`; `@MainActor final class SDLViewportPicker` (`init(renderer:)`, `pick(at:in:)`, `isPending(for:)`, `schedule(_:)`, `refresh(_:) async`, `pickWhenReady(at:in:) async` (synchronous after step 6), `onReady`, `renderCount`); the rig's `picker`, `prepare(_:)`, `pick(at:in:)`, `picks(at:in:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorViewportTests/SDLPickerTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The ID pass and its read-back on SDL_GPU (spec §8's offscreen test, as `OffscreenRenderTests` runs it on Metal): the face and edge
/// IDs under chosen pixels of a known solid, from the `r32Uint` words `SDLGPUDevice.download` returns. Pixel colours are never compared.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLPickerTests {
    typealias Rig = SDLRenderRig

    @Test func theIDPassReportsTheFaceAndEdgeUnderChosenPixels() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        // TestMeshes.box: face 2 is the front (−Y), and edge 1 its top (side 0, top).
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(80, 160), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(100, 26), in: frame) == .edge(solid: 0, EdgeID(1)),
                "1.5 points below the top edge is inside its 6-point pick width")
        #expect(rig.picker.pick(at: ScreenPoint(100, 174), in: frame) == .edge(solid: 0, EdgeID(0)), "and the bottom edge")
        #expect(rig.picker.pick(at: ScreenPoint(100, 10), in: frame) == nil)
        #expect(rig.picker.pick(at: ScreenPoint(160, 100), in: frame) == nil)
    }

    @Test func picksOutsideTheViewOrBeforeItHasASizeAreNil() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        await rig.picker.refresh(frame)
        for point in [ScreenPoint(-1, 100), ScreenPoint(100, -0.5), ScreenPoint(200, 100), ScreenPoint(100, 200),
                      ScreenPoint(.nan, 3), ScreenPoint(.infinity, 3),
        ] {
            #expect(rig.picker.pick(at: point, in: frame) == nil, "\(point)")
        }
        var empty = frame
        empty.size = ViewportSize(width: 0, height: 0)
        #expect(rig.picker.pick(at: ScreenPoint(0, 0), in: empty) == nil)
        #expect(!rig.picker.isPending(for: empty), "a view with no size has nothing to wait for")
    }

    @Test func theIDBufferIsReusedUntilTheCameraMoves() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        _ = try await rig.pick(at: ScreenPoint(100, 100), in: frame)
        await rig.picker.refresh(frame)
        _ = rig.picker.pick(at: ScreenPoint(90, 120), in: frame)
        #expect(rig.picker.renderCount == 1)
        var turned = frame
        turned.pose.yaw += 0.1
        _ = try await rig.pick(at: ScreenPoint(100, 100), in: turned)
        #expect(rig.picker.renderCount == 2)
    }

    @Test func aBufferThatHasNotLandedIsPendingAndAnswersNilUntilItDoes() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        #expect(rig.picker.isPending(for: frame))
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == nil)
        var landed = 0
        rig.picker.onReady = { landed += 1 }
        let target = await rig.picker.pickWhenReady(at: ScreenPoint(100, 100), in: frame)
        #expect(target == .face(solid: 0, FaceID(2)))
        #expect(!rig.picker.isPending(for: frame))
        #expect(landed >= 1, "the model is told so it can look under the pointer again")
        var turned = frame
        turned.pose.yaw += 0.1
        #expect(rig.picker.isPending(for: turned), "a new camera has no buffer yet")
    }

    @Test func aFrameWhoseMeshesWereNeverUploadedLandsEmptyAndIsTriedAgainOnTheNextSchedule() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        await rig.picker.refresh(frame)
        #expect(!rig.picker.isPending(for: frame), "a failed pass counts as landed, so nothing waits for it forever")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == nil)
        try await rig.prepare(frame)
        await rig.picker.refresh(frame)
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)), "asked again, it is tried again")
    }

    /// A newer request replaces an older one that has not started, a resize is a view of its own, and an older view can be asked for
    /// again: nothing waits forever and nothing is answered with another view's pixels.
    @Test func aNewCameraOrSizeSupersedesOlderRequestsAndAnOlderViewCanBeAskedForAgain() async throws {
        let rig = try Rig()
        let first = RenderFixtures.boxFrame()
        var second = first
        second.pose.yaw += 0.1
        var resized = second
        resized.size = ViewportSize(width: 100, height: 100)
        try await rig.prepare(first)
        rig.picker.schedule(first)            // an orbit asks for a pass every frame ...
        rig.picker.schedule(second)           // ... and each replaces the one before while the view moves ...
        await rig.picker.refresh(resized)     // ... until a click or the quiet runs the newest
        #expect(!rig.picker.isPending(for: resized))
        #expect(rig.picker.isPending(for: first) && rig.picker.isPending(for: second), "the replaced requests never ran")
        #expect(rig.picker.pick(at: ScreenPoint(150, 150), in: resized) == nil, "outside the smaller view")
        await rig.picker.refresh(second)
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: second) == .face(solid: 0, FaceID(2)),
                "an older view can be asked for again")
    }

    @Test(.timeLimit(.minutes(1)))
    func theQuietBeforeAPassIsShortAndStartsItWithoutAnyoneAsking() async throws {
        let rig = try Rig()
        let frame = RenderFixtures.boxFrame()
        try await rig.prepare(frame)
        rig.picker.schedule(frame)
        #expect(rig.picker.isPending(for: frame), "not yet: the view has not been still")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            rig.picker.onReady = { continuation.resume() }
        }
        #expect(!rig.picker.isPending(for: frame), "the pass ran by itself after \(SDLViewportPicker.settleDelay)")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
    }

    /// `PickID` holds 256 solids (8 bits): a scene with more draws them all, and the ones past 255 are simply not pickable.
    @Test func aSolidPastTheTwoHundredFiftyFifthIsDrawnButNotPickable() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let beside = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(-10, 10, 30)))
        frame.items.append(FrameItem(meshSerial: 2, mesh: beside, solidIndex: PickID.maxSolids, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: []))
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == nil, "the 257th solid has no pick ID")
        let drawn = try await rig.draw(frame)
        let alone = try await rig.draw(RenderFixtures.boxFrame())
        #expect(Rig.color(drawn, 40, 100) != Rig.color(alone, 40, 100), "but it is drawn")
    }

    @Test func anEmptySceneHasNothingUnderAnyPixel() async throws {
        let rig = try Rig()
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: RenderFixtures.emptyFrame()) == nil)
    }

    @Test func aGuideIsNeverPickedAndATintedPartIsPickedAsBefore() async throws {
        let rig = try Rig()
        let wide = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(15, 10, 30)))
        var frame = RenderFixtures.boxFrame()
        frame.items.append(FrameItem(meshSerial: 2, mesh: wide, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: Set(wide.edgePolylines.keys), isGuide: true))
        #expect(try await rig.pick(at: ScreenPoint(25, 100), in: frame) == nil, "on the guide's edge")
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == nil, "where the guide's face would be")
        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)), "the part is picked as before")
        var tinted = RenderFixtures.boxFrame()
        tinted.items[0].fieldValues = TestMeshes.box(RenderFixtures.bounds).positions.map { Float($0.x) }
        tinted.items[0].fieldRamp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: tinted) == .face(solid: 0, FaceID(2)), "the front face, as untinted")
    }

    @Test func theCutViewPicksOnlyWhatIsLeft() async throws {
        let rig = try Rig()
        func frame(_ clip: ViewportClip?) -> ViewportFrame {
            var frame = RenderFixtures.boxFrame()
            frame.clip = clip
            return frame
        }
        func nearSide(_ y: Double) -> ViewportClip { ViewportClip(origin: Vector3(0, y, 0), normal: Vector3(0, -1, 0)) }
        let point = ScreenPoint(100, 100)
        #expect(try await rig.pick(at: point, in: frame(nil)) == .face(solid: 0, FaceID(2)), "the front face")
        let inside = try await rig.pick(at: point, in: frame(nearSide(0)))
        #expect(inside == .face(solid: 0, FaceID(4)), "the back face, seen from inside: \(String(describing: inside))")
        #expect(try await rig.pick(at: point, in: frame(nearSide(100))) == nil)
    }

    @Test func twoSolidsAreToldApartByTheirIndex() async throws {
        let rig = try Rig()
        var frame = RenderFixtures.boxFrame()
        let beside = TestMeshes.box(BoundingBox(min: Vector3(-15, -10, 0), max: Vector3(-10, 10, 30)))
        frame.items.append(FrameItem(meshSerial: 2, mesh: beside, solidIndex: 1, isGhost: false, hoveredFace: nil,
                                     selectedFaces: [], selectedEdges: []))
        #expect(try await rig.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
        #expect(rig.picker.pick(at: ScreenPoint(40, 100), in: frame) == .face(solid: 1, FaceID(2)), "the second box is at view x 25…50")
    }
}
#endif
```

`Tests/CreatorViewportTests/Support/SDLRenderRig.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/Support/SDLRenderRig.swift
+++ b/Tests/CreatorViewportTests/Support/SDLRenderRig.swift
@@ -11,6 +11,7 @@
     static let pixels = 400
     let device: SDLGPUDevice
     let renderer: SDLViewportRenderer
+    let picker: SDLViewportPicker
     let target: SDLGPUTexture
 
     init() throws {
@@ -19,6 +20,7 @@
         }
         self.device = device
         renderer = SDLViewportRenderer(device: device, pipelines: pipelines)
+        picker = SDLViewportPicker(renderer: renderer)
         guard let target = device.makeTexture(SDLGPUTextureDescription(
             width: Self.pixels, height: Self.pixels, format: .b8g8r8a8Unorm, usage: [.colorTarget, .sampler])) else {
             throw SDLRigError(description: "the target texture could not be made")
@@ -40,6 +42,31 @@
         return bytes
     }
 
+    /// Uploads the meshes `frame` shows, as a draw would, without drawing.
+    func prepare(_ frame: ViewportFrame) async throws {
+        let boxed = Handoff(value: frame)
+        let renderer = renderer
+        let device = device
+        let fence = try await device.submitBatch { commandBuffer in
+            renderer.prepareMeshes(for: boxed.value, SDLViewportUploader(device: device, commandBuffer: commandBuffer))
+        }
+        await fence.wait()
+    }
+
+    /// The face or edge under `point` in `frame`, from a read-back ID pass (the picker the app uses).
+    func pick(at point: ScreenPoint, in frame: ViewportFrame) async throws -> PickTarget? {
+        try await prepare(frame)
+        await picker.refresh(frame)
+        return picker.pick(at: point, in: frame)
+    }
+
+    /// ``pick(at:in:)`` for each of `points`, from one ID pass (no loop here holds locals across an `await`).
+    func picks(at points: [ScreenPoint], in frame: ViewportFrame) async throws -> [PickTarget?] {
+        try await prepare(frame)
+        await picker.refresh(frame)
+        return points.map { picker.pick(at: $0, in: frame) }
+    }
+
     /// The colour at view point (`x`, `y`) of a 400 × 400 draw at 2 pixels per point, as red, green and blue.
     static func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
         let at = (y * 2 * pixels + x * 2) * 4
```

- [ ] **Step 2: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. Linux: `cannot find 'SDLViewportPicker' in scope`.

- [ ] **Step 3: Implement**

The batch's recording closure hands the renderer nothing but `SDLIDPassInputs` and the two textures. The picker's loop keeps its bookkeeping in synchronous helpers (`takeWanted`, `land`) so no loop holds locals across an `await` (the Windows Swift 6.4 compiler assert), and no `async` function here takes a closure parameter, so none can be closure-specialised (Global Constraints); `idle()`'s loop holds no locals. Windows' release build of this file is CI's "Build release (for the zip)" step: read it after the push.

`Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// Answers "what is under this point?" from the ID pass (spec §6.3) on SDL_GPU. Reading a texture back is asynchronous here: the pass
/// is recorded and submitted as a batch of its own (`SDLGPUDevice.submitBatch`), its fence awaited off the main actor, and the `r32Uint`
/// words downloaded. So the picker works ahead: the draw that follows a change of camera or scene calls ``schedule(_:)``, which starts
/// the pass once the view has been still for ``settleDelay`` (an orbit draws every frame, and a read-back per frame nobody asked for
/// would be waste), the ID buffer lands a few milliseconds after that, and ``pick(at:in:)`` reads it with no wait, as `ViewportPicker`
/// reads Metal's: a hover's answer (user decision U4, hybrid). A click does not wait for the quiet: ``pickWhenReady(at:in:)`` starts the
/// pass for the click's own view at once and answers from it, never from another view's buffer (asynchronously until MetalUI gap
/// XP-G22; then synchronously, plan task 7 step 6).
///
/// A pick for a view whose buffer has not landed answers `nil` and ``isPending(for:)`` says so. The buffer is kept until the camera or
/// the scene changes (`PickKey`), as Metal's is. A pass that fails (no GPU memory, a lost device, meshes not uploaded yet) counts as
/// landed with nothing in it, so nothing waits for it forever; the next draw's ``schedule(_:)`` and the next ``refresh(_:)`` try again.
@MainActor
final class SDLViewportPicker {
    /// How long the view must be still before a draw's ``schedule(_:)`` starts the ID pass.
    static let settleDelay = Duration.milliseconds(40)

    private enum Landed {
        case pixels(width: Int, height: Int, words: [UInt32])
        /// The pass could not run; ``schedule(_:)`` and ``refresh(_:)`` run it again.
        case failed
    }

    private let device: SDLGPUDevice
    private let renderer: SDLViewportRenderer
    private var landed: (key: PickKey, result: Landed)?
    /// The newest frame asked for; a pass in flight for an older view is followed by one for this.
    private var wanted: ViewportFrame?
    private var running = false
    private var settleTask: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Called after a buffer has landed (`ViewportModel.refreshHover`).
    var onReady: (@MainActor () -> Void)?
    /// ID passes that have landed. Tests use it to check the read-back is reused.
    private(set) var renderCount = 0

    init(renderer: SDLViewportRenderer) {
        self.renderer = renderer
        device = renderer.device
    }

    /// The face or edge under `point` (viewport points), or `nil` for empty space, a point outside the view, a view with no size
    /// yet, or a buffer that has not landed.
    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        guard !frame.size.isEmpty, point.x.isFinite, point.y.isFinite,
              let landed, landed.key == frame.pickKey, case .pixels(let width, let height, let words) = landed.result else { return nil }
        guard point.x >= 0, point.y >= 0, point.x < Double(width), point.y < Double(height) else { return nil }
        return PickID.decode(words[Int(point.y) * width + Int(point.x)])
    }

    /// Whether the buffer for `frame` has yet to land: ``pick(at:in:)`` would answer `nil` for want of it. A pass that failed has
    /// landed, with nothing in it.
    func isPending(for frame: ViewportFrame) -> Bool {
        guard !frame.size.isEmpty else { return false }
        return landed?.key != frame.pickKey
    }

    /// Whether the ID pass has still to run for `frame`. A pass that failed counts as run unless `retryFailed`.
    private func needsPass(for frame: ViewportFrame, retryFailed: Bool) -> Bool {
        guard !frame.size.isEmpty else { return false }
        guard let landed, landed.key == frame.pickKey else { return true }
        if retryFailed, case .failed = landed.result { return true }
        return false
    }

    /// Makes sure the buffer for `frame` is on its way, once the view has been still for ``settleDelay``. The draw calls it after it
    /// encodes, once the frame's meshes are on the GPU; a newer call replaces an older one that has not started.
    func schedule(_ frame: ViewportFrame) {
        guard needsPass(for: frame, retryFailed: true) else { return }
        wanted = frame
        armSettle()
    }

    private func armSettle() {
        guard !running else { return }   // the pass in flight re-arms it when it ends
        settleTask?.cancel()
        settleTask = Task { [self] in
            try? await Task.sleep(for: Self.settleDelay)
            if !Task.isCancelled { start() }
        }
    }

    /// Starts the pass for `wanted` now, unless one is running (it takes `wanted` when it ends).
    private func start() {
        settleTask?.cancel()
        settleTask = nil
        guard !running, wanted != nil else { return }
        running = true
        Task { await self.run() }
    }

    /// Returns once the buffer for `frame` has landed, running its pass at once (the quiet is not waited for). A buffer that landed
    /// failed is tried again once. Tests await it.
    func refresh(_ frame: ViewportFrame) async {
        if needsPass(for: frame, retryFailed: true) {
            wanted = frame
            start()
        }
        await idle()
        // A pass for an older view may have been in flight and taken the place of this one.
        if needsPass(for: frame, retryFailed: false) {
            wanted = frame
            start()
            await idle()
        }
    }

    /// Returns once no pass is running.
    private func idle() async {
        while running {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    /// ``pick(at:in:)`` once the buffer for `frame` has landed (at once if it has).
    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        await refresh(frame)
        return pick(at: point, in: frame)
    }

    /// Renders the ID pass for the frame asked for last. The bookkeeping around the pass is synchronous (`takeWanted`, `land`,
    /// `finish`), so no loop's locals are held across an `await` (the Windows Swift 6.4 compiler asserts on that).
    private func run() async {
        if let frame = takeWanted() {
            let result = await render(frame)
            land(result, for: frame.pickKey)
        }
        finish()
    }

    private func takeWanted() -> ViewportFrame? {
        defer { wanted = nil }
        return wanted
    }

    /// Keeps `result` as the buffer for `key` and tells the model.
    private func land(_ result: Landed, for key: PickKey) {
        landed = (key, result)
        if case .pixels = result { renderCount += 1 }
        onReady?()
    }

    /// The pass is over: a request that came meanwhile waits for the quiet again, and whoever waits for the pass is woken.
    private func finish() {
        running = false
        if wanted != nil { armSettle() }
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }

    private func render(_ frame: ViewportFrame) async -> Landed {
        let width = Int(frame.size.width.rounded(.down))
        let height = Int(frame.size.height.rounded(.down))
        guard width > 0, height > 0, let inputs = renderer.idPassInputs(for: frame, width: width, height: height) else { return .failed }
        if inputs.isEmpty { return .pixels(width: width, height: height, words: [UInt32](repeating: 0, count: width * height)) }
        guard let ids = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: SDLViewportPipelines.idFormat,
                                                                    usage: [.colorTarget])),
              let depth = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: .d32Float,
                                                                      usage: [.depthStencilTarget])),
              let fence = try? await device.submitBatch({ commandBuffer in
                  SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
              }) else { return .failed }
        await fence.wait()
        guard let bytes = await device.download(ids), bytes.count == width * height * MemoryLayout<UInt32>.stride else { return .failed }
        let words = bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        return .pixels(width: width, height: height, words: words)
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+IDPass.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// What the ID pass draws, gathered on the main actor so the batch that records it, on the device's worker thread, reads none of the
/// renderer's state: the pipelines and buffers are immutable once made, and the batch retains them until its fence signals.
struct SDLIDPassInputs: @unchecked Sendable {
    struct Solid {
        var vertices: SDLGPUBuffer
        var vertexCount: Int
        /// `PickID.base` for the solid's faces.
        var pickBase: UInt32
    }

    var pipelines: SDLViewportPipelines
    var solids: [Solid]
    var edges: [(buffer: SDLGPUBuffer, count: Int)]
    var uniforms: FrameUniforms
    var clip: ClipUniforms
    /// `SDLViewportRenderer.edgeDepthBias`: edges move this far (mm) towards the camera.
    var edgeBias: Float

    /// Whether anything is drawn (an empty scene has no ID pass to run).
    var isEmpty: Bool { solids.isEmpty && edges.isEmpty }
}

extension SDLViewportRenderer {
    /// The ID pass's draws for `frame` at the size of the ID target, or `nil` if a mesh the frame shows has not been prepared yet (a
    /// draw prepares them: `encode`). Guides are no part of the scene: they're never in the ID pass.
    func idPassInputs(for frame: ViewportFrame, width: Int, height: Int) -> SDLIDPassInputs? {
        var solids: [SDLIDPassInputs.Solid] = []
        var edges: [(buffer: SDLGPUBuffer, count: Int)] = []
        for item in frame.items where !item.isGuide {
            guard let mesh = meshes[item.meshSerial], mesh.hasPickEdges(solid: item.solidIndex) else { return nil }
            if let vertices = mesh.vertexBuffer, let base = PickID.base(kind: PickID.faceKind, solid: item.solidIndex) {
                solids.append(SDLIDPassInputs.Solid(vertices: vertices, vertexCount: mesh.vertexCount, pickBase: base))
            }
            if let instances = mesh.cachedPickEdges(solid: item.solidIndex) { edges.append(instances) }
        }
        let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                 pixelWidth: width, pixelHeight: height)
        return SDLIDPassInputs(pipelines: pipelines, solids: solids, edges: edges, uniforms: uniforms, clip: ClipUniforms(frame.clip),
                               edgeBias: Float(Self.edgeDepthBias(frame)))
    }

    /// The ID pass into `ids` (`r32Uint`, one texel per point) with a matching single-sample `depth` target. Faces write their face
    /// pick IDs and edges theirs, 6 points wide and biased towards the camera. It is static: it touches nothing but `inputs`.
    static func encodeIDs(_ inputs: SDLIDPassInputs, into ids: SDLGPUTexture, depth: SDLGPUTexture,
                          commandBuffer: SDLGPUCommandBuffer) {
        let color = SDLGPUColorAttachment(texture: ids, loadOp: .clear, clearColor: (0, 0, 0, 0), storeOp: .store)
        let depthTarget = SDLGPUDepthAttachment(texture: depth, loadOp: .clear, clearDepth: 1, storeOp: .dontCare)
        guard let pass = commandBuffer.beginRenderPass(color: color, depth: depthTarget) else { return }
        let camera = uniformBytes(inputs.uniforms)
        let clip = uniformBytes(inputs.clip)
        for solid in inputs.solids {
            pass.bind(inputs.pipelines.idMesh)
            pass.pushVertexUniform(camera, at: 0)
            pass.pushVertexUniform(uniformBytes(DrawUniforms(pickBase: solid.pickBase, ghost: 0, faceCount: 0, padding: 0)), at: 1)
            pass.pushFragmentUniform(clip, at: 0)
            pass.bindVertexStorageBuffers([solid.vertices])
            pass.draw(vertexCount: solid.vertexCount)
        }
        let style = LineUniforms(widthOverride: 6, depthBias: inputs.edgeBias, padding0: 0, padding1: 0)
        for edges in inputs.edges where edges.count > 0 {
            pass.bind(inputs.pipelines.idLine)
            pass.pushVertexUniform(camera, at: 0)
            pass.pushVertexUniform(uniformBytes(style), at: 1)
            pass.pushFragmentUniform(clip, at: 0)
            pass.bindVertexStorageBuffers([edges.buffer])
            pass.draw(vertexCount: 4, instanceCount: edges.count)
        }
        pass.end()
    }
}
#endif
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 317 tests in 44 suites passed` (baseline 304/41 + 13 tests, + 3 suites).
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 316 tests in 42 suites passed` (baseline 259/34 + 57 tests, + 8 suites).

`SDLPickerTests` covers: the face and edge IDs under chosen pixels, outside-the-view and not-a-number points, the buffer reused until the camera moves, pending then landed, a frame whose meshes were never uploaded, an empty scene, a guide never picked, the cut view, two solids told apart, a new camera or size superseding older requests, the settle delay, and the 257th solid.
- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+IDPass.swift \
  Tests/CreatorViewportTests/SDLPickerTests.swift \
  Tests/CreatorViewportTests/Support/SDLRenderRig.swift
git commit -m "viewport: SDL ID pass, picker and read-back"
```


- [ ] **Step 6 (after task 8, once MetalUI answers XP-G22): the click renders its own ID pass synchronously**

**Gate.** Do this step when MetalUI has `SDLGPUDevice.submitBatchSynchronously(_:) throws -> SDLGPUFence` (gap XP-G22, the signature requested in `docs/metalui-gaps.md`) and master's `METALUI_COMMIT` includes it; until then skip it and go on (the asynchronous click of steps 1 to 5 is exact, only later). Check with `git -C ../MetalUI grep -n "func submitBatchSynchronously" HEAD -- Backends/SDL/Sources/MetalUISDLGPU`. If MetalUI spelled it differently, change only `SDLViewportPicker.renderNow`. Adopting it means bumping `METALUI_COMMIT` in `.github/workflows/xp.yml` to that commit (the one pin bump this plan makes, and only here) and saying so in the XP-G22 row. Do it after task 8, because `SDLViewportBackend` (task 8) forwards `pickWhenReady` and changes with it.

**What changes.** `ViewportBackend.pickWhenReady(at:in:)` stops being `async`: Metal's default answers at once, as before; `SDLViewportPicker.pickWhenReady` answers from the landed buffer for the click's view or, when there is none, renders the ID pass now (`submitBatchSynchronously`), waits (`SDLGPUFence.waitBlocking()`) and reads it back (`SDLGPUDevice.downloadSynchronously`), landing it for hovers too. A ticket per pass keeps a slower batch from replacing a newer landed buffer. `ViewportModel.click` delivers every click at once through `(pickWhenReady ?? pick)`; the click `Task` and its tool and projector capture go, and so do `FakeBackend`'s waiters and the two waiting-click tests, replaced by `aClickIsAnsweredAtOnceFromItsOwnIDPassWhileTheHoverBufferIsPending`; `SDLPickerTests` gains `aClickRendersItsOwnIDPassWhenNoBufferHasLanded`. A hover is unchanged (Review Focus 3).

`Sources/CreatorViewport/Render/ViewportBackend.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/ViewportBackend.swift
+++ b/Sources/CreatorViewport/Render/ViewportBackend.swift
@@ -5,8 +5,8 @@
 /// Picking is the part the model sees (user decision U4, hybrid). Metal answers a pick at once, by rendering the ID buffer and waiting
 /// for it. The SDL_GPU backend answers a hover from the ID buffer it rendered ahead (``isPickPending(for:)`` says when that buffer is not
 /// for the camera and scene of the frame asked about yet) and calls ``onPickReady`` when a new one lands; a click asks
-/// ``pickWhenReady(at:in:)``, which answers from a buffer for the click's own view, waiting for it (asynchronously until MetalUI gap
-/// XP-G22 lets it render one synchronously).
+/// ``pickWhenReady(at:in:)``, which answers from a buffer for the click's own view, rendering it and waiting for the GPU when none has
+/// landed, as Metal does.
 @MainActor
 protocol ViewportBackend: AnyObject {
     /// Main passes drawn so far. Tests and the launch smoke test use it to tell "drew" from "bailed out".
@@ -23,8 +23,9 @@
     /// Whether the ID buffer for `frame` is on its way, so ``pick(at:in:)`` would answer `nil` for want of it.
     func isPickPending(for frame: ViewportFrame) -> Bool
 
-    /// The click's pick: ``pick(at:in:)`` from an ID buffer for `frame` itself, once it has landed. Never another view's answer.
-    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget?
+    /// The click's pick: ``pick(at:in:)`` from an ID buffer for `frame` itself, rendered and waited for now when none has landed (it may
+    /// stall a frame, as Metal's `waitUntilCompleted` does; only a click asks). Never another view's answer.
+    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget?
 
     /// Whether this backend draws the view cube and the axis triad. The model hit-tests the cube (hover, click, drag, the context menu's
     /// exclusion) only while it is drawn: a cube nobody can see must not rotate the camera. Metal draws them; the SDL backend says
@@ -37,7 +38,7 @@
 
     func isPickPending(for frame: ViewportFrame) -> Bool { false }
 
-    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
+    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
         pick(at: point, in: frame)
     }
 }
```

`Sources/CreatorViewport/Model/ViewportModel.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel.swift
@@ -71,10 +71,11 @@
     /// Answers "what is under this point?". It's set when the GPU objects are made (`install(_:)`), and tests set it directly.
     @ObservationIgnored var pick: (@MainActor (ScreenPoint) -> PickTarget?)?
     /// Whether `pick` has no answer yet because the ID buffer for the view as it is now is on its way (an SDL_GPU backend reads it back
-    /// asynchronously). A hover then keeps the face it had, and a click waits for `pickWhenReady`. `nil` means never.
+    /// asynchronously). A hover then keeps the face it had. `nil` means never.
     @ObservationIgnored var isPickPending: (@MainActor () -> Bool)?
-    /// `pick`, once the ID buffer for the view as it is now has landed.
-    @ObservationIgnored var pickWhenReady: (@MainActor (ScreenPoint) async -> PickTarget?)?
+    /// A click's pick: `pick` from an ID buffer for the view as it is now, rendered and waited for when none has landed (user decision U4,
+    /// hybrid). `nil` (no backend: tests that set `pick` directly) falls back to `pick`.
+    @ObservationIgnored var pickWhenReady: (@MainActor (ScreenPoint) -> PickTarget?)?
     @ObservationIgnored var drag: DragState?
     /// The camera when the scroll under way (a trackpad scroll, or a run of wheel steps) began; `nil` between scrolls.
     @ObservationIgnored var scrollStartPose: CameraPose?
```

`Sources/CreatorViewport/Model/ViewportModel+Backend.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Backend.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Backend.swift
@@ -26,7 +26,7 @@
         }
         pickWhenReady = { [weak self] point in
             guard let self else { return nil }
-            return await backend.pickWhenReady(at: point, in: frame(at: clock.now()))
+            return backend.pickWhenReady(at: point, in: frame(at: clock.now()))
         }
         backend.onPickReady = { [weak self] in self?.refreshHover() }
     }
```

`Sources/CreatorViewport/Model/ViewportModel+Input.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Input.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Input.swift
@@ -132,19 +132,9 @@
             if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
         } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil,
                   tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
-            if isPickPending?() == true, let pickWhenReady {
-                // The ID buffer for this view is still on its way: the click is delivered when it lands, not as a click on empty space.
-                // It is the click of the press: the tool and the projector are those of the press, not of whatever the tool or an
-                // animating camera has become by the time the buffer lands.
-                let pressTool = tool
-                let pressProjector = projector
-                Task { [self] in
-                    let target = await pickWhenReady(point)
-                    deliverClick(on: target, at: point, modifiers: modifiers, tool: pressTool, projector: pressProjector)
-                }
-            } else {
-                deliverClick(on: pick?(point), at: point, modifiers: modifiers, tool: tool, projector: projector)
-            }
+            // A click is exact (user decision U4, hybrid): answered from an ID buffer for this view, which the backend renders and
+            // waits for if it has not landed, so it is delivered now, to the tool and with the projector of the press.
+            deliverClick(on: (pickWhenReady ?? pick)?(point), at: point, modifiers: modifiers, tool: tool, projector: projector)
         }
         pointerReleased(at: point)
     }
```

`Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift
@@ -35,8 +35,8 @@
         picker.isPending(for: frame)
     }
 
-    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
-        await picker.pickWhenReady(at: point, in: frame)
+    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
+        picker.pickWhenReady(at: point, in: frame)
     }
 
     /// Draws `frame` into the surface's target, in the frame's own command buffer, then starts the ID pass for it if it is for a view
```

`Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift
@@ -6,9 +6,10 @@
 /// words downloaded. So the picker works ahead: the draw that follows a change of camera or scene calls ``schedule(_:)``, which starts
 /// the pass once the view has been still for ``settleDelay`` (an orbit draws every frame, and a read-back per frame nobody asked for
 /// would be waste), the ID buffer lands a few milliseconds after that, and ``pick(at:in:)`` reads it with no wait, as `ViewportPicker`
-/// reads Metal's: a hover's answer (user decision U4, hybrid). A click does not wait for the quiet: ``pickWhenReady(at:in:)`` starts the
-/// pass for the click's own view at once and answers from it, never from another view's buffer (asynchronously until MetalUI gap
-/// XP-G22; then synchronously, plan task 7 step 6).
+/// reads Metal's: a hover's answer (user decision U4, hybrid). A click does not wait for the quiet: ``pickWhenReady(at:in:)`` answers
+/// from the buffer for the click's own view, and when none has landed renders it now and waits for the GPU (MetalUI's
+/// `submitBatchSynchronously`, `SDLGPUFence.waitBlocking()` and `SDLGPUDevice.downloadSynchronously`: gaps XP-G22 and XP-G14), never
+/// answering from another view's buffer.
 ///
 /// A pick for a view whose buffer has not landed answers `nil` and ``isPending(for:)`` says so. The buffer is kept until the camera or
 /// the scene changes (`PickKey`), as Metal's is. A pass that fails (no GPU memory, a lost device, meshes not uploaded yet) counts as
@@ -27,6 +28,9 @@
     private let device: SDLGPUDevice
     private let renderer: SDLViewportRenderer
     private var landed: (key: PickKey, result: Landed)?
+    /// Every pass takes a ticket when it starts; a result lands only if no later pass has landed (a click's pass can overtake a batch).
+    private var tickets = 0
+    private var landedTicket = 0
     /// The newest frame asked for; a pass in flight for an older view is followed by one for this.
     private var wanted: ViewportFrame?
     private var running = false
@@ -115,9 +119,13 @@
         }
     }
 
-    /// ``pick(at:in:)`` once the buffer for `frame` has landed (at once if it has).
-    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
-        await refresh(frame)
+    /// The click's pick: ``pick(at:in:)`` from the buffer for `frame`, rendered now and waited for when it has not landed (or landed
+    /// failed). It blocks the main actor for one ID pass, as Metal's picker does; it is called outside a draw (a click), never inside one.
+    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
+        if needsPass(for: frame, retryFailed: true) {
+            let ticket = nextTicket()
+            land(renderNow(frame), for: frame.pickKey, ticket: ticket)
+        }
         return pick(at: point, in: frame)
     }
 
@@ -125,19 +133,27 @@
     /// `finish`), so no loop's locals are held across an `await` (the Windows Swift 6.4 compiler asserts on that).
     private func run() async {
         if let frame = takeWanted() {
+            let ticket = nextTicket()
             let result = await render(frame)
-            land(result, for: frame.pickKey)
+            land(result, for: frame.pickKey, ticket: ticket)
         }
         finish()
     }
 
+    private func nextTicket() -> Int {
+        tickets += 1
+        return tickets
+    }
+
     private func takeWanted() -> ViewportFrame? {
         defer { wanted = nil }
         return wanted
     }
 
-    /// Keeps `result` as the buffer for `key` and tells the model.
-    private func land(_ result: Landed, for key: PickKey) {
+    /// Keeps `result` as the buffer for `key` and tells the model, unless a pass that started later has landed already.
+    private func land(_ result: Landed, for key: PickKey, ticket: Int) {
+        guard ticket > landedTicket else { return }
+        landedTicket = ticket
         landed = (key, result)
         if case .pixels = result { renderCount += 1 }
         onReady?()
@@ -152,22 +168,61 @@
         for waiter in waiting { waiter.resume() }
     }
 
-    private func render(_ frame: ViewportFrame) async -> Landed {
+    /// One ID pass's inputs and targets, made here on the main actor, or the answer when there is nothing to render.
+    private enum Prepared {
+        case answered(Landed)
+        case pass(width: Int, height: Int, inputs: SDLIDPassInputs, ids: SDLGPUTexture, depth: SDLGPUTexture)
+    }
+
+    private func prepare(_ frame: ViewportFrame) -> Prepared {
         let width = Int(frame.size.width.rounded(.down))
         let height = Int(frame.size.height.rounded(.down))
-        guard width > 0, height > 0, let inputs = renderer.idPassInputs(for: frame, width: width, height: height) else { return .failed }
-        if inputs.isEmpty { return .pixels(width: width, height: height, words: [UInt32](repeating: 0, count: width * height)) }
+        guard width > 0, height > 0, let inputs = renderer.idPassInputs(for: frame, width: width, height: height) else {
+            return .answered(.failed)
+        }
+        if inputs.isEmpty {
+            return .answered(.pixels(width: width, height: height, words: [UInt32](repeating: 0, count: width * height)))
+        }
         guard let ids = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: SDLViewportPipelines.idFormat,
                                                                     usage: [.colorTarget])),
               let depth = device.makeTexture(SDLGPUTextureDescription(width: width, height: height, format: .d32Float,
-                                                                      usage: [.depthStencilTarget])),
-              let fence = try? await device.submitBatch({ commandBuffer in
-                  SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
-              }) else { return .failed }
-        await fence.wait()
-        guard let bytes = await device.download(ids), bytes.count == width * height * MemoryLayout<UInt32>.stride else { return .failed }
-        let words = bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
-        return .pixels(width: width, height: height, words: words)
+                                                                      usage: [.depthStencilTarget])) else { return .answered(.failed) }
+        return .pass(width: width, height: height, inputs: inputs, ids: ids, depth: depth)
     }
+
+    /// The words of a read-back ID texture, or `.failed` when the read-back is missing or the wrong size.
+    private static func words(_ bytes: [UInt8]?, width: Int, height: Int) -> Landed {
+        guard let bytes, bytes.count == width * height * MemoryLayout<UInt32>.stride else { return .failed }
+        return .pixels(width: width, height: height, words: bytes.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) })
+    }
+
+    /// The pass in a batch of its own, awaited off the main actor (the ahead-of-time path a hover reads).
+    private func render(_ frame: ViewportFrame) async -> Landed {
+        switch prepare(frame) {
+        case .answered(let answer):
+            return answer
+        case .pass(let width, let height, let inputs, let ids, let depth):
+            guard let fence = try? await device.submitBatch({ commandBuffer in
+                SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
+            }) else { return .failed }
+            await fence.wait()
+            return Self.words(await device.download(ids), width: width, height: height)
+        }
+    }
+
+    /// The pass now, on the main actor, waited for (a click's path): submitted without `await` (XP-G22), the fence waited on, the words
+    /// read back synchronously (XP-G14).
+    private func renderNow(_ frame: ViewportFrame) -> Landed {
+        switch prepare(frame) {
+        case .answered(let answer):
+            return answer
+        case .pass(let width, let height, let inputs, let ids, let depth):
+            guard let fence = try? device.submitBatchSynchronously({ commandBuffer in
+                SDLViewportRenderer.encodeIDs(inputs, into: ids, depth: depth, commandBuffer: commandBuffer)
+            }) else { return .failed }
+            fence.waitBlocking()
+            return Self.words(device.downloadSynchronously(ids), width: width, height: height)
+        }
+    }
 }
 #endif
```

`Tests/CreatorViewportTests/ViewportBackendTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ViewportBackendTests.swift
+++ b/Tests/CreatorViewportTests/ViewportBackendTests.swift
@@ -3,47 +3,34 @@
 import Testing
 @testable import CreatorViewport
 
-/// A backend that answers picks as a test tells it to, and holds them back like an SDL_GPU readback that has not landed.
+/// A backend that answers picks as a test tells it to: a hover from the buffer that has landed (nothing while one is pending, like an
+/// SDL_GPU readback on its way), a click from the ID pass of its own view (`clickAnswer` while a buffer is pending).
 @MainActor
 final class FakeBackend: ViewportBackend {
     var drawnFrames = 0
     var onPickReady: (@MainActor () -> Void)?
     var isPending = false
     var answer: PickTarget?
+    /// What the click's own ID pass finds while the hover's buffer is pending.
+    var clickAnswer: PickTarget?
     /// What a real backend answers for ``ViewportBackend/drawsWidgets``.
     var drawsWidgets = true
-    private var waiters: [CheckedContinuation<PickTarget?, Never>] = []
-    private var registration: CheckedContinuation<Void, Never>?
+    /// Clicks that asked for their own pick.
+    private(set) var clickPicks = 0
 
-    /// How many clicks are waiting for the ID buffer.
-    var waitersRegistered: Int { waiters.count }
-
     func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? { isPending ? nil : answer }
 
     func isPickPending(for frame: ViewportFrame) -> Bool { isPending }
 
-    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
-        if !isPending { return answer }
-        return await withCheckedContinuation {
-            waiters.append($0)
-            registration?.resume()
-            registration = nil
-        }
+    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
+        clickPicks += 1
+        return isPending ? clickAnswer : answer
     }
 
-    /// Returns once a click is waiting (at once if one already is): the model's click `Task` has run and registered.
-    func untilAWaiterIsRegistered() async {
-        if !waiters.isEmpty { return }
-        await withCheckedContinuation { registration = $0 }
-    }
-
-    /// The ID buffer lands: pending ends, waiting clicks are answered and the model is told.
+    /// The ID buffer lands: pending ends and the model is told.
     func land(_ target: PickTarget?) {
         isPending = false
         answer = target
-        let waiting = waiters
-        waiters = []
-        for waiter in waiting { waiter.resume(returning: target) }
         onPickReady?()
     }
 }
@@ -108,55 +95,25 @@
         #expect(clicked == .some(face))
     }
 
-    @Test(.timeLimit(.minutes(1)))
-    func aClickWaitsForAPendingPickAndIsThenDeliveredOnTheLandedTarget() async {
+    /// A click is exact while the hover's buffer is on its way (user decision U4, hybrid): the backend renders the click's own ID pass and
+    /// waits, so the click is delivered before `click` returns, on its own view's target and to the tool of the press.
+    @Test func aClickIsAnsweredAtOnceFromItsOwnIDPassWhileTheHoverBufferIsPending() {
         let backend = FakeBackend()
         let model = makeModel(backend)
+        let tool = RecordingTool()
+        tool.claims = false
+        model.tool = tool
+        backend.answer = edge          // the older buffer's answer, which a click must not take
         backend.isPending = true
-        var landed = false
-        var deliveredBeforeLanding = false
-        var waitersWhenLanding = 0
-        let delivered = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
-            model.events.clicked = {
-                deliveredBeforeLanding = !landed
-                continuation.resume(returning: $0)
-            }
-            model.click(at: ScreenPoint(200, 200))
-            Task {
-                await backend.untilAWaiterIsRegistered()
-                waitersWhenLanding = backend.waitersRegistered
-                landed = true
-                backend.land(face)
-            }
-        }
-        #expect(waitersWhenLanding == 1, "the click is waiting for the buffer, not already answered")
-        #expect(!deliveredBeforeLanding, "nothing was delivered while the pick was pending")
-        #expect(delivered == face, "the click was on the face, not on empty space")
+        backend.clickAnswer = face     // what the click's own pass finds
+        var clicked: PickTarget??
+        model.events.clicked = { clicked = $0 }
+        model.click(at: ScreenPoint(200, 200))
+        #expect(clicked == .some(face), "delivered before click returned, from the click's own view")
+        #expect(tool.modelPicks == [face], "offered to the tool of the press")
+        #expect(backend.clickPicks == 1)
     }
 
-    @Test(.timeLimit(.minutes(1)))
-    func aWaitingClickGoesToTheToolItWasMadeWithAndNotTheOneSetWhileItWaited() async {
-        let backend = FakeBackend()
-        let model = makeModel(backend)
-        let first = RecordingTool()
-        first.claims = false
-        let second = RecordingTool()
-        second.claims = false
-        model.tool = first
-        backend.isPending = true
-        _ = await withCheckedContinuation { (continuation: CheckedContinuation<PickTarget?, Never>) in
-            model.events.clicked = { continuation.resume(returning: $0) }
-            model.click(at: ScreenPoint(200, 200))
-            model.tool = second   // the tool changes in the milliseconds before the buffer lands
-            Task {
-                await backend.untilAWaiterIsRegistered()
-                backend.land(face)
-            }
-        }
-        #expect(first.modelPicks == [face], "the press belonged to the first tool")
-        #expect(second.modelPicks.isEmpty)
-    }
-
     @Test func aBackendThatDrawsNoCubeLeavesItsCornerToTheScene() {
         let backend = FakeBackend()
         backend.drawsWidgets = false
```

`Tests/CreatorViewportTests/SDLPickerTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/SDLPickerTests.swift
+++ b/Tests/CreatorViewportTests/SDLPickerTests.swift
@@ -61,8 +61,8 @@
         #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == nil)
         var landed = 0
         rig.picker.onReady = { landed += 1 }
-        let target = await rig.picker.pickWhenReady(at: ScreenPoint(100, 100), in: frame)
-        #expect(target == .face(solid: 0, FaceID(2)))
+        await rig.picker.refresh(frame)
+        #expect(rig.picker.pick(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)))
         #expect(!rig.picker.isPending(for: frame))
         #expect(landed >= 1, "the model is told so it can look under the pointer again")
         var turned = frame
@@ -70,6 +70,24 @@
         #expect(rig.picker.isPending(for: turned), "a new camera has no buffer yet")
     }
 
+    /// A click whose view has no landed buffer renders its own ID pass and waits for the GPU (user decision U4, hybrid; MetalUI gaps
+    /// XP-G22 and XP-G14), so it is answered before `pickWhenReady` returns; a landed buffer is not rendered again.
+    @Test func aClickRendersItsOwnIDPassWhenNoBufferHasLanded() async throws {
+        let rig = try Rig()
+        let frame = RenderFixtures.boxFrame()
+        try await rig.prepare(frame)
+        #expect(rig.picker.isPending(for: frame), "no pass has run for this view")
+        #expect(rig.picker.pickWhenReady(at: ScreenPoint(100, 100), in: frame) == .face(solid: 0, FaceID(2)), "answered at once")
+        #expect(!rig.picker.isPending(for: frame), "and a hover has the buffer now too")
+        #expect(rig.picker.renderCount == 1)
+        #expect(rig.picker.pickWhenReady(at: ScreenPoint(100, 26), in: frame) == .edge(solid: 0, EdgeID(1)))
+        #expect(rig.picker.renderCount == 1, "a landed buffer is not rendered again")
+        var turned = frame
+        turned.pose.yaw += 0.1
+        _ = rig.picker.pickWhenReady(at: ScreenPoint(100, 100), in: turned)
+        #expect(rig.picker.renderCount == 2, "a click on a new view renders that view, never answering from the old one")
+    }
+
     @Test func aFrameWhoseMeshesWereNeverUploadedLandsEmptyAndIsTriedAgainOnTheNextSchedule() async throws {
         let rig = try Rig()
         let frame = RenderFixtures.boxFrame()
```

Run, as in step 4 and with the release check of task 2 step 4:

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release 2>&1 | grep -E 'error:|Assertion|While splitting|Build complete'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```

Expected: macOS one test fewer than before this step (`ViewportBackendTests` loses two and gains one), Linux the same number (`SDLPickerTests` gains one), no issue line, `Build complete!` with no assertion. If task 9 is done, also: in `CLAUDE.md`'s xp-3 paragraph, the sentence that begins "Picking is user decision U4, hybrid" says a click "waits for the buffer of its own view (asynchronously until MetalUI gap XP-G22)": make it say a click renders its own ID pass when none has landed and waits for it (`pickWhenReady`, MetalUI `submitBatchSynchronously`); in human check XP-22 drop the parenthesis that says the click "waits a few milliseconds"; in erratum E7 drop "(asynchronously until MetalUI answers gap XP-G22, a render batch submitted without `await`)"; in the XP-G22 row of `docs/metalui-gaps.md` set the status to `✅ fixed by MetalUI <commit>, adopted by xp-3 task 7 step 6`. Then lint and commit:

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorViewport/Render/ViewportBackend.swift Sources/CreatorViewport/Model/ViewportModel.swift \
  Sources/CreatorViewport/Model/ViewportModel+Backend.swift Sources/CreatorViewport/Model/ViewportModel+Input.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift Sources/CreatorViewport/RenderSDL/SDLViewportPicker.swift \
  Tests/CreatorViewportTests/ViewportBackendTests.swift Tests/CreatorViewportTests/SDLPickerTests.swift \
  .github/workflows/xp.yml CLAUDE.md docs/metalui-gaps.md docs/verification/human-checks.md \
  docs/superpowers/specs/2026-10-13-cross-platform-design.md
git commit -m "viewport: a click renders its own ID pass and waits for it on SDL (MetalUI XP-G22), as on Metal"
```


### Task 8: The SDL backend, the real viewport in the window, and a smoke test that sees it

Everything joins. `SDLViewportBackend` is the `ViewportBackend` over the renderer and the picker, made on the first draw from the window renderer's borrowed device (`ctx.view.device`); `ViewportModel.draw(_ context: any GPUSurfaceContext)` downcasts to `SDLGPUDrawContext`, encodes into the frame's own command buffer and then `schedule`s the ID pass; if the GPU objects cannot be made the surface is cleared to the dark red Metal shows and `gpuFailureMessage` says why. `ViewportPane` is always `ViewportView`; `ViewportPlaceholder` and its sentence are gone (spec section 2.3 and human check XP-2 are superseded). `--smoke-test` now passes only if the real viewport drew: `LaunchSmoke.viewport` is a report of frames drawn and the failure, set by `main.swift` from `model.viewport.drawnFrames` and `gpuFailureMessage`. `--self-test` also asks the viewport whether its shaders ship (`ViewportShaderCheck`).

**Files:**
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift`
- Create: `Tests/CreatorViewportTests/SDLViewportBackendTests.swift`
- Create: `Sources/CreatorViewport/ViewportShaderCheck.swift`
- Modify: `Sources/CreatorApp/LaunchSmoke.swift`
- Modify: `Sources/CreatorApp/SelfTest.swift`
- Modify: `Sources/CreatorApp/ViewportPane.swift`
- Modify: `Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift`
- Modify: `Sources/MetalCreatorApp/main.swift`
- Modify: `Tests/CreatorAppTests/LaunchSmokeTests.swift`
- Modify: `Tests/CreatorAppTests/ViewportPaneTests.swift`
- Modify: `Tests/CreatorViewportTests/ShaderSourceTests.swift`
- Delete: `Sources/CreatorApp/ViewportPlaceholder.swift`

**Interfaces:**
- Consumes: tasks 2, 6 and 7; MetalUI `SDLGPUDrawContext`, `SDLGPUFrameView`; `AppModel.viewport`.
- Produces: `final class SDLViewportBackend: ViewportBackend` (`init(renderer:)`, `convenience init(device:) throws`, `draw(_:in:scale:)`, `drawsWidgets`, false until task 10); `ViewportModel.draw(_: any GPUSurfaceContext)` for SDL; `LaunchSmoke.ViewportReport(frames:failure:)`, `LaunchSmoke.viewport`; `ViewportShaderCheck.run() throws -> String?`.

- [ ] **Step 1: Write the failing tests**

`LaunchSmokeTests` pin the verdict; `ViewportPaneTests` pin that the window has the viewport's GPU surface on every platform; `ViewportShaderDirectoryTests` also pins `ViewportShaderCheck`.

`Tests/CreatorAppTests/LaunchSmokeTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorAppTests/LaunchSmokeTests.swift
+++ b/Tests/CreatorAppTests/LaunchSmokeTests.swift
@@ -16,4 +16,27 @@
         #expect(smoke.passed)
         #expect(smoke.report == "MetalCreator smoke test: reached the first frame, ran 2.5 s.")
     }
+
+    @Test func aViewportThatDrewPassesAndSaysHowOften() {
+        let smoke = LaunchSmoke(seconds: 5)
+        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 3, failure: nil) }
+        #expect(!smoke.passed, "no first frame yet")
+        smoke.frameReached()
+        #expect(smoke.passed)
+        #expect(smoke.report == "MetalCreator smoke test: reached the first frame and the 3D viewport drew 3 frames, ran 5 s.")
+        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 1, failure: nil) }
+        #expect(smoke.report.contains("drew 1 frame,"))
+    }
+
+    @Test func aViewportThatDrewNothingFailsTheRunAndSaysWhy() {
+        let smoke = LaunchSmoke(seconds: 5)
+        smoke.frameReached()
+        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 0, failure: "The GPU could not create a pipeline.") }
+        #expect(!smoke.passed)
+        #expect(smoke.report == "MetalCreator smoke test: reached the first frame, but the 3D viewport drew nothing: "
+            + "The GPU could not create a pipeline.")
+        smoke.viewport = { LaunchSmoke.ViewportReport(frames: 0, failure: nil) }
+        #expect(!smoke.passed)
+        #expect(smoke.report.hasSuffix("drew nothing (it was never asked to draw)."))
+    }
 }
```

`Tests/CreatorAppTests/ViewportPaneTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorAppTests/ViewportPaneTests.swift
+++ b/Tests/CreatorAppTests/ViewportPaneTests.swift
@@ -4,27 +4,18 @@
 import Testing
 @testable import CreatorApp
 
-/// What fills the viewport's place in the window (cross-platform spec 2.3): the Metal 3D view on macOS and, where there is none,
-/// a card saying so. The layout, top bar and panels around it are the same.
+/// What fills the viewport's place in the window (cross-platform spec section 4): the real 3D view on every platform, drawn by Metal
+/// on macOS and by SDL_GPU on Linux and Windows. The layout, top bar and panels around it are the same.
 @MainActor
 struct ViewportPaneTests {
-    @Test func theCardSaysWhatTheSpecSays() {
-        #expect(ViewportPlaceholder.message == "The 3D view isn't available on this platform yet.")
+    @Test func theWindowHasTheViewportsGPUSurfaceWhereverItRuns() async throws {
+        let app = try await AppWindow.open()
+        #expect(app.window.scene.surfaces.count == 1, "the viewport's GPU surface fills its place, on every platform")
+        #expect(!app.window.scene.glyphs.isEmpty, "the top bar and panels draw around it")
     }
 
-    @Test func theWindowShowsTheCardExactlyWhereThereIsNoMetalView() async throws {
-        let app = try await AppWindow.open()
-        let cards = try app.window.elements { $0.label == ViewportPlaceholder.message || $0.value == ViewportPlaceholder.message }
-        #if canImport(Metal)
-        #expect(cards.isEmpty, "macOS draws the viewport")
-        #else
-        #expect(cards.count == 1, "the card stands in the viewport's place")
-        #endif
-        #expect(!app.window.scene.glyphs.isEmpty, "the top bar and panels draw whatever fills the viewport")
-    }
-
-    /// Sketch mode needs the viewport to draw on, which is xp-3's, but opening it must not trap and leaving it must work.
-    @Test func aSketchStillOpensAndClosesWithTheCardWhereTheViewportIs() async throws {
+    /// Sketch mode needs the viewport to draw on; opening it must not trap and leaving it must work.
+    @Test func aSketchOpensAndClosesWithTheViewportWhereItIs() async throws {
         var builder = GraphBuilder()
         let box = builder.sketchedBox(rectangleSketch())
         let app = try await AppWindow.open(builder.graph)
```

`Tests/CreatorViewportTests/ShaderSourceTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ShaderSourceTests.swift
+++ b/Tests/CreatorViewportTests/ShaderSourceTests.swift
@@ -147,8 +147,26 @@
 struct ViewportShaderDirectoryTests {
     @Test func everyStageLoadsForThePlatformsDriver() throws {
         #expect(try SDLViewportShaders.verify() == 16)
+        #expect(try ViewportShaderCheck.run() == "the viewport's 16 SDL_GPU shader stages were found")
     }
 
+    /// `--self-test` asks the viewport whether its shaders were built. With no directory it fails, and the message says which directory
+    /// it looked in, that the shaders are built and not checked in, and what to run (user decision U1(b)).
+    @Test func aMissingDirectoryFailsTheSelfTestCheckWithAMessageThatSaysWhatToRun() {
+        let nowhere = FileManager.default.temporaryDirectory.appending(path: "no-viewport-shaders-\(UUID().uuidString)")
+        do {
+            _ = try ViewportShaderCheck.run(sourceTree: nowhere)
+            Issue.record("the check passed with no compiled shaders anywhere")
+        } catch let failure as ViewportShaderCheck.Failure {
+            #expect(failure.description.contains(nowhere.path), "it names the directory it looked in: \(failure)")
+            #expect(failure.description.contains("scripts/build-shaders.sh"), "it names the script to run: \(failure)")
+            #expect(failure.description.contains("SDL_shadercross"), "it names the tool the script needs: \(failure)")
+            #expect(failure.description.contains("scripts/shadercross.env"), "it says where the pin is: \(failure)")
+        } catch {
+            Issue.record("the check threw \(error), not a ViewportShaderCheck.Failure")
+        }
+    }
+
     @Test func aStageThatIsMissingIsNamed() throws {
         let library = try SDLViewportShaders.library()
         #expect(throws: (any Error).self) { try library.vertex("no_such_shader", driver: SDLViewportShaders.platformDriver) }
```

- [ ] **Step 2: Run the tests: they fail**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests|LaunchSmokeTests|ViewportPaneTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests|LaunchSmokeTests|ViewportPaneTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. `value of type 'LaunchSmoke' has no member 'viewport'`, `cannot find 'ViewportShaderCheck' in scope`.

- [ ] **Step 3: Implement**

Delete `Sources/CreatorApp/ViewportPlaceholder.swift` (`git rm Sources/CreatorApp/ViewportPlaceholder.swift`).

`Tests/CreatorViewportTests/SDLViewportBackendTests.swift` (new; Linux and Windows only, like the other SDL suites):

```swift
#if canImport(MetalUISDLGPU)
import Testing
@testable import CreatorViewport

/// What the SDL backend tells the model about itself. (Its draw and its picks are `SDLRenderTests` and `SDLPickerTests`.)
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLViewportBackendTests {
    @Test func theBackendDrawsNoCubeYetSoTheModelDoesNotHitTestOne() throws {
        let rig = try SDLRenderRig()
        let backend = SDLViewportBackend(renderer: rig.renderer)
        #expect(!backend.drawsWidgets, "until task 10 there is no cube on screen, so none may rotate the camera")
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The Linux and Windows backend: the SDL_GPU renderer and the picker that reads its ID buffer back. The device is the window
/// renderer's, borrowed from the first draw, so it is kept no longer than the window.
@MainActor
final class SDLViewportBackend: ViewportBackend {
    let renderer: SDLViewportRenderer
    let picker: SDLViewportPicker

    init(renderer: SDLViewportRenderer) {
        self.renderer = renderer
        picker = SDLViewportPicker(renderer: renderer)
    }

    convenience init(device: SDLGPUDevice) throws {
        self.init(renderer: try SDLViewportRenderer(device: device, library: try SDLViewportShaders.library()))
    }

    /// No view cube or triad is drawn yet (task 10 draws them): the model must not hit-test a cube nobody can see.
    var drawsWidgets: Bool { false }

    var drawnFrames: Int { renderer.encodedPasses }

    var onPickReady: (@MainActor () -> Void)? {
        get { picker.onReady }
        set { picker.onReady = newValue }
    }

    func pick(at point: ScreenPoint, in frame: ViewportFrame) -> PickTarget? {
        picker.pick(at: point, in: frame)
    }

    func isPickPending(for frame: ViewportFrame) -> Bool {
        picker.isPending(for: frame)
    }

    func pickWhenReady(at point: ScreenPoint, in frame: ViewportFrame) async -> PickTarget? {
        await picker.pickWhenReady(at: point, in: frame)
    }

    /// Draws `frame` into the surface's target, in the frame's own command buffer, then starts the ID pass for it if it is for a view
    /// the picker has no buffer for. The ID pass is a batch of its own, submitted after the frame's buffer.
    func draw(_ frame: ViewportFrame, in view: SDLGPUFrameView, scale: Double) {
        renderer.encode(frame, into: view.target, scale: scale, commandBuffer: view.commandBuffer)
        picker.schedule(frame)
    }
}
#endif
```

`Sources/CreatorViewport/ViewportShaderCheck.swift` (new):

```swift
import Foundation

/// `MetalCreator --self-test` asks the viewport whether its shaders were built and ship: Metal compiles its source at run time, so
/// there is nothing to find on macOS; on Linux and Windows the SDL_GPU renderer needs the shaders compiled at build time
/// (`Shaders/viewport/compiled`, made by `scripts/build-shaders.sh` and git-ignored; `MetalUIAppShaders` beside the executable in a
/// shipped app, where packaging copied the build output), and a build without them draws nothing.
public enum ViewportShaderCheck {
    /// The check failed: the message says where it looked and what to run, in words a person new to the project can follow.
    public struct Failure: Error, CustomStringConvertible, LocalizedError, Equatable {
        public let description: String
        public var errorDescription: String? { description }
    }

    /// What a passing check reports, or `nil` where the viewport has no shader files to find. Throws a ``Failure``.
    public static func run() throws -> String? {
        #if canImport(MetalUISDLGPU)
        try run(sourceTree: SDLViewportShaders.sourceTree)
        #else
        nil
        #endif
    }

    /// The same check against another source-tree directory (the test points it at an empty one).
    static func run(sourceTree: URL) throws -> String? {
        #if canImport(MetalUISDLGPU)
        do {
            let stages = try SDLViewportShaders.verify(sourceTree: sourceTree)
            return "the viewport's \(stages.formatted()) SDL_GPU shader stages were found"
        } catch {
            throw Failure(description: "The viewport's compiled SDL_GPU shaders are missing or incomplete (\(error)). They are compiled at build time and are not in the repository: "
                + "run scripts/build-shaders.sh (scripts/build-shaders.ps1 on Windows), which needs SDL_shadercross at the commit pinned in scripts/shadercross.env, "
                + "and in a shipped app copy the result to MetalUIAppShaders beside the executable.")
        }
        #else
        return nil
        #endif
    }
}
```

`Sources/CreatorApp/LaunchSmoke.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorApp/LaunchSmoke.swift
+++ b/Sources/CreatorApp/LaunchSmoke.swift
@@ -1,15 +1,29 @@
 import Foundation
 
 /// `MetalCreator --smoke-test [seconds]` (CI, cross-platform spec §2.6): opens the real window over SDL's offscreen
-/// renderers, lets it run, and reports whether it reached its first frame. The window's root calls ``frameReached()`` from
-/// a `.task`, which MetalUI starts inside the first frame, so a run that never draws never sets it.
+/// renderers, lets it run, and reports whether it reached its first frame and whether the 3D viewport drew in it. The window's root
+/// calls ``frameReached()`` from a `.task`, which MetalUI starts inside the first frame, so a run that never draws never sets it; the
+/// viewport's count comes from ``viewport``, so a viewport whose GPU objects could not be made fails the run with the reason.
 @MainActor
 public final class LaunchSmoke {
     /// How long a smoke test runs when no number of seconds is given.
     public nonisolated static let defaultSeconds = 5.0
 
+    /// What the 3D viewport has done so far: the main passes it drew and, if its GPU objects could not be made, why not.
+    public struct ViewportReport: Sendable, Equatable {
+        public var frames: Int
+        public var failure: String?
+
+        public init(frames: Int, failure: String?) {
+            self.frames = frames
+            self.failure = failure
+        }
+    }
+
     public let seconds: Double
     public private(set) var reachedFirstFrame = false
+    /// Asks the app's viewport what it drew; `nil` for a run that has no viewport to check.
+    public var viewport: (@MainActor () -> ViewportReport)?
 
     public init(seconds: Double = LaunchSmoke.defaultSeconds) {
         self.seconds = seconds
@@ -20,15 +34,22 @@
         reachedFirstFrame = true
     }
 
-    /// Whether the run passed: it reached its first frame.
-    public var passed: Bool { reachedFirstFrame }
+    /// Whether the run passed: it reached its first frame and, where the viewport is checked, the viewport drew at least one.
+    public var passed: Bool {
+        guard reachedFirstFrame else { return false }
+        return viewport.map { $0().frames > 0 } ?? true
+    }
 
     /// The line printed when the time is up.
     public var report: String {
-        if reachedFirstFrame {
-            "MetalCreator smoke test: reached the first frame, ran \(seconds.formatted(.number)) s."
-        } else {
-            "MetalCreator smoke test: no frame was drawn in \(seconds.formatted(.number)) s."
+        let duration = seconds.formatted(.number)
+        guard reachedFirstFrame else { return "MetalCreator smoke test: no frame was drawn in \(duration) s." }
+        guard let state = viewport?() else { return "MetalCreator smoke test: reached the first frame, ran \(duration) s." }
+        if state.frames > 0 {
+            return "MetalCreator smoke test: reached the first frame and the 3D viewport drew \(state.frames.formatted()) "
+                + "frame\(state.frames == 1 ? "" : "s"), ran \(duration) s."
         }
+        let why = state.failure.map { ": \($0)" + ($0.hasSuffix(".") ? "" : ".") } ?? " (it was never asked to draw)."
+        return "MetalCreator smoke test: reached the first frame, but the 3D viewport drew nothing\(why)"
     }
 }
```

`Sources/CreatorApp/SelfTest.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorApp/SelfTest.swift
+++ b/Sources/CreatorApp/SelfTest.swift
@@ -5,6 +5,7 @@
 #if canImport(Metal)
 import Metal
 #elseif canImport(MetalUISDL)
+import CreatorViewport
 import MetalUISDL
 #endif
 
@@ -12,7 +13,7 @@
 /// window, that the app reaches everything it ships. The kernel check models, measures and meshes a cube on OCCT; the
 /// exports write STEP and STL, which run OCCT's data-exchange libraries; the shader check finds MetalUI's shader
 /// resource bundle and compiles it on the Metal device (off macOS it finds the SDL backend's compiled shader
-/// directory). The packaging script runs it on the finished `.app` with Homebrew's directories unreadable.
+/// directory and the viewport's own, `ViewportShaderCheck`). The packaging script runs it on the finished `.app` with Homebrew's directories unreadable.
 @MainActor
 public enum SelfTest {
     /// Runs every check in order. Exports are written into `scratch`, which is created and then removed.
@@ -65,7 +66,7 @@
         #if canImport(Metal)
         "MetalUI's shader bundle compiled"
         #else
-        "MetalUI's SDL shaders were found"
+        "MetalUI's SDL shaders and the viewport's were found"
         #endif
     }
 
@@ -78,6 +79,7 @@
         _ = try ShaderLibrary.make(device: device)
         #elseif canImport(MetalUISDL)
         _ = try SDLWindowRenderer.defaultShaderDirectory()
+        _ = try ViewportShaderCheck.run()
         #else
         // Neither Metal nor MetalUI's SDL backend: nothing here could draw, so the check must not pass silently.
         throw Failure("this build has neither Metal nor MetalUI's SDL backend, so there are no shaders to find.")
```

`Sources/CreatorApp/ViewportPane.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorApp/ViewportPane.swift
+++ b/Sources/CreatorApp/ViewportPane.swift
@@ -1,19 +1,16 @@
 import CreatorViewport
 import MetalUI
 
-/// The viewport's place in the window: the Metal 3D view where there is one, else the placeholder card. The one place the
-/// app shell asks which; everything else (the model, picking, the scene, sketch mode) is the same on every platform.
+/// The viewport's place in the window: the real 3D view on every platform (cross-platform spec section 4). It draws with Metal
+/// on macOS and with SDL_GPU, over Vulkan or Direct3D 12, on Linux and Windows; everything else (the model, picking, the scene,
+/// sketch mode) is the same on all of them.
 struct ViewportPane: Component {
     let model: ViewportModel
 
     var content: some ElementGroup {
-        #if canImport(Metal)
         // `ViewportView` has a `==`, but no `.equatable()` here: its `GPUSurface` makes an `.equatable()` Component ineligible
         // ("surface") even since MetalUI C14-h, so it only adds a content evaluation and a retainedIneligible per frame (measured
         // 2026-10-21 on every warm row; element requests unchanged, docs/verification/performance.md, "C14-f and C14-h adopted").
         ViewportView(model: model)
-        #else
-        ViewportPlaceholder()
-        #endif
     }
 }
```

`Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift
+++ b/Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift
@@ -1,9 +1,45 @@
-#if !canImport(Metal)
+#if canImport(MetalUISDLGPU)
+import MetalUI
+import MetalUISDL
+import MetalUISDLGPU
+
+extension ViewportModel {
+    /// The `GPUSurface` draw on SDL (spec §6.3; the Metal `draw` is `ViewportModel+Surface`). It runs on the main actor inside MetalUI's
+    /// frame, after the tracked build. It makes the GPU objects on first use and encodes into the frame's own command buffer, and
+    /// never submits it. It writes only untracked state (a draw must never dirty the window). If the GPU objects can't be made,
+    /// the surface is cleared to the dark red the Metal viewport shows.
+    func draw(_ context: any GPUSurfaceContext) {
+        guard let sdl = context as? SDLGPUDrawContext else {
+            context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
+            return
+        }
+        let view = sdl.view
+        guard let sdlBackend = sdlBackend(for: view.device) else {
+            sdl.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
+            return
+        }
+        sdlBackend.draw(frame(at: clock.now()), in: view, scale: sdl.scaleFactor > 0 ? Double(sdl.scaleFactor) : 1)
+    }
+
+    private func sdlBackend(for device: SDLGPUDevice) -> SDLViewportBackend? {
+        if let existing = backend as? SDLViewportBackend { return existing }
+        guard gpuFailure == nil else { return nil }
+        do {
+            let made = try SDLViewportBackend(device: device)
+            install(made)
+            return made
+        } catch {
+            gpuFailure = String(describing: error)
+            return nil
+        }
+    }
+}
+#elseif !canImport(Metal)
 import MetalUI
 
 extension ViewportModel {
-    /// The `GPUSurface` draw where there is no Metal. Until the SDL renderer is installed (xp-3 task 8) it clears the surface to the
-    /// colour a viewport whose GPU objects could not be made shows on macOS.
+    /// The `GPUSurface` draw in a build with neither Metal nor MetalUI's SDL GPU layer: it clears the surface to the colour a viewport
+    /// whose GPU objects could not be made shows on macOS.
     func draw(_ context: any GPUSurfaceContext) {
         context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
     }
```

`Sources/MetalCreatorApp/main.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/MetalCreatorApp/main.swift
+++ b/Sources/MetalCreatorApp/main.swift
@@ -58,6 +58,8 @@
                           forwarding: LaunchCommand.forwardedDocuments(path: path) { FileManager.default.fileExists(atPath: $0) })
     app.preferredColorScheme = .dark
     let model = AppModel(kernel: makeKernel(), themes: AppThemes.store(), implicitEngine: .automatic)
+    // The smoke test passes only if the real 3D viewport drew (`ViewportModel.drawnFrames`), not just the window around it.
+    smoke?.viewport = { LaunchSmoke.ViewportReport(frames: model.viewport.drawnFrames, failure: model.viewport.gpuFailureMessage) }
     let themeEditor = ThemeEditorModel(themes: model.themes)
     let input = AppInput(model: model)
     AppCommands.install(on: app, model: model, themeEditor: themeEditor)
```

- [ ] **Step 4: Run the tests: they pass**

```bash
swift build --build-tests 2>&1 | tail -3
swift test --filter 'CreatorViewportTests|LaunchSmokeTests|ViewportPaneTests|SelfTestTests' 2>&1 | grep -E 'recorded an issue|failed after|Test run with'
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests|LaunchSmokeTests|ViewportPaneTests|SelfTestTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- macOS: no `recorded an issue` or `failed after` line, and `Test run with 317 tests in 44 suites passed` (baseline 304/41 + 13 tests, + 3 suites); plus `11 tests in 3 suites` for the app filter.
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 318 tests in 43 suites passed` (baseline 259/34 + 59 tests, + 9 suites); plus `11 tests in 3 suites` for the app filter.

The CreatorAppTests run is the second line.
- [ ] **Step 5: Run the app's own checks on Linux**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh build
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh smoke
```

Expected: the build succeeds; `--self-test` prints `ok   shaders: MetalUI's SDL shaders and the viewport's were found` and exits 0; `--smoke-test 20` prints `MetalCreator smoke test: reached the first frame and the 3D viewport drew 1 frame, ran 20 s.` (the surface redraws on demand, so one frame is a window that stays still) and exits 0. If it prints `…the 3D viewport drew nothing: <reason>`, the reason is `ViewportModel.gpuFailureMessage`.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add Sources/CreatorApp/LaunchSmoke.swift \
  Sources/CreatorApp/SelfTest.swift \
  Sources/CreatorApp/ViewportPane.swift \
  Sources/CreatorApp/ViewportPlaceholder.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift \
  Sources/CreatorViewport/View/ViewportModel+SDLSurface.swift \
  Sources/CreatorViewport/ViewportShaderCheck.swift \
  Sources/MetalCreatorApp/main.swift \
  Tests/CreatorAppTests/LaunchSmokeTests.swift \
  Tests/CreatorAppTests/ViewportPaneTests.swift \
  Tests/CreatorViewportTests/SDLViewportBackendTests.swift \
  Tests/CreatorViewportTests/ShaderSourceTests.swift
git commit -m "viewport: SDL backend and surface draw, the real viewport in the window, a smoke test that sees it"
```


### Task 9: CI, packaging, CLAUDE.md, human checks and the spec's erratum

The Windows job runs the render suites on Direct3D 12's WARP and fails, instead of skipping, without a device (`XP_REQUIRE_GPU`); its comments and the Linux job's say so. **The packages ship the viewport's compiled shaders:** master's `scripts/package-linux.sh` and `scripts/package-windows.ps1` (xp-2) copy only MetalUI's own `MetalUISDLShaders`, so both now copy `Shaders/viewport/compiled` to `MetalUIAppShaders` beside the executable and stop, naming the script to run, when it was not built; the AppImage is packed from the tarball's tree and so carries it too; `scripts/linux-test.sh package` checks the directory in the clean Ubuntu, and the zip's self-test runs with the checkout's compiled directory moved aside, so the source-tree fallback cannot hide a package without it (Review Focus 7, human check XP-25). `CLAUDE.md` gets the xp-3 paragraph and its short edits; the human checks get a group XP3 (**XP-20 to XP-26**, after xp-2's XP-16 to XP-19) and XP-2 and XP-9 reworded; the cross-platform spec gets erratum **E7**. Then the first and only full `swift test` run on each platform, by the pass rule.

**Files:**
- Modify: `.github/workflows/xp.yml`
- Modify: `scripts/package-linux.sh`
- Modify: `scripts/package-windows.ps1`
- Modify: `scripts/linux-test.sh` (the package checks)
- Modify: `docs/packaging.md`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-10-13-cross-platform-design.md`
- Modify: `docs/verification/human-checks.md`

**Interfaces:**
- Consumes: tasks 0 to 8; `Shaders/viewport/compiled` (task 4); `ViewportShaderCheck` in `--self-test` (task 8).
- Produces: `MetalUIAppShaders` in the tarball, the AppImage and the zip; human checks XP-20 to XP-26; erratum E7; nothing code depends on.

- [ ] **Step 1: CI**

`.github/workflows/xp.yml` (change, on top of task 4's; apply with `git apply` or by hand):

```diff
--- a/.github/workflows/xp.yml
+++ b/.github/workflows/xp.yml
@@ -8,7 +8,9 @@
 # The Linux jobs run scripts/linux-test.sh, the script a developer runs in Docker on a Mac: build, the suite (exit 0, no
 # "recorded an issue" or "failed after" line, twelve "Test run with" lines), the app's --self-test, and --smoke-test 20, then
 # scripts/linux-test.sh package: a release tarball and an AppImage (packed from the tarball's tree by scripts/package-appimage.sh,
-# which downloads its pinned packer; no FUSE is needed), each unpacked or extracted and run in a clean Ubuntu.
+# which downloads its pinned packer; no FUSE is needed), each unpacked or extracted and run in a clean Ubuntu. The image draws on
+# Mesa's lavapipe (a CPU Vulkan driver), so the SDL_GPU viewport's render and pick suites run on these GPU-less runners, and
+# XP_REQUIRE_GPU=1 (set by the script) fails them instead of skipping when no device answers (xp-3).
 #
 # OpenCascade 7.9 (xp-2, spec section 3): on Linux it is built from a pinned commit in the Dockerfile's `occt` stage, which CI
 # builds alone with buildx and caches in the GitHub Actions cache (scope xp-occt-<arch>); the first run on a new key builds it
@@ -137,6 +139,9 @@
       # sha256 of SDL3-devel-3.4.16-VC.zip (computed by downloading the release asset once); bump it with SDL_VERSION.
       SDL_SHA256: 1a784cb2a5c64d56fe7a62090fe9d242d9865f235e4ea9678f1a6ba4e693e7de
       EXPECTED_TEST_RUNS: 12
+      # The viewport's SDL_GPU suites run on Direct3D 12's WARP (a CPU adapter) here; a runner without a device fails instead of
+      # skipping (SDLGPUAvailabilityTests, xp-3).
+      XP_REQUIRE_GPU: 1
     defaults:
       run:
         shell: pwsh
@@ -285,7 +290,7 @@
         # Runs even when Test is red, so one run reports both.
         if: ${{ !cancelled() }}
         # --smoke-test opens the real window over SDL's offscreen renderers (Direct3D 12 on WARP) for 20 s and fails unless it
-        # drew a first frame.
+        # drew a first frame and the 3D viewport drew in it (xp-3); --self-test also finds the viewport's compiled shaders.
         run: |
           $flags = @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB") +
                    @(Get-Content "$env:RUNNER_TEMP\accesskit-flags.txt")
```

- [ ] **Step 2: The packages ship the viewport's shaders (U7(a))**

`scripts/package-linux.sh` (change against master; apply with `git apply` or by hand):

```diff
--- a/scripts/package-linux.sh
+++ b/scripts/package-linux.sh
@@ -1,14 +1,16 @@
 #!/bin/bash
 # Builds dist/MetalCreator-<version>-linux-<arch>.tar.gz: a release build of MetalCreatorApp, the Swift runtime, OpenCascade, SDL3
 # and the other non-system shared libraries it needs in lib/, MetalUI's compiled SDL shaders in
-# MetalUISDLShaders beside the executable, the desktop entry, MIME type and icon for .mcgraph files, install.sh, and the licences.
+# MetalUISDLShaders and the 3D viewport's in MetalUIAppShaders beside the executable, the desktop entry, MIME type and icon for
+# .mcgraph files, install.sh, and the licences.
 # Unpacked, the folder runs from anywhere: the executable's rpath is $ORIGIN/lib (Package.swift).
 #
 # usage: scripts/package-linux.sh        (on Linux; scripts/linux-test.sh package runs it in the test image)
 #   METALCREATOR_DIST_DIR   where the tarball is written (default: <repo>/dist).
 #   METALCREATOR_SCRATCH    SwiftPM's build folder (default: <repo>/.build).
 #   OCCT_PREFIX             OpenCascade's install prefix (default /opt/occt), for its licence files.
-# Needs MetalUI beside this repository (../MetalUI), patchelf, and the libraries `ldd` names for the built executable.
+# Needs MetalUI beside this repository (../MetalUI), patchelf, the libraries `ldd` names for the built executable, and the viewport's
+# shaders compiled by scripts/build-shaders.sh (scripts/linux-test.sh package runs it first).
 set -euo pipefail
 
 ROOT="$(cd "$(dirname "$0")/.." && pwd)"
@@ -58,6 +60,11 @@
 SHADERS="$METALUI/Backends/SDL/Shaders/compiled"
 [ -f "$SHADERS/SOURCE.sha256" ] || fail "MetalUI's compiled shaders are missing: $SHADERS/SOURCE.sha256"
 cp -R "$SHADERS" "$FOLDER/MetalUISDLShaders"
+# The 3D viewport's own shaders (plan xp-3, user decision U7(a)): MetalUIAppShaders beside the executable, where the SDL renderer looks
+# first (MetalUI's SDLGPUShaderLibrary.locate). They are a build product, never in git: scripts/build-shaders.sh makes them.
+APP_SHADERS="$ROOT/Shaders/viewport/compiled"
+[ -f "$APP_SHADERS/SOURCE.sha256" ] || fail "the viewport's compiled shaders are missing ($APP_SHADERS): run scripts/build-shaders.sh first"
+cp -R "$APP_SHADERS" "$FOLDER/MetalUIAppShaders"
 
 step "Copying the non-system libraries it links, transitively"
 ldd "$BINARY" > "$WORK/ldd.txt"
```

`scripts/package-windows.ps1` (change against master; apply with `git apply` or by hand). `$appShaders` is set where the folder is assembled and used again by the zip's check:

```diff
--- a/scripts/package-windows.ps1
+++ b/scripts/package-windows.ps1
@@ -1,6 +1,6 @@
 # Builds dist\MetalCreator-<version>-windows-x64.zip: a release build of MetalCreatorApp as MetalCreator.exe, every DLL it
 # needs beside it (OpenCascade's, SDL3's, the Swift runtime's, the Visual C++ runtime's), MetalUI's compiled SDL shaders in
-# MetalUISDLShaders, the .mcgraph file-type script and the licences. The zip is then unpacked into a scratch folder and
+# MetalUISDLShaders, the 3D viewport's in MetalUIAppShaders, the .mcgraph file-type script and the licences. The zip is then unpacked into a scratch folder and
 # `MetalCreator.exe --self-test` runs from there with a PATH that holds only Windows' own folders, so a DLL that is missing
 # from the zip fails the build instead of the user's machine.
 #
@@ -13,7 +13,8 @@
 #                only look its folder up. CI does this, so that a failed release build is its own red step.
 # Environment: OCCT_PREFIX is OpenCascade's install root (bin\*.dll, share\opencascade\copyright); this script uses its release
 # set (`bin`), never `debug\bin`.
-# Needs MetalUI beside this repository (..\MetalUI). Not run outside CI.
+# Needs MetalUI beside this repository (..\MetalUI) and the viewport's shaders compiled by scripts\build-shaders.ps1 (CI runs it before
+# the build). Not run outside CI.
 param(
     [string[]]$BuildFlags = @(),
     [Parameter(Mandatory)][string]$SdlRoot,
@@ -53,6 +54,11 @@
 $shaders = Join-Path $metalUI 'Backends\SDL\Shaders\compiled'
 if (-not (Test-Path (Join-Path $shaders 'SOURCE.sha256'))) { throw "MetalUI's compiled shaders are missing: $shaders" }
 Copy-Item -Recurse $shaders (Join-Path $folder 'MetalUISDLShaders')
+# The 3D viewport's own shaders (plan xp-3, user decision U7(a)): MetalUIAppShaders beside the executable, where the SDL renderer looks
+# first. A build product, never in git: scripts\build-shaders.ps1 makes them.
+$appShaders = Join-Path $root 'Shaders\viewport\compiled'
+if (-not (Test-Path (Join-Path $appShaders 'SOURCE.sha256'))) { throw "the viewport's compiled shaders are missing ($appShaders): run scripts\build-shaders.ps1 first" }
+Copy-Item -Recurse $appShaders (Join-Path $folder 'MetalUIAppShaders')
 
 Step 'Copying the DLLs it needs, transitively'
 
@@ -216,13 +222,17 @@
 $savedPath = $env:PATH
 $env:PATH = "$system;$env:SystemRoot"
 # MetalUI's SDL backend falls back to the shaders in the source tree it was built from, which would hide a zip without
-# MetalUISDLShaders; so the checkout is moved aside for the check.
+# MetalUISDLShaders, and the viewport falls back to this checkout's Shaders\viewport\compiled, which would hide one without
+# MetalUIAppShaders; so both are moved aside for the check.
 $aside = "$metalUI.aside"
+$appShadersAside = "$appShaders.aside"
 Rename-Item $metalUI $aside
+Rename-Item $appShaders $appShadersAside
 try {
     & (Join-Path $check "$name\MetalCreator.exe") --self-test
     $code = $LASTEXITCODE
 } finally {
+    Rename-Item $appShadersAside $appShaders
     Rename-Item $aside $metalUI
     $env:PATH = $savedPath
 }
```

`scripts/linux-test.sh` (change, on top of task 4's; apply with `git apply` or by hand): the clean-Ubuntu checks look for the directory too (the `--self-test` they already run fails without it, because no source tree exists there to fall back to):

```diff
--- a/scripts/linux-test.sh
+++ b/scripts/linux-test.sh
@@ -132,6 +132,7 @@
         grep -q "RUNPATH from file ./MetalCreator" /tmp/ld.txt
         if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
         test -f MetalUISDLShaders/SOURCE.sha256 && ls lib | grep -q "^libTKernel.so.7.9$"
+        test -f MetalUIAppShaders/SOURCE.sha256 && test -s MetalUIAppShaders/mesh.vert.spv
         cd share/doc/metalcreator
         for f in NOTICE.txt LICENSE_LGPL_21.txt OCCT_LGPL_EXCEPTION.txt SDL3-LICENSE.txt Swift-LICENSE.txt; do test -s "$f"; done
         grep -q "V7_9_3" NOTICE.txt && grep -q "LGPL" NOTICE.txt'
@@ -149,6 +150,8 @@
         grep -q "RUNPATH from file .*/usr/metalcreator/MetalCreator" /tmp/ld.txt
         if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
         ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/share/mime/packages/*.xml" >/dev/null
+        ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/MetalUIAppShaders/*" >/dev/null
+        test -s squashfs-root/usr/metalcreator/MetalUIAppShaders/mesh.vert.spv
         test -f squashfs-root/usr/metalcreator/share/mime/packages/com.metalcreator.MetalCreator.xml
         ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/share/doc/metalcreator/*" >/dev/null
         cd squashfs-root/usr/metalcreator/share/doc/metalcreator
```

`docs/packaging.md` (change against master; apply with `git apply` or by hand):

```diff
--- a/docs/packaging.md
+++ b/docs/packaging.md
@@ -101,7 +101,8 @@
 write `dist/MetalCreator-<version>-linux-<arch>.tar.gz`. Unpacked, the folder holds `MetalCreator` (a release build), `lib/` (the Swift
 runtime's libraries, OpenCascade's `libTK*.so.7.9`, `libSDL3.so.0` and whatever else `ldd` names that is not glibc or
 the C++ runtime; linking the Swift runtime statically does not work with Foundation here), `MetalUISDLShaders/` (MetalUI's compiled SDL shaders, which the backend looks for beside the executable first,
-ruling `PX-P`), `share/applications/com.metalcreator.MetalCreator.desktop`, `share/mime/packages/com.metalcreator.MetalCreator.xml`,
+ruling `PX-P`), `MetalUIAppShaders/` (the 3D viewport's shaders, compiled by `scripts/build-shaders.sh` and looked for there first by
+MetalUI's `SDLGPUShaderLibrary.locate`; the script stops if they were not built), `share/applications/com.metalcreator.MetalCreator.desktop`, `share/mime/packages/com.metalcreator.MetalCreator.xml`,
 `share/icons/hicolor/256x256/apps/com.metalcreator.MetalCreator.png` (a placeholder icon), `install.sh` and `share/doc/metalcreator/` (the licences: OpenCascade's LGPL 2.1 and its exception, MetalUI's third-party notices and the
 licence files they name). The executable's RUNPATH is set to `$ORIGIN/lib` and each bundled library's to `$ORIGIN` (`patchelf`; the
 build's `/opt/occt/lib` and the toolchain's `/usr/lib/swift/linux` are left out), so the folder runs from anywhere and finds
@@ -147,7 +148,7 @@
 ```
 
 write `dist/MetalCreator-<version>-linux-<arch>.AppImage`. It holds the tarball's tree (so the same libraries, the same `RUNPATH
-$ORIGIN/lib` and `MetalUISDLShaders`) as `usr/metalcreator` in an AppDir whose root has `AppRun`, the same desktop entry and icon the
+$ORIGIN/lib`, `MetalUISDLShaders` and `MetalUIAppShaders`) as `usr/metalcreator` in an AppDir whose root has `AppRun`, the same desktop entry and icon the
 tarball installs, and a `.DirIcon` link; appimagetool packs it. The tool is appimagetool 1.9.1 and the runtime the type2 runtime
 20251108, both third-party and both fetched by the script while packaging, pinned by version and sha256 and checked before they run.
 They are no dependency of MetalCreator (nothing links them; a version bump changes the hashes in `scripts/package-appimage.sh`, whose
@@ -181,9 +182,9 @@
 It writes `dist\MetalCreator-<version>-windows-x64.zip` with `MetalCreator.exe`, every DLL the executable needs beside it (OpenCascade's
 from `OCCT_PREFIX\bin`, `SDL3.dll`, the Swift runtime's and the Visual C++ runtime's, found by following the `DLL Name:` lines of
 `llvm-objdump -p` (or `dumpbin /dependents` when the toolchain has no objdump); Windows' own DLLs are left out), `MetalUISDLShaders\`,
-`register-mcgraph.ps1` and `licenses\`. The Swift runtime's folder is looked up (by `swiftCore.dll`, under the `Swift` folder that
+`MetalUIAppShaders\` (the viewport's shaders, from `scripts\build-shaders.ps1`), `register-mcgraph.ps1` and `licenses\`. The Swift runtime's folder is looked up (by `swiftCore.dll`, under the `Swift` folder that
 `swift.exe` and `SDKROOT` sit in), not written down. The script then unpacks the zip and runs `--self-test` with only Windows'
-folders on `PATH` and MetalUI's checkout moved aside (the SDL backend falls back to the shaders in its source tree), so a missing DLL
+folders on `PATH` and MetalUI's checkout and the viewport's `Shaders\viewport\compiled` moved aside (both renderers fall back to the shaders in their source trees), so a missing DLL
 or shader directory fails the job. It packages a release build: CI makes it in its own step (`swift build -c release --product
 MetalCreatorApp`, then `-NoBuild`), because the suite is a debug build.
 
```

Check it on Linux (the AppImage step downloads its pinned packer, so it needs the network; a release build, so it is slow):

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh package 2>&1 | grep -E 'PASS|FAIL|ok |shaders|error'
```

Expected: `ok   shaders: MetalUI's SDL shaders and the viewport's were found` in both clean-Ubuntu self-tests, `Linux tarball: PASS (…)` and `Linux AppImage: PASS (…)`. To see the check bite once: `mv Shaders/viewport/compiled /tmp/xp3-compiled`, run `METALCREATOR_SCRATCH=… scripts/package-linux.sh` in the image (through `scripts/linux-test.sh package` it would recompile first), expect `package-linux: the viewport's compiled shaders are missing (…): run scripts/build-shaders.sh first`, and move the directory back. The zip is checked by CI's "Package (zip), checked on its own" step.

**CI time added by this plan (estimates).** Linux: the `shadercross` stage is built once per pin and arch by buildx and cached under `xp-shadercross-<arch>` (the DXC fork is an LLVM build: MetalUI measured 6 min 45 s at `-j8` on Linux aarch64, so expect 15 to 30 minutes on a 4-core runner the first time, about a minute to restore after); compiling 16 shaders natively and building MetalUI's tool take under a minute per run. Windows: about 10 minutes once per pin for `install-shadercross.ps1` (an estimate nobody has run), then a cache restore and the compile, a minute or two. The timeouts (150 minutes for Linux, 180 for Windows) cover it.

- [ ] **Step 3: Docs**

`CLAUDE.md` (change against master; apply with `git apply` or by hand). It keeps `CIPinTests`' phrases ("exit 0 and 12 \"Test run with\" lines"; no "11 \"Test run with\""):

````diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -114,15 +114,43 @@
 `::warning::` step and a summary line when its suite is red. On the way: `ImageResolver.read` has a Windows branch, the named-pipe and
 device tests and `PackagingScriptTests` are not run on Windows, and the test executables reserve a 16 MB stack (`-Xlinker /STACK:16777216`;
 a layout tree overflowed Windows' 1 MB default thread stack).
+Cross-platform, sub-project xp-3 (the 3D viewport on SDL GPU, Linux and Windows; plan `docs/superpowers/plans/2026-10-21-xp-3-sdl-gpu-viewport.md`,
+spec §4, erratum E7) is the viewport's second renderer. `ViewportModel` talks to a `ViewportBackend` (`drawnFrames`, `pick(at:in:)`,
+`isPickPending(for:)`, `pickWhenReady`, `onPickReady`, `drawsWidgets`): `MetalViewportBackend` on macOS (`ViewportRenderer` and `ViewportPicker`,
+unchanged), `SDLViewportBackend` on Linux and Windows (`Sources/CreatorViewport/RenderSDL`, everything behind `#if canImport(MetalUISDLGPU)`, MetalUI's
+typed SDL_GPU layer, no raw `SDL_` call). `ViewportView` is the same on both and picks `MetalView` or `GPUSurface`; `ViewportModel.draw` has one
+overload per context. The SDL renderer plans a frame first (`SDLFramePlan`: every buffer made and every copy recorded, because a copy pass cannot run
+inside a render pass) and then records the pass; solids, lines, fills, the cube and the slice read their data as vertex-stage storage buffers. Its
+pipelines carry their own depth test and are made with `compileGraphicsPipeline` (`SDLViewportPipelines`), so a refused one says SDL's reason in
+`gpuFailureMessage`. The shaders are HLSL in `Shaders/viewport` (`common.hlsli` mirrors the Swift structs, every member a `float4`, `uint4` or scalar,
+never a `float3`), **compiled at build time on Linux and Windows, never checked in**: `scripts/build-shaders.sh` (`.ps1` on Windows; `scripts/linux-test.sh`
+and CI run it before `swift build`) runs MetalUI's `MetalUICompileShaders`, built from `../MetalUI` with a scratch path of ours, through the
+SDL_shadercross commit pinned in `scripts/shadercross.env` (built by the Dockerfile's `shadercross` stage and `scripts/install-shadercross.ps1`) into
+`Shaders/viewport/compiled` (SPIR-V, DXIL, MSL, reflection, `SOURCE.sha256`, `INCLUDES.sha256`; git-ignored), so **`swift build` alone compiles no
+shader** and a missing tool stops the script naming the tool and the pin. `ShaderSourceTests` pins the HLSL struct sizes to the Swift strides
+(`GPUDataTests`) and, on Linux and Windows, that the build produced every stage and is current; edit the HLSL, the Swift struct and the MSL together.
+The compiled directory is found beside the executable as `MetalUIAppShaders` first, then in the source tree (`SDLViewportShaders`); the tarball, the
+AppImage and the zip ship it, and `--self-test` fails without it, saying what to run (`ViewportShaderCheck`). Picking is user decision U4, hybrid:
+`SDLViewportPicker` renders the ID pass in a batch after the draw that follows a change and reads it back with `SDLGPUDevice.download`; until it
+lands a hover keeps its face and a click waits for the buffer of its own view (asynchronously until MetalUI gap XP-G22) and goes to the tool of its
+press (`ViewportModel.isPickPending`, `pickWhenReady`, `ViewportBackendTests`). `Matrix4.float` is a `FloatMatrix4` and `FrameUniforms` is plain SIMD
+(no `simd`), so both exist everywhere. The cube's face names are rasterized by `CubeLabelAtlas.rasterize(using:)` through MetalUI's `TextSystem`
+(CoreText's on macOS, the portable one over the installed fonts elsewhere), `CubeLabelFonts` choosing. The render and pick suites (`SDLRenderTests`,
+`SDLFieldGuideClipTests`, `SDLPickerTests`, `SDLWidgetTests`, `SDLSliceTests`) run under Mesa's lavapipe in the Linux image and Direct3D 12's WARP in
+CI; they skip when no SDL_GPU device answers, and with `XP_REQUIRE_GPU=1` (`scripts/linux-test.sh`, the Windows job) `SDLGPUAvailabilityTests` fails
+instead. `--smoke-test` passes only if the viewport drew (`LaunchSmoke.viewport`). Tasks 10 to 12 add the view cube and the triad, the ghosts'
+depth-only prepass and the field slice (MetalUI S11's `setViewport`, `maxAnisotropy`, `writesColor`, `r32Float`); until each lands the SDL viewport
+lacks it (no cube or triad, and the model then leaves the cube's corner to the scene: `drawsWidgets`). Keep SDL's async calls out of loops that hold
+locals across an `await` (the Windows compiler notes below).
 `Package.swift` has two lists, like MetalUI's: the targets that import no Apple
-framework are declared everywhere (`CreatorViewport` too: its model, camera and tools are portable and only the Metal renderer files
-are behind `#if canImport(Metal)`); `ViewportHarness` and `GraphPanelPreview` are declared on macOS only, while `COCCT`,
+framework are declared everywhere (`CreatorViewport` too: its model, camera and tools are portable, its Metal renderer files
+are behind `#if canImport(Metal)` and its SDL GPU ones behind `#if canImport(MetalUISDLGPU)`); `ViewportHarness` and `GraphPanelPreview` are declared on macOS only, while `COCCT`,
 `CreatorOCCT` and `CreatorOCCTTests` are declared everywhere since xp-2 (OpenCascade 7.9 on every platform: `Package.swift` reads its
 install prefix from `OCCT_PREFIX`, default Homebrew's on macOS, `/opt/occt` on Linux, `C:/occt` on Windows, with per-platform linker
 flags: an `$ORIGIN/lib` rpath on Linux, DLLs on `PATH` or beside the executable on Windows). On Linux and Windows the MetalUI dependency asks for the `SDL` and `AccessKit` traits and
 `MetalCreatorApp` links `MetalUISDL` (`main.swift` picks `SDLPlatform` with `PortableTextSystem` over the installed fonts under
 `canImport(MetalUISDL)`). The app runs over `OCCTKernel` on every platform (xp-2; `KernelUnavailable`, which answers "Geometry isn't available on this
-platform yet.", stays in `CreatorKernel` for tests of a platform without a kernel) and, off macOS, the viewport's place shows `ViewportPlaceholder` ("The 3D view isn't available on this platform yet."). The Image
+platform yet.", stays in `CreatorKernel` for tests of a platform without a kernel) and, off macOS, the viewport draws on SDL GPU (xp-3; `ViewportPlaceholder` is gone). The Image
 Field works everywhere: `GreyImageDecoder` decodes through MetalUI's `DecodedImage` (S2, gap XP-G4) on every platform. Rules
 for new code: no CryptoKit (use `SHA256`/`SHA1` in `CreatorGraph/Hashing`), no CoreGraphics, ImageIO, CoreText or Metal outside a
 `#if canImport(…)` file or block, keyboard shortcuts and modifier checks on MetalUI events say `.primary` (⌘ on macOS, Ctrl
@@ -450,7 +478,7 @@
   `nonisolated static func ==`), and `expectEqualityCovers` (`CreatorEditorTests`) fails when a view gains a property its
   test has no variant for. The viewport draws `ViewportModel.theme`, which the
   app shell sets. Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
-- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView`.
+- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView` (macOS) and `GPUSurface` over SDL GPU (Linux and Windows, xp-3).
   - A host takes the primary pointer through `ViewportModel.tool` (`ViewportTool`: hover, clicks, and plain primary
     drags it claims, each with a `ViewportProjector` for screen → plane), and draws over the scene with
     `showOverlay(_:)` (`ViewportOverlay`: world-space lines and points in `OverlayTint` roles, dashed construction, and
@@ -467,7 +495,8 @@
     the camera animates: gap S5-c; each box is its text's measured width, MetalUI C23: see below). The face menu adds New Sketch on Face (`ViewportEvents.newSketchOnFace`) on a flat
     face that has a normal, outside sketch mode.
   - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
-    the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
+    the context menu and handles. `ViewportBackend` is what it needs from a renderer: `ViewportRenderer`/`ViewportPicker` (through
+    `MetalViewportBackend`) are the Metal side, `SDLViewportBackend` the SDL one. `ViewportView` is the
     MetalUI glue. A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
     solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
     (`ViewportRenderer+Guides`). The renderer keeps the triad's, the overlay's and the region fills' GPU buffers between
@@ -485,7 +514,8 @@
     ghost, and wrong-sized values draw the plain surface. A `ViewportSlice` (`ViewportModel.showSlice`) is a translucent quad over the
     scene showing a grid of values (`r32Float`, read with a bilinear blend in `slice_fragment`, kept by `SliceTextures` until its
     `generation` changes); it is equal and hashed by `generation`, never by its values, is drawn ignoring depth (it passes through the
-    part) and is never in the ID pass or `sceneBounds`. The viewport's shader source is `ViewportShaders.source + LineShaders.source + FieldShaders.source`.
+    part) and is never in the ID pass or `sceneBounds`. The viewport's Metal shader source is `ViewportShaders.source + LineShaders.source + FieldShaders.source` (MSL, compiled at run time);
+    the SDL renderer's is the HLSL in `Shaders/viewport`.
     The cut view (implicit spec §5.1) is a `ViewportClip` (`ViewportModel.showClip`): the fragment shaders discard what lies on the
     side its normal points to, for faces, B-rep edges, field tints and the ID pass (`ClipUniforms` at fragment buffer 3, 4 for the
     tint, 0 for lines, off for handles), and a back face seen while cutting is the part's colour darkened. A `ViewportItem`'s
@@ -675,7 +705,8 @@
 build)); a refused blend costs tens of milliseconds more than one that works (`BlendRefusalBench`,
 `docs/verification/performance.md`).
 MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
-The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
+The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift` and the HLSL in `Shaders/viewport/common.hlsli`; `GPUDataTests`
+pins their strides and `ShaderSourceTests` the HLSL's, so change all three together; the next build recompiles the HLSL (`scripts/build-shaders.sh`).
 The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
 `ViewportModel` (`dragChanged`/`dragEnded`/`dragCancelled(button:)`, `click(at:modifiers:)`, `modifiersChanged(_:)`,
 `contextMenuItems(at:)`, `scrolled(by:at:phase:)`, `pinchChanged`/`pinchEnded`, `cursor`), and `ViewportView` only forwards
@@ -735,7 +766,7 @@
 swift test --filter 'CreatorGraphTests.EvaluatorTests/wiredValuesFlowDownstream'   # one test
 swift test --filter CreatorNodesTests        # node definitions through the real Evaluator (OCCT where geometry matters)
 swift test --filter BracketAcceptanceTests   # the §7.2 bracket, headless
-swift test --filter CreatorViewportTests   # viewport model, maths and the offscreen ID pass (needs a Metal device)
+swift test --filter CreatorViewportTests   # viewport model, maths, the HLSL struct sizes, the build's shaders (Linux, Windows) and the offscreen render and ID passes (a GPU: Metal, or SDL_GPU on Linux and Windows)
 swift run ViewportHarness                  # dev window for docs/verification/human-checks.md group V
 swift test --filter CreatorEditorTests       # editor model + headless render tests
 swift run GraphPanelPreview                   # graph panel + inspector, for docs/verification/human-checks.md (M5)
@@ -753,7 +784,8 @@
 scripts/linux-test.sh [build|test|smoke|package|all|clean]   # the suite on Linux in Docker (OrbStack): swift build, swift test (12 "Test run with" lines), --self-test, --smoke-test 20
 scripts/linux-test.sh test --filter CreatorOCCTTests   # one target on Linux (no count rule); XP_TRACK=xp-2 IMAGE=metalcreator-linux:xp-2 keep a track's volume and image apart
 scripts/linux-test.sh package              # the tarball and the AppImage in dist/, each run in a clean ubuntu:24.04 (docs/packaging.md)
-swift run MetalCreatorApp --smoke-test 5   # a Linux or Windows build: the real window over SDL's offscreen renderers; exit 0 if a first frame was drawn
+swift run MetalCreatorApp --smoke-test 5   # a Linux or Windows build: the real window over SDL's offscreen renderers; exit 0 if a first frame was drawn and the 3D viewport drew
+scripts/build-shaders.sh                   # Linux: compile Shaders/viewport into Shaders/viewport/compiled (git-ignored) through MetalUI's MetalUICompileShaders and the pinned SDL_shadercross; linux-test.sh runs it. Windows: scripts/build-shaders.ps1
 ```
 
 Benchmarks (`Tests/CreatorAppTests/Bench`) are Swift Testing suites that print `BENCH …` lines and assert no time; a
@@ -774,7 +806,7 @@
   volume named for the track (`XP_TRACK`, default `xp-1`), and a run stops only its own container. MetalUI must be a sibling checkout.
   The image also holds OpenCascade 7.9 (xp-2); its first build takes minutes, then Docker's layer cache keeps it.
   Windows cannot be run here: it is CI's job (`.github/workflows/xp.yml`; it builds, tests with OpenCascade from vcpkg, launches and packages).
-- The Windows Swift 6.4 toolchain asserts in LLVM's coroutine splitting (`CoroFrame.cpp`, "Layout->getElementOffset") on an `async` function that holds a loop's locals across an `await` (`DrainHoles.drainPoints` did); keep the synchronous work in a non-async helper.
+- The Windows Swift 6.4 toolchain asserts in LLVM's coroutine splitting (`CoroFrame.cpp`, "Layout->getElementOffset") on an `async` function that holds a loop's locals across an `await` (`DrainHoles.drainPoints` did); keep the synchronous work in a non-async helper. In a release build it also crashes splitting the closure-specialised clone of an `async` function that takes a closure (`OccupancyGrid.fill(lipschitz:awaiting:)` did): mark such a thin wrapper `@_optimize(none)` with a comment and keep the heavy work in optimised synchronous helpers; pass no typed-throws closure to a generic helper. CI's Windows release build ("Build release (for the zip)") is the check; on this Mac the 6.4 asserts snapshot reproduces the crashes: `TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release`.
 - Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
 - OpenCascade 7.9 comes from Homebrew on macOS (`brew install opencascade`, linked from `/opt/homebrew/opt/opencascade`; linker
   warnings about dylibs built for a newer macOS are expected), from source on Linux (the `occt` stage of `scripts/linux/Dockerfile`,
````

`docs/superpowers/specs/2026-10-13-cross-platform-design.md` (change against master; apply with `git apply` or by hand). E6 is adopt-s9's, so xp-3's erratum is E7:

```diff
--- a/docs/superpowers/specs/2026-10-13-cross-platform-design.md
+++ b/docs/superpowers/specs/2026-10-13-cross-platform-design.md
@@ -162,3 +162,17 @@
   orientation" no longer holds: MetalUI S9 (record §117, master `d3ebfa18`) made the format, stored size and orientation readable without
   a decode, `GreyImageDecoder.inspect` uses `ImageInfo(data:)`, and `ImageHeader` is deleted. A small `OtherPictureSignature` stays so a
   GIF or TIFF is "not a PNG or JPEG" and not "damaged" (gap XP-G12).
+- **E7 (xp-3, section 4). The SDL GPU viewport.** Section 4 is implemented as follows. `CreatorViewport`'s renderer is behind
+  `ViewportBackend`; the Metal implementation is unchanged and the SDL one (`SDLViewportBackend`) lives in `Sources/CreatorViewport/RenderSDL`
+  behind `#if canImport(MetalUISDLGPU)`. The shaders are HLSL (`Shaders/viewport`, one source for the SDL renderer; the Metal renderer keeps its MSL
+  strings, so macOS is untouched), compiled at build time on Linux and Windows by MetalUI's `MetalUICompileShaders` (MetalUI S12, gap XP-G20) through a
+  pinned SDL_shadercross into SPIR-V, DXIL and MSL files that are not checked in (user decision U1(b)), and shipped beside the executable as
+  `MetalUIAppShaders` in the tarball, the AppImage and the zip. XP-G1 was answered by MetalUI S5 and S6, and what the typed layer still lacked, XP-G14 to
+  XP-G19 (a synchronous readback, viewport and scissor, a colour write mask, `r32Float`, anisotropy, a refused pipeline's reason), by MetalUI S11; all
+  are logged in `docs/metalui-gaps.md`. Picking differs from Metal in one way a person can see (user decision U4, hybrid): the ID buffer is rendered after
+  the draw that follows a change and a hover keeps its face for the few milliseconds until it lands; a click is always answered from a buffer for its own
+  view, waiting for it (asynchronously until MetalUI answers gap XP-G22, a render batch submitted without `await`). Until tasks 10 to 12 land, the
+  SDL viewport draws no view cube or triad, blends ghosts in one pass and draws no slice. `Matrix4.float` and `FrameUniforms` use plain SIMD types
+  (`FloatMatrix4`), `CubeLabelAtlas` rasterizes through MetalUI's `TextSystem`, `ViewportPlaceholder` is gone, `--smoke-test` requires the viewport to
+  have drawn, and `--self-test` checks the viewport's compiled shaders. Section 2.3's second bullet (the card) and human check XP-2 no longer hold.
+  Implicit evaluation and meshing stay on the CPU off macOS (xp-c).
```

`docs/verification/human-checks.md` (change against master; apply with `git apply` or by hand). xp-2's group XP2 ends with XP-19 (the AppImage), so xp-3's checks are XP-20 to XP-26 in a group of their own after it:

```diff
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -1810,9 +1810,8 @@
   on the right, in Dracula. Quitting (the window's close button, and File's quit where the platform has one) asks nothing on an
   unedited document. The top bar's top edge is fully visible below the strip (the root is not clipped by it: nothing in MetalCreator reads
   `Window.drawnChromeHeight`, spec erratum E3). Pinned: `--smoke-test` (`LaunchSmokeTests`). **Observed:**
-- [ ] **XP-2 The viewport card.** The area behind the panels shows the theme's gradient and one glass card, centred, reading "The
-  3D view isn't available on this platform yet."; the window's size changes keep the layout. Pinned: `ViewportPaneTests`.
-  **Observed:**
+- [ ] **XP-2 (superseded by XP-20).** xp-1 showed a card where the 3D view would be; xp-3 draws the real view and the card is gone. The
+  window's size changes keep the layout. Pinned: `ViewportPaneTests` (the window has the viewport's GPU surface). **Observed:**
 - [ ] **XP-3 Geometry badges.** Wire Rectangle → Extrude → Output: the Extrude's badge is the error and its text reads "Geometry
   isn't available on this platform yet."; the Rectangle's is fine. Editing a parameter, wiring, undo and redo, groups, notes and
   frames, and Save then Open all work. Pinned: `KernelUnavailableNodeTests`, `KernelUnavailableTests`. **Observed:**
@@ -1837,8 +1836,9 @@
   gap XP-G8) and not the move cursor, sharp on a 1x and a 2x display, and the panels' resize handles show the system resize cursors.
   On macOS the system closed hand is unchanged. Pinned: `GrabCursorTests`, `PanelResizeCursorTests` (the intent; the platform's shape is SDL's). **Observed:**
 - [ ] **XP-9 Self-test and smoke test.** `MetalCreatorApp --self-test` prints four `ok` lines (the kernel and both exports
-  "skipped: Geometry isn't available on this platform yet.", the shaders found) and exits 0; `--smoke-test 5` prints "reached the
-  first frame" and exits 0 on a desktop with a display too. Both pass in CI on Linux and Windows (Direct3D 12 on WARP; the
+  "skipped: Geometry isn't available on this platform yet.", MetalUI's shaders and the viewport's found; since xp-2 the kernel and the
+  exports run on OpenCascade) and exits 0; `--smoke-test 5` prints "reached the first frame and the 3D viewport drew" and exits 0 on a
+  desktop with a display too. Both pass in CI on Linux and Windows (Direct3D 12 on WARP; the
   smoke test opens `SDLPlatform(options: .headless)`, public since MetalUI S8, gap XP-G9); a desktop with a display is what is left to see. Pinned: `SelfTestTests`, `LaunchSmokeTests`. **Observed:**
 - [ ] **XP-10 A screen reader (optional).** With Orca on Linux or Narrator on Windows running, the top bar's buttons and the
   graph panel's nodes are announced by name (MetalUI's `AccessKit` trait). Not pinned: MetalUI's own tests cover the bridge.
@@ -2085,3 +2085,40 @@
   path/to/part.mcgraph` opens that file. The AppImage does not register the `.mcgraph` type itself (plan decision 2): register it with
   the three commands in `docs/packaging.md` ("Linux: an AppImage") or through the integration tool, then double-click a `.mcgraph`: it
   opens, and a second double-click goes to the running instance. **Observed:**
+
+## Group XP3 — the 3D viewport on SDL GPU, Linux and Windows (xp-3)
+
+**Status: NOT RUN.** Plan `2026-10-21-xp-3-sdl-gpu-viewport.md`; spec `docs/superpowers/specs/2026-10-13-cross-platform-design.md` §4 and
+erratum E7. CI renders and picks on Mesa's lavapipe (Linux) and Direct3D 12's WARP (Windows), and the packages' self-tests find the
+compiled shaders; these checks are what a real GPU, a real pointer and a person's eye show. Linux: build as for group XP after
+`scripts/build-shaders.sh` (or use the tarball or AppImage); Windows: the zip.
+
+- [ ] **XP-20 The 3D view draws (Linux and Windows).** On a real desktop GPU (Linux: Vulkan on Mesa or the vendor driver; Windows 11:
+  Direct3D 12) the area behind the panels is the theme's gradient with the ground grid fading into the distance, not a card. The §7.2
+  bracket (OpenCascade, xp-2) and a Mesh node (a TPMS lattice) show as shaded surfaces with their edges per the View menu's shading, and a
+  theme change in the theme editor recolours the gradient, the shading, the grid and the edges. The look is the macOS one: compare with a
+  Mac. **Pinned:** `SDLRenderTests` (lavapipe and WARP). **Observed:**
+- [ ] **XP-21 Orbit, pan and zoom.** Right-drag orbits, middle-drag and ⇧-drag pan, the wheel and a pinch zoom about the pointer, F frames
+  the part, with no tearing, no stale pixels after a resize or a move to a monitor of another scale, and a frame rate you cannot tell from
+  the Mac's. MSAA edges are smooth on a scale-2 display. **Pinned:** the model's tests; the feel is the check. **Observed:**
+- [ ] **XP-22 Hover and click on the SDL picker.** The face under the pointer tints cyan as it moves; it does not flicker to nothing while you
+  orbit and stop (a hover may show the old face for a frame or two after the camera stops, never a stall). A click right after an orbit
+  selects the face under the pointer, never empty space and never the face the old camera showed (it waits a few milliseconds for the ID
+  buffer of its own view), and an Edges by Tag pick made that way names the edge you clicked. In a sketch, clicks on the plane still place
+  points. **Until xp-3 task 10 lands** the top-left 96 × 96 points are the scene's, not a cube: hovering there picks the face under it,
+  clicking there selects it and does not turn the camera. **Pinned:** `ViewportBackendTests`, `SDLPickerTests`. **Observed:**
+- [ ] **XP-23 The widgets (after xp-3 task 10).** The view cube at the top left shows TOP, BOTTOM, FRONT, BACK, LEFT and RIGHT on its faces, upright
+  and readable at a slant, the hovered region cyan and the active one cyan; clicking a face, an edge or a corner turns the camera; the triad at the
+  bottom left follows the orbit with X red, Y green and Z blue. **Pinned:** `SDLWidgetTests`. **Observed:**
+- [ ] **XP-24 Ghosts, the field tint, the slice and the cut view.** A ghosted node's preview is one even, dimmed layer (no back faces showing
+  through, after task 11); a Field node's tint colours the surface by the ramp; a slice is a translucent quad coloured by the field (after
+  task 12); the Cut view removes one side of a part and shows the inside of its far wall darkened; a check's warning faces take the theme's
+  warning colour. **Pinned:** `SDLRenderTests` (ghosts), `SDLFieldGuideClipTests`, `SDLSliceTests`. **Observed:**
+- [ ] **XP-25 A shipped app finds its shaders.** Unpack the tarball (and run the AppImage, and unzip the zip on Windows) in a folder away from
+  any checkout: the viewport draws (its shaders are `MetalUIAppShaders` beside the executable), and `--self-test` says MetalUI's SDL
+  shaders and the viewport's were found. Moving the unpacked folder elsewhere keeps both working. **Pinned:** the clean-Ubuntu checks of
+  `scripts/linux-test.sh package` and the zip's self-test in `scripts/package-windows.ps1`. **Observed:**
+- [ ] **XP-26 macOS cube labels are unchanged.** On a Mac the view cube's six face names look as they did before xp-3: the same weight (semibold),
+  size and position, upright and readable at a slant. They are now rasterized through MetalUI's `CoreTextTextSystem` instead of a direct
+  `CTLineDraw`, so antialiasing may differ by a hair; anything more (a different weight, size or font) is a bug in
+  `CubeLabelAtlas.rasterize(using:)`. **Pinned:** `CubeLabelTests`, `OffscreenRenderTests.theFrontLabelIsPaintedOnTheFrontFace`. **Observed:**
```

- [ ] **Step 4: The full suites**

Linux first (cheap), then macOS once, then the push that runs CI. Nothing else is run per task from here; the macOS full run is not repeated until task 12.

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh all 2>&1 | tail -6
swift test 2>&1 | tee "${TMPDIR:-/tmp}/xp3-full.log" | grep -E 'recorded an issue|failed after'
grep -c 'Test run with' "${TMPDIR:-/tmp}/xp3-full.log"
grep 'Test run with' "${TMPDIR:-/tmp}/xp3-full.log" | sed -E 's/.*Test run with ([0-9]+) tests.*/\1/' | awk '{s += $1} END {print s}'
TOOLCHAINS=org.swift.64202605271a swift build -c release --scratch-path .build/asserts-release 2>&1 | grep -E 'error:|Assertion|While splitting|Build complete'
```

Expected: `Linux: PASS (12 'Test run with' lines, N tests; …)` with N the Linux full-suite baseline of task 0 plus 60 (59 in `CreatorViewportTests`, +2 `LaunchSmokeTests`, −1 `ViewportPaneTests`), then `--self-test` and `--smoke-test 20` as in task 8; on macOS no issue line, `12` lines, and a total of master's 4822 plus 14 = **4836** (13 in `CreatorViewportTests`, +2 `LaunchSmokeTests`, −1 `ViewportPaneTests`); the asserts release build `Build complete!`. After task 12 the macOS total is master + 15 (4837: task 12's `SliceTextureValuesTests`) and, if task 7 step 6 ran, one fewer. Then push `xp-3` and read the run: both Linux jobs green, and in the Windows job (continue-on-error) the Test step (12 lines), "Self-test and launch smoke", **"Build release (for the zip)"** and "Package (zip), checked on its own" green; a red Windows step shows as the warning step's summary line.

- [ ] **Step 5: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
bash -n scripts/linux-test.sh scripts/package-linux.sh && echo syntax-ok
git add .github/workflows/xp.yml \
  scripts/package-linux.sh scripts/package-windows.ps1 scripts/linux-test.sh docs/packaging.md \
  CLAUDE.md \
  docs/superpowers/specs/2026-10-13-cross-platform-design.md \
  docs/verification/human-checks.md
git commit -m "CI, packaging, docs: Windows renders on WARP, the packages ship MetalUIAppShaders, CLAUDE.md, human checks XP-20..26, erratum E7"
```


### Task 10: The view cube and the triad (MetalUI S11: `setViewport`, `maxAnisotropy`)

The view cube (96 x 96 points at the top left; its tiles, hover and active region cyan, and its six face names from the label atlas, mipmapped) and the axis triad (64 x 64 points at the bottom left) each draw in a square of the target with a camera of their own, as Metal's `setViewport` lets them: `SDLGPURenderPass.setViewport(x:y:width:height:)` (gap XP-G15). The face names are an `r8Unorm` texture with a full mip chain (`levelCount`, `generateMipmaps(of:)`, which needs `sampler` and `colorTarget` usage and runs outside a pass, so it is part of the plan), read through a linear sampler with 8x anisotropy (`maxAnisotropy`, gap XP-G18). The cube is convex, so back-face culling replaces a depth test and a face turned away hides its name. The cube hides with `showsViewCube`; a widget that does not fit the target is left out, as in Metal. Review Focus 5 is a test here: with a blank atlas (no installed font) the cube still draws, unlabelled.

This task's code was first built against a local copy of MetalUI patched with the signatures requested in `docs/metalui-gaps.md`; MetalUI S11 (`11dca65e`) then landed them, and every call here was checked against MetalUI `5f03ab7b`'s source on 2026-10-22: `SDLGPURenderPass.setViewport(x:y:width:height:minDepth:maxDepth:) -> Bool` (`@discardableResult`, top-left target pixels), `SDLGPUSamplerDescription(filter:mipmapFilter:repeats:maxLevel:maxAnisotropy:)`, `SDLGPUCommandBuffer.generateMipmaps(of:)`, `SDLGPURenderPass.bindFragmentSamplers(_:firstSlot:)`, `SDLGPUTextureDescription(width:height:format:usage:sampleCount:levelCount:)`. The only difference from the patch is the `Bool` result, which the calls ignore.

**Files:**
- Create: `Shaders/viewport/cube.frag.hlsl`
- Create: `Shaders/viewport/cube.vert.hlsl`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportCube.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Widgets.swift`
- Create: `Tests/CreatorViewportTests/SDLWidgetTests.swift`
- Modify: `Shaders/viewport/common.hlsli`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`
- Modify: `Tests/CreatorViewportTests/SDLViewportBackendTests.swift`
- Modify: `Tests/CreatorViewportTests/ShaderSourceTests.swift`
- Modify: `Tests/CreatorViewportTests/Support/SDLRenderRig.swift`

**Interfaces:**
- Consumes: task 6's plan and recorder; `CubeLabelFonts.atlas()` (task 3); `GPUGeometry.cubeVertices/triadInstances`; `ViewCubeLayout`, `TriadLayout`; MetalUI `SDLGPURenderPass.setViewport(x:y:width:height:minDepth:maxDepth:)`, `SDLGPUSamplerDescription(…, maxAnisotropy:)`, `SDLGPUCommandBuffer.generateMipmaps(of:)`.
- Produces: `SDLViewportRenderer.init(device:pipelines:labelAtlas:)` and the convenience `init(device:library:labelAtlas:)`; `SDLViewportCube`; `SDLFramePlan.Cube/Triad/WidgetViewport`; pipelines `cube`; shaders `cube.vert/frag` and `CubeVertex` in `common.hlsli`; `SDLRenderRig.init(labelAtlas:)`; `renderer.triadBuffer`.

- [ ] **Step 1: Confirm the MetalUI checkout has `setViewport` and `maxAnisotropy` (answered by MetalUI S11, `11dca65e`)**

No wait: master's pin `5f03ab7b` contains S11. Check that the sibling checkout the build uses does too (it is read, never changed):

```bash
git -C ../MetalUI merge-base --is-ancestor 11dca65e HEAD && echo has-S11
git -C ../MetalUI grep -n "public func setViewport\|public var maxAnisotropy" HEAD -- Backends/SDL/Sources/MetalUISDLGPU/SDLGPUGraphics.swift
```

Expected: `has-S11` and the declaration (`setViewport(x: Float, y: Float, width: Float, height: Float, minDepth: Float = 0, maxDepth: Float = 1) -> Bool`, `@discardableResult`, which this task's calls ignore; `maxAnisotropy: Float`, the last argument of `SDLGPUSamplerDescription.init`, capped at 16). If `../MetalUI` is behind `5f03ab7b`, it is not this branch's to move: ask whoever owns that checkout. `METALUI_COMMIT` in `.github/workflows/xp.yml` stays `5f03ab7b…` (no bump).

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorViewportTests/SDLWidgetTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import MetalUISDLGPU
import Testing
@testable import CreatorViewport

/// The view cube and the triad on SDL_GPU, each drawn into a square of the target with a camera of its own (`SDLGPURenderPass.setViewport`).
/// With `RenderFixtures`' 200 × 200 point view at 2 pixels per point, the cube is 96 points at (16, 16) and the triad 64 points at
/// (16, 120). The faces' names are a texture painted on the cube (`CubeLabelAtlas`).
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLWidgetTests {
    typealias Rig = SDLRenderRig

    /// The red channel of every pixel of a draw of `frame` in the front view, row by row.
    func redChannel(_ rig: Rig, _ frame: ViewportFrame) async throws -> [UInt8] {
        let bytes = try await rig.draw(frame)
        return stride(from: 2, to: bytes.count, by: 4).map { bytes[$0] }   // bgra: red is byte 2
    }

    /// The one test that reads colours back from the cube: its FRONT label is painted on the FRONT face. Looking from the front, the
    /// face is the cyan active region, and the #f8f8f2 ink (red ≈ 248, against cyan's 139) shows across the middle of the face and
    /// nowhere near its rim. Seen from behind, FRONT is culled.
    @Test func theFrontLabelIsPaintedOnTheFrontFace() async throws {
        let rig = try Rig()
        // The cube is 96 points at (16, 16), 2 pixels per point: centred on pixel (128, 128), with a face spanning ±96 / 1.8 ≈ ±53
        // pixels. The text box is ±0.8 of the face across and ±0.3 of it up and down.
        func inked(_ red: [UInt8], xs: ClosedRange<Int>, ys: ClosedRange<Int>) -> Int {
            ys.reduce(0) { count, y in count + xs.count { red[y * 400 + $0] > 195 } }
        }
        let fromFront = try await redChannel(rig, RenderFixtures.emptyFrame())
        let text = inked(fromFront, xs: 88...168, ys: 116...140)
        #expect(text > 150, "label ink across the middle of FRONT (\(text) pixels)")
        #expect(inked(fromFront, xs: 80...176, ys: 154...172) == 0, "no ink between the text and the face's rim")
        var behind = RenderFixtures.emptyFrame()
        behind.pose.yaw = .pi
        let fromBehind = try await redChannel(rig, behind)
        #expect(inked(fromBehind, xs: 88...168, ys: 116...140) > 150, "BACK's own label shows from behind")
        #expect(fromBehind != fromFront, "and FRONT's doesn't show through it")
    }

    /// A machine with no installed font (a minimal container, Windows Server Core) has no face names to paint; the cube still draws.
    @Test func aBlankAtlasLeavesTheCubeDrawnButUnlabelled() async throws {
        let blank = try Rig(labelAtlas: .blank)
        let red = try await redChannel(blank, RenderFixtures.emptyFrame())
        let inked = (116...140).reduce(0) { count, y in count + (88...168).count { red[y * 400 + $0] > 195 } }
        #expect(inked == 0, "no label ink (\(inked) pixels)")
        var hidden = RenderFixtures.emptyFrame()
        hidden.showsViewCube = false
        let withCube = try await blank.draw(RenderFixtures.emptyFrame())
        #expect(Rig.color(withCube, 64, 64) != Rig.color(try await blank.draw(hidden), 64, 64), "the cube's tiles are there")
        #expect(try await Rig().draw(RenderFixtures.emptyFrame()) != withCube, "and the labelled cube differs")
    }

    @Test func theCubeStaysInsideItsSquareAndIsHiddenWhenAskedTo() async throws {
        let rig = try Rig()
        let shown = try await rig.draw(RenderFixtures.emptyFrame())
        var hidden = RenderFixtures.emptyFrame()
        hidden.showsViewCube = false
        let without = try await rig.draw(hidden)
        #expect(Rig.color(shown, 64, 64) != Rig.color(without, 64, 64), "the cube covers the middle of its square")
        #expect(Rig.color(shown, 130, 64) == Rig.color(without, 130, 64), "and not the view beside it")
        #expect(Rig.color(shown, 100, 190) == Rig.color(without, 100, 190), "nor the bottom of the view")
    }

    @Test func aHoveredRegionChangesThePixelsOfTheCubeAndNoOthers() async throws {
        let rig = try Rig()
        var hovered = RenderFixtures.emptyFrame()
        hovered.pose = CameraPose(target: Vector3(0, 0, 15), distance: RenderFixtures.front.distance, yaw: 0.6, pitch: 0.4,
                                  projection: .orthographic)
        let plain = try await rig.draw(hovered)
        hovered.hoveredCubeRegion = .top
        let tinted = try await rig.draw(hovered)
        #expect(plain != tinted)
        #expect(Rig.color(plain, 100, 190) == Rig.color(tinted, 100, 190), "off the cube nothing changes")
    }

    @Test func theTriadDrawsItsThreeAxesInTheirColoursInItsOwnSquare() async throws {
        let rig = try Rig()
        var turned = RenderFixtures.emptyFrame()
        turned.pose = CameraPose(target: Vector3(0, 0, 15), distance: RenderFixtures.front.distance, yaw: 0.6, pitch: 0.4,
                                 projection: .orthographic)
        let bytes = try await rig.draw(turned)
        let palette = ViewportPalette.dracula
        // The triad's square: x 16…80, y 120…184 points (the view is 200 points tall; the bottom margin is 16).
        func near(_ colour: SIMD4<Float>) -> Int {
            let want = Rig.bytes(colour)
            var count = 0
            for y in 120..<184 {
                for x in 16..<80 {
                    let pixel = Rig.color(bytes, x, y)
                    if zip(pixel, want).allSatisfy({ abs($0 - $1) <= 24 }) { count += 1 }
                }
            }
            return count
        }
        #expect(near(palette.axisX) > 8, "red axis")
        #expect(near(palette.axisY) > 8, "green axis")
        #expect(near(palette.axisZ) > 8, "blue axis")
        #expect(Rig.color(bytes, 150, 150) == Rig.color(try await rig.draw(turned), 150, 150))
    }

    @Test func theTriadAndCubeBuffersSurviveAnOrbitAndFollowThePalette() async throws {
        let rig = try Rig()
        try await rig.draw(RenderFixtures.emptyFrame())
        let first = try #require(rig.renderer.triadBuffer)
        var orbited = RenderFixtures.emptyFrame()
        orbited.pose.yaw += 0.3
        try await rig.draw(orbited)
        #expect(try #require(rig.renderer.triadBuffer).buffer === first.buffer, "an orbit turns the widget's camera, not its instances")
        var other = RenderFixtures.emptyFrame()
        other.palette = ViewportPalette(.alucard)
        try await rig.draw(other)
        #expect(try #require(rig.renderer.triadBuffer).buffer !== first.buffer)
    }

    @Test func aWidgetThatDoesNotFitTheTargetIsLeftOut() async throws {
        let rig = try Rig()
        var cramped = RenderFixtures.emptyFrame()
        cramped.cube = ViewCubeLayout(origin: ScreenPoint(150, 16), side: 96)   // runs past the view's right edge
        cramped.triad = TriadLayout(side: 64, leading: 150, bottom: 16)
        let drawn = try await rig.draw(cramped)
        var hidden = cramped
        hidden.showsViewCube = false
        #expect(drawn[0..<64] == (try await rig.draw(hidden))[0..<64])
        #expect(rig.renderer.encodedPasses == 2, "the pass itself still runs")
    }
}
#endif
```

`Tests/CreatorViewportTests/ShaderSourceTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ShaderSourceTests.swift
+++ b/Tests/CreatorViewportTests/ShaderSourceTests.swift
@@ -77,6 +77,7 @@
             "LineInstance": MemoryLayout<LineInstance>.stride, "LineUniforms": MemoryLayout<LineUniforms>.stride,
             "GridUniforms": MemoryLayout<GridUniforms>.stride, "FillVertex": MemoryLayout<FillVertex>.stride,
             "ClipUniforms": MemoryLayout<ClipUniforms>.stride, "FieldRampUniforms": MemoryLayout<FieldRampUniforms>.stride,
+            "CubeVertex": MemoryLayout<CubeVertex>.stride,
         ]
         #expect(sizes.count == (try Self.structs().count), "every struct in the header is made of float4, uint4, float2, float and uint")
         for (name, expected) in swift {
@@ -115,7 +116,7 @@
     /// `INCLUDES.sha256` it wrote match the sources and the header now. A source edited after the last build fails here and says so.
     @Test func theBuildCompiledEveryStageIntoTheDirectoryTheRendererReads() throws {
         let sources = Self.stageSources
-        #expect(sources.count >= 16, "the viewport's vertex and fragment stages are found")
+        #expect(sources.count >= 18, "the viewport's vertex and fragment stages are found")
         let compiled = try #require(Self.runtimeDirectory, "no compiled shader directory beside the executable or in the source tree. \(Self.remedy)")
         for source in sources {
             let stem = String(source.lastPathComponent.dropLast(".hlsl".count))
@@ -146,8 +147,8 @@
 /// the source tree's, holds every stage for the platform's driver, with its reflection.
 struct ViewportShaderDirectoryTests {
     @Test func everyStageLoadsForThePlatformsDriver() throws {
-        #expect(try SDLViewportShaders.verify() == 16)
-        #expect(try ViewportShaderCheck.run() == "the viewport's 16 SDL_GPU shader stages were found")
+        #expect(try SDLViewportShaders.verify() == 18)
+        #expect(try ViewportShaderCheck.run() == "the viewport's 18 SDL_GPU shader stages were found")
     }
 
     /// `--self-test` asks the viewport whether its shaders were built. With no directory it fails, and the message says which directory
```

`Tests/CreatorViewportTests/Support/SDLRenderRig.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/Support/SDLRenderRig.swift
+++ b/Tests/CreatorViewportTests/Support/SDLRenderRig.swift
@@ -14,12 +14,13 @@
     let picker: SDLViewportPicker
     let target: SDLGPUTexture
 
-    init() throws {
+    /// `labelAtlas` is the cube's face names: the installed fonts' by default.
+    init(labelAtlas: CubeLabelAtlas = CubeLabelFonts.atlas()) throws {
         guard let device = SDLTestDevice.shared, let pipelines = SDLTestDevice.pipelines else {
             throw SDLRigError(description: "no SDL_GPU device: \(SDLGPUDevice.lastFailure)")
         }
         self.device = device
-        renderer = SDLViewportRenderer(device: device, pipelines: pipelines)
+        renderer = SDLViewportRenderer(device: device, pipelines: pipelines, labelAtlas: labelAtlas)
         picker = SDLViewportPicker(renderer: renderer)
         guard let target = device.makeTexture(SDLGPUTextureDescription(
             width: Self.pixels, height: Self.pixels, format: .b8g8r8a8Unorm, usage: [.colorTarget, .sampler])) else {
```

- [ ] **Step 3: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'SDLWidgetTests|ShaderSourceTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. Linux: `extra argument 'labelAtlas' in call`, `cannot find 'CubeVertex' in scope`.

- [ ] **Step 4: Implement**

`Shaders/viewport/cube.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

// The face's name, from the label atlas (r8 coverage, mipmapped), blended in `ink` over the tile's colour (hover and active
// cyan included). uv 0...1 is the text box. Outside it, or with an empty rect, there is no ink. The gradient is taken before
// clamping to the rect, so the mip level stays smooth up to the box's edge.
Texture2D<float> labels : register(t0, space2);
SamplerState atlas : register(s0, space2);
cbuffer Ink : register(b0, space3) { float4 ink; };

struct In {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    nointerpolation float4 labelRect : TEXCOORD2;
};

float4 main(In input) : SV_Target0 {
    float2 atlasUV = lerp(input.labelRect.xy, input.labelRect.zw, input.uv);
    float2 inRect = clamp(atlasUV, input.labelRect.xy, input.labelRect.zw);
    float coverage = labels.SampleGrad(atlas, inRect, ddx(atlasUV), ddy(atlasUV));
    bool inside = all(input.uv >= 0.0) && all(input.uv <= 1.0) && input.labelRect.z > input.labelRect.x;
    float3 rgb = lerp(input.color.rgb, ink.rgb, inside ? coverage * ink.a : 0.0);
    return float4(rgb * input.color.a, input.color.a);
}
```

`Shaders/viewport/cube.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The view cube: two triangles per tile, in the viewport the renderer sets for it.
StructuredBuffer<CubeVertex> vertices : register(t0, space0);
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };

struct Out {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    nointerpolation float4 labelRect : TEXCOORD2;
};

Out main(uint vid : SV_VertexID) {
    CubeVertex v = vertices[vid];
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(v.position.xyz, 1.0));
    output.color = v.color;
    output.uv = v.uv;
    output.labelRect = v.labelRect;
    return output;
}
```

`Sources/CreatorViewport/RenderSDL/SDLViewportCube.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import Foundation
import MetalUISDLGPU

/// The view cube's GPU resources: its tiles, kept until the hover, the camera or the palette changes so a frame of a continuous orbit
/// makes no buffer (spec §7.3's 60 fps), and its face-name texture, made once (the `ViewCubeResources` of the SDL renderer).
final class SDLViewportCube: @unchecked Sendable {
    /// The tiles and what they were built from.
    private struct CachedTiles {
        var hovered: ViewCubeRegion?
        var pose: CameraPose
        var palette: ViewportPalette
        var buffer: SDLGPUBuffer
        var count: Int
    }

    private let device: SDLGPUDevice
    private let atlas: CubeLabelAtlas
    private var tiles: CachedTiles?
    private var labels: SDLGPUTexture?
    /// Linear between texels and between mip levels, clamped at the edge, anisotropic up to 8× (the cube is seen at a slant).
    let sampler: SDLGPUSampler?

    init(device: SDLGPUDevice, atlas: CubeLabelAtlas) {
        self.device = device
        self.atlas = atlas
        sampler = device.makeSampler(SDLGPUSamplerDescription(filter: .linear, mipmapFilter: .linear, maxAnisotropy: 8))
    }

    /// The tiles in `palette`'s colours, rebuilt when the hover, the camera or the palette (the theme) changes.
    func vertices(hovered: ViewCubeRegion?, pose: CameraPose, palette: ViewportPalette,
                  uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let tiles, tiles.hovered == hovered, tiles.pose == pose, tiles.palette == palette { return (tiles.buffer, tiles.count) }
        let vertices = GPUGeometry.cubeVertices(hovered: hovered, pose: pose, palette: palette)
        guard let buffer = uploader.storageBuffer(vertices) else { return nil }
        tiles = CachedTiles(hovered: hovered, pose: pose, palette: palette, buffer: buffer, count: vertices.count)
        return (buffer, vertices.count)
    }

    /// The label atlas as an `r8Unorm` texture with a full mip chain, uploaded on first use by copies recorded in the uploader's
    /// command buffer, so call it before the pass that samples it begins. `nil` if SDL refuses the texture or the buffer.
    func labelTexture(uploader: SDLViewportUploader) -> SDLGPUTexture? {
        if let labels { return labels }
        let levels = Int(log2(Double(max(atlas.width, atlas.height)))) + 1
        guard let texture = device.makeTexture(SDLGPUTextureDescription(
                  width: atlas.width, height: atlas.height, format: .r8Unorm, usage: [.sampler, .colorTarget], levelCount: levels)),
              let transfer = device.makeTransferBuffer(size: atlas.pixels.count, direction: .upload),
              let memory = transfer.map() else { return nil }
        let copied = atlas.pixels.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            memory.copyMemory(from: base, byteCount: bytes.count)
            return true
        }
        transfer.unmap()
        guard copied else { return nil }
        uploader.commandBuffer.copy(transfer, to: texture, mipLevel: 0)
        uploader.commandBuffer.generateMipmaps(of: texture)
        labels = texture
        return texture
    }
}
#endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Widgets.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import MetalUISDLGPU

extension SDLViewportRenderer {
    /// The view cube in its own square at the top-left, or `nil` when it is hidden, does not fit the target, or its face names or
    /// tiles could not be made. A cube is convex, so back-face culling replaces a depth test, and a face turned away hides its name.
    func planCube(_ frame: ViewportFrame, scale: Double, width: Int, height: Int,
                  _ uploader: SDLViewportUploader) -> SDLFramePlan.Cube? {
        guard frame.showsViewCube else { return nil }
        let layout = frame.cube
        let x = layout.origin.x * scale, y = layout.origin.y * scale, side = layout.side * scale
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let labels = cube.labelTexture(uploader: uploader), let sampler = cube.sampler,
              let tiles = cube.vertices(hovered: frame.hoveredCubeRegion, pose: frame.pose, palette: frame.palette,
                                        uploader: uploader) else { return nil }
        let camera = GPUGeometry.frameUniforms(layout.widgetPose(frame.pose), size: layout.widgetSize, sceneRadius: 2,
                                               pixelWidth: Int(side), pixelHeight: Int(side))
        return SDLFramePlan.Cube(tiles: tiles.buffer, count: tiles.count, labels: labels, sampler: sampler,
                                 ink: frame.palette.cubeLabel,
                                 viewport: SDLFramePlan.WidgetViewport(x: Float(x), y: Float(y), side: Float(side), camera: camera))
    }

    /// The axis triad in its own square at the bottom-left, or `nil` when it does not fit the target.
    func planTriad(_ frame: ViewportFrame, scale: Double, width: Int, height: Int,
                   _ uploader: SDLViewportUploader) -> SDLFramePlan.Triad? {
        let triad = frame.triad
        let origin = triad.origin(in: frame.size)
        let x = origin.x * scale, y = origin.y * scale, side = triad.side * scale
        guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
              let lines = triadInstances(scale: Float(scale), palette: frame.palette, uploader) else { return nil }
        let camera = GPUGeometry.frameUniforms(triad.widgetPose(frame.pose),
                                               size: ViewportSize(width: triad.side, height: triad.side), sceneRadius: 2,
                                               pixelWidth: Int(side), pixelHeight: Int(side))
        return SDLFramePlan.Triad(
            lines: SDLFramePlan.Lines(buffer: lines.buffer, count: lines.count, style: Self.plainLines),
            viewport: SDLFramePlan.WidgetViewport(x: Float(x), y: Float(y), side: Float(side), camera: camera))
    }

    /// The triad's instances in GPU memory, kept until the scale or the palette change.
    private func triadInstances(scale: Float, palette: ViewportPalette,
                                _ uploader: SDLViewportUploader) -> (buffer: SDLGPUBuffer, count: Int)? {
        if let cached = triadBuffer, cached.scale == scale, cached.palette == palette { return (cached.buffer, cached.count) }
        let instances = GPUGeometry.triadInstances(scale: scale, palette: palette)
        guard let buffer = uploader.storageBuffer(instances) else {
            triadBuffer = nil
            return nil
        }
        triadBuffer = (scale, palette, buffer, instances.count)
        return (buffer, instances.count)
    }

    /// Draws the cube into its square: the viewport maps clip space into it, and its camera is the cube's own.
    func drawCube(_ cube: SDLFramePlan.Cube, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(cube.viewport.camera))
        pass.setViewport(x: cube.viewport.x, y: cube.viewport.y, width: cube.viewport.side, height: cube.viewport.side)
        recorder.bind(pipelines.cube)
        pass.bindVertexStorageBuffers([cube.tiles])
        pass.bindFragmentSamplers([(texture: cube.labels, sampler: cube.sampler)])
        pass.pushFragmentUniform(uniformBytes(cube.ink), at: 0)
        pass.draw(vertexCount: cube.count)
    }

    /// Draws the triad into its square with its own camera.
    func drawTriad(_ triad: SDLFramePlan.Triad, in pass: SDLGPURenderPass) {
        let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(triad.viewport.camera))
        pass.setViewport(x: triad.viewport.x, y: triad.viewport.y, width: triad.viewport.side, height: triad.viewport.side)
        drawLines(triad.lines, pipeline: pipelines.lineAlways, in: recorder)
    }
}
#endif
```

`Shaders/viewport/common.hlsli` (change; apply with `git apply` or by hand):

```diff
--- a/Shaders/viewport/common.hlsli
+++ b/Shaders/viewport/common.hlsli
@@ -69,6 +69,14 @@
     float4 color;
 };
 
+struct CubeVertex {
+    float4 position;
+    float4 color;
+    float2 uv;
+    float2 padding;
+    float4 labelRect;
+};
+
 /// The cut view's plane: a point is cut away when dot(plane.xyz, p) + plane.w > 0. `enabled` is 0 for no cut.
 struct ClipUniforms {
     float4 plane;
```

`Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift
@@ -21,6 +21,30 @@
         var clip: ClipUniforms = .off
     }
 
+    /// A square of the target, in pixels from its top left, that a widget (the view cube, the triad) draws into with a camera of its own.
+    struct WidgetViewport {
+        var x: Float
+        var y: Float
+        var side: Float
+        var camera: FrameUniforms
+    }
+
+    /// The view cube's tiles, its face-name texture with the sampler it is read through, and the ink the names are painted in.
+    struct Cube {
+        var tiles: SDLGPUBuffer
+        var count: Int
+        var labels: SDLGPUTexture
+        var sampler: SDLGPUSampler
+        var ink: SIMD4<Float>
+        var viewport: WidgetViewport
+    }
+
+    /// The axis triad's lines.
+    struct Triad {
+        var lines: Lines
+        var viewport: WidgetViewport
+    }
+
     var opaque: [Solid] = []
     var ghosts: [Solid] = []
     var edges: [Lines] = []
@@ -30,5 +54,7 @@
     var fills: (buffer: SDLGPUBuffer, count: Int)?
     var overlay: Lines?
     var handles: Lines?
+    var cube: Cube?
+    var triad: Triad?
 }
 #endif
```

`Tests/CreatorViewportTests/SDLViewportBackendTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/SDLViewportBackendTests.swift
+++ b/Tests/CreatorViewportTests/SDLViewportBackendTests.swift
@@ -6,10 +6,10 @@
 @MainActor
 @Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
 struct SDLViewportBackendTests {
-    @Test func theBackendDrawsNoCubeYetSoTheModelDoesNotHitTestOne() throws {
+    @Test func theBackendDrawsTheCubeSoTheModelMayHitTestIt() throws {
         let rig = try SDLRenderRig()
         let backend = SDLViewportBackend(renderer: rig.renderer)
-        #expect(!backend.drawsWidgets, "until task 10 there is no cube on screen, so none may rotate the camera")
+        #expect(backend.drawsWidgets, "task 8 had no cube to draw and said false; from task 10 the cube and triad are drawn")
     }
 }
 #endif
```

`Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift
@@ -14,11 +14,12 @@
     }
 
     convenience init(device: SDLGPUDevice) throws {
-        self.init(renderer: try SDLViewportRenderer(device: device, library: try SDLViewportShaders.library()))
+        self.init(renderer: try SDLViewportRenderer(device: device, library: try SDLViewportShaders.library(),
+                                                    labelAtlas: CubeLabelFonts.atlas()))
     }
 
-    /// No view cube or triad is drawn yet (task 10 draws them): the model must not hit-test a cube nobody can see.
-    var drawsWidgets: Bool { false }
+    /// The renderer draws the view cube and the axis triad (`SDLViewportRenderer+Widgets`), so the model hit-tests the cube.
+    var drawsWidgets: Bool { true }
 
     var drawnFrames: Int { renderer.encodedPasses }
 
```

`Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
@@ -27,17 +27,19 @@
     let lineBehind: SDLGPUGraphicsPipeline
     /// The ground grid: blended, tested against the solids without writing.
     let grid: SDLGPUGraphicsPipeline
+    /// The view cube: blended, never depth-tested (a cube is convex, so back-face culling does the hiding).
+    let cube: SDLGPUGraphicsPipeline
     let idMesh: SDLGPUGraphicsPipeline
     let idLine: SDLGPUGraphicsPipeline
 
     init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
         func pipeline(_ vertex: String, _ fragment: String, primitive: SDLGPUPrimitiveType = .triangleList,
-                      color: SDLGPUTextureFormat = Self.colorFormat, blend: SDLGPUBlend = .none,
+                      cull: SDLGPUCullMode = .none, color: SDLGPUTextureFormat = Self.colorFormat, blend: SDLGPUBlend = .none,
                       samples: SDLGPUSampleCount = Self.sampleCount,
                       depth: SDLGPUDepthState) throws -> SDLGPUGraphicsPipeline {
             let description = SDLGPUGraphicsPipelineDescription(
                 vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
-                primitiveType: primitive, cullMode: .none, colorFormat: color, blend: blend, sampleCount: samples, depth: depth)
+                primitiveType: primitive, cullMode: cull, colorFormat: color, blend: blend, sampleCount: samples, depth: depth)
             do {
                 return try device.compileGraphicsPipeline(description)
             } catch {
@@ -58,6 +60,7 @@
         lineAlways = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: always)
         lineBehind = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: behind)
         grid = try pipeline("grid", "grid", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
+        cube = try pipeline("cube", "cube", cull: .back, blend: .premultipliedAlpha, depth: always)
         idMesh = try pipeline("id_mesh", "id_mesh", color: Self.idFormat, samples: .one, depth: writes)
         idLine = try pipeline("id_line", "id_line", primitive: .triangleStrip, color: Self.idFormat, samples: .one, depth: tests)
     }
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift
@@ -6,7 +6,9 @@
 extension SDLViewportRenderer {
     /// Makes every buffer the main pass reads and records the copies that fill them (`commandBuffer` is the uploader's). The layers
     /// are the Metal renderer's, in the order it draws them: solids, edges, guides, overlay, handles.
-    func plan(_ frame: ViewportFrame, scale: Float, uploader: SDLViewportUploader) -> SDLFramePlan {
+    func plan(_ frame: ViewportFrame, scale pixelScale: Double, width: Int, height: Int,
+              uploader: SDLViewportUploader) -> SDLFramePlan {
+        let scale = Float(pixelScale)
         prepareMeshes(for: frame, uploader)
         var plan = SDLFramePlan()
         let clip = ClipUniforms(frame.clip)
@@ -41,6 +43,8 @@
         plan.handles = handleInstances(for: frame, scale: scale, uploader).map {
             SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
         }
+        plan.cube = planCube(frame, scale: pixelScale, width: width, height: height, uploader)
+        plan.triad = planTriad(frame, scale: pixelScale, width: width, height: height, uploader)
         return plan
     }
 
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
@@ -15,7 +15,8 @@
 
 extension SDLViewportRenderer {
     /// Records the main pass from `plan`, in the Metal renderer's order: the background gradient, opaque solids, the ground grid
-    /// (unless the overlay has a plane grid of its own), B-rep edges, ghosts, guides, the overlay's fills, lines and points, handles.
+    /// (unless the overlay has a plane grid of its own), B-rep edges, ghosts, guides, the overlay's fills, lines and points, handles, the
+    /// view cube and the triad (each in a square of its own).
     func record(_ plan: SDLFramePlan, _ frame: ViewportFrame, _ uniforms: FrameUniforms, in pass: SDLGPURenderPass) {
         let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(uniforms))
         drawBackground(frame.palette, in: pass)
@@ -30,6 +31,8 @@
         if let fills = plan.fills { drawFills(fills, in: recorder) }
         if let overlay = plan.overlay { drawLines(overlay, pipeline: pipelines.lineAlways, in: recorder) }
         if let handles = plan.handles { drawLines(handles, pipeline: pipelines.lineAlways, in: recorder) }
+        if let cube = plan.cube { drawCube(cube, in: pass) }
+        if let triad = plan.triad { drawTriad(triad, in: pass) }
     }
 
     /// The background gradient, drawn first and ignoring depth.
@@ -73,7 +76,7 @@
     }
 
     /// Instanced line quads, four vertices as a strip per instance.
-    private func drawLines(_ lines: SDLFramePlan.Lines, pipeline: SDLGPUGraphicsPipeline, in recorder: SDLPassRecorder) {
+    func drawLines(_ lines: SDLFramePlan.Lines, pipeline: SDLGPUGraphicsPipeline, in recorder: SDLPassRecorder) {
         guard lines.count > 0 else { return }
         recorder.bind(pipeline)
         recorder.pass.bindVertexStorageBuffers([lines.buffer])
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift
@@ -6,7 +6,7 @@
 /// Draws a `ViewportFrame` with SDL_GPU (cross-platform spec section 4): the Metal `ViewportRenderer`'s passes, in the same
 /// order, over the shaders in `Shaders/viewport`.
 /// - The main pass draws the background gradient, opaque solids, the ground grid, B-rep edges, ghosts, guides' selected edges,
-///   the overlay's fills, lines and points, and handles. It renders into its own 4× MSAA colour and depth targets, resolved into
+///   the overlay's fills, lines and points, handles, the view cube (its face names painted on from a label atlas) and the triad. It renders into its own 4× MSAA colour and depth targets, resolved into
 ///   the target it is given (a `GPUSurface`'s, `bgra8Unorm`).
 /// - The ID pass (`SDLViewportRenderer+IDPass`) writes `PickID`s into an `r32Uint` target.
 /// GPU meshes are cached by mesh serial and dropped once a frame no longer shows them; the buffers that bake colours in are rebuilt
@@ -27,6 +27,7 @@
 
     let device: SDLGPUDevice
     let pipelines: SDLViewportPipelines
+    let cube: SDLViewportCube
     private(set) var meshes: [Int: SDLViewportMesh] = [:]
     private var multisample: (width: Int, height: Int, color: SDLGPUTexture, depth: SDLGPUTexture)?
     /// The handles' instances, kept until the handles, the scale or the palette change, so a frame of a continuous orbit makes no
@@ -34,20 +35,24 @@
     var handleBuffer: CachedHandles?
     /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
     var overlayBuffer: (key: OverlayBufferKey, buffer: SDLGPUBuffer, count: Int)?
+    /// The triad's instances, which depend only on the pixel scale and the palette: an orbit turns the widget's camera.
+    var triadBuffer: (scale: Float, palette: ViewportPalette, buffer: SDLGPUBuffer, count: Int)?
     /// The overlay's fill triangles, kept until the fills or the palette change, and dropped once a frame has none.
     var fillBuffer: (key: FillBufferKey, buffer: SDLGPUBuffer, count: Int)?
     /// Main passes encoded so far. Tests use it to tell "drew" from "bailed out".
     private(set) var encodedPasses = 0
 
-    init(device: SDLGPUDevice, pipelines: SDLViewportPipelines) {
+    /// `labelAtlas` is the view cube's six face names (`CubeLabelFonts.atlas()`), rasterized by the caller on the main actor.
+    init(device: SDLGPUDevice, pipelines: SDLViewportPipelines, labelAtlas: CubeLabelAtlas) {
         self.device = device
         self.pipelines = pipelines
+        cube = SDLViewportCube(device: device, atlas: labelAtlas)
     }
 
     /// With pipelines made from `library`. Making them compiles every shader, which a real GPU does in milliseconds and a CPU driver in
     /// a second, on whichever thread asks: make them once per device.
-    convenience init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
-        self.init(device: device, pipelines: try SDLViewportPipelines(device: device, library: library))
+    convenience init(device: SDLGPUDevice, library: SDLGPUShaderLibrary, labelAtlas: CubeLabelAtlas) throws {
+        self.init(device: device, pipelines: try SDLViewportPipelines(device: device, library: library), labelAtlas: labelAtlas)
     }
 
     /// The main pass into `target` (`b8g8r8a8Unorm`, `scale` pixels per point). It does nothing for an empty view or a target in
@@ -59,7 +64,7 @@
               target.description.format == SDLViewportPipelines.colorFormat,
               let targets = multisampleTargets(width: width, height: height) else { return }
         let uploader = SDLViewportUploader(device: device, commandBuffer: commandBuffer)
-        let plan = plan(frame, scale: Float(scale), uploader: uploader)
+        let plan = plan(frame, scale: scale, width: width, height: height, uploader: uploader)
         let uniforms = GPUGeometry.frameUniforms(frame.pose, size: frame.size, sceneRadius: frame.sceneRadius,
                                                  pixelWidth: width, pixelHeight: height)
         let color = SDLGPUColorAttachment(texture: targets.color, loadOp: .clear, clearColor: (0, 0, 0, 1), storeOp: .resolve,
```

`Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift
@@ -21,7 +21,7 @@
     }
 
     /// Every shader the viewport builds a pipeline from; each has a vertex stage and a fragment stage of the same name.
-    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "id_mesh", "id_line"]
+    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "cube", "id_mesh", "id_line"]
 
     /// The driver whose blobs this platform's SDL picks: Direct3D 12 (DXIL) on Windows, Vulkan (SPIR-V) elsewhere.
     static var platformDriver: String {
```

- [ ] **Step 5: The shaders build**

Nothing to run by hand: `scripts/linux-test.sh` compiles first (the sources changed, so it recompiles). Expected: `Built Shaders/viewport/compiled (74 files).` and `git status` shows no compiled file; `Shaders/viewport/compiled` now has 74 files (`cube.vert/frag.{spv,dxil,msl,json}` added; every other file is byte-identical).

- [ ] **Step 6: Run the tests: they pass**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 325 tests in 44 suites passed` (baseline 259/34 + 66 tests, + 10 suites).

`SDLWidgetTests` has 7 tests: the FRONT label painted on the FRONT face (and BACK's from behind), the cube inside its square and hidden when asked, a hovered region, the triad's three axis colours, the triad and cube buffers surviving an orbit, a widget that does not fit, and the blank atlas.
- [ ] **Step 7: Update the docs that say what is still missing**

`docs/metalui-gaps.md` already says XP-G15 and XP-G18 are answered (task 0); add only "used by xp-3 task 10, commit <this task's commit>" to the end of the row's status if it is not there. In `CLAUDE.md`'s xp-3 paragraph (task 9) shorten the sentence beginning "Tasks 10 to 12 add" so it no longer lists the view cube and the triad, and in `docs/superpowers/specs/2026-10-13-cross-platform-design.md` erratum E7 do the same to the sentence that begins "Until tasks 10 to 12 land". (If task 9 has not run yet, there is nothing to shorten.)

- [ ] **Step 8: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add CLAUDE.md docs/metalui-gaps.md docs/superpowers/specs/2026-10-13-cross-platform-design.md \
  Shaders/viewport/common.hlsli \
  Shaders/viewport/cube.frag.hlsl \
  Shaders/viewport/cube.vert.hlsl \
  Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportBackend.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportCube.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Widgets.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift \
  Tests/CreatorViewportTests/SDLViewportBackendTests.swift \
  Tests/CreatorViewportTests/SDLWidgetTests.swift \
  Tests/CreatorViewportTests/ShaderSourceTests.swift \
  Tests/CreatorViewportTests/Support/SDLRenderRig.swift
git commit -m "viewport: the view cube and the triad on SDL_GPU"
```


### Task 11: The ghosts' depth-only prepass (MetalUI S11: `writesColor`)

A ghost (another node's preview, blended at 40%) takes two steps so each pixel blends once, at its nearest ghost surface: a depth-only prepass, then the blended colour pass, which passes only where its depth equals the prepass's (less-or-equal, no write). Metal's prepass pipeline writes no colour. SDL needs the pipeline's colour write mask (`writesColor: false`, gap XP-G16). Until then (tasks 0 to 9) the ghost pass blends every layer it is not hidden by. The test is the one that fails without the prepass: a ghost box looks, in the middle of its front face, as a ghost of that face alone does. The prepass runs the same `mesh` fragment (`ghost == 1`) as the colour pass, exactly as Metal does.

**Files:**
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift`
- Modify: `Tests/CreatorViewportTests/SDLRenderTests.swift`

**Interfaces:**
- Consumes: task 6's `drawSolids`; MetalUI `SDLGPUGraphicsPipelineDescription(…, writesColor:)`.
- Produces: `SDLViewportPipelines.ghostDepth`; the ghost colour pipeline now tests less-or-equal.

- [ ] **Step 1: Confirm the MetalUI checkout has `writesColor` (answered by MetalUI S11, `11dca65e`)**

No wait: master's pin `5f03ab7b` contains S11. Check that the sibling checkout the build uses does too (it is read, never changed):

```bash
git -C ../MetalUI merge-base --is-ancestor 11dca65e HEAD && echo has-S11
git -C ../MetalUI grep -n "public var writesColor" HEAD -- Backends/SDL/Sources/MetalUISDLGPU/SDLGPUGraphics.swift
```

Expected: `has-S11` and the declaration (`writesColor: Bool`, the last argument of `SDLGPUGraphicsPipelineDescription.init`, default `true`). If `../MetalUI` is behind `5f03ab7b`, it is not this branch's to move: ask whoever owns that checkout. `METALUI_COMMIT` in `.github/workflows/xp.yml` stays `5f03ab7b…` (no bump).

- [ ] **Step 2: Write the failing tests**

The test fails on the code of task 6 for a reason you can read: the ghost box's middle is denser than one layer, because its back face is blended over its front.

`Tests/CreatorViewportTests/SDLRenderTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/SDLRenderTests.swift
+++ b/Tests/CreatorViewportTests/SDLRenderTests.swift
@@ -104,6 +104,30 @@
         }
     }
 
+    /// Ghosts take two steps so each pixel blends once, at its nearest ghost surface (spec §6.3's 40%, with no back faces or interior
+    /// showing through): a depth-only prepass, then the blended colour pass. A ghost box therefore looks, in the middle of its front
+    /// face, as a ghost of that front face alone does.
+    @Test func aGhostBlendsOnceAtItsNearestSurfaceWhateverLiesBehindIt() async throws {
+        let rig = try Rig()
+        var whole = RenderFixtures.boxFrame()
+        whole.items[0].isGhost = true
+        var frontOnly = whole
+        let mesh = TestMeshes.box(RenderFixtures.bounds)
+        let keep = mesh.triangleFaces.indices.filter { mesh.triangleFaces[$0] == FaceID(2) }
+        frontOnly.items[0].mesh = DisplayMesh(
+            positions: mesh.positions, normals: mesh.normals,
+            indices: keep.flatMap { [mesh.indices[3 * $0], mesh.indices[3 * $0 + 1], mesh.indices[3 * $0 + 2]] },
+            triangleFaces: keep.map { mesh.triangleFaces[$0] }, edgePolylines: [:])
+        frontOnly.items[0].meshSerial = 2
+        let both = try await rig.draw(whole), one = try await rig.draw(frontOnly)
+        for point in [(100, 100), (85, 60), (115, 150)] {
+            #expect(Rig.color(both, point.0, point.1) == Rig.color(one, point.0, point.1),
+                    "(\(point.0), \(point.1)): \(Rig.color(both, point.0, point.1)) against \(Rig.color(one, point.0, point.1))")
+        }
+        let background = Rig.color(try await rig.draw(RenderFixtures.emptyFrame()), 100, 100)
+        #expect(Rig.color(both, 100, 100) != background, "and it is there")
+    }
+
     // MARK: Meshes at the extremes
 
     /// A Mesh node can come out empty (a scatter of nothing, a failed mesh) or bare of edges; neither may trap, and what is there draws.
```

- [ ] **Step 3: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'SDLRenderTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. Run against task 10's code (it compiles); `aGhostBlendsOnceAtItsNearestSurfaceWhateverLiesBehindIt` fails with `(100, 100): [113, 114, 121] against [92, 93, 102]` (the numbers will differ a little).

- [ ] **Step 4: Implement**

`Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
@@ -18,7 +18,9 @@
     let mesh: SDLGPUGraphicsPipeline
     /// The surface coloured by a field's values (`field_mesh`).
     let fieldMesh: SDLGPUGraphicsPipeline
-    /// The ghosts' blended colour pass: test against the solids without writing.
+    /// The ghosts' depth-only prepass (no colour is written), then their blended colour pass, which passes only where its depth equals the
+    /// prepass's (less-or-equal, no write): each pixel blends once, at its nearest ghost surface.
+    let ghostDepth: SDLGPUGraphicsPipeline
     let ghost: SDLGPUGraphicsPipeline
     /// Lines (premultiplied source-over): tested against the solids (less-or-equal) without writing; never tested; and only where
     /// something nearer already wrote depth (a guide's edges behind the part).
@@ -35,11 +37,12 @@
     init(device: SDLGPUDevice, library: SDLGPUShaderLibrary) throws {
         func pipeline(_ vertex: String, _ fragment: String, primitive: SDLGPUPrimitiveType = .triangleList,
                       cull: SDLGPUCullMode = .none, color: SDLGPUTextureFormat = Self.colorFormat, blend: SDLGPUBlend = .none,
-                      samples: SDLGPUSampleCount = Self.sampleCount,
-                      depth: SDLGPUDepthState) throws -> SDLGPUGraphicsPipeline {
+                      samples: SDLGPUSampleCount = Self.sampleCount, depth: SDLGPUDepthState,
+                      writesColor: Bool = true) throws -> SDLGPUGraphicsPipeline {
             let description = SDLGPUGraphicsPipelineDescription(
                 vertex: try library.vertex(vertex, for: device), fragment: try library.fragment(fragment, for: device),
-                primitiveType: primitive, cullMode: cull, colorFormat: color, blend: blend, sampleCount: samples, depth: depth)
+                primitiveType: primitive, cullMode: cull, colorFormat: color, blend: blend, sampleCount: samples, depth: depth,
+                writesColor: writesColor)
             do {
                 return try device.compileGraphicsPipeline(description)
             } catch {
@@ -55,7 +58,8 @@
         fill = try pipeline("fill", "fill", blend: .premultipliedAlpha, depth: always)
         mesh = try pipeline("mesh", "mesh", depth: writes)
         fieldMesh = try pipeline("field_mesh", "field_mesh", depth: writes)
-        ghost = try pipeline("mesh", "mesh", blend: .premultipliedAlpha, depth: SDLGPUDepthState(compare: .less, write: false))
+        ghostDepth = try pipeline("mesh", "mesh", depth: writes, writesColor: false)
+        ghost = try pipeline("mesh", "mesh", blend: .premultipliedAlpha, depth: tests)
         lineTest = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
         lineAlways = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: always)
         lineBehind = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: behind)
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
@@ -43,28 +43,40 @@
         pass.draw(vertexCount: 3)
     }
 
-    /// Opaque solids, or ghosts (blended, tested against what is already there). A solid with a tint draws with the field pipeline.
+    /// Opaque solids, or ghosts (blended, tested against the prepass's depth). A solid with a tint draws with the field pipeline.
     private func drawSolids(_ solids: [SDLFramePlan.Solid], ghosts: Bool, shade: ShadeUniforms, clip: ClipUniforms,
                             in recorder: SDLPassRecorder) {
+        if ghosts {
+            // The prepass: the nearest ghost surface's depth, with no colour.
+            for solid in solids {
+                drawSolid(solid, plain: pipelines.ghostDepth, ghosts: true, shade: shade, clip: clip, in: recorder)
+            }
+        }
+        for solid in solids {
+            drawSolid(solid, plain: ghosts ? pipelines.ghost : pipelines.mesh, ghosts: ghosts, shade: shade, clip: clip, in: recorder)
+        }
+    }
+
+    /// One solid with `plain`, or with the field pipeline when it has a tint (a ghost never does).
+    private func drawSolid(_ solid: SDLFramePlan.Solid, plain: SDLGPUGraphicsPipeline, ghosts: Bool, shade: ShadeUniforms,
+                           clip: ClipUniforms, in recorder: SDLPassRecorder) {
         let pass = recorder.pass
-        for solid in solids {
-            let draw = DrawUniforms(pickBase: 0, ghost: ghosts ? 1 : 0, faceCount: UInt32(solid.faceCount), padding: 0)
-            if let tint = solid.tint {
-                recorder.bind(pipelines.fieldMesh)
-                pass.pushFragmentUniform(uniformBytes(shade), at: 0)
-                pass.pushFragmentUniform(uniformBytes(tint.ramp), at: 1)
-                pass.pushFragmentUniform(uniformBytes(clip), at: 2)
-                pass.bindVertexStorageBuffers([solid.vertices, solid.flags, tint.values])
-            } else {
-                recorder.bind(ghosts ? pipelines.ghost : pipelines.mesh)
-                pass.pushFragmentUniform(uniformBytes(draw), at: 0)
-                pass.pushFragmentUniform(uniformBytes(shade), at: 1)
-                pass.pushFragmentUniform(uniformBytes(clip), at: 2)
-                pass.bindVertexStorageBuffers([solid.vertices, solid.flags])
-            }
-            pass.pushVertexUniform(uniformBytes(draw), at: 1)
-            pass.draw(vertexCount: solid.vertexCount)
+        let draw = DrawUniforms(pickBase: 0, ghost: ghosts ? 1 : 0, faceCount: UInt32(solid.faceCount), padding: 0)
+        if let tint = solid.tint {
+            recorder.bind(pipelines.fieldMesh)
+            pass.pushFragmentUniform(uniformBytes(shade), at: 0)
+            pass.pushFragmentUniform(uniformBytes(tint.ramp), at: 1)
+            pass.pushFragmentUniform(uniformBytes(clip), at: 2)
+            pass.bindVertexStorageBuffers([solid.vertices, solid.flags, tint.values])
+        } else {
+            recorder.bind(plain)
+            pass.pushFragmentUniform(uniformBytes(draw), at: 0)
+            pass.pushFragmentUniform(uniformBytes(shade), at: 1)
+            pass.pushFragmentUniform(uniformBytes(clip), at: 2)
+            pass.bindVertexStorageBuffers([solid.vertices, solid.flags])
         }
+        pass.pushVertexUniform(uniformBytes(draw), at: 1)
+        pass.draw(vertexCount: solid.vertexCount)
     }
 
     private func drawGrid(_ frame: ViewportFrame, in recorder: SDLPassRecorder) {
```

- [ ] **Step 5: Run the tests: they pass**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 326 tests in 44 suites passed` (baseline 259/34 + 67 tests, + 10 suites).

- [ ] **Step 6: Update the docs that say what is still missing**

`docs/metalui-gaps.md` already says XP-G16 is answered (task 0); add only "used by xp-3 task 11, commit <this task's commit>" to the end of the row's status if it is not there. In `CLAUDE.md`'s xp-3 paragraph (task 9) shorten the sentence beginning "Tasks 10 to 12 add" so it no longer lists the ghosts' depth-only prepass, and in `docs/superpowers/specs/2026-10-13-cross-platform-design.md` erratum E7 do the same to the sentence that begins "Until tasks 10 to 12 land". (If task 9 has not run yet, there is nothing to shorten.)

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add CLAUDE.md docs/metalui-gaps.md docs/superpowers/specs/2026-10-13-cross-platform-design.md \
  Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift \
  Tests/CreatorViewportTests/SDLRenderTests.swift
git commit -m "viewport: the ghosts' depth-only prepass on SDL_GPU"
```


### Task 12: The field slice (MetalUI S11: `r32Float`)

The slice (fields spec section 6) is a translucent quad through the scene showing a grid of values, drawn ignoring depth because it passes through the part. Its grid is an `r32Float` texture (gap XP-G17), kept until the slice's generation, size or ramp middle changes (`SDLSliceTextures`; the stored numbers are `SliceTextureValues`, now shared with Metal's `SliceTextures`: NaN becomes the ramp's middle, an infinity the end it lies beyond). The shader reads it at texel centres through a nearest sampler (a texel fetch) and blends bilinearly itself, so no support for filtering a float texture is assumed. The slice is never in the ID pass; `SDLSliceTests.aSliceIsNeverUnderAPick` pins it.

**Files:**
- Create: `Shaders/viewport/slice.frag.hlsl`
- Create: `Shaders/viewport/slice.vert.hlsl`
- Create: `Sources/CreatorViewport/Render/SliceTextureValues.swift`
- Create: `Sources/CreatorViewport/RenderSDL/SDLSliceTextures.swift`
- Create: `Tests/CreatorViewportTests/SDLSliceTests.swift`
- Modify: `Shaders/viewport/common.hlsli`
- Modify: `Sources/CreatorViewport/Render/SliceTextures.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift`
- Modify: `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`
- Modify: `Tests/CreatorViewportTests/ShaderSourceTests.swift`
- Modify: `Tests/CreatorViewportTests/ViewportSliceTests.swift`

**Interfaces:**
- Consumes: task 6's plan; `ViewportSlice`, `SliceUniforms`, `FieldRampUniforms`; MetalUI `SDLGPUTextureFormat.r32Float`.
- Produces: `SliceTextureValues.filled(_:ramp:)`, `.texels(of:)`; `SDLSliceTextures`; `SDLFramePlan.Slice`; pipeline `slice`; shaders `slice.vert/frag` and `SliceUniforms` in `common.hlsli`; `renderer.sliceTextures.uploads`.

- [ ] **Step 1: Confirm the MetalUI checkout has `r32Float` (answered by MetalUI S11, `11dca65e`)**

No wait: master's pin `5f03ab7b` contains S11. Check that the sibling checkout the build uses does too (it is read, never changed):

```bash
git -C ../MetalUI merge-base --is-ancestor 11dca65e HEAD && echo has-S11
git -C ../MetalUI grep -n "case r32Float" HEAD -- Backends/SDL/Sources/MetalUISDLGPU/SDLGPUTexture.swift
```

Expected: `has-S11` and the declaration (`case r32Float`, 4 bytes a texel; linear filtering of it is optional hardware, and this task samples it with a nearest sampler). If `../MetalUI` is behind `5f03ab7b`, it is not this branch's to move: ask whoever owns that checkout. `METALUI_COMMIT` in `.github/workflows/xp.yml` stays `5f03ab7b…` (no bump).

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorViewportTests/SDLSliceTests.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The field slice on SDL_GPU (fields spec §6), as `ViewportSliceRenderTests` reads it on Metal: a translucent quad over the scene,
/// its grid an `r32Float` texture read with a bilinear blend done in the shader. `RenderFixtures`' front view (orthographic, 5 points
/// per mm, centred on (0, 0, 15)) puts a 20 × 20 mm quad in the XZ plane at view x 50…150, y 50…150.
@MainActor
@Suite(.enabled(if: SDLTestDevice.isAvailable, "needs an SDL_GPU device"))
struct SDLSliceTests {
    typealias Rig = SDLRenderRig
    /// Red at the quad's left edge, green in the middle, blue at its right edge.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -1...1)

    /// A 64 × 64 grid whose value grows from −1 on the left to 1 on the right.
    func slice(generation: Int = 1, flipped: Bool = false) -> ViewportSlice {
        let row = (0..<64).map { Float($0) / 63 * 2 - 1 }
        let values = (0..<64).flatMap { _ in flipped ? row.reversed() : row }
        return ViewportSlice(origin: Vector3(0, 0, 15), xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 10, columns: 64,
                             rows: 64, values: values, ramp: Self.ramp, generation: generation)
    }

    func frame(_ slice: ViewportSlice?) -> ViewportFrame {
        var frame = RenderFixtures.emptyFrame()
        frame.slice = slice
        return frame
    }

    @Test func theQuadShowsTheRampLeftToRightAndLeavesTheRestAlone() async throws {
        let rig = try Rig()
        let with = try await rig.draw(frame(slice()))
        let without = try await rig.draw(frame(nil))
        let left = Rig.color(with, 55, 100), middle = Rig.color(with, 100, 100), right = Rig.color(with, 145, 100)
        #expect(left[0] > 180 && left[1] < 90 && left[2] < 90, "red: \(left)")
        #expect(middle[1] > 180 && middle[0] < 90 && middle[2] < 90, "green: \(middle)")
        #expect(right[2] > 180 && right[0] < 90 && right[1] < 90, "blue: \(right)")
        #expect(Rig.color(with, 30, 100) == Rig.color(without, 30, 100) && Rig.color(with, 100, 30) == Rig.color(without, 100, 30),
                "outside the quad")
        #expect(Rig.color(with, 100, 100) != Rig.color(without, 100, 100))
    }

    @Test func theQuadIsTranslucentSoWhatIsBehindItShowsThrough() async throws {
        let rig = try Rig()
        let without = try await rig.draw(frame(nil))
        let with = try await rig.draw(frame(slice()))
        // The background is a dark gradient (#3a3d4e to #191a21); at 0.85 opacity a fraction of it remains, so the pure green of the
        // ramp's middle is dimmed in red and blue by the background rather than being exactly 0.
        let behind = Rig.color(without, 100, 100), over = Rig.color(with, 100, 100)
        #expect(over[0] > 0 && over[0] <= behind[0] / 2, "some of the background's red remains: \(over) over \(behind)")
    }

    @Test func theValuesAreDrawnWhicheverWayTheyRun() async throws {
        let flipped = try await Rig().draw(frame(slice(generation: 2, flipped: true)))
        let left = Rig.color(flipped, 55, 100), right = Rig.color(flipped, 145, 100)
        #expect(left[2] > 180 && right[0] > 180, "blue on the left now, red on the right: \(left) \(right)")
    }

    @Test func rowZeroIsTheEdgeOnTheNegativeYAxisSide() async throws {
        // Value −1 in row 0 and 1 in the last row: red at the bottom (the −Z edge) and blue at the top.
        let values = (0..<64).flatMap { row in [Float](repeating: Float(row) / 63 * 2 - 1, count: 64) }
        var vertical = slice()
        vertical.values = values
        let bytes = try await Rig().draw(frame(vertical))
        let top = Rig.color(bytes, 100, 55), bottom = Rig.color(bytes, 100, 145)
        #expect(top[2] > 180 && bottom[0] > 180, "the last row is the +Z edge, drawn on top: \(top) \(bottom)")
    }

    @Test func theTextureIsKeptWhileTheGenerationDoesNotChange() async throws {
        let rig = try Rig()
        try await rig.draw(frame(slice(generation: 1)))
        try await rig.draw(frame(slice(generation: 1)))
        #expect(rig.renderer.sliceTextures.uploads == 1)
        try await rig.draw(frame(slice(generation: 2)))
        #expect(rig.renderer.sliceTextures.uploads == 2)
    }

    @Test func anInvalidSliceDrawsNothing() async throws {
        let rig = try Rig()
        var broken = slice()
        broken.values = [0, 1]
        #expect(try await rig.draw(frame(broken)) == (try await rig.draw(frame(nil))))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleColour() async throws {
        var nothing = slice()
        nothing.values = [Float](repeating: .nan, count: 64 * 64)
        let middle = Rig.color(try await Rig().draw(frame(nothing)), 55, 100)
        #expect(middle[1] > 180 && middle[0] < 90, "green everywhere: \(middle)")
    }

    @Test func aSliceIsNeverUnderAPick() async throws {
        let rig = try Rig()
        var with = RenderFixtures.boxFrame()
        with.slice = slice()
        let points = stride(from: 20.0, to: 180.0, by: 20.0).flatMap { x in
            stride(from: 20.0, to: 180.0, by: 20.0).map { ScreenPoint(x, $0) }
        }
        let withSlice = try await rig.picks(at: points, in: with)
        let without = try await rig.picks(at: points, in: RenderFixtures.boxFrame())
        #expect(withSlice == without, "the slice is no part of the scene")
        #expect(withSlice.contains { $0 != nil }, "the part itself is still picked")
    }
}
#endif
```

`Tests/CreatorViewportTests/ShaderSourceTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ShaderSourceTests.swift
+++ b/Tests/CreatorViewportTests/ShaderSourceTests.swift
@@ -78,6 +78,7 @@
             "GridUniforms": MemoryLayout<GridUniforms>.stride, "FillVertex": MemoryLayout<FillVertex>.stride,
             "ClipUniforms": MemoryLayout<ClipUniforms>.stride, "FieldRampUniforms": MemoryLayout<FieldRampUniforms>.stride,
             "CubeVertex": MemoryLayout<CubeVertex>.stride,
+            "SliceUniforms": MemoryLayout<SliceUniforms>.stride,
         ]
         #expect(sizes.count == (try Self.structs().count), "every struct in the header is made of float4, uint4, float2, float and uint")
         for (name, expected) in swift {
@@ -116,7 +117,7 @@
     /// `INCLUDES.sha256` it wrote match the sources and the header now. A source edited after the last build fails here and says so.
     @Test func theBuildCompiledEveryStageIntoTheDirectoryTheRendererReads() throws {
         let sources = Self.stageSources
-        #expect(sources.count >= 18, "the viewport's vertex and fragment stages are found")
+        #expect(sources.count >= 20, "the viewport's vertex and fragment stages are found")
         let compiled = try #require(Self.runtimeDirectory, "no compiled shader directory beside the executable or in the source tree. \(Self.remedy)")
         for source in sources {
             let stem = String(source.lastPathComponent.dropLast(".hlsl".count))
@@ -147,8 +148,8 @@
 /// the source tree's, holds every stage for the platform's driver, with its reflection.
 struct ViewportShaderDirectoryTests {
     @Test func everyStageLoadsForThePlatformsDriver() throws {
-        #expect(try SDLViewportShaders.verify() == 18)
-        #expect(try ViewportShaderCheck.run() == "the viewport's 18 SDL_GPU shader stages were found")
+        #expect(try SDLViewportShaders.verify() == 20)
+        #expect(try ViewportShaderCheck.run() == "the viewport's 20 SDL_GPU shader stages were found")
     }
 
     /// `--self-test` asks the viewport whether its shaders were built. With no directory it fails, and the message says which directory
```

`Tests/CreatorViewportTests/ViewportSliceTests.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Tests/CreatorViewportTests/ViewportSliceTests.swift
+++ b/Tests/CreatorViewportTests/ViewportSliceTests.swift
@@ -37,3 +37,15 @@
         #expect(wider != a)
     }
 }
+
+/// How a slice's numbers are stored in the GPU texture, on every platform (the Metal renderer's `SliceTextures` and the SDL one's
+/// `SDLSliceTextures` fill their texels from it): a NaN becomes the ramp's middle value, an infinity the ramp's end it lies beyond.
+struct SliceTextureValuesTests {
+    @Test func notANumberIsTheMiddleAndInfinityIsTheEndItLiesBeyond() {
+        let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...10)
+        #expect(SliceTextureValues.filled(.nan, ramp: ramp) == 5)
+        #expect(SliceTextureValues.filled(.infinity, ramp: ramp) == 10)
+        #expect(SliceTextureValues.filled(-.infinity, ramp: ramp) == 0)
+        #expect(SliceTextureValues.filled(3.5, ramp: ramp) == 3.5)
+    }
+}
```

- [ ] **Step 3: Run the tests: they fail**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'SliceTextureValuesTests|SDLSliceTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected: the build fails. `cannot find 'SliceTextureValues' in scope`, `value of type 'SDLViewportRenderer' has no member 'sliceTextures'`.

- [ ] **Step 4: Implement**

`SliceTextureValues` is portable, and Metal's `SliceTextures` now fills its texture from it (its own `filled` goes), so the two renderers store the same numbers.

`Shaders/viewport/slice.frag.hlsl` (new):

```hlsl
#include "common.hlsli"

// The grid is an r32Float texture read at texel centres through a nearest-neighbour sampler, which is a texel fetch, and blended
// here, so no support for filtering a float texture is assumed.
Texture2D<float> grid : register(t0, space2);
SamplerState gridSampler : register(s0, space2);
cbuffer Slice : register(b0, space3) { SliceUniforms slice; };
cbuffer Ramp : register(b1, space3) { FieldRampUniforms ramp; };

float gridValue(int2 texel, float2 size) {
    return grid.SampleLevel(gridSampler, (float2(texel) + 0.5) / size, 0);
}

/// The grid read at `uv` (0...1 over the quad) with a bilinear blend of the four texels round it, texel centres at
/// (i + 0.5) / size, edges held.
float sliceValue(float2 uv) {
    uint width;
    uint height;
    grid.GetDimensions(width, height);
    float2 size = float2(width, height);
    float2 p = uv * size - 0.5;
    float2 f = p - floor(p);
    int2 low = int2(floor(p));
    int2 last = int2(width, height) - 1;
    int2 a = clamp(low, int2(0, 0), last);
    int2 b = clamp(low + 1, int2(0, 0), last);
    float bottom = lerp(gridValue(int2(a.x, a.y), size), gridValue(int2(b.x, a.y), size), f.x);
    float top = lerp(gridValue(int2(a.x, b.y), size), gridValue(int2(b.x, b.y), size), f.x);
    return lerp(bottom, top, f.y);
}

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 {
    float3 color = fieldRamp(ramp, sliceValue(uv));
    float alpha = slice.style.x;
    return float4(color * alpha, alpha);
}
```

`Shaders/viewport/slice.vert.hlsl` (new):

```hlsl
#include "common.hlsli"

// The field slice: a translucent quad, four vertices as a strip.
cbuffer Frame : register(b0, space1) { FrameUniforms frame; };
cbuffer Slice : register(b1, space1) { SliceUniforms slice; };

struct Out {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

Out main(uint vid : SV_VertexID) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float3 world = slice.origin.xyz + slice.across.xyz * (2.0 * corner.x - 1.0) + slice.up.xyz * (2.0 * corner.y - 1.0);
    Out output;
    output.position = mulColumns(frame.viewProjection, float4(world, 1.0));
    output.uv = corner;
    return output;
}
```

`Sources/CreatorViewport/Render/SliceTextureValues.swift` (new):

```swift
/// How a slice's numbers are stored in its GPU texture, the same on every platform: a NaN becomes the ramp's middle value (which is
/// why the middle is part of the texture's cache key: a range change without a new generation must refill them), and an infinity is
/// held to the ramp's end it lies beyond.
enum SliceTextureValues {
    /// `value` as stored: NaN is the ramp's middle, ±infinity the ramp's high or low end, anything else as it is.
    static func filled(_ value: Float, ramp: FieldRamp) -> Float {
        if value.isNaN { return ramp.midValue }
        if value == .infinity { return ramp.highValue }
        if value == -.infinity { return ramp.lowValue }
        return value
    }

    /// Every sample of `slice` as stored, row by row from the `-yAxis` edge.
    static func texels(of slice: ViewportSlice) -> [Float] {
        slice.values.map { filled($0, ramp: slice.ramp) }
    }
}
```

`Sources/CreatorViewport/RenderSDL/SDLSliceTextures.swift` (new):

```swift
#if canImport(MetalUISDLGPU)
import MetalUISDLGPU

/// The field slice's grid as an `r32Float` texture, kept until the slice's generation, size or ramp middle changes, so a redraw of an
/// unchanged slice (an orbit) uploads nothing (`SliceTextures`, the Metal twin; the stored numbers are `SliceTextureValues`'). A nearest
/// sampler reads it at texel centres, so the shader's bilinear blend sees the stored numbers exactly.
final class SDLSliceTextures: @unchecked Sendable {
    private struct Entry {
        let generation: Int
        let columns: Int
        let rows: Int
        let middle: Float
        let texture: SDLGPUTexture
    }

    private let device: SDLGPUDevice
    private var cached: Entry?
    let sampler: SDLGPUSampler?
    /// Textures made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var uploads = 0

    init(device: SDLGPUDevice) {
        self.device = device
        sampler = device.makeSampler(SDLGPUSamplerDescription(filter: .nearest, mipmapFilter: .nearest))
    }

    /// The texture for `slice`, filled by a copy recorded in the uploader's command buffer (so before the pass that samples it), or
    /// `nil` if SDL refuses it.
    func texture(for slice: ViewportSlice, uploader: SDLViewportUploader) -> SDLGPUTexture? {
        if let cached, cached.generation == slice.generation, cached.columns == slice.columns, cached.rows == slice.rows,
           cached.middle == slice.ramp.midValue {
            return cached.texture
        }
        let texels = SliceTextureValues.texels(of: slice)
        let size = texels.count * MemoryLayout<Float>.stride
        guard let texture = device.makeTexture(SDLGPUTextureDescription(
                  width: slice.columns, height: slice.rows, format: .r32Float, usage: [.sampler])),
              let transfer = device.makeTransferBuffer(size: size, direction: .upload),
              let memory = transfer.map() else { return nil }
        let copied = texels.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            memory.copyMemory(from: base, byteCount: size)
            return true
        }
        transfer.unmap()
        guard copied else { return nil }
        uploader.commandBuffer.copy(transfer, to: texture)
        cached = Entry(generation: slice.generation, columns: slice.columns, rows: slice.rows, middle: slice.ramp.midValue,
                       texture: texture)
        uploads += 1
        return texture
    }
}
#endif
```

`Shaders/viewport/common.hlsli` (change; apply with `git apply` or by hand):

```diff
--- a/Shaders/viewport/common.hlsli
+++ b/Shaders/viewport/common.hlsli
@@ -105,3 +105,10 @@
     float t = span > 0.0 ? saturate((value - ramp.range.y) / span) : 1.0;
     return lerp(ramp.mid.rgb, ramp.high.rgb, t);
 }
+
+struct SliceUniforms {
+    float4 origin;
+    float4 across;
+    float4 up;
+    float4 style;
+};
```

`Sources/CreatorViewport/Render/SliceTextures.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/Render/SliceTextures.swift
+++ b/Sources/CreatorViewport/Render/SliceTextures.swift
@@ -28,7 +28,7 @@
         descriptor.usage = .shaderRead
         descriptor.storageMode = .shared
         guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
-        let values = slice.values.map { Self.filled($0, ramp: slice.ramp) }
+        let values = SliceTextureValues.texels(of: slice)
         values.withUnsafeBytes { bytes in
             guard let base = bytes.baseAddress else { return }
             texture.replace(region: MTLRegionMake2D(0, 0, slice.columns, slice.rows), mipmapLevel: 0, withBytes: base,
@@ -39,13 +39,5 @@
         uploads += 1
         return texture
     }
-
-    /// `value` as stored: NaN is the ramp's middle, ±infinity the ramp's high or low end, anything else as it is.
-    static func filled(_ value: Float, ramp: FieldRamp) -> Float {
-        if value.isNaN { return ramp.midValue }
-        if value == .infinity { return ramp.highValue }
-        if value == -.infinity { return ramp.lowValue }
-        return value
-    }
 }
 #endif
```

`Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift
@@ -39,6 +39,14 @@
         var viewport: WidgetViewport
     }
 
+    /// The field slice's quad: its grid texture and the sampler it is read through, the quad and the ramp.
+    struct Slice {
+        var texture: SDLGPUTexture
+        var sampler: SDLGPUSampler
+        var geometry: SliceUniforms
+        var ramp: FieldRampUniforms
+    }
+
     /// The axis triad's lines.
     struct Triad {
         var lines: Lines
@@ -51,6 +59,7 @@
     var guides: [Lines] = []
     /// A guide's faded edges, drawn only where the part hides them.
     var hiddenGuides: [Lines] = []
+    var slice: Slice?
     var fills: (buffer: SDLGPUBuffer, count: Int)?
     var overlay: Lines?
     var handles: Lines?
```

`Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift
@@ -29,6 +29,8 @@
     let grid: SDLGPUGraphicsPipeline
     /// The view cube: blended, never depth-tested (a cube is convex, so back-face culling does the hiding).
     let cube: SDLGPUGraphicsPipeline
+    /// The field slice's translucent quad: blended, never depth-tested (it passes through the part).
+    let slice: SDLGPUGraphicsPipeline
     let idMesh: SDLGPUGraphicsPipeline
     let idLine: SDLGPUGraphicsPipeline
 
@@ -61,6 +63,7 @@
         lineBehind = try pipeline("line", "line", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: behind)
         grid = try pipeline("grid", "grid", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: tests)
         cube = try pipeline("cube", "cube", cull: .back, blend: .premultipliedAlpha, depth: always)
+        slice = try pipeline("slice", "slice", primitive: .triangleStrip, blend: .premultipliedAlpha, depth: always)
         idMesh = try pipeline("id_mesh", "id_mesh", color: Self.idFormat, samples: .one, depth: writes)
         idLine = try pipeline("id_line", "id_line", primitive: .triangleStrip, color: Self.idFormat, samples: .one, depth: tests)
     }
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift
@@ -36,6 +36,7 @@
                 plan.hiddenGuides.append(SDLFramePlan.Lines(buffer: faded.buffer, count: faded.count, style: edgeStyle))
             }
         }
+        plan.slice = planSlice(frame, uploader)
         plan.fills = fillVertices(for: frame, uploader)
         plan.overlay = overlayInstances(for: frame, scale: scale, uploader).map {
             SDLFramePlan.Lines(buffer: $0.buffer, count: $0.count, style: Self.plainLines)
@@ -46,6 +47,14 @@
         plan.cube = planCube(frame, scale: pixelScale, width: width, height: height, uploader)
         plan.triad = planTriad(frame, scale: pixelScale, width: width, height: height, uploader)
         return plan
+    }
+
+    /// The field slice (fields spec §6): a translucent quad over the scene, ignoring depth because it passes through the part (a depth
+    /// test would hide the half of it that lies inside the solid). `nil` for a slice with no valid grid.
+    private func planSlice(_ frame: ViewportFrame, _ uploader: SDLViewportUploader) -> SDLFramePlan.Slice? {
+        guard let slice = frame.slice, slice.isValid, let sampler = sliceTextures.sampler,
+              let texture = sliceTextures.texture(for: slice, uploader: uploader) else { return nil }
+        return SDLFramePlan.Slice(texture: texture, sampler: sampler, geometry: SliceUniforms(slice), ramp: FieldRampUniforms(slice.ramp))
     }
 
     static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift
@@ -15,7 +15,7 @@
 
 extension SDLViewportRenderer {
     /// Records the main pass from `plan`, in the Metal renderer's order: the background gradient, opaque solids, the ground grid
-    /// (unless the overlay has a plane grid of its own), B-rep edges, ghosts, guides, the overlay's fills, lines and points, handles, the
+    /// (unless the overlay has a plane grid of its own), B-rep edges, ghosts, guides, the field slice, the overlay's fills, lines and points, handles, the
     /// view cube and the triad (each in a square of its own).
     func record(_ plan: SDLFramePlan, _ frame: ViewportFrame, _ uniforms: FrameUniforms, in pass: SDLGPURenderPass) {
         let recorder = SDLPassRecorder(pass: pass, camera: uniformBytes(uniforms))
@@ -28,6 +28,7 @@
         drawSolids(plan.ghosts, ghosts: true, shade: shade, clip: clip, in: recorder)
         for guide in plan.guides { drawLines(guide, pipeline: pipelines.lineTest, in: recorder) }
         for faded in plan.hiddenGuides { drawLines(faded, pipeline: pipelines.lineBehind, in: recorder) }
+        if let slice = plan.slice { drawSlice(slice, in: recorder) }
         if let fills = plan.fills { drawFills(fills, in: recorder) }
         if let overlay = plan.overlay { drawLines(overlay, pipeline: pipelines.lineAlways, in: recorder) }
         if let handles = plan.handles { drawLines(handles, pipeline: pipelines.lineAlways, in: recorder) }
@@ -97,6 +98,15 @@
         recorder.pass.draw(vertexCount: 4, instanceCount: lines.count)
     }
 
+    private func drawSlice(_ slice: SDLFramePlan.Slice, in recorder: SDLPassRecorder) {
+        recorder.bind(pipelines.slice)
+        recorder.pass.pushVertexUniform(uniformBytes(slice.geometry), at: 1)
+        recorder.pass.pushFragmentUniform(uniformBytes(slice.geometry), at: 0)
+        recorder.pass.pushFragmentUniform(uniformBytes(slice.ramp), at: 1)
+        recorder.pass.bindFragmentSamplers([(texture: slice.texture, sampler: slice.sampler)])
+        recorder.pass.draw(vertexCount: 4)
+    }
+
     private func drawFills(_ fills: (buffer: SDLGPUBuffer, count: Int), in recorder: SDLPassRecorder) {
         recorder.bind(pipelines.fill)
         recorder.pass.bindVertexStorageBuffers([fills.buffer])
```

`Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift
@@ -28,6 +28,8 @@
     let device: SDLGPUDevice
     let pipelines: SDLViewportPipelines
     let cube: SDLViewportCube
+    /// The field slice's grid as a texture, kept until the slice's generation or size changes.
+    let sliceTextures: SDLSliceTextures
     private(set) var meshes: [Int: SDLViewportMesh] = [:]
     private var multisample: (width: Int, height: Int, color: SDLGPUTexture, depth: SDLGPUTexture)?
     /// The handles' instances, kept until the handles, the scale or the palette change, so a frame of a continuous orbit makes no
@@ -47,6 +49,7 @@
         self.device = device
         self.pipelines = pipelines
         cube = SDLViewportCube(device: device, atlas: labelAtlas)
+        sliceTextures = SDLSliceTextures(device: device)
     }
 
     /// With pipelines made from `library`. Making them compiles every shader, which a real GPU does in milliseconds and a CPU driver in
```

`Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift` (change; apply with `git apply` or by hand):

```diff
--- a/Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift
+++ b/Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift
@@ -21,7 +21,7 @@
     }
 
     /// Every shader the viewport builds a pipeline from; each has a vertex stage and a fragment stage of the same name.
-    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "cube", "id_mesh", "id_line"]
+    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "cube", "slice", "id_mesh", "id_line"]
 
     /// The driver whose blobs this platform's SDL picks: Direct3D 12 (DXIL) on Windows, Vulkan (SPIR-V) elsewhere.
     static var platformDriver: String {
```

- [ ] **Step 5: The shaders build**

As in task 10, `scripts/linux-test.sh` compiles first. Expected: `Built Shaders/viewport/compiled (82 files).`; `compiled` has 82 files; `slice.frag.json` says `"samplers": 1`.

- [ ] **Step 6: Run the tests: they pass**

```bash
XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter 'CreatorViewportTests' 2>&1 | grep -E 'error:|warning:|recorded an issue|failed after|Test run with'
```
Expected:
- Linux: no `error:` line, no `recorded an issue` or `failed after`, and `Test run with 335 tests in 46 suites passed` (baseline 259/34 + 76 tests, + 12 suites); plus `11 tests in 3 suites` for the app filter.

`SDLSliceTests` has 8 tests, `SliceTextureValuesTests` 1.
- [ ] **Step 7: Update the docs that say what is still missing**

`docs/metalui-gaps.md` already says XP-G17 is answered (task 0); add only "used by xp-3 task 12, commit <this task's commit>" to the end of the row's status if it is not there. In `CLAUDE.md`'s xp-3 paragraph (task 9) shorten the sentence beginning "Tasks 10 to 12 add" so it no longer lists the field slice, and in `docs/superpowers/specs/2026-10-13-cross-platform-design.md` erratum E7 do the same to the sentence that begins "Until tasks 10 to 12 land". (If task 9 has not run yet, there is nothing to shorten.)

- [ ] **Step 8: The final check**

With the last layer in, run the whole of task 9's "full suites" step again (Linux `all`, macOS `swift test` once, the asserts release build, then the push) and confirm the pass rule: macOS 12 `Test run with` lines adding up to master + 15 tests (4837 on `1aad412`; one fewer if task 7 step 6 ran), Linux 12 lines adding up to the task 0 baseline + 77 (76 in `CreatorViewportTests`, +1 in the app tests), no `recorded an issue` or `failed after`, and CI's Windows Test and "Build release (for the zip)" steps green. Then tick the human checks XP-20 to XP-26 that a person can do (`docs/verification/human-checks.md`, group XP3).

- [ ] **Step 9: Lint and commit**

```bash
swiftlint lint --strict --quiet   # no output
git add CLAUDE.md docs/metalui-gaps.md docs/superpowers/specs/2026-10-13-cross-platform-design.md \
  Shaders/viewport/common.hlsli \
  Shaders/viewport/slice.frag.hlsl \
  Shaders/viewport/slice.vert.hlsl \
  Sources/CreatorViewport/Render/SliceTextureValues.swift \
  Sources/CreatorViewport/Render/SliceTextures.swift \
  Sources/CreatorViewport/RenderSDL/SDLFramePlan.swift \
  Sources/CreatorViewport/RenderSDL/SDLSliceTextures.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportPipelines.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Plan.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Record.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportRenderer.swift \
  Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift \
  Tests/CreatorViewportTests/SDLSliceTests.swift \
  Tests/CreatorViewportTests/ShaderSourceTests.swift \
  Tests/CreatorViewportTests/ViewportSliceTests.swift
git commit -m "viewport: the field slice on SDL_GPU"
```


---

## Verification

**Revision of 2026-10-22 (start of execution): what was checked and what was not.** Planning only; no product code was written into the repository. Checked:
  (1) **The rebase.** `git rebase master` moved the plan's three commits onto `1aad412` with no conflict (they touch only this file).
  (2) **Every MetalUI name the plan now uses**, read at MetalUI `5f03ab7b` (`git -C ../MetalUI show 5f03ab7b:<path>`): `SDLGPURenderPass.setViewport(x:y:width:height:minDepth:maxDepth:) -> Bool` and `setScissor(x:y:width:height:) -> Bool`; `SDLGPUGraphicsPipelineDescription(…, writesColor:)`; `SDLGPUTextureFormat.r32Float`; `SDLGPUSamplerDescription(…, maxAnisotropy:)`; `SDLGPUFence.waitBlocking()`; `SDLGPUDevice.downloadSynchronously(_:region:) -> [UInt8]?`; `compileGraphicsPipeline(_:) throws` and `SDLGPUError`; `submitBatch` (still `async` only, hence XP-G22); `SDLGPUShaderLibrary(directory:)` (a marker or a reflection `.json`) and `init(directory:verifyingSources:)`; `MetalUICompileShaders`' arguments, outputs and `SOURCE.sha256` format (`CompileArguments.swift`, `ShaderPlan.swift`, `SourceMarker.swift`, `ShaderCompiler.swift`), the shadercross lookup (`ShadercrossLocator.swift`), the plugin, and `docs/packaging.md` §4a (the pin, the Linux aarch64 recipe, `BS-H`). `compile-app-shaders.py` is gone from `5f03ab7b`.
  (3) **The scripts' logic**, on macOS: `MetalUICompileShaders` built from a read-only copy of MetalUI `5f03ab7b` with `swift run --package-path … --scratch-path …` (nothing written into the copy) and run by `scripts/build-shaders.sh` with a stub shadercross: the outputs are named `NAME.<stage>.{spv,msl,dxil,json}`, MetalUI's `SOURCE.sha256` equals what `sha256sum` prints for the stage files (so the script's "current" test accepts it), the rerun prints `Shaders/viewport/compiled is current.`, a missing shadercross exits 69 with the pin in the message, and a failed compile exits 1 and removes the directory.
  (4) **The diffs apply.** Every code block and diff of tasks 0 to 8, applied in order to an export of `1aad412`, applied (`patch`, 86 operations, no reject), and task 7 step 6's diffs apply to the result of task 8. Task 9's diffs were made with `diff -u` from master's files (and task 4's versions); `bash -n` passes on `scripts/build-shaders.sh`, `scripts/linux-test.sh` and `scripts/package-linux.sh` as changed, and the workflow parses as YAML.
  (5) **The baseline.** macOS `CreatorViewportTests` on `1aad412`: 304 tests in 41 suites, passed (the figure the tasks' deltas start from).
  (6) **The finished tree builds.** In a scratch copy (all of tasks 0 to 12 applied, with a read-only export of MetalUI `5f03ab7b` as `../MetalUI`): on macOS, with task 7 step 6 too, `swift build --build-tests` with no warning beyond the linker's, and `CreatorViewportTests` 317 tests in 45 suites passed (304 + 14 − 1) and the app filter 11 tests; on Linux (the xp-2 image, without step 6, whose `submitBatchSynchronously` does not exist yet) `swift build --build-tests` built every `RenderSDL` file with no error or warning. No test ran on Linux (no shadercross in that image, so no compiled shaders).
  Not checked: the Linux and Windows test runs; the native `shadercross` stage, a real shadercross run through `MetalUICompileShaders` on Linux, the PowerShell scripts, Windows, and `scripts/linux-test.sh` end to end. Task 4 step 4, task 5 step 4 (the clean macOS build, `SG-D`) and every task's "Expected" line are where they get checked.

Written and checked in a scratch copy of the worktree (the session's scratchpad), with a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (read-only; master `b15e038c`). Every code block above is a file read from, or a diff between, the scratch trees "master plus tasks 0 to N", so applying the tasks in order reproduces them (the compiled shaders aside: they are not in the repository, the build makes them). For each task: `swift build --build-tests` on macOS with no new warning (Linux builds print none either), `swift test --filter` on macOS and, through `XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh test --filter …`, on Linux (Docker, OrbStack, Mesa lavapipe), and `swiftlint lint --strict` with zero violations. Tasks 10 to 12 were built and tested on Linux against a copy of MetalUI patched as in the appendix; everything else against MetalUI as it is.

The second review round (cube hit-testing, `metalUISDL`, no raw `SDL_GetError()`, the waiting-click tests, gap and check numbering, the script's argument form and `IMAGE`) was applied to the finished tree (tasks 0 to 12) and checked there: `swift package clean` then `swift build --build-tests` on macOS (the `SG-D` check: 999 build steps, no `error:`, no `warning:`), `swiftlint lint --strict` with no output on both trees, the macOS full run and the Linux `all` run by the pass rule (below), and the new tests mutated: with the click's tool capture reverted `aWaitingClickGoesToTheToolItWasMadeWithAndNotTheOneSetWhileItWaited` fails, with `drawsWidgets` left out of `cubeCatches` `aBackendThatDrawsNoCubeLeavesItsCornerToTheScene` fails. The task 8 variant (`SDLViewportBackend.drawsWidgets` false, its test expecting false) was run on Linux (`ViewportBackendTests` and `SDLViewportBackendTests`, 10 tests passed); the intermediate trees of tasks 1 to 7 were not rebuilt one by one this round (their diffs are unchanged except the lines named above).

| Task | State | macOS `CreatorViewportTests` (baseline 304 tests in 41 suites) | Linux `CreatorViewportTests` (baseline 259 in 34) | MetalUI |
|---|---|---|---|---|
| 0 | `t0` | unchanged (docs and a script) | baseline | b15e038c |
| 1 | `t1` | baseline + 0 (304 in 41) | baseline + 1 (260 in 34) | b15e038c |
| 2 | `t2` | baseline + 9 (313 in 42) | baseline + 10 (269 in 35) | b15e038c |
| 3 | `t3` | baseline + 10 (314 in 42) | baseline + 13 (272 in 35) | b15e038c |
| 4 | `t4` | baseline + 13 (317 in 44) | baseline + 17 (276 in 37) | b15e038c |
| 5 | `t5` | baseline + 13 (317 in 44) | baseline + 21 (280 in 39) | b15e038c |
| 6 | `t6` | baseline + 13 (317 in 44) | baseline + 45 (304 in 41) | b15e038c |
| 7 | `t7` | baseline + 13 (317 in 44) | baseline + 57 (316 in 42) | b15e038c |
| 8 | `t8` | baseline + 13 (317 in 44) | baseline + 59 (318 in 43) | b15e038c |
| 9 | `t9` | baseline + 13 (317 in 44) | baseline + 59 (318 in 43) | b15e038c |
| 10 | `g1` | unchanged (only SDL files change) | baseline + 66 (325 in 44) | a copy patched with the request (MetalUI S11 has it since) |
| 11 | `g2` | unchanged (only SDL files change) | baseline + 67 (326 in 44) | a copy patched with the request (MetalUI S11 has it since) |
| 12 | `g3` | baseline + 14 (318 in 45) | baseline + 76 (335 in 46) | a copy patched with the request (MetalUI S11 has it since) |

This table is the record of the trees built before the 2026-10-22 revision (MetalUI `b15e038c`, tasks 10 to 12 on a patched copy). The figures in brackets are the absolute counts measured on master `11aab8e` (master `1aad412`'s macOS `CreatorViewportTests` is the same 304 in 41); **judge by the delta from the baseline you took in task 0**, since another track's merge (7c-4) moves the absolute figure. The new tests per task are the differences between rows. The macOS app tests (`LaunchSmokeTests`, `ViewportPaneTests`, `SelfTestTests`) run 11 tests after task 8 (master: `LaunchSmokeTests` 2 and `ViewportPaneTests` 3 are 5 of them, so +2 and -1, and `SelfTestTests` unchanged); on Linux the same filter runs 11.

Full suites, by the pass rule, **as measured before this revision on master `11aab8e`** (11 lines on Linux then; 12 everywhere now: the expectations of task 9 step 4 replace these):

- Linux, end of task 9 (`XP_TRACK=xp-3 IMAGE=metalcreator-linux:xp-3 scripts/linux-test.sh all`): PASS, 11 "Test run with" lines, 4123 tests (derived: the end-of-task-12 run below minus tasks 10 to 12's 17 Linux tests), then `--self-test` and `--smoke-test 20` ok.
- Linux, end of task 12 (patched MetalUI): PASS, 11 lines, 4140 tests, `--self-test` and `--smoke-test 20` ok (the smoke test reports `the 3D viewport drew 1 frame`).
- macOS, end of task 12 (`swift test` once): exit 0, 12 "Test run with" lines, 4671 tests, 0 issue lines. Master: 12 lines, 4656 tests.

Also checked: the finished tasks 0 to 9 on Linux against MetalUI at the CI pin `c502f14c` (`CreatorViewportTests`, the app tests above, `--self-test` and `--smoke-test 20` all pass, as against `b15e038c`). Not verified, and why: Windows and Direct3D 12 (CI only; see Risks), a real GPU (human checks XP-20 to XP-25), and tasks 10 to 12 against a MetalUI that has landed the verbs (the signatures are the request's; adopt and rerun).

**Revision of 2026-10-21 (U1(b)): what was checked and what was not.** Planning only; no product code was written into the repository. Checked, in a scratch directory outside the repository (the session's scratchpad), against SDL_shadercross commit `1ff05bec573988a98ef9e0260b4da44f512b8367`: 
  (1) **The pin exists and is the only pin there is.** `gh api repos/libsdl-org/SDL_shadercross/releases` and `/tags` return nothing and `git ls-remote --tags` is empty; `main` is at `1ff05bec573988a98ef9e0260b4da44f512b8367` (2026-09-03T17:00:18Z) and its latest successful `Build` run (33781992136) is on that commit. Its CMake script fixes Microsoft's DirectXShaderCompiler `v1.9.2602` (`linux_dxc_2026_02_20.x86_64.tar.gz`, `dxc_2026_02_20.zip`, SHA-256 in the script; no Linux aarch64 build exists).
  (2) **It builds in the plan's Dockerfile stage.** An `amd64` `ubuntu:24.04` stage on this aarch64 Mac (OrbStack, emulated): SDL3 `release-3.4.16` from source, then SDL_shadercross at the pinned commit with its three submodules, the prebuilt DXC, SPIRV-Cross built shared, and `-DSDLSHADERCROSS_VENDORED=OFF -DSDLSHADERCROSS_INSTALL_RUNTIME=OFF`. First variant (with `INSTALL_RUNTIME=ON`, which also builds vkd3d and clones three repositories at `main`): 18 min 41 s cold, 867 MB. The plan's variant (runtime libraries copied beside the binary instead): 4 min 06 s on top of the cached SDL layer, 214 MB, so about 12 minutes cold (apt 3 min 40 s, SDL3 4 min). Both images produce the same output.
  (3) **It compiles the plan's HLSL.** The 16 stage files and `common.hlsli` of Task 4 (extracted from this plan) compiled with `scripts/build-shaders.sh` as written here, inside the image, with MetalUI mounted read-only: `Compiled 16 shader(s) to SPIR-V, MSL, DXIL and reflection JSON`, 66 files (`.spv` starts `03 02 23 07`, `.dxil` is a `DXBC` container, `.msl` is Metal source, `mesh.vert.json` says 2 storage and 2 uniform buffers as this task says), 1 min 40 s emulated, 336 KB; a second run is byte-identical (`diff -r`), and the two images' outputs are byte-identical. The scripts' failure paths were run too: unchanged sources print `Shaders/viewport/compiled is current.`; an edited source rebuilds; no shadercross exits 69 with the message that names the tool, the repository and the pinned commit; a source that does not compile exits 1 with the compiler's complaint, the file and the same naming, and removes the half-built directory. Nothing was written into the repository: the scratch tree, the images and the outputs are in the session's scratchpad and were not committed.
  Not checked: the PowerShell scripts (no `pwsh` here) and the Windows build (CI only), `scripts/linux-test.sh` end to end (`bash -n` only; the diff is made against task 0's version and needs the rest of the tasks applied to run), the workflow (YAML parsed, not run), and any native aarch64 or x86_64 timing.
Not re-measured: every test count after Task 4 is recalculated by arithmetic from the figures measured on master `11aab8e` (macOS: the old three shader tests become three; Linux: one more at task 4, one at task 8, plus the new suite), not by a run; the tasks 4 to 12 trees were not rebuilt after this revision. Rebuild and re-measure when executing (task 4 step 5 and the deltas). The `ShaderSourceTests`, `ShaderToolchainTests` and `ViewportShaderCheck` code in this revision was written against the tree of tasks 1 to 3 by reading, not compiled.

A first full Linux run, made before the shared pipelines of task 5 existed, failed once on `ScrollZoomTests.theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay`, a real-clock test; an immediate rerun passed. The likely cause is a main actor held by tests that each compiled their own pipelines (about a second each on lavapipe) on a Mac that other sessions were also loading, which task 5 removes by sharing one set; both later full runs (end of task 9, end of task 12) passed with it.

---

## Risks

1. **Direct3D 12 is unverified until the Windows job runs.** The SPIR-V path (Vulkan on lavapipe) is what these tests exercised. DXIL comes from the same SPIR-V through spirv-cross and DXC. The known trap, MetalUI rule `GA-Q` (a fragment stage must read every vertex output it declares), is respected: every fragment shader reads all its inputs, and the ID pass has vertex shaders of its own for that reason. If `CreateGraphicsPipelineState` still answers `E_INVALIDARG`, the error names the vertex and fragment shader and carries SDL's reason (`compileGraphicsPipeline`, MetalUI S11).
2. **A real GPU is stricter than lavapipe** about descriptor bindings, storage-buffer alignment and MSAA formats. Human checks XP-20 to XP-25 are where that shows.
3. **The borrowed device.** `SDLViewportBackend` keeps the window renderer's `SDLGPUDevice` and every buffer made on it; the viewport model must not outlive its window (MetalUI: "keep it no longer than the window"). The app has one window, and `New`/`Open` replace the model inside it, which releases the old buffers on the live device.
4. **Pick latency (U4, hybrid).** A hover can name the previous camera's face for the 40 ms settle plus a few milliseconds of readback after an orbit stops; a click never does: it is answered from its own view's buffer. Until MetalUI answers XP-G22 such a click is delivered a few milliseconds late (asynchronously, to the tool of its press); after task 7 step 6 it stalls that one frame instead, as on Metal. A scene that changes on every frame for a long time (a fillet drag) never settles, so its hover freezes until it stops.
5. **Large meshes.** A mesh's vertex buffer is `3 × triangles × 48` bytes; SDL_GPU buffers are limited to 4 GiB (`UInt32`), so a mesh of about 29 million triangles fails to upload and its solid is skipped silently (`SDLViewportUploader.storageBuffer` answers `nil`). 7c's previews are far below that (4 M triangles is 576 MB).
6. **macOS look.** The cube's face names now go through `CoreTextTextSystem` instead of a direct `CTLineDraw`: the test that reads the pixels passes, the antialiasing may differ by a hair (XP-26).
7. **The Windows Swift 6.4 compiler** asserts on an `async` function that holds a loop's locals across an `await`, and in release builds crashes splitting a closure-specialised `async` function that takes a closure (xp-2's `OccupancyGrid.fill`, fixed with `@_optimize(none)`). The picker's loop is split into synchronous helpers, no `async` function in `RenderSDL` takes a closure parameter, and no test has a loop around an `await`. The release build is CI's "Build release (for the zip)" step, which compiles `RenderSDL`; the asserts snapshot on this Mac (`TOOLCHAINS=org.swift.64202605271a`) covers only the portable code. If Windows still crashes, the stack trace names the function: give it the `@_optimize(none)` treatment with a comment.
8. **MetalUI drift.** Every MetalUI name was checked against `5f03ab7b`, master's pin (S11, S12 and the XP-G21 fix in it). A later MetalUI that renames a typed verb breaks the build in `SDLViewportPipelines`, `SDLViewportUploader`, `SDLViewportRenderer+Record`, `SDLViewportPicker` or the scripts' `MetalUICompileShaders` call, loudly; `ShaderToolchainTests` names the tool the scripts must run.
9. **Real-clock tests on a loaded machine.** `ScrollZoomTests.theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay` failed once in a full Linux run (see Verification). Task 5 removes the likeliest cause; if it recurs on a busy runner, the test (not xp-3's) needs a yield-based wait instead of a wall-clock one.
10. **The SDL products on macOS (`SG-D`).** `CreatorViewport` and its tests name `metalUISDL` and `metalUISDLGPU`, both conditional on Linux and Windows. Task 5 builds the macOS tests from a clean state straight after the manifest change and it passed (MetalUI `b15e038c`, before this revision; re-check it at `5f03ab7b`); a MetalUI or SwiftPM change that drops the module maps again would show as a missing `MetalUISDL` or `CSDL` module on macOS first, and the stop-and-decide note in task 5 says what to do.
11. **A refused pipeline's reason is SDL's.** `compileGraphicsPipeline` (MetalUI S11, XP-G19) puts SDL's text in the error, but some drivers leave it empty; MetalUI then names the description's key fields (`GB-G`). On a Direct3D 12 failure with no text, run the same pipeline on Vulkan (lavapipe) to tell a bad register from a missing feature.
12. **Numbering across branches.** XP-G21 is taken (the Windows release-build crash, fixed by MetalUI `5f03ab7b`, xp-2's row); xp-3 owns XP-G14 to XP-G20 and XP-G22, and human checks XP-20 to XP-26 (xp-2 took XP-16 to XP-19, XP-19 being the AppImage); the erratum is E7 (E6 is adopt-s9's). A gap any branch finds next takes XP-G23, a check XP-27.
13. **The Linux shadercross stage is an LLVM build.** It builds libsdl-org's DirectXShaderCompiler fork from source with MetalUI's recipe, natively on x86_64 and aarch64 (MetalUI measured 6 min 45 s at `-j8` on Linux aarch64), so the first CI run on a new pin pays 15 to 30 minutes per arch and buildx's cache serves the rest; this replaces the earlier amd64-only image (Microsoft ships no Linux aarch64 DXC), which ran emulated on aarch64 and would now also have had to run Swift emulated for `MetalUICompileShaders`. If the stage fails to build on one arch, the fallbacks are MetalUI's: `--formats spv,msl,json` (no DXIL is needed on Linux; HLSL to SPIR-V still needs DXC), or compiling on the other job and handing the directory over as an artifact.
14. **The Windows shadercross build has never run.** `scripts/install-shadercross.ps1` and the workflow steps follow SDL_shadercross's own Windows CI (`Build` workflow, MSVC row: prebuilt DXC, SPIRV-Cross built from the submodule, Ninja, `-DSDLSHADERCROSS_VENDORED=OFF`), but PowerShell is not installed on the Mac this was written on and no Windows machine ran it. Expect a fix or two on the first run: the SDL3 cmake config found through `CMAKE_PREFIX_PATH`, the runtime DLLs (`dxcompiler.dll`, `dxil.dll`, `spirv-cross-c-shared.dll`) that `-DSDLSHADERCROSS_INSTALL_RUNTIME=ON` copies beside the executable, and `Enter-VsDevShell` from Visual Studio's DevShell module inside the script (no action, so the later `swift` steps keep their environment). The Windows job is `continue-on-error`, so the Linux result stays readable; its cache is `actions/cache/restore` + `save` keyed by the pin, saved right after a whole build.
15. **`swift build` alone compiles no shader.** A developer who builds without `scripts/build-shaders.sh` (or `scripts/linux-test.sh`, which runs it) gets a binary whose SDL viewport has no shaders. It does not hide: `--self-test` and `--smoke-test` fail with a message that names the script and the pinned tool, the SDL suites fail on the first `verify()`, and a build older than an HLSL edit fails `ShaderSourceTests`. MetalUI's `CompileShaders` command plugin (`swift package --allow-writing-to-package-directory compile-shaders --source Shaders/viewport --out Shaders/viewport/compiled`) does the same compile from this package; MetalUI offers no build-tool plugin (ruling `BS-D`), so a step stays.
16. **The pin is a commit of a repository with no release and no tag.** GitHub serves any commit reachable from a branch by its SHA, so `git fetch origin <sha>` keeps working while it stays on `main`; if SDL force-pushed `main`, the fetch would fail and the build would stop (naming the tool and the commit). Mitigation if that happens: mirror the commit into a repository of ours and change `SHADERCROSS_REPOSITORY` (one line). Moving the pin is one commit in `scripts/shadercross.env` plus the Dockerfile's `ARG`, and `ShaderToolchainTests` fails until both agree.
17. **What the Linux stage fetches.** SDL by tag, SDL_shadercross by commit and its four submodules by the commits it records; `-DSDLSHADERCROSS_INSTALL_RUNTIME` is OFF, because ON makes its CMake clone Vulkan-Headers and Vulkan-Loader at `GIT_TAG main` and build vkd3d, for a Direct3D-bytecode path the viewport does not use. Only Ubuntu's apt packages are unpinned. The Windows script keeps the option ON, as SDL_shadercross's own Windows CI does, because there it only copies DLLs.
18. **Files made by the container in the worktree.** `scripts/linux-test.sh` runs the compile in a container that mounts the repository read-write, so `Shaders/viewport/compiled` belongs to whoever Docker maps (OrbStack: the user; Docker on a Linux host: root, which the next `rm -rf` of a plain user cannot remove). It is git-ignored either way.
19. **`swift run` on a read-only MetalUI.** `scripts/build-shaders.sh` builds `MetalUICompileShaders` with `swift run --package-path ../MetalUI --scratch-path …`; in the container `../MetalUI` is mounted read-only. Measured on macOS against a read-only copy of `5f03ab7b`: it builds and writes nothing there (MetalUI has no remote dependency, so no `Package.resolved`). If a SwiftPM on Linux wants to write into the package anyway, build the tool from this package's own graph instead (`swift build --product MetalUICompileShaders --scratch-path /build`, MetalUI being a path dependency) and run it from `--show-bin-path`; MetalUI's docs name `swift run --package-path .build/checkouts/MetalUI` as the certain fallback for a URL dependency.
20. **XP-G22 may take a while.** Until MetalUI submits a render batch without `await`, a click whose buffer has not landed is delivered a few milliseconds late. That is exact (the click's own view, the press's tool and projector: task 2's tests) and blocks nothing; task 7 step 6 is ready against the requested signature and changes only `SDLViewportPicker.renderNow` if MetalUI spells it differently.

## Self-review

- **Revision of 2026-10-22 (start of execution).** Rebased on master `1aad412` (xp-2 merged). MetalUI's answers are in: task 0 logs XP-G1, XP-G2 and XP-G14 to XP-G20 as answered, with S11 `11dca65e` and S12 `d995f4b4`, and XP-G22 (a render batch submitted without `await`) as the one open gap; tasks 10 to 12 have no gate and use `setViewport(…) -> Bool`, `maxAnisotropy:`, `writesColor:` and `r32Float` as MetalUI spells them; pipelines come from `compileGraphicsPipeline` with SDL's reason in `ViewportRenderError.deviceRefused` (task 5, and the pipeline diffs of tasks 10 and 11 rebuilt on it); the appendix that patched MetalUI is gone and `METALUI_COMMIT` is not bumped (except by task 7 step 6, if XP-G22 lands). The scripts run `MetalUICompileShaders` from `../MetalUI` with a scratch path of ours; the freshness check stays on the `SOURCE.sha256` it writes, plus our `INCLUDES.sha256` (U1, task 4). U4 is hybrid (U4, Key decisions, Review Focus 3, task 2's and task 7's text, task 7 step 6, Risks 4 and 20). Checks are XP-20 to XP-26 in group XP3 and the erratum is E7, everywhere (the shared-files table, task 3's and task 8's notes, CLAUDE.md, the Risks). Task 0, task 4's Docker and CI steps and task 9 are rewritten against master's files (no re-added test arguments, `IMAGE`, count, SHA pins or vcpkg steps; every `uses:` SHA-pinned), and the packages now ship `MetalUIAppShaders` with clean-environment checks (task 9, Review Focus 7). The Windows compiler rules and the process, MetalUI and CRLF rules are Global Constraints, with the asserts-snapshot release build in tasks 2, 7 step 6 and 9.
- **Spec coverage (section 4 and the task list).** Renderer behind a protocol, Metal kept: task 2. The same passes on SDL: 4x MSAA and depth (6), instanced lines (6), the ID-pass picker with readback (7), label texture (10), slice texture (12), field tint, `ViewportClip`, warning faces, guides, overlay fills (6), triad and cube (10), ghosts (6, 11). HLSL to SPIR-V/DXIL through the path MetalUI provides (`MetalUICompileShaders`, MetalUI S12): 4. `Matrix4`/`FrameUniforms` off `simd`, `GPUDataTests` in sync: 1 and 4. `CubeLabelAtlas` through portable text: 3. `ViewportPlaceholder` replaced: 8. Packaging ships the shaders: 9. MetalUI gaps logged, never worked around: 0. Tests: model-side portable (2), renderer tests under lavapipe and WARP (5 to 12), the picker's readback (7), gating and `XP_REQUIRE_GPU` (0, 5, 9), human checks (9), `--smoke-test` draws the real viewport (8). Constraints: CLAUDE.md portability (every SDL file is `#if canImport(MetalUISDLGPU)`), non-async heavy loops and no closure-taking `async` function (7), Linux via `scripts/linux-test.sh` with `XP_TRACK=xp-3` (0), Windows in CI only, release build included (9), 12 "Test run with" lines everywhere (no new target). Out of scope respected: no compute (xp-c), Mesh items draw (6). Erratum E1 is honoured (`CreatorViewport` stays declared everywhere).
- **Placeholder scan.** No "TBD" or "add error handling": every step is code or a command. The values left to the executor are facts of the outside world: the baselines of task 0, the MetalUI commit that answers XP-G22 (task 7 step 6), and on Windows where the developer built shadercross (`-ShaderCross`).
- **Type consistency.** `ViewportBackend.pickWhenReady(at:in:)` is `async` from task 2 to task 8 (and `SDLViewportPicker.pickWhenReady`, `SDLViewportBackend.pickWhenReady` with it) and synchronous after task 7 step 6, which changes the protocol, its default, `ViewportModel.pickWhenReady`, `install(_:)`, `click(at:modifiers:)`, the picker, the backend and both tests together; `SDLViewportPicker`'s `land(_:for:ticket:)` takes a ticket only from step 6. `SDLViewportPipelines.init(device:library:)`'s `pipeline(…)` helper gains `cull:` (10) and `writesColor:` (11) on the `compileGraphicsPipeline` form of task 5. `SDLViewportRenderer.init(device:pipelines:)` and `init(device:library:)` (task 6) become `init(device:pipelines:labelAtlas:)` and `init(device:library:labelAtlas:)` in task 10 and the callers (`SDLViewportBackend`, `SDLRenderRig`) change in the same task; `SDLFramePlan` gains `cube`, `triad` (10) and `slice` (12); `SDLViewportPipelines` gains `cube` (10), `ghostDepth` (11), `slice` (12); `SDLViewportShaders.names` grows with them and the stage counts follow (16, 18, 20; 66, 74, 82 compiled files); `SliceTextures.filled` (Metal) becomes `SliceTextureValues.filled` in task 12. `ShaderToolchainTests`' first test is `thePinIsWrittenOnceAndTheScriptsCompileThroughMetalUIsTool`.
- **Interfaces blocks.** Re-read for every task against the code it carries: task 0 (master's script, the gap rows), task 4 (MetalUI's tool and marker in, the scripts' exit codes, `METALUI_TOOLS_SCRATCH`, `compile_shaders`, `SHADERCROSS_IMAGE`/`JOBS` and `/opt/shadercross` out), task 5 (`compileGraphicsPipeline`), task 7 (the async verbs, and step 6's `waitBlocking`, `downloadSynchronously`, `submitBatchSynchronously`), task 9 (`MetalUIAppShaders` in the packages), tasks 10 to 12 (MetalUI S11's verbs).
- **Review Focus.** Each of the seven lines has its test or check in the task named there.
- **Applied, not built.** Every code block and diff of tasks 0 to 12, in order (task 7 step 6 after task 8), applies to an export of `1aad412` (136 operations, no reject); see Verification for what was built and run.
- **Earlier rounds.** Review round 2 (cross-track and cube) and the 2026-10-21 U1(b) revision stand as amended above: `drawsWidgets` and `cubeCatches(_:)` (task 2, switched on in task 10), `metalUISDL` beside `metalUISDLGPU` with a clean macOS build as the `SG-D` check (task 5), no raw `SDL_` call, a waiting click keeping the tool and projector of its press (with tests that fail without it), baseline-plus-delta counts.
