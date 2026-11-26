# CreatorViewport

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Cross-platform, sub-project xp-3 (the 3D viewport on SDL GPU, Linux and Windows; plan `docs/superpowers/plans/2026-10-21-xp-3-sdl-gpu-viewport.md`,
spec §4, erratum E7) is the viewport's second renderer. `ViewportModel` talks to a `ViewportBackend` (`drawnFrames`, `pick(at:in:)`,
`isPickPending(for:)`, `pickWhenReady`, `onPickReady`, `drawsWidgets`): `MetalViewportBackend` on macOS (`ViewportRenderer` and `ViewportPicker`,
unchanged), `SDLViewportBackend` on Linux and Windows (`Sources/CreatorViewport/RenderSDL`, everything behind `#if canImport(MetalUISDLGPU)`, MetalUI's
typed SDL_GPU layer, no raw `SDL_` call). `ViewportView` is the same on both and picks `MetalView` or `GPUSurface`; `ViewportModel.draw` has one
overload per context. The SDL renderer plans a frame first (`SDLFramePlan`: every buffer made and every copy recorded, because a copy pass cannot run
inside a render pass) and then records the pass; solids, lines, fills, the cube and the slice read their data as vertex-stage storage buffers. Its
pipelines carry their own depth test and are made with `compileGraphicsPipeline` (`SDLViewportPipelines`), so a refused one says SDL's reason in
`gpuFailureMessage`. The shaders are HLSL in `Sources/CreatorViewport/Shaders` (`common.hlsli` mirrors the Swift structs, every member a `float4`, `uint4` or scalar,
never a `float3`), **compiled by `swift build` on Linux and Windows, never checked in** (MetalUI BS-D and XP-G32): `Package.swift` applies MetalUI's build-tool
plugin `CompileShadersOnBuild` to `CreatorViewport` under `#if os(Linux) || os(Windows)` (the host's OS, so a macOS build skips it and needs no shadercross), and it runs
the SDL_shadercross commit pinned in `scripts/shadercross.env` (`METALUI_SHADERCROSS`, else `PATH`; built by the Dockerfile's `shadercross` stage and
`scripts/install-shadercross.ps1`; `scripts/linux-test.sh` and the CI Windows job set the variable) into the target's `MetalUIAppShaders` resource (SPIR-V, DXIL, MSL,
reflection, `SOURCE.sha256`, `INCLUDES.sha256`; editing `common.hlsli` alone reruns it), and a build without shadercross fails with MetalUI's `error:` lines naming
the tool and the pin (after installing it, `swift package clean`: a replaced tool does not rerun the step). `ShaderSourceTests` pins the HLSL struct sizes to the Swift strides
(`GPUDataTests`) and, on Linux and Windows, that the build produced every stage and is current; edit the HLSL, the Swift struct and the MSL together.
The compiled directory is found beside the executable as `MetalUIAppShaders` first, then in the target's resource bundle, then the source tree
(`SDLViewportShaders`, MetalUI's `SDLGPUShaderLibrary.locate(resourceBundle:)`); the tarball, the
AppImage and the zip ship it (copied from the release build's `MetalCreator_CreatorViewport.bundle`), and `--self-test` fails without it, saying what to do (`ViewportShaderCheck`). Picking is user decision U4, hybrid:
`SDLViewportPicker` renders the ID pass in a batch after the draw that follows a change and reads it back with `SDLGPUDevice.download`; until it
lands a hover keeps its face and a click renders its own ID pass when none has landed and waits for it (`pickWhenReady`, MetalUI's `submitBatchSynchronously`; a failed pass answers
empty space at once) and goes to the tool of its press (`ViewportModel.isPickPending`, `pickWhenReady`, `ViewportBackendTests`). `Matrix4.float` is a `FloatMatrix4` and `FrameUniforms` is plain SIMD
(no `simd`), so both exist everywhere. The cube's face names are rasterized by `CubeLabelAtlas.rasterize(using:)` through MetalUI's `TextSystem`
(CoreText's on macOS, the portable one over the installed fonts elsewhere), `CubeLabelFonts` choosing. The render and pick suites (`SDLRenderTests`,
`SDLFieldGuideClipTests`, `SDLPickerTests`, `SDLWidgetTests`, `SDLSliceTests`) run under Mesa's lavapipe in the Linux image and Direct3D 12's WARP in
CI; they skip when no SDL_GPU device answers, and with `XP_REQUIRE_GPU=1` (`scripts/linux-test.sh`, the Windows job) `SDLGPUAvailabilityTests` fails
instead. `--smoke-test` passes only if the viewport drew (`LaunchSmoke.viewport`). The view cube and the axis triad are drawn (task 10: `SDLViewportRenderer+Widgets`, each in its own square through `setViewport`, the cube's names a mipmapped `r8Unorm` atlas read with 8x anisotropy; `drawsWidgets` is true). The ghosts take a depth-only prepass (task 11: `SDLViewportPipelines.ghostDepth`, MetalUI S11's `writesColor: false`, then the
blended pass at less-or-equal), so each pixel blends once. Keep SDL's async calls out of loops that hold
locals across an `await` (the Windows compiler notes below).

- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView` (macOS) and `GPUSurface` over SDL GPU (Linux and Windows, xp-3).
  - A host takes the primary pointer through `ViewportModel.tool` (`ViewportTool`: hover, clicks, and plain primary
    drags it claims, each with a `ViewportProjector` for screen → plane), and draws over the scene with
    `showOverlay(_:)` (`ViewportOverlay`: world-space lines and points in `OverlayTint` roles, dashed construction, and
    a `gridPlane` that replaces the ground grid). Navigation (right/middle drags, Shift/⌥ drags, scroll (a two-finger trackpad scroll pans, a mouse wheel zooms), pinch, the
    cube, handles) always stays the viewport's; the face menu offers only Look At while a tool is set. A tool's
    `navigation` (`ViewportNavigation`, default `.free`) of `.planar` locks the orientation: drags that would orbit
    pan, the cube and its controls are hidden, turning commands and the face menu do nothing (`showsViewCube`,
    `isPlanar`; the first scene's framing never runs, and input finishes an animation instead of freezing it); a tool's
    `framingBounds` is what F frames, and `ViewportProjector.modelArea` the area its on-screen chrome stays in.
    `lookAt(_ plane:framing:)` faces a plane, orthographic. A tool also takes the face or edge under a click it declined
    (`clickedModel`: the sketch editor's Project). `ViewportOverlay` also carries `fills` (`OverlayFill`: world triangles
    in the `.region` tint, one blended pipeline drawn under the lines, never in the ID pass) (a sketch's dimension values are no longer overlay labels: they are ANSI `OverlayDimension`s, `SketchDimensionDrawing`,
    shown with `ViewportModel.showDimensions(_:)`). The face menu adds New Sketch on Face (`ViewportEvents.newSketchOnFace`) on a flat
    face that has a normal, outside sketch mode.
  - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
    the context menu and handles. `ViewportBackend` is what it needs from a renderer: `ViewportRenderer`/`ViewportPicker` (through
    `MetalViewportBackend`) are the Metal side, `SDLViewportBackend` the SDL one. `ViewportView` is the
    MetalUI glue. A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
    solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
    (`ViewportRenderer+Guides`). The renderer keeps the triad's, the overlay's and the region fills' GPU buffers between
    frames: the overlay's key holds the grid's extent and the dashes' zoom, not the pose, so an orbit allocates none, and
    the fills' buffer is dropped once a frame has no fills (`RendererCacheTests`). `handleLabels(measuring:)` reads the size through
    the tracked `viewSize`, as `placedDimensions(measuring:)` does. Text sizes are measured, never estimated from a character count:
    `ViewportView` (and the sketch editor's `PointerReadoutView`) read MetalUI's `@Environment(\.textMeasurer)`, wrap it as a
    `TextMeasure` (`ProposalText` in `.caption`) and pass it into the model calls that place labels and chips; a model test passes a
    fake measure, a view test the real one (`TextMeasure.real()` in each test target's `Support/TextMeasureSupport.swift`).
    There is no default measure and no fallback estimate. Every scroll or pinch event stops a camera animation started mid-gesture.
    The field preview's half of the viewport knows numbers and colours only. A `ViewportItem` may carry `fieldValues` (one per vertex
    of `ViewportModel.displayMesh(of:)`) and a `FieldRamp` (three colours at three values; `FieldRamp.color(at:)` is the Swift twin of
    the shader's `field_ramp`): the renderer draws it with a second pipeline (`FieldShaders`: `field_mesh_*`, a float per de-indexed
    corner in a buffer `GPUMesh` keeps until the values change, `GPUGeometry.fieldCorners`), lit like the plain surface, never on a
    ghost, and wrong-sized values draw the plain surface. A `ViewportSlice` (`ViewportModel.showSlice`) is a translucent quad over the
    scene showing a grid of values (`r32Float`, read with a bilinear blend in `slice_fragment`, kept by `SliceTextures` until its
    `generation` changes); it is equal and hashed by `generation`, never by its values, is drawn ignoring depth (it passes through the
    part) and is never in the ID pass or `sceneBounds`. The viewport's Metal shader source is `ViewportShaders.source + LineShaders.source + FieldShaders.source` (MSL, compiled at run time);
    the SDL renderer's is the HLSL in `Sources/CreatorViewport/Shaders`.
    The cut view (implicit spec §5.1) is a `ViewportClip` (`ViewportModel.showClip`): the fragment shaders discard what lies on the
    side its normal points to, for faces, B-rep edges, field tints and the ID pass (`ClipUniforms` at fragment buffer 3, 4 for the
    tint, 0 for lines, off for handles), and the section's cap (`ViewportSection`, `showSection`; Metal `SectionShaders`, SDL `section.*.hlsl` and `id_section.frag.hlsl` (which draws through `section`'s vertex stage), 25 stages in all with zebra's two) is drawn on the plane with a plane-space hatch and writes nothing in the ID pass, so it is never picked; its outlines are clipped by the current clip moved by the edge bias (so an old outline beyond a moved plane is discarded), and `id_section` declares the clip only; a back face seen while cutting is the part's colour darkened, which remains only as the fallback (before the first cap lands, an item whose section failed, an open mesh). The zebra stripes (`ViewportZebra`, `showZebra`; Metal `ZebraShaders`, SDL `zebra_mesh.vert.hlsl` and `zebra_mesh.frag.hlsl`, pipeline `zebra_mesh`) replace the plain or field-tinted shading of an opaque solid with bands of the reflected direction in the camera's frame or a locked one (`ZebraUniforms`; `ZebraBand` is the CPU twin the tests hold the shaders to); the fragment reads `draw.ghost` so SDL keeps its cbuffer slot (gap XP-G28, adopted: MetalUI XP-G36, pin `71e46462`, now fails the shader build naming the shader and registers when a fragment cbuffer is dropped and SDL's uniform slots would shift); the zebra mesh is tessellated at `DisplayAngle.zebra`. A `ViewportItem`'s
    `warningFaces` take the theme's warning colour (`ShadeUniforms.warning`, face-flag bit 4): a check's highlighted triangles.
  - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
    `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
  `ViewportTool.hoverChanged(_:at:projector:)` tells a tool what is under the pointer and `offersSectionFromFace` lets the face menu offer Section from Face
  beside Look At while a tool (Measure) is set.
  Sheets and curves (NS-1): the theme role `sheetBack` colours a sheet's back (face flag bit 8; `ShadeUniforms` stride 96, so Swift, MSL and HLSL change together); a curve is a `ViewportItem` with `isCurve` and a cached display solid, drawn in every mode and never picked; zebra and the field tint ignore `sheetBack`.

The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift` and the HLSL in `Sources/CreatorViewport/Shaders/common.hlsli`; `GPUDataTests`
pins their strides and `ShaderSourceTests` the HLSL's, so change all three together; the next Linux or Windows build recompiles the HLSL (the plugin).
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`/`dragCancelled(button:)`, `click(at:modifiers:)`, `modifiersChanged(_:)`,
`contextMenuItems(at:)`, `scrolled(dx:dy:at:phase:)`, `pinchChanged`/`pinchEnded`, `cursor`), and `ViewportView` only forwards
gesture values. MetalUI C16 adds a tap's modifiers, `onModifierKeysChanged` (⌘ over a still pointer reaches a tool through
`ViewportTool.pointerMoved(to:modifiers:projector:)`: the sketch editor drops its inference while ⌘ is held), `onCancelled`
on drags and pinches (a dropped gesture ends where it was, a lost primary release too since MetalUI C26: the next press cancels it; one gap is left,
VI-c, a plain pointer move doesn't) and wheel latching. Its keys stay
window-wide stopgaps in `ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
