# CreatorGeometry

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres. `Files/RegularFile.read(_:limit:)` is the bounded read of a regular file (DR-5 R23). `Spline/`: `SplineDefinition` (fit points + `SplineHandle`s, the chord-length parameter; `resolvedHandles()` solves the C3/C4 natural system, falling back to chord tangents), `SplineCurve2D` (degree-5 B-spline: poles, knots, multiplicities; `split`, `reversed`, `polyline`, `curvature(at:)`) and `Segment2D.spline`; a kernel that can't build one throws `KernelError.splinesUnsupported` (`FakeKernel` does).
