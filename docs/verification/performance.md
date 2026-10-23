# Performance — spec §7.3, measured

Spec §7.3 asks for three targets, "measured, not just asserted". This file records the numbers against each, how they
were taken, and who owns each miss. Re-measure with `scripts/bench.sh` after any change to drawing, the canvas, the
viewport or the kernel, and replace the numbers here (keep the machine, load and commits with them).

## How to run

```sh
scripts/bench.sh                      # every benchmark: about 10 minutes, most of it the release build
scripts/bench.sh GraphPanZoomBench    # one suite (also OrbitBench, FilletDragBench, KernelBench, BlendRefusalBench, PatternBench, FieldBench)
scripts/preview-sweep.sh              # the preview triangle cap sweep (PreviewSweepBench); about a minute after the build, on an idle Mac
```

The benchmarks are Swift Testing suites in `Tests/CreatorAppTests/Bench`. A plain `swift test` skips them
(`.enabled(if: Bench.isRequested)`); `scripts/bench.sh` sets `METALCREATOR_BENCH=1` and builds with `-c release`,
because a debug build of MetalUI draws about 45× slower (docs/metalui-gaps.md PERF-a). A benchmark run in a debug build
records an issue instead of printing numbers. They print `BENCH …` lines and assert no time, so they can't flake. Run
them on an otherwise idle Mac: the script prints the machine and its load average before and after.

## Method

Each benchmark drives the real app model (`AppModel`, its `EditorModel` and `ViewportModel`) the way input does, then
draws the frame headless:

- **model**: the step itself (a canvas transform, an orbit drag step, a handle value) and `AppModel.settle()`, which
  waits for any evaluation, the scene refresh and the meshes.
- **window-cpu (cold frame)**: the whole window built, laid out and painted by MetalUI (`renderFrame` over `AppRoot`, 1440 × 900
  points at scale 2, the graph panel docked left at its default size). This is the work a pan, a zoom or an orbit
  causes in the app: each changes observed state, and MetalUI rebuilds the whole window on every observed change
  (gap PERF-b).
- **gpu**: MetalUI's renderer compositing that scene into an offscreen texture, plus (orbit and fillet drag) the
  viewport's own Metal pass (`ViewportRenderer`), each committed and waited for.
- **command-to-frame** (fillet drag): from the handle's value change to both GPU passes done.

Medians are judged against the budget: 16.67 ms a frame for 60 fps, 100 ms for the fillet drag. The first 10 frames
of a run are warm-up and not counted (the drag counts every step: each is a new value).

What headless can't show, so the numbers are an upper bound for the CPU and a lower bound for latency:

- The **cold** rows (`renderFrame` draws a fresh window's first frame every time: no text shaping cache, raster cache,
  retained `Frame` or state table survives between frames). A real window keeps them, so its CPU frame is cheaper. The
  **warm** rows below measure that. MetalUI's own warm-loop figures for the 20-node bracket are in PERF-b (12–13 ms release with
  nothing moving).
- A real window overlaps a frame's GPU work with the next frame's build, so its frame time is about the larger of CPU
  and GPU, not their sum; here they run one after the other.
- No display link: the fillet drag's command-to-frame leaves out waiting for the next vsync (up to 16.7 ms more).

## Warm interaction rows (judge the 16.67 ms budget here)

The `window-cpu` rows above time a **cold frame**: `BenchRenderer.windowScene` calls `renderFrame`, which builds a fresh
`Frame` every call, so MetalUI's retained skip and graft (C14b, C14b-2, C14-c, C14b-3) can never pay off. That is the
cost of a first frame (window open, resize, theme switch), and until 2026-10-20 it was what the 60 fps budget was judged
on. Steady interaction (an orbit, a pan, a zoom, a drag) is **warm**: the window and its `Frame` live across the steps.
A work-count bisect (`FrameWork` per orbit step, graph panel docked left) found 332 element requests per warm frame
against 4,572 per cold frame.

So each interaction bench has a `-warm` row: `WarmBenchWindow` keeps one `TestWindow` over `AppWindowRoot` alive, the step
is applied (a drag step, a canvas transform, a handle value), `settle()` waits, and the frame redrawn by the window
(`setNeedsRedraw` then `tick`) is timed alone. The first 10 steps are warm-up, the rest are counted (100 orbit steps,
120 pan or zoom steps, 65 fillet steps). Each row also prints `element-requests` per frame. The cold rows stay as the
reference for a first frame. The CPU side only: the GPU rows are unchanged, and a real window overlaps them with the next
build. `WarmWorkPinTests` pins the work of a steady warm orbit-panel-left step with no timing, in plain `swift test`: no
ineligible replay, no redo, no rasterized pixel, and fewer than 2 x 332 element requests.

**Relative numbers only.** These were taken on a heavily loaded Mac (load averages 60.24 / 52.00 / 70.37 before and
18.67 / 40.21 / 60.24 after; idle means all three under 3), so the absolute milliseconds are inflated and no verdict
here is final. Final judged numbers come from the next idle window.

2026-10-20, MacBook Pro (MacBookPro18,2), macOS 27.0.1, branch `warm-bench` before the `.equatable()` panels:

```text
BENCH orbit-panel-left window-cpu (cold frame): median 29.89 ms, p95 33.17 ms, max 41.81 ms (n 100); budget 16.67 ms: missed
BENCH orbit-panel-left-warm window-cpu (warm frame): median 7.67 ms, p95 9.31 ms, max 10.09 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-left-warm: element requests per frame, median 332, max 332
BENCH orbit-panel-hidden window-cpu (cold frame): median 2.61 ms, p95 3.00 ms, max 3.17 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden-warm window-cpu (warm frame): median 1.99 ms, p95 2.01 ms, max 2.04 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden-warm: element requests per frame, median 161, max 161
BENCH pan-50 window-cpu (cold frame): median 25.16 ms, p95 28.62 ms, max 30.57 ms (n 120); budget 16.67 ms: missed
BENCH pan-50-warm window-cpu (warm frame): median 14.11 ms, p95 22.23 ms, max 27.70 ms (n 120); budget 16.67 ms: met
BENCH pan-50-warm: element requests per frame, median 1409, max 1697
BENCH zoom-50 window-cpu (cold frame): median 29.18 ms, p95 34.58 ms, max 36.32 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50-warm window-cpu (warm frame): median 25.23 ms, p95 38.22 ms, max 49.90 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50-warm: element requests per frame, median 1857, max 2879
BENCH fillet-drag window-cpu (cold frame): median 31.52 ms, p95 33.01 ms, max 98.77 ms (n 75)
BENCH fillet-drag-warm window-cpu (warm frame): median 21.57 ms, p95 22.54 ms, max 23.33 ms (n 65)
BENCH fillet-drag-warm: element requests per frame, median 888, max 888
```

After Task B (the panels `.equatable()`: `GraphPanel`, `GraphPanelBody`, `GraphCanvas`, `CanvasSurface`, `NodeLibraryView`,
`InspectorPanel`; MetalUI C14-d), same Mac, **load averages 14.61 / 18.23 / 39.50 before and 59.48 / 35.62 / 40.83 after**
(other sessions started builds during the run; the milliseconds below are noisier than the first run's, and their
distribution tails are load, not the code). Element requests are deterministic and are the comparison to trust:

```text
BENCH orbit-panel-left-warm: element requests per frame, median 222, max 222
BENCH orbit-panel-left-warm window-cpu (warm frame): median 9.21 ms, p95 36.36 ms, max 125.77 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden-warm: element requests per frame, median 161, max 161
BENCH orbit-panel-hidden-warm window-cpu (warm frame): median 2.21 ms, p95 12.94 ms, max 71.44 ms (n 100); budget 16.67 ms: met
BENCH pan-50-warm: element requests per frame, median 1409, max 1697
BENCH pan-50-warm window-cpu (warm frame): median 22.65 ms, p95 39.21 ms, max 59.32 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50-warm: element requests per frame, median 1857, max 2879
BENCH zoom-50-warm window-cpu (warm frame): median 63.71 ms, p95 154.41 ms, max 247.35 ms (n 120); budget 16.67 ms: missed
BENCH fillet-drag-warm: element requests per frame, median 888, max 888
BENCH fillet-drag-warm window-cpu (warm frame): median 26.01 ms, p95 33.18 ms, max 40.11 ms (n 65)
```

The panels cut a warm orbit-panel-left step from 332 to 222 element requests. Pan, zoom and the fillet drag are unchanged in
requests (1409, 1857, 888): a pan or zoom writes the document's `ViewState` and a fillet drag changes the scene, and
neither is something a panel can skip. Pan and zoom rebuild most of the canvas each step (the transform is read by
every node view); that, not the panels, is what their warm figures are made of. `GraphPanel`'s `onGeometryChange` records a
`geometryChange` ineligible reason each frame when it is `.equatable()` (about 23 more element requests in the orbit step than
without it: 222 against 199), which MetalUI may be able to clear. The call-site `.equatable()` on `GraphPanel(...)` is
therefore dropped (`GraphPanel` keeps its `==` and `Equatable`); the warm orbit-panel-left step now measures
`BENCH orbit-panel-left-warm: element requests per frame, median 199, max 199`. The pan, zoom and fillet-drag medians above are over the
judged budget in these loaded runs and are **not judged**; the idle re-run decides them.

**Final judged numbers come from the next idle window** (all three load averages under 3); none of the figures in this
section are final.

## Results

Figures in this file that did not come from one controlled run (the same machine, load and commit for both sides of a
comparison) are labelled as such where they appear. They are indicative only. The 2026-10-13 run below is the first
near-idle one; the 2026-10-09 table is kept for comparison.

2026-10-09, MacBook Pro (MacBookPro18,2, Apple M1 Max, 10 cores), macOS 27.0.1, MetalUI `2155f1e`, MetalCreator
`71ec6fc` (branch `m7-measure`). Load averages (1, 5, 15 minutes) 22.54 / 33.70 / 58.73 before the run and 11.92 / 26.99 / 53.35
after: **not idle** (other worktrees were building and testing in parallel; idle means all three under 3, before and
after). So the zoom-50 and orbit-panel-left verdicts, which sit within a millisecond or two of the budget, are **not
judged**: the medians are kept, to be judged on an idle machine. The other verdicts are far from their budgets and hold
at any load.

| §7.3 target | Benchmark | Measured (median, p95) | Budget | Verdict | A miss belongs to |
|---|---|---|---|---|---|
| Panning a 50-node graph at 60 fps | `pan-50` | CPU 13.09 ms (p95 14.79), GPU 3.25 ms; the canvas builds 16 of 50 nodes (max 20) | 16.67 ms | **Met** (with canvas culling; 26.63 ms without it is from a separate run at a different load, so not a controlled comparison) | — |
| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 15.03 ms (p95 17.56, max 36.06), GPU 3.38 ms; 25 of 50 nodes built (all 50 zoomed out), with level of detail | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median under the budget, p95 over; 26.53 ms without culling and level of detail is from a separate run at a different load, so not a controlled comparison) | MetalUI C14 (PERF-b), if it misses on an idle run |
| Fillet radius drag: viewport updated within 100 ms of each value change | `fillet-drag` | command-to-frame 43.14 ms (p95 45.59): evaluate + mesh 20.44 ms, window CPU 16.91 ms, GPU 5.44 ms; 75 of 75 steps showed a new part | 100 ms | **Met** | — |
| Orbiting the bracket at 60 fps | `orbit-panel-left` | CPU 16.01 ms (p95 17.70), GPU 5.11 ms | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median at the budget's edge, p95 over): each orbit step rebuilds the graph panel too | MetalUI C14 (PERF-b), if it misses on an idle run |
| (the same, graph panel hidden) | `orbit-panel-hidden` | CPU 1.98 ms (p95 2.13), GPU 2.06 ms | 16.67 ms | **Met** | — |

### What MetalCreator changed

- **Canvas culling** (`EditorModel.drawnNodes`, `drawnCanvasRect`, `CanvasLayers`): the canvas builds only the nodes
  and wires whose frames meet the visible canvas grown by `EditorModel.cullingMargin` (160 points) on every side.
  Panning the 50-node graph went from 26.63 ms to 13.09 ms of CPU a frame (runs minutes apart, both loaded; the
  second at load 10.55 / 26.20 / 52.76 before). Hit testing, selection and every edit still see the whole graph;
  culling is drawing only. A window resize reaches the canvas as the panel's `onGeometryChange` reports its new frame
  (`EditorModel.panelPlacement`, gap EP-a), so what a bigger window uncovers is drawn at once.
- **Level of detail** (`EditorModel.drawsNodeRows`, `rowsMinimumZoom` = 0.5): zoomed out below half size, nodes are
  drawn without their rows, whose text is too small to read there. Zoomed out, culling can't help (every node is in
  view), so this is MetalCreator's lever on the zoom target. From the M7 plan's probe, not re-measured on this branch:
  all 50 nodes in view at zoom 0.25, alternating frames with and without rows in one release run (so both saw the same
  load, 1-minute load 61): 28.82 ms with rows, 19.02 ms without, 34% less; the frame's glyphs drop from 2,151 to 971. Re-measure it on an
  idle machine with `CanvasLayers` passing every node's rows (one uncommitted line) if the zoom verdict is close.
- **Every node draws** (`CanvasLayers` keys nodes by their whole UUID): MetalUI's `ForEach` names an element by its
  id's description and drops a repeat (gap M7-a), and a `NodeID` prints only its first 8 hex digits, so two nodes whose
  IDs began alike drew as one.

### Why the open verdicts are MetalUI's to fix

MetalCreator decides how big a view tree the canvas builds, and has cut it twice: culling (only what is in view)
and level of detail (no rows when zoomed out). What is left is a node's header, body, border and sockets for every
node in view, the least a node can be drawn with. The model step is 0.10 ms for a pan or zoom step (0.01 ms for an
orbit step), and building each node view's inputs about 0.01 ms (PERF-b's 0.19 ms for 20 nodes). The rest is MetalUI
rebuilding, laying out and painting the whole window on every observed change, whether or not the view's inputs
changed. With the panel hidden an orbit frame costs 1.98 ms; with it shown, 16.01 ms, though nothing on the panel
changed; MetalCreator can't tell MetalUI to skip the unchanged panel (PERF-b's request). If either verdict is a miss
on an idle run, it waits for MetalUI C14-b (PERF-b: rebuild only what changed; slice 1, which skips unchanged content getters, is
adopted); its entry cites this file. Both are
judged on the 2026-10-13 run below.

**C14 slice 1 adopted (plan `2026-10-13-adopt-c14`).** The canvas's node, wire and comment views skip their
`content` getter while their value is unchanged (gap PERF-b), which saves the getters of every node that did not change
in a drag step or a camera change; the build recursion, prepaint and paint still run whole (C14-b). The counts are pinned
by `CanvasContentSkipWindowTests` (a drag move evaluates one node and its wires and skips the rest). C14-c (MetalUI `41a2180f`) adopted: the selection box, the one canvas view that read `@Environment`, is skipped too while its rect and the theme are unchanged; nothing timed.

**C14b-3 adopted (MetalUI `711ab9c4`, record §121):** reading control state no longer counts as a write, so unfocused fields, unscrolled scroll views and unmoved lists no longer make an `.equatable()` subtree ineligible; timings come in the quiet window.

### Idle re-time after C14 slice 1 (2026-10-13)

2026-10-13, MacBook Pro (MacBookPro18,2, Apple M1 Max, 10 cores), macOS 27.0.1, MetalUI `e85cb07a` (C14 slice 1; C14b is not in
this checkout), MetalCreator `d734684` (master). `scripts/bench.sh`, every suite, release build. Load averages (1, 5, 15 minutes)
2.32 / 4.61 / 6.49 before the run and 2.22 / 3.89 / 5.94 after. **Near idle, not idle by this file's rule** (all three under 3):
the 1-minute load was under 3 but the 5- and 15-minute averages were not, because the release build ran just before (the load
fell from 8.62 to 2.32 in the two minutes waited). Nothing else was started by this session. Full log: `.build/bench.log`.

