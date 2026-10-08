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

Nothing landed or designed yet; C7 is next after MetalUI's C4. Names below are provisional (C7's design phase
probes SwiftUI and may rule otherwise; where SwiftUI has a spelling, MetalUI takes it). MetalCreator wraps each
stopgap behind one function/modifier of its own, named after these, so the swap is local.

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

- **Gap 5 (C7 item 5, now concrete): modifiers during a drag.** Shift-drag pans and ⌥-drag zooms the viewport (spec §9).
   `DragGesture.Value` has no modifiers. Stopgap: `ViewportModifierTracker` follows `.modifiersChanged` through a
   chained `Window.onInput`. Wanted: `DragGesture.Value.modifiers` (the modifiers held at each change, including at the press).
   Known limit: `held` modifiers can go stale if Shift is released while the window is inactive.
- **Gap 4 (C7 item 4, now concrete): context-menu location.** The face menu must know which face was under the
   secondary press: the press point in the element's local points. Stopgap: the last `onContinuousHover` point
   (`ViewportModel.contextMenuItems()` reads the hovered pick). The model re-picks at the last pointer point whenever
   the camera moves under a still pointer (drag release, key zoom, projection switch, end of a view-cube or Look At
   animation) or the scene is replaced (`refreshHover()`). It's still wrong if the pointer moved without a hover
   event since. Wanted: the opening location passed to the `.contextMenu` builder, or `SpatialTapGesture` for secondary clicks.
- **Gap 1 (C7 item 1): scroll-wheel zoom toward the cursor.** Not available. Stopgaps: ⌥-drag and the +/− keys
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
     can't follow a camera animation. They're hidden while one runs. Wanted: `TimelineView(.animation)`, or a per-frame
     rebuild hook for elements above a continuous surface.

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
