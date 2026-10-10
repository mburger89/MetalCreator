# MetalUI gaps hit by MetalCreator

MetalUI's design agent reads this file (MetalUI item C7). Each entry gives a concrete use case:
which button or gesture, which coordinates, what we do in the meantime.

## Summary (M7, 2026-10-09)

Every gap in this file, the MetalUI item that owns it and where it stands, checked against MetalUI master `2155f1e`
and its branches.
"Fixed, not adopted" means MetalUI has the API and MetalCreator still runs its stopgap; adopting it is MetalCreator's
work (the owner named). The sections below keep each gap's full use case.

| Gap | What | MetalUI item | Status |
|---|---|---|---|
| 1–5 | Scroll wheel, pinch/rotate, middle and right drags, tap location, cursor and drag modifiers | C7 | ✅ fixed (c62d6ba), adopted by the viewport and the graph panel |
| M4-a | An element's size (`onGeometryChange`), focus on click | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
| M4-b | Opaque helper inside a builder `for`; redraw labels during a camera animation (`TimelineView`) | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
| M5-a | `Slider` `onEditingChanged` | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-b | Hover- or region-scoped key bindings | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
| M5-c | Materials and blur | C10 | ✅ fixed (2155f1e) as a flat tint, adopted by decision (the glass keeps the theme's tint); the backdrop blur is C10-a |
| M5-d | Gradients | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-e | Modifiers on a press | C7 | ✅ fixed (c62d6ba), adopted |
| M5-f | Canvas scroll and pinch | C7 | ✅ fixed (c62d6ba), adopted |
| M5-g | A press elsewhere ends text editing | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
| M5-h | ↑/↓ in a focused single-line field | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
| M5-i | Keyframe animation | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M5-j | `ProgressView` | C10 | ✅ fixed (2155f1e), adopted (Adopt C10) |
| M6-a | Window title and edited marker | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| M6-b | Close and quit veto | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| M6-c | Full-size content view | C8 | 🔄 open: fixed in MetalUI 70e9389 (PR #61) but not adopted; the window keeps its standard title bar until human check AS-5 shows it drags (C8-a) |
| M6-d | Open-document events | C8 | ✅ fixed (MetalUI 70e9389, PR #61), adopted (plan `2026-10-09-adopt-c8`) |
| C8-a | Window drag region for a hidden title bar under a gesture-carrying view | none yet | ⏳ reported to the MetalUI session 2026-10-10, not yet queued; predicted from reading MetalUI, AS-5 not run (it would confirm or refute) |
| M6-e | Public headless test window | item 8 (test harness) | ⏳ queued |
| M6-f | `ColorPicker` | C10 | ✅ fixed (2155f1e), adopted (Themes Task 11) |
| M6 resize cursor | Column/row resize cursor | C7 | ✅ fixed (c62d6ba), adopted |
| VI-a | A dropped gesture's end | C16 | ⏳ queued after C8 and C9 |
| GI-a | Modifiers on a tap | none yet (with S5-a) | ⏳ reported, not queued |
| GI-b | Wheel latching (`CI-AD`) | none yet | ⏳ reported, not queued |
| PERF-a | Shadow re-rasterized and re-blurred every frame its content moves | C13 | 🔄 in progress (`perf/shadow-cache`) |
| PERF-b | Every observed change rebuilds, lays out and paints the whole window | C14 | ⏳ queued; measured by M7 (below) |
| EP-a | Element frame in window coordinates, hover coordinate space, window size | C15 | ⏳ queued after C9 |
| EP-b | Chrome-less point-anchored popover that closes on an outside press | C15 | ⏳ queued after C9 |
| P-a | Third-party notices | C17 | ✅ fixed (67a579e), adopted |
| LF-a | A clip inside an `offset` or uniform `scaleEffect` | C18 | ✅ fixed (0b400b4) |
| LF-b | A clip inside nested flattening effects (LF-a's regression) | C19 | ✅ fixed (9ad2254) |
| TH-a | Menu content can't be evaluated outside MetalUI | none yet (with M6-e) | ⏳ reported, not queued |
| S5-a | Modifiers on a hover (and a tap, GI-a) | none yet (with GI-a) | ⏳ reported, not queued |
| S5-b | No click count on a drag's value (canvas double click) | C16 (with GI-a) | ⏳ reported 2026-10-09 |
| M7-a | `ForEach` identity is an id's description | none yet | ⏳ reported, not queued |
| M7-b | No warm headless frame for measuring | none yet (with M6-e) | ⏳ reported, not queued; used again by C10 (below) |
| C10-a | No backdrop blur behind a material | C10-c (unscheduled) | ⏳ sent to the MetalUI session 2026-10-09 |

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
- **M5-c. No materials or blur** (`.background(.ultraThinMaterial)`, `.blur(radius:)`). Glass panels over the viewport
  need a backdrop blur (spec §6.1). Stopgap: `#21222c` at 86% opacity with the hairline (`GlassPanel`).
  **Fixed by MetalUI C10 lane 3** (2155f1e; `.blur(radius:)` and `Material`, rulings `LK-K`, `LK-L`), **adopted by
  decision, nothing swapped** (Adopt C10 plan Task 5): MetalUI's materials are a flat grey tint fitted to SwiftUI's
  (its divergences 166, 167) with no backdrop blur, and `.blur(radius:)` blurs a view's own pixels, so neither gives
  the spec's glass; and a material's grey is the same in every theme, where `GlassPanel` fills with the theme's `glass`
  role (Dracula's `#21222c` at 86%, editable in the theme editor). `GlassPanel` keeps the theme's tint and the hairline;
  `GlassFillTests` pins it. What spec §6.1 wants, a blur of what is behind the panel, is gap C10-a.
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
  canvas need the modifiers at the press, in the gesture's value. Stopgap: `GraphPanelInput.dragValueModifiers(_:)`
  returns the set `GraphPanelInput.handle(_:)` tracks from `.modifiersChanged`; C7's `DragGesture.Value.modifiers`
  replaces its body. A click's location is `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
- ✅ **Closed by C7 (graph panel, 2026-10-09):** `.onScrollWheel` pans the canvas by the scroll's delta (momentum
  honoured) and ⌘-scroll zooms about `ScrollEvent.location` (`EditorModel.scrolled(by:at:modifiers:phase:)`; a
  trackpad scroll zooms or pans as it began, and a zoom's glide is ignored); `MagnifyGesture` zooms about
  `startLocation` (`EditorModel.pinchChanged`). The +/− keys and the header's zoom buttons stay; the keys' hover veto
  in `AppInput` stays until keys are scoped (M4-a, M5-b).
  **M5-f. Canvas scroll and pinch** (adds to items 1 and 2). Two-finger scroll should pan the graph canvas and
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
  its name and "— Edited". The window keeps its standard title bar (M6-c is open), so AppKit draws the title and the proxy icon.
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
- 🔄 **Fixed in MetalUI 70e9389 (PR #61, rulings AS-E, AS-F, AS-J), not adopted:** `windowStyle: .hiddenTitleBar` is
  held back (plan Task 4b) until human check AS-5 shows the window drags by its top bar (gap C8-a predicts it doesn't).
  `TopBar` already pads its content by `AppLayout.topBarClearance(titleBarInsets:)` (`AppRoot` reads
  `@Environment(\.titleBarInsets)`); the inset is zero in a standard window. To adopt: run AS-5 with the
  `windowStyle: .hiddenTitleBar` argument added in `Sources/MetalCreatorApp/main.swift`, record the result, then commit it.
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
- **GI-b. No wheel latching, met by a canvas pan's glide** (MetalUI `CI-AD`, stated, not built). A flick that pans
  the graph canvas glides on through momentum events, and MetalUI sends each to whatever is under the pointer at that
  event. If the pointer drifts off the canvas mid-glide, the canvas stops and the rest of the glide scrolls the node
  library's list or the inspector, if the pointer is over one (the viewport ignores momentum, and the graph panel's
  chrome claims every scroll). Stopgap: none. Wanted: `CI-AD`'s latch (a scroll gesture's events, momentum included,
  go to the element under its `.began`). Human check GI-1 records what happens.
- **VI-a, met again.** The canvas's pinch keeps its start in `EditorModel` too, so a pinch that changes at another
  centre while one is under way, or finds the canvas moved since that one's last change, ends it first
  (`aPinchThatLostItsEndDoesntPullTheNextOneBack`, `aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince`); a lost
  pinch end followed by a pinch at the same centre, with nothing moving the canvas between, zooms from the lost
  pinch's start. A canvas press already drops a press that lost its release (`EditorModel.ensurePress`), its
  modifiers with it (`aLostPressTakesItsModifiersWithIt`).

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
  view costs about the budget, about 0.5 ms a node rebuilt, so canvas culling (which brought panning well inside the
  budget) can't help there; MetalCreator's level of detail (no rows below half zoom) takes about a third off such a
  frame, and what is left is MetalUI's rebuild of nodes that didn't change. Both verdicts are not judged yet (the
  recorded run was not idle); a miss on an idle run waits for C14.

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
  pinch over the palette does nothing: the palette is the pinch's target (`CI-D`) and nothing on its chain takes a
  pinch (`PaletteDock` is drawn beside the graph panel and the viewport, not inside them), so it stays open. Wanted: a chrome-less popover style (SwiftUI's
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
- **M7-b. No warm headless frame to measure.** Spec §7.3's targets are measured headless
  (`Tests/CreatorAppTests/Bench`, docs/verification/performance.md). The only public way to draw the app's window
  without a screen is `renderFrame`, which draws a fresh window's first frame each call: no state table, text
  shaping cache or raster cache survives to the next, so every number is a cold-frame upper bound. PERF-a and PERF-b
  were measured with a warm frame loop and a headless `Window`, but those need `@testable import MetalUI` and aren't
  checked in. Stopgap: cold frames, labelled as an upper bound. Wanted, as one request with M6-e: a public headless
  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,
  including the display link's pacing.

## Used again by the C10 adoption, 2026-10-09

- **M6-e and M7-b, used again.** The C10 adoption's two animations can be seen only at rest from a test: `renderFrame`
  draws one frame at time zero with a fresh animation store, and a `Frame`'s timestamp and `AnimationStore` are
  internal. The refusal shake's motion is tested through the public `KeyframeTimeline` at injected times, the
  spinner's through its still frame, and what a real window does (the shake running on a new refusal, the spinner
  turning, a slider's `onEditingChanged` pairing) is human checks C10-2 to C10-4. Stopgap: none beyond that. Wanted,
  with M6-e: a public headless window, or `renderFrame` taking a timestamp and returning its animation store, so a
  test can tick a `keyframeAnimator` and a `ProgressView` and press a `Slider`.

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

## Hit by adopting C8 (app shell), 2026-10-09

Labelled C8-a… so they don't clash with the labels above. Checked against MetalUI `70e9389`.

- **C8-a. No window-drag region for a hidden title bar under a gesture-carrying view.** With
  `windowStyle: .hiddenTitleBar` MetalUI drags the window from a press in the title-bar band only when nothing claims
  the press: no opaque hitbox and no gesture arena (ruling AS-J, `Window.answerUnclaimedTitleBarPress`).
  MetalCreator's viewport fills the whole window (spec §6.1) and carries gestures over all of it
  (`ViewportView+Parts`: a `SpatialTapGesture`, three `DragGesture`s and a `MagnifyGesture`), so every press in the
  band, including one on the empty glass of the top bar (glass only paints, divergence 141), forms an arena, and the
  window can't be dragged by its top bar. Found by reading MetalUI 70e9389; human check AS-5 confirms or refutes it.
  Stopgap: none (a claiming view over the band would not drag the window either, and the viewport stays full-bleed).
  Until AS-5 shows otherwise the window keeps its standard title bar (plan Task 4b: the one `windowStyle:` line is not
  merged; the top bar's clearance code stays, it is zero in a standard window), and M6-c stays open.
  Wanted: a way to mark a region as the window's drag handle that wins over the gestures beneath it, as SwiftUI's
  `WindowDragGesture` / `.windowBackgroundDragBehavior(.enabled)` (macOS 15) or a `.windowDragArea()` modifier; the
  top bar's glass would carry it.
