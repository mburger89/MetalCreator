# MetalCreator roadmap — the todo list

The single list of everything left to build. The binding spec is
`docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; deferred review items live in
`docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`. Each milestone goes plan → review → subagent-driven
execution → final review → merge.

Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (reason given) · 💬 needs a design conversation

## Vertical slice (sub-projects 1–5)

| # | Item | Status | Depends on |
|---|---|---|---|
| M0 | OCCT probe: shim, box, fillet, STEP/STL | ✅ | — |
| M1 | Graph engine: values, broadcasting, evaluator, undo, `.mcgraph`, `DocumentModel` | ✅ | — |
| M2 | OCCT kernel: all operations, tags through history, conformance + naming stability | ✅ | M0, M1 |
| M3 | The 26 nodes (values, profiles, solids, selection rules, fillet/chamfer, output) | ✅ | M2 |
| M4 | Viewport on MetalUI `MetalView`: shaded/edge/ID passes, camera, view cube, picking, context menu, handles | 🔄 code done; human checks V pending | M2; MetalUI C7 for final input bindings (stopgaps until then) |
| M5 | Graph panel on MetalUI: canvas, both docks, palette, context inspector | 🔄 code done; human checks M5 pending | M1; node inspector specs from M3 |
| M6 | App shell + acceptance demo (§7.2 bracket, STEP/STL export) | ⏳ after M3–M5 | M3, M4, M5 |
| M7 | Measure §7.3 targets, finish `docs/metalui-gaps.md`, CLAUDE.md | ⏳ after M6 | M6 |

## Later sub-projects

| # | Item | Status | Notes |
|---|---|---|---|
| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 💬 | Needs its own brainstorm → spec with the user ("both from the start"); solver can be built in parallel with M3–M6 |
| 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
| 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
| — | Packaging: bundle OCCT dylibs into a signed `.app` | ⏳ after M6 | Spec §11 |

## Cross-project dependencies

| Item | Owner | Status |
|---|---|---|
| MetalUI C7 "Input API gaps for MetalCreator" (scroll, pinch/rotate, middle/right drag, tap location, cursor + drag modifiers) | MetalUI session | 🔄 started 2026-10-08 on MetalUI branch feat/input-apis; renames of the provisional names (docs/metalui-gaps.md) will be flagged in MetalUI docs/superpowers/2026-10-08-input-apis-decisions.md (prefix CI-). MetalUI now also has `.task`/`.task(id:)` |

## Carry-over items with a milestone

- ✅ Before M3: Edges-by-Tag subset matching; Edges by Direction `abs(dot)` + `kind == .line`; Edge Set Op dedupe; Loft segment-count message; warn on `.unnamed` picks; multi-solid boolean warning.
- ✅ Before M4: edge polylines from `BRep_Tool::PolygonOnTriangulation`; mesh determinism across calls.
- M6: install the graph's input with `GraphPanelInput.install(on:)` (it chains `onInput`/`onAction` and appends its
  keymap). Only its `onInput` side composes with M4's `ViewportModifierTracker.install(on:)` in either order: set the
  viewport's keymap and `onAction` (which M4's harness assigns directly) before `install(on:)`, or append and chain
  them the same way, or the palette's ↑/↓ bindings and `handleAction` are dropped. Call `releaseTextFocus` on viewport
  presses too; give M4's viewport keymap bindings a key context (gap M4-a), because window-wide `=`/`+`/`-` bindings run
  before `onInput` and take the graph's zoom keys; place `GraphPanel` per `EditorModel.dock`,
  `GraphShowButton` while hidden, and `InspectorPanel` on the right over the viewport; consume
  `EditorModel.inspectorRequest` for "Pick edges in view…" (write the picks as `.edgePicks(…)` under `NodeSetting.picks`);
  pass the real `BuiltInNodes.registry`. Deferred to M6 from spec §6.1/§6.2:
  resizing the docked panel along its inner edge, and the Preview menu (Final / Selected node →
  `document.previewNode`). M7: measure 50-node pan/zoom (CanvasLayers is the hot path; add viewport culling there if
  it misses 60 fps).
- M7: `oriented()` cost; OCCTKernel on the default executor; per-item calls under the global lock.
