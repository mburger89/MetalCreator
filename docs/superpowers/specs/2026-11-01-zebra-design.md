# Zebra stripes — design

Status: draft for review, 2026-11-01. Mockup the user reviewed and called "accurate to what I have used before":
https://claude.ai/artifact/BhzPuZNCFmBi7UeeSg72tZ

## Intent

The user builds surfaces (fillets, lofts, sweeps, blends, implicit shapes) and needs to see whether they flow into each
other as intended. Zebra stripes are the standard check: reflected black and white bands over the part, read where
they cross the edges between faces. The check runs over and over while shaping, so turning it on must be one key and the
picture must be trustworthy: a good surface must not look wavy because of how we draw it.

How the three reference products do it (research, 2026-11-01; Alias and Fusion from their official help, SOLIDWORKS
from search snippets and a tutorial):

- **Fusion 360:** Inspect ▸ Zebra Analysis on selected bodies, saved as an entry in the browser's Analysis folder.
  Direction Vertical or Horizontal, Repeats 1 to 100, Opacity 0 to 100 %, Lock Stripes, High Quality. Stripes move as
  you orbit and zoom; Lock Stripes fixes them. Its help gives the reading rule: G0 edges don't align, G1 align at a sharp
  angle, G2 stay smooth.
- **Alias:** a Diagnostic Shading mode. Vertical or horizontal, Repeats, Thickness, Transparency, ambient and diffuse
  light, Lock Texture, and a light linked to the camera by default (or set by azimuth and elevation).
- **SOLIDWORKS:** View ▸ Display ▸ Zebra Stripes. Number and width of stripes, horizontal or vertical, a Stripe Accuracy
  slider.

## Goals

1. A view mode that draws zebra stripes on every shown part: OpenCascade solids and meshes (implicit shapes, lattices,
   decimated meshes) alike. The user's answer: "any surface really". (MetalCreator has no mesh import; building one is
   not part of this.)
2. Stripes that are reflections of a striped environment fixed to the camera, so they slide over the part as the view
   turns. This sliding is how a flaw shows itself.
3. Controls as in the mockup: **Direction** (Horizontal, Vertical), **Stripes** (count, 4 to 40, default 12: `count`
   black-and-white periods over the full turn of the reflection's angle, the density of the mockup the user approved),
   **Black share** (20 % to 80 %, default 50 %), **Lock stripes to the part** (off by default).
4. Edges read correctly: a crease breaks the stripes, a tangent joint kinks them, a curvature-continuous joint lets them
   flow. Nothing in our drawing may add a break or kink of its own.
5. macOS (Metal) and Linux and Windows (SDL GPU), like every viewport feature.

## Non-goals

- A saved analysis object, a browser entry, or per-body scope (Fusion's model). Zebra is a view mode.
- Curvature maps, curvature combs, draft analysis, isophotes, highlight lines. They may share this work later; they are
  not part of it.
- A numeric continuity report (G0/G1/G2 per edge). The stripes are read by eye.
- Custom stripe colours, opacity, light controls. None of the three references document colours; opacity and light
  controls are left out to keep the panel to the four controls the user saw.

## Anti-goals (a failure even if it works)

- **Faceting that reads as a flaw.** Stripes that zigzag along triangle edges on a smooth fillet send the user chasing a
  problem that isn't there. This is the main risk and the reason for the display-mesh section below.
- Zebra that makes orbiting noticeably slower than it is without it.
- An edit to the model. Like the Section and Measure, zebra is view state: no command, no undo step, no edited dot.

## How it behaves

- **Starting and stopping:** a "Zebra" toggle in the top bar beside Section and Measure, View ▸ Zebra Stripes, and the
  key Z (in the viewport key context; a focused text field types it). The Zebra panel (glass, the mockup's layout) sits
  where the Section panel does; when both are open the panels stack (Section, Measure, Zebra, top to bottom).
- **Saved:** the settings, whether zebra is on and whether Lock is on (with the frame it captured, below) are saved as an
  optional `ViewState` key (no format bump), like `ViewState.section`, so a reopened file shows the same stripes. New
  starts with zebra off.
- **With other modes:** zebra replaces the part's shading, nothing else. Edges, the section cap and its outlines,
  Measure's dimensions, handles and the field preview's slice still draw on top. A field tint and zebra are exclusive:
  while zebra is on the tint is not drawn (the legend stays). Ghosts (pick sessions, Selected-node preview) are not
  striped. Sketch mode hides zebra, as it hides the section.
- **Lock:** with Lock on, the stripes are painted onto the part as they stood at the moment Lock was ticked: they stop
  sliding and stay on the same places of the surface while the user orbits, as Fusion's Lock Stripes and Alias's Lock
  Texture do. Unticking returns them to the camera.
- **Clip:** the section's clip applies to striped faces exactly as to shaded ones.

## The stripes (the decided maths)

Per pixel, in view space: the view direction `v` (toward the eye) and the interpolated, renormalized surface normal `n`
give the reflection `r = 2(n·v)n − v`. Horizontal stripes are bands of the angle of `r` about the camera's horizontal
axis, vertical stripes of its angle about the camera's vertical axis; the band function is a square wave with `count`
periods over the half-circle and the black share as its duty cycle, antialiased over the pixel's derivative (`fwidth`)
so stripes have no shimmer. With Lock on, the shader uses the camera's world-space view direction and basis captured at the moment Lock was ticked
(the *lock frame*) in place of the live ones, with the normal in world space, so the stripes depend on the normal alone
and stay fixed to the surface. A little diffuse light from the existing key light keeps the surface reading as a surface.

Back faces seen through a clip use the same rule with the flipped normal.

## The display mesh

Today a solid is tessellated with a 0.05 mm linear deflection and a 0.5 rad angular deflection, and its vertex normals
are the surface's exact normals (OpenCascade's `ComputeNormals`). Zebra reflects the normal, so it magnifies any error
in the interpolated normal: 0.5 rad between neighbouring vertex normals is far too coarse.

Decided: while zebra is on, solids are tessellated with a finer angular deflection, **0.05 rad**, keeping the linear
deflection, and these finer meshes are what the viewport draws and picks (the zebra mesh is not a second mesh beside the
normal one). Turning zebra off goes back to the normal meshes. The finer mesh is computed off the main actor; until it
lands the part is striped on its normal mesh. Meshes keep their own resolution. A mesh with vertex normals (from the field's gradient) uses them; a mesh without
(a Decimate output) uses the display path's averaged vertex normals, as it is shaded today. Those meshes are faceted
approximations, and zebra shows them as such; no extra smoothing.

Left to the builder: whether 0.05 rad holds the stripe quality on the bracket and a lofted fillet without making the
re-tessellation too slow (measure it; a benchmark row records it), and how the finer meshes are cached.

## What is left to the builder

- The renderer changes in both backends (a stripe pipeline or a mode of the existing shaded pipeline), keeping the MSL,
  HLSL and Swift GPU structs in step as CLAUDE.md requires.
- Where the zebra state lives (`ZebraSettings` in CreatorGraph beside `SectionSettings`, a `ZebraModel` in CreatorApp, is
  the natural shape) and the panel's construction.
- The tests: settings round trip, the maths against a CPU reference, a render test per backend, the panel, the key, the
  view-state encoding.
- Human checks (a new group) and a benchmark row for the zebra tessellation and an orbiting frame.

## Later

- ~~Mesh import (STL, 3MF), so imported meshes can be checked with zebra too.~~ **Done** (2026-11-03): `2026-11-03-mesh-import-design.md`;
  an imported mesh is striped like any opaque solid, and the numbers are in `docs/verification/performance.md` ("Mesh import").