| §7.3 target | Benchmark | 2026-10-09 (loaded) | 2026-10-13 (median, p95) | Budget | Verdict |
|---|---|---|---|---|---|
| Panning a 50-node graph at 60 fps | `pan-50` | CPU 13.09 ms, GPU 3.25 ms | CPU 17.05 ms (p95 18.33), GPU 4.07 ms; 16 of 50 nodes built (max 20) | 16.67 ms | **Missed** (CPU; GPU met). It was Met on the loaded run and is slower now |
| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 15.03 ms (not judged), GPU 3.38 ms | CPU 18.64 ms (p95 21.48, max 23.73), GPU 4.49 ms; 25 of 50 built | 16.67 ms | **Missed** (CPU; GPU met) |
| Fillet radius drag, within 100 ms | `fillet-drag` | command-to-frame 43.14 ms: evaluate + mesh 20.44, window CPU 16.91, GPU 5.44 | command-to-frame 54.77 ms (p95 58.79): evaluate + mesh 25.38, window CPU 21.96 (p95 24.65), GPU 7.05; 75 of 75 steps showed a new part | 100 ms | **Met** |
| Orbiting the bracket at 60 fps | `orbit-panel-left` | CPU 16.01 ms (not judged), GPU 5.11 ms | CPU 20.56 ms (p95 21.97), GPU 5.73 ms; 19 of 20 nodes built | 16.67 ms | **Missed** (CPU; GPU met) |
| (the same, graph panel hidden) | `orbit-panel-hidden` | CPU 1.98 ms, GPU 2.06 ms | CPU 1.84 ms (p95 2.01), GPU 2.17 ms | 16.67 ms | **Met** |

**Three rows miss their budget on the near-idle run, and the two that were Met on the loaded run (`pan-50`) or at its edge
(`orbit-panel-left`) now miss too.** Every window-cpu figure here is higher than the 2026-10-09 one (pan +3.96 ms, zoom +3.61
ms, orbit +4.55 ms, fillet-drag +5.05 ms), though the model step is unchanged (0.10 ms, 0.10 ms, 0.01 ms) and the first run was
the heavily loaded one. So C14 slice 1 did not make the window CPU frame cheaper in this measurement, and the two runs differ
in more than that commit (MetalUI `2155f1e` against `e85cb07a`, MetalCreator `71ec6fc` on `m7-measure` against master
`d734684`, the fields and pattern work between them), so this run does not say whether slice 1 helped or what raised the frames.
The panel-hidden orbit frame is unchanged (1.84 ms), which again puts the cost in the panel's rebuild, painting and layout. The
three misses are MetalUI's, C14-b (PERF-b: rebuild only what changed); the entry cites this file. The 5- and 15-minute loads were
above 3 for this run, so a run with all three under 3 could move the figures; a 4 ms gap against a load that low is not
expected to close.

The same run's other rows:

| Row | 2026-10-13 (median, p95) | Budget | Verdict |
|---|---|---|---|
| `pan-50` model / window-gpu | 0.10 ms / GPU 4.07 ms (p95 5.13) | 16.67 ms (GPU) | GPU **Met** |
| `kernel-bracket re-evaluation` (Width 60 to 90, wall) | 54.86 ms (was 46.91 ms) | none | recorded |
| `kernel-main-actor gap` | 0.01 ms, max 0.10 ms (n 45,745) | 16.67 ms | **Met** |
| `kernel-extrude`, `-revolve`, `-loft` | 0.48 ms, 0.48 ms, 2.09 ms | none | recorded |
| `kernel-lock`, `kernel-hop` | 0.74 ms per 100,000 calls, 0.94 ms per 100 calls | none | recorded |

### Quiet-window idle run (2026-10-20)

2026-10-20, MacBook Pro (MacBookPro18,2, Apple M1 Max, 10 cores), macOS 27.0.1, MetalCreator `5e4069e` (master), MetalUI `711ab9c4`
(C14b-2, P3, C14-c and C14b-3 adopted). MetalUI had paused its builds for the window. Release builds through `scripts/bench.sh`, one
suite at a time. The release build ran first and the Mac was left until all three load averages were under 3 (it took about 35 minutes
after the builds), then each suite started with all three under 3, except FieldBench, whose 1-minute load was 2.78 and the rest under 3
too (so **idle by this file's rule at the start of every suite**). The loads after a suite include the suite's own work.

| Suite | Load before (1, 5, 15 min) | Load after |
|---|---|---|
| preview sweep (`xp-preview-sweep`, merged with master) | 1.63 / 2.20 / 2.98 | 2.17 / 2.32 / 2.85 |
| GraphPanZoomBench | 2.21 / 2.33 / 2.85 | 2.02 / 2.28 / 2.82 |
| OrbitBench | 2.02 / 2.28 / 2.82 | 1.87 / 2.23 / 2.80 |
| FilletDragBench | 1.87 / 2.23 / 2.80 | 1.81 / 2.21 / 2.78 |
| ImplicitBench (i-1 to i-7, which includes IL-0) | 1.74 / 2.19 / 2.77 | 2.92 / 2.40 / 2.74 |
| FieldBench | 2.78 / 2.39 / 2.73 | 3.69 / 2.62 / 2.81 |

**Pan, zoom, orbit and fillet drag (re-time after MetalUI C14b-2, P3, C14-c, C14b-3).**

| §7.3 target | Benchmark | 2026-10-13 (near idle) | 2026-10-20 (idle; median, p95) | Budget | Verdict |
|---|---|---|---|---|---|
| Panning a 50-node graph at 60 fps | `pan-50` | CPU 17.05 ms (p95 18.33), GPU 4.07 ms | CPU 21.35 ms (p95 24.11), GPU 4.47 ms (p95 5.12); 16 of 50 nodes built (max 20) | 16.67 ms | **Missed** (CPU; GPU met) |
| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 18.64 ms (p95 21.48), GPU 4.49 ms | CPU 24.45 ms (p95 28.55), GPU 4.73 ms (p95 5.34); 25 of 50 built (max 50) | 16.67 ms | **Missed** (CPU; GPU met) |
| Orbiting the bracket at 60 fps | `orbit-panel-left` | CPU 20.56 ms (p95 21.97), GPU 5.73 ms | CPU 25.80 ms (p95 26.61), GPU 6.55 ms (p95 6.93); 19 of 20 nodes built | 16.67 ms | **Missed** (CPU; GPU met) |
| (the same, graph panel hidden) | `orbit-panel-hidden` | CPU 1.84 ms, GPU 2.17 ms | CPU 1.96 ms (p95 2.07), GPU 2.19 ms (p95 2.65) | 16.67 ms | **Met** |
| Fillet radius drag, within 100 ms | `fillet-drag` | command-to-frame 54.77 ms (p95 58.79) | command-to-frame 60.15 ms (p95 62.94, max 134.41): evaluate + mesh 25.30 ms, window CPU 27.27 ms (p95 29.47), GPU 7.17 ms; 75 of 75 steps showed a new part | 100 ms | **Met** |

The idle numbers are higher than 2026-10-13's for every row whose window includes the graph panel (pan +4.30 ms, zoom +5.81 ms, orbit
+5.24 ms, fillet-drag window CPU +5.31 ms), with the model step unchanged (0.12, 0.11 and 0.01 ms) and the panel-hidden orbit frame
unchanged (1.96 ms). So the three adopted MetalUI changes did not bring these rows under budget in this measurement; the cost is still
the panel's rebuild, layout and painting, and the misses stay with MetalUI C14-b. The two runs differ in more than those adoptions
(MetalCreator `d734684` against `5e4069e`, MetalUI `e85cb07a` against `711ab9c4`, and the pattern, field and implicit work between), so this run does not say
which change raised the frames. Not investigated during the window.

**Implicit (IL-0 included).** `scripts/bench.sh ImplicitBench` on the 100 mm gyroid cell (`ImplicitBenchFixtures.cellSize` 100); the
50 mm fallback was not needed, because i-4's peak memory was 0.94 GB against 4 GB (the 19.6 million triangle, 3 GB estimate was high).

| Row | Measured (median) | Budget | Verdict |
|---|---|---|---|
| i-1 first preview pass, warm | 13.31 ms (p95 13.74; cold, shaders compiled: 22.13 ms) | 1000 ms | **Met** |
| i-2 thickness edit | 8.37 ms (p95 12.12) | 100 ms | **Met** |
| i-1m first pass at 0.78 mm | GPU mesher 12.76 ms, CPU mesher over the GPU's values 58.00 ms; 323,808 triangles from each | recorded | n/a |
| i-3 To Implicit of the bracket | 281.66 ms (p95 287.21) | 500 ms | **Met** |
| i-4 export to STL, 0.1 mm | 18.60 s (n 1); peak memory 0.94 GB; file 1008 MB | 60 s, 4 GB | **Met** (both) |
| i-4b 3MF export | 36.48 s; file 177 MB from 1436 MB of model XML; process peak so far 1.81 GB | recorded | n/a |
| i-4z 4794 MB Zip64 entry | 22.38 s; `unzip -t` exit 0, no errors | valid | **Met** |
| i-5 decimate 2,097,152 triangles | 6.84 s (p95 6.86); 2,097,152 to 290,730 triangles | 10 s | **Met** |
| i-6 Mesh to Solid, 100,000 triangles | 14.06 s (p95 14.09), 100,000 faces | 15 s | **Met** (6% headroom; the nearest row to its budget) |
| i-7 trapped-volume fill | 28,094,464 cells, 1 void, 4.23 s; peak resident 2,261 MB (2,261 MB before the grid: the process holds earlier rows) | recorded | n/a |

IL-0 is satisfied by this run (the rows i-1 to i-4 are in budget with the 100 mm cell). The earlier non-idle ImplicitBench figures in the
Implicit section below are superseded by these.

**Fields.** `scripts/bench.sh FieldBench`:

| Row | Measured (median, p95) | Budget | Verdict |
|---|---|---|---|
| field-1 five nodes x 10,000 points | 0.71 ms (0.71) | 5 ms | **Met** |
| field-2 signed distance to a plate x 10,000 points, first (OCCT) | 73.14 ms (73.85) | 100 ms | **Met** (27% headroom) |
| field-2 cached | 0.20 ms (0.21) | recorded | n/a |
| field-2b smooth loft x 10,000 points | 860.41 ms (865.68) | recorded | n/a |
| field-3 Field Scatter, about 2,000 points | 45.84 ms (46.17) | 50 ms | **Met** (8% headroom; still the row nearest its budget) |
| field-3b Sample Field + Cull by Field x 2,000 | 0.34 ms (0.35) | 50 ms | **Met** |
| field-4c first tint (kernel) | 179.66 ms (n 1) | recorded | n/a |
| field-4 edit to a tinted bracket (Remap) | 37.44 ms (38.17; max 290.55) | 150 ms | **Met** |
| field-4b edit to a tinted bracket (Radial Gradient) | 40.23 ms (41.44) | 150 ms | **Met** |

The raw lines of all of these are under Raw output.

### Preview triangle cap sweep (2026-10-20)

Decision (user, 2026-10-20): 1M, spec erratum D19.

`scripts/preview-sweep.sh` (Errata D15) on branch `xp-preview-sweep`, after `git merge master` (master `5e4069e`, MetalUI `711ab9c4`), release build,
load 1.63 / 2.20 / 2.98 before and 2.17 / 2.32 / 2.85 after. The merge changed `ImplicitBenchFixtures` to build a TPMS gyroid, which broke
the sweep's fixture; the sweep keeps the noise sheet it was calibrated on (a copy of the old builder in `PreviewSweepFixtures`), so the
rungs are comparable to the ladder's design. The rules: (a) GPU p95 of an orbit frame, graph panel shown, at most 8 ms; (b) window CPU p95
within 1 ms of the smallest rung; (c) footprint added at most 1 GB; (d) GPU mesh at most 1 s.

| Rung | Triangles | Voxel | GPU p95, shown / hidden | Window CPU p95 (vs smallest rung) | Footprint added | GPU mesh (CPU mesh) | Footprint at once / settled | Result |
|---|---|---|---|---|---|---|---|---|
| 1 (0.25M) | 324,604 | 1.90 mm | 7.02 / 3.70 ms | 16.57 ms (0.00) | 91 MB | 17.05 ms (48.88) | 561 / 153 MB | **PASS** |
| 2 (0.5M) | 570,700 | 1.55 mm | 7.55 / 3.58 ms | 16.88 ms (+0.31) | 160 MB | 22.54 ms (83.06) | 814 / 300 MB | **PASS** |
| 3 (1M) | 1,039,236 | 1.22 mm | **9.31** / 4.42 ms | 16.67 ms (+0.09) | 302 MB | 24.68 ms (149.73) | 1240 / 538 MB | **FAIL** (a) |
| 4 (2M) | 1,979,960 | 0.93 mm | **11.14** / 5.72 ms | 17.48 ms (+0.91) | 589 MB | 35.92 ms (292.21) | 2109 / 1022 MB | **FAIL** (a) |
| 5 (4M) | 4,060,684 | 0.65 mm | **10.77** / **8.59** ms | 17.02 ms (+0.45) | **1196 MB** | 65.32 ms (636.99) | 3906 / 1986 MB | **FAIL** (a, c) |
| 6 (8M) | 8,083,708 | 0.46 mm | **13.96** / **13.87** ms | 16.48 ms (-0.09) | **2329 MB** | 113.40 ms (1386.79) | 6439 / 2743 MB | **FAIL** (a, c) |

**Cap candidate: 570,700 triangles (rung 2, the last rung before the first failure).** Rung 3 misses only (a), by 1.31 ms (9.31 ms against
8 ms); the other three rules hold through rung 4, and the window CPU rule (b) and the mesh rule (d) hold at every rung. Each rung's mesh
has n 3 for the mesh timings and n 60 for the frame timings, so the p95 of the mesh rows is a max of three. The graph-panel-shown
GPU p95 is above the panel-hidden one by 2.4 to 3.3 ms up to 2M and converges above that, where the viewport pass dominates. Process peak
resident was 5.11 GB. `PreviewSchedule.maximumTriangles` is **not** changed; the decision is the owner's.

### P4 adopted: raster overscan (MetalUI 679f5d7d, 2026-10-20)

MetalUI P4 (raster overscan for shadows, blurs and gradients; pooled rasterizer scratch) replaced the pin 711ab9c4 with 679f5d7d. It
has no API change, and no MetalCreator code changed. The warm benches (`OrbitBench`, `GraphPanZoomBench`, `FilletDragBench`; release)
were run against both MetalUI commits with the same temporary instrumentation, which printed every `FrameWork` counter per timed
warm frame (the committed benches print only `elementRequests`). Median per frame, then the worst frame:

| Row | elementRequests | rasterizedPixels | newTextures | newTexturePixels |
| --- | --- | --- | --- | --- |
| fillet-drag-warm | 888 / 888 | 0 / 0 | 0 / 0 | 0 / 0 |
| pan-50-warm | 1409 / 1697 | 0 / 5,618 | 0 / 1 | 0 / 5,618 |
| zoom-50-warm | 1857 / 2,879 | 13,289 / 24,767 | 16 / 28 | 14,454 / 23,195 |
| orbit-panel-left-warm | 199 / 199 | 0 / 0 | 0 / 0 | 0 / 0 |
| orbit-panel-hidden-warm | 161 / 161 | 0 / 0 | 0 / 0 | 0 / 0 |

These values are identical at 711ab9c4 and 679f5d7d. So are the other counters (`blurredPixels` 0 everywhere, `elementPrepaints`,
`elementPaints`, `contentEvaluations`, `contentSkips`, `retained*`, `rects`, `glyphs`, `images`). The one difference is the worst
frame's `atlasUploadPixels` on fillet-drag-warm: 338 at 711ab9c4, 26,416 at 679f5d7d (median 0 in both). P4 does not lower the
warm raster work of these scenes: the 50-node zoom still re-rasterizes about 13,000 px a frame.

Window-CPU medians (indicative only; the Mac was loaded, load averages before/after: P4 13.53 30.01 25.78 / 5.94 21.15 22.89,
711 5.94 21.15 22.89 / 6.42 14.57 19.67; P4 ran first):

| Row | 711ab9c4 ms | 679f5d7d ms |
| --- | --- | --- |
| fillet-drag cold | 30.26 | 31.06 |
| fillet-drag-warm | 21.99 | 21.85 |
| pan-50 cold | 24.40 | 24.38 |
| pan-50-warm | 13.01 | 13.08 |
| zoom-50 cold | 29.53 | 28.07 |
| zoom-50-warm | 25.00 | 23.64 |
| orbit-panel-left cold | 31.62 | 30.36 |
| orbit-panel-left-warm | 6.27 | 6.10 |
| orbit-panel-hidden cold | 2.36 | 2.31 |
| orbit-panel-hidden-warm | 1.92 | 1.88 |

The cold rows use `BenchRenderer`, which does not expose `FrameWork`, so they have times only.

### C14-d adopted (MetalUI 99b21a1c, PR #104, 2026-10-20)

