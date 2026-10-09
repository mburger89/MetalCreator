# MetalUI gaps hit by MetalCreator

MetalUI's design agent reads this file (MetalUI item C7). Each entry gives a concrete use case:
which button or gesture, which coordinates, what we do in the meantime.

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
are closed for the viewport, and gaps 4 and 5 below with them. The graph panel's adoption (M5-e, M5-f and the
canvas's share of items 1 and 2) is a later plan; the viewport's keys still wait for key scoping (M4-a, MetalUI C9).

The provisional names, as the MetalUI session reported them on 2026-10-08 (all kept: C7's design phase probed
SwiftUI, and where SwiftUI has a spelling MetalUI took it). MetalCreator wraps each stopgap that is left (the graph
panel's, in `GraphPanelInput`) behind one function/modifier of its own, named after these, so the swap is local.

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
- **M5-c. No materials or blur** (`.background(.ultraThinMaterial)`, `.blur(radius:)`). Glass panels over the viewport
  need a backdrop blur (spec §6.1). Stopgap: `#21222c` at 86% opacity with the hairline (`GlassPanel`).
- **M5-d. No gradients.** The window background is a `#3a3d4e` → `#191a21` vertical gradient (spec §6.6). Stopgap:
  solid `#191a21`.
- **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete). Shift-click and ⇧/⌥-drag on the
  canvas need the modifiers at the press, in the gesture's value. Stopgap: `GraphPanelInput.dragValueModifiers(_:)`
  returns the set `GraphPanelInput.handle(_:)` tracks from `.modifiersChanged`; C7's `DragGesture.Value.modifiers`
  replaces its body. A click's location is `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
