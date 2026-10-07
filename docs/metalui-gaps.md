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