MetalUI's C14-d makes the `.equatable()` Component the retention unit, replays an `.equatable()` occurrence that moved through
layout or a scroll/offset shifted (whole device pixels; rects, glyphs and images only), counts what refuses translation by name in
`FrameWork.retainedTranslationRefusedReasons`, and lets a graft under comparable custom environment keys hit
(`METALUI_RETAINED_TRANSLATION=0` turns the layout translation off for an A/B). What MetalCreator did for it:

- **The per-node view was already the retention unit.** `NodeView` (and `CommentFrameView`, `StickyView`, `WireView`, the header, rows,
  badge and socket layer inside it) are `.equatable()` with all inputs by value (`NodeViewEqualityTests`), so there was nothing to
  convert; the new window tests pin it (`aWarmPanEvaluatesNoNodeView`, `changingOneNodeEvaluatesExactlyThatNodeView`).
- **The pan state is split out of `ViewState`.** `DocumentModel` held the file's `ViewState` as one observable value, so a pan (which
  writes the canvas offset and zoom) invalidated `GraphPanelBody`, which reads `dock` and `showsLibrary`. It now holds `dock`,
  `canvasOffset`, `canvasZoom`, `camera`, `homeCamera` and `showsLibrary` as separate observable properties, and `viewState`
  assembles them for the file. `ViewState` itself, its coding keys and the file encoding are unchanged
  (`ViewStateEncodingTests`: an old view state re-encodes to its own bytes; a document opened on a file saves that file's bytes).
  A pan now evaluates one view (the surface), was two (the surface and the `GraphPanelBody` shell).

Same Mac (MacBookPro18,2), release, `scripts/bench.sh Warm`. "Before" is this repository at master with MetalUI already at 99b21a1c
(the counter printing is the only change); "after" adds the split. **The machine was not idle** (load averages 54.18 / 45.47 / 25.13
before the first run, 38.18 / 43.19 / 30.52 before the second), so milliseconds are noisy; the counters are deterministic and are
the comparison to trust. Counters are per frame, median / max over the timed warm frames.

| Row | | elementRequests | elementPrepaints | elementPaints | rasterizedPixels | contentEvaluations | window-cpu median |
|---|---|---|---|---|---|---|---|
| pan-50-warm | before | 1409 / 1697 | 1494 / 1800 | 247 / 615 | 0 / 5618 | 2 / 34 | 24.59 ms |
| | after | 1409 / 1697 | 1494 / 1800 | 247 / 615 | 0 / 5618 | 1 / 33 | 13.44 to 14.65 ms |
| zoom-50-warm | before | 1857 / 2879 | 1999 / 3094 | 2391 / 3815 | 13289 / 24767 | 2 / 122 | 39.27 ms |
| | after | 1857 / 2879 | 1999 / 3094 | 2383 / 3815 | 13289 / 24767 | 1 / 121 | 26.05 ms |
| orbit-panel-left-warm | before | 199 / 199 | 184 / 184 | 213 / 213 | 0 / 0 | 0 / 0 | 7.35 ms |
| | after | 199 / 199 | 184 / 184 | 213 / 213 | 0 / 0 | 0 / 0 | 6.75 ms |
| fillet-drag-warm | before | 888 / 888 | 966 / 966 | 1138 / 1138 | 0 / 0 | 12 / 12 | 27.59 ms |
| | after | 888 / 888 | 966 / 966 | 1138 / 1138 | 0 / 0 | 12 / 12 | 25.49 ms |

`retainedTranslationRefusedReasons` on pan-50-warm, summed over the 120 timed frames: **none** (and `retainedTranslationRefused` 0 on
every frame). The pan moves the whole canvas by a render effect (`scaleEffect` and `offset` on `CanvasSurface`), so each node view
is translated by the older render-effect rule (`retainedTranslated` 25 / 35 per frame, `retainedHits` 27 / 37, `retainedMisses`
3 / 35, `retainedGrafts` 0), not through layout. With `METALUI_TRACE_RETAINED=1` the untimed first frames do log refusals, all
`accessibilityRecords` (the nodes' socket dots and rows carry accessibility records, `ax 1/0` to `ax 12/1`); they do not reach the
timed frames. Wires are paths, which would refuse translation by rule; none was refused in a timed frame.

A/B, pan-50-warm with `METALUI_RETAINED_TRANSLATION=0`: identical counters (1409 element requests, 25 translated per frame) and
14.57 ms median against 13.44 ms with it on (noise). The switch turns off the layout translation only ("RK-G's render-effect
translation stays"), and the pan never moves a node through layout, so C14-d's new path is not exercised by this row.

What is left in pan-50-warm's 1409 element requests per frame is not explained by this run: only 3 retained misses per frame, yet
`elementPaints` 247 and the requests stay high. It is MetalUI's to read (`retainedSkippedRequests` and the prepaint/paint split);
the row now prints enough counters (`WarmCounters`) to chase it. Zoom changes the scale of every node, which is not a translation, so
zoom-50-warm still misses (171 retained misses per frame) and rasterizes.

### C14-e adopted (MetalUI c502f14c, PR #105, 2026-10-20)

No API change. MetalUI's C14-e settles the first warm frames (CF-E): from the frame after the records exist, `warm[n] == warm[n+1]`
on every `FrameWork` counter. What MetalCreator did for it:

- **The exact warm check starts at redraw 1.** `unchangedFramesAfterTheFirstRedrawDoExactlyTheSameWork` (was `...AfterSettling...`)
  skipped the first two redraws because the second carried a one-off `layoutMeasureCalls` spike (C14-e (e)); it now skips only redraw 0
  and passes.
- **`ViewportView` has a `==` (the model by identity) and a `PanelEqualityTests`-style test, but no `.equatable()` at the call
  site.** Measured with `.equatable()` on `ViewportPane`: element requests did not rise (orbit-panel-left-warm 199, orbit-panel-hidden-warm
  161, both as without), but `contentEvaluations` went from 0 to 1 per frame on both rows and `retainedIneligible` was no longer 0, so
  `aSteadyWarmOrbitStepWithThePanelDockedLeftDoesAlmostNoWork` failed. The `onGeometryChange` in its body makes an `.equatable()`
  Component ineligible every frame until MetalUI C14-e (c) lands, which is not in this merge; the call site waits for it.

Same Mac, release, `scripts/bench.sh`. "Before" is the C14-d table above (MetalUI 99b21a1c); "after" is this repository on c502f14c.
Counters are per frame, median / max.

| Row | | elementRequests | elementPaints | contentEvaluations |
|---|---|---|---|---|
| pan-50-warm | before | 1409 / 1697 | 247 / 615 | 1 / 33 |
| | after | 1409 / 1697 | 247 / 615 | 1 / 33 |
| zoom-50-warm | before | 1857 / 2879 | 2383 / 3815 | 1 / 121 |
| | after | 1857 / 2879 | 2383 / 3815 | 1 / 121 |
| orbit-panel-left-warm | before | 199 / 199 | 213 / 213 | 0 / 0 |
| | after | 199 / 199 | 213 / 213 | 0 / 0 |
| orbit-panel-hidden-warm | before | 161 / 161 | 166 / 166 | 0 / 0 |
| | after | 161 / 161 | 166 / 166 | 0 / 0 |
| fillet-drag-warm | before | 888 / 888 | 1138 / 1138 | 12 / 12 |
| | after | 888 / 888 | 1138 / 1138 | 12 / 12 |

The counters did not move on any row, and no count assertion changed. MetalUI notes that a redo frame's `contentEvaluations` may now be
higher (CF-C); none of these rows has a redo frame in its timed window, so it is not visible here.

### C14-g adopted (MetalUI b15e038c, PR #106, 2026-10-20)

No API change. MetalUI's C14-g lets an effect-translated prepaint replay run for a ledger that carries accessibility records, so a
warm pan of the 50-node graph now grafts instead of rebuilding. Zoom still refuses by design.

Same Mac, release, `scripts/bench.sh Warm`; the Mac was heavily loaded (`uptime` before: load averages 152.43 83.96 63.29; after:
73.13 124.89 97.68), so the ms are only indicative and the counters are the result. "Before" is the C14-e table above. Counters per
frame, median / max.

| Row | | elementRequests | elementPrepaints | elementPaints | retainedGrafts | retainedHits / Misses | contentEvaluations |
|---|---|---|---|---|---|---|---|
| pan-50-warm | before | 1409 / 1697 | n/a | 247 / 615 | 0 | n/a | 1 / 33 |
| | after | 192 / 468 | 212 / 500 | 247 / 615 | 27 / 37 | 27 / 37 and 3 / 35 | 1 / 33 |
| zoom-50-warm | after | 1857 / 2879 | 1999 / 3094 | 2383 / 3815 | 0 / 2 | 2 / 102 and 171 / 240 | 1 / 121 |
| orbit-panel-left-warm | after | 199 / 199 | 184 / 184 | 213 / 213 | 1 / 1 | 2 / 2 and 0 / 0 | 0 / 0 |
| orbit-panel-hidden-warm | after | 161 / 161 | 144 / 144 | 166 / 166 | 0 / 0 | 1 / 1 and 0 / 0 | 0 / 0 |
| fillet-drag-warm | after | 888 / 888 | 966 / 966 | 1138 / 1138 | 94 / 94 | 94 / 94 and 30 / 30 | 12 / 12 |

`retainedRedos` is not in the bench's report; the pan is pinned to 0 in `WarmWorkPinTests`. The pan row's window-cpu (warm frame) median
was 8.70 ms (p95 11.57 ms), inside the 16.67 ms budget; zoom stays at 28.32 ms (missed). Only pan moved; the other rows are unchanged
from C14-e.

Pinned: `aSteadyWarmPanOfFiftyNodesGraftsAndNeverRedoes` (steady steps: retainedGrafts > 0, retainedRedos == 0, median element
requests under 2 x 192) and `aWarmPanEvaluatesNoNodeView` (retainedGrafts > 0, element requests under 2 x 189 for the six-node
fixture, picture still equal to a full rebuild).

### C14-f and C14-h adopted (MetalUI 1bdead8d, 2026-10-21)

MetalUI C14-f (c55d44e8: geometry-observer replay, per-shelf atlas dirty rects, placement-memo translation) and C14-h (1bdead8d:
`onModifierKeysChanged`, lifecycle and, through a recomputed geometry note on a translated replay, `onGeometryChange` no longer
make an `.equatable()` component ineligible; `surface`, a `GPUSurface` or `MetalView`, still does). The bench report now also
prints `retainedIneligible`, `retainedGraftIneligible`, `retainedPrepaintIneligible`, `retainedRedos`, `retainedBackoffFrames` and the
worst-frame `atlasUploadPixels` (the max of the median/max pair), and `BENCH refused` / `BENCH ineligible` give the translation
refusal and ineligibility reasons as median/max per frame. Before: MetalUI b15e038c (C14-g), after: 1bdead8d, same MetalCreator
bench otherwise. The Mac was heavily loaded (load average 75 before, over 200 after), so the milliseconds are indicative only and
the counts are exact. Raw output: the "before" and "after" runs of this adoption.

| Row | Counter (median / max per frame) | Before | After |
| --- | --- | --- | --- |
| pan-50-warm | element requests / prepaints / paints | 192 / 212 / 247 | 192 / 212 / 247 |
|  | retainedGrafts / Hits / Misses / Redos | 27 / 27 / 3 / 0 | 27 / 27 / 4 / 0 |
|  | contentEvaluations; worst atlasUploadPixels | 1; 0 | 1; 0 |
|  | window-cpu median / p95 (ms) | 8.74 / 12.19 | 13.79 / 52.39 (loaded) |
| zoom-50-warm | element requests / prepaints / paints | 1857 / 1999 / 2383 | 1857 / 1999 / 2383 |
|  | retainedGrafts / Hits / Misses / Redos | 0 / 2 / 171 / 0 (max 1) | 0 / 2 / 172 / 0 (max 1) |
|  | contentEvaluations; worst atlasUploadPixels | 1; 0 | 1; 0 |
|  | window-cpu median / p95 (ms) | 28.83 / 45.54 | 63.37 / 185.87 (loaded) |
| orbit-panel-left-warm | element requests / prepaints / paints | 199 / 184 / 213 | 130 / 145 / 170 |
|  | retainedGrafts / Hits / Misses / Redos | 1 / 2 / 0 / 0 | 2 / 2 / 0 / 0 |
|  | contentEvaluations; worst atlasUploadPixels | 0; 0 | 0; 0 |
|  | window-cpu median / p95 (ms) | 6.88 / 7.60 | 6.98 / 32.47 (loaded) |
| orbit-panel-hidden-warm | element requests / prepaints / paints | 161 / 144 / 166 | 131 / 144 / 166 |
|  | retainedGrafts / Hits / Misses / Redos | 0 / 1 / 0 / 0 | 1 / 1 / 0 / 0 |
|  | contentEvaluations; worst atlasUploadPixels | 0; 0 | 0; 0 |
|  | window-cpu median / p95 (ms) | 1.99 / 2.45 | 1.92 / 9.42 (loaded) |
| fillet-drag-warm | element requests / prepaints / paints | 888 / 966 / 1138 | 888 / 966 / 1138 |
|  | retainedGrafts / Hits / Misses / Redos | 94 / 94 / 30 / 0 | 94 / 94 / 32 / 0 |
|  | contentEvaluations; worst atlasUploadPixels | 12; 26,572 | 12; 396 |
|  | window-cpu median / p95 (ms) | 26.40 / 28.67 | 43.40 / 100.91 (loaded) |

`retainedBackoffFrames` is 0 on every row except zoom-50-warm (median 1, max 1, both runs), and `retainedIneligible` is 0 on every
row in both runs. The ineligibility reasons per frame: before, `lifecycle` 2/2 on fillet-drag-warm and 1/1 on orbit-panel-left-warm
and orbit-panel-hidden-warm (the lifecycle hooks of the panels), none on pan and zoom; after, none on any row, and no translation
refusal on any row either. The `geometryChange` reason that made `GraphPanel` ineligible is gone.

Decisions:

- **Call-site `.equatable()` on `GraphPanel`: kept.** Orbit-panel-left went from 199 to 130 element requests per step (grafts 1 to 2), the
  hidden panel row, pan, zoom and fillet are unchanged in requests, and every existing pin passes. The price is one more
  retained node in the rows that rebuild the panel: `retainedMisses` +1 on pan and zoom and +2 on the fillet drag, with the same
  number of extra `contentSkips`.
- **Call-site `.equatable()` on `ViewportView`: not kept.** Tried on all five rows with `GraphPanel` already `.equatable()`: element
  requests, prepaints, paints, grafts and hits are identical to without it on every row, `contentEvaluations` rises by 1 per frame on
  orbit-panel-left, orbit-panel-hidden and fillet-drag (0 to 1, 12 to 13) and `retainedIneligible` rises to 1 (2 on the fillet drag), every
  one with the reason `surface`. It still does not pay while `GPUSurface` is refused.
- **Atlas upload.** The fillet drag's worst frame uploaded 26,572 atlas pixels before (the single dirty rect, step 51) and 338 to 442
  across the 2026-10-21 runs. `WarmWorkPinTests.filletAtlasUploadBound` (900, a little over twice the largest measurement) pins it in
  `swift test` and the fillet bench asserts the same bound.
- Tightened: the orbit-panel-left element request bound is now 2 x 130 (was 2 x 199). The pan bound (2 x 192) did not move.

## Carry-over items (the M0–M1 carry-over note, M7)

| Item | Benchmark | Measured (median) | Verdict |
|---|---|---|---|
| `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude, revolve and loft | `kernel-extrude`, `kernel-revolve`, `kernel-loft` | a whole extrude 0.49 ms, revolve 0.49 ms, loft 2.14 ms, `oriented()` included | Not worth changing: the whole operation, `oriented()` included, costs at most 2.14 ms against the drag's 100 ms, so the call can't be what a slow evaluation spends its time on. |
| `OCCTKernel` runs on the default actor executor | `kernel-bracket re-evaluation`, `kernel-main-actor gap` | the bracket re-evaluates in 46.91 ms; meanwhile the main actor never waits more than 0.13 ms (16,388 turns) | Fine: OCCT work occupies one cooperative-pool thread, never the main actor. No custom executor needed. |
| Per-item calls under the global lock | `kernel-lock`, `kernel-hop` | the lock 7.7 ns a call uncontended; a refused call's actor round trip 9.1 µs | Fine: under 2% of the cheapest real operation (0.49 ms), so a broadcast of n items pays n × 9 µs at most. |
| Picking renders the ID pass only when the camera or scene changes, never during a drag | `orbit-*` | not on the orbit path (the orbit frames above include no ID pass) | Nothing to measure in an orbit; a pick after it settles is one ID pass. |
| A dragged fillet radius re-tessellates each step | `fillet-drag evaluate+mesh` | 20.44 ms, evaluation and meshing together | Met within the drag's 100 ms. |

## Refused blends (Errata: Kernel, largest size for blends OCCT can't build)

A refused fillet or chamfer searches for the largest size that works (`OCCTKernel.largestValidBlend`: at most 20 tries
on a 0.1 mm grid). `scripts/bench.sh BlendRefusalBench`, 2026-10-09, MacBook Pro (MacBookPro18,2, Apple M1 Max),
macOS 27.0.1, a release build. Load averages 150.92 / 147.58 / 132.21 before the run and 83.84 / 123.64 / 125.55 after:
**far from idle** (other worktrees were building and testing), so read these as upper bounds on the cost; re-measure
on an idle machine to judge them.

| Part | Case | Median (p95) |
|---|---|---|
| §8 hexagon flange (plate + hexagon, four upright edges) | fillet R2.5, works: build + check | 16.22 ms (78.45) |
| | fillet R3, refused: build + check + search | 97.95 ms (202.07) |
| | the search alone | 69.89 ms (161.33) |
| | `BRepCheck_Analyzer` alone on the union | 2.37 ms (4.78) |
| §7.2 bracket (the Fillet node and everything after it) | radius 3.05 to 3.24, works | 37.48 ms (171.31) |
| | radius 8.25 to 9.20, refused (the message names max ≈ 3.9 mm) | 100.91 ms (255.27) |

```text
BENCH blend-flange fillet R2.5 (works: build + check): median 16.22 ms, p95 78.45 ms, max 78.68 ms (n 25)
BENCH blend-flange fillet R3 (refused: build + check + search): median 97.95 ms, p95 202.07 ms, max 212.10 ms (n 25)
BENCH blend-flange search alone (largestValidBlend below R3): median 69.89 ms, p95 161.33 ms, max 181.52 ms (n 25)
BENCH blend-flange checker alone (BRepCheck_Analyzer on the union): median 2.37 ms, p95 4.78 ms, max 6.61 ms (n 25)
BENCH blend-bracket message: Radius 9.2 mm is too large for the selected edges (max ≈ 3.9 mm).
BENCH blend-bracket Fillet node R3.x (works; evaluation of the Fillet and what follows): median 37.48 ms, p95 171.31 ms, max 173.99 ms (n 20)
BENCH blend-bracket Fillet node R8.x (refused; evaluation of the Fillet and what follows): median 100.91 ms, p95 255.27 ms, max 290.22 ms (n 20)
```

A refused blend costs about 60 to 80 ms more than one that works. The evaluation runs off the main actor and a
cancelled one stops between tries, so the window never waits for it; but a radius handle dragged past the maximum pays
the search on every step, so its error appears about 100 ms after the drag, not 37 ms. Which refusal the bracket's
radius 8.25 to 9.20 met (OCCT not done, or the checker rejecting) is not recorded; both run the same search.

Against the 100 ms budget for the fillet drag (spec §7.3), the bracket's refused evaluation (median 100.91 ms, p95
255.27 ms) sits at the budget's edge, but the run was at a load of about 150, far from idle, so it is **not judged**:
neither inside nor outside the budget until the idle re-run replaces these figures. (The “works” cases are well inside it.)

**Re-run 2026-10-13** (near idle: load 2.32 / 4.61 / 6.49 before, 2.22 / 3.89 / 5.94 after; MetalCreator `d734684`): the flange
fillet R2.5 works in 11.75 ms (p95 12.86), R3 refused in 79.28 ms (p95 80.57), the search alone 60.42 ms, the checker alone
1.96 ms; the bracket's Fillet node R3.x works in 23.82 ms (p95 24.40) and R8.x is refused in 75.13 ms (p95 78.22). So the refused
bracket evaluation is **inside** the 100 ms budget on a near-idle machine (75.13 ms), and the verdict above is no longer open.

## Patterns (patterns spec §7, sub-project 7a-2)

**Target:** about 200 instances, edit-to-preview within a second or two, release build on an idle Mac: the median of an
edit's evaluation, scene and meshes stays under **2,000 ms** (`Bench.patternBudget`). A miss is recorded with its numbers,
never hidden (parent spec §7.3).

**What is measured** (`Tests/CreatorAppTests/Bench/PatternBench.swift`, fixture `PatternBenchApp`): a 210 × 110 × 6 plate
with 200 Ø5 through-holes, a 20 × 10 grid 10 mm apart, three ways, each in a real `AppModel` on OCCT:

| Benchmark | The graph |
|---|---|
| `pattern-200 Hole Pattern` | Grid Points → Points to Placements → Hole Pattern (through all) → Output |
| `pattern-200 Hole Pattern + Fillet on one hole` | the same, then Edges by Tag (the rim of hole {110} picked) → Fillet R0.5 → Output |
| `pattern-200 Place + Boolean` | Grid Points → Points to Placements → Place (a Circle and an Extrude as the tool) → one Boolean → Output |

Each is built once (the **cold build**: every node, the scene and its meshes), then the holes' diameter is edited 40 times
to a value never seen before (4.00 → 4.39 mm), each step waiting for the evaluation, the scene and its meshes: the
**edit-to-preview** a person gets dragging the size. The same run is the proof of the §7 claims in code: one
`Kernel.place` and one `Kernel.boolean` per evaluation (`PatternFeatureNodeTests.subtractingMakesOnePlaceAndOneBooleanWhateverTheCount`),
one tool per distinct size (`ToolPlanTests`), and instance tags that add no boolean work (`PlaceConformanceTests`).

**Fixture checks** run in a plain `swift test` on a 5 × 3 grid (`PatternBenchAppTests`: every node OK, the volume exact,
the Place + Boolean variant the same part as the shortcut, one blend face for the filleted variant). The full 200-hole size
was also built once in a debug test run while writing the plan (all three variants, every node OK, the removed volume
equal to 200 holes' to 1e-9), which says nothing about speed.

**Results.** `scripts/bench.sh`, 2026-10-13, MacBookPro18,2 (Apple M1 Max, 10 cores), macOS 27.0.1, release build,
MetalCreator `d734684`, MetalUI `e85cb07a`. Load averages 2.32 / 4.61 / 6.49 before and 2.22 / 3.89 / 5.94 after: near idle (the
1-minute load under 3; the 5- and 15-minute averages not). This is the first measurement of these three; the cold build is one
run, the edit is 40.

| Benchmark | Cold build | Edit median | p95 | max | Budget | Verdict |
|---|---|---|---|---|---|---|
| `pattern-200 Hole Pattern` | 651.24 ms | 637.26 ms | 660.52 ms | 672.35 ms | 2,000 ms | **Met** |
| `pattern-200 Hole Pattern + Fillet on one hole` | 1,143.08 ms | 824.27 ms | 848.56 ms | 851.43 ms | 2,000 ms | **Met** |
| `pattern-200 Place + Boolean` | 645.08 ms | 622.77 ms | 653.79 ms | 658.11 ms | 2,000 ms | **Met** |

No edit median is over 2,000 ms; the slowest (the filleted variant) is 824.27 ms, 41% of the budget. The Place + Boolean path
costs no more than the shortcut (622.77 ms against 637.26 ms: the same two kernel calls), and the Fillet on one hole adds about
190 ms to the edit (it re-fillets after every edit) and about 490 ms to the cold build. The copies lever (`TopoDS_Shape::Moved`)
was not needed and was not pulled.

## Fields (fields spec §7, sub-project 7b-1)

**Targets**, release build on an idle Mac, the median of each row judged against its budget (`FieldBench.fiveNodeBudget`,
`distanceBudget`, `placementsBudget`). A miss is recorded with its numbers, never hidden (parent spec §7.3).

| Row | Case | Target |
|---|---|---|
| `field-1` | a five-node field (a radial gradient, a remap, noise, a multiply, a clamp), no kernel distance, 10,000 points | under **5 ms** |
| `field-2` | the signed distance from a 60 × 40 × 6 plate (R4 corners) to 10,000 points on OCCT, the first time and cached | first under **100 ms** (a gate: see below), cached about nothing |
| `field-2b` | the same points against a smooth loft through three circles (B-spline faces), first | recorded, no budget |
| `field-3` | Field Scatter on a 120 × 120 mm face with a radial-gradient field (spacing 1.4 to 2.4 mm, 3 mm margin): about 2,000 points (7b-3) | under **50 ms** |
| `field-3b` | Sample Field then Cull by Field (Probability) over 2,000 placements in 40 branches (7b-1's stand-in for row 3, kept) | under **50 ms** |
| `field-4` | the edit to a tinted preview on the bracket: a Remap of the signed distance to it selected and its range edited, to the frame (7b-3) | under **150 ms** (parent §7.3's edit-to-preview budget) |
| `field-4b` | the same with a Radial Gradient (no kernel distance) | under **150 ms** |
| `field-4c` | the first tint of the bracket by its signed distance (the kernel measures its mesh and the slice's grid) | recorded, no budget |

**The 100 ms is for analytic solids.** The plate is planes and cylinders. A point against a smooth loft's B-spline faces cost about
0.9 ms on a saturated machine (3,000 points took 2.7 s at a load of about 168), roughly forty times the plate's, so 10,000 points
against such a solid will not meet 100 ms on any machine this plan knows of, and `field-2b` records what it does. Nobody should read
the plate's number as the cost of every solid.

**What is measured** (`Tests/CreatorAppTests/Bench/FieldBench.swift`, fixtures `FieldBenchFixtures`): row 1 and 3 call
`FieldSampler.sample` and the two nodes' `evaluate` directly on the Fake kernel; row 2 samples a plate extruded by `OCCTKernel`
with a new `FieldDistanceCache` each round (so the first sampling always asks the kernel) and then again with the same cache
(the cached time is the cache's lookup: hashing 10,000 points and comparing them). The distance cache is keyed by Solid identity, so a solid evicted from the result cache and rebuilt equal is a new key and is re-measured.

**How row 2 is kept fast.** `BRepExtrema_DistShapeShape` costs about 28 µs a point on this plate (CPU time on one thread,
measured with the fixture's plate and points in a standalone program), and a solid classification about 18 µs more. So
`occt_distances` asks the classifier only about points inside the solid's bounds (9% of the fixture's points) and shares the
points out in blocks of 64 over OCCT's thread pool: one thread is about 280 ms for 10,000 points, so the 100 ms target needs
about four cores working. The threads change no number: serial and threaded results were identical in the standalone program
and `aBatchGivesWhatEachPointGivesOnItsOwn` pins batch equals single on OCCT.

**Fixture checks** run in a plain `swift test` (`FieldBenchFixturesTests`): row 1's field has five nodes and gives varied
numbers in 0…1, the points are the same every time, row 2's plate and row 2b's loft give the right signed distances on OCCT, row
3's face gets about 2,000 points denser in the middle, row 3b's tree is 2,000 placements in 40 branches; `FieldBenchAppTests`
checks row 4's bracket and field nodes (selecting a field tints the bracket and shows the slice, an edit changes the tint, and
the Remap's edit asks the kernel for nothing new).

**Rows 3 and 4 (7b-3).** `field-3` calls `FieldScatterNode.evaluate` on the Fake kernel (the field has no kernel distance) over an
OCCT plate's picked top face. `field-4`, `field-4b` and `field-4c` (`FieldBenchPreview`, fixture `FieldBenchApp`) drive the
§7.2 bracket's app as `FilletDragBench` does: each step edits the selected field node to a value not seen before (the Remap's
`fromHigh` 20.1 … 24 mm, the gradient's radius 40.5 … 60 mm), waits for `AppModel.settle()` (evaluation, scene, meshes, the tint's
sampling over the bracket's vertices and the slice's grid) and draws the window's frame and both GPU passes. The slice is
a 256 × 256 grid for a field with no kernel distance (`field-4b`) and 64 × 64 for one that measures a solid (`field-4`; 65,536 kernel distances would take
seconds on OCCT); `field-4c` records what the first tint costs.

**Results.** Two runs of `scripts/bench.sh FieldBench` (release build, MacBookPro18,2, 10 cores, macOS 27.0.1); the raw lines are under Raw output. Idle means all three load averages under 3, and **neither run met
that**: the first (7b-1, after lever 1) ran at load 4.16 3.69 4.95 before and 5.51 4.00 5.04 after; the second (7b-3) at 2.85 7.32
10.89 before and 4.74 7.31 10.74 after, so its 1-minute load was under 3 but its 5- and 15-minute averages were not. Rows 1, 2, 2b and
3b come from the first run; rows 3, 4, 4b and 4c from the second.

| Row | Median | p95 | max | n | Budget | Verdict |
|---|---|---|---|---|---|---|
| `field-1` | 0.64 ms | 0.66 ms | 0.77 ms | 60 | 5 ms | met |
| `field-2`, first (OCCT) | 70.61 ms | 73.04 ms | 80.97 ms | 22 | 100 ms | met |
| `field-2`, cached | 0.20 ms | 0.21 ms | 0.21 ms | 22 | none | n/a |
| `field-2b`, first (OCCT, smooth loft) | 868.20 ms | 892.38 ms | 892.38 ms | 8 | none | recorded |
| `field-3`, Field Scatter × about 2,000 points on a face | 46.41 ms | 47.17 ms | 47.59 ms | 22 | 50 ms | met |
| `field-3b`, Sample Field then Cull by Field | 0.35 ms | 0.36 ms | 0.38 ms | 40 | 50 ms | met |
| `field-4`, edit to a tinted bracket (Remap of the signed distance) | 31.70 ms | 36.88 ms | 480.13 ms | 40 | 150 ms | met |
| `field-4b`, the same with a Radial Gradient | 34.71 ms | 36.12 ms | 61.04 ms | 40 | 150 ms | met |
| `field-4c`, first tint of the bracket by its signed distance (kernel) | 572.60 ms | 572.60 ms | 572.60 ms | 1 | none | recorded |

(The first run's log called row 3b `field-3`, the name it had in 7b-1; its raw line keeps that name.)

**Re-taken 2026-10-13** (`scripts/bench.sh`, every suite; MetalCreator `d734684`; load 2.32 / 4.61 / 6.49 before, 2.22 / 3.89 /
5.94 after: near idle, 1-minute load under 3, the longer averages not; the lines are under Raw output):

| Row | Median | p95 | max | n | Budget | Verdict | Before |
|---|---|---|---|---|---|---|---|
| `field-1` | 0.70 ms | 0.73 ms | 0.80 ms | 60 | 5 ms | met | 0.64 ms |
| `field-2`, first (OCCT) | 73.79 ms | 74.57 ms | 74.89 ms | 22 | 100 ms | met | 70.61 ms |
| `field-2`, cached | 0.20 ms | 0.22 ms | 0.22 ms | 22 | none | n/a | 0.20 ms |
| `field-2b`, first (OCCT, smooth loft) | 850.74 ms | 866.87 ms | 866.87 ms | 8 | none | recorded | 868.20 ms |
| `field-3`, Field Scatter × about 2,000 points on a face | 45.20 ms | 45.98 ms | 46.68 ms | 22 | 50 ms | met | 46.41 ms |
| `field-3b`, Sample Field then Cull by Field | 0.35 ms | 0.39 ms | 0.43 ms | 40 | 50 ms | met | 0.35 ms |
| `field-4`, edit to a tinted bracket (Remap of the signed distance) | 32.04 ms | 35.45 ms | 238.65 ms | 40 | 150 ms | met | 31.70 ms |
| `field-4b`, the same with a Radial Gradient | 34.71 ms | 35.99 ms | 61.11 ms | 40 | 150 ms | met | 34.71 ms |
| `field-4c`, first tint of the bracket by its signed distance (kernel) | 184.64 ms | 184.64 ms | 184.64 ms | 1 | none | recorded | 572.60 ms |

**`field-3` still meets 50 ms:** 45.20 ms, 4.80 ms under the budget (it was 46.41 ms, 3.59 ms under), so the watch is not lifted
but it is not worse; 9.6% headroom on a near-idle machine. Keep watching it: it is the row nearest its budget, and the 5- and
15-minute loads of this run were above 3.

**`field-4c` fell from 572.60 ms to 184.64 ms with the analytic distance fast path** (3.1 times faster, one run, n 1, so read the
ratio loosely). The 572.60 ms was taken before the fast path; this run has it. `field-2` is unchanged by the re-run (70.61 ms to
73.79 ms, both under 100 ms), and its gate stays met. `field-4`'s max of 238.65 ms is a single outlier step in 40 (the median is
32.04 ms); the 480.13 ms max of the earlier run was the same kind.

**`field-4c` in the table above is before the fast path.** The 7b-3 run was taken on a branch that did not yet have the analytic
distance fast path (lever 1 below). The 572.60 ms is the number without it; the 2026-10-13 re-take above, with the fast path, is
184.64 ms.

**Row 2 needed lever 1.** An idle run before it measured `field-2` at a median of 585.37 ms (p95 589.87, n 22; load before 2.85
7.32 10.89), which missed the 100 ms gate. Lever 1 is the analytic fast path for planar and cylindrical faces in
`Sources/COCCT/cocct_distance_analytic.hpp` (commits b3e6684, c3c2294 and ae5cb93). In a single-thread profile, `Extrema` on the six
planar faces cost about 23 µs of the roughly 25 µs a point. After the change a point costs about 3.5 µs unsigned and 5.3 µs signed.
Lever 2 (a coarser classifier tolerance) was not needed and was not pulled.

**Row 2 after lever 1** measured 75.31 ms (machine saturated, load about 10 to 20), 75.33 ms (1-minute load 2.81, 5- and 15-minute
11.16 and 15.21), and 70.61 ms (load 4.16 3.69 4.95 before, 5.51 4.00 5.04 after). The gate asked for all three load averages
under 3, and no run reached that: other sessions kept the Mac busy. The gate is recorded as met on these runs anyway, because every run
is under 100 ms by 25 ms or more, and the number barely moves between load 20 and load 4. A run with all three averages under 3 has
not been taken.

**Row 2b is slow, as expected.** The smooth loft's B-spline faces still go through `Extrema`, so 10,000 points take 868.20 ms. It has
no budget and is recorded as it is.

If a later run puts `field-3` over 50 ms, the levers, in the order to pull them and re-measure: (1) key the point grid by one packed
`Int` instead of a hashed two-field struct (`PoissonScatter.Cell`), (2) fewer candidates per point (`candidatesPerPoint` 30 to 20,
which loosens the packing a little and changes every scatter, so `FieldScatterNodeTests` and `FieldsAcceptanceTests` re-pin their
counts), (3) stop and ask. The budget is not edited and a miss is not called met.

## Implicit (implicit spec §6, sub-project 7c-1)

`scripts/bench.sh ImplicitBench` runs rows i-1 to i-10. Release, an idle Mac
with a GPU. The fixture is a gyroid sheet filling a 100 mm cube: a TPMS node (gyroid, sheet, one cell of 100 mm, 3 mm wall) on an
Implicit Box, meshed and sent to an Output (7c-1 measured a noise sheet of the same cost class until the lattice nodes existed; 7c-2
swapped in the gyroid and kept the rows). A gyroid of 8 mm cells has about 150 million triangles at 0.1 mm, which no in-memory mesh
holds in 4 GB, so the fixture is one cell: its surface is 3.09 × 100² mm² twice over, about 196,000 triangles at 1.0 mm and so about
19.6 million at 0.1 mm (an estimate, not yet measured: 3 GB at the 155 bytes a triangle of the 7c-1 run), and its wall volume was 9.2% of the cube, the 9.3% a 3 mm wall
on that surface has.
Per the spec's Errata, the budgets of i-1 and i-2 are for the Metal path measured with Metal meshing (D13, plan 7c-1g), and the streamed
export that i-4 needs (D12, built by 7c-3: the file is written window by window and the mesh is never held) is what row i-4 measures from 7c-3 on. The first run below measured Metal evaluation with the CPU mesher; **the 7c-1g run after it
measures i-1 and i-2 with the GPU mesher**, which is what the budgets are for. Row i-4 was not re-measured by 7c-1g: it is 7c-3's row,
and its run below predates GPU meshing. The CPU engine records its numbers without a budget (D11). A budget is a record here, never a
gate (7c-1's ruling U6): a miss is written down as a miss.

| Row | Case | Target |
|---|---|---|
| i-1 | the sheet's first preview pass, on a fresh evaluator with the shaders compiled | under 1 s |
| i-2 | a thickness edit (the TPMS node's `thickness`), warm, no recompile: one coarse pass | under 100 ms |
| i-3 | To Implicit of the slice's filleted bracket (OCCT), bake cache emptied each time | under 500 ms |
| i-4 | the sheet exported at 0.1 mm to STL, the whole pipeline (streamed, D12) | under 60 s and a peak memory under 4 GB |
| i-4b | the same sheet exported to a 3MF (7c-3): file size, model XML size, time | recorded, no budget |
| i-4z | a 4.7 GB zip entry through `ZipWriter` read by `unzip -t` (macOS; Zip64) | valid, recorded |
| i-5 | Decimate of a 2,097,152-triangle sphere (a 100 mm ball) at 0.01 mm: `MeshDecimator` alone | under 10 s |
| i-6 | Mesh to Solid of a 100,000-triangle mesh on OCCT: the weld, the faces, the merge and the check | under 15 s |
| i-7 | the trapped-volume flood fill of a hollow 150 mm cube at the largest grid (28 million cells): time and peak resident memory | recorded |
| i-7s, i-7h | `TrappedVolumeCheck.run` of a solid and of a hollow 150 mm cube: time and peak resident memory against D16's 450 MB (7c-3f) | recorded |
| i-8 | Check Trapped Volumes and Check Thin Walls of a 30 mm cube with a 1.5 mm skin and a 1.2 mm gyroid sheet, meshed at 0.3 mm (7c-3f) | recorded |
| i-9 | a gyroid (10 mm cells, 1.5 mm wall) wrapped round the axis of a 90 mm × 100 mm post, Cylindrical: the first preview pass on a fresh evaluator (7c-4) | proposed: under 1 s |
| i-10c | the first evaluation of a Face-mapped lattice on an OpenCascade cylinder of 90 mm: To Implicit and the face's chart (125,000 samples through the kernel) (7c-4) | proposed: under 10 s (the chart alone is about 5 s) |
| i-10 | a thickness edit of that lattice, warm, chart cached: one coarse pass (7c-4) | proposed: under 250 ms |

Rows i-9, i-10c and i-10 are 7c-4's. They have **not been run**: the planning and the verification of 7c-4 took place on a Mac at a load average over 100, where a release timing is meaningless, and the budgets are proposals until the plan's user decision U9 settles them (IM-18). A wrapped lattice's lipschitz bound is its own times the mapping's stretch (about the mean radius over the 1 mm exclusion where the region holds the axis), so the sparse evaluation prunes far fewer bricks than a straight one: expect i-9 to be the dearest first pass of the suite, and the node says "the preview may be slow" from a stretch of 10.

The run recorded here (2026-10-14, release build, 7c-core) was taken while other sessions kept the Mac at a load average of 130 to 270 on 10 cores (so none of these numbers is a measurement of the
code; they show the benchmarks run, and the order of magnitude). It measured the noise sheet of 7c-1; **the gyroid fixture of 7c-2 has not
been run** (the Mac was not idle). **Superseded by the idle run of 2026-10-20 (Results, "Quiet-window idle run"); the lines below are kept as the history.**

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 265.76 238.70 211.00
BENCH i-1 first preview pass of a 100 mm sheet, cold (shaders compiled): median 254.21 ms, p95 254.21 ms, max 254.21 ms (n 1)
BENCH i-1 first preview pass of a 100 mm sheet: median 482.25 ms, p95 548.29 ms, max 548.29 ms (n 6); budget 1000.00 ms: met
BENCH i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile): median 307.57 ms, p95 373.58 ms, max 407.83 ms (n 22); budget 100.00 ms: missed
BENCH i-3 To Implicit of the bracket (bake, OCCT): median 1010.14 ms, p95 1106.43 ms, max 1106.43 ms (n 10); budget 500.00 ms: missed
BENCH i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline): median 86628.62 ms, p95 86628.62 ms, max 86628.62 ms (n 1); budget 60000.00 ms: missed
BENCH i-4 peak memory 4.53 GB (file 1599 MB); budget 4.00 GB: missed
BENCH load after: 127.82 167.82 184.74
```

The 7c-1g run (2026-10-14): `scripts/bench.sh "ImplicitBench/(theFirstPreview|aThicknessEdit|theFirstPassOnTheGPU)"`, rows i-1 and i-2
with marching cubes and the Newton snap on the GPU (`MetalImplicitEngine.meshBricks`), and the comparison `i-1m`: the same first pass by
the GPU mesher and by the CPU mesher over the GPU's values, which is how i-1 and i-2 were made before. **The Mac was not idle: the load
average was 32 at the start and 49 at the end, with other sessions running**, so these are not idle-Mac numbers; the GPU rows are
GPU-bound and the CPU comparison row is the one the load inflates. **Superseded by the idle run of 2026-10-20.**

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 32.32 86.74 106.78
BENCH i-1 first preview pass of a 100 mm sheet, cold (shaders compiled): median 288.29 ms, p95 288.29 ms, max 288.29 ms (n 1)
BENCH i-1 first preview pass of a 100 mm sheet: median 19.50 ms, p95 20.37 ms, max 20.37 ms (n 6); budget 1000.00 ms: met
BENCH i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile): median 22.62 ms, p95 25.29 ms, max 25.47 ms (n 22); budget 100.00 ms: met
BENCH i-1m first pass of the sheet at 0.78 mm, GPU mesher: median 28.92 ms, p95 29.64 ms, max 29.64 ms (n 6)
BENCH i-1m the same pass, CPU mesher over the GPU's values (before D13): median 106.28 ms, p95 108.76 ms, max 108.76 ms (n 6)
BENCH i-1m triangles: GPU 507760, CPU 507760
BENCH load after: 49.02 82.63 100.10
```

Both meshers made 507,760 triangles. The GPU mesh orders its vertices and triangles by thread timing, so the same shape is not the same
file twice (the set is the same). These rows time the first pass only. The Auto preview is capped (Errata D15): it stops before a pass
estimated over 2,000,000 triangles (four times the last pass's), so for this sheet, whose first pass has 507,760 triangles (four times
that is 2,031,040), it ends after the first pass; IM-13 asks a person to watch it. The cold row includes the compile of the meshing
kernels, a second library of the same source, which happens on the first mesh of a shape; later passes and edits of that shape reuse it.

The first run's reading of the misses, kept for the record (i-2 has since met its budget with GPU meshing; i-4 was not re-measured
by 7c-1g, and an export meshes on the GPU only while its edge table fits, `largestTable`, 2^27 slots, and falls back to the CPU otherwise): **i-2** is the first coarse pass again (128 cells across, marching
cubes and the Newton snap on the CPU), so it is about as long as i-1 and cannot be under 100 ms without a coarser first pass or marching
cubes on the GPU (D13, plan 7c-1g, which re-measures it); the spec's targets for i-1 and i-2 are not consistent with each other while
the first pass is the same pass. **i-3** is the tessellation, the BVH and 600 to
2,000 blocks of samples in parallel on the CPU. **i-4** holds the whole mesh and its vertex map in memory (about 150 bytes a triangle);
streaming bricks to the STL, which the user decided on (D12) and 7c-3 builds, cuts the memory; the time is the mesher's, so GPU
meshing (7c-1g) is what moves it.

## Preview triangle cap (D15): measured

`PreviewSchedule.maximumTriangles` (Errata D15) stops the Auto preview before a pass estimated over 2,000,000 triangles. That number
was a guess; `scripts/preview-sweep.sh` (`PreviewSweepBench`, a filter on `scripts/bench.sh`) measures what the app shows smoothly.
Release, an **idle** Mac with a GPU: any other build, test or render running at the same time inflates every frame time and moves the
cap, so a run taken on a busy Mac says only that the benchmark works. The run takes about a minute once the release build is done
(the build itself is several minutes, so run `swift test -c release --no-parallel --filter ZZNoSuchTestZZ` first, or let the script do it).

```sh
scripts/preview-sweep.sh     # = scripts/bench.sh PreviewSweepBench; the log is .build/bench.log
```

**The fixture** is `ImplicitBenchFixtures`' sheet (a thin curved wall through a 100 mm cube) with its noise features 8 mm across and a
wall of about 1 mm, standing in for a gyroid of 8 mm cells until the TPMS node exists (7c-2); it has several times row i-1's triangles
at one resolution. **The ladder** is six voxel sizes making about 0.25M, 0.5M, 1M, 2M, 4M and 8M triangles (`PreviewSweepFixtures.ladder`;
a thin wall's count falls short of the area law at coarse sizes, so the rungs are measured, not computed, and the run prints the real
counts). At each rung the run records:

1. **Meshing**: the first-pass time, plan and meshing, on the GPU mesher (`MetalImplicitEngine.meshBricks`) and on the CPU mesher over
   the GPU's values (as row i-1m), the median of 3.
2. **Orbit**: the sheet previewed down to the rung's resolution in the app (the app's own meshing and refinement, so the viewport holds
   what the app would show), orbited as `OrbitBench` does, with the panel docked left and hidden: model step, window CPU and GPU
   (viewport and window) per frame, median and p95 over 60 steps after 10 warm-up frames.
3. **Memory**: the mesh's own bytes (positions, normals and indices), the GPU vertex buffer derived from the renderer's layout (three
   48-byte corners per triangle; the renderer does not expose its buffers), and the process's `phys_footprint` (`task_info`, what
   Activity Monitor calls Memory) with the mesh in the viewport after the first frame, less the footprint of the same renderer after it
   drew an empty app: the mesh, its refinement, the viewport's display copy of it (doubles, 48 bytes a vertex plus the indices), the GPU
   copy, and the app. Both readings are **settled**: malloc keeps freed large blocks resident for some seconds after a rung's app is
   released (a dry run saw a rung's footprint fall from 2.2 GB to 1.0 GB within 15 s with nothing running), so
   `PreviewSweepFixtures.settledFootprint` trims, then reads every 0.5 s until three readings agree within 2% (at most 30 s). A
   `teardown` line prints, per rung, whether the `AppModel`, `ViewportModel`, renderer and mesh storage were freed (weak references),
   `MTLDevice.currentAllocatedSize`, the footprint at once and settled, and the live malloc heap. **What the dry runs found** (a
   saturated Mac, release): every object was freed and Metal held 1 MB, `leaks` found 0 leaks, and the footprint a rung left behind
   was malloc's freed-but-resident blocks plus about 100 MB of live heap per rung that does not grow with the mesh: MetalUI's
   `ContentMemoStore` of every `renderFrame` of the orbit stays alive with the models its `.equatable()` content read (a retain cycle
   through the observation's `onChange`, reproduced without MetalCreator; `docs/metalui-gaps.md` PERF-c). So MetalCreator retains no
   mesh (`PreviewSweepReleaseTests` pins that an app's mesh is freed, before and after frames), the memory column is the settled
   footprint of the rung's own app less the settled footprint of the same renderer with an empty app (so what earlier rungs left
   behind is subtracted), and a rung's footprint is read before its orbit, which is where the leaked frames come from. Across three
   dry runs the added column agreed within 2% (rung 6: 2,325, 2,329 and 2,329 MB; rung 3: 299, 295 and 302 MB) while the footprint
   under it climbed from 355 MB to 3,487 MB, which is why the figure is the difference and not the reading. The teardown reading
   waits 14 s for malloc's timer (rung 6 took 28 s and fell from 2.5 GB to 2.2 GB in the last 14); the live malloc heap grew by a
   steady 102 MB a rung (107 to 616 MB) whatever the mesh, which is PERF-c.
4. **The triangle count** the viewport shows.

| Row | Rung | Voxel | Triangles | Mesh, GPU (median of 3) | Mesh, CPU (median of 3) | Orbit GPU p95, panel shown / hidden | Window CPU p95, panel shown / hidden | Footprint added |
|---|---|---|---|---|---|---|---|---|
| 1 | 0.25M | 1.90 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |
| 2 | 0.5M | 1.55 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |
| 3 | 1M | 1.22 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |
| 4 | 2M | 0.93 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |
| 5 | 4M | 0.65 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |
| 6 | 8M | 0.46 mm | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` | `<pending idle run>` |

**The decision rule** (proposed; `PreviewSweepRule`, and it is applied to both panel states). A rung passes when all four hold:

- (a) the orbit's GPU p95 is at most 8 ms, half a 60 fps frame, which leaves room for MetalUI's own pass;
- (b) the window CPU p95 is unchanged from the smallest rung, within 1 ms;
- (c) the footprint the mesh adds is at most 1 GB;
- (d) the GPU meshing of that pass takes at most about 1 s (1,000 ms).

The cap is the **last rung before the first rung that fails**, scanning up the ladder from the smallest; if the smallest fails there is
none. A rung that passes above a failure never counts: a noisy pass on a rung that should have failed is not a size the preview shows
smoothly (`PreviewSweepRule.capCandidate`, pinned by `aPassAboveAFailureNeverCounts`).

The run prints `BENCH preview-sweep rung N rule: …` for each rung, with the four values and `PASS` or `FAIL`, and one line
`BENCH preview-sweep cap-candidate N`, N the triangle count of the cap (`none` if the smallest fails). Read the rung lines before
setting the cap: a failure caused by a busy Mac moves it.

| Result | Value |
|---|---|
| Machine, load before and after | `<pending idle run>` |
| MetalCreator commit | `<pending idle run>` |
| `BENCH preview-sweep cap-candidate` | `<pending idle run>` |
| The cap set in `PreviewSchedule.maximumTriangles` | `<pending idle run>` (2,000,000 until the idle run; do not change it before) |

### 7c-3 final fixes (streamer evaluator, trapped-volume memory)

`ImplicitBench`, release, Mac shared with other sessions (not idle; the figures are for the choice between engines, not for the budgets' final word):

```text
BENCH i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline): median 40595.40 ms (GPU values, CPU mesher; budget 60000 ms: met)
BENCH i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline): median 295403.97 ms (CPU values; budget 60000 ms: missed)
BENCH i-7 28094464 cells, 1 void, 3.96 s; peak resident 425 MB (54 MB before the grid)
```

The streamed export therefore keeps the GPU engine's values (`StreamingMesherGPUTests` holds them to the seam welding, and a seam that
does not weld throws `seamsDidNotJoin`); the CPU mesher builds the triangles, and `meshBricks` is not used (recorded as a deviation).
i-7 is the flood fill of a hollow 150 mm cube at the largest grid: about 370 MB over the process's baseline.

### Rows i-4 to i-7 with the mesh tools (7c-3)

Taken 2026-10-19 on a MacBookPro18,2, release build of 7c-3 after merging master, on a Mac that was NOT idle (load 9.7 before, 8.7 after on 10 cores, other sessions running): a record, not a verdict. Every budget was met even so. The streamed export meshes on the CPU over the GPU engine's values.

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 9.72 15.46 12.32
BENCH i-1 first preview pass of a 100 mm sheet, cold (shaders compiled): median 423.11 ms, p95 423.11 ms, max 423.11 ms (n 1)
BENCH i-1 first preview pass of a 100 mm sheet: median 9.89 ms, p95 10.63 ms, max 10.63 ms (n 6); budget 1000.00 ms: met
BENCH i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile): median 8.06 ms, p95 8.27 ms, max 9.08 ms (n 22); budget 100.00 ms: met
BENCH i-1m first pass of the sheet at 0.78 mm, GPU mesher: median 12.61 ms, p95 12.64 ms, max 12.64 ms (n 6)
BENCH i-1m the same pass, CPU mesher over the GPU's values (before D13): median 57.77 ms, p95 59.36 ms, max 59.36 ms (n 6)
BENCH i-1m triangles: GPU 323808, CPU 323808
BENCH i-3 To Implicit of the bracket (bake, OCCT): median 288.96 ms, p95 301.32 ms, max 301.32 ms (n 10); budget 500.00 ms: met
BENCH i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline): median 18850.45 ms, p95 18850.45 ms, max 18850.45 ms (n 1); budget 60000.00 ms: met
BENCH i-4 peak memory 0.86 GB (file 1008 MB); budget 4.00 GB: met
BENCH i-4b export of the 100 mm sheet at 0.1 mm (3MF, whole pipeline): median 36838.25 ms, p95 36838.25 ms, max 36838.25 ms (n 1)
BENCH i-4b 3MF file 177 MB, model XML 1436 MB; peak memory of the process so far 2.00 GB
BENCH i-4z a 4794 MB zip entry (deflated): median 22879.88 ms, p95 22879.88 ms, max 22879.88 ms (n 1)
BENCH i-4z unzip -t: exit 0 No errors detected in compressed data of /var/folders/_h/phx9n5sd01dd8sf4h76clcc80000gn/T/10BF6732-685E-4A6B-B169-2E6F69FFCB04.zip.
BENCH i-5 decimate a 2097152 triangle sphere (0.01 mm): median 6804.42 ms, p95 6813.99 ms, max 6813.99 ms (n 3); budget 10000.00 ms: met
BENCH i-5 triangles 2097152 to 290730
BENCH i-7 28094464 cells, 1 void, 4.180774292 seconds; peak resident 2,271 MB (2,271 MB before the grid)
BENCH i-6 Mesh to Solid of a 100000 triangle mesh (OCCT): median 14143.10 ms, p95 14214.17 ms, max 14214.17 ms (n 2); budget 15000.00 ms: met
BENCH i-6 faces 100000
BENCH load after: 8.69 11.16 11.15
```

**i-4** was 86.6 s and 4.53 GB in 7c-core's in-memory export; streamed it is 18.9 s and 0.86 GB (the file is 1,008 MB at this sheet). **i-4b**: the 3MF is 177 MB from 1,436 MB of model XML in 36.8 s, under 4 GB of XML so a plain zip; **i-4z** writes a 4.8 GB entry as Zip64 and `unzip -t` accepts it. **i-5**: 6.8 s against 10 s. **i-6**: 14.1 s against 15 s (close: a busy Mac misses it, re-run on an idle one). **i-7**'s resident figures are polluted by the bench process holding earlier rows (2,271 MB before the grid); the earlier isolated run measured 425 MB peak.

### Rows i-5 to i-8 with the robust checks (7c-3f)

Taken 2026-10-20 on a MacBookPro18,2, release build of 7c-3f, on a Mac that was NOT idle (load 3 to 8 on 10 cores, other sessions running): a record, not a verdict. The rows run were i-5, i-6, i-7 and the new i-8 (`scripts/bench.sh ImplicitBench`), and i-7s and i-7h, each alone in its own process (`scripts/bench.sh theChecksOfASolid150mmCube`, then `theChecksOfAHollow150mmCube`). Nothing 7c-3f changed is in i-5 (Decimate) or i-6 (Mesh to Solid), so their budgets are re-checked, not re-argued: both are still met, and i-6 is as close to its budget as in 7c-3.

```text
BENCH i-5 decimate a 2097152 triangle sphere (0.01 mm): median 7039.09 ms, p95 7264.74 ms, max 7264.74 ms (n 3); budget 10000.00 ms: met
BENCH i-5 triangles 2097152 to 290730
BENCH i-7 28094464 cells, 1 void, 3.645953917 seconds; peak resident 738 MB (692 MB before the grid)
BENCH i-6 Mesh to Solid of a 100000 triangle mesh (OCCT): median 14358.38 ms, p95 14416.84 ms, max 14416.84 ms (n 2); budget 15000.00 ms: met
BENCH i-6 faces 100000
BENCH i-8 Check Trapped Volumes of a 554960 triangle sheet: median 2054.87 ms, p95 2061.66 ms, max 2061.66 ms (n 2)
BENCH i-8 Check Thin Walls of the same mesh: median 1267.62 ms, p95 1293.01 ms, max 1293.01 ms (n 2)
BENCH i-8 voids 2, thin places 0
BENCH i-7s 5288 triangles, 0 void, 2.169670875 seconds; peak resident 395 MB (57 MB before the check)
BENCH i-7h 8752 triangles, 1 void, 5.204713291000001 seconds; peak resident 425 MB (57 MB before the check)
```

i-8's two voids are the two gyroid channels the skin closes; the phantom void of Errata M5 is gone. **i-7s and i-7h** (each run alone, so the peak is the check's own on top of the process's 57 MB) put the whole check, the unsigned-distance fill and the winding number included, on a solid and on a hollow 150 mm cube, 28 million cells each: 395 MB and 425 MB resident, inside D16's 450 MB, in 2.2 s and 5.2 s. They exist because the unsigned grid makes the interior of a thick solid part one pocket of 27 million cells: the first version of the check listed all of it before calling it material and peaked at **603 MB** on the solid cube (2.24 s), past the budget. `EnclosedVoids` now judges a pocket from its first 4,096 listed cells and stops listing one judged material (`aPocketBiggerThanTheJudgingSizeIsJudgedBeforeItIsListedInFull`). **The choice of inside test** (Errata D18) was measured on the same sheet and on a larger one, release, with the `SignedDistanceMesh` already built:

| Mesh | Triangles | Grid cells | `SignedDistanceMesh` built | Pseudonormal sign, every cell | Winding number, every cell | Unsigned distance, winding number once per pocket (shipped) |
|---|---|---|---|---|---|---|
| 30 mm cube, skin and sheet | 554,960 | 274,625 | 1.20 s | 0.81 s | 18.5 s | 0.81 s |
| 50 mm cube, skin and sheet | 2,550,048 | 1,157,625 | 7.00 s | 3.92 s | 138.6 s | 3.91 s |

A winding number at every cell is 23 to 35 times the pseudonormal's cost, which the 50 mm cube makes minutes, so Check Trapped Volumes fills the grid from the unsigned distance and asks the winding number about five cells of each pocket the flood fill leaves. All three find the same voids on these two meshes (2 and 8); the phantom shows on the 8 mm fixture of `TrappedVolumePhantomTests`, where the pseudonormal sign finds a third. The winding-number clusters (about 80 bytes a BVH node, plus their build time) are built on the first `isInside` and not with the `SignedDistanceMesh`, so To Implicit's bake, which only asks for the pseudonormal sign, never builds them and row i-3 is unaffected.

## Raw output

The 2026-10-20 idle run (MetalCreator `5e4069e`, MetalUI `711ab9c4`; the machine and load lines are the scripts', copied from their
output; the sweep ran in `MetalCreator-sweep` on `xp-preview-sweep` merged with master):

Preview sweep (`scripts/preview-sweep.sh`):

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 1.63 2.20 2.98
BENCH preview-sweep rung 1 (0.25M) mesh: res 1.9 mm, 324604 triangles, 165248 vertices; own bytes 9 MB (positions 3 MB, normals 3 MB, indices 4 MB)
BENCH preview-sweep rung 1 (0.25M) mesh-gpu: median 17.05 ms, p95 17.26 ms, max 17.26 ms (n 3)
BENCH preview-sweep rung 1 (0.25M) mesh-cpu: median 48.88 ms, p95 50.77 ms, max 50.77 ms (n 3)
BENCH preview-sweep rung 1 (0.25M) memory: footprint 352 MB with an empty app drawn, 443 MB with the mesh in the viewport, added 91 MB; GPU vertex buffer 47 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 1 (0.25M) viewport: 324604 triangles shown
BENCH preview-sweep rung 1 (0.25M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 1 (0.25M) panel-left window-cpu: median 16.31 ms, p95 16.57 ms, max 17.43 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 1 (0.25M) panel-left gpu (viewport + window): median 5.59 ms, p95 7.02 ms, max 7.65 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 1 (0.25M) panel-hidden model: median 0.00 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 1 (0.25M) panel-hidden window-cpu: median 1.68 ms, p95 2.03 ms, max 2.20 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 1 (0.25M) panel-hidden gpu (viewport + window): median 3.25 ms, p95 3.70 ms, max 3.78 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 1 (0.25M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 561 MB at once, 153 MB settled after 15.77 s; live malloc heap 5 MB
BENCH preview-sweep rung 1 (0.25M) rule: (a) gpu p95 7.02 shown / 3.70 hidden ms (<= 8.00): met; (b) window cpu p95 0.00 / 0.00 ms over the smallest rung (<= 1.00): met; (c) footprint added 91 MB (<= 1000 MB): met; (d) gpu mesh 17.05 ms (<= 1000.00): met => PASS
BENCH preview-sweep rung 2 (0.5M) mesh: res 1.55 mm, 570700 triangles, 282572 vertices; own bytes 16 MB (positions 5 MB, normals 5 MB, indices 7 MB)
BENCH preview-sweep rung 2 (0.5M) mesh-gpu: median 22.54 ms, p95 37.25 ms, max 37.25 ms (n 3)
BENCH preview-sweep rung 2 (0.5M) mesh-cpu: median 83.06 ms, p95 101.32 ms, max 101.32 ms (n 3)
BENCH preview-sweep rung 2 (0.5M) memory: footprint 472 MB with an empty app drawn, 632 MB with the mesh in the viewport, added 160 MB; GPU vertex buffer 82 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 2 (0.5M) viewport: 570700 triangles shown
BENCH preview-sweep rung 2 (0.5M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 2 (0.5M) panel-left window-cpu: median 16.28 ms, p95 16.88 ms, max 17.10 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 2 (0.5M) panel-left gpu (viewport + window): median 5.52 ms, p95 7.55 ms, max 8.22 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 2 (0.5M) panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 2 (0.5M) panel-hidden window-cpu: median 1.62 ms, p95 1.72 ms, max 1.93 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 2 (0.5M) panel-hidden gpu (viewport + window): median 3.49 ms, p95 3.58 ms, max 3.96 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 2 (0.5M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 814 MB at once, 300 MB settled after 15.72 s; live malloc heap 5 MB
BENCH preview-sweep rung 2 (0.5M) rule: (a) gpu p95 7.55 shown / 3.58 hidden ms (<= 8.00): met; (b) window cpu p95 0.31 / -0.30 ms over the smallest rung (<= 1.00): met; (c) footprint added 160 MB (<= 1000 MB): met; (d) gpu mesh 22.54 ms (<= 1000.00): met => PASS
BENCH preview-sweep rung 3 (1M) mesh: res 1.22 mm, 1039236 triangles, 500984 vertices; own bytes 29 MB (positions 8 MB, normals 8 MB, indices 12 MB)
BENCH preview-sweep rung 3 (1M) mesh-gpu: median 24.68 ms, p95 52.12 ms, max 52.12 ms (n 3)
BENCH preview-sweep rung 3 (1M) mesh-cpu: median 149.73 ms, p95 173.33 ms, max 173.33 ms (n 3)
BENCH preview-sweep rung 3 (1M) memory: footprint 632 MB with an empty app drawn, 934 MB with the mesh in the viewport, added 302 MB; GPU vertex buffer 150 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 3 (1M) viewport: 1039236 triangles shown
BENCH preview-sweep rung 3 (1M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 3 (1M) panel-left window-cpu: median 16.28 ms, p95 16.67 ms, max 17.26 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 3 (1M) panel-left gpu (viewport + window): median 6.20 ms, p95 9.31 ms, max 10.25 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 3 (1M) panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 3 (1M) panel-hidden window-cpu: median 1.62 ms, p95 1.69 ms, max 1.83 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 3 (1M) panel-hidden gpu (viewport + window): median 4.30 ms, p95 4.42 ms, max 4.47 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 3 (1M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 1240 MB at once, 538 MB settled after 14.67 s; live malloc heap 5 MB
BENCH preview-sweep rung 3 (1M) rule: (a) gpu p95 9.31 shown / 4.42 hidden ms (<= 8.00): missed; (b) window cpu p95 0.09 / -0.34 ms over the smallest rung (<= 1.00): met; (c) footprint added 302 MB (<= 1000 MB): met; (d) gpu mesh 24.68 ms (<= 1000.00): met => FAIL
BENCH preview-sweep rung 4 (2M) mesh: res 0.93 mm, 1979960 triangles, 945482 vertices; own bytes 54 MB (positions 15 MB, normals 15 MB, indices 24 MB)
BENCH preview-sweep rung 4 (2M) mesh-gpu: median 35.92 ms, p95 71.31 ms, max 71.31 ms (n 3)
BENCH preview-sweep rung 4 (2M) mesh-cpu: median 292.21 ms, p95 310.23 ms, max 310.23 ms (n 3)
BENCH preview-sweep rung 4 (2M) memory: footprint 968 MB with an empty app drawn, 1557 MB with the mesh in the viewport, added 589 MB; GPU vertex buffer 285 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 4 (2M) viewport: 1979960 triangles shown
BENCH preview-sweep rung 4 (2M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 4 (2M) panel-left window-cpu: median 16.27 ms, p95 17.48 ms, max 17.60 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 4 (2M) panel-left gpu (viewport + window): median 7.09 ms, p95 11.14 ms, max 12.40 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 4 (2M) panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 4 (2M) panel-hidden window-cpu: median 1.62 ms, p95 1.74 ms, max 1.80 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 4 (2M) panel-hidden gpu (viewport + window): median 5.60 ms, p95 5.72 ms, max 5.92 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 4 (2M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 2109 MB at once, 1022 MB settled after 14.69 s; live malloc heap 5 MB
BENCH preview-sweep rung 4 (2M) rule: (a) gpu p95 11.14 shown / 5.72 hidden ms (<= 8.00): missed; (b) window cpu p95 0.91 / -0.29 ms over the smallest rung (<= 1.00): met; (c) footprint added 589 MB (<= 1000 MB): met; (d) gpu mesh 35.92 ms (<= 1000.00): met => FAIL
BENCH preview-sweep rung 5 (4M) mesh: res 0.65 mm, 4060684 triangles, 1983220 vertices; own bytes 112 MB (positions 32 MB, normals 32 MB, indices 49 MB)
BENCH preview-sweep rung 5 (4M) mesh-gpu: median 65.32 ms, p95 98.00 ms, max 98.00 ms (n 3)
BENCH preview-sweep rung 5 (4M) mesh-cpu: median 636.99 ms, p95 647.60 ms, max 647.60 ms (n 3)
BENCH preview-sweep rung 5 (4M) memory: footprint 1622 MB with an empty app drawn, 2818 MB with the mesh in the viewport, added 1196 MB; GPU vertex buffer 585 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 5 (4M) viewport: 4060684 triangles shown
BENCH preview-sweep rung 5 (4M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 5 (4M) panel-left window-cpu: median 16.25 ms, p95 17.02 ms, max 18.19 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 5 (4M) panel-left gpu (viewport + window): median 8.88 ms, p95 10.77 ms, max 11.40 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 5 (4M) panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 5 (4M) panel-hidden window-cpu: median 1.62 ms, p95 1.65 ms, max 1.90 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 5 (4M) panel-hidden gpu (viewport + window): median 8.33 ms, p95 8.59 ms, max 8.65 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 5 (4M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 3906 MB at once, 1986 MB settled after 14.68 s; live malloc heap 5 MB
BENCH preview-sweep rung 5 (4M) rule: (a) gpu p95 10.77 shown / 8.59 hidden ms (<= 8.00): missed; (b) window cpu p95 0.45 / -0.38 ms over the smallest rung (<= 1.00): met; (c) footprint added 1196 MB (<= 1000 MB): missed; (d) gpu mesh 65.32 ms (<= 1000.00): met => FAIL
BENCH preview-sweep rung 6 (8M) mesh: res 0.46 mm, 8083708 triangles, 4027652 vertices; own bytes 226 MB (positions 64 MB, normals 64 MB, indices 97 MB)
BENCH preview-sweep rung 6 (8M) mesh-gpu: median 113.40 ms, p95 201.76 ms, max 201.76 ms (n 3)
BENCH preview-sweep rung 6 (8M) mesh-cpu: median 1386.79 ms, p95 1391.24 ms, max 1391.24 ms (n 3)
BENCH preview-sweep rung 6 (8M) memory: footprint 2957 MB with an empty app drawn, 5286 MB with the mesh in the viewport, added 2329 MB; GPU vertex buffer 1164 MB (de-indexed, derived from the layout)
BENCH preview-sweep rung 6 (8M) viewport: 8083708 triangles shown
BENCH preview-sweep rung 6 (8M) panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 6 (8M) panel-left window-cpu: median 16.25 ms, p95 16.48 ms, max 17.38 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 6 (8M) panel-left gpu (viewport + window): median 11.84 ms, p95 13.96 ms, max 14.59 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 6 (8M) panel-hidden model: median 0.00 ms, p95 0.01 ms, max 0.01 ms (n 60)
BENCH preview-sweep rung 6 (8M) panel-hidden window-cpu: median 1.63 ms, p95 1.79 ms, max 2.03 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 6 (8M) panel-hidden gpu (viewport + window): median 13.38 ms, p95 13.87 ms, max 14.00 ms (n 60); budget 16.67 ms: met
BENCH preview-sweep rung 6 (8M) teardown: AppModel, renderer and mesh storage freed; Metal allocated 1 MB; footprint 6439 MB at once, 2743 MB settled after 27.46 s; live malloc heap 5 MB
BENCH preview-sweep rung 6 (8M) rule: (a) gpu p95 13.96 shown / 13.87 hidden ms (<= 8.00): missed; (b) window cpu p95 -0.09 / -0.24 ms over the smallest rung (<= 1.00): met; (c) footprint added 2329 MB (<= 1000 MB): missed; (d) gpu mesh 113.40 ms (<= 1000.00): met => FAIL
BENCH preview-sweep row: 324604 triangles at 1.90 mm; mesh gpu 17.05 ms, cpu 48.88 ms; orbit gpu p95 7.02 ms shown, 3.70 ms hidden; window cpu p95 16.57 ms shown, 2.03 ms hidden; footprint added 91 MB
BENCH preview-sweep row: 570700 triangles at 1.55 mm; mesh gpu 22.54 ms, cpu 83.06 ms; orbit gpu p95 7.55 ms shown, 3.58 ms hidden; window cpu p95 16.88 ms shown, 1.72 ms hidden; footprint added 160 MB
BENCH preview-sweep row: 1039236 triangles at 1.22 mm; mesh gpu 24.68 ms, cpu 149.73 ms; orbit gpu p95 9.31 ms shown, 4.42 ms hidden; window cpu p95 16.67 ms shown, 1.69 ms hidden; footprint added 302 MB
BENCH preview-sweep row: 1979960 triangles at 0.93 mm; mesh gpu 35.92 ms, cpu 292.21 ms; orbit gpu p95 11.14 ms shown, 5.72 ms hidden; window cpu p95 17.48 ms shown, 1.74 ms hidden; footprint added 589 MB
BENCH preview-sweep row: 4060684 triangles at 0.65 mm; mesh gpu 65.32 ms, cpu 636.99 ms; orbit gpu p95 10.77 ms shown, 8.59 ms hidden; window cpu p95 17.02 ms shown, 1.65 ms hidden; footprint added 1196 MB
BENCH preview-sweep row: 8083708 triangles at 0.46 mm; mesh gpu 113.40 ms, cpu 1386.79 ms; orbit gpu p95 13.96 ms shown, 13.87 ms hidden; window cpu p95 16.48 ms shown, 1.79 ms hidden; footprint added 2329 MB
BENCH preview-sweep process peak resident 5.11 GB
BENCH preview-sweep cap-candidate 570700
BENCH load after: 2.17 2.32 2.85
```

