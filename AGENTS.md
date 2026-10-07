# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine) and M2 (OCCT kernel) are done.

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
- `CreatorKernel`: the `Kernel` protocol, `Solid`, tagged topology tables, `FakeKernel` for tests.
- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
  OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
  `*_free`; no C++ exception crosses into Swift.
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.

## Commands

```sh
swift build                                  # build the library
swift build -c release
swift test                                   # run all tests
swift test --filter CreatorGraphTests        # one test target (also CreatorOCCTTests, CreatorGeometryTests, CreatorKernelTests)
swift test --filter CreatorOCCTTests         # kernel conformance + naming stability (needs OCCT)
swift test --filter 'CreatorGraphTests.EvaluatorTests/wiredValuesFlowDownstream'   # one test
```

There is no linter or formatter configured.

## Toolchain constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]` — full Swift 6 strict concurrency checking is on. Data-race violations are compile **errors**, not warnings. Shared mutable state needs an actor, `Sendable` conformance, or an explicit global-actor annotation; do not reach for `@unchecked Sendable` or `nonisolated(unsafe)` to silence a diagnostic without understanding it.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Keep new tests on Swift Testing.
- Local toolchain: Apple Swift 6.4, arm64 macOS.
- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
  Linker warnings about dylibs built for a newer macOS are expected.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
