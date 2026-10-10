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
| Polish | Editor polish: the add-node palette floats over the window at the pointer (flipping at the edges); a node library ("Nodes") in the graph panel, shown by default, click or drag to add (plan `2026-10-08-editor-polish.md`, Errata (editor polish)) | ✅ code done; human checks EP pending | M5, M6 |
| Themes | Custom colour themes (spec §6.6, Errata (M6)): duplicate, edit, rename and delete them (the built-ins stay read-only); export and import `.mctheme` files, a small versioned JSON of hex colours by role (missing roles fall back to Dracula, unknown roles are ignored, a bad hex is refused plainly, e.g. "‘selection’ isn’t a colour like #ff79c6."), stored in `~/Library/Application Support/MetalCreator/Themes/`; the selected theme remembered in preferences (a `ThemePreferences` over the user's defaults). Themes stay app-level, never in `.mcgraph`. Also map roles onto MetalUI's control tokens (`.theme(_:)`) | ✅ code done, including Task 11's `ColorPicker` (MetalUI C10); human checks TH pending | M6's `CreatorStyle` (`ColorTheme`, `ThemeColors`, `ThemeStore`); MetalUI gap M6-f (no colour picker) |
| M7 | Measure §7.3 targets, finish `docs/metalui-gaps.md`, CLAUDE.md (plan `2026-10-09-m7-measure.md`) | ✅ numbers recorded in `docs/verification/performance.md` (`scripts/bench.sh`): pan, fillet drag and orbit with the panel hidden met; zooming the 50-node graph out (with level of detail) and orbiting with the panel shown not judged yet: the recorded run was not idle, so they await an idle re-run, and a miss there waits for MetalUI C14 (PERF-b); canvas culling and level of detail added; human checks M7 pending | M6 |

## Later sub-projects

| # | Item | Status | Notes |
|---|---|---|---|
| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5a (editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve; plan `2026-10-09-sketcher-s5-editor.md`) ✅ code done, human checks S5 pending; S5b (trim/extend/fillet/mirror/pattern tools, 3-point arcs, tangent and point-on inference with glyphs, double-click to edit; plan `2026-10-09-sketcher-s5b.md`) ✅ code done, human checks S5b pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) ⏳ | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
| 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
| 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
| — | Groups: model and evaluation (C1) — group definitions saved in the file (format 5), group nodes through `NodeRegistry.makeNode`, a definition's graph evaluated per instance under scoped node IDs (tags stay put per instance and across definition edits), Group / Ungroup / Make Unique and definition edits as single undo steps, ⌘G / ⇧⌘G on the top level (spec `2026-10-09-selection-groups-comments-design.md` §4–§5, plan `2026-10-09-groups-core.md`, Errata (C1)) | ✅ code done | Multi-select (A); comments (B) add their keys under format 5 |
| — | Groups: editor (C2) — the group node's look, entering a group (double-click, ⌘↓, Edit Group), breadcrumbs and ⌘↑, per-level pan and zoom, Group Input/Output + sockets, the group inspector, the library's Groups section, the viewport inside a group (spec §6; a pick made there is written relative to the level shown, as `GroupScopes.identity` names it), the clipboard carrying the definitions pasted group nodes use, merged by content (spec §9), and inner node states from `DocumentModel.innerResults` | ⏳ after C1 | MetalUI gap GI-a (canvas double-click, synthesised until MetalUI C16) |
| — | Packaging: bundle OCCT dylibs into a signed `.app` | ✅ code done; human checks P pending | Spec §11, Errata (Packaging); `scripts/package-app.sh`, `docs/packaging.md`. Ad hoc by default, Developer ID via `METALCREATOR_SIGN_IDENTITY`; notarization is manual; no icon yet; needs macOS 27 while Homebrew's bottles do; MetalUI gap P-a fixed (MetalUI 67a579e; its notices are bundled) |
| — | C7 adoption: swap the viewport's, the graph panel's and the app's input stopgaps for MetalUI C7's APIs once `feat/input-apis` merges (lists in the carry-over note, From M4, From M5, From M6) | ✅ viewport (human checks VC pass); graph panel and app ✅ merged 2026-10-09 (human checks GI pending) | MetalUI decisions file `docs/superpowers/2026-10-08-input-apis-decisions.md` |
| — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer's failure was the invalid-blends row, now done), `BracketAcceptanceTests+MergedFaces` |
| — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)) | ✅ code done (plan `2026-10-09-kernel-invalid-blends.md`, Errata (Kernel: invalid blends)): every fillet and chamfer result is checked (`OCCTShape.isValid`); one OCCT's checker rejects is refused, naming the largest size that works ("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."); repair was probed (ShapeFix, UnifySameDomain, tolerances, fillet shapes and parameters, edge order) and can't make it valid | `BracketAcceptanceTests+PolygonSwap` (flipped: the Fillet names 2.5 mm; at 2.5 mm the Chamfer and the Output have their part), `InvalidBlendTests`, `ShapeValidityTests` |
| — | Kernel: largest size for blends OCCT can't build — a fillet or chamfer OCCT reports not done still says "can't be rounded this much" without a maximum (spec §3, risks table: "the maximum radius where possible"); `OCCTKernel.largestValidBlend` could name one there too, at the cost of up to ~20 failing tries | ⏳ | `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` (its `maxRadius` would become 9.9) |
| — | Naming: face picks on merged faces — a `FacePick` (Plane from Face) on a face a union merged names both operands' tags and matches nothing once they stop merging; narrow it like `EdgeKey.narrowed` (it has no other side, so it needs its own rule). Also not narrowed yet: an edge pick between a merged face and a third operand's face (a hole through a merged plate+flange side), since the hole wall's tags share no origin with the merged side | 💬 | Errata (naming: merged faces) |
| — | Viewport: a selected rule's edges over the Final part — in Final preview, show the edges of a selected rule whose solid isn't shown (spec §6.3, Errata (M6)) | ⏳ after M6 | `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid` |
| — | Adopt MetalUI C10 (merged as MetalUI 2155f1e): `Slider` `onEditingChanged` for the inspector's coalescing (M5-a), materials and blur for the glass panels (M5-c), the window gradient (M5-d), the refused wire's keyframe shake (M5-i), `ProgressView` for the evaluating badge (M5-j); `ColorPicker` (M6-f) is already adopted (Themes Task 11) | ✅ code done (plan `2026-10-09-adopt-c10.md`): M5-a, M5-d, M5-i and M5-j adopted; M5-c decided, the glass keeps the theme's flat tint because materials are a fitted grey with no backdrop blur and `.blur` blurs a view's own pixels (the backdrop blur is gap C10-a); human checks C10 pending | docs/metalui-gaps.md summary table |
| — | Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3) | ✅ merged 2026-10-09 (human checks VC pending; the arrows, cube and pointer-less key zoom keep it there) | carry-over From M6 |
| — | Multi-select polish (A): ⌘-click toggles, box select (a plain drag replaces, ⇧ adds, ⌘ toggles; the middle button pans), ⌘A, Esc, arrow nudge, F frames the graph's selection, drags and ⌥-drags of the whole selection, on a `CanvasSelection` comments join (spec `2026-10-09-selection-groups-comments-design.md` §3, Errata (A: multi-select); plan `2026-10-09-multi-select.md`) | ✅ code done; human checks MS pending | Unblocks Comments (B) and Groups (C1, C2) |