GraphPanZoomBench:

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 2.21 2.33 2.85
BENCH pan-50 nodes built of 50: median 16, max 20
BENCH pan-50 model: median 0.12 ms, p95 0.13 ms, max 0.15 ms (n 120)
BENCH pan-50 window-cpu: median 21.35 ms, p95 24.11 ms, max 24.68 ms (n 120); budget 16.67 ms: missed
BENCH pan-50 window-gpu: median 4.47 ms, p95 5.12 ms, max 5.98 ms (n 120); budget 16.67 ms: met
BENCH zoom-50 nodes built of 50: median 25, max 50
BENCH zoom-50 model: median 0.11 ms, p95 0.13 ms, max 0.16 ms (n 120)
BENCH zoom-50 window-cpu: median 24.45 ms, p95 28.55 ms, max 30.39 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50 window-gpu: median 4.73 ms, p95 5.34 ms, max 5.42 ms (n 120); budget 16.67 ms: met
BENCH load after: 2.02 2.28 2.82
```

OrbitBench:

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 2.02 2.28 2.82
BENCH orbit-panel-left: the canvas builds 19 of 20 nodes
BENCH orbit-panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 100)
BENCH orbit-panel-left window-cpu: median 25.80 ms, p95 26.61 ms, max 28.59 ms (n 100); budget 16.67 ms: missed
BENCH orbit-panel-left gpu (viewport + window): median 6.55 ms, p95 6.93 ms, max 7.98 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden: the graph panel is hidden (20 nodes)
BENCH orbit-panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 100)
BENCH orbit-panel-hidden window-cpu: median 1.96 ms, p95 2.07 ms, max 2.30 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden gpu (viewport + window): median 2.19 ms, p95 2.65 ms, max 3.68 ms (n 100); budget 16.67 ms: met
BENCH load after: 1.87 2.23 2.80
```

