# M0–M1 carry-over for later milestones

Deferred review findings from the M0–M1 subagent-driven run (final review triage, 2026-10-07).
Read this before writing the M2 and M3 plans.

## Before the first M2 OCCT operation
- STEP export sets the process-global `Interface_Static` unit; meshing writes triangulation into the shared TShape. Keep all OCCT access serialized inside `OCCTKernel` (dedicated serial executor recommended).
- Map `OCCTError` to `KernelError` so raw OCCT text never reaches users.
- Query sentinel `-1` is ambiguous for `occt_volume` (negative volumes exist): expose throwing/optional queries in `OCCTKernel`.
- Silence OCCT's STEP statistics on stdout (Message messenger level); add an unwritable-path STL test.
- `occt_edge_length` rebuilds the edge map per call (O(n²) loops).
- Implement `try Task.checkCancellation()` on entry to every `OCCTKernel` operation (protocol contract).
- Define a fallback tag for faces OCCT history leaves untagged; make `TopoTag`, `TopoRole`, `EdgeKey` Codable (needed by Edges by Tag) — remember: a new `ConstantValue` kind needs a `formatVersion` bump.

## Before M3 selection-rule and profile nodes
- FakeKernel: circle rim edges get `direction = normal` (collides with "parallel to Z" rules); 2-segment profiles give vertical edges a shared `EdgeKey`; blend doesn't dedupe edges; centroid/area are zero placeholders; coverage gaps (chamfer, transform, union, intersect, tessellate).
- `Segment2D` arcs assume a CCW normalized sweep (reversed arc → negative length); `Profile2D.bounds` is conservative for partial arcs; `Plane.init` does not normalize.

## Can wait
- `NodeID` init overlap; `EdgeKey` separators unescaped; linear topology lookups; 128-byte estimate constant.
- `NodeRegistry.all` tiebreak; `BroadcastPlan.inputs(at:)` precondition; NodeError strings not yet localised.
- Duplicate node IDs in a file collapse first-wins; O(N·L) link scans.
- Parameter commands don't mark parameter-reading nodes `.evaluating`; `setInput` doesn't check the socket exists; undo coalescing is key-only; removing a parameter and undoing re-appends it at the end.
- `formatVersion` ≤ 0 accepted; partial `ViewState` untested; `GraphFileError` has no user-facing message (M6).
- `restoreLinks` doesn't guard duplicates within one call or occupied inputs (only reachable via hand-built commands).
- `CancelsTaskNode` test assumes nodes run in the caller's task — revisit with parallel evaluation.
- Hard-coded `/opt/homebrew` OCCT prefix (packaging deferred, spec §11).
