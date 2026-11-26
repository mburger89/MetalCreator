# COCCT and CreatorOCCT (the OpenCascade shim and kernel)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
  OCCT history, tessellation, STEP/STL export; `occt_segment` kind 2 is a spline edge, a degree-5 `Geom_BSplineCurve`, its poles, knots and multiplicities in the profile's shared side tables). **The only code that may touch OCCT.** Every C allocation has a
  `*_free`; no C++ exception crosses into Swift. `occt_distances` (`cocct_distance.cpp`) measures points to a solid's faces,
  picked faces or picked edges: planes and cylinders bounded by lines and circle arcs by exact formulas (`cocct_distance_analytic.hpp`),
  every other face with `BRepExtrema_DistShapeShape` (to the faces, not the solid: OCCT answers 0 for a point
  inside a solid; `occt_distances_reference` is the Extrema-only path `DistanceFastPathTests` compares to at 1e-9) and signs a solid's distance with `BRepClass3d_SolidClassifier`, only for a point inside the solid's bounds; it
  shares the points out in blocks of 64 over OCCT's thread pool while `OCCTKernel.serialized` is held, and the caller's buffer
  is the output, so it allocates nothing to free. `OCCTKernel` calls it 1,024 points at a time, checking for cancellation between.
  NS-1 shim files: `cocct_curve.cpp` (curves, the degree-5 fit), `cocct_sheet.cpp`/`.hpp` (planar surface, extrude, revolve, loft and sweep sheets, boundary roles) and `readShapes` in `cocct_import.cpp`.

Also read:

@../CreatorKernel/CLAUDE.md
@../CreatorNodes/Surfaces/CLAUDE.md