- **M5-f. Canvas scroll and pinch** (adds to items 1 and 2). Two-finger scroll should pan the graph canvas and
  ⌘-scroll or pinch should zoom about the pointer (the `location` in the canvas's local points). Stopgap: drag on empty
  canvas pans; +/− keys and the header buttons zoom about the pointer (`EditorModel.zoom(in:)`). With M4's viewport
  in the same window, M4's window-wide keymap takes `=`/`+`/`-` before `onInput` (gap M4-a), so M6 needs a key context.
- **M5-g. A press elsewhere never clears text focus** (focus-by-click is deliberately not MetalUI policy,
  `Window.focus(_:)` docs). After editing an inspector field, the field keeps Delete, ⌘C/⌘V/⌘Z and Space while the
  user clicks nodes, so the graph's keys stop working with no visible cause. Stopgap: the canvas gesture calls
  `GraphPanelInput.releaseTextFocus` (`window.focus(nil)`) at the start of each press. A SwiftUI-like rule (a press on
  non-focusable content resigns the field), or a `.focusable(false)`-style "clears focus" modifier, would fix it.
- **M5-h. A focused single-line field claims ↑/↓** (mac: caret to start/end, `TextEditing.key`) before the raw key
  bubble and `onInput`. The add-node palette needs ↑/↓ to move its highlight while its search field is focused.
  Stopgap: `GraphPanelInput.keymap` binds `up`/`down` to `PaletteMove`, and `handleAction` runs it only while the
  palette is open (the keymap stage precedes field keys). SwiftUI's `onKeyPress` on the field would fix it.
- **M5-i. No keyframe animation.** The refused-wire "brief shake" (spec §6.2) wants a back-and-forth keyframe
  animation. Stopgap: the node's offset jumps 6 pt and springs back (`.animation(.spring(duration:bounce:), value:)`).
- **M5-j. No `ProgressView` or indeterminate spinner.** The node status badge shows a spinner while the node evaluates
  (spec §6.2). MetalUI has no activity indicator. Stopgap: a static `◌` glyph (`StatusBadge.text(for:)`). Wanted:
  `ProgressView()` (indeterminate, small control size) or a `TimelineView(.animation)` to rotate a glyph.

## Hit by M6 (app shell), 2026-10-09

Labelled M6-a… so they don't clash with the C7 items 1–5, M4-a… or M5-a…

- **M6-a. No window title API.** The title is fixed by `App.openWindow(title:…)`. `PlatformWindow.title` is settable,
  but `Window` doesn't expose it, and there's no represented file or edited marker (AppKit's `representedURL` and
  `isDocumentEdited`). The app wants "bracket.mcgraph — Edited" in the title bar. Stopgap: the glass top bar shows the
  name and "— Edited"; the native title stays "MetalCreator". Wanted: a settable `Window.title` and an edited marker,
  or SwiftUI's `.navigationTitle` / `.navigationDocument(_:)`.
- **M6-b. No close or quit interception.** Closing the window, or ⌘Q, ends the app at once, so it can't ask whether
  to save (AppKit: `windowShouldClose(_:)`, `applicationShouldTerminate(_:)`; SwiftUI document apps get it from
  `DocumentGroup`). Stopgap: none. New and Open ask before discarding unsaved changes; close and quit don't. Wanted: a
  window-close veto and an app terminate hook that can show an alert first.
- **M6-c. No full-size content view.** Spec §6.1 draws the glass top bar under the traffic lights (AppKit
  `.fullSizeContentView` with a transparent title bar; SwiftUI `.windowStyle(.hiddenTitleBar)`). Stopgap: the top bar
  sits below the standard title bar.
- **M6-d. No open-document events.** Finder double-click, `open -a`, dropping a file on the Dock icon and Open Recent
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
- **M6-f. No colour picker.** The Themes milestone after M6 (roadmap) edits a custom theme's colours role by role,
  which wants SwiftUI's `ColorPicker(_:selection:supportsOpacity:)`: a colour well that opens the system colour panel
  (AppKit `NSColorWell`/`NSColorPanel`), with opacity. MetalUI has none. M6 doesn't need it: its three built-in themes
  are read-only and chosen from View ▸ Theme. Stopgap, if the Themes milestone comes first: a hex `TextField` per role,
  refused plainly when it isn't a colour. Wanted: `ColorPicker` over MetalUI's `Color`.
**Being fixed by MetalUI C10
  lane 1** (`feat/controls-looks`: `ColorPicker(_:selection:supportsOpacity:)` and its drawn panel, rulings `LK-C`,
  `LK-D`, `LK-P`). The Themes plan (`2026-10-09-themes-editor.md`) adopts it in its last task once C10 is merged; until
  then the editor shows each role's hex and a swatch, and colours change only by import, with no hex-field stopgap.
- **M4-a and M5-b, used again by M6.** The viewport's F, + and − carry the `!Panel` key context, and the graph panel
  and the inspector contribute `Panel` from a MetalUI `Stack` wrapper, so a focused field types them. With nothing
  focused they are window-wide. Over the graph canvas `AppInput.handleAction` declines + and − by reading the
  canvas's hover state, so the graph's own + and − zoom it (as M5-b does for Tab); F has no graph binding and still
  frames the viewport. A key context contributed while an element
  is hovered, or `onKeyPress` on a region, would replace both vetoes. C7 (`feat/input-apis`) doesn't include it.
- **Cursor for the dock's resize edge** (adds to C7 item 5). The graph panel's inner edge is a drag handle and should
  show a column or row resize cursor. C7's `PointerStyle` has `.columnResize` and `.rowResize` (decision `CI-H`).
  Adopt them when C7 merges.

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
  pinch over the palette reaches what is under it, where nothing takes a pinch yet (gap 2). Wanted: a chrome-less popover style (SwiftUI's
  `.presentationBackground(.clear)` / a plain `popoverStyle`) with a point anchor (`attachmentAnchor: .point(_:)`),
  or an outside-press callback for an overlay.

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
- **M6-d, now visible.** The packaged app declares `.mcgraph` (owner, exported type), so a double-click in Finder
  opens MetalCreator, but not the file: no open-document event reaches the app (human check P2).

## Hit by the Themes milestone, 2026-10-09

Labelled TH-a… so they don't clash with the labels above. Checked against MetalUI `67a579e`.

- **TH-a. Menu content can't be evaluated outside MetalUI.** View ▸ Theme is built from the store each time it
  opens (the built-ins, a divider, the custom themes, a divider, Edit Themes…), and a test should check what it lists,
  which item is checked, and that choosing one runs its action. `MenuContent`'s only requirement is SPI and
  `MenuNode` is internal (`MN-D` item 1), so a client test can't read a `CommandMenu`'s or a `Menu`'s items. Stopgap:
  `ThemeMenu.sections(_:)` returns the themes it lists, which `ThemeMenuTests` checks; the builder only turns them into
  items. Wanted: a public read-only evaluation of menu content (titles, enabled, `isOn`, shortcut, and a way to run an
  item), or one in a test-support product (with M6-e's headless window).
