# MetalCreator

[![XP cross-platform](https://github.com/mburger89/MetalCreator/actions/workflows/xp.yml/badge.svg?branch=main)](https://github.com/mburger89/MetalCreator/actions/workflows/xp.yml)

MetalCreator is a node-based parametric CAD application written in Swift. You build a part by wiring modelling operations
together in a graph, as in Grasshopper or Blender's geometry nodes, and the graph is the model: change a number and the
part is rebuilt. It is for people who want to iterate quickly on variants of a part, and for Swift developers interested in a
large application built on [MetalUI](https://github.com/mburger89/MetalUI) (MIT) and OpenCascade 7.9.

## What it does

- **Node graph.** Wire values, profiles, solids, fields and lists together on a canvas. Nodes can be grouped, the graph
  has undo and redo, and it saves to `.mcgraph` files.
- **Sketcher.** Draw points, lines, arcs and circles on a plane or face, constrain them (coincident, horizontal, vertical,
  parallel, perpendicular, tangent, equal, midpoint, concentric, symmetric, fixed) and drive them with dimensions
  (distance, length, radius, diameter, angle). A sketch is a node, so its dimensions can be wired to the rest of the graph.
- **Solid modelling** on the OpenCascade B-rep kernel: Extrude, Revolve, Loft, Boolean, Transform, Chamfer and Fillet.
  Fillets can be circular (tangent) or curvature continuous (G2). Edges can be selected by direction, tag or filter.
  Faces keep their identity through edits, so later nodes still find them.
- **Patterns.** Linear, circular, grid, curve and face layouts of hole, boss and slot features, with data trees to
  broadcast, graft, flatten and partition lists.
- **Fields.** Noise, gradient, distance and image fields to sample, cull or scatter features.
- **Implicit geometry and lattices.** Implicit boxes, cylinders and spheres combined with smooth unions, subtractions and
  intersections, plus TPMS, strut and Voronoi lattices, optionally mapped onto cylindrical, spherical or face coordinates.
  These produce meshes.
- **Analysis in the viewport.** A section tool, a measure tool (distances between picks, with measurements kept in the
  file) and zebra stripes for checking surface continuity.
- **Export** to STEP and STL, and to 3MF for mesh results.
- **Themes.** Dracula, Nord and Alucard ship with the app; you can edit them or add your own `.mctheme` files.

## Status

This is an early, single-developer project. The automated tests are extensive, but many features still have manual
checks pending (listed in [`docs/verification/human-checks.md`](docs/verification/human-checks.md)), including section,
measure and zebra stripes. macOS is the primary platform. The Linux and Windows builds are newer and less exercised.
There are no signed or notarized releases: you build from source (see [`docs/packaging.md`](docs/packaging.md) for the
packaging scripts and their limits). File formats can still change.

## Platforms and requirements

| Platform | Requirements |
|---|---|
| macOS | macOS 26 (`Package.swift`); Apple Swift 6.4 (`swift-tools-version: 6.4`, Swift 6 language mode); OpenCascade 7.9 from Homebrew (`brew install opencascade`). A packaged `MetalCreator.app` currently needs macOS 27, because the bundled libraries come from Homebrew bottles built for it. |
| Linux | Swift 6.4; OpenCascade 7.9 built from source (the recipe is `scripts/linux/Dockerfile`; the default prefix is `/opt/occt`, overridable with `OCCT_PREFIX`). Runs on MetalUI's SDL backend. CI covers x86_64 and aarch64. |
| Windows | Swift 6.4; OpenCascade 7.9.3 from vcpkg (`packaging/windows/vcpkg.json`). Runs on MetalUI's SDL backend. Built and tested in CI. |

On Linux and Windows the viewport's shaders are compiled at build time with SDL_shadercross, pinned in
`scripts/shadercross.env`; set `METALUI_SHADERCROSS` to its path.

## Build and run

`Package.swift` expects MetalUI as a sibling checkout at `../MetalUI`, so clone the two repositories side by side:

```sh
git clone https://github.com/mburger89/MetalUI.git
git clone https://github.com/mburger89/MetalCreator.git
cd MetalCreator
```

MetalCreator is built against a specific MetalUI commit. CI pins it as `METALUI_COMMIT` in
[`.github/workflows/xp.yml`](.github/workflows/xp.yml); check out that commit in your MetalUI clone if the current
MetalUI `master` does not build.

```sh
swift run MetalCreatorApp                    # start the app
swift run MetalCreatorApp docs/examples/bracket-7.2.mcgraph   # start it with a file open
swift run MetalCreatorApp --self-test        # headless check of OpenCascade, export and shaders
```

A path on the command line opens that document; inside the app use File > Open. The example is a parametric mounting
bracket: a rounded plate with a grid of holes, an L-flange, a fillet and a chamfer, driven by graph parameters.

Packaging scripts (see [`docs/packaging.md`](docs/packaging.md)):

```sh
scripts/package-app.sh                       # macOS: dist/MetalCreator.app, OpenCascade bundled, signed ad hoc
scripts/verify-app.sh [path.app]             # re-check a packaged app
scripts/linux-test.sh package                # Linux: tarball and AppImage in dist/, built in Docker
```

## How it is organised

| Module in `Sources/` | Purpose |
|---|---|
| `CreatorGeometry` | Vectors, planes, transforms and other geometry value types |
| `CreatorSketch` | The sketch model and its constraint and dimension solver |
| `CreatorKernel` | The `Kernel` protocol for B-rep operations, and a fake kernel for tests |
| `COCCT`, `CreatorOCCT` | The C++ shim over OpenCascade and the Swift kernel built on it; the only code that touches OpenCascade |
| `CreatorGraph` | Graph model, evaluator with caching and cancellation, undo, `.mcgraph` files |
| `CreatorImplicit` | Implicit solids, the evaluator, octree and mesher |
| `CreatorNodes` | The built-in node definitions |
| `CreatorStyle` | Colour themes and the app's visual style |
| `CreatorViewport` | The 3D viewport: camera, picking, rendering on Metal or SDL GPU |
| `CreatorEditor` | The node canvas, inspector and palette |
| `CreatorSketchEditor` | The sketch editing tools and overlay |
| `CreatorApp` | The application model: documents, export, section, measure, themes |
| `MetalCreatorApp` | The executable that opens the window |
| `GraphPanelPreview`, `ViewportHarness` | Development windows for the node editor and the viewport (macOS) |

## Contributing

Bug reports and ideas are welcome as [GitHub issues](https://github.com/mburger89/MetalCreator/issues). For a bug,
include the platform, what you did, and a `.mcgraph` file if you can. For a feature, describe the part you were trying to
make.

To work on the code, set up the sibling checkouts and toolchain as above, branch from `main`, and open a pull request
against `main`. Before opening it, run:

```sh
swift build --build-tests
swift test
swiftlint lint --strict                      # must report zero violations
scripts/linux-test.sh                        # the same suite on Linux, in Docker
```

CI runs on every pull request, on Linux (x86_64 and aarch64) and Windows. It does not cover macOS, so the macOS suite is
yours to run. The Windows job does not fail the run when it goes red, so read its log if you touched anything
Windows-specific.

Conventions:

- Swift 6 language mode with strict concurrency; data races are compile errors. Don't silence them with
  `@unchecked Sendable` or `nonisolated(unsafe)` without understanding why.
- Tests use Swift Testing (`import Testing`), not XCTest. New behaviour comes with tests. Code that does not
  import OpenCascade goes through the `Kernel` protocol.
- The specs in [`docs/superpowers/specs/`](docs/superpowers/specs/) are binding. Read the one for a feature before
  changing it, and update it if the behaviour changes.
- Anything a test can't see (look, feel, pointer input) gets an entry in
  [`docs/verification/human-checks.md`](docs/verification/human-checks.md).
- If the problem is in the UI framework, fix it in MetalUI instead of working around it here, and record it in
  [`docs/metalui-gaps.md`](docs/metalui-gaps.md).
- Prefer fixing code to adding `swiftlint:disable`; give any disable a reason.

`CLAUDE.md` is the detailed developer guide, with the full list of commands and toolchain notes.

## Roadmap

[`docs/roadmap.md`](docs/roadmap.md) tracks what is done and what is planned. Next are surface textures (knurl,
hex, Voronoi and embossed skins), a variants and versions interface for graph parameters, and Class A freeform surfaces
(NURBS surface nodes, control-point editing and surface-quality analysis).

## License

MetalCreator is released under the MIT License; see [`LICENSE`](LICENSE). By submitting a contribution you agree that it
is licensed under the same terms.

OpenCascade is a separate project under its own license (LGPL 2.1 with the OCCT exception). Packaged builds bundle it
(`docs/packaging.md`, "Licences in the packages").