FilletDragBench:

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 1.87 2.23 2.80
BENCH fillet-drag: 75 of 75 steps showed a new part
BENCH fillet-drag evaluate+mesh: median 25.30 ms, p95 26.87 ms, max 28.72 ms (n 75)
BENCH fillet-drag window-cpu: median 27.27 ms, p95 29.47 ms, max 85.62 ms (n 75)
BENCH fillet-drag gpu (viewport + window): median 7.17 ms, p95 8.49 ms, max 24.01 ms (n 75)
BENCH fillet-drag command-to-frame: median 60.15 ms, p95 62.94 ms, max 134.41 ms (n 75); budget 100.00 ms: met
BENCH load after: 1.81 2.21 2.78
```

ImplicitBench:

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 1.74 2.19 2.77
BENCH i-1 first preview pass of a 100 mm sheet, cold (shaders compiled): median 22.13 ms, p95 22.13 ms, max 22.13 ms (n 1)
BENCH i-1 first preview pass of a 100 mm sheet: median 13.31 ms, p95 13.74 ms, max 13.74 ms (n 6); budget 1000.00 ms: met
BENCH i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile): median 8.37 ms, p95 12.12 ms, max 13.55 ms (n 22); budget 100.00 ms: met
BENCH i-1m first pass of the sheet at 0.78 mm, GPU mesher: median 12.76 ms, p95 12.95 ms, max 12.95 ms (n 6)
BENCH i-1m the same pass, CPU mesher over the GPU's values (before D13): median 58.00 ms, p95 58.95 ms, max 58.95 ms (n 6)
BENCH i-1m triangles: GPU 323808, CPU 323808
BENCH i-3 To Implicit of the bracket (bake, OCCT): median 281.66 ms, p95 287.21 ms, max 287.21 ms (n 10); budget 500.00 ms: met
BENCH i-4 export of the 100 mm sheet at 0.1 mm (STL, whole pipeline): median 18600.08 ms, p95 18600.08 ms, max 18600.08 ms (n 1); budget 60000.00 ms: met
BENCH i-4 peak memory 0.94 GB (file 1008 MB); budget 4.00 GB: met
BENCH i-4b export of the 100 mm sheet at 0.1 mm (3MF, whole pipeline): median 36482.31 ms, p95 36482.31 ms, max 36482.31 ms (n 1)
BENCH i-4b 3MF file 177 MB, model XML 1436 MB; peak memory of the process so far 1.81 GB
BENCH i-4z a 4794 MB zip entry (deflated): median 22378.96 ms, p95 22378.96 ms, max 22378.96 ms (n 1)
BENCH i-4z unzip -t: exit 0 No errors detected in compressed data of /var/folders/_h/phx9n5sd01dd8sf4h76clcc80000gn/T/52748003-389A-4F31-91DD-95626A15F99B.zip.
BENCH i-5 decimate a 2097152 triangle sphere (0.01 mm): median 6837.89 ms, p95 6863.57 ms, max 6863.57 ms (n 3); budget 10000.00 ms: met
BENCH i-5 triangles 2097152 to 290730
BENCH i-7 28094464 cells, 1 void, 4.226632625 seconds; peak resident 2,261 MB (2,261 MB before the grid)
BENCH i-6 Mesh to Solid of a 100000 triangle mesh (OCCT): median 14057.18 ms, p95 14091.19 ms, max 14091.19 ms (n 2); budget 15000.00 ms: met
BENCH i-6 faces 100000
BENCH load after: 2.92 2.40 2.74
```

