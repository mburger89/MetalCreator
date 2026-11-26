# CreatorSketchEditor

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
  sketch being edited, its live solve (`solve(_:dragging:)` per drag step), the tool and its stroke, the selection, and
  the inspector's rows; it is the viewport's `ViewportTool` (planar navigation; F frames the sketch) and builds its
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport, with the inference glyphs'
  `InferenceChip`; both are as wide as their measured text: `readoutChip(measuring:)`, `inferenceChip(measuring:)`). The command tools (Trim, Extend, Fillet, Mirror, Pattern) run `SketchCommands` on a click and show
  a refused command's message as `refusal`; their settings are `SketchToolOptions`. A click within the pick radius of
  a curve (not a point) holds a new point on it (point-on); a line leaving an arc's end snaps tangent; ⌘ suppresses
  both, never a shared point. Project (P) declines the plane click and takes the viewport's pick: the host resolves it
  (`events.projection`) into `ProjectionCandidate`s, each becomes a fixed `.projected` entity with a reference `edgeN`, and
  the commit's `projections` carry the picks to store. The overlay also carries a fill per closed region
  (`RegionTriangulator`, found again only when the sketch changes) and each dimension drawn as an ANSI
  dimension (`SketchDimensionDrawing`; a double-click on its text opens the value box). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  The Spline tool (S, `SketchEditorModel+Spline`): clicks add fit points, Return, Esc or a click on the last point finishes; a selected spline shows its fit points and, per point, a tangent and a curvature knob (dragging one activates it, `Sketch.activateHandles(for:)`, and the solve moves only that handle's columns), the inspector's Release returns a handle to automatic (refused while a Tangent or Curvature uses it) and its Curvature button adds the G2 constraint. A plain click on a fit point of a selected spline swaps the spline for the point, so Delete takes only the point (`handleSplines` keeps the knobs shown; ⇧ keeps both selected). Trim, Extend and Fillet refuse a spline; Mirror and Pattern copy it (handle vectors take the transform's linear part).
  Depends on CreatorSketch, CreatorViewport, CreatorKernel (Project's `EdgePick`), CreatorGeometry, CreatorStyle and
  MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, P, S (Spline), X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
  key because F frames the sketch), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
  nodes (the graph's selection is the Sketch node being edited). The toolbar is a `ViewThatFits` over rows that move tools into a "More" menu from the end (`SketchToolbarRow`), and every key is an invisible button outside it (`SketchToolbarKeys`), since an unchosen row registers no shortcut and a closed menu item's is display only; the visible buttons carry none. Tests: `swift test --filter CreatorSketchEditorTests`.
