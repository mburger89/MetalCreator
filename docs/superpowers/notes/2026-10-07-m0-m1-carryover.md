# M0–M1 carry-over for later milestones

Deferred review findings from the M0–M1 subagent-driven run (final review triage, 2026-10-07).
Read this before writing the M2 and M3 plans.

## Before the first M2 OCCT operation
- ✅ (M2) STEP export sets the process-global `Interface_Static` unit; meshing writes triangulation into the shared TShape. Keep all OCCT access serialized inside `OCCTKernel` (dedicated serial executor recommended).
- ✅ (M2) Map `OCCTError` to `KernelError` so raw OCCT text never reaches users.
- ✅ (M2) Query sentinel `-1` is ambiguous for `occt_volume` (negative volumes exist): expose throwing/optional queries in `OCCTKernel`.
- ✅ (M2) Silence OCCT's STEP statistics on stdout (Message messenger level); add an unwritable-path STL test.
- `occt_edge_length` rebuilds the edge map per call (O(n²) loops).
- ✅ (M2) Implement `try Task.checkCancellation()` on entry to every `OCCTKernel` operation (protocol contract).
- ✅ (M2) Define a fallback tag for faces OCCT history leaves untagged; make `TopoTag`, `TopoRole`, `EdgeKey` Codable (needed by Edges by Tag) — remember: a new `ConstantValue` kind needs a `formatVersion` bump.

## Before M3 selection-rule and profile nodes
- FakeKernel and OCCTKernel both report a circle's axis as `direction` (by design); 'Edges by Direction' must require `kind == .line`. 2-segment profiles give vertical edges a shared `EdgeKey`; blend doesn't dedupe edges; centroid/area are zero placeholders; coverage gaps (chamfer, transform, union, intersect, tessellate).
- `Segment2D` arcs assume a CCW normalized sweep (reversed arc → negative length); `Profile2D.bounds` is conservative for partial arcs; `Plane.init` does not normalize.

## From M2
- All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids
  and meshing mutates it; never call the shim outside it (tests included).
- Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is
  prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
- Full revolves: OCCT's `Generated(edge)` is empty for planar swept faces; `BRepSweep_Revol::Shape(edge)` names them
  (cocct_build.cpp).
- Swift 6.4 crashes compiling typed-throws closures that return tuples or are passed to `serialized`; a few OCCTKernel
  closures use untyped `throws` with a comment — revert when the compiler is fixed.
- Deferred kernel items: multi-solid boolean results pass as one Solid (multi-body deferred, spec §11; see the
  `Kernel.boolean` doc comment); fillet `maxRadius` is always nil.
- Fillet/chamfer corner faces (generated from vertices) carry the `.blend` tags of every selected edge at that vertex.
  Booleans run non-destructively; inside-out solids are fixed with `BRepLib::OrientClosedSolid`, never `Reversed()`.
- `OCCTKernel` runs on the default actor executor; long OCCT calls occupy a cooperative-pool thread. Measure in M7.
- Fuse/cut call `SimplifyResult()`; if that ever drops history for a face it shows up as `.unnamed` (pinned by
  `noFaceIsUntaggedOrUnnamedInTheBracket`).

## Can wait
- `NodeID` init overlap; `EdgeKey` separators unescaped; linear topology lookups; 128-byte estimate constant.
- `NodeRegistry.all` tiebreak; `BroadcastPlan.inputs(at:)` precondition; NodeError strings not yet localised.
- Duplicate node IDs in a file collapse first-wins; O(N·L) link scans.
- Parameter commands don't mark parameter-reading nodes `.evaluating`; `setInput` doesn't check the socket exists; undo coalescing is key-only; removing a parameter and undoing re-appends it at the end.
- `formatVersion` ≤ 0 accepted; partial `ViewState` untested; `GraphFileError` has no user-facing message (M6).
- `restoreLinks` doesn't guard duplicates within one call or occupied inputs (only reachable via hand-built commands).
- `CancelsTaskNode` test assumes nodes run in the caller's task — revisit with parallel evaluation.
- Hard-coded `/opt/homebrew` OCCT prefix (packaging deferred, spec §11).