FieldBench:

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 2.78 2.39 2.73
BENCH field-1 five nodes × 10,000 points (no kernel): median 0.71 ms, p95 0.71 ms, max 0.75 ms (n 60); budget 5.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, first (OCCT): median 73.14 ms, p95 73.85 ms, max 73.87 ms (n 22); budget 100.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, cached: median 0.20 ms, p95 0.21 ms, max 0.22 ms (n 22)
BENCH field-2b signed distance to a smooth loft × 10,000 points, first (OCCT): median 860.41 ms, p95 865.68 ms, max 865.68 ms (n 8)
BENCH field-3 Field Scatter × about 2,000 points on a face: median 45.84 ms, p95 46.17 ms, max 46.40 ms (n 22); budget 50.00 ms: met
BENCH field-3b Sample Field + Cull by Field × 2,000 placements: median 0.34 ms, p95 0.35 ms, max 0.39 ms (n 40); budget 50.00 ms: met
BENCH field-4c first tint of the bracket by its signed distance (kernel): median 179.66 ms, p95 179.66 ms, max 179.66 ms (n 1)
BENCH field-4 edit to a tinted bracket preview (Remap of the signed distance): median 37.44 ms, p95 38.17 ms, max 290.55 ms (n 40); budget 150.00 ms: met
BENCH field-4b edit to a tinted bracket preview (Radial Gradient): median 40.23 ms, p95 41.44 ms, max 67.81 ms (n 40); budget 150.00 ms: met
BENCH load after: 3.69 2.62 2.81
```

The 2026-10-13 run (`scripts/bench.sh`, every suite; MetalCreator `d734684`, MetalUI `e85cb07a`; the machine and load lines are
the script's, copied from its output):

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 2.32 4.61 6.49
BENCH blend-flange fillet R2.5 (works: build + check): median 11.75 ms, p95 12.86 ms, max 13.19 ms (n 25)
BENCH blend-flange fillet R3 (refused: build + check + search): median 79.28 ms, p95 80.57 ms, max 82.46 ms (n 25)
BENCH blend-flange search alone (largestValidBlend below R3): median 60.42 ms, p95 62.41 ms, max 62.52 ms (n 25)
BENCH blend-flange checker alone (BRepCheck_Analyzer on the union): median 1.96 ms, p95 2.06 ms, max 2.06 ms (n 25)
BENCH blend-bracket message: Radius 9.2 mm is too large for the selected edges (max ≈ 3.9 mm).
BENCH blend-bracket Fillet node R3.x (works; evaluation of the Fillet and what follows): median 23.82 ms, p95 24.40 ms, max 24.82 ms (n 20)
BENCH blend-bracket Fillet node R8.x (refused; evaluation of the Fillet and what follows): median 75.13 ms, p95 78.22 ms, max 78.85 ms (n 20)
BENCH field-1 five nodes × 10,000 points (no kernel): median 0.70 ms, p95 0.73 ms, max 0.80 ms (n 60); budget 5.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, first (OCCT): median 73.79 ms, p95 74.57 ms, max 74.89 ms (n 22); budget 100.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, cached: median 0.20 ms, p95 0.22 ms, max 0.22 ms (n 22)
BENCH field-2b signed distance to a smooth loft × 10,000 points, first (OCCT): median 850.74 ms, p95 866.87 ms, max 866.87 ms (n 8)
BENCH field-3 Field Scatter × about 2,000 points on a face: median 45.20 ms, p95 45.98 ms, max 46.68 ms (n 22); budget 50.00 ms: met
BENCH field-3b Sample Field + Cull by Field × 2,000 placements: median 0.35 ms, p95 0.39 ms, max 0.43 ms (n 40); budget 50.00 ms: met
BENCH field-4c first tint of the bracket by its signed distance (kernel): median 184.64 ms, p95 184.64 ms, max 184.64 ms (n 1)
BENCH field-4 edit to a tinted bracket preview (Remap of the signed distance): median 32.04 ms, p95 35.45 ms, max 238.65 ms (n 40); budget 150.00 ms: met
BENCH field-4b edit to a tinted bracket preview (Radial Gradient): median 34.71 ms, p95 35.99 ms, max 61.11 ms (n 40); budget 150.00 ms: met
BENCH fillet-drag: 75 of 75 steps showed a new part
BENCH fillet-drag evaluate+mesh: median 25.38 ms, p95 26.77 ms, max 27.39 ms (n 75)
BENCH fillet-drag window-cpu: median 21.96 ms, p95 24.65 ms, max 37.05 ms (n 75)
BENCH fillet-drag gpu (viewport + window): median 7.05 ms, p95 8.50 ms, max 18.89 ms (n 75)
BENCH fillet-drag command-to-frame: median 54.77 ms, p95 58.79 ms, max 79.88 ms (n 75); budget 100.00 ms: met
BENCH pan-50 nodes built of 50: median 16, max 20
BENCH pan-50 model: median 0.10 ms, p95 0.12 ms, max 0.14 ms (n 120)
BENCH pan-50 window-cpu: median 17.05 ms, p95 18.33 ms, max 21.66 ms (n 120); budget 16.67 ms: missed
BENCH pan-50 window-gpu: median 4.07 ms, p95 5.13 ms, max 6.87 ms (n 120); budget 16.67 ms: met
BENCH zoom-50 nodes built of 50: median 25, max 50
BENCH zoom-50 model: median 0.10 ms, p95 0.11 ms, max 0.13 ms (n 120)
BENCH zoom-50 window-cpu: median 18.64 ms, p95 21.48 ms, max 23.73 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50 window-gpu: median 4.49 ms, p95 5.22 ms, max 5.93 ms (n 120); budget 16.67 ms: met
BENCH kernel-extrude (60 × 40 × 6 plate): median 0.48 ms, p95 0.50 ms, max 0.53 ms (n 50)
BENCH kernel-revolve (tube): median 0.48 ms, p95 0.51 ms, max 0.51 ms (n 50)
BENCH kernel-loft (two rectangles): median 2.09 ms, p95 2.13 ms, max 2.25 ms (n 50)
BENCH kernel-lock (uncontended, per 100,000 calls): median 0.74 ms, p95 0.75 ms, max 0.78 ms (n 50)
BENCH kernel-hop (refused calls: an actor round trip each, no OCCT; per 100 calls): median 0.94 ms, p95 0.99 ms, max 1.04 ms (n 50)
BENCH kernel-bracket re-evaluation (Width 60 ↔ 90, wall): median 54.86 ms, p95 56.05 ms, max 56.05 ms (n 8)
BENCH kernel-main-actor gap during re-evaluation: median 0.01 ms, p95 0.01 ms, max 0.10 ms (n 45745); budget 16.67 ms: met
BENCH orbit-panel-left: the canvas builds 19 of 20 nodes
BENCH orbit-panel-left model: median 0.01 ms, p95 0.01 ms, max 0.01 ms (n 100)
BENCH orbit-panel-left window-cpu: median 20.56 ms, p95 21.97 ms, max 24.20 ms (n 100); budget 16.67 ms: missed
BENCH orbit-panel-left gpu (viewport + window): median 5.73 ms, p95 6.80 ms, max 7.91 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden: the graph panel is hidden (20 nodes)
BENCH orbit-panel-hidden model: median 0.00 ms, p95 0.00 ms, max 0.01 ms (n 100)
BENCH orbit-panel-hidden window-cpu: median 1.84 ms, p95 2.01 ms, max 2.24 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden gpu (viewport + window): median 2.17 ms, p95 2.56 ms, max 3.21 ms (n 100); budget 16.67 ms: met
BENCH pattern-200 Hole Pattern cold build (every node, scene and meshes): median 651.24 ms, p95 651.24 ms, max 651.24 ms (n 1)
BENCH pattern-200 Hole Pattern edit diameter (evaluate+scene+meshes): median 637.26 ms, p95 660.52 ms, max 672.35 ms (n 40); budget 2000.00 ms: met
BENCH pattern-200 Hole Pattern + Fillet on one hole cold build (every node, scene and meshes): median 1143.08 ms, p95 1143.08 ms, max 1143.08 ms (n 1)
BENCH pattern-200 Hole Pattern + Fillet on one hole edit diameter (evaluate+scene+meshes): median 824.27 ms, p95 848.56 ms, max 851.43 ms (n 40); budget 2000.00 ms: met
BENCH pattern-200 Place + Boolean cold build (every node, scene and meshes): median 645.08 ms, p95 645.08 ms, max 645.08 ms (n 1)
BENCH pattern-200 Place + Boolean edit diameter (evaluate+scene+meshes): median 622.77 ms, p95 653.79 ms, max 658.11 ms (n 40); budget 2000.00 ms: met
BENCH load after: 2.22 3.89 5.94
```

