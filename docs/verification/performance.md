# Performance — spec §7.3, measured

Spec §7.3 asks for three targets, "measured, not just asserted". This file records the numbers against each, how they
were taken, and who owns each miss. Re-measure with `scripts/bench.sh` after any change to drawing, the canvas, the
viewport or the kernel, and replace the numbers here (keep the machine, load and commits with them).

## How to run

```sh
scripts/bench.sh                      # every benchmark: about 10 minutes, most of it the release build
scripts/bench.sh GraphPanZoomBench    # one suite (also OrbitBench, FilletDragBench, KernelBench)
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
- **window-cpu**: the whole window built, laid out and painted by MetalUI (`renderFrame` over `AppRoot`, 1440 × 900
  points at scale 2, the graph panel docked left at its default size). This is the work a pan, a zoom or an orbit
  causes in the app: each changes observed state, and MetalUI rebuilds the whole window on every observed change
  (gap PERF-b).
- **gpu**: MetalUI's renderer compositing that scene into an offscreen texture, plus (orbit and fillet drag) the
  viewport's own Metal pass (`ViewportRenderer`), each committed and waited for.
- **command-to-frame** (fillet drag): from the handle's value change to both GPU passes done.

Medians are judged against the budget: 16.67 ms a frame for 60 fps, 100 ms for the fillet drag. The first 10 frames
of a run are warm-up and not counted (the drag counts every step: each is a new value).

What headless can't show, so the numbers are an upper bound for the CPU and a lower bound for latency:

- `renderFrame` draws a fresh window's first frame every time: no text shaping cache, raster cache or state table
  survives between frames (MetalUI exposes no warm headless frame: gap M7-b). A real window keeps them, so its CPU
  frame is cheaper. MetalUI's own warm-loop figures for the 20-node bracket are in PERF-b (12–13 ms release with
  nothing moving).
- A real window overlaps a frame's GPU work with the next frame's build, so its frame time is about the larger of CPU
  and GPU, not their sum; here they run one after the other.
- No display link: the fillet drag's command-to-frame leaves out waiting for the next vsync (up to 16.7 ms more).

## Results

2026-10-09, MacBook Pro (MacBookPro18,2, Apple M1 Max, 10 cores), macOS 27.0.1, MetalUI `2155f1e`, MetalCreator
`71ec6fc` (branch `m7-measure`). Load averages (1, 5, 15 minutes) 22.54 / 33.70 / 58.73 before the run and 11.92 / 26.99 / 53.35
after: **not idle** (other worktrees were building and testing in parallel; idle means all three under 3, before and
after). So the zoom-50 and orbit-panel-left verdicts, which sit within a millisecond or two of the budget, are **not
judged**: the medians are kept, to be judged on an idle machine. The other verdicts are far from their budgets and hold
at any load.

| §7.3 target | Benchmark | Measured (median, p95) | Budget | Verdict | A miss belongs to |
|---|---|---|---|---|---|
| Panning a 50-node graph at 60 fps | `pan-50` | CPU 13.09 ms (p95 14.79), GPU 3.25 ms; the canvas builds 16 of 50 nodes (max 20) | 16.67 ms | **Met** (with canvas culling; 26.63 ms without it, indicative: a separate run at a different load) | — |
| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 15.03 ms (p95 17.56, max 36.06), GPU 3.38 ms; 25 of 50 nodes built (all 50 zoomed out), with level of detail | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median under the budget, p95 over; 26.53 ms without culling and level of detail, indicative: a separate run at a different load) | MetalUI C14 (PERF-b), if it misses on an idle run |
| Fillet radius drag: viewport updated within 100 ms of each value change | `fillet-drag` | command-to-frame 43.14 ms (p95 45.59): evaluate + mesh 20.44 ms, window CPU 16.91 ms, GPU 5.44 ms; 75 of 75 steps showed a new part | 100 ms | **Met** | — |
| Orbiting the bracket at 60 fps | `orbit-panel-left` | CPU 16.01 ms (p95 17.70), GPU 5.11 ms | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median at the budget's edge, p95 over): each orbit step rebuilds the graph panel too | MetalUI C14 (PERF-b), if it misses on an idle run |
| (the same, graph panel hidden) | `orbit-panel-hidden` | CPU 1.98 ms (p95 2.13), GPU 2.06 ms | 16.67 ms | **Met** | — |

### What MetalCreator changed

- **Canvas culling** (`EditorModel.drawnNodes`, `drawnCanvasRect`, `CanvasLayers`): the canvas builds only the nodes
  and wires whose frames meet the visible canvas grown by `EditorModel.cullingMargin` (160 points) on every side.
  Panning the 50-node graph went from 26.63 ms to 13.09 ms of CPU a frame (runs minutes apart, both loaded; the
  second at load 10.55 / 26.20 / 52.76 before). Hit testing, selection and every edit still see the whole graph;
  culling is drawing only. A window resize reaches the canvas one task after the viewport's draw records the new size
  (`ViewportModel.observedViewSize`, gap M4-a's stopgap), so what a bigger window uncovers is drawn at once.
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
on an idle run, it waits for MetalUI C14 (PERF-b: rebuild only what changed); its entry cites this file. Both are
judged on an idle run, which is still to do: the machine stayed loaded while this was recorded.

## Carry-over items (the M0–M1 carry-over note, M7)

| Item | Benchmark | Measured (median) | Verdict |
|---|---|---|---|
| `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude, revolve and loft | `kernel-extrude`, `kernel-revolve`, `kernel-loft` | a whole extrude 0.49 ms, revolve 0.49 ms, loft 2.14 ms, `oriented()` included | Not worth changing: the whole operation, `oriented()` included, costs at most 2.14 ms against the drag's 100 ms, so the call can't be what a slow evaluation spends its time on. |
| `OCCTKernel` runs on the default actor executor | `kernel-bracket re-evaluation`, `kernel-main-actor gap` | the bracket re-evaluates in 46.91 ms; meanwhile the main actor never waits more than 0.13 ms (16,388 turns) | Fine: OCCT work occupies one cooperative-pool thread, never the main actor. No custom executor needed. |
| Per-item calls under the global lock | `kernel-lock`, `kernel-hop` | the lock 7.7 ns a call uncontended; a refused call's actor round trip 9.1 µs | Fine: under 2% of the cheapest real operation (0.49 ms), so a broadcast of n items pays n × 9 µs at most. |
| Picking renders the ID pass only when the camera or scene changes, never during a drag | `orbit-*` | not on the orbit path (the orbit frames above include no ID pass) | Nothing to measure in an orbit; a pick after it settles is one ID pass. |
| A dragged fillet radius re-tessellates each step | `fillet-drag evaluate+mesh` | 20.44 ms, evaluation and meshing together | Met within the drag's 100 ms. |

## Raw output

The run the tables above come from (`scripts/bench.sh`, every suite):

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
