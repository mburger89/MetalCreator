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
| M5 | Graph panel on MetalUI: canvas, both docks, palette, context inspector | 📝 plan ready for review (…-m5-graph-panel.md); runs after M4 | M1; node inspector specs from M3 |
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
- M7: `oriented()` cost; OCCTKernel on the default executor; per-item calls under the global lock.
