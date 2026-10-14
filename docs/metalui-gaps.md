# MetalUI gaps hit by MetalCreator

MetalUI's design agent reads this file (MetalUI item C7). Each entry gives a concrete use case:
which button or gesture, which coordinates, what we do in the meantime.

## Summary (M7, 2026-10-09)

Every gap in this file, the MetalUI item that owns it and where it stands, checked against MetalUI master `2155f1e`
and its branches (the PERF-b row alone was re-checked against `e85cb07a` when C14 slice 1 was adopted).
A gap marked fixed and adopted no longer has a stopgap in MetalCreator; its entry below keeps the use case and the
stopgap as they were. The sections below keep each gap's full use case.

| Gap | What | MetalUI item | Status |
|---|---|---|---|
| 1–5 | Scroll wheel, pinch/rotate, middle and right drags, tap location, cursor and drag modifiers | C7 | ✅ fixed (c62d6ba), adopted by the viewport and the graph panel |
| M4-a | An element's size (`onGeometryChange`), focus on click | C9 | ✅ size: fixed by C9 (`onGeometryChange`, KF-J) and adopted (plan `2026-10-12-adopt-c15`): `ViewportView` records the viewport's size from its layout (`AppWindowTests.theViewportLearnsTheWindowsSizeFromItsLayout`, `aResizedWindowResizesTheViewport`, `aDocumentLoadedIntoTheWindowLearnsTheSizeToo`, `ViewSizeObservationTests`); the draw-time record and `observedViewSize` are gone. Focus on click: C9's key regions are adopted for the graph canvas (M5-b, M5-g); the viewport's pointer veto stays (M5-b); its press-resigns-focus hook (`releaseTextFocus`) is gone, `AppWindowRoot` resigns on a press (CT-a, MetalUI C24) |
| M4-b | Opaque helper inside a builder `for`; redraw labels during a camera animation (`TimelineView`) | C9 | 🔄 half fixed: C9 is on MetalUI master and has `TimelineView(.animation)` (api-overview, "Animation"), not adopted: the labels are still hidden while the camera animates (S5-c); the opaque-helper half is not re-checked, the viewport's label loops are still written inline |
| M5-a | `Slider` `onEditingChanged` | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-b | Hover- or region-scoped key bindings | C9 | ✅ fixed by C9 (`feat/key-focus`: `hoverKeyRegion`, `onKeyPress`), adopted for the graph canvas (Comments typing plan); the viewport still runs its pointer veto (M4-a) |
| M5-c | Materials and blur | C10 | ✅ fixed (2155f1e) as a flat tint, adopted by decision (the glass kept the theme's tint); the backdrop blur came with C21 and is adopted (C10-a) |
| M5-d | Gradients | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-e | Modifiers on a press | C7 | ✅ fixed (c62d6ba), adopted |
| M5-f | Canvas scroll and pinch | C7 | ✅ fixed (c62d6ba), adopted |
| M5-g | A press elsewhere ends text editing | C9 | ✅ fixed by C9 (`feat/key-focus`: a key region clears a field's focus on a press), adopted for the graph canvas (Comments typing plan); a press outside every region now resigns too, since the app's root is a resign region (CT-a, MetalUI C24): `AppModel.releaseTextFocus` is gone |
| M5-h | ↑/↓ in a focused single-line field | C9 | ✅ fixed by C9 (`onKeyPress(keys:)` on the field), not adopted: the palette's ↑/↓ stay a keymap action (`PaletteMove`) until the palette is moved onto it |
| M5-i | Keyframe animation | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-j | `ProgressView` | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M6-a | Window title and edited marker | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| M6-b | Close and quit veto | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| M6-c | Full-size content view | C8, C22 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-12-adopt-c22`, with C8-a): the window opens with `windowStyle: AppLayout.windowStyle` (`.hiddenTitleBar`), pending human check AS-5, the live test of the drag |
| M6-d | Open-document events | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| C8-a | Window drag region for a hidden title bar under a gesture-carrying view | C22 | ✅ fixed (MetalUI 930db4a, PR #70: `WindowDragGesture`), adopted (plan `2026-10-12-adopt-c22`), pending human check AS-5: `WindowDragHandle` marks the top bar's empty space and the strip above it (`WindowDragWindowTests`, `SketchWindowDragWindowTests`, `TitleBarClearanceWindowTests`); the real AppKit drag is unproven live (MetalUI's WD1–WD7) |
| M6-e | Public headless test window | item 8 (test harness) | ✅ fixed (MetalUI 280d706, PR #65: `MetalUITesting`), adopted in the test targets (plan `2026-10-12-adopt-test-harness`): `AppWindow` opens the app's real root in a `TestWindow` (`AppWindowTests`), and the observable key routing is pinned by the window tests (`ViewportKeyRoutingWindowTests`, `EditMenuRoutingWindowTests`, `PaletteKeyRoutingWindowTests`), while the canvas hover veto and the `Panel` key context stay pinned only by mapping tests (`AppInputTests`); MetalCreator had no platform fake of its own to replace; the harness's one limit for this app (no `MetalView` draw, so no window size) is gone: the size and the panel's frame come from `onGeometryChange` (M4-a, EP-a) |
| M6-f | `ColorPicker` | C10 | ✅ fixed (2155f1e), adopted (Themes Task 11) |
| M6 resize cursor | Column/row resize cursor | C7 | ✅ fixed (c62d6ba), adopted |
| VI-a | A dropped gesture's end | C16 | ✅ fixed (MetalUI a720fba, PR #67: `.onCancelled` on Drag/Magnify/Rotate gestures; a synthesized `.cancelled` scroll when the window stops being key), adopted (plan `2026-10-12-adopt-c16`): the viewport's three button drags and pinch, the canvas's press, middle pan and pinch, the library row's drag and the panel's resize edge end through it (`ViewportCancelWindowTests`, `CanvasCancelWindowTests`, `PointerCancelTests`); the lost-pinch guesses are gone. A primary drag whose release was lost ends at the next press, through VI-b's fix (MetalUI C26); a plain move still doesn't end it (VI-c) |
| VI-b | A press that continues a gesture arena fails a drag that had reported, without `onCancelled` | C26 | ✅ fixed (MetalUI ff8a1ea4, PR #72: a primary press that finds the arena still pressing is a lost release, so that arena is abandoned through `cancel()` and a fresh arena forms; `press(… continuing: true)` also cancels a reported drag it fails), ✅ adopted (plan `2026-10-12-adopt-c26`): the three stopgaps are gone (the same-button branch of `ViewportModel.beginDragIfNeeded`, the primary half of the drag-ending line in `click(at:)`, `EditorModel.ensurePress`'s drop) and window tests show the viewport's orbit, a handle edit's end and the canvas's move and box ending at the press (`ContinuingPressCancelWindowTests`, `ViewportCancelWindowTests`) |
| VI-c | A lost primary release is not cancelled by the pointer's next plain move, only by the next press | none (MetalUI ruling `GC-C`; SwiftUI behaves the same) | ➖ accepted divergence, found by the C26 adoption (plan `2026-10-12-adopt-c26`); not sent; no stopgap; pinned by `ContinuingPressCancelWindowTests.aPlainMoveDoesntEndALostPrimaryDragOnlyTheNextPressDoes` |
| GI-a | Modifiers on a tap | C16 (with S5-a) | ✅ fixed (MetalUI a720fba: `SpatialTapGesture.Value.modifiers`), adopted (plan `2026-10-12-adopt-c16`): the viewport's click passes its tap's modifiers (`ViewportModifiersWindowTests.aCommandClickReachesTheToolWithCommandAndAPlainOneWithout`); the graph canvas needs nothing, since its one zero-distance drag already carries them and must stay a drag |
| GI-b | Wheel latching (`CI-AD`) | C16 | ✅ fixed (MetalUI a720fba: a scroll latches to the element under its `.began`, momentum included; synthesized `.cancelled` on key loss), adopted (plan `2026-10-12-adopt-c16`) with no code to remove (the entry's stopgap was none): `ScrollLatchWindowTests` pins the canvas's glide staying on the canvas, the viewport's staying off it and key loss mid-glide; human check C16-1 |
| PERF-a | Shadow re-rasterized and re-blurred every frame its content moves | C13 | ✅ fixed (MetalUI ebcf3c7, PR #63), adopted with no code change; idle re-measure pending |
| PERF-b | Every observed change rebuilds, lays out and paints the whole window | C14 | 🔄 partly fixed (MetalUI e85cb07a, C14 slice 1), adopted: unchanged canvas views skip their content getter; build, prepaint and paint still run whole (C14-b queued); timing re-take owed; measured by M7 (below) |
| EP-a | Element frame in window coordinates, hover coordinate space, window size | C15 | ✅ fixed (MetalUI 0abce86, PR #66: `CoordinateSpace.named`, `onGeometryChange` with `.global`/`.named`, `onContinuousHover(coordinateSpace:)`, `\.windowSize`), adopted (plan `2026-10-12-adopt-c15`): the graph panel measures itself (`PanelPlacementTests.theEditorIsToldWhereItsCanvasIs`, `aGrownWindowRebuildsTheCanvasWithWhatItUncovers`, `hidingThePanelClearsThePlacementAndShowingItBringsItBack`, `aNewDocumentIsPlacedToo`) and the palette opens at the canvas's `.global` hover (`PaletteOverlayWindowTests.itOpensWithItsTopLeftCornerAtThePointerWhateverTheViewportHasDrawn`, `FloatingPaletteTests`) |
| EP-b | Chrome-less point-anchored popover that closes on an outside press | C15 | ✅ fixed (MetalUI 0abce86, PR #66: `.anchoredOverlay(isPresented:at:in:anchor:content:)`), adopted (plan `2026-10-12-adopt-c15`): `SearchPaletteOverlay` is an `anchoredOverlay`, and the stopgap's known limits are pinned fixed (`PaletteOverlayWindowTests.aPressIntoATextFieldClosesItAndTheFieldGetsFocus`, `aRightClickThatOpensAContextMenuClosesItAndTheMenuStillOpens`, `aScrollOverItDoesNotReachTheCanvasOrTheViewport`, `itFlipsLeftAtTheRightEdgeAndUpAtTheBottom`) |
| P-a | Third-party notices | C17 | ✅ fixed (67a579e), adopted |
| LF-a | A clip inside an `offset` or uniform `scaleEffect` | C18 | ✅ fixed (0b400b4) |
| LF-b | A clip inside nested flattening effects (LF-a's regression) | C19 | ✅ fixed (9ad2254) |
| TH-a | Menu content can't be evaluated outside MetalUI | none yet (with M6-e) | ✅ fixed (MetalUI 280d706, `MenuEvaluation`, `TestApp.menuBar`), adopted (plan `2026-10-12-adopt-test-harness`): `ThemeMenuEvaluationTests` |
| S5-a | Modifiers on a hover (and a tap, GI-a) | C16 (with GI-a) | ✅ fixed (MetalUI a720fba: `.onModifierKeysChanged(mask:initial:_:)`, also while the pointer is still and on key loss), adopted (plan `2026-10-12-adopt-c16`): `ViewportView` watches ⌘, `ViewportModel.modifiersChanged(_:)` replays the tool's hover with it (`ViewportTool.pointerMoved(to:modifiers:projector:)`), and the sketch editor's rubber band and glyphs drop inference while ⌘ is held, with no mouse move (`InferenceGlyphTests`, `ViewportModifiersWindowTests`); human check C16-2 |
| S5-b | No click count on a drag's value (canvas double click) | C16 (with GI-a) | ✅ fixed (MetalUI a720fba: `DragGesture.Value.clickCount`), adopted (plan `2026-10-12-adopt-c16`): `EditorModel` pairs a click counted 1 and one counted 2 on one target; its own 0.4 s / 4 pt timer, `RecentClick` and the injectable `now` are gone, and the user's double-click speed decides (`DoubleClickTests`, `CanvasDoubleClickWindowTests`); human check C16-3 |
| S5-c | A `MetalView` draw can't draw text (world-anchored labels), and a text's size can't be asked | C23 | ✅ measuring fixed by C23 and adopted; ➖ `drawText` deferred by MetalUI to C14's close-out (GT-F), labels stay views (see entry) |
| M7-a | `ForEach` identity is an id's description | C20 | ✅ fixed by C20 (MetalUI master 5f35df6: identity by `Hashable` equality); nothing to adopt, the canvas's `\.id.rawValue` keys stay correct |
| M7-b | No warm headless frame for measuring | none yet (with M6-e) | ✅ fixed (MetalUI 280d706, `TestWindow` warm frames and `FrameWork`), adopted for work counts (plan `2026-10-12-adopt-test-harness`): `WarmFrameTests`; the release benchmarks (`Bench`) still report cold-frame milliseconds until they are moved onto it |
| C10-a | No backdrop blur behind a material | C21 (was C10-c) | ✅ fixed by C21 (MetalUI master d6a815c: a material blurs what MetalUI drew beneath it, GPU surfaces included; divergences 245 to 248), adopted (plan `2026-10-12-adopt-c21.md`): every glass panel is a material under the theme's tint (`GlassStyle`); human checks C21 pending |
| C21-a | A `Material`'s tint opacity can't be read, so a theme's tint can't be sized against it | C27 | ✅ fixed by C27 (MetalUI master 848ee029, PR #76, record §101: `Material.tint(in:)`, ruling `MT-B`), adopted (plan `2026-10-13-adopt-c27.md`): `GlassThickness.materialOpacity(isDark:)` reads it; the copied `LK-L` table is gone and `GlassMaterialTableTests` with it, `GlassMaterialOpacityTests` checks the read against the drawn backdrop; MetalUI human check MT-3 covers the solve |
| C21-b | Reduce Transparency is neither readable by an app nor honoured by materials | C27 | ✅ fixed by C27 (MetalUI master 848ee029, PR #76, record §101: `EnvironmentValues.accessibilityReduceTransparency`, materials draw an opaque grey with no blur, divergence 315; `TestWindow.setReduceTransparency`), adopted (plan `2026-10-13-adopt-c27.md`): the glass panels and chips read it and the theme's tint goes opaque with MetalUI's grey (`GlassReduceTransparencyWindowTests`); C21-5 runs on a real system |
| CM-a | `TextEditor` has no commit key (⌘↩ or `onSubmit`) | C9 | ✅ fixed by C9 (KF-Z/KF-AA: ⌘↩ is no editing key of a `TextEditor`, so an `onKeyPress` for it commits), adopted by the inspector's note box and the canvas editor (Comments typing plan) |
| CT-a | A press outside every key region resigns no focus, and nothing asks it to without taking over key routing | C24 | ✅ fixed (MetalUI 0fb2ea6e, PR #74, record §98, rulings RF-A…RF-I: `.resignsFocusOnPress(_ isEnabled: Bool = true)`, an opt-in container modifier: a primary press inside it resigns a focused field and routes no key by hover), ✅ adopted (plan `2026-10-13-adopt-c24`): `AppWindowRoot` (and `GraphPanelPreview`'s root) carry it; the viewport's `releaseTextFocus` hook is gone; a press on inert chrome ends a canvas edit and commits a typed inspector value (`CanvasResignOnPressWindowTests`, `InspectorFieldResignWindowTests`) |
| CT-b | No way to set a text field's selection or caret (a field focused from code opens with its caret at the start) | C25 | ✅ fixed by C25 (MetalUI master 3fce05f: `TextField(_:text:selection:)` and `TextEditor(_:text:selection:)` over `Binding<TextSelection?>`; divergences 265, 266), adopted (plan `2026-10-12-adopt-c25.md`): a frame's title opens with all of it selected and a note with the caret at its end (`CommentEdit.selection`); human checks C25 pending |
| CT-c | The canvas typing's key, focus and press routing can't be driven from a test (the C9-dependent behaviour is pinned only by human checks CT-1..CT-9) | M6-e (public headless `Window` with `simulateInput`) | ✅ fixed (MetalUI 280d706), adopted (plan `2026-10-12-adopt-test-harness`): `CanvasNoteTypingWindowTests`, `CanvasTitleTypingWindowTests`, `CanvasTypingKeysWindowTests`, `CanvasTypingFocusWindowTests`, `CanvasTypingUndoWindowTests`; CT-1..CT-11 keep only their visual and machine-specific parts |
| CT-d | The test harness can't drive an input method, so a field's composing (marked text) next to a selection write has no automated test | C28 | ✅ fixed by C28 (MetalUI master f6f865c1, PR #75, record §102: `TestWindow.setMarkedText`, `commitMarkedText`, `cancelMarkedText`; divergences 325 and 326), adopted (plan `2026-10-13-adopt-c28.md`): `CanvasTypingCompositionWindowTests`, `InspectorFieldCompositionWindowTests`; ⌘Z after a selection write is documented and pinned; C25-3 keeps only the feel |
| XP-G3 | Custom chrome or a hidden title bar on SDL (divergence 276) | MetalUI S1 (in progress, record §112, `CW-`) | ✅ fixed by MetalUI S1 (master `ceca59f6`, record §112, `CW-`), adopted (branch `xp-adopt-s1`): the window is borderless on SDL, MetalUI draws minimise, zoom and close, `TopBar` clears `titleBarInsets` at both ends, Close reaches `AppModel.closeRequested()`. **But the drag regions are not published while a real (gesture-taking) viewport is behind the bar: see XP-G11, which bites at xp-3** (human checks XP-11..XP-14) |
| XP-G11 | A window-drag handle above a full-window pointer-taking view gets no SDL drag region (S1, divergence 426) | MetalUI S1b (PR #87, ruling CW-V) | ✅ fixed by MetalUI S1b (PR #87, master `a4ebe288`, ruling CW-V), adopted (branch `xp-adopt-s1b`, CI pin `a4ebe288`): a hitbox carves a `WindowDragGesture` handle only if it ranks strictly above the handle's own hitbox (layer, registration index), and the title band has no element of its own: every blocker carves it except a backdrop (a blocker as wide as the window that reaches below the band), which MetalCreator's full-window viewport is. Buttons, fields and taps in the bar still carve (divergence 426). Divergence 425 is amended: a window-wide pointer-taking view behind the bar loses its presses inside the band to the drag; nothing in MetalCreator relies on a viewport press there. `SDLChromeWindowTests` no longer pins it: the band and the bar's regions are asserted on macOS with the real viewport |
| XP-G4 | Grey pixels and EXIF orientation from PNG/JPEG without ImageIO | MetalUI S2 (record §113, `IB-`, PR #84) | ✅ fixed by MetalUI S2 (master `dea698ca`), adopted (branch `adopt-s2`): `GreyImageDecoder` decodes through `DecodedImage(data:format: .rgba)` on every platform, so the Image Field works on Linux and Windows; ImageIO is gone from `Sources`, and so are `GreyImageDecoder+ImageIO.swift`, `ImageProblem.platformUnsupported` and its sentence. Left open at MetalUI: XP-G10 (a header-only read) |
| XP-G5 | Open-document events on SDL (divergence 176) | answered | ✅ answered by MetalUI (`Platform.onOpenURLs` → `.onOpenURL`; command-line files via `app.open(…)` after the first window; `.desktop` `Exec=… %F` + `MimeType=`); xp-2's (packaging), not adopted in xp-1 |
| XP-G6 | `ContentType` filtering by extension (divergence 129) | answered | ✅ answered and already in use: every `ContentType` the file panels use declares `filenameExtensions` (`ContentType+MetalCreator`, `+Images`, `+Theme`), pinned by `ContentTypeTests`; nothing to change for xp-1 |
| XP-G7 | Clipboard types beyond text (graph fragments) | MetalUI S3 (queued) | 🔄 queued at MetalUI. Nothing to do in xp-1: MetalCreator's graph-fragment clipboard is in memory (`NodeClipboard`) and never reaches the system pasteboard on any platform; a system clipboard (marked JSON text now, S3's custom types later) is a feature of its own |
| XP-G8 | Hand and zoom cursor fallbacks | MetalUI S4 (queued) | ➖ accepted: MetalUI's fallback (`.link` hand, grab → move, zoom → arrow) is used as is; S4 adds image cursors (human check XP-8) |
| XP-G9 | `SDLPlatform(hiddenWindows:offscreenRenderers:)` is `@_spi(Checks)` | open (new) | 🔄 open at MetalUI. `MetalCreatorApp --smoke-test` (the CI launch check, `main.swift`) imports it with `@_spi(Checks) import MetalUISDL`; promote it to public API or name a supported headless-launch entry point |
| XP-G10 | A header-only read of a picture's size and orientation (before any pixel is decoded) | open (new, forward to MetalUI) | 🔄 open at MetalUI. `DecodedImage` reports size and orientation only after it decodes the whole picture, but `ImageLimits` must refuse an oversize one first; MetalCreator keeps a small `ImageHeader` reader (PNG IHDR and `eXIf`, JPEG SOF and APP1) for that. Needed: a public `ImageInfo(data:)` (format, stored size, orientation, no pixel work) |

## Reported 2026-10-07 (C7)

1. **Scroll wheel / trackpad scroll on an element.** Viewport: two-finger scroll zooms toward the
   cursor (needs the cursor position in the element's local points, plus phase and momentum).
   Graph panel: two-finger scroll pans and ⌘-scroll zooms. Stopgap: +/− keys and header zoom buttons.
2. **Magnify and rotate gestures.** Pinch zooms the viewport and graph about the pinch centre.
   Stopgap: none (keys only).
3. **Middle and other buttons, and right-drag.** Viewport: middle-drag pans, right-drag orbits.
   Stopgap: primary-drag orbits, Shift-drag pans.
4. **Click and tap location.** Viewport picking and the right-click face menu need the click point
   in local coordinates to read the ID buffer pixel. Stopgap: zero-distance `DragGesture` if allowed.
5. **Cursor from content, and modifiers during a drag.** Crosshair while picking, grab hand while
   panning, and ⌥ held mid-drag to duplicate nodes.

## C7 status and provisional API names (from the MetalUI session, 2026-10-08)

**Merged (MetalUI `c62d6ba`, record §81, rulings `CI-A`…`CI-AL`).** Every provisional name below was kept. The
refinements: `.onScrollWheel`'s closure returns `Bool` (`true` claims), the scroll's local point is
`ScrollEvent.location`, `RotateGesture.Value.rotation` is clockwise-positive, the crosshair is
`PointerStyle.rectSelection`, and the located context menu is `.contextMenu { (location: Point<Pixels>?) in … }`
(`CI-R`). **The viewport has adopted it** (plan `docs/superpowers/plans/2026-10-09-viewport-input-c7.md`): items 1–5
are closed for the viewport, and gaps 4 and 5 below with them. **The graph panel has adopted it too** (plan
`docs/superpowers/plans/2026-10-09-graph-input-c7.md`): M5-e, M5-f, the canvas's share of items 1, 2 and 5 and the
dock edge's resize cursor are closed, and GI-a and GI-b below are what it found. The viewport's and the graph's keys
still wait for key scoping (M4-a, M5-b, MetalUI C9).

The provisional names, as the MetalUI session reported them on 2026-10-08 (all kept: C7's design phase probed
SwiftUI, and where SwiftUI has a spelling MetalUI took it). No C7 stopgap is left in MetalCreator; the input stopgaps
that remain are for gaps outside C7 (keys, focus, the palette's outside press), in `GraphPanelInput` and `AppInput`.

- Tap location: `SpatialTapGesture` (`.location`), `.onTapGesture(count:coordinateSpace:perform:)`.
- Pinch/rotate: `MagnifyGesture` (`.magnification`, `.startLocation`), `RotateGesture` (`.rotation`).
- Cursor: `.pointerStyle(_:)` (`.grabIdle`, `.grabActive`, `.rectSelection`, plus a crosshair).
- Scroll wheel (MetalUI-only): something like `.onScrollWheel { event in }` exposing `ScrollEvent` (deltas, phase, momentum).
- Middle/right drags (MetalUI-only): likely `DragGesture(button: .secondary / .middle)`.
- Modifiers during a drag: a `modifiers` field on `DragGesture.Value` or an `EventModifiers` read during the gesture.

MetalCreator's concrete expectations (for C7's designer): see the M4 (viewport) and M5 (graph panel) plans —
`location` in the gesture element's local coordinate space; middle-drag pans, right-drag orbits, two-finger
scroll zooms toward the cursor in the viewport and pans the graph canvas (⌘-scroll zooms it); momentum is honoured
for canvas panning and ignored for viewport zoom.

## Hit by M4 (viewport), 2026-10-08

Gap numbers 1–5 are the C7 items above. New gaps are labelled M4-a… (M5 uses M5-a…), so later milestones never collide with the C7 numbering. Each stopgap lives behind one type of ours, named in its entry, so the swap stays local.

- ✅ **Closed by C7 (viewport, 2026-10-09):** the drags read `DragGesture.Value.modifiers` and
   `ViewportModifierTracker` is deleted; the closed hand (`.grabActive`) shows while a drag orbits or pans, and the
   crosshair (`.rectSelection`) while picking.
   **Gap 5 (C7 item 5, now concrete): modifiers during a drag.** Shift-drag pans and ⌥-drag zooms the viewport (spec §9).
   `DragGesture.Value` has no modifiers. Stopgap: `ViewportModifierTracker` follows `.modifiersChanged` through a
   chained `Window.onInput`. Wanted: `DragGesture.Value.modifiers` (the modifiers held at each change, including at the press).
   Known limit: `held` modifiers can go stale if Shift is released while the window is inactive.
- ✅ **Closed by C7 (viewport, 2026-10-09):** the face menu uses the located `.contextMenu` and picks at the right
   press (`ViewportModel.contextMenuItems(at:)`); clicks are a `SpatialTapGesture` (`ViewportModel.click(at:)`). A
   right-drag (`DragGesture(button: .secondary)`) orbits, and a right press that moves less than 5 points opens the
   menu on its release.
   **Gap 4 (C7 item 4, now concrete): context-menu location.** The face menu must know which face was under the
   secondary press: the press point in the element's local points. Stopgap: the last `onContinuousHover` point
   (`ViewportModel.contextMenuItems()` reads the hovered pick). The model re-picks at the last pointer point whenever
   the camera moves under a still pointer (drag release, key zoom, projection switch, end of a view-cube or Look At
   animation) or the scene is replaced (`refreshHover()`). It's still wrong if the pointer moved without a hover
   event since. Wanted: the opening location passed to the `.contextMenu` builder, or `SpatialTapGesture` for secondary clicks.
- ✅ **Closed by C7 (viewport, 2026-10-09), with items 2 and 3:** `.onScrollWheel` zooms toward `ScrollEvent.location`
   (a run of wheel steps settles the camera once the wheel has been still for 0.15 s, a trackpad scroll at its end,
   momentum ignored), `MagnifyGesture` zooms
   about `startLocation`, and middle-drag pans. ⌥-drag and the +/− keys stay. The viewport has no rotate gesture
   (spec §6.3 gives it none).
   **Gap 1 (C7 item 1): scroll-wheel zoom toward the cursor.** Not available. Stopgaps: ⌥-drag and the +/− keys
   (`ViewportInputMap`). The C7 shape the viewport expects is in the "C7 status" section above.
- **M4-a (new): an element's size, and keyboard focus.**
   - No `GeometryReader` or `onGeometryChange`: the viewport learns its size from `MetalDrawContext.pixelSize / scaleFactor`
     inside its draw, into untracked state (`ViewportModel.viewSize`). Input before the first draw sees a zero size and is ignored.
     Symptom: handle labels are missing on the first build of a document with a saved camera, and misplaced during a live resize, until the next rebuild (handle labels are laid out from the recorded size).
     Wanted: `onGeometryChange(for:of:action:)` or a size in the draw's `value:` round trip.
     M7 extends this stopgap for the graph canvas's culling: a recorded size that differs from the last bumps the
     observed `ViewportModel.viewSizeChanges` one task after the draw (`observedViewSize`, which
     `AppModel.panelPlacement` reads), so a resize rebuilds the canvas at the new size, one frame late. It goes with
     the stopgap.
     **Fixed by MetalUI C9 (`onGeometryChange`, KF-J) and adopted** (plan `2026-10-12-adopt-c15`, 2026-10-12): `ViewportView`
     reports its size from `onGeometryChange` into the tracked `ViewportModel.viewSize` (`recordViewSize(_:)`), so the
     draw-time record, `viewSizeChanges`, `sizeChangeTask` and `observedViewSize` are gone. The labels, the first framing
     and a resize follow the layout, in a `TestWindow` too (`AppWindowTests`). The report carries the model's identity, so
     New and Open (a fresh `ViewportModel` under the same view) are told the size again. The graph panel's placement
     (gap EP-a) is measured the same way. The focus half of this entry (below) is C9's and still only partly adopted: see
     M5-b and M5-g.
   - A click doesn't focus a `.focusable()` element (divergence 94), so the viewport's F, + and − keys are bound window-wide
     (`ViewportKeyBindings`). The app shell will collide with text fields. Wanted: focus-on-click for a focusable
     surface, or a key context an element contributes while hovered.
- **M4-b (new): builder and redraw ergonomics.**
   - A helper returning `some Element`, called inside a `for` in a container's builder, fails with "underlying type for opaque
     result type could not be inferred" (the same chain written inline compiles). The viewport writes its label
     loops inline.
   - A `.continuous` `MetalView` redraws its surface every frame, but the element tree isn't rebuilt, so overlay labels
     can't follow a camera animation. The triad's axis names and the handle values are hidden while one runs. (The
     view cube's face names no longer depend on this: they're painted on the cube in its Metal pass.) Wanted:
     `TimelineView(.animation)`, or a per-frame rebuild hook for elements above a continuous surface.

## Reported 2026-10-08 (M5 graph panel)

These are labelled M5-a… so they don't clash with the C7 items 1–5 or M4's M4-a… entries in the section above.

- **M5-a. `Slider` has no editing-ended callback** (SwiftUI's `Slider(value:in:onEditingChanged:)`). The inspector
  coalesces a slider drag into one undo step and needs to know when the drag ends. Stopgap: steps share a coalescing
  key; it ends on the next selection change, canvas press, other edit, undo or redo
  (`EditorModel.setInput(_:to:continuous:)`). Two drags of the same slider with nothing between them merge.
  **Fixed by MetalUI C10 lane 1** (2155f1e; `Slider(value:in:onEditingChanged:)`, rulings `LK-B`, `LK-Q`, `LK-U`: `true`
  before the press's write, `false` after the release's, always paired) and adopted (Adopt C10 plan Task 1): both
  inspector sliders (a node's input and a document parameter) call `EditorModel.sliderEditingChanged(_:)`, which closes
  the undo run, so a drag is one undo step and two drags with nothing between them are two. The selection, canvas-press
  and undo ends stay as a safety net.
- **M5-b. No focus-scoped or hover-scoped key binding.** Tab focus traversal claims Tab before `Window.onInput`
  whenever anything focusable is on screen (the inspector always is). The window keymap runs earlier, and a binding
  whose `onAction` returns false falls through to the later stages, traversal included, so the graph binds Tab
  there: `GraphPanelInput.keymap` maps `tab` to `GraphTab`, and `handleAction` opens the add-node palette only while
  the panel is visible, the pointer is over the canvas and no palette is open (spec §6.2). Otherwise Tab moves focus.
  While hidden, `GraphShowButton` carries `.keyboardShortcut(.tab, modifiers: [])` (the shortcut stage also precedes
  traversal). What is missing: the binding is window-wide and decides by reading the model's hover state, so with
  the pointer over the canvas Tab opens the palette even from a focused inspector field instead of moving focus.
  Wanted: a key context an element contributes while hovered (as M4-a asks for the viewport), or `onKeyPress` on a
  focus region.
  **Fixed by MetalUI C9** (`feat/key-focus`, KF-B to KF-E: `onKeyPress`, `hoverKeyRegion`; a key region's keys follow the
  pointer while nothing is focused, and a focused field keeps every key) and **adopted for the graph canvas** (Comments typing
  plan Task 4): `CanvasSurface` is a key region and its one `onKeyPress` runs the graph's keys, Tab included (it no longer opens
  the palette from a focused field; `GraphTab` and the keymap's `tab` binding are gone). The viewport's F, + and − keep
  `AppInput`'s pointer veto until the viewport adopts C9 (M4-a).
- **M5-c. No materials or blur** (`.background(.ultraThinMaterial)`, `.blur(radius:)`). Glass panels over the viewport
  need a backdrop blur (spec §6.1). Stopgap: `#21222c` at 86% opacity with the hairline (`GlassPanel`).
  **Fixed by MetalUI C10 lane 3** (2155f1e; `.blur(radius:)` and `Material`, rulings `LK-K`, `LK-L`), **adopted by
  decision, nothing swapped** (Adopt C10 plan Task 5): MetalUI's materials are a flat grey tint fitted to SwiftUI's
  (its divergences 166, 167) with no backdrop blur, and `.blur(radius:)` blurs a view's own pixels, so neither gives
  the spec's glass; and a material's grey is the same in every theme, where `GlassPanel` fills with the theme's `glass`
  role (Dracula's `#21222c` at 86%, editable in the theme editor). `GlassPanel` keeps the theme's tint and the hairline;
  `GlassFillTests` pinned it. What spec §6.1 wants, a blur of what is behind the panel, was gap C10-a: fixed by MetalUI C21 and
  adopted, so the glass is now a material under the theme's tint (the C10-a entry).
- **M5-d. No gradients.** The window background is a `#3a3d4e` → `#191a21` vertical gradient (spec §6.6). Stopgap:
  solid `#191a21`.
  **Fixed by MetalUI C10 lane 3** (2155f1e; `LinearGradient`, ruling `LK-J`) and adopted (Adopt C10 plan Task 4): the
  preview window's background is `WindowBackground`, the theme's `backgroundTop` to `backgroundBottom` top to bottom.
  The app's viewport already paints the same gradient on the GPU (`ViewportRenderer`), so the app shell has no
  background to swap.
- ✅ **Closed by C7 (graph panel, 2026-10-09):** the canvas's one `DragGesture(minimumDistance: 0)` reads
  `DragGesture.Value.modifiers` (a click those at the press, a drag those when it starts), `GraphPanelInput` no
  longer tracks `.modifiersChanged`, and `dragValueModifiers(_:)` and `spatialTapGesture()` are gone. A click's
  location is still that drag's, not a `SpatialTapGesture`'s, because a tap's value has no modifiers (GI-a).
  **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete). Shift-click and ⇧/⌥-drag on the
  canvas need the modifiers at the press, in the gesture's value. Former stopgap (removed by C7):
  `GraphPanelInput.dragValueModifiers(_:)` returned the set `GraphPanelInput.handle(_:)` tracked from `.modifiersChanged`
  until C7's `DragGesture.Value.modifiers` replaced its body. A click's location was
  `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
- ✅ **Closed by C7 (graph panel, 2026-10-09):** `.onScrollWheel` pans the canvas by the scroll's delta (momentum
  honoured) and ⌘-scroll zooms about `ScrollEvent.location` (`EditorModel.scrolled(by:at:modifiers:phase:)`; a
  trackpad scroll zooms or pans as it began, and a zoom's glide is ignored); `MagnifyGesture` zooms about
  `startLocation` (`EditorModel.pinchChanged`). The +/− keys and the header's zoom buttons stay; the keys' hover veto
  in `AppInput` stays until keys are scoped (M4-a, M5-b).
  **M5-f. Canvas scroll and pinch** (adds to items 1 and 2). Two-finger scroll should pan the graph canvas and
  ⌘-scroll or pinch should zoom about the pointer (the `location` in the canvas's local points). Former stopgap (C7
  replaced the pan; the +/− keys and the header buttons stay): a drag on empty canvas panned, and the keys and buttons
  zoomed about the pointer (`EditorModel.zoom(in:)`). With M4's viewport in the same window, M4's window-wide keymap
  takes `=`/`+`/`-` before `onInput` (gap M4-a), so M6 needed a key context.
- **M5-g. A press elsewhere never clears text focus** (focus-by-click is deliberately not MetalUI policy,
  `Window.focus(_:)` docs). After editing an inspector field, the field keeps Delete, ⌘C/⌘V/⌘Z and Space while the
  user clicks nodes, so the graph's keys stop working with no visible cause. Stopgap: the canvas gesture calls
  `GraphPanelInput.releaseTextFocus` (`window.focus(nil)`) at the start of each press. A SwiftUI-like rule (a press on
  non-focusable content resigns the field), or a `.focusable(false)`-style "clears focus" modifier, would fix it.
  **Fixed by MetalUI C9** as an opt-in, not a default (KF-G keeps SwiftUI's rule that a press elsewhere resigns nothing):
  a primary press inside a `hoverKeyRegion` clears a field's focus, unless it lands on a text field. **Adopted for the
  graph canvas** (Comments typing plan Task 4): the canvas surface is a key region, `GraphPanelInput.releaseTextFocus` is
  gone, and a canvas press ends a typed value and a canvas edit. A press outside every region resigned nothing (gap CT-a),
  so viewport presses called `AppModel.releaseTextFocus` until **MetalUI C24** (entry CT-a): the app's root now resigns on
  every primary press and that hook is gone.
- **M5-h. A focused single-line field claims ↑/↓** (mac: caret to start/end, `TextEditing.key`) before the raw key
  bubble and `onInput`. The add-node palette needs ↑/↓ to move its highlight while its search field is focused.
  Stopgap: `GraphPanelInput.keymap` binds `up`/`down` to `PaletteMove`, and `handleAction` runs it only while the
  palette is open (the keymap stage precedes field keys). SwiftUI's `onKeyPress` on the field would fix it.
  **Fixed by MetalUI C9** (`onKeyPress(keys: [.upArrow, .downArrow])` on the field runs before the field's own keys, KF-C
  item 4). **Not adopted** by the Comments typing plan, which uses no single-line field's arrows: the palette's `PaletteMove`
  keymap action stays until the palette moves onto it.
- **M5-i. No keyframe animation.** The refused-wire "brief shake" (spec §6.2) wants a back-and-forth keyframe
  animation. Stopgap: the node's offset jumps 6 pt and springs back (`.animation(.spring(duration:bounce:), value:)`).
  **Fixed by MetalUI C10 lane 2** (2155f1e; `keyframeAnimator`, `KeyframeTimeline`, rulings `LK-H`, `LK-I`) and adopted
  (Adopt C10 plan Task 3): `NodeView` runs `RefusalShake`'s keyframes (6 pt out in 0.05 s, 6 pt back across in 0.1 s,
  home in 0.05 s) each time `EditorModel.shakeCount(of:)` goes up. `isShaking` and its 300 ms timer are gone.
- **M5-j. No `ProgressView` or indeterminate spinner.** The node status badge shows a spinner while the node evaluates
  (spec §6.2). MetalUI has no activity indicator. Stopgap: a static `◌` glyph (`StatusBadge.text(for:)`). Wanted:
  `ProgressView()` (indeterminate, small control size) or a `TimelineView(.animation)` to rotate a glyph.
  **Fixed by MetalUI C10 lane 2** (2155f1e; `ProgressView`, rulings `LK-E`, `LK-F`) and adopted (Adopt C10 plan Task 2):
  `StatusBadgeView` draws `ProgressView().controlSize(.small)` while `StatusBadge.isBusy`; `StatusBadge.text` is empty
  for `.evaluating`.

## Hit by M6 (app shell), 2026-10-09

Labelled M6-a… so they don't clash with the C7 items 1–5, M4-a… or M5-a…

- ✅ **Fixed in MetalUI 70e9389 (PR #61, rulings AS-D), adopted:** `WindowChromeSync` sets `Window.title`,
  `Window.isDocumentEdited` and `Window.representedURL` from the document (`AppModel.windowChrome`), so the title bar
  reads the file's name, the close button shows the edited dot and the proxy icon names the file. The top bar keeps
  its name and "— Edited". Under the hidden title bar (M6-c, adopted) AppKit draws neither the title nor the proxy icon; the Window menu still names the document.
  **M6-a. No window title API.** The title is fixed by `App.openWindow(title:…)`. `PlatformWindow.title` is settable,
  but `Window` doesn't expose it, and there's no represented file or edited marker (AppKit's `representedURL` and
  `isDocumentEdited`). The app wants "bracket.mcgraph — Edited" in the title bar. Stopgap: the glass top bar shows the
  name and "— Edited"; the native title stays "MetalCreator". Wanted: a settable `Window.title` and an edited marker,
  or SwiftUI's `.navigationTitle` / `.navigationDocument(_:)`.
- ✅ **Fixed in MetalUI 70e9389 (PR #61, rulings AS-B, AS-C, AS-K), adopted:** `Window.onCloseRequest` is
  `AppModel.closeRequested()`, which answers `.later` with unsaved changes and shows Save / Don't Save / Cancel;
  `AppModel.answerSaveChanges(_:)` runs the save flow and calls `Window.replyToCloseRequest`. The app sets no
  `onTerminateRequest`: ⌘Q asks the one window's handler, so close and quit share one question and one reply.
  **M6-b. No close or quit interception.** Closing the window, or ⌘Q, ends the app at once, so it can't ask whether
  to save (AppKit: `windowShouldClose(_:)`, `applicationShouldTerminate(_:)`; SwiftUI document apps get it from
  `DocumentGroup`). Stopgap: none. New and Open ask before discarding unsaved changes; close and quit don't. Wanted: a
  window-close veto and an app terminate hook that can show an alert first.
- ✅ **Fixed in MetalUI 70e9389 (PR #61, rulings AS-E, AS-F, AS-J) and C22 (930db4a), adopted (plan `2026-10-12-adopt-c22`), pending
  human check AS-5:** `MetalCreatorApp` opens the window with `windowStyle: AppLayout.windowStyle` (`.hiddenTitleBar`), so the glass top
  bar is drawn under the window buttons. `TopBar` pads its content by `AppLayout.topBarClearance(titleBarInsets:)` (`AppRoot` reads
  `@Environment(\.titleBarInsets)`; zero in full screen and in a standard window; `TitleBarClearanceWindowTests` sets the insets as
  AppKit reports them). The window is dragged by the top bar (gap C8-a). AS-5 runs it live.
  **M6-c. No full-size content view.** Spec §6.1 draws the glass top bar under the traffic lights (AppKit
  `.fullSizeContentView` with a transparent title bar; SwiftUI `.windowStyle(.hiddenTitleBar)`). Stopgap: the top bar
  sits below the standard title bar.
- ✅ **Fixed in MetalUI 70e9389 (PR #61, rulings AS-G, AS-M, AS-Q), adopted:** `app.onOpenURL` is
  `AppModel.openRequested(_:)` (set before `app.run()`), and the path argument goes through `app.open(_:)`. An
  edited document asks the New and Open… question first.
  **M6-d. No open-document events.** Finder double-click, `open -a`, dropping a file on the Dock icon and Open Recent
  all need the app to receive file URLs (AppKit `application(_:open:)`, SwiftUI `.onOpenURL`). This matters once the
  app is packaged. Stopgap: a path argument (`swift run MetalCreatorApp bracket.mcgraph`). Queued in MetalUI as C8
  (app shell). The packaged app declares `.mcgraph` with no `NSDocumentClass`, so a Finder double-click may show AppKit's
  "cannot open files in this format" alert rather than nothing (human check P2 records which).
- **M6-e. No public test window or headless platform.** `Window`'s initializer is internal and `FakePlatformWindow`
  lives in MetalUI's own test target (C7's `CI-N` keeps it there), so a client can't dispatch keys and clicks through
  a real `Window` in its tests. M6's riskiest routing (the `Panel` / `!Panel` key contexts on the focus chain, the
  canvas hover veto, menu commands running before `onInput`, button shortcuts ahead of the palette) is pinned only
  as mapping (`AppInputTests`) plus human checks M6-4, M6-5 and M6-11. Stopgap: none. Wanted: a public headless
  `Window` (or `FakePlatformWindow` in a test-support product) with `simulateInput` and a rendered frame.
  **Fixed by MetalUI item 8** (master 280d706, PR #65: the `MetalUITesting` product) **and adopted** (plan
  `2026-10-12-adopt-test-harness`): `CreatorAppTests` depends on `MetalUITesting`, and `AppWindow` (test support) opens
  `AppWindowRoot` over `FakeKernel` in a `TestWindow` with the app's own `AppCommands` and `AppInput`, so clicks and
  keys go through MetalUI's real routing (`AppWindowTests`). The observable key routing is pinned by those window tests; the canvas hover veto and the `Panel` key context stay pinned only by mapping tests (`AppInputTests`). MetalCreator never wrote a `Platform` or `PlatformWindow`
  fake (its stopgap was no test at all, the mapping tests and the human checks), so there was nothing to replace or
  delete; `renderFrame` stays for the render tests that read one cold frame.
  **A limit of the harness, not a MetalUI gap, and now no limit for this app:** `MetalUITesting` records a
  `GPUSurface`/`MetalView` draw and does not run it (`../MetalUI/docs/testing.md`, "What it cannot do", ruled deferral
  `HT-Q`: there is no GPU context to hand the closure), so an app that learned its window's size from a draw had none in a
  `TestWindow`. **Adopted (decision D1, plan `2026-10-12-adopt-c15`):** the viewport and the graph panel report their size
  and frame from `onGeometryChange` (KF-J), which does run headless, so the property form of `AppModel.panelPlacement`
  is the measured panel (`PanelPlacementTests.theEditorIsToldWhereItsCanvasIs`, both docks, agreeing with `AppLayout`'s
  numbers), `canvasFrameInWindow` works (a library drop, the culling, the visible centre), and `AppWindow.canvasFrame` is
  that measured frame rather than a computation from `AppLayout`.
  **The routes this entry named are pinned through the window** (Task 5 of the plan): F, + and − go to the viewport over the
  viewport and to the graph over its canvas, and a focused inspector field keeps them until a viewport press gives them
  back (`ViewportKeyRoutingWindowTests`, M6-4); the Edit menu is titled by the step and runs Undo and Redo, ⌘Z and ⇧⌘Z
  act over the canvas and over the viewport, and ⌘C, ⌘V and ⌘D copy, paste and duplicate over the canvas only
  (`EditMenuRoutingWindowTests`, M6-5); Space over the canvas opens the palette with its search field focused, "f+" is
  typed into it and Return adds the node (`PaletteKeyRoutingWindowTests`, EP-2). The canvas hover veto and the
  `Panel` key context in `AppInput` are not what these tests depend on: with either removed they still pass, because C9's
  key region and a focused field claim the keys first. **Not driven yet** (adopted, untested): the sketch toolbar's button
  shortcuts ahead of the palette (M6-11), the window shell (close veto, title, edited dot: group AS), the viewport's
  gesture glue (group V) and the inspector box's own focus-loss commit (CM-7).
- **M6-f. No colour picker.** The Themes milestone after M6 (roadmap) edits a custom theme's colours role by role,
  which wants SwiftUI's `ColorPicker(_:selection:supportsOpacity:)`: a colour well that opens the system colour panel
  (AppKit `NSColorWell`/`NSColorPanel`), with opacity. MetalUI has none. M6 doesn't need it: its three built-in themes
  are read-only and chosen from View ▸ Theme. Stopgap, if the Themes milestone comes first: a hex `TextField` per role,
  refused plainly when it isn't a colour. Wanted: `ColorPicker` over MetalUI's `Color`.
**Fixed by MetalUI C10
  lane 1** (2155f1e; `ColorPicker(_:selection:supportsOpacity:)` and its drawn panel, rulings `LK-C`, `LK-D`, `LK-P`)
  and adopted by the Themes plan's last task: each role's row in the theme editor is a `ColorPicker`, opacity only for
  the glass and the edges. MetalUI draws its own panel on macOS too (its divergence 165: SwiftUI opens `NSColorPanel`).
- **M4-a and M5-b, used again by M6.** The viewport's F, + and − carry the `!Panel` key context, and the graph panel
  and the inspector contribute `Panel` from a MetalUI `Stack` wrapper, so a focused field types them. With nothing
  focused they are window-wide. Over the graph canvas `AppInput.handleAction` declines + and − by reading the
  canvas's hover state, so the graph's own + and − zoom it (as M5-b does for Tab); F has no graph binding and still
  frames the viewport. A key context contributed while an element
  is hovered, or `onKeyPress` on a region, would replace both vetoes. C7 (`feat/input-apis`) doesn't include it.
- ✅ **Closed by C7 (2026-10-09):** `PanelResizeHandle` shows `.columnResize` on the left dock's edge and
  `.rowResize` on the bottom dock's (`PanelResizeHandle.pointerStyle(alongWidth:)`).
  **Cursor for the dock's resize edge** (adds to C7 item 5). The graph panel's inner edge is a drag handle and should
  show a column or row resize cursor. C7's `PointerStyle` has `.columnResize` and `.rowResize` (decision `CI-H`);
  MetalCreator adopted them when C7 merged.

## Hit by the viewport's C7 adoption, 2026-10-09

Labelled VI-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a… and PERF-a… entries.

- **VI-a. A gesture dropped without an end tells its owner nothing.** MetalUI drops a stale button arena or pinch
  arena silently when the next press of that button, or the next pinch, arrives (`CI-AB`: no `onEnded`), and the
  primary arena's re-formation drops a drag the same way. SwiftUI resets per-gesture state on cancellation through
  `@GestureState` / `updating(_:body:)`, which MetalUI doesn't offer (`IX-B`). The viewport holds per-gesture state
  in its model: the drag's mode (and with it the closed-hand cursor) and the camera a pinch began from. Stopgap:
  `ViewportModel` ends a drag, where it was, when a value of the same button arrives from another press, or a
  primary drag value or a click arrives while another button's drag is under way (MetalUI forms the primary arena on
  every primary press, `CI-F` item 3); and a pinch when one begins at another centre
  (`aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain`, `aPrimaryDragAfterALostMiddleReleaseStillOrbits`,
  `aClickAfterALostDragEndsItAndHoversAgain`, `aClickAfterALostDragBringsBackTheArrow`,
  `aPinchThatLostItsEndDoesntPullTheNextOneBack`). What is left: nothing for primary input. A lost right or middle
  release leaves that drag, its closed hand and a still hover until the next primary press or click, or the next
  drag of the same button; until then a drag of the other of the two is ignored, as MetalUI ignores its press
  (`CI-AA` item 4). A trackpad scroll whose `.ended`/`.cancelled` never arrives (the window resigns mid-scroll) leaves
  the camera unsettled into the document and the hover un-picked until a later scroll ends; and a pinch that lost its
  end followed by one at the same centre reuses the stale start camera. Wanted: an `onEnded` (or a separate cancellation callback) for a gesture its arena drops, or
  `@GestureState`.
  **Fixed by MetalUI C16** (master a720fba, PR #67, rulings `IF-E`, `IF-F`, `IF-H`: `onCancelled` on `DragGesture`,
  `MagnifyGesture` and `RotateGesture`, once and only for a gesture that had reported; a synthesized `.cancelled` scroll
  on key loss) **and adopted** (plan `2026-10-12-adopt-c16`): `ViewportView`'s button drags call `ViewportModel.dragCancelled(button:)`
  (the drag ends where it was: mode, closed hand, handle edit and settling included) and both pinches call `pinchEnded()`,
  so the viewport's and the canvas's lost-pinch guesses (a pinch at another centre; a canvas moved since the last change,
  `CanvasPinch.applied`) are gone; the canvas's press, middle pan, library-row drag and the panel's resize edge end
  through `EditorModel.pointerCancelled()` (as Esc ends a drag, and never a click), `middleCancelled()`,
  `cancelLibraryDrag()` and `AppModel.endPanelResize()`. A lost right or middle release now ends at the next plain
  move, and a scroll or pinch the window cut short ends on its own (`ViewportCancelWindowTests`,
  `CanvasCancelWindowTests`, `PointerCancelTests`, `ScrollLatchWindowTests`). **The last piece was VI-b** (a primary drag
  whose release was lost and whose next press lands on the same element): MetalUI C26 fixed it and its three stopgaps are gone
  (entry VI-b below). Human checks C16-4 to C16-7, and C26-1.

## Hit by the graph panel's C7 adoption, 2026-10-09

Labelled GI-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a…, VI-a… and PERF-a… entries.

- **GI-a. A tap's value has no modifiers.** Shift-click extends the graph's selection (spec §6.2), so a canvas click
  must know whether ⇧ was held at the press. `SpatialTapGesture.Value` carries only `location` (SwiftUI's carries no
  more; a SwiftUI app reads `NSEvent.modifierFlags` or `onModifierKeysChanged(mask:initial:_:)`, which C7 deferred,
  `CI-A`). So the canvas can't be written the viewport's way (a `SpatialTapGesture` inside a nonzero-distance drag):
  it keeps one `DragGesture(minimumDistance: 0)` for clicks and drags, whose values carry the location and the
  modifiers (`CI-G`), and `EditorModel` tells a click from a drag by its own 3-point threshold, beside MetalUI's
  5-point tap slop. Every value is C7's, so nothing here is undone later, but the canvas can't recognise a double
  click. Wanted: `modifiers` on `SpatialTapGesture.Value` (MetalUI-only, as `DragGesture.Value.modifiers` is,
  divergence 140), or `onModifierKeysChanged`.
  **Fixed by MetalUI C16** (master a720fba, `IF-B`: `SpatialTapGesture.Value.modifiers`, the last press's) **and adopted**
  (plan `2026-10-12-adopt-c16`): `ViewportView`'s `SpatialTapGesture` passes `ViewportModifiers($0.modifiers)` to
  `ViewportModel.click(at:modifiers:)`, so a ⌘-click in the sketch editor suppresses inference at its press
  (`ViewportModifiersWindowTests.aCommandClickReachesTheToolWithCommandAndAPlainOneWithout`). **The graph canvas needs
  nothing:** its one `DragGesture(minimumDistance: 0)` already carries the modifiers of the press and of each change, and
  it has to stay a drag, because a press becomes a box, a wire or a move, which a tap beside a drag can't follow; its
  3-point click threshold stays beside MetalUI's 5-point tap slop. The double-click half is S5-b.
- **GI-b. No wheel latching, met by a canvas pan's glide** (MetalUI `CI-AD`, stated, not built). A flick that pans
  the graph canvas glides on through momentum events, and MetalUI sends each to whatever is under the pointer at that
  event. If the pointer drifts off the canvas mid-glide, the canvas stops and the rest of the glide scrolls the node
  library's list or the inspector, if the pointer is over one (the viewport ignores momentum, and the graph panel's
  chrome claims every scroll). Stopgap: none. Wanted: `CI-AD`'s latch (a scroll gesture's events, momentum included,
  go to the element under its `.began`). Human check GI-1 records what happens.
  **Fixed by MetalUI C16** (master a720fba, `IF-G`, `IF-H`: a scroll latches to the element under its `.began`,
  momentum included; a synthesized `.cancelled` reaches the latched handlers on key loss) **and adopted** (plan
  `2026-10-12-adopt-c16`): nothing to remove, since this entry's stopgap was none. The canvas's pan glide stays on the canvas when the
  pointer drifts onto the viewport, the library or the inspector, a viewport zoom's glide stays off the canvas, and key loss
  mid-glide leaves no stuck "ignore the zoom's glide" state (`ScrollLatchWindowTests`). `EditorModel.scrolled`'s
  `.changed`-with-no-`.began` fallback stays for a latch whose canvas was rebuilt mid-scroll
  (`aScrollThatBeganElsewhereIsTakenUpAsItIsNow`). Human check C16-1.
- **VI-a, met again.** The canvas's pinch keeps its start in `EditorModel` too, so a pinch that changes at another
  centre while one is under way, or finds the canvas moved since that one's last change, ends it first
  (`aPinchThatLostItsEndDoesntPullTheNextOneBack`, `aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince`); a lost
  pinch end followed by a pinch at the same centre, with nothing moving the canvas between, zooms from the lost
  pinch's start. A canvas press that lost its release was dropped by `EditorModel.ensurePress`, its
  modifiers with it, until MetalUI C26; now MetalUI cancels it at the next press (`pointerCancelled()`), its modifiers
  with it (`aCancelledPressTakesItsModifiersWithIt`).
  **Adopted with VI-a** (plan `2026-10-12-adopt-c16`): the canvas's pinch ends through `onCancelled`, and the two guesses and
  their tests are replaced by `aCancelledPinchDoesntPullTheNextOneBack`; `ensurePress`'s drop of a press with another
  start stayed for VI-b and went with it (plan `2026-10-12-adopt-c26`).

## Found by the C16 adoption, 2026-10-12

Labelled VI-b so it stays beside VI-a.

- **VI-b. A press that continues a gesture arena fails a drag that had reported, without `onCancelled`.** MetalUI treats
  a primary press on the element the live arena belongs to as the second press of a tap sequence (`Window.dispatchGestures`
  passes `continuing: true`; `GestureArena.press(at:clickCount:continuing:modifiers:)`), and fails every undecided leaf that
  is not a tap, a drag among them, through `fail(_:)` and not through `cancel()`. A drag that had reported (the viewport's
  orbit, a handle edit, the canvas's move, wire or box) and whose release was lost (Mission Control or a native menu took
  it; C16 cancels a button arena on the next `.mouseMoved`, `IF-F` item 3, but not the primary arena) is therefore dropped
  by the next primary press on the same element with neither `onEnded` nor the `onCancelled` C16 added for this. A press on
  another element does abandon and cancel
  (`ViewportCancelWindowTests.aPrimaryPressOnAnotherElementThatReplacesALostDragEndsIt`); the same element did not until C26
  (its pin is now `aPrimaryPressOnTheSameElementCancelsTheLostDragAndTheNewDragStartsFresh`). Stopgap, kept from VI-a and removed by the C26 adoption:
  `ViewportModel.beginDragIfNeeded` ends a primary drag, where it was, when a primary value arrives from another press, and
  `click(at:)` ends any drag under way; `EditorModel.ensurePress` drops a canvas press whose start differs. Until then the
  drag's mode, closed hand and a handle edit's end linger. Wanted: `GestureArena.press(… continuing: true)` runs the leaves
  it fails through the same `cancel()` as `abandon()` (a leaf that reported owes its `onCancelled`), or the primary arena
  is cancelled on a plain `.mouseMoved` as the button arenas are. Done by the C26 adoption (below): the pin test was inverted and renamed
  `aPrimaryPressOnTheSameElementCancelsTheLostDragAndTheNewDragStartsFresh`, the matching `PressModifierTests` pin is now
  `aCancelledPressTakesItsModifiersWithIt`, and the stopgaps are removed. Sent to the MetalUI session with this entry; queued there as C26, after C22 (both edit
  the gesture arena), leaning to the first fix.
  **Fixed by MetalUI C26** (master ff8a1ea4, PR #72, rulings `GC-B` to `GC-G`, record 100; no API change): a primary press that
  finds the arena still pressing is a lost release, so that arena is abandoned through `cancel()` (a drag that had reported gets
  `onCancelled` once), a fresh arena forms for the new press (its minimum distance included) and the late release cancels
  nothing again; `press(… continuing: true)` also cancels a reported drag it fails. Real double clicks are unchanged.
  **Adopted** (plan `2026-10-12-adopt-c26`): window tests drive the lost release through the app's real window and show the
  viewport's orbit (closed hand and settling), a handle edit's end (`.ended` once, one undo step) and the canvas's node move and
  box ending at the press itself, before any value of the new press arrives
  (`ContinuingPressCancelWindowTests`, `ViewportCancelWindowTests.aPrimaryPressOnTheSameElementCancelsTheLostDragAndTheNewDragStartsFresh`).
  The pin tests were inverted (`PressModifierTests.aCancelledPressTakesItsModifiersWithIt`) and the stopgaps removed:
  `ViewportModel.beginDragIfNeeded`'s same-button branch, `click(at:)`'s ending of a primary drag and `EditorModel.ensurePress`'s
  drop. What stays: a primary value or a click still ends a *right or middle* drag under way (`CI-F` item 3; a held button, not a
  lost release; `aClickWhileAnotherButtonsDragIsUnderWayEndsItAndHoversAgain`). No model guard is kept for a direct model call that
  skips `onCancelled`: the only callers are `ViewportView` and `GraphPanelInput`, which go through MetalUI, and a skipped cancel
  only continues the press in progress, with nothing leaking and nothing crashing
  (`valuesOfAPrimaryDragUnderWayContinueItWhateverStartTheyCarry`,
  `aPressInProgressIsContinuedByLaterValuesWhateverStartTheyCarry`). Human checks C26-1 and C26-2.

## Found by the C26 adoption, 2026-10-12

Labelled VI-c so it stays beside VI-a and VI-b.

- **VI-c. A lost primary release is not cancelled by the pointer's next plain move.** MetalUI cancels a *button* arena (right,
  middle) at the next `.mouseMoved` (`IF-F` item 3), since AppKit sends a plain move only while no button is held, but it leaves
  the primary arena alone: C26's ruling `GC-C` built the next-press cancel only, and SwiftUI behaves the same (MetalUI's probe `L3`: it does not cancel on a bare move either). So this is parity with SwiftUI, and the request is for MetalUI to change a ruling, not to fix a bug. A primary drag
  (the viewport's orbit, a handle edit, the canvas's move, wire or box) whose release was lost therefore stays under way after the
  pointer moves freely again, until the next primary press: the viewport keeps the closed hand and a camera that has not settled
  (nothing is hover-picked meanwhile), a handle edit stays open, the canvas keeps its wire, ghosts or box.
  `ContinuingPressCancelWindowTests.aPlainMoveDoesntEndALostPrimaryDragOnlyTheNextPressDoes` pins it. Stopgap: none (ending a drag
  on a plain move in the models would work around MetalUI). If the ruling is ever revisited: cancel the primary arena on a plain
  `.mouseMoved` too, through the same `abandon()` (option (b) of C26's design), and invert the pin test. Not blocking. Not sent to the MetalUI session: MetalUI declined this by ruling GC-C, as SwiftUI behaves; accepted as a divergence, no stopgap.

## Node-drag performance, 2026-10-08

Labelled PERF-a… so they don't clash with the labels above. Measured on branch `perf/node-drag` (MetalUI `dc6528c`)
with headless harnesses that drive the real `AppRoot` (they need `@testable import MetalUI`, gap M6-e, so they
aren't checked in): a window-like frame loop (one `StateTable`, `ShapingCache`, `GlyphAtlas` and `AnimationStore`
kept across frames, 1440 × 900 at 2×) and a real `Window` over a headless `PlatformWindow`, a drag delivered as
`.mouseDown`/`.mouseDragged` events with one display-link tick each. No GPU work is included. The machine was
loaded, so timings are ±20%; the pixel counters are exact. MetalCreator's own share of a drag event is small and
was checked separately: the model step (`EditorModel` → `DocumentModel.perform(.batch([.move]))`, coalesced) costs
0.03–0.06 ms, the app's scene refresh it wakes 0.05–0.1 ms (nothing is re-evaluated, `ViewportModel.show` and
`showHandles` aren't called, the viewport's `renderKey` doesn't change, so the `MetalView` doesn't redraw;
`NodeDragTests` pins this), and building the views' inputs (wires, draw order, node shapes and rows, the inspector
page) 0.19 ms release / 0.55 ms debug for the 20-node §7.2 bracket. The window idles (0 frames in 30 ticks) before
and after a drag, and draws exactly one frame per drag event.

| Per drag event (input + build + paint) | Circle only, debug | Circle only, release | Bracket (20 nodes), debug | Bracket, release |
|---|---|---|---|---|
| Today (selection glow on the dragged node) | 631 ms | 17 ms | 915 ms | 39 ms |
| Glow modifier given a zero colour (measurement only) | 30 ms | 3.2 ms | 140 ms | 15 ms |
| Frame with nothing moving (cache hits) | 10.8 ms | 2.1 ms | 58 ms | 13 ms |

- **PERF-a. A shadow is re-rasterized and re-blurred on the CPU every frame its content moves.** `NodeView` draws
  the selected node's glow as `.shadow(color: accent.opacity(0.7), radius: 10)` over the whole node. Per SH5 every
  leaf gets its own shadow: 9 for a Circle node, 21 for an Extrude. Each goes through `Frame.shadowImage` →
  `shadowCoverage` (`silhouette` per primitive, then `BoxBlur.blur`) → `RasterCache.tint`. The coverage `RasterKey`
  holds `full` (the composed affine, translation included), the leaf primitives' absolute bounds and the clip from
  `RasterPlacement`, so moving the node by one point misses every entry, and so does panning the canvas or resizing
  the panel. Evidence, from the frame loop and `AnimationStore.rasters`:
  - The node still: 0 px blurred and 0 px rasterized per frame. The node moving 2 pt per frame: 500,904 px blurred,
    231,177 px rasterized and 9 new tinted textures per frame (Circle); 584,000–797,000 px blurred (bracket node).
  - `NodeView` alone, selected: 637 ms per frame moving against 1.8 ms still (debug); 13.7 ms against 0.43 ms
    (release). Unselected (the glow's colour is clear, so `shadowImage` returns early): 1.6–1.8 ms either way.
  - Release `sample` of the moving loop: `BoxBlur.blur` about 70% of the frame, `RasterCache.tint` about 14%.
  - The silhouettes alone cost too: radius 0 with the 0.7 colour (no blur) still takes 94 ms debug / 5.6 ms release
    per drag event for the Circle node, against 30 / 3.2 ms with a clear colour.
  - Each miss also makes new `ImageTexture` identities, so the renderer uploads 9–21 new textures per frame (not
    measured headless).
  The debug build is about 45× slower than release here, and `swift run` builds MetalUI in debug, so the user saw
  about 1.5 frames per second.
  Proposed fix: key the coverage translation-free. Split `full` into its linear part and its device-pixel
  translation, key on the linear part, the fractional translation (quantized to 1/4 px if needed) and the leaf's
  geometry relative to its own origin, rasterize unclipped (or clipped to a translation-relative rect), and crop to
  `placement.clip` after the lookup. Place the cached mask at the new integer offset. Whole-pixel moves and pans then
  hit the cache, and so does the tinted texture, so no re-upload either. Separately, `BoxBlur` and the silhouette loops
  could use unchecked buffer access or vImage (`vImageBoxConvolve_Planar8`) on Apple platforms. MetalCreator's
  selection glow is being removed on another branch, but any shadow over moving content hits this.
- **PERF-b. Every observed change rebuilds, lays out and paints the whole window.** With nothing moving and every
  raster cached, a frame of the bracket graph (20 nodes, one selected) costs 54–58 ms debug / 12–13 ms release,
  about 0.5 ms per node in release and 2.5–3 ms in debug. A Circle-only graph costs 10.8 / 2.1 ms. Of that,
  MetalCreator's view inputs are 0.55 / 0.19 ms (above). A release `sample` puts about 43% in `requestLayout`
  (the `NodeView` subtrees alone about 33%) and the rest in paint, spread over dictionary lookups, retain/release
  and generic-metadata lookups inside MetalUI. A drag invalidates `Graph`, which every node view reads, so this
  repeats on every pointer move: 15 ms per drag event for the bracket in release, with no glow, is over a 120 Hz
  frame (8.3 ms) and close to 60 Hz. Wanted: rebuild only what changed. SwiftUI re-runs only bodies whose
  dependencies changed and reuses unchanged subtrees. For MetalUI that could be per-`Component` observation scopes
  that skip an unchanged subtree and reuse its last layout and paint, or `EquatableView`-style skipping for a
  component whose stored inputs compare equal. MetalCreator can then pass each `NodeView` value inputs, as it already
  does.
  **Measured by M7 (2026-10-09, release; the numbers are in docs/verification/performance.md, "Results" and "Why
  the open verdicts are MetalUI's to fix").** Spec §7.3's targets meet this gap twice. Orbiting the bracket changes only the
  camera, yet the window's CPU frame with the graph panel shown is several times the frame with it hidden, close to
  the 60 fps budget: every orbit step rebuilds the panel's nodes. Zooming the 50-node graph out until every node is in
  view costs about the budget, so canvas culling (which brought panning well inside the budget) can't help there;
  MetalCreator's level of detail (no rows below half zoom) takes a share off such a frame (its figure is in
  performance.md, from a probe at another load), and what is left is MetalUI's rebuild of nodes that didn't change.
  Both verdicts are not judged yet (the recorded run was not idle); a miss on an idle run waits for C14.
  **Fixed by MetalUI C13** (merged to MetalUI master ebcf3c7, PR #63, rulings PF-A…PF-N): shadow, blur, path and gradient
  rasters are cached apart from position, so a node dragged by whole device pixels reuses its texture (MetalUI measured
  20 shadowed nodes at 2×: 9 new textures a frame before, 0 after). MetalCreator adopts it with no code change; the
  node-drag and pan numbers in `docs/verification/performance.md` wait for the idle benchmark re-run.
  **Partly fixed by MetalUI C14 slice 1** (merged to MetalUI master e85cb07a, PR #82, record §104, rulings IV-A…IV-Q;
  adopted by plan `2026-10-13-adopt-c14`). Two parts landed. The layout memo is automatic (a frame whose layout inputs are
  structurally unchanged restores the layout instead of measuring again) and needed no code here. `Component.equatable()`
  is opt-in: a component that is `Equatable` skips its `content` getter while its value and its `@State` are unchanged, and
  re-evaluates when an `@Observable` property its last evaluation read changes. Only the getter is saved: the build
  recursion, prepaint and paint of the content still run (spec §2 of the MetalUI design; C14-b will retain subtrees), so
  nothing is claimed about time. A component that declares `@Environment` is refused (it evaluates every frame and is
  counted in `FrameWork.contentRefusals`; divergence 346, carried as C14-c). So the canvas's views stopped reading the
  `ThemeStore` environment: `CanvasLayers` (the one canvas view that still reads it) makes the `Palette` and passes it down
  as a value, and `NodeView`, `NodeHeaderView`, `NodeRowView`, `StatusBadgeView`, `SocketLayer`, `WireView`,
  `CommentFrameView`, `StickyView` and `CommentHandleView` are `Equatable` with every input a stored property (the
  synthesized `==` covers them; `expectEqualityCovers` fails when one gains a property its test has no variant for).
  `CanvasLayers` applies `.equatable()` to each node, wire, note and frame, and the node applies it to its header, rows,
  badge and socket layer. Counted in the app's real window (`CanvasContentSkipWindowTests`, `FrameWork.contentEvaluations`
  / `contentSkips` / `contentRefusals`): a node drag move evaluates the dragged node's view and its wires' views and
  skips every other node, wire and comment; a theme change evaluates every view (they all carry the palette) and draws the
  colours a window that started in the theme draws; a selection change evaluates the node that lost it and the one that
  gained it; a node's badge follows its evaluation state; each incremental frame draws the picture a full re-evaluation
  draws. **Not measured:** the drag bench's milliseconds. A timing re-take needs an idle Mac (the machine was loaded); it is
  owed, and nothing here is recorded as measured. **Still open:** the rest of PERF-b is the build recursion, prepaint and
  paint of a frame (C14-b: M7's orbit-with-the-panel-shown and zoom-out-50-nodes verdicts wait for it and for an idle run),
  and `CanvasLayers` itself still evaluates on every graph change because it reads the model (it builds each visible
  node's `NodeRowModel`s and every wire's geometry each time).

## Hit by editor polish (floating palette, node library), 2026-10-08

Labelled EP-a… so they don't clash with the labels above. Checked against MetalUI `c62d6ba` (C7 merged). Two
things the design expected to be gaps are not. Tooltips: `.help(_:)` (ruling `MN-P`, after the pointer rests 1 s)
shows a library type's inputs → outputs. The library's drag: each row's one `DragGesture(minimumDistance: 0,
coordinateSpace: .global)` reports window points (C7), so the release is mapped onto the canvas with the host's
placement, no row frame needed, and the model tells a click (under 10 pt) from a drag. MetalUI's drag and drop
(`draggable(_:)`, `dropDestination(for:action:isTargeted:)`, rulings `DN-*`) is deliberately not used: a draggable
that leaves the window becomes a system drag (`NSDraggingSession`, divergence 101), which the design ruled out, and
it starts on any move with no slop, ahead of a click (`DN-D`).

- **EP-a. No element frame in window coordinates, no hover coordinate space, and no window size** (adds to M4-a).
  The add-node palette floats over the window with its top-left corner at the pointer and flips at the window's right
  and bottom edges, so it needs the pointer in window points and the window's size; a click on a library type adds it
  at the visible canvas's centre, so it needs the canvas's size. Gesture values can be in window points
  (`DragGesture(coordinateSpace: .global)`, `SpatialTapGesture`, C7), which the library's drag uses, but the palette
  opens from the hover pointer: `HoverPhase.active` is element-local only, nothing reports an element's frame
  (no `onGeometryChange`), and nothing reports the window's size. Stopgap: the panel's insides
  are computed (`GraphPanelLayout`; the header and the library are framed to it), and the host reports the panel's
  frame and the window's size through `EditorModel.placement`: the app from `AppLayout.graphPanelFrame` and the
  viewport's recorded draw size (the viewport fills the window, M4-a), `GraphPanelPreview` from a window kept at one
  size (`PreviewLayout`). Known limits: before the viewport's first draw the palette opens at the canvas-local point
  unflipped; resizing the window while the palette is open leaves it where it opened; a refusal line under the
  canvas makes the "visible centre" half a line low. Wanted: `onGeometryChange(for:of:action:)` with a global or
  named coordinate space (SwiftUI's `.global`, `coordinateSpace(_:)`), a coordinate space for `onContinuousHover`'s
  location, and the window's size in the environment.
  **Fixed by MetalUI C15** (master 0abce86, PR #66) **and adopted** (plan `2026-10-12-adopt-c15`): `GraphPanel` reports
  `PanelPlacement(window:, panel:)` from `onGeometryChange` (`proxy.frame(in: .global)`) and `@Environment(\.windowSize)`
  into `EditorModel.panelPlacement`, so `EditorModel.placement`, `AppLayout.graphPanelFrame`, `AppModel.panelPlacement(inWindowOf:)`
  and `GraphPanelPreview`'s `PreviewLayout.placement` are gone, and the viewport's recorded draw size is not involved (gap
  M4-a). The palette opens at `EditorModel.pointerWindowLocation`, the canvas container's
  `onContinuousHover(coordinateSpace: .global)`. The known limits are gone: the palette opens correctly before any draw
  (`itOpensWithItsTopLeftCornerAtThePointerWhateverTheViewportHasDrawn`: this window never draws one), the visible centre
  reads the measured canvas, which the refusal line shortens, and a resize while it is open re-places it
  (`resizingTheWindowWhileOpenKeepsItInside`). The panel's frame is the panel's own, so it is right in any host.
  `PanelPlacement.window` is kept (a headless window pins that `\.windowSize` arrives: `theEditorIsToldWhereItsCanvasIs`),
  but nothing in `Sources` reads it now: MetalUI flips the palette itself (gap EP-b).
- **EP-b. No plain anchored overlay that dismisses on an outside press.** `.popover` is placed against its anchor
  and dismissed by an outside press or Escape (`MN-N`), but it draws its own chrome (the `.surface` panel, border and
  default shadow, a per-frame cost over moving content, PERF-a) and anchors to an element's edge, not to a point.
  The palette wants glass chrome, its top-left corner at the pointer, no shadow. Stopgap: the host draws
  `SearchPaletteOverlay` last in its root `ZStack` (in the app inside `PaletteDock`, which contributes the `Panel`
  key context so F, + and − type into the search field); a transparent backdrop with an empty `DragGesture` and a
  claiming `.onScrollWheel` keeps a press or a scroll on the palette's padding from reaching the canvas, the
  inspector or the viewport beneath; a press of any button outside is read from `Window.onInput`'s `.mouseDown`,
  `.rightMouseDown` and `.otherMouseDown` (`GraphPanelInput.handle(_:)` → `EditorModel.windowPressed(at:)`). Known
  limits: a press into a text field or onto a slider, and a right-click that opens the viewport's context menu, are
  claimed before `onInput`, so they don't close the palette (Escape, a canvas press, or any other press does); a
  pinch over the palette does nothing: the palette is the pinch's target (`CI-D`) and nothing on its chain takes a
  pinch (`PaletteDock` is drawn beside the graph panel and the viewport, not inside them), so it stays open. Wanted: a chrome-less popover style (SwiftUI's
  `.presentationBackground(.clear)` / a plain `popoverStyle`) with a point anchor (`attachmentAnchor: .point(_:)`),
  or an outside-press callback for an overlay.
  **Fixed by MetalUI C15** (master 0abce86, PR #66) **and adopted** (plan `2026-10-12-adopt-c15`). The call is
  `.anchoredOverlay(isPresented:at:in:anchor:content:)` (the summary row first spelled it with `attachmentAnchor:`, which
  is `.popover`'s): `SearchPaletteOverlay` puts `SearchPaletteView` (its own glass, no shadow) at the palette's window point
  (`in: .global`, `anchor: .topLeading`, the pointer). `EditorModel.windowPressed`, `paletteFrame`, `PalettePlacement`,
  `PaletteLayout.windowMargin`, the palette's backdrop (the empty `DragGesture`, the claiming `.onScrollWheel`) and the
  `.mouseDown`/`.rightMouseDown`/`.otherMouseDown` cases of `GraphPanelInput.handle(_:)` are gone. The known limits are
  fixed, each pinned through the window (`PaletteOverlayWindowTests`): a press into a text field closes it and the field
  gets the focus, a right-click that opens a context menu closes it and the menu opens, any outside press (primary,
  right, middle, on the canvas, the viewport) closes it, Escape closes it with its field focused and leaves the selection alone
  (`PaletteOverlayWindowTests.escapeClosesItAndLeavesTheSelectionAlone`), a press, a scroll or a pinch on it reaches nothing
  beneath, and F, + and − still type into its field. Behaviour that differs from the stopgap: MetalUI clamps with no
  margin, so a palette at the window's edge is flush with it (the stopgap kept `PaletteLayout.windowMargin`, 8 points);
  a pinch over it still does nothing and it stays open (C15 swallows presses, wheel and drops, not pinches, and the
  stopgap's note held too: GI-7).

## Hit by packaging, 2026-10-09

Labelled P-a… so they don't clash with the C7 items, M4-a…, M5-a…, M6-a… or PERF-a….

- **P-a. No list of the third-party code a MetalUI app links.** A packaged app has to carry the notices of the code
  compiled into it. MetalCreator's release binary contains MetalUI's vendored stb_image (`CStbImage`, MIT or public
  domain; `nm` finds 92 `stbi_` symbols), and other products or traits could add FreeType, HarfBuzz, SheenBidi or
  libunibreak. Which vendored code each MetalUI product links on macOS isn't written down, so
  `scripts/package-app.sh` bundles the licences of the Homebrew libraries only. Wanted: in MetalUI's
  `docs/packaging.md`, or a `THIRD-PARTY-NOTICES` file, a list per platform and trait of the vendored code each
  product links and where its licence file is. **Fixed in MetalUI 67a579e** (`THIRD-PARTY-NOTICES.md`, "Third-party
  notices" in its `docs/packaging.md`): on macOS with the default text system only stb_image is linked, and
  `scripts/package-app.sh` copies `THIRD-PARTY-NOTICES.md` and `Sources/CStbImage/LICENSE` into
  `Contents/Resources/Licenses/MetalUI/` (checked by `scripts/verify-app.sh`).
- ✅ **M6-d, now fixed (adopted, plan `2026-10-09-adopt-c8`; human checks AS-6 and AS-7).** **M6-d, now visible.** The packaged app declares `.mcgraph` (owner, exported type), so a double-click in Finder
  opens MetalCreator, but not the file: no open-document event reaches the app (human check P2).

## Hit by the node library's overlap fix, 2026-10-09

Labelled LF-a… so they don't clash with the labels above. Checked against MetalUI `67a579e`.

- ✅ **Fixed in MetalUI 0b400b4 (PR #58, ruling GX-X; the known issue in `aNodeAboveTheCanvasNeverCoversTheHeader` is
  gone).** **LF-a. A clip pushed inside an `offset` or a uniform `scaleEffect` forgets the clip outside it.** A node on the
  graph canvas is `NodeView` (`.clipShape(RoundedRectangle)` then `.offset` to its place), inside the canvas's
  `ZStack { … }.scaleEffect(zoom).offset(pan)`, inside the canvas's `.clipped()`. Panned past the canvas's top edge,
  the node's body and header paint outside the canvas: over the node library (docked left, the strip across the
  canvas's top; docked at the bottom, the column at its left) and over the panel's header. Its sockets and border,
  which have no clip of their own, are cut at the canvas's edge as they should be. Cause, read from the source: a
  translation or uniform positive scale is a *flattening* render effect (`Frame.paintWithRenderEffect`), which leaves
  `clipBase` alone, so a clip pushed inside it is intersected with the outer clip in the content's **pre-effect**
  space (`pushClip`); `RenderEffect.apply(to:flattens:outer:)` then maps that `contentMask` (it is `innerMask`) by
  the effect and never cuts it by the clip in force at the scope's entry. The outer clip moves with the content.
  Non-flattening effects (rotation) split the clip at entry and keep an outer mask, so they're right. Minimal
  reproduction (`renderFrame`, 200 × 200, scale factor 1):
  ```swift
  ZStack(alignment: .topLeading) {
      Color.red.frame(width: Pixels(40), height: Pixels(40)).clipped().offset(x: Pixels(0), y: Pixels(-60))
  }
  .frame(width: Pixels(100), height: Pixels(100)).clipped().padding(Pixels(50))
  ```
  The red rect is at (80, 20) 40 × 40 with `contentMask` (80, 20) 40 × 40, so it paints 30 px above the clip at
  y = 50; without the inner `.clipped()` its mask is (50, 50) 100 × 100, as it should be. `.scaleEffect(4)` in place of
  the offset gives the same: bounds and mask (20, 20) 160 × 160 against the clip (50, 50) 100 × 100. Wanted: a clip
  pushed inside a flattening effect is cut by the clip in force at the effect's entry after it is mapped (as an
  `innerMask` primitive's mask is mapped), in paint and in prepaint (hitboxes). Meanwhile: the graph panel draws the
  node library after the canvas (`GraphPanelBody`), over the room the canvas is inset from, so a node goes under the
  library's opaque background; that order is right regardless and stays. Still broken until the fix: a node panned
  past the canvas's top shows over the panel's header (which has no opaque fill), and one panned past the panel's
  edge shows over the glass padding and beyond it. Pinned: `aNodeAboveTheCanvasNeverCoversTheHeader` (a known
  issue; it starts failing as "Known issue was not recorded" once MetalUI fixes this, and the `withKnownIssue` goes).
- ✅ **Fixed in MetalUI 9ad2254 (PR #60, ruling GX-Y; the known issue in `aNodeAtANegativeCanvasPositionDrawsWhole`
  is gone).** **LF-b. A clip inside nested flattening effects is cut by the outer clip in the wrong space (regression in MetalUI
  0b400b4, the LF-a fix).** A node whose canvas position is negative (left of or above the canvas's origin before the
  pan and zoom), panned wholly into the canvas, paints only the slice of its header and body right of (and below) the
  canvas's edge moved by the pan: the rest shows the canvas background, while its border and sockets (no clip of their
  own) draw whole. A node laid out past the canvas's right or bottom edge (beyond the canvas's size, before the pan)
  and panned in loses its right or bottom part the same way, or vanishes. On MetalUI 67a579e the same nodes drew whole
  (their masks were the node's own clip, uncut: LF-a's leak). Cause, read from the source: each flattening scope cuts
  the masks pushed inside it by its `outer`, the clip in force at its entry, right after its own map
  (`Frame.insertThroughScopes` → `cutToEntryClip`). For the node's `.offset`, nested in the canvas's
  `.scaleEffect(zoom).offset(pan)`, that entry clip is the canvas's `.clipped()`, pushed **outside** the enclosing
  scopes, so in window space; it is applied in the enclosing scopes' content space (before zoom and pan) and then
  moved by them. Effective mask: the node's clip ∩ the canvas clip mapped by the zoom and pan, so the cut sits at the
  canvas's edge + pan. LF-a's nested test (`aClipInsideNestedFlatteningEffectsIsCutByTheClipOutsideBoth`) keeps its
  bar inside the outer clip in every space, so it can't see this. Wanted: a nested flattening scope cuts only by the
  clips pushed inside the enclosing flattening scope (when none has been pushed since that scope's entry, by nothing:
  the enclosing scope's own cut covers it). Minimal reproduction (MetalUI's `RenderEffectTests` harness:
  `effectFrame`, 200 × 200, scale factor 1; `fxBar(40, 40)` is `Color(.accent).frame(width: 40, height: 40)`; the
  LF-a stage is `ZStack(alignment: .topLeading) { inner }.frame(width: 100, height: 100).clipped().padding(50)`):
  ```swift
  lfaStage(fxBar(40, 40).clipped().offset(x: px(-60), y: px(0)).offset(x: px(60), y: px(0)))
  ```
  The bar is at (80, 80) 40 × 40, wholly inside the clip (50, 50) 100 × 100, but its `contentMask` is (110, 80)
  10 × 40, so only its right 10 px paint; wanted (80, 80) 40 × 40. Without the inner `.clipped()` the mask is
  (50, 50) 100 × 100, as it should be; on 67a579e this tree gives (80, 80) 40 × 40. The canvas's shape gives the same:
  `lfaStage(ZStack(alignment: .topLeading) { fxBar(40, 40).clipped().offset(x: px(-60), y: px(0)) }
  .scaleEffect(1, anchor: .topLeading).offset(x: px(60), y: px(0)))` → mask (110, 80) 10 × 40; with
  `.scaleEffect(0.5, anchor: .topLeading)` the bar is at (110, 80) 20 × 20 and its mask (125, 80) 5 × 20 (wanted the
  bar's bounds). In MetalCreator (`CanvasClipRenderTests`, panel 900 × 600, scale 2, canvas at (10, 46)): a Rectangle
  node at canvas (−100, 0), pan (150, 0), zoom 1, paints at (60, 46) 168 × 136 pt with its body's mask (160, 46)
  68 × 136 pt (device (320, 92) 136 × 272); at zoom 1.5 at (10, 46) 252 × 204 pt, mask (160, 46) 102 × 204 pt. Not a
  window-position effect: the panel's offset in the window, the dock and the selection don't matter. Pinned:
  `aNodeAtANegativeCanvasPositionDrawsWhole` (a known issue; it starts failing as "Known issue was not recorded" once
  MetalUI fixes this, and the `withKnownIssue` goes).

## Hit by the Themes milestone, 2026-10-09

Labelled TH-a… so they don't clash with the labels above. Checked against MetalUI `67a579e`.

- **TH-a. Menu content can't be evaluated outside MetalUI.** View ▸ Theme is built from the store each time it
  opens (the built-ins, a divider, the custom themes, a divider, Edit Themes…), and a test should check what it lists,
  which item is checked, and that choosing one runs its action. `MenuContent`'s only requirement is SPI and
  `MenuNode` is internal (`MN-D` item 1), so a client test can't read a `CommandMenu`'s or a `Menu`'s items. Stopgap:
  `ThemeMenu.sections(_:)` returns the themes it lists, which `ThemeMenuTests` checks; the builder only turns them into
  items. Wanted: a public read-only evaluation of menu content (titles, enabled, `isOn`, shortcut, and a way to run an
  item), or one in a test-support product (with M6-e's headless window).
  **Fixed by MetalUI item 8** (master 280d706: `MenuEvaluation`, `TestApp.menuBar`, `performMenuBarItem`) **and adopted**
  (plan `2026-10-12-adopt-test-harness`): `ThemeMenuEvaluationTests` evaluates `ThemeMenu.items` as a window does at the
  menu's open and checks what it lists (built-ins, divider, custom themes, divider, Edit Themes…), which item is checked,
  and that choosing one shows the theme and Edit Themes… opens the editor; it also reads View ▸ Theme from the app's
  menu bar (`AppCommands`) and runs an item through `performMenuBarItem`, which restyles the window. `ThemeMenu.sections(_:)`
  stays: it is the list the menu is built from, and `ThemeMenuTests` keeps pinning it.

## Hit by the sketch editor (S5a), 2026-10-09

Labelled S5-a… so they don't clash with the labels above.

- **S5-a. No modifiers on a hover (and, as GI-a, on a tap).** Sketcher spec §8: holding ⌘ suppresses constraint
  inference while drawing (a line's end snapping horizontal or vertical), and the rubber band previews what a click
  would infer, so both the click and the hover need the modifiers held. The tap half is the graph-input track's
  **GI-a** (`SpatialTapGesture.Value` has only `location`), one request with this one. What S5-a adds is the hover:
  `onContinuousHover`'s phase carries no modifiers, and nothing reports a modifier change while the pointer is still
  (SwiftUI apps on macOS read `NSEvent.modifierFlags` or `onModifierKeysChanged(mask:initial:_:)`).
  `DragGesture.Value.modifiers` (C7's `CI-G`) covers drags only. Stopgap: none. `ViewportModel.click(at:modifiers:)`
  and the editor take modifiers, and `ViewportView` passes `[]`, so ⌘ doesn't suppress inference yet (human check
  S5-3 records it). The Select tool's clicks toggle membership instead of needing ⇧. Wanted, as one request with GI-a:
  tap modifiers (GI-a), and modifiers on hover or SwiftUI's `onModifierKeysChanged(mask:initial:_:)`.
  **Fixed by MetalUI C16** (master a720fba, `IF-B`, `IF-D`: `SpatialTapGesture.Value.modifiers` and
  `onModifierKeysChanged(mask:initial:_:)`, which also fires while the pointer is still and reports the keys released when
  the window stops being key) **and adopted** (plan `2026-10-12-adopt-c16`): `ViewportView` watches ⌘ only
  (`ViewportModifiers.hoverMask`, so ⇧ and ⌥ wake nothing) and calls `ViewportModel.modifiersChanged(_:)`, which replays
  the tool's last hover with the modifiers held (`ViewportTool.pointerMoved(to:modifiers:projector:)`); the sketch editor's
  rubber band and inference glyphs drop the snap while ⌘ is held, with no mouse move, and a click carries ⌘ from its tap
  (GI-a). The Select tool keeps toggling membership (user decision U2). Human check C16-2 answers S5-3's "known".

## Hit by the sketch editor (S5b), 2026-10-09

- **S5-b. A drag's value has no click count, so the graph canvas can't see a double click.** Sketcher spec §8: a
  double click on a Sketch node opens its sketch. The canvas's clicks come from its one
  `DragGesture(minimumDistance: 0)` (GI-a: a tap's value has no modifiers), whose `Value` has no click count, though
  MetalUI's platform event has one (`MouseEvent.clickCount`, AppKit's, which honours the user's double-click speed).
  `SpatialTapGesture(count: 2)` recognises a double tap, but beside the zero-distance drag the two compete in the
  gesture arena (whether `.simultaneousGesture` lets both recognise can't be checked from a client without a headless
  window, M6-e), and its sequence waits MetalUI's fixed 0.33 s (`tapSequenceDeferral`), not the user's setting.
  Stopgap: `EditorModel+DoubleClick` pairs two plain clicks on one node itself, at most 0.4 s
  (`doubleClickInterval`) and 4 points (`doubleClickSlop`) apart, with an injectable clock. The values are the groups
  spec's (`2026-10-09-selection-groups-comments-design.md` §6: "two primary clicks within 0.4 s and 4 pt with no
  modifiers"), not macOS's 500 ms default, so the groups editor shares this one recogniser. **The same request as the
  groups spec's "Canvas double-click (GI-a, MetalUI C16)" (§8)**: one MetalUI request, C16, covers both; S5-b is this
  file's record of it. Wanted: `clickCount` on `DragGesture.Value` (the press's `MouseEvent.clickCount`), as
  SwiftUI-on-AppKit apps read `NSEvent.clickCount`; then the model reads the count, the user's double-click speed is
  honoured, and the stopgap goes. Human check S5b-7 records it. Sent to the MetalUI session with this entry.
  **Fixed by MetalUI C16** (master a720fba, `IF-C`: `DragGesture.Value.clickCount`, the press's, the same in every value of
  one press) **and adopted** (plan `2026-10-12-adopt-c16`, user decision U1): `GraphPanelInput` passes the press's count and
  `EditorModel` pairs a click counted 1 with one counted 2 on the same target (a node's body, a note, a frame's title bar,
  no modifiers on either); `RecentClick`, `EditorModel.now`, `doubleClickInterval` (0.4 s), `doubleClickSlop` (4 pt) and
  the tests' `TestClock` are gone, so the user's double-click speed decides. Human check C16-3.

## Hit by M7 (measure and record), 2026-10-09

Labelled M7-a… so they don't clash with the labels above. Checked against MetalUI `2155f1e`.

- **M7-a. `ForEach` names an element by its id's description, so ids that print alike drop elements.** The graph
  canvas draws its nodes with `ForEach(nodes, id: …)`. A `NodeID` is a UUID that prints only its first 8 hex digits
  (short, for messages), so two nodes whose UUIDs began alike drew as one: MetalUI produces only the first element
  whose id is equal **in value or in description** (`DD-L`, divergence 79, pinned on purpose by
  `aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst`), where SwiftUI tells `Hashable` ids apart. Real nodes
  collide rarely (random UUIDs), but tests that number their nodes (`00000000-…-000000000001`) lost every node after
  the first. Fixed in MetalCreator without a stopgap: the canvas keys nodes and ⌥-drag ghosts by the whole UUID
  (`id: \.id.rawValue`, `CanvasIdentityRenderTests`), which stays right if MetalUI changes. Wanted: identity by
  `Hashable` equality alone, as SwiftUI; or, failing that, a debug-build warning when a `ForEach` drops an element,
  since today it drops it silently.
  **Fixed by MetalUI C20** (master 5f35df6, PR #68): `ForEach` tells ids apart by `Hashable` equality, as SwiftUI does;
  ids equal as values still produce only the first. Nothing to adopt: keying by the whole UUID stays correct.
- **M7-b. No warm headless frame to measure.** Spec §7.3's targets are measured headless
  (`Tests/CreatorAppTests/Bench`, docs/verification/performance.md). The only public way to draw the app's window
  without a screen is `renderFrame`, which draws a fresh window's first frame each call: no state table, text
  shaping cache or raster cache survives to the next, so every number is a cold-frame upper bound. PERF-a and PERF-b
  were measured with a warm frame loop and a headless `Window`, but those need `@testable import MetalUI` and aren't
  checked in. Stopgap: cold frames, labelled as an upper bound. Wanted, as one request with M6-e: a public headless
  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,
  including the display link's pacing.
  **Fixed by MetalUI item 8** (master 280d706: a `TestWindow` is one `Window` for its life, `lastFrameWork`/`frameWork`
  count the work of each frame) **and adopted for counts** (plan `2026-10-12-adopt-test-harness`): `WarmFrameTests` opens
  the editor with `recordsLayout: false` and pins what is stable on any machine, never a time: an idle window draws no
  frame at all, a warm redraw uploads no atlas pixels, rasterizes and blurs no pixels and makes no texture, and a second
  unchanged frame does exactly the work of the first. It does **not** pin zero layout work: a forced redraw of the
  whole window re-measures it (hundreds of layout cache misses at 1440 × 900), which is PERF-b (C14 slice 1 adopted, C14-b
  queued), so the test leaves that number to PERF-b's own adoption. Not done: moving `Tests/CreatorAppTests/Bench`
  onto the warm
  window (the release benchmark is never run in this plan); `docs/verification/performance.md` still says cold frames.

## Used again by the C10 adoption, 2026-10-09

- **M6-e and M7-b, used again.** The C10 adoption's two animations can be seen only at rest from a test: `renderFrame`
  draws one frame at time zero with a fresh animation store, and a `Frame`'s timestamp and `AnimationStore` are
  internal. The refusal shake's motion is tested through the public `KeyframeTimeline` at injected times, the
  spinner's through its still frame, and what a real window does (the shake running on a new refusal, the spinner
  turning, a slider's `onEditingChanged` pairing) is human checks C10-2 to C10-4. Stopgap: none beyond that. Wanted,
  with M6-e: a public headless window, or `renderFrame` taking a timestamp and returning its animation store, so a
  test can tick a `keyframeAnimator` and a `ProgressView` and press a `Slider`.
  **Fixed by MetalUI item 8, partly adopted** (plan `2026-10-12-adopt-test-harness`): `RefusalShakeWindowTests` moves the
  window's clock by hand and reads the frames (a refused node is 6 points out at 0.05 s, 6 across at 0.15 s and home at
  0.25 s, only that node moves, and a second refusal shakes again) and `InspectorSliderWindowTests` drags the inspector's
  real slider (one drag is one "Change Width" step, two drags are two). Not adopted: the spinner turning, because a
  node can be held mid-evaluation only by a kernel that waits, which no test kernel does; human check C10-3 stays.

## Hit by the C10 adoption, 2026-10-09

Labelled C10-a… so they don't clash with the labels above. Checked against MetalUI `2155f1e`.

- **C10-a. No backdrop blur behind a material.** Spec §6.1 wants the floating panels (graph panel, inspector, top bar)
  to blur the 3D viewport behind them. MetalUI's `Material` is a flat tint fitted to SwiftUI's (divergence 166) and
  `.blur(radius:)` blurs a view's own pixels, leaving a `MetalView` unblurred (divergence 167), so nothing blurs what is
  behind a panel, and the viewport behind MetalCreator's panels is a GPU surface a CPU blur could not read
  (`LK-L` item 4, deferred as C10-c in `LK-A`). Stopgap, and the look we ship: `GlassPanel` fills with the theme's
  translucent `glass` tint and a 1-pt hairline. Wanted: a backdrop blur that sees a `MetalView` beneath it (a pass split
  at each material on both renderers), usable as `.background(.ultraThinMaterial)`; until then the theme's own tint stays.
  Sent to the MetalUI session by the controller, 2026-10-09.
  **Fixed by MetalUI C21** (master d6a815c, item C21, record §94, rulings `BB-A` to `BB-T`): `.background(.ultraThinMaterial)`
  and the other five materials on a rounded rectangle, capsule or ellipse blur what MetalUI drew beneath them, a
  `MetalView` viewport included, with the material's tint composited on top. **Adopted** (plan `2026-10-12-adopt-c21.md`):
  every glass panel (`GlassPanel`: the graph panel, inspector, top bar, pick banner, Show graph button, palette and theme
  editor, and the sketch chrome through it) and the sketch editor's chips draw `GlassStyle` through
  `glassBackground(_:in:)`: the surface's material (`GlassSurface.thickness`), then the theme's `glass` role over it at an
  opacity lowered so that the pair hides what the role's opacity says (the role's colour, so a theme editor edit and
  Alucard's light glass still apply), then the hairline. `GlassFillTests`, `GlassBackgroundTests`, `ChipGlassTests` and
  `GlassBlursViewportTests` pin it (one backdrop record per panel, painted after the viewport's surface); the look over a
  moving viewport is human check group C21. What C21 leaves, MetalUI's divergences: 245 the blur sees only the window's own
  content (the viewport is that, the desktop is not); 246 no saturation lift (a blurred backdrop is plainer than SwiftUI's);
  247 the blur region is the shape's bounding box (a small panel, a chip, blurs only what is in its own box, edge-clamped);
  248 a material inside `.shadow`, `.blur` or `.compositingGroup()` draws flat (no panel here uses them,
  `aPanelHasNoImagesSoNothingIsRasterised`); Reduce Transparency is honoured since C27 (C21-b: MetalUI draws an opaque grey, the tint goes opaque). MetalUI's own human checks
  BB1 to BB6 are unrun; C21-1 and C21-3 are the first real-window sight of the blur over a viewport, and a result that
  looks like a MetalUI fault should be run against BB1 and BB2 in MetalUI's demo before it is logged here.

## Hit by adopting C8 (app shell), 2026-10-09

Labelled C8-a… so they don't clash with the labels above. Checked against MetalUI `70e9389`.

- ✅ **Fixed in MetalUI 930db4a (C22, PR #70: SwiftUI's `WindowDragGesture`), adopted (plan `2026-10-12-adopt-c22`), pending human
  check AS-5:** `WindowDragHandle` (CreatorStyle) is `Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())`. It fills the
  top bar's empty space (the label and the gap beside the controls; the sketch toolbar's too) and `AppRoot` lays one across the window's
  top for `AppLayout.windowDragStripHeight`. It wins the press over the viewport's gestures, which are cancelled when the drag starts
  (divergence 275); a click in it moves nothing and doesn't reach the viewport; a double click doesn't zoom. This entry
  predicted the failure below (the viewport's gestures form an arena over the band, so MetalUI's unclaimed-press drag never
  fired); C22 gives the band a gesture of its own that joins that arena and wins it. AppKit's real move is MetalUI's WD1–WD7
  and our AS-5.
  **C8-a. No window-drag region for a hidden title bar under a gesture-carrying view.** With
  `windowStyle: .hiddenTitleBar` MetalUI drags the window from a press in the title-bar band only when nothing claims
  the press: no opaque hitbox and no gesture arena (ruling AS-J, `Window.answerUnclaimedTitleBarPress`).
  MetalCreator's viewport fills the whole window (spec §6.1) and carries gestures over all of it
  (`ViewportView+Parts`: a `SpatialTapGesture`, three `DragGesture`s and a `MagnifyGesture`), so every press in the
  band, including one on the empty glass of the top bar (glass only paints, divergence 141), forms an arena, and the
  window can't be dragged by its top bar. Found by reading MetalUI 70e9389; human check AS-5 confirms or refutes it.
  Stopgap: none (a claiming view over the band would not drag the window either, and the viewport stays full-bleed).
  (Superseded: the hidden title bar is on, with C22's `WindowDragGesture`; see the first lines of this entry.)
  Wanted: a way to mark a region as the window's drag handle that wins over the gestures beneath it, as SwiftUI's
  `WindowDragGesture` / `.windowBackgroundDragBehavior(.enabled)` (macOS 15) or a `.windowDragArea()` modifier; the
  top bar's glass would carry it.

## Canvas comments (sub-project B)

- **CM-a. `TextEditor` has no commit key.** Canvas comments spec §7: a note's text commits on focus loss or ⌘↩.
  MetalUI's `TextField` has `onSubmit` (Return), but `TextEditor` has none: Return inserts a line break (ruling
  TI-H), and whether a ⌘↩ reaches the window's `onInput` fallback while a `TextEditor` is focused can't be checked
  without a headless window (M6-e). Originally (before C9): no stopgap, since a global ⌘↩ chord would work around the gap, so MetalCreator commits
  a note's text on focus loss only (a canvas press clears focus, M5-g; the model also commits on a selection change
  and on saving), and ⌘↩ is unbound. Wanted: C9 lets MetalCreator bind it with SwiftUI's own
  `.onKeyPress(.return) { press in guard press.modifiers.contains(.command) else { return .ignored }; commit();
  return .handled }` on the `TextEditor` (no MetalUI-only hook is needed). Status: answered: lands with C9. The gap
  was already sent to the MetalUI session by the controller. Logged with C9 (key and focus scoping), which owns the key
  handling.
  **Pinned through a real window (2026-10-12):** `CanvasTypingFocusWindowTests` types into the inspector's `TextEditor`
  and sends the primary-modifier Return (commits, one "Edit Note" step) and a plain Return (breaks the line).
  **Fixed by MetalUI C9** (KF-Z/KF-AA, merged to MetalUI master 0a9eb36): a Return with the commit modifier (⌘ on macOS, ⌃ elsewhere: `CommentKeys.commitModifier`) is not an editing key of a
  `TextEditor`, and an `onKeyPress(keys: [.return])` handler runs before the editor's keys, so
  `press.modifiers.contains(commitModifier) ? commit() : .ignored` commits on ⌘↩ (⌃↩ off macOS) while plain Return still breaks the line (no
  MetalUI-only hook was needed). **Adopted** (Comments typing plan Task 3): `CommentKeys.commitsNote` is that test, used by
  the inspector's note box (`CommentTextEntry`) and the canvas editor (`CommentEditorField`). The spec's CM Errata line
  "not on ⌘↩" is superseded (Errata (B: typing on the canvas)).

## Hit by the sketch editor (S5c), 2026-10-09

- **S5-c. A `MetalView` draw can't draw text, so labels anchored in the 3D scene are element-tree text, rebuilt on every
  camera change, and a text's size could not be asked.** Sketcher spec §8: a sketch's dimension values are shown in the view, at the dimension
  (`ViewportOverlay.labels`, drawn from `ViewportModel.overlayLabels(measuring:)`). They follow the camera (a pan, a zoom, the Look
  At onto the plane) and a sketch has dozens. MetalUI draws text only as elements in the tree, never inside a `MetalView`'s
  draw (`MetalDrawContext` offers the target, the command buffer, `clear(…)` and the scale factor, and no text), so
  `ViewportView` places one `ProposalText` per label from a function that reads the pose: the tree is rebuilt on every
  camera change (PERF-b's cost), and a camera animation doesn't rebuild it (M4-b), so the labels are hidden for the 250 ms
  Look At that opens a sketch. A text box's size couldn't be asked either, so the box was computed from the text (7 points a
  character, `PlacedLabel.size(of:)`, as the S5a readout chip's was), which clips a wide string and wastes room on a narrow one.
  **Measuring: fixed by MetalUI C23 and adopted** (merged to MetalUI master 7f891629, PR #73, record §99, rulings
  GT-A…GT-I, divergences 295 and 296; plan `2026-10-12-adopt-c23`): `@Environment(\.textMeasurer)` is a get-only `TextMeasurer`,
  and `measurer.resolve(Text or ProposalText).measure(in: proposal)` is the unrounded size layout gives the text. `ViewportView` and
  `PointerReadoutView` read it, wrap it as a `TextMeasure` (`TextMeasure+MetalUI.swift`: `ProposalText` in `.caption`, no wrapping) and
  hand it to the models as a parameter, so the placement stays in the models and a unit test passes a deterministic measure
  (`ViewportModel.overlayLabels(measuring:)`, `handleLabels(measuring:)`, `SketchEditorModel.readoutChip(measuring:)`,
  `inferenceChip(measuring:)`). A box is the measured width rounded up plus padding at each side; no fallback estimate is left
  (`PlacedLabel.size(of:)`, `PlacedLabel.characterWidth` and `ReadoutChip.characterWidth` are gone). The triad's axis names keep
  their fixed 16-point box: one capital letter, centred on a fixed spot, not an estimate from a length. Pinned:
  `TextMeasureWindowTests` (MetalUI's own `docs/testing.md` pattern: the real measurer equals the laid-out frame, and ten
  capital Ws get a wider box than the old estimate), `OverlayLabelTests`, `HandleLabelTests`, `ChipMeasureTests`.
  **Drawing text in a `MetalView` pass: deferred by MetalUI, and not needed.** MetalUI measured the element path first (GT-A:
  20 and 100 `Text` overlays over a `GPUSurface` cost linear in their number, with no raster or upload after the first frame)
  and deferred `MetalDrawContext.drawText` to C14's close-out (GT-F; the trigger is that after C14 a 100-label overlay still scales
  with N through anything but the labels' own paint and human check S5c-6 reports a missing frame budget). It recommends keeping
  labels as views over the surface, which is what MetalCreator does: that is the design, not a workaround. What is left of this
  gap's first complaint is not S5-c's: the tree rebuild on every camera change is PERF-b's (C14 slice 1 adopted, C14-b
  queued), and the hiding of the labels
  during the 250 ms Look At that opens a sketch is M4-b's (`TimelineView(.animation)` is on MetalUI master since C9 and is not
  adopted here: labels still hide while the camera animates, `ViewportModel.overlayLabels` and its test say so). Human checks S5c-6
  (the camera, and the trigger's frame budget) and C23 (the sizes). Not measured: a sketch with 20 or more labels pays the rebuild
  for each on every camera change; S5c-6 is where that is looked at, and the labels are not capped or culled by count (a silent cap
  would hide dimensions). Reported and answered by MetalUI (C23, GT-F); nothing outstanding from MetalCreator.

## Typing on the canvas (Comments typing plan), 2026-10-10

Labelled CT-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a…, CM-a… entries.

- **CT-a. A press outside every key region resigns no focus, and nothing asks it to without taking over key routing.**
  Typing a note or a title on the canvas should end when the user presses anywhere else (spec §8: "on a press elsewhere").
  C9 gives a key region (`hoverKeyRegion`): a primary press inside it clears a field's focus, but a region also routes keys
  by hover, and a press outside every region resigns nothing (KF-G, SwiftUI's rule). MetalCreator uses what exists and works
  around nothing: the canvas is a region (a canvas press ends the edit), viewport presses still call `window.focus(nil)`
  (M4-a's hook), and every model commit ends it (a selection or level change, hiding the panel, undo, save, export, another
  field being typed into). A press on inert chrome (the glass padding, the header's gaps, the inspector's empty areas)
  leaves the editor open and focused; the next press on the canvas, the viewport or a control ends it. Wanted: an opt-in
  that makes a container resign focus on a primary press inside it without routing keys, for example
  `.resignsFocusOnPress()` (or `hoverKeyRegion(routesKeys: false)`), which MetalCreator would put on the app's root. Human
  check CT-11 records what a press on inert chrome does. Status: queued as MetalUI C24 (after C9, which merged to MetalUI master 0a9eb36; the spelling is still open) (the
  standing rule: every MetalUI gap goes to that session to implement); the repository is never edited from here.
  **Adopted (2026-10-13, plan `2026-10-13-adopt-c24.md`):** C24 is on MetalUI master 0fb2ea6e (PR #74, record §98, rulings
  RF-A…RF-I; it adds no divergence). The spelling is `.resignsFocusOnPress(_ isEnabled: Bool = true)`, on any element group
  (MetalUI-only: SwiftUI has no such modifier, RF-A). `AppWindowRoot` carries it (and `GraphPanelPreview`'s `PreviewRoot`;
  `ViewportHarness` hosts no field and does not). MetalUI's rules, which the code relies on: a primary press inside the region
  clears focus and routes no key by hover (unlike `hoverKeyRegion`, so `CanvasSurface` is unchanged); a press on a text field or
  a click-focusable element moves focus straight to it (A→B, no nil in between); a press on inert chrome resigns;
  `allowsHitTesting(false)`, `.disabled` and `.hidden()` withdraw the region; a `Deferred` presentation's press does not resign
  through a region below it; a secondary or other press resigns nothing; `@FocusState` observes the resign. What changed
  here: a press on the graph panel's glass or its header gaps now ends a canvas edit (one
  "Edit Note" or "Edit Frame" step) and commits a typed inspector value (one step) (a press on the inspector's empty glass
  already ended it, through the viewport beneath, so the tests do not count it as a root-modifier spot); `AppModel.releaseTextFocus` and its install
  in `AppInput` are gone (the viewport's press still commits a pending entry, which is a model commit); the inspector's accent
  swatch is a button, so a press on it now ends the edit too (the text commits a frame after the accent changes: two undo
  steps). Model-driven ends are untouched (selection or level change, hiding the panel, undo, save, export, another field
  typed into). Pinned: `CanvasResignOnPressWindowTests`, `InspectorFieldResignWindowTests`, `CanvasTypingFocusWindowTests`.
  Human checks CT-11 (rewritten) and C24-1 to C24-5.
- **CT-b. No way to set a text field's selection or caret, so an editor opened from code cannot open with its text
  selected or its caret at the end.** A double click that starts editing a note or a title in place wants the title's
  whole text selected (as a rename does) and a note's caret at the end of its text. `TextField` and `TextEditor` have no
  selection binding (SwiftUI's `TextField(text:selection:)` with `TextSelection`, macOS 15), and a field focused from code
  (`FocusState` written in `onAppear`) opens with its caret at the start of its text and nothing selected (measured in the
  C9 probe: a `.textInput("X")` into a freshly focused field gives `Xhello`). Before C25, MetalCreator worked around nothing: the editor
  opened as MetalUI opened it, and the user pressed ⌘A or ⌘→ (or clicks) to select or move the caret. Wanted: a selection
  binding on both fields, or `FocusState`-style `selectAll()` / caret-position on focus. Human check CT-1 records what the
  user sees. Status: queued as MetalUI C25 (after C9, merged to MetalUI master 0a9eb36; a `selection` binding or a selectAll/caret-on-focus hook); the repository is never edited from here.
  **Adopted (2026-10-12, plan `2026-10-12-adopt-c25.md`):** C25 is on MetalUI master 3fce05f. The canvas editor binds the selection
  (the controlled spellings `TextField(_:text:selection:onChange:onSelectionChange:)` and the `TextEditor` one, over
  `CommentEdit.selection`): `beginEditing` sets it, a frame's title opens with its whole text selected (typing replaces it,
  as a rename does) and a note opens with the caret at the end of its text (typing appends), and the field's own
  selections (typing, a click, a double click, shift-arrows, ⌘A, Delete) are stored back with
  `EditorModel.commentSelectionChanged`. MetalUI's rules, which the code relies on: a write applies before the next frame
  and wins over the focus in the same turn (divergence 265), nothing is written at focus or resign (divergence 266), the
  field's own echo is ignored, a write while an input method composes is held back (the model writes only when the edit
  begins, so a composition is never raced), a stale index reads safely (`CommentEdit.selectedOffsets` clamps it), a
  multi-selection acts on its first range, and the undo history is untouched except that the open typing group ends.
  Pinned: `CommentEditSelectionTests`, `CanvasTypingSelectionWindowTests`; the typing tests that assumed a caret at the
  start (gap CT-b's old measurement) now expect typing to append to a note. Other fields focused from code (the palette's
  search, which opens empty) and the click-focused fields (inspector names, the theme name, dimension fields) are not
  changed: a click puts the caret where it lands, and there is nothing to select in an empty field (user decision U3 of
  the plan). Composing had no automated test (new gap CT-d, adopted by C28 below). Human checks CT-1 (updated) and C25-1 to C25-7.
- **CT-c. The comment editor's C9-dependent behaviour has no automated test.** The field's Return, Esc and ⌘↩ handlers,
  the focus-loss commit, `onAppear` focus, a canvas press clearing focus (M5-g), the hovered key region and a focused field
  winning over hover are `onKeyPress` / `FocusState` / key-region behaviour that exists only inside a real `Window`.
  MetalUI exposes no public key or mouse injection (`simulateInput` lives on `FakePlatformWindow` in MetalUI's own test
  target: M6-e), so MetalCreator tests only the pure `KeyPress` to `KeyEvent` mapping, the model and render geometry. If
  MetalUI changes, or the sibling-not-child arrangement regresses, only the manual checks CT-1..CT-9 notice. MetalCreator
  works around nothing (no private-API or `@testable` reach into MetalUI). Wanted: M6-e's public headless `Window` with
  `simulateInput` and a rendered frame, then a test that types into the field, sends ⌘↩ and Esc, presses the canvas, and
  asserts `commentEdit` and the graph. Status: rides with M6-e (queued); forward to the MetalUI session per the standing
  rule; the repository is never edited from here.
  **Adopted (2026-10-12, plan `2026-10-12-adopt-test-harness`):** the tests type through the app's real window
  (`AppWindow`, MetalUI 280d706). `CanvasNoteTypingWindowTests`: a double click opens a focused editor exactly over the
  note (both docks, and at 0.5× and 2× zoom), Return breaks the line, `CommentKeys.commitModifier` (primary-modifier)
  Return commits as one "Edit Note" step, Esc cancels with nothing to undo, a press on empty canvas commits and clears
  focus (M5-g). `CanvasTitleTypingWindowTests`: the same for a frame's title (Return commits through `onSubmit`, a blank
  title is refused; dragging the title bar moves the frame and its nodes as one "Move" step). `CanvasTypingKeysWindowTests`: while a field is focused the graph's keys edit its text (Delete,
  arrows, Space, F, the ⌘ chords, ⌘A, Tab) and afterwards act again over the canvas but not over the viewport (M5-b).
  `CanvasTypingFocusWindowTests`: a double click on another comment commits the first and focuses the next; the
  inspector's note box breaks lines on Return and commits on the primary-modifier Return (CM-a); clicking into it commits
  a canvas edit first; a press on the panel's glass ends the edit (CT-a, adopted from MetalUI C24: `CanvasResignOnPressWindowTests`);
  a press on the 3D viewport commits at once; the inspector's accent swatch changes the accent and ends the edit (C24). `CanvasTypingUndoWindowTests`: ⌘Z and ⇧⌘Z undo and redo a committed note edit in one
  step each, and ⌘Z while an editor is focused undoes the typing in the field and leaves the document alone (KF-C).
  A field's focus-loss commit (`onChange(of:)`) runs in the frame after the click, so that test runs `runUntilIdle()`.
  Human checks CT-1..CT-11 keep what a person must judge (CT-1's look, CT-6's softness, CT-7, CT-12), a physical
  keyboard, the paste and the swatch.

## Hit by the C21 adoption, 2026-10-12

Labelled C21-a… so they don't clash with the labels above. Checked against MetalUI `d6a815c` and again at `930db4a` (`d6a815c` or later works).

- **C21-a (adopted by C27). A `Material`'s tint opacity can't be read, so a theme's tint can't be sized against it.** A glass panel is
  the theme's `glass` role (a colour and the opacity the person chose) over a material, and the pair should hide as much
  of the backdrop as the role says: `(1 - tint) * (1 - material) = 1 - glass`. That needs the material's own opacity
  (0.4706 for `.ultraThinMaterial` in light, 0.5059 in dark, and so on), which is `Material.fill(for:)`, internal. Nor can a
  material be given our colour (`.ultraThinMaterial.tint(color)`) or an opacity. Stopgap: `GlassThickness.materialOpacity(isDark:)`
  copied MetalUI's `LK-L` table, and `GlassMaterialTableTests` rendered each material in both schemes and failed when MetalUI's
  record differed from the copy. Wanted: a public read of a material's tint (`Material.tint(in:) -> Color`, or its opacity),
  or a material that takes a tint colour. Found by the C21 adoption; sent to the MetalUI session 2026-10-12.
  Note: MetalUI's `Material.swift` doc comment still says "a fitted flat tint, with no backdrop blur (divergence 166)"; divergences.md says 166 was amended, so the source comment is stale (seen at `930db4a`).
  **Adopted (2026-10-13, plan `2026-10-13-adopt-c27.md`; MetalUI C27, master 848ee029, PR #76, record §101, ruling `MT-B`):**
  `Material.tint(in: ColorScheme) -> Color` is public (MetalUI-only; SwiftUI has no such read), and the opacity is
  `tint(in: scheme).resolve(in: EnvironmentValues()).opacity`. `GlassThickness.materialOpacity(isDark:)` is now that read, so the
  copied `LK-L` table is deleted and a retune of MetalUI's fitted table moves every tint with it. `GlassMaterialTableTests`, which
  guarded the copy, is replaced by `GlassMaterialOpacityTests` (per thickness and scheme, the opacity read equals the opacity of
  the backdrop record MetalUI draws) and `GlassThicknessTests` (what any table must satisfy: a thicker material is more opaque,
  every opacity is a fraction, light and dark differ). The solve `t = 1 - (1 - g) / (1 - m)` is unchanged, in
  `GlassStyle.tint` and `tintOpacity(glass:materialOpacity:)`; that the pair really hides `g` of the backdrop is MetalUI's human
  check MT-3 and ours C21-1. The stale source comment in the note is fixed in MetalUI (it now says there is no saturation lift,
  divergence 166).
- **C21-b (adopted by C27). Reduce Transparency is neither readable by an app nor honoured by materials.** MetalUI's divergence 249: a
  material blurs whatever the accessibility setting says, and nothing in `EnvironmentValues` carries the setting (SwiftUI's
  `\.accessibilityReduceTransparency`). The HIG asks for it. Sent to the MetalUI session 2026-10-12. No stopgap: MetalUI gaps
  are fixed in MetalUI, so the panels blur whatever the setting says until MetalUI provides it. Wanted:
  `\.accessibilityReduceTransparency` (the reduce-motion pattern: two `PlatformWindow` requirements), and materials that fall
  back to an opaque tint when it is on. Human check C21-5 waits on it.
  **Adopted (2026-10-13, plan `2026-10-13-adopt-c27.md`; MetalUI C27, master 848ee029, PR #76, record §101, rulings `MT-D`,
  `MT-E`, `MT-F`, `MT-G`, `MT-I`):** `EnvironmentValues.accessibilityReduceTransparency` (SwiftUI's key, read-only outside
  MetalUI) is stamped from two defaultless `PlatformWindow` requirements: AppKit reads
  `NSWorkspace.accessibilityDisplayShouldReduceTransparency` live, SDL answers `false` and never fires (`MT-E`). With it on every
  material draws the scheme's fitted grey at alpha 1 as an ordinary rect and never a backdrop record, so no blur pass and no
  frame-target copy (`MT-F`, divergence 315: a ruling, not a measurement of SwiftUI). MetalCreator owns no `PlatformWindow`
  conformer (`grep PlatformWindow Sources` finds nothing: the app runs on MetalUI's platforms and the tests on
  `HeadlessPlatformWindow`), so the two new requirements need no change here. `GlassPanel`, `ReadoutChipView` and
  `InferenceChipView` read the value and pass it to `GlassStyle(reducesTransparency:)`, which makes the theme's tint fully opaque
  (plan user decision U-C27-1); the material layer is still drawn and MetalUI turns it into the grey under the tint. The
  stopgap-shaped `GlassStyle.blursBackdrop` is removed: MetalUI owns the blur. `GlassReduceTransparencyWindowTests` (real
  headless windows, `HeadlessPlatformWindow.Options` and `TestWindow.setReduceTransparency(_:)`) pin: with it on no panel, palette
  or chip draws a backdrop record, each is the theme's glass colour at full opacity, every label is still drawn, and switching it
  on and off while the app runs returns the original frame; `reducingTransparencyKeepsEveryThemesTextLegible` pins the contrast
  of every built-in theme's text on its opaque glass (primary 7:1, dim 3:1). Still open: the grey against a real SwiftUI window
  is MetalUI's human check MT-1, and the real system toggle is ours, C21-5.

## Found by the C25 adoption, 2026-10-12

Labelled CT-d so it stays beside CT-b and CT-c. Checked against MetalUI `3fce05f`.

- **CT-d (adopted by C28). `MetalUITesting` cannot drive an input method, so how the canvas editor behaves while text is composing has no
  automated test.** MetalUI holds a selection write back while an input method composes (marked text; divergence 266 and
  ruling `SL-H`) and publishes the selection after the composition commits, but `TestWindow` types only committed text
  (`typeText`) and keys (`typeKey`): no public call starts, updates or commits marked text. The canvas editor opens a
  title with all of it selected and a note with its caret at the end, and it writes the selection only when an edit begins,
  so nothing in MetalCreator can race a composition; but a regression in how the field takes a composition into the
  model's draft, or a model that later writes the selection mid-edit, would pass every test. MetalCreator works around
  nothing: human check C25-3 (an input source such as Japanese Hiragana) is the only cover. Likewise the undo granularity around a selection write (MetalUI ends the open typing group when a selection is written) has no automated test, because what MetalUI restores after ⌘Z in the field is not documented and a test would pin a guess: human check C25-7 is its only cover. Wanted: a `TestWindow`
  composition driver, for example `setMarkedText(_:selectedRange:)` and `commitMarkedText()` beside `typeText`, with the
  field's accessibility value or `focusedElement` reading the marked text. Sent to the MetalUI session 2026-10-12.
  **Adopted (2026-10-13, plan `2026-10-13-adopt-c28.md`; MetalUI C28, master f6f865c1, PR #75, record §102, rulings
  `IM-A`…`IM-J`):** `TestWindow` has `setMarkedText(_:selectedRange:)`, `commitMarkedText()`, `commitMarkedText(_:)`,
  `cancelMarkedText()`, `markedText` and `markedSelection`, which send the platforms' own composition events through the
  window. `CanvasTypingCompositionWindowTests` composes in a frame's title and a note, and `InspectorFieldCompositionWindowTests`
  in an inspector number field: marked text is in the field and not in the model's draft (the selection the edit opened
  with is untouched); committing a candidate is one write and one undo step, with the caret published after it; cancelling
  changes nothing and the opening selection still applies; and a press on inert chrome or the viewport while composing, which
  resigns the focus (C24), **drops the composition uncommitted** (`IM-I`: a field that loses focus while an input method
  composes loses the composition) and ends the edit with the text typed before it, so the marked text is lost, not
  committed. While composing, the field's accessibility value is the committed text only (MetalUI divergence 325;
  AppKit's field editor includes the marked text); a selection written to the `selection:` binding is held back and
  superseded by the commit (divergence 326, `SL-H`), which MetalCreator cannot trigger, since it writes the selection
  only when an edit begins. The second half of the gap is answered too: MetalUI's `docs/testing.md` ("Undo after a
  selection write", `SL-O`) says a written selection ends the open typing group, so ⌘Z removes only the text typed after
  it and restores the written selection; `commandZInTheFieldAfterTheOpeningSelectionRestoresTheTitleAndItsSelection` pins
  it for a title (typing replaces it, ⌘Z brings the old title back all selected, nothing reaches the document).
  Human check C25-7 is now that pin plus a look; C25-3 keeps what only a real input method shows. No MetalCreator
  production code changed.

## Hit by the cross-platform port (xp-1), 2026-10-13

Labelled XP-G3 to XP-G8, plus XP-G9 added by this plan and XP-G10 by the S2 adoption, after the spec's table (`docs/superpowers/specs/2026-10-13-cross-platform-design.md` §5); XP-G1 and XP-G2
(SDL GPU for the viewport, portable compute) belong to xp-3 and are logged there. Checked against MetalUI `fb9a7e42` (the pin in `.github/workflows/xp.yml` is now `ceca59f6`, which has S1 and S2), the commit
`.github/workflows/xp.yml` pins. None of these is worked around in a way MetalUI will have to undo: each stopgap is one switch
(`#if`) or one sentence.

- **XP-G3. A hidden title bar or custom chrome on SDL.** The window opens with `windowStyle: AppLayout.windowStyle`
  (`.hiddenTitleBar`, gap M6-c). SDL ignores it and keeps its system title bar (divergence 276), `titleBarInsets` reads zero and
  `WindowDragHandle` is a no-op there, so `TopBar` sits under the system bar with no clearance to make and nothing to drag.
  Needed: a borderless window with MetalUI-drawn controls and a drag region. **Fixed by MetalUI S1** (record §112, `CW-`, master
  `ceca59f6`) and adopted on branch `xp-adopt-s1`: `.hiddenTitleBar` is a borderless window on SDL, `titleBarInsets` reads a 32-point
  band plus MetalUI's drawn cluster (right 138 on Linux and Windows), `AppLayout.topBarClearance` and `topBarTrailingClearance` pad
  the top bar's content by `.left` and `.right`, and `drawsWindowControls` stays at its default so MetalUI draws the buttons; Close
  goes through `onCloseRequest` (`AppModel.installCloseHandling`). macOS is unchanged (`SDLChromeWindowTests.macLayoutIsWhatItWas`).
  Human checks XP-11..XP-14. The drag works with the real viewport behind the bar since MetalUI S1b (gap XP-G11, fixed).
- **XP-G11. A drag handle above a full-window pointer-taking view gets no SDL drag region.** Fixed by MetalUI S1b (PR #87, master
  `a4ebe288`, ruling CW-V) and adopted on branch `xp-adopt-s1b`. S1's `ChromeRegions.compute` carved the band and each
  `WindowDragGesture` handle by every opaque pointer-taking hitbox in the window with no regard for depth, and MetalCreator's viewport
  fills the window behind the glass bar, so `windowDragRegions` was empty on an SDL-shaped headless window on macOS. Now a hitbox carves a
  handle only if it ranks strictly above the handle's own hitbox (layer, registration index); the title band has no element of its own and
  every blocker carves it except a backdrop (a blocker as wide as the window reaching below the band, which the viewport is). Buttons,
  fields and taps in the bar still carve (divergence 426). Cost, divergence 425 amended: a window-wide pointer-taking view behind the bar
  loses its presses inside the 32-point band to the drag. Nothing in MetalCreator relies on a viewport press there (only the 12-point
  strip above the bar and the side margins show the viewport; the strip was already a window handle by design). The known-issue pins in
  `SDLChromeWindowTests` are removed.
- **XP-G4. Grey pixels and the EXIF orientation of a PNG or JPEG without ImageIO.** Fixed by MetalUI S2 (record §113, `IB-`,
  PR #84, master `dea698ca`) and adopted on branch `adopt-s2`. `GreyImageDecoder` now decodes through `DecodedImage(data:format: .rgba)` on
  every platform (stb_image, the same bytes in as out on macOS, Linux and Windows), then does its own grey conversion and orientation:
  Rec. 709 luminance of the straight-alpha colour composited against black (not S2's `.grey`, which is Rec. 601 with alpha dropped), and
  the EXIF tag from `DecodedImage.orientation` applied while the grey grid is built (no oriented copy of the RGBA). The Image Field works
  off macOS; "Images need a newer MetalUI on this platform.", `ImageProblem.platformUnsupported` and the macOS-only fence are gone, and no
  file in `Sources` imports ImageIO. Measured against ImageIO on every existing fixture before it was removed: PNG grids agree within
  128 of 65,535 (the only moves are 16-bit samples, which S2 rounds to 8 bits); JPEG grids within 441 (under two levels, a colour JPEG:
  stb's IDCT and chroma upsampling are not ImageIO's). Differences to know: MetalUI refuses a PNG with a bad CRC on any chunk (libpng
  tolerated an ancillary one), a side over 16,384 px, and a truncated JPEG, which is stricter than ImageIO and never looser; a 16-bit PNG
  is read to the nearest 1/255 (`aGrey16BitPictureIsReadToTheNearest8BitLevel` replaces the exact-precision test). Peak memory for a legal
  8,192 × 8,192 picture: the 16 MB file, MetalUI's decode (up to 256 MB of RGBA, plus whatever it holds while decoding) and the 128 MB result.
  The 32 MB band survives only as the unit of cancellation checks.
- **XP-G5. Open-document events on SDL.** Answered: `Platform.onOpenURLs` (an SDL drop with window 0) routes to `.onOpenURL`;
  command-line files go through `app.open(…)` after the first window (MetalUI `docs/packaging.md`, "Launch arguments"); the
  `.desktop` file carries `Exec=… %F` and `MimeType=`. Linux and Windows packaging is xp-2, so xp-1 adopts nothing; the
  command-line path already reaches the app the same way (`MetalCreatorApp [file.mcgraph]`).
- **XP-G6. `ContentType` filtering by extension.** Answered (`ContentType("…", conformingTo: [.json], filenameExtensions: ["mcgraph"])`
  in `allowedContentTypes`), and MetalCreator had it already: `mcgraph`, `step`, `stl`, `png`, `jpeg` and `mctheme` declare their
  extensions, because macOS's panels matched them by extension too. `ContentTypeTests` pins each.
- **XP-G7. Clipboard types beyond text.** MetalCreator's graph-fragment clipboard (`NodeClipboard`, ⌘C ⌘V ⌘D on the canvas) is held
  in memory and never reaches the system pasteboard on any platform, so there is nothing to port and nothing lost off macOS. A
  system clipboard is a feature of its own: it would write the fragment as marked JSON text (MetalUI's interim pattern) and move to
  MetalUI S3's custom types when they land. Not an xp-1 task.
- **XP-G8. Hand and zoom cursors.** SDL has no hand or zoom cursor. MetalUI maps the hand to the link cursor, grab to move and zoom
  to the default arrow; the viewport's `ViewportCursor` and the canvas's `CanvasCursor` already go through `PointerStyle`, so they
  take the fallback with no change. MetalUI S4 adds image cursors. Human check XP-8.
- **XP-G9. The headless launch used by CI is SPI.** `SDLPlatform(hiddenWindows:offscreenRenderers:)` is `@_spi(Checks) public`
  (`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`), meant for MetalUI's own checks. `MetalCreatorApp --smoke-test` (Task 7)
  opens the real window on hidden windows and offscreen renderers (Direct3D 12 on WARP on Windows, Mesa software on Linux) and
  exits 0 only after a `.task` ran inside the first frame, which is how CI proves a launch with no display. It uses the SPI because
  MetalUI offers no public way to do that. Needed: a public headless-launch initializer or flag on `SDLPlatform`, so CI does not
  depend on a symbol MetalUI may rename without notice. Until then a MetalUI bump can break `main.swift` at compile time, loudly,
  and the fix is one line. The smoke test passes in CI on Linux and Windows (run 38535917146) (human
  check XP-9).
- **XP-G10. A header-only read of a picture's size and orientation.** `DecodedImage` reports the stored size and the orientation after the
  whole picture is decoded (`IB-C`), but `ImageLimits` (16 MB, 8,192 px a side, PNG and JPEG only) must refuse an oversize picture before
  a pixel is decoded, and the limit is on the oriented size. So `ImageHeader` (`Sources/CreatorNodes/Fields`) reads the PNG IHDR and
  `eXIf` chunk and the JPEG SOF and APP1 segment itself, the one EXIF reader xp-1 hoped not to write; `decode` refuses a picture whose
  decoded size disagrees with it. Needed from MetalUI: a public `ImageInfo(data:)` (format, stored size, orientation) that does no pixel
  work, after which `ImageHeader` goes. To be forwarded to the MetalUI session.
