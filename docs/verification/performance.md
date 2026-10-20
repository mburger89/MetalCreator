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

`scripts/bench.sh ImplicitBench` runs rows i-1 to i-7. Release, an idle Mac
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

The run recorded here (2026-10-14, release build, 7c-core) was taken while other sessions kept the Mac at a load average of 130 to 270 on 10 cores (so none of these numbers is a measurement of the
code; they show the benchmarks run, and the order of magnitude). It measured the noise sheet of 7c-1; **the gyroid fixture of 7c-2 has not
been run** (the Mac was not idle). **Re-run on an idle Mac with `scripts/bench.sh ImplicitBench` and replace these lines, keeping the load
lines.**

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
GPU-bound and the CPU comparison row is the one the load inflates. **Re-run on an idle Mac and replace them, keeping the load lines.**

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

## Raw output

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
