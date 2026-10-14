# Cross-platform: Linux and Windows (sub-project XP) — design

Status: written 2026-10-13 from a conversation with the user; awaiting the user's review.
Parent spec: `2026-10-07-metalcreator-vertical-slice-design.md`, with all its Errata. MetalUI's cross-platform path:
`../MetalUI/docs/getting-started.md` ("Linux and Windows"), `docs/guides/cross-platform.md`, record §37, §80.

## 1. Intent

MetalCreator runs on macOS only today. MetalUI already runs on Linux and Windows through its SDL3 backend (`MetalUISDL`,
traits `SDL` and `AccessKit`; Vulkan on Linux, Direct3D 12 on Windows; portable text, glass, file dialogs, drawn menus,
AccessKit). XP brings MetalCreator to Linux (x86_64, aarch64) and Windows (x64) on that backend, running **in parallel
with 7c**.

**Success, in the end:** the same app, the same files, the same graph, on all three platforms, with the macOS build
unchanged in look and behaviour.

### Decisions recorded (user, 2026-10-13)

| # | Decision |
|---|---|
| X1 | Port on MetalUI's SDL backend; run as a parallel track beside 7c. |
| X2 | Milestones: **xp-1** everything except the 3D viewport (a placeholder there) builds, tests and launches; **xp-2** OpenCascade on Linux and Windows; **xp-3** the viewport on SDL GPU (needs MetalUI gap XP-G1). Each milestone is its own plan. |
| X3 | Verification: Linux locally in Docker (OrbStack, aarch64) and in CI; Windows in CI (GitHub Actions `windows-latest`). MetalCreator gains `.github/workflows`. macOS stays verified locally (full suite, OCCT, Metal), not in CI. |
| X4 | 7c stays portable (7c spec D11). |
| X5 | No third-party code without asking: Apple-only pieces are replaced by our own Swift or by MetalUI API. |

## 2. xp-1: everything but the viewport

### 2.1 Package

- Follow MetalUI's recipe (`getting-started.md`, `SG-D`): on Linux and Windows the MetalUI dependency asks for traits
  `["SDL", "AccessKit"]`; the app target adds `MetalUISDL` (`.when(platforms: [.linux, .windows])`),
  `MetalUIPortableText` and `MetalUISystemFonts` (unconditionally). `platforms:` keeps `.macOS(.v26)`.
- The manifest becomes two lists, like MetalUI's (`PC-A`): targets that import no Apple framework are declared
  everywhere; `CreatorViewport`, `CreatorOCCT`/`COCCT`, `ViewportHarness` and `GraphPanelPreview` are declared under
  `#if os(macOS)` in xp-1. The OCCT `unsafeFlags` and Homebrew prefix stay macOS-only until xp-2.
- MetalUI stays a sibling `path:` dependency; CI checks out `mburger89/MetalUI` (public) beside the repo at a pinned
  commit recorded in the workflow file, bumped when MetalCreator adopts a MetalUI change.

### 2.2 Code that moves off Apple frameworks

| Today | xp-1 |
|---|---|
| `CryptoKit.SHA256` (`ImageHash`, `NodeID+Scoped`) | our own `SHA256` in `CreatorGraph` (pure Swift), used on every platform, pinned by the NIST test vectors and by equality with CryptoKit's output on macOS |
| `GreyImageDecoder` (ImageIO, CoreGraphics, UTType) | MetalUI S2's public decode (grey pixels plus EXIF orientation, stb_image) on every platform once it lands, pinned against ImageIO's result on macOS for the existing fixtures; until then ImageIO stays on macOS and Image Field off macOS reports "Images need a newer MetalUI on this platform." (XP-G4) |
| Test image fixtures written with CoreGraphics (`TestImages`, `AppTestImages`) | checked-in PNG/JPEG bytes, or written by a tiny PNG encoder in the test support |
| `SelfTest`'s Metal check | `#if canImport(Metal)`; off macOS it checks the SDL shader directory instead |
| `main.swift` `try App()` | `#if canImport(MetalUISDL)` → `App(platform: try SDLPlatform(), textSystem: …PortableTextSystem…)` as `metalui new --cross-platform` generates |

### 2.3 Kernel and viewport placeholders

- Off macOS in xp-1 the app has no OCCT. A `KernelUnavailable` kernel (`CreatorKernel`) answers every operation with
  the error "Geometry isn't available on this platform yet." Nodes show it on their badges; the graph, inspector,
  sketcher (pure Swift), patterns, fields that don't need the kernel, groups, comments, save and open all work.
- The viewport pane shows a placeholder card: "The 3D view isn't available on this platform yet." The layout,
  split, top bar and panels are otherwise the same.

### 2.4 Window chrome and input

- `windowStyle: .hiddenTitleBar` is ignored on SDL and `titleBarInsets` reads zero (MetalUI `AS-E`); `TopBar` already
  pads from `titleBarInsets`, so it sits under the system title bar there. `WindowDragHandle` stays (a no-op on SDL,
  divergence 276). MetalUI draws the menu bar strip (25 pt) and the toolbar strip where the platform has none; the
  layout reads `Window.drawnChromeHeight` where it sizes against the window.
- Shortcuts use MetalUI's `.primary` modifier (⌘ on macOS, Ctrl elsewhere); any shortcut spelled `.command` is
  re-spelled `.primary` (macOS value-identical).
- `ContentType`s used in file dialogs declare `filenameExtensions` (SDL filters by extension only, divergence 129).
- Cursors: SDL has no hand or zoom cursor (`CI-H` item 8); MetalUI's fallback is accepted.

