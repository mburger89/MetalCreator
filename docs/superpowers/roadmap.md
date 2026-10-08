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
| M4 | Viewport on MetalUI `MetalView`: shaded/edge/ID passes, camera, view cube, picking, context menu, handles | ✅ code merged; human checks V pending | M2; MetalUI C7 for final input bindings (stopgaps until then) |
| M5 | Graph panel on MetalUI: canvas, both docks, palette, context inspector | ✅ code merged; human checks M5 pending | M1; node inspector specs from M3 |
| M6 | App shell + acceptance demo (§7.2 bracket, STEP/STL export) | ✅ code merged; human checks M6 pending | M3, M4, M5 |
| Themes | Custom colour themes (spec §6.6, Errata (M6)): duplicate, edit, rename and delete them (the built-ins stay read-only); export and import `.mctheme` files, a small versioned JSON of hex colours by role (missing roles fall back to Dracula, unknown roles are ignored, a bad hex is refused plainly, e.g. "‘selection’ isn’t a colour like #ff79c6."), stored in `~/Library/Application Support/MetalCreator/Themes/`; the selected theme remembered in preferences (a `ThemePreferences` over the user's defaults). Themes stay app-level, never in `.mcgraph`. Also map roles onto MetalUI's control tokens (`.theme(_:)`) | ⏳ after M6 | M6's `CreatorStyle` (`ColorTheme`, `ThemeColors`, `ThemeStore`); MetalUI gap M6-f (no colour picker) |
| M7 | Measure §7.3 targets, finish `docs/metalui-gaps.md`, CLAUDE.md | ⏳ after M6 | M6 |

## Later sub-projects

| # | Item | Status | Notes |
|---|---|---|---|
| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ⏳ ready to plan (handoff: notes/2026-10-08-sketcher-s1-s2-handoff.md); S5 after S4 | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
| 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
| 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
| — | Packaging: bundle OCCT dylibs into a signed `.app` | ⏳ after M6 | Spec §11 |
| — | C7 adoption: swap the viewport's, the graph panel's and the app's input stopgaps for MetalUI C7's APIs once `feat/input-apis` merges (lists in the carry-over note, From M4, From M5, From M6) | 🔒 MetalUI C7 | MetalUI decisions file `docs/superpowers/2026-10-08-input-apis-decisions.md` |
| — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ⏳ after M6 | `BracketAcceptanceTests+PolygonSwap` (flip its expectations when fixed) |
| — | Viewport: a selected rule's edges over the Final part — in Final preview, show the edges of a selected rule whose solid isn't shown (spec §6.3, Errata (M6)) | ⏳ after M6 | `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid` |
| — | Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3) | ⏳ after M6 | carry-over From M6 |

## Cross-project dependencies

| Item | Owner | Status |
|---|---|---|
| MetalUI C7 "Input API gaps for MetalCreator" (scroll, pinch/rotate, middle/right drag, tap location, cursor + drag modifiers) | MetalUI session | 🔄 in verification (2026-10-08); started 2026-10-08 on MetalUI branch feat/input-apis; renames of the provisional names (docs/metalui-gaps.md) will be flagged in MetalUI docs/superpowers/2026-10-08-input-apis-decisions.md (prefix CI-). MetalUI now also has `.task`/`.task(id:)` |
| MetalUI C8 app shell: M6-b close/quit veto (first), M6-a title + edited marker, M6-c hidden title bar, M6-d open-document events | MetalUI session | ⏳ queued 2026-10-08, after C7 |
| MetalUI C9 key and focus scoping: M4-a/M5-b hover- or region-scoped keys + element size, M5-g press ends editing, M5-h ↑/↓ in fields, M4-b redraw during animation | MetalUI session | ⏳ queued 2026-10-08, after C7 |
| MetalUI C10 controls and looks: M6-f ColorPicker (needed by Themes), M5-a Slider onEditingChanged, M5-c blur, M5-d gradients, M5-i keyframes, M5-j ProgressView | MetalUI session | ⏳ queued 2026-10-08 |
| MetalUI public test harness (item 8): M6-e headless Window + simulateInput | MetalUI session | ⏳ queued 2026-10-08, after C7 |

## Carry-over items with a milestone

- ✅ Before M3: Edges-by-Tag subset matching; Edges by Direction `abs(dot)` + `kind == .line`; Edge Set Op dedupe; Loft segment-count message; warn on `.unnamed` picks; multi-solid boolean warning.
- ✅ Before M4: edge polylines from `BRep_Tool::PolygonOnTriangulation`; mesh determinism across calls.
- ✅ M6: window input is installed once through `AppInput` (forwarding to the current document);
  `GraphPanelInput.install(on:)` is only for GraphPanelPreview. Also done: `releaseTextFocus` on viewport presses; give M4's viewport
  keymap bindings a key context (gap M4-a), because window-wide `=`/`+`/`-` bindings run before `onInput` and take the graph's zoom keys; place `GraphPanel` per `EditorModel.dock`,
  `GraphShowButton` while hidden, and `InspectorPanel` on the right over the viewport; consume
  `EditorModel.inspectorRequest` for "Pick edges in view…" (write the picks as `.edgePicks(…)` under `NodeSetting.picks`);
  pass the real `BuiltInNodes.registry`. Deferred to M6 from spec §6.1/§6.2:
  resizing the docked panel along its inner edge, and the Preview menu (Final / Selected node →
  `document.previewNode`).
- M7: measure 50-node pan/zoom (CanvasLayers is the hot path; add viewport culling there if
  it misses 60 fps). `oriented()` cost; OCCTKernel on the default executor; per-item calls under the global lock.