The 2026-10-09 run the first table comes from (`scripts/bench.sh`, every suite):

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 22.54 33.70 58.73
BENCH fillet-drag: 75 of 75 steps showed a new part
BENCH fillet-drag evaluate+mesh: median 20.44 ms, p95 21.90 ms, max 22.82 ms (n 75)
BENCH fillet-drag window-cpu: median 16.91 ms, p95 18.20 ms, max 31.65 ms (n 75)
BENCH fillet-drag gpu (viewport + window): median 5.44 ms, p95 6.54 ms, max 17.16 ms (n 75)
BENCH fillet-drag command-to-frame: median 43.14 ms, p95 45.59 ms, max 68.79 ms (n 75); budget 100.00 ms: met
BENCH pan-50 nodes built of 50: median 16, max 20
BENCH pan-50 model: median 0.10 ms, p95 0.11 ms, max 0.18 ms (n 120)
BENCH pan-50 window-cpu: median 13.09 ms, p95 14.79 ms, max 15.50 ms (n 120); budget 16.67 ms: met
BENCH pan-50 window-gpu: median 3.25 ms, p95 3.82 ms, max 5.11 ms (n 120); budget 16.67 ms: met
BENCH zoom-50 nodes built of 50: median 25, max 50
BENCH zoom-50 model: median 0.10 ms, p95 0.13 ms, max 3.56 ms (n 120)
BENCH zoom-50 window-cpu: median 15.03 ms, p95 17.56 ms, max 36.06 ms (n 120); budget 16.67 ms: met
BENCH zoom-50 window-gpu: median 3.38 ms, p95 3.82 ms, max 5.90 ms (n 120); budget 16.67 ms: met
BENCH kernel-extrude (60 × 40 × 6 plate): median 0.49 ms, p95 0.56 ms, max 0.61 ms (n 50)
BENCH kernel-revolve (tube): median 0.49 ms, p95 0.54 ms, max 0.54 ms (n 50)
BENCH kernel-loft (two rectangles): median 2.14 ms, p95 2.31 ms, max 2.46 ms (n 50)
BENCH kernel-lock (uncontended, per 100,000 calls): median 0.77 ms, p95 0.78 ms, max 0.81 ms (n 50)
BENCH kernel-hop (refused calls: an actor round trip each, no OCCT; per 100 calls): median 0.91 ms, p95 1.32 ms, max 1.58 ms (n 50)
BENCH kernel-bracket re-evaluation (Width 60 ↔ 90, wall): median 46.91 ms, p95 48.66 ms, max 48.66 ms (n 8)
BENCH kernel-main-actor gap during re-evaluation: median 0.02 ms, p95 0.04 ms, max 0.13 ms (n 16388); budget 16.67 ms: met
BENCH orbit-panel-left: the canvas builds 19 of 20 nodes
BENCH orbit-panel-left model: median 0.01 ms, p95 0.01 ms, max 0.02 ms (n 100)
BENCH orbit-panel-left window-cpu: median 16.01 ms, p95 17.70 ms, max 18.64 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-left gpu (viewport + window): median 5.11 ms, p95 5.39 ms, max 6.01 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden: the graph panel is hidden (20 nodes)
BENCH orbit-panel-hidden model: median 0.00 ms, p95 0.01 ms, max 0.02 ms (n 100)
BENCH orbit-panel-hidden window-cpu: median 1.98 ms, p95 2.13 ms, max 2.50 ms (n 100); budget 16.67 ms: met
BENCH orbit-panel-hidden gpu (viewport + window): median 2.06 ms, p95 2.20 ms, max 2.93 ms (n 100); budget 16.67 ms: met
BENCH load after: 11.92 26.99 53.35
```

Before canvas culling and level of detail (the same final tree with `CanvasLayers` from the commit "the canvas keys
nodes by their whole UUID", which draws `drawOrder`: one run of `scripts/bench.sh "GraphPanZoomBench|OrbitBench"`, load
averages 10.55 / 26.20 / 52.76 before and 7.92 / 22.86 / 49.72 after; still not idle). Built: all 50 nodes (pan, zoom)
and all 20 (orbit).

```text
BENCH pan-50 nodes built: all 50
BENCH zoom-50 nodes built: all 50
BENCH orbit-panel-left nodes built: all 20
BENCH pan-50 window-cpu: median 26.63 ms, p95 28.83 ms, max 29.84 ms (n 120); budget 16.67 ms: missed
BENCH zoom-50 window-cpu: median 26.53 ms, p95 29.86 ms, max 30.92 ms (n 120); budget 16.67 ms: missed
BENCH orbit-panel-left window-cpu: median 15.96 ms, p95 18.01 ms, max 19.08 ms (n 100); budget 16.67 ms: met
```

The `FieldBench` run the Fields results come from (`scripts/bench.sh FieldBench`; the machine and load lines were not in the saved
log and are copied from the run's notes, load before 4.16 3.69 4.95 and after 5.51 4.00 5.04):

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 4.16 3.69 4.95
BENCH field-1 five nodes × 10,000 points (no kernel): median 0.64 ms, p95 0.66 ms, max 0.77 ms (n 60); budget 5.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, first (OCCT): median 70.61 ms, p95 73.04 ms, max 80.97 ms (n 22); budget 100.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, cached: median 0.20 ms, p95 0.21 ms, max 0.21 ms (n 22)
BENCH field-2b signed distance to a smooth loft × 10,000 points, first (OCCT): median 868.20 ms, p95 892.38 ms, max 892.38 ms (n 8)
BENCH field-3 Sample Field + Cull by Field × 2,000 placements: median 0.35 ms, p95 0.36 ms, max 0.38 ms (n 40); budget 50.00 ms: met
BENCH load after: 5.51 4.00 5.04
```