### 2.5 Tests

- The full suite runs on Linux and Windows minus what needs Metal or OCCT; those test targets or declarations are
  gated with `#if canImport(Metal)` / `#if os(macOS)` (MetalUI's `PC-B`). Tests importing `MetalUIText` (CoreText) move
  to `MetalUIPortableText` where they only need measuring, else stay macOS-only.
- **Pass rule per platform:** exit 0, no "recorded an issue" or "failed after" line, and the number of "Test run with"
  lines the plan states for that platform (macOS keeps its own count).
- macOS's suite count must not drop: a test that moves stays, a gate only removes it off macOS.

### 2.6 CI

`.github/workflows/xp.yml`:
- **linux** (x86_64 and aarch64): a Docker image with Swift 6.4, SDL3 ≥ 3.4 and AccessKit, built like MetalUI's
  `sdl-gpu-linux.yml` image; `swift build`, `swift test`, and a 5-second headless launch of the app under
  `xvfb-run` or MetalUI's offscreen renderer (`SDLPlatform(offscreenRenderers:)`) checking it reaches its first frame.
- **windows** (x64, `windows-latest`): Swift 6.4, SDL 3.4.x, AccessKit as MetalUI's Windows job fetches them; build,
  test, the same launch smoke.
- Runs on pushes to `main` and on pull requests. A red CI never blocks a local macOS merge in xp-1 but is reported.
- Local Linux: `scripts/linux-test.sh` runs the same image under OrbStack's Docker on this Mac (aarch64).

## 3. xp-2: OpenCascade on Linux and Windows

- OCCT 7.9 on Linux from source or a pinned distribution build in the CI image; on Windows a pinned vcpkg or prebuilt
  OCCT 7.9, DLLs beside the executable.
- The manifest's OCCT flags become per-OS (`.when(platforms:)` on the `unsafeFlags`, or `-Xcc`/`-Xlinker` from the
  scripts as MetalUI does for SDL, `PX-I`); `$ORIGIN` rpath on Linux.
- The OCCT and acceptance tests run on Linux and Windows. Packaging for both (a tarball or AppImage on Linux, a zip
  with DLLs on Windows, plus `MetalUISDLShaders`) is part of xp-2.

## 4. xp-3: the viewport on SDL GPU

- `CreatorViewport`'s renderer goes behind a protocol; the Metal implementation stays, an SDL GPU implementation
  draws the same passes (4× MSAA, depth, instanced lines, the ID-pass picker with readback, label and slice textures,
  field tint). Shaders in HLSL compiled to SPIR-V/DXIL through the path MetalUI provides.
- `Matrix4`/`FrameUniforms` move off `simd` to plain SIMD types; `CubeLabelAtlas` rasterizes through MetalUI's
  portable text instead of CoreText.
- Blocked on MetalUI gap XP-G1 (app access to SDL GPU, shader build path, MSAA resolve, depth, readback). xp-3's plan
  is written when it lands.

## 5. MetalUI gaps (forwarded to metalui-7a on 2026-10-13)

| # | Gap | Needed by |
|---|---|---|
| XP-G1 | App access to SDL_GPU through `GPUSurface` (CSDL types or a portable GPU API), a shader build path for apps, MSAA resolve, depth targets, instanced draws, storage buffers, mipmapped r8 textures, texture readback | xp-3 |
| XP-G2 | Portable compute (SDL GPU compute) for 7c's implicit engine | after xp-3 |
| XP-G3 | Custom chrome or hidden title bar on SDL (divergence 276) | polish; xp-1 accepts the system title bar. **MetalUI S1 in progress** (borderless window, `SDL_SetWindowHitTest` drag, resize edges; record §112, `CW-`): adopt when it lands |
| XP-G4 | Grey pixels and EXIF orientation from PNG/JPEG without ImageIO | xp-1 (Image Field). **MetalUI S2 in progress** (public RGBA8/grey decode with size, stride and EXIF orientation over its stb_image; record §113, `IB-`): `GreyImageDecoder` uses it on every platform and xp-1 writes no EXIF reader of its own; until S2 lands, Image Field off macOS reports "Images need a newer MetalUI on this platform." |
| XP-G5 | Open-document events on SDL (divergence 176) | xp-2. **Answered:** `Platform.onOpenURLs` (SDL drop with window 0) → `.onOpenURL` routing; command-line files via `app.open(…)` after the first window (MetalUI `docs/packaging.md`, "Launch arguments"); `.desktop` `Exec=… %F` + `MimeType=` |
| XP-G6 | ContentType filtering by extension (divergence 129) | xp-1. **Answered:** `ContentType("…", conformingTo: [.json], filenameExtensions: ["mcgraph"])` in `allowedContentTypes` |
| XP-G7 | Clipboard types beyond text (graph fragments) | xp-1 copies graph fragments as marked JSON text on every platform without custom types (MetalUI's interim pattern); MetalUI S3 (queued) adds custom types later |
| XP-G8 | Hand and zoom cursor fallbacks | xp-1 accepts MetalUI's fallback (`.link` hand, grab → move, zoom → arrow); MetalUI S4 (queued) adds image cursors |

Each is logged in `docs/metalui-gaps.md` by the track that reaches it, entry and summary row.

## 6. Out of scope

Linux and Windows packaging in xp-1 (it is xp-2); signing for Windows; Wayland-specific or X11-specific behaviour
beyond what MetalUI provides; macOS CI; Intel macOS.