## Cross-project dependencies

| Item | Owner | Status |
|---|---|---|
| MetalUI C7 "Input API gaps for MetalCreator" (scroll, pinch/rotate, middle/right drag, tap location, cursor + drag modifiers) | MetalUI session | ✅ merged as MetalUI c62d6ba (PR #56), 2026-10-09; final names in MetalUI `docs/superpowers/2026-10-08-input-apis-decisions.md` (CI-A…CI-AL). Adopted by the viewport; graph panel and app still to adopt |
| MetalUI C8 app shell: M6-b close/quit veto (first), M6-a title + edited marker, M6-c hidden title bar, M6-d open-document events | MetalUI session | 🔄 in progress since 2026-10-09 (close/quit veto first) |
| MetalUI C9 key and focus scoping: M4-a/M5-b hover- or region-scoped keys + element size, M5-g press ends editing, M5-h ↑/↓ in fields, M4-b redraw during animation | MetalUI session | 🔄 in progress since 2026-10-09; also onGeometryChange, the for-loop builder fix (M4-b; until then `ForEach` works), TimelineView, focus-on-click |
| MetalUI C10 controls and looks: M6-f ColorPicker (needed by Themes), M5-a Slider onEditingChanged, M5-c blur, M5-d gradients, M5-i keyframes, M5-j ProgressView | MetalUI session | ✅ merged 2155f1e (PR #59); ColorPicker adopted by Themes Task 11, the rest by the row "Adopt MetalUI C10" |
| MetalUI C10-c backdrop blur for materials, over a GPU surface (gap C10-a) | MetalUI session | ⏳ unscheduled (deferred in MetalUI `LK-A`) |
| MetalUI public test harness (item 8): M6-e headless Window + simulateInput | MetalUI session | ⏳ queued 2026-10-08, after C7 |
| MetalUI C13/C14 performance: PERF-a translation-free shadow cache + portable fast blur (no vImage: MetalUI imports nothing), PERF-b rebuild only what changed | MetalUI session | C13 🔄 in progress on MetalUI `perf/shadow-cache` (2026-10-09: rulings PF-A…PF-L, lane 1's red tests); C14 ⏳ queued 2026-10-08. M7 measured C14's share (`docs/verification/performance.md`): zooming the 50-node graph out and orbiting with the panel shown wait for it if an idle run still misses (verdicts not judged yet) |
| MetalUI C18/C19 clips: LF-a a clip inside a flattening effect, LF-b its nested regression | MetalUI session | ✅ merged as MetalUI 0b400b4 (C18) and 9ad2254 (C19) |
| MetalUI C15 editor overlays: EP-a frames/hover in window coordinates, window size; EP-b a chrome-less point-anchored popover that closes on any outside press | MetalUI session | ⏳ after C9 |
| MetalUI C16 cancellation: VI-a dropped drags and pinches, lost scroll ends (`.cancelled` on resign) | MetalUI session | ⏳ after C8 and C9 |
| MetalUI C17 third-party notices: P-a | MetalUI session | ✅ merged as MetalUI 67a579e (PR #57); bundled by `scripts/package-app.sh` |

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
- ✅ M7: measure 50-node pan/zoom (CanvasLayers is the hot path; add viewport culling there if
  it misses 60 fps). `oriented()` cost; OCCTKernel on the default executor; per-item calls under the global lock.
  Done (`docs/verification/performance.md`): the canvas culls, which brings panning inside the budget; `oriented()`,
  the default executor and the per-item lock and hop are each too small to change.