The 7b-3 `FieldBench` run (`scripts/bench.sh FieldBench`, taken before the distance fast path existed; every BENCH line of the saved log):

```text
BENCH field-1 five nodes × 10,000 points (no kernel): median 0.68 ms, p95 0.70 ms, max 0.72 ms (n 60); budget 5.00 ms: met
BENCH field-2 signed distance to a plate × 10,000 points, first (OCCT): median 585.37 ms, p95 589.87 ms, max 592.60 ms (n 22); budget 100.00 ms: missed
BENCH field-2 signed distance to a plate × 10,000 points, cached: median 0.21 ms, p95 0.23 ms, max 0.24 ms (n 22)
BENCH field-2b signed distance to a smooth loft × 10,000 points, first (OCCT): median 857.71 ms, p95 863.63 ms, max 863.63 ms (n 8)
BENCH field-3 Field Scatter × about 2,000 points on a face: median 46.41 ms, p95 47.17 ms, max 47.59 ms (n 22); budget 50.00 ms: met
BENCH field-3b Sample Field + Cull by Field × 2,000 placements: median 0.35 ms, p95 0.38 ms, max 0.40 ms (n 40); budget 50.00 ms: met
BENCH field-4c first tint of the bracket by its signed distance (kernel): median 572.60 ms, p95 572.60 ms, max 572.60 ms (n 1)
BENCH field-4 edit to a tinted bracket preview (Remap of the signed distance): median 31.70 ms, p95 36.88 ms, max 480.13 ms (n 40); budget 150.00 ms: met
BENCH field-4b edit to a tinted bracket preview (Radial Gradient): median 34.71 ms, p95 36.12 ms, max 61.04 ms (n 40); budget 150.00 ms: met
```

## Implicit engines side by side (plan xp-c)

Suite `ImplicitBenchHLSL` (`scripts/bench.sh ImplicitBenchHLSL`; Linux: `DOCKER_EXTRA="-e METALCREATOR_BENCH=1" XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh test -c release --no-parallel --filter ImplicitBenchHLSL`).
Solid: a 100 mm gyroid sheet (wall 3 mm; the edit is 2.5 mm), the mesher alone at 0.78 mm, preview quality, median of six warm runs.
Mac: MacBookPro18,2, 10 cores, macOS 27.0.1, load before 6.22 11.50 37.48 and after 17.60 14.41 32.00 (other sessions were running: the Mac was not idle, so the
GPU figures are upper bounds). Linux: the metalcreator-linux:xp-c Docker image on the same Mac, Mesa lavapipe (a software Vulkan device, so its rows measure the CPU).

| Row | Machine and load | Engine | Median | Budget | Verdict |
| --- | --- | --- | --- | --- | --- |
| x-1 first pass | Mac, busy | Metal | 12.94 ms | none | recorded |
| x-1 first pass | Mac, busy | Metal (HLSL) | 9.98 ms | none | recorded |
| x-1 first pass | Mac, busy | CPU | 1,852.69 ms | none | recorded |
| x-1 first pass | Docker, lavapipe | Vulkan | 62.62 ms | none | recorded |
| x-1 first pass | Docker | CPU | 1,495.11 ms | none | recorded |
| x-2 thickness edit | Mac, busy | Metal | 13.81 ms | none | recorded |
| x-2 thickness edit | Mac, busy | Metal (HLSL) | 9.41 ms | none | recorded |
| x-2 thickness edit | Mac, busy | CPU | 1,763.10 ms | none | recorded |
| x-2 thickness edit | Docker, lavapipe | Vulkan | 62.37 ms | none | recorded |
| x-2 thickness edit | Docker | CPU | 1,496.78 ms | none | recorded |
| x-1h | Mac, busy | Metal (HLSL) | 9.98 ms | 1000 ms | met |
| x-3m new shape, evaluation kernel, uncached | Mac, busy | Metal | first 98.64 ms, median 42.84 ms, max 98.64 ms (5 shapes); second run 89.73 / 42.43 / 89.73 ms | none | recorded |
| x-3m new shape, the five meshing kernels, uncached | Mac, busy | Metal | first 319.48 ms, median 319.47 ms, max 320.31 ms (5 shapes); second run 326.35 / 312.46 / 326.35 ms | none | recorded |
| x-3o offline compile, one kernel (shadercross CLI) | Docker | HLSL to SPIR-V, DXIL, MSL | 0.60 s (157 kernels in 94.7 s) | none | recorded |
| x-3 | | | after XP-G25 (task 11) | | |
| x-4 | | | after XP-G25 (task 11) | | |

x-3o is an upper bound on XP-G25's in-process compile: it divides a whole `kernels` run (all seven targets' outputs through the MetalUICompileShaders
tool, with `.build/generated-kernels/compiled` emptied first so every kernel compiled) by the 157 kernels. x-3m times Metal's own compile of five different shapes (a type or form each, none the x-1 sheet), each kernel given a fresh per-run name and each library a per-run literal in an added kernel, so the AIR itself is unseen (a comment is gone in the AIR and only defeats the source-to-AIR cache, leaving the AIR-to-GPU-binary step open to a pipeline or binary cache an earlier run filled; an earlier version of this row did that and read 12.37 ms median for the evaluation kernel). Two successive runs agree (second run in the rows above), which a partial cache hit would not; the evaluation kernel and the five meshing kernels
are timed apart, and the first shape is reported apart from the median because the first compile in a process pays for Metal's compiler start-up. An
earlier version of the row reused sources Metal had already compiled and read 0.14 ms; that was a cache hit, not a compile, and is superseded. Ruling: the x-3m rows are recorded as taken under load (6 to 37 on 10 cores), not as met figures: the evaluation kernel's 42.84 ms median was not a cache hit by the two-run check, but both rows are to be re-measured on an idle Mac after merge, and no verdict (x-3, D21) may quote them as measured until then. Task 11's
x-3 (the HLSL engine's run-time compile) is compared with the first-shape figures.

```text
BENCH x-1 Metal: first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median 12.94 ms
BENCH x-2 Metal: thickness edit, warm: median 13.81 ms
BENCH x-1 Metal (HLSL): first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median 9.98 ms
BENCH x-2 Metal (HLSL): thickness edit, warm: median 9.41 ms
BENCH x-1h Metal (HLSL): 9.98 ms; budget 1000.00 ms: met
BENCH x-1 CPU: first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median 1,852.69 ms
BENCH x-2 CPU: thickness edit, warm: median 1,763.10 ms
BENCH x-3m Metal: a new shape, uncached source: evaluation kernel first 98.64 ms, median 42.84 ms, max 98.64 ms; the five meshing kernels first 319.48 ms, median 319.47 ms, max 320.31 ms
BENCH x-1 Vulkan: first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median 62.62 ms
BENCH x-2 Vulkan: thickness edit, warm: median 62.37 ms
BENCH x-1 CPU: first pass of a 100 mm gyroid sheet at 0.78 mm, warm: median 1,495.11 ms
BENCH x-2 CPU: thickness edit, warm: median 1,496.78 ms
COMPILE-TIME 157 kernels in 94.7 s
```
