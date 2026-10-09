# Viewport Input on MetalUI C7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3D viewport's input stopgaps with MetalUI C7's input APIs (scroll and pinch zoom, right and middle drags, tap and context-menu locations, cursors, modifiers from the drag value), and frame the part in the model area the floating panels leave.

**Architecture:** All behaviour stays in `@MainActor @Observable ViewportModel`, testable without a GPU or a window: new model entry points take plain values (`ScreenPoint`, `ViewportModifiers`, `ViewportPointerButton`, `ViewportScrollPhase`) and `ViewportView` only forwards MetalUI gesture values to them. Each MetalUI type the viewport reads gets one small `+MetalUI.swift` conversion, unit-tested. `CameraNavigation.frame` learns the model area's insets. Keys are untouched (key scoping is MetalUI C9).

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftPM, Swift Testing, MetalUI at `../MetalUI` master `c62d6ba` (C7 merged: `SpatialTapGesture`, `MagnifyGesture`, `DragGesture(minimumDistance:coordinateSpace:button:)`, `DragGesture.Value.modifiers`, `.onScrollWheel`, `ScrollEvent.phase`/`momentumPhase`/`location`, `.pointerStyle(_:)`, the located `.contextMenu`).

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§6.3 viewport, §9 MetalUI gaps, and every Errata section; Errata (M6)'s "Look At is framed … in the whole viewport, not the model area" is what Task 1 fixes). MetalUI's final API names: `../MetalUI/docs/superpowers/2026-10-08-input-apis-decisions.md` (`CI-A` … `CI-AL`) and `../MetalUI/docs/record/81-input-apis.md`. The C7 items being closed: `docs/metalui-gaps.md` (items 1–5, gap 4, gap 5) and `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` ("From M4", and "From M6"'s framing item).

**Files shared with other tracks** (everything else is inside `Sources/CreatorViewport`, `Sources/ViewportHarness` and `Tests/CreatorViewportTests`):
- `Sources/CreatorApp/AppRoot.swift` — one line (line 20: `ViewportView(model: model.viewport, modifiers: input.modifiers)` → `ViewportView(model: model.viewport)`). The editor-polish track edits `AppRoot` (its overlay); expect a trivial merge.
- `Sources/CreatorApp/AppInput.swift` — deletes the `modifiers` tracker property, its `install(on:)` line and one doc-comment line.
- `Sources/CreatorApp/AppModel+Scene.swift` — one line in `refreshScene()` (and its doc comment) sets `viewport.isPicking`.
- `Tests/CreatorAppTests/PickCursorTests.swift` — new file.
- `CLAUDE.md` and `AGENTS.md` — one paragraph (the "Viewport input stopgaps" line).
- `docs/metalui-gaps.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, `docs/verification/human-checks.md` (a new group VC, inserted before group M5, and three lines of group V).
- **Not touched:** `CreatorEditor` (the graph panel's C7 adoption is a later plan; its stale mention of `ViewportModifierTracker` in `GraphPanelInput.swift`'s doc comment is left for it), `docs/superpowers/roadmap.md` and the spec (mark the roadmap rows "C7 adoption" (viewport part) and "Viewport: frame in the model area" when merging), `Package.swift`.

## Global Constraints

- Platforms are `.macOS(.v26)` (spec Errata (M0–M1)); `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are compile errors.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- Models are `@MainActor @Observable`; behaviour lives in models, views are thin MetalUI glue (CLAUDE.md, `CreatorViewport` bullet).
- One type per file; no force unwraps; no GCD; FormatStyle for user-facing numbers.
- `CreatorViewport` depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph (CLAUDE.md).
- MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI, never worked around here (spec §9: "The app never patches around a gap in a way that would have to be undone").
- The camera reaches `ViewState` only through `cameraSettled`/`homeChanged`, never per frame (CLAUDE.md; spec §7.3: "Orbiting the viewport with the bracket shown runs at 60 fps").
- `swift build --build-tests` adds no warning (master's only compiler warning is `ContextMenuTests.swift`'s pre-existing "'underPointer' mutated after capture by sendable closure"; OCCT `ld: warning`s are expected); `swift test` passes; `swiftlint lint --strict` reports zero violations.
- Never edit `Package.swift`'s MetalUI path. Run every command from the worktree root.
- Keep the keyboard bindings as they are: F, `=`, `shift-+`, `+` and `-` in `ViewportInputMap.keyBindings`, window-wide with the `!Panel` context (MetalUI C9 will scope them).

## Key decisions

1. **Clicks are a `SpatialTapGesture`, declared inside the primary drag.** MetalUI's arena (`IX-D` item 3) runs normal gestures innermost first and declaration order is inner to outer, so `.gesture(SpatialTapGesture()).gesture(DragGesture(minimumDistance: 5))` gives a click to the tap and a move to the drag (`G9a`/`G9b`). A drag never clicks, even one that returns to its start; `ViewportInputMap.clickSlop` (3 pt) is replaced by `dragThreshold` (5 pt, MetalUI's tap slop). A click calls `events.pressed()` and stops an animation, as a press did.
2. **The press logic moves from the view into the model.** `dragChanged(from:to:modifiers:button:)` / `dragEnded(from:at:modifiers:button:)` begin the drag lazily from the value's `startLocation` (the view used to do this with `isPointerDown`). `pointerDown(at:modifiers:button:)` (`button` defaults to `.primary`), `pointerDragged(to:)` and `pointerUp(at:)` stay public: `CreatorAppTests.ViewportGlueTests` drives them.
3. **Buttons.** Middle-drag always pans; right-drag always orbits about the point under the press (on the view cube, as a cube drag); handles are grabbed only by the primary button. One drag at a time. The drag under way ends first, where it was, when its release must have been lost: a value of the same button from a new press (MetalUI `CI-AB` replaces such an arena), or a primary value or click while another button's drag is under way (MetalUI forms the primary arena on every primary press, apart from the button arena, `CI-F` item 3, so the primary button always gets its drag). A right or middle value while another drag is under way is ignored, as MetalUI ignores that press (`CI-AA` item 4). The primary drag's Shift/⌥ mode comes from `DragGesture.Value.modifiers` at its first change (spec §9 kept).
4. **The face menu picks at the right press.** `.contextMenu { (location: Point<Pixels>?) in … }` (`CI-R`) hands `contextMenuItems(at:)` the press point, which is picked then and there. `nil` (a keyboard or accessibility open) and a press on the view cube give no menu. The hover pick (`refreshHover()`) is kept for the hover tint only. A right press that moves less than 5 points opens the menu on its release; one that moves further orbits (`CI-F` item 4).
5. **Scroll zoom.** `.onScrollWheel` claims every scroll over the surface. A positive `delta.y` zooms in (the sign MetalUI's canvas demo uses; human check VC1 confirms the feel), `exp(Δy × 0.01)` per event, so a wheel step (10 pt) is about 10%. Nothing settles per event: a trackpad scroll (`.mayBegin`/`.began`/`.changed`) settles once at `.ended`/`.cancelled`, and a run of wheel steps (`phase == .none`, which is also every SDL scroll, `CI-I` item 6) settles once the wheel has been still for 0.15 s (`ViewportInputMap.wheelSettleDelay`, timed on the injected `ViewportClock`, so `ManualClock` tests stay deterministic); momentum is ignored (C7 item 1, "momentum ignored for viewport zoom"). The hover is re-picked only when a scroll settles, never per event.
6. **Pinch zoom** applies `MagnifyGesture`'s cumulative magnification to the camera the pinch began with, about `startLocation` (`CI-C` item 3: the pointer doesn't move during a pinch), clamped below at 0.05 (MetalUI's magnification is `1 + Σ` and can reach 0 or below), and settles once at its end. A pinch that begins at another centre while one is under way means the old one lost its end (MetalUI drops it silently, `CI-AB`), so the old one settles first; the same rule ends a drag when its button presses again (decision 3). That MetalUI says nothing when it drops a gesture is new gap **VI-a**. **No `RotateGesture`**: spec §6.3 gives the viewport no rotate binding.
7. **Cursors.** A closed hand (`.grabActive`) while a drag orbits or pans (the cube's drag included); a crosshair (`.rectSelection`, MetalUI's crosshair) while the host is picking edges (`ViewportModel.isPicking`, set by `AppModel.refreshScene()`); otherwise no style (the arrow) — the viewport isn't a grab surface at rest, and ⌥-zoom and handle drags keep the arrow. `activeDragMode` is tracked state written once per press and release, never per move.
8. **Framing in the model area.** `CameraNavigation.frame(_:_:size:insets:margin:)` fits the bounding sphere in the model area's angular extent and moves the target so the bounds' centre projects to the area's centre. The first framing, F, Home without a saved home view, and Look At pass `modelArea`. A saved home view is not re-framed. Insets the view can't honour (negative, non-finite, or leaving under one point) are ignored for framing only; validating `setModelArea` stays M7's (carry-over From M6). Because the target is then off the part, everything that turned about the target now turns about the point shown at the model area's centre (`ViewportModel.modelAreaPivot(_:)`), so a part framed there stays there: the ◀▲▼▶ arrows and the cube's face, edge and corner clicks (`perform(.rotate)`, `perform(.view)`) and a cube drag (`CameraNavigation.orbit` with that pivot). The +/− keys with no pointer over the view zoom toward the model area's centre, not the view's. With no insets all of these are exactly what they were.

## Review Focus

The six inputs the spec implies but doesn't spell out that are most likely to bite, each pinned by a test in the task that owns the code:

1. **A right click on the view cube** must not open a face menu for the face drawn behind the cube — `noFaceMenuOverTheViewCubeOrWithoutAPointer` (Task 4).
2. **A hard pinch-in** drives MetalUI's magnification to zero or below; the camera must hold zoomed out, not spring back to where the pinch began or go non-finite — `aHardPinchInHoldsInsteadOfSpringingBack` (Task 6).
3. **A drag whose release never arrives** (the pointer left the window, the app lost focus, a modal took the pointer) must not swallow every later drag, and above all not the primary button's — `aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain`, `aPrimaryDragAfterALostMiddleReleaseStillOrbits` (Task 2), `aClickAfterALostDragEndsItAndHoversAgain` (Task 3), `aClickAfterALostDragBringsBackTheArrow` (Task 7).
4. **A window narrower than its panels** (or a negative or non-finite inset) must still frame the whole part in a finite camera — `insetsTheViewCantHonourAreIgnored` (Task 1).
5. **A trackpad scroll's many events, or a free-spinning wheel's** (and a trackpad's momentum glide) must not write the camera into the document, or pick on the GPU, per event, which would rebuild the graph panel at 60 Hz (spec §7.3) — `aTrackpadScrollZoomsAndSettlesOnceWhenItEnds`, `aRunOfWheelStepsSettlesOnce`, `momentumIsIgnored`, `aScrollThatDoesntZoomReportsNothing` (Task 5).
6. **A part framed in the model area must stay there** when the ◀▲▼▶ arrows, a cube click or a cube drag turn the camera, or the +/− keys zoom with no pointer over the view; turning about the target (now off the part) would swing it under the inspector or the bottom panel — `theArrowsTheCubeAndACubeDragTurnThePartWhereItIs`, `keyZoomWithoutAPointerZoomsTowardTheModelAreaCentre` (Task 1).

## Risks left open

- **Animated turns pass off-centre.** The arrows and the cube's regions end with the part centred in the model area, but `CameraAnimation` interpolates the target linearly, so mid-animation the part can drift (it comes back by the end, 0.25 s). Human check VC8 looks at it.
- **Chorded buttons.** A primary press during a live right or middle drag ends that drag (the price of never losing primary input). Releasing the right button afterwards begins and ends an empty right drag (one `pressed()`, no camera change); moving it first jumps the orbit by the distance from the right press. Nothing in spec §6.3 binds a chord.
- **A lost right or middle release** keeps that drag, its closed hand and a still hover until the next primary press or click or the next drag of that button (VI-a); a drag of the other of the two is ignored meanwhile.
- **The +/− keys still settle per press** (and per key repeat), as on master; a held key writes the camera into the document at the repeat rate. Measured with spec §7.3 in M7, not here.
- **The wheel's settle delay** (0.15 s) is a guess; VC1 checks that the tint catching up after the wheel stops doesn't read as lag.
- **The view glue isn't exercised by a test** (no headless MetalUI window, gap M6-e); group VC covers it by hand.

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorViewport/Overlay/ViewportInsets.swift` (modify) | 1 | `usable(in:)`: the insets framing can honour |
| `Sources/CreatorViewport/Camera/CameraNavigation.swift` (modify) | 1 | `frame(_:_:size:insets:margin:)` centres and fits in the model area |
| `Sources/CreatorViewport/Model/ViewportModel.swift` (modify) | 1, 4, 5, 6, 7 | `defaultHome` framing; `scrollStartPose`, `wheelSettleTask`, `pinchStart`; `isPicking`, `activeDragMode`; doc of `refreshHover()` |
| `Sources/CreatorViewport/Model/ViewportModel+ModelArea.swift` (modify) | 1 | `modelAreaCentre`, `modelAreaPivot(_:)`, `centring(_:inTheModelAreaOf:)` |
| `Sources/CreatorViewport/Model/ViewportModel+Commands.swift` (modify) | 1 | F frames in the model area; the arrows and cube regions turn about its centre; key zoom toward it |
| `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift` (modify) | 1, 4 | Look At in the model area; `contextMenuItems(at:)`, `faceRef(for:)` |
| `Sources/CreatorViewport/Input/ViewportPointerButton.swift` (create) | 2 | The button behind a drag |
| `Sources/CreatorViewport/Input/ViewportPointerButton+MetalUI.swift` (create) | 2 | → MetalUI `MouseButton` |
| `Sources/CreatorViewport/Input/ViewportInputMap.swift` (modify) | 2, 3, 5, 6 | Bindings: `dragMode(for:button:)`, `dragThreshold`, `scrollZoomPerPoint`, `wheelSettleDelay`, `minimumMagnification` |
| `Sources/CreatorViewport/Model/DragState.swift` (modify) | 2 | Records the drag's button |
| `Sources/CreatorViewport/Model/ViewportModel+Input.swift` (modify) | 1, 2, 3, 7 | A cube drag turns about the model area's centre; `dragChanged`/`dragEnded`, buttons in `pointerDown`, lost releases, `click(at:)`, drags never click, `activeDragMode` |
| `Sources/CreatorViewport/View/ViewportModifierTracker.swift` (delete) | 2 | — |
| `Sources/CreatorViewport/View/ViewportView.swift` (modify) | 2 | `init(model:)` |
| `Sources/CreatorViewport/View/ViewportView+Parts.swift` (modify) | 2–7 | The surface's gestures, wheel, menu and pointer style |
| `Sources/CreatorApp/AppRoot.swift`, `AppInput.swift` (modify) | 2 | Drop the tracker |
| `Sources/ViewportHarness/main.swift` (modify) | 2, 7 | Drop the tracker; `HARNESS_PICK=1` |
| `Sources/CreatorViewport/Input/ViewportScrollPhase.swift` (create) | 5 | Step, moving, ended, momentum |
| `Sources/CreatorViewport/Input/ViewportScrollPhase+MetalUI.swift` (create) | 5 | From MetalUI `ScrollEvent` |
| `Sources/CreatorViewport/Model/ViewportModel+Scroll.swift` (create) | 5 | `scrolled(by:at:phase:)`, the wheel's settle, `waitForScroll()` |
| `Sources/CreatorViewport/Model/ViewportModel+Pinch.swift` (create) | 6 | `pinchChanged(magnification:centre:)`, `pinchEnded()` |
| `Sources/CreatorViewport/Model/PinchStart.swift` (create) | 6 | The camera and centre a pinch began with |
| `Sources/CreatorViewport/Input/ViewportCursor.swift` (create) | 7 | Crosshair, grabbing |
| `Sources/CreatorViewport/View/ViewportCursor+MetalUI.swift` (create) | 7 | → MetalUI `PointerStyle` |
| `Sources/CreatorViewport/Model/ViewportModel+Cursor.swift` (create) | 7 | `cursor` |
| `Sources/CreatorApp/AppModel+Scene.swift` (modify) | 7 | `viewport.isPicking` follows `pick` |
| Tests: `ModelAreaFramingTests` (1), `ButtonDragTests` (2), `InputMapTests` (2, 5), `ViewportInputTests`/`ViewportEventTests` (3), `ContextMenuTests` (4), `ScrollZoomTests` (5), `PinchZoomTests` (6), `CursorTests` (7) in `Tests/CreatorViewportTests`; `PickCursorTests` (7) in `Tests/CreatorAppTests` | | |
| `docs/metalui-gaps.md`, carry-over note, `docs/verification/human-checks.md`, `CLAUDE.md`, `AGENTS.md` (modify) | 8 | What C7 closed; group VC |

Test counts (master: **901**; `CreatorViewportTests` 117, `CreatorAppTests` 55): after Task 1 **909**, 2 **919**, 3 **923**, 4 **925**, 5 **932**, 6 **937**, 7 **942**, 8 **942** (master + 41). To total `swift test`'s per-bundle lines: `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`.

---

### Task 1: Frame the part in the model area

Roadmap row "Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3)"; spec Errata (M6).

**Files:**
- Modify: `Sources/CreatorViewport/Overlay/ViewportInsets.swift`, `Sources/CreatorViewport/Camera/CameraNavigation.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift` (`defaultHome(for:)`), `Sources/CreatorViewport/Model/ViewportModel+ModelArea.swift`, `Sources/CreatorViewport/Model/ViewportModel+Commands.swift` (`perform(_:)`'s `.view` and `.rotate`, `zoom(by:)`, `frameSelectionOrEverything()`), `Sources/CreatorViewport/Model/ViewportModel+Input.swift` (`pointerDragged(to:)`'s `.cube`), `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift` (`lookAt(_:)`)
- Test: `Tests/CreatorViewportTests/ModelAreaFramingTests.swift` (create)

**Interfaces:**
- Consumes: `ViewportModel.modelArea: ViewportInsets` (set by the app through `setModelArea(_:)`, unchanged).
- Produces: `CameraNavigation.frame(_ bounds: BoundingBox, _ pose: CameraPose, size: ViewportSize, insets: ViewportInsets = ViewportInsets(), margin: Double = 1.1) -> CameraPose`; `ViewportInsets.usable(in size: ViewportSize) -> ViewportInsets` (internal); on `ViewportModel` (internal): `modelAreaCentre: ScreenPoint`, `modelAreaPivot(_ pose: CameraPose) -> Vector3`, `centring(_ pivot: Vector3, inTheModelAreaOf turned: CameraPose) -> CameraPose`, `animateTurn(_ turn: (CameraPose) -> CameraPose)`. With no insets, `frame`, the arrows, the cube's regions, a cube drag and key zoom do exactly what they did before.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/ModelAreaFramingTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// Framing in the model area (spec §6.3, roadmap "Viewport: frame in the model area"): the first framing, F and
/// Look At centre the part in the part of the view the floating panels leave, and fit it there.
@MainActor
struct ModelAreaFramingTests {
    let size = ViewportSize(width: 800, height: 500)
    /// The app's left dock: the top bar, the graph panel on the left and the inspector on the right.
    let panels = ViewportInsets(top: 60, leading: 300, bottom: 0, trailing: 260)

    /// The model area's centre and its rectangle, in view points.
    var areaCentre: ScreenPoint {
        ScreenPoint((panels.leading + size.width - panels.trailing) / 2, (panels.top + size.height - panels.bottom) / 2)
    }

    func isInsideTheArea(_ point: ScreenPoint) -> Bool {
        point.x >= panels.leading && point.x <= size.width - panels.trailing
            && point.y >= panels.top && point.y <= size.height - panels.bottom
    }

    func makeModel(pose: CameraPose? = CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4)) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        model.setModelArea(panels)
        return model
    }

    @Test(arguments: [Projection.perspective, .orthographic])
    func framingCentresTheBoundsInTheModelAreaAndFitsEveryCorner(_ projection: Projection) throws {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: Vector3(500, 0, 0), distance: 3, yaw: 0.8, pitch: 0.6, projection: projection)
        let framed = CameraNavigation.frame(bounds, start, size: size, insets: panels)
        #expect(framed.yaw == start.yaw && framed.pitch == start.pitch && framed.projection == projection)
        let centre = try #require(CameraMath.project(bounds.center, framed, size: size, sceneRadius: 40)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(bounds) {
            let point = try #require(CameraMath.project(corner, framed, size: size, sceneRadius: 40)).point
            #expect(isInsideTheArea(point), "\(point) is under a panel")
        }
    }

    @Test func noInsetsFrameInTheWholeViewAsBefore() {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: .zero, distance: 3, yaw: 0.8, pitch: 0.6)
        let framed = CameraNavigation.frame(bounds, start, size: size)
        #expect(framed.target == bounds.center)
        #expect(framed == CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets()))
    }

    @Test func insetsTheViewCantHonourAreIgnored() {
        let bounds = BoundingBox(min: Vector3(-30, -10, 0), max: Vector3(30, 20, 6))
        let start = CameraPose(target: .zero, distance: 3, yaw: 0.8, pitch: 0.6)
        let whole = CameraNavigation.frame(bounds, start, size: size)
        // Panels wider than the view, a model area thinner than a point, and an empty view: the whole view is used.
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets(leading: 500, trailing: 400)) == whole)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: ViewportInsets(top: 250, bottom: 249.5)) == whole)
        let empty = ViewportSize(width: 0, height: 0)
        #expect(CameraNavigation.frame(bounds, start, size: empty, insets: panels)
            == CameraNavigation.frame(bounds, start, size: empty))
        // Negative and non-finite sides count as none.
        let odd = ViewportInsets(top: -40, leading: .nan, bottom: .infinity, trailing: 0)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: odd) == whole)
        #expect(CameraNavigation.frame(bounds, start, size: size, insets: odd).isFinite)
    }

    @Test func theFirstFramingCentresThePartInTheModelArea() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(box.bounds) {
            #expect(isInsideTheArea(try #require(CameraMath.project(corner, model.pose, size: size)).point))
        }
    }

    @Test func fFramesThePartInTheModelArea() async throws {
        let model = makeModel()
        let box = try await fakeBox(width: 80)
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        model.performKey(.frame)
        await model.waitForAnimation()
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
        for corner in corners(box.bounds) {
            #expect(isInsideTheArea(try #require(CameraMath.project(corner, model.pose, size: size)).point))
        }
    }

    @Test func lookAtCentresTheFaceInTheModelArea() async throws {
        let model = makeModel()
        model.show([ViewportItem(solid: try await fakeBox(width: 80))])
        await model.waitForMeshes()
        model.choose(.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))
        await model.waitForAnimation()
        #expect(isClose(model.pose.toEye, .unitX), "the right face looks along +X")
        // The right face is 20 × 30 at x = 40, centred on (40, 0, 15).
        let centre = try #require(CameraMath.project(Vector3(40, 0, 15), model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-9))
    }

    /// The arrows, the cube's regions and a cube drag turn the camera about the point shown at the model area's
    /// centre, not about the target (which framing moved off the part), so the part stays in the model area instead
    /// of swinging under a panel.
    @Test func theArrowsTheCubeAndACubeDragTurnThePartWhereItIs() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        func partCentre() throws -> ScreenPoint {
            try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        }
        let commands: [ViewportCommand] = [.rotate(.right), .rotate(.up), .rotate(.right), .view(.front), .view(.isometric)]
        for command in commands {
            model.perform(command)
            await model.waitForAnimation()
            #expect(isClose(try partCentre(), areaCentre, tolerance: 1e-6), "after \(command)")
        }
        let cube = model.cubeLayout.center
        model.pointerDown(at: cube, modifiers: [])
        model.pointerDragged(to: ScreenPoint(cube.x + 30, cube.y + 12))
        model.pointerUp(at: ScreenPoint(cube.x + 30, cube.y + 12))
        #expect(isClose(try partCentre(), areaCentre, tolerance: 1e-6), "after a cube drag")
    }

    @Test func keyZoomWithoutAPointerZoomsTowardTheModelAreaCentre() async throws {
        let model = makeModel(pose: nil)
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let framed = model.pose
        model.performKey(.zoomIn)
        #expect(isClose(model.pose.distance, framed.distance / ViewportInputMap.keyZoomFactor))
        let centre = try #require(CameraMath.project(box.bounds.center, model.pose, size: size)).point
        #expect(isClose(centre, areaCentre, tolerance: 1e-6))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `ModelAreaFramingTests.swift:…: error: extra argument 'insets' in call`.

- [ ] **Step 3: Teach framing the model area**

In `Sources/CreatorViewport/Overlay/ViewportInsets.swift`, replace:

```swift
    }
}
```

with:

```swift
    }

    /// These insets as far as a view of `size` can honour them, for framing: a negative or non-finite side counts
    /// as 0, and insets that would leave a model area under one point wide or high are dropped (the whole view is
    /// used), as they are for an empty view.
    func usable(in size: ViewportSize) -> ViewportInsets {
        func side(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
        let result = ViewportInsets(top: side(top), leading: side(leading), bottom: side(bottom), trailing: side(trailing))
        guard !size.isEmpty, size.width - result.leading - result.trailing >= 1,
              size.height - result.top - result.bottom >= 1 else { return ViewportInsets() }
        return result
    }
}
```

In `Sources/CreatorViewport/Camera/CameraNavigation.swift`, replace:

```swift

    /// Centres `bounds` and backs off until its bounding sphere fits the view with `margin`, keeping the
    /// orientation and projection. A point or flat box still gets a usable distance. Non-finite bounds change nothing.
    static func frame(_ bounds: BoundingBox, _ pose: CameraPose, size: ViewportSize, margin: Double = 1.1) -> CameraPose {
        guard bounds.min.isFinite, bounds.max.isFinite else { return pose }
        let radius = max(bounds.size.length / 2, 0.5)
        let halfVertical = CameraPose.fieldOfView / 2
        let halfHorizontal = atan(tan(halfVertical) * size.aspect)
        var next = pose
        next.target = bounds.center
        next.distance = min(max(radius * margin / sin(min(halfVertical, halfHorizontal)), minimumDistance), maximumDistance)
        return next
```

with:

```swift

    /// Centres `bounds` in the model area (the view less `insets`, spec §6.3) and backs off until its bounding
    /// sphere fits that area with `margin`, keeping the orientation and projection. Insets the view can't honour are
    /// ignored (`ViewportInsets.usable(in:)`). A point or flat box still gets a usable distance. Non-finite bounds
    /// change nothing.
    static func frame(_ bounds: BoundingBox, _ pose: CameraPose, size: ViewportSize, insets: ViewportInsets = ViewportInsets(),
                      margin: Double = 1.1) -> CameraPose {
        guard bounds.min.isFinite, bounds.max.isFinite else { return pose }
        let area = insets.usable(in: size)
        let radius = max(bounds.size.length / 2, 0.5)
        // The area's width and height in units of the view's height: the tangent of an angle across it.
        let high = size.isEmpty ? 1 : (size.height - area.top - area.bottom) / size.height
        let wide = size.isEmpty ? size.aspect : (size.width - area.leading - area.trailing) / size.height
        let tanHalf = tan(CameraPose.fieldOfView / 2)
        let halfVertical = atan(tanHalf * high)
        let halfHorizontal = atan(tanHalf * wide)
        var next = pose
        next.distance = min(max(radius * margin / sin(min(halfVertical, halfHorizontal)), minimumDistance), maximumDistance)
        // The target sits at the view's centre; move it so the bounds' centre lands on the area's centre instead.
        let scale = CameraMath.millimetresPerPoint(next, size: size)
        let offsetX = (area.leading - area.trailing) / 2
        let offsetY = (area.top - area.bottom) / 2
        next.target = bounds.center - next.right * (offsetX * scale) + next.up * (offsetY * scale)
        return next
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift

    /// Isometric, perspective, framed on `bounds`.
    func defaultHome(for bounds: BoundingBox) -> CameraPose {
```

with:

```swift

    /// Isometric, perspective, framed on `bounds` in the model area.
    func defaultHome(for bounds: BoundingBox) -> CameraPose {
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
        home.projection = .perspective
        return CameraNavigation.frame(bounds, home, size: viewSize)
    }
```

with:

```swift
        home.projection = .perspective
        return CameraNavigation.frame(bounds, home, size: viewSize, insets: modelArea)
    }
```

In `Sources/CreatorViewport/Model/ViewportModel+Commands.swift`, replace:

```swift

    /// Spec §6.3: "F frames the selection, or everything". With nothing shown, nothing happens.
    func frameSelectionOrEverything() {
        guard let bounds = selectionBounds() ?? sceneBounds else { return }
        animate(to: CameraNavigation.frame(bounds, currentPose(), size: viewSize))
    }
```

with:

```swift

    /// Spec §6.3: "F frames the selection, or everything", in the model area the panels leave. With nothing shown,
    /// nothing happens.
    func frameSelectionOrEverything() {
        guard let bounds = selectionBounds() ?? sceneBounds else { return }
        animate(to: CameraNavigation.frame(bounds, currentPose(), size: viewSize, insets: modelArea))
    }
```

In `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`, replace:

```swift

    /// Look At (spec §6.3): animates to face the face's normal, orthographic, framed on the face.
    public func lookAt(_ ref: ViewportFaceRef) {
```

with:

```swift

    /// Look At (spec §6.3): animates to face the face's normal, orthographic, framed on the face in the model area.
    public func lookAt(_ ref: ViewportFaceRef) {
```

In `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`, replace:

```swift
        target.projection = .orthographic
        animate(to: CameraNavigation.frame(bounds, target, size: viewSize))
    }
```

with:

```swift
        target.projection = .orthographic
        animate(to: CameraNavigation.frame(bounds, target, size: viewSize, insets: modelArea))
    }
```

The target is now off the part, so what turned about the target turns about the point at the model area's centre.

In `Sources/CreatorViewport/Model/ViewportModel+ModelArea.swift`, replace:

```swift
extension ViewportModel {
    /// The overlays' margin from the model area's edges, in points.
```

with:

```swift
import CreatorGeometry

extension ViewportModel {
    /// The overlays' margin from the model area's edges, in points.
```

In `Sources/CreatorViewport/Model/ViewportModel+ModelArea.swift`, replace:

```swift
        triadLayout.bottom = insets.bottom + Self.overlayMargin
    }
}
```

with:

```swift
        triadLayout.bottom = insets.bottom + Self.overlayMargin
    }

    /// The model area's centre in view points: where framing puts the part. The view's centre when the insets
    /// can't be honoured (`ViewportInsets.usable(in:)`).
    var modelAreaCentre: ScreenPoint {
        let area = modelArea.usable(in: viewSize)
        return ScreenPoint((area.leading + viewSize.width - area.trailing) / 2,
                           (area.top + viewSize.height - area.bottom) / 2)
    }

    /// The model point `pose` shows at the model area's centre, on the plane through its target. The arrows, the
    /// cube's regions and a cube drag turn about it, so a part framed in the model area stays there. With no insets
    /// it's the target.
    func modelAreaPivot(_ pose: CameraPose) -> Vector3 {
        guard !viewSize.isEmpty else { return pose.target }
        let offset = modelAreaCentre - viewSize.center
        let scale = CameraMath.millimetresPerPoint(pose, size: viewSize)
        return pose.target + pose.right * (offset.x * scale) - pose.up * (offset.y * scale)
    }

    /// `turned` moved, not turned, so that it shows `pivot` at the model area's centre.
    func centring(_ pivot: Vector3, inTheModelAreaOf turned: CameraPose) -> CameraPose {
        guard !viewSize.isEmpty else { return turned }
        let offset = modelAreaCentre - viewSize.center
        let scale = CameraMath.millimetresPerPoint(turned, size: viewSize)
        var next = turned
        next.target = pivot - turned.right * (offset.x * scale) + turned.up * (offset.y * scale)
        return next
    }
}
```

In `Sources/CreatorViewport/Model/ViewportModel+Commands.swift`, replace:

```swift
        case .view(let region):
            animate(to: region.pose(from: currentPose()))
        case .rotate(let arrow):
            animate(to: CameraNavigation.rotate(currentPose(), arrow))
```

with:

```swift
        case .view(let region):
            animateTurn(region.pose(from:))
        case .rotate(let arrow):
            animateTurn { CameraNavigation.rotate($0, arrow) }
```

In `Sources/CreatorViewport/Model/ViewportModel+Commands.swift`, replace:

```swift

    func zoom(by factor: Double) {
        stopAnimation()
        let before = pose
        apply(CameraNavigation.zoom(pose, factor: factor, toward: lastHoverPoint, size: viewSize))
```

with:

```swift

    /// Animates to `turn(now)`, the camera now turned, moved so the point shown at the model area's centre
    /// (`modelAreaPivot`) stays there: the arrows and the cube's regions turn the part where it is.
    func animateTurn(_ turn: (CameraPose) -> CameraPose) {
        let now = currentPose()
        animate(to: centring(modelAreaPivot(now), inTheModelAreaOf: turn(now)))
    }

    /// One zoom step (the + and − keys) toward the pointer or, with no pointer over the view, toward the model
    /// area's centre, where framing puts the part.
    func zoom(by factor: Double) {
        stopAnimation()
        let before = pose
        apply(CameraNavigation.zoom(pose, factor: factor, toward: lastHoverPoint ?? modelAreaCentre, size: viewSize))
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift
        case .cube:
            apply(CameraNavigation.orbit(pose, dx: dx, dy: dy, pivot: nil))
```

with:

```swift
        case .cube:
            apply(CameraNavigation.orbit(pose, dx: dx, dy: dy, pivot: modelAreaPivot(pose)))
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 125 tests in 15 suites passed` (117 + 8). The existing `framingFitsEveryCorner`, `lookAtFacesTheFaceOrthographicAndFramesIt`, arrow, cube and key-zoom tests still pass unchanged: with no insets the framing is the old one, the pivot is the target and the key zoom's fallback point is the view's centre.

- [ ] **Step 5: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, then `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, then `swiftlint lint --strict`
Expected: only the pre-existing `ContextMenuTests.swift` "'underPointer' mutated after capture by sendable closure" warning; **909**; `Done linting! Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests/ModelAreaFramingTests.swift
git commit -m "feat(viewport): frame the part in the model area the panels leave"
```

### Task 2: Right and middle drags, and modifiers from the drag value

C7 items 3 and 5, gap 5: `DragGesture(minimumDistance:coordinateSpace:button:)` and `DragGesture.Value.modifiers` (`CI-F`, `CI-G`). `ViewportModifierTracker` is deleted. The primary drag is still the zero-distance drag that carries clicks until Task 3.

**Files:**
- Create: `Sources/CreatorViewport/Input/ViewportPointerButton.swift`, `Sources/CreatorViewport/Input/ViewportPointerButton+MetalUI.swift`
- Modify: `Sources/CreatorViewport/Input/ViewportInputMap.swift`, `Sources/CreatorViewport/Model/DragState.swift`, `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, `Sources/CreatorViewport/View/ViewportView.swift`, `Sources/CreatorViewport/View/ViewportView+Parts.swift`, `Sources/ViewportHarness/main.swift`, **shared:** `Sources/CreatorApp/AppRoot.swift` (line 20 only), `Sources/CreatorApp/AppInput.swift`
- Delete: `Sources/CreatorViewport/View/ViewportModifierTracker.swift`
- Test: `Tests/CreatorViewportTests/ButtonDragTests.swift` (create), `Tests/CreatorViewportTests/InputMapTests.swift`

**Interfaces:**
- Consumes: MetalUI `DragGesture(minimumDistance: Pixels, coordinateSpace: CoordinateSpace = .local, button: MouseButton)`, `DragGesture.Value.startLocation`/`.location: Point<Pixels>`, `.modifiers: EventModifiers` (`EventModifiers` is MetalUI's `Modifiers`, so the existing `ViewportModifiers.init(_: Modifiers)` converts it); `MouseButton.primary`/`.secondary`/`.middle`.
- Produces:
  - `public enum ViewportPointerButton: Hashable, Sendable { case primary, secondary, middle }` and `var mouseButton: MouseButton`
  - `ViewportInputMap.dragMode(for modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) -> ViewportDragMode`, `ViewportInputMap.dragThreshold = 5.0`
  - `ViewportModel.dragChanged(from start: ScreenPoint, to point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton)`, `dragEnded(from start: ScreenPoint, at point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton)`
  - `ViewportModel.pointerDown(at:modifiers:button: ViewportPointerButton = .primary)` (existing callers compile unchanged)
  - `DragState.button: ViewportPointerButton`
  - `ViewportView.init(model: ViewportModel)` (the `modifiers:` parameter is gone); `ViewportView.drag(_ button: ViewportPointerButton, minimumDistance: Double, model: ViewportModel) -> DragGesture` (Task 3 drops `minimumDistance:`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/ButtonDragTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// MetalUI C7's drags (spec §9, docs/metalui-gaps.md C7 items 3 and 5): the right button orbits, the middle
/// button pans, and a primary drag reads its modifiers from the drag's own value.
@MainActor
struct ButtonDragTests {
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(pose: CameraPose) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        return model
    }

    /// One drag as MetalUI reports it: a change at each point after the press, then the end at the last.
    func drag(_ model: ViewportModel, _ button: ViewportPointerButton, from start: ScreenPoint, through points: [ScreenPoint],
              modifiers: ViewportModifiers = []) {
        for point in points { model.dragChanged(from: start, to: point, modifiers: modifiers, button: button) }
        model.dragEnded(from: start, at: points.last ?? start, modifiers: modifiers, button: button)
    }

    @Test func aMiddleDragPansWhateverIsHeld() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        drag(model, .middle, from: ScreenPoint(200, 150), through: [ScreenPoint(215, 150), ScreenPoint(230, 150)],
             modifiers: .option)
        #expect(isClose(try #require(CameraMath.project(start.target, model.pose, size: size)).point, ScreenPoint(230, 150)))
        #expect(model.pose.distance == start.distance, "⌥ doesn't turn a middle drag into a zoom")
    }

    @Test func aRightDragOrbitsAboutThePointUnderThePointer() async throws {
        let model = makeModel(pose: CameraPose(target: Vector3(0, 0, 15), distance: 80, yaw: 0, pitch: 0))
        let box = try await fakeBox()
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        let press = ScreenPoint(215, 135)   // over the front face, off its quad diagonal
        let ray = CameraMath.ray(through: press, model.pose, size: size)
        let hit = try #require(MeshRaycast.nearest(ray, in: [(solidIndex: 0, mesh: TestMeshes.box(box.bounds))]))
        drag(model, .secondary, from: press, through: [ScreenPoint(240, 120), ScreenPoint(260, 110)], modifiers: .shift)
        #expect(!isClose(model.pose.yaw, 0), "Shift doesn't turn a right drag into a pan")
        #expect(isClose(try #require(CameraMath.project(hit.point, model.pose, size: size)).point, press, tolerance: 1e-9))
    }

    @Test func aRightDragOnTheCubeOrbitsAboutTheTarget() {
        let start = CameraPose(target: Vector3(1, 1, 1), distance: 100, yaw: 0.3, pitch: 0.2)
        let model = makeModel(pose: start)
        let centre = model.cubeLayout.center
        drag(model, .secondary, from: centre, through: [ScreenPoint(centre.x + 30, centre.y)])
        #expect(isClose(model.pose.yaw, 0.3 - 30 * ViewportInputMap.orbitRadiansPerPoint))
        #expect(model.pose.target == start.target)
        #expect(!model.isAnimating, "a drag on the cube never picks a region")
    }

    @Test func aRightDragOnAHandleOrbitsInsteadOfEditingIt() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                              projection: .orthographic)
        let model = makeModel(pose: pose)
        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
                                          style: .linear, tint: .solid),
        ])
        var reports = 0
        model.events.handleChanged = { _, _, _ in reports += 1 }
        drag(model, .secondary, from: ScreenPoint(200, 75), through: [ScreenPoint(230, 75)])
        #expect(reports == 0)
        #expect(model.handles[0].value == 10)
        #expect(model.pose != pose)
    }

    @Test func aPrimaryDragTakesItsModeFromItsOwnModifiers() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        drag(model, .primary, from: ScreenPoint(200, 150), through: [ScreenPoint(230, 150)], modifiers: .shift)
        #expect(isClose(try #require(CameraMath.project(start.target, model.pose, size: size)).point, ScreenPoint(230, 150)))
        let panned = model.pose
        drag(model, .primary, from: ScreenPoint(200, 150), through: [ScreenPoint(200, 100)], modifiers: .option)
        #expect(isClose(model.pose.distance, 100 / exp(0.5)))
        #expect(model.pose.yaw == panned.yaw)
    }

    @Test func aSecondButtonDuringADragIsIgnored() {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        let press = ScreenPoint(200, 150)
        model.dragChanged(from: press, to: ScreenPoint(220, 150), modifiers: [], button: .secondary)
        let orbited = model.pose
        model.dragChanged(from: press, to: ScreenPoint(260, 150), modifiers: [], button: .middle)
        model.dragEnded(from: press, at: ScreenPoint(260, 150), modifiers: [], button: .middle)
        #expect(model.pose == orbited, "the middle button neither pans nor ends the right drag")
        #expect(settled.isEmpty)
        model.dragEnded(from: press, at: ScreenPoint(220, 150), modifiers: [], button: .secondary)
        #expect(settled == [orbited])
    }

    /// A drag whose release never arrived (the window lost the pointer) doesn't swallow the next drag of its button.
    @Test func aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain() throws {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        let lost = model.pose
        drag(model, .middle, from: ScreenPoint(100, 100), through: [ScreenPoint(130, 100)])
        #expect(settled.first == lost, "the stale drag settled where it was")
        #expect(settled.count == 2)
        #expect(!model.isPointerDown)
        let target = try #require(CameraMath.project(start.target, model.pose, size: size)).point
        #expect(isClose(target, ScreenPoint(250, 150)), "both pans moved the scene: 20 + 30 points")
    }

    /// A right or middle drag whose release was lost doesn't swallow the primary button's drags: MetalUI forms the
    /// primary arena on every primary press, apart from the button arena (`CI-F` item 3), so its values arrive.
    @Test func aPrimaryDragAfterALostMiddleReleaseStillOrbits() {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        let lost = model.pose
        drag(model, .primary, from: ScreenPoint(100, 100), through: [ScreenPoint(130, 100)])
        #expect(isClose(model.pose.yaw, lost.yaw - 30 * ViewportInputMap.orbitRadiansPerPoint), "the primary drag orbited")
        #expect(settled == [lost, model.pose], "the stale pan settled where it was, then the orbit")
        #expect(!model.isPointerDown)
    }
}
```

In `Tests/CreatorViewportTests/InputMapTests.swift`, replace:

```swift
        #expect(ViewportInputMap.dragMode(for: .command) == .orbit)
    }
```

with:

```swift
        #expect(ViewportInputMap.dragMode(for: .command) == .orbit)
    }

    @Test func theRightButtonOrbitsAndTheMiddleButtonPans() {
        #expect(ViewportInputMap.dragMode(for: [], button: .secondary) == .orbit)
        #expect(ViewportInputMap.dragMode(for: .shift, button: .secondary) == .orbit)
        #expect(ViewportInputMap.dragMode(for: [], button: .middle) == .pan)
        #expect(ViewportInputMap.dragMode(for: .option, button: .middle) == .pan)
        #expect(ViewportInputMap.dragMode(for: .option, button: .primary) == .zoom)
    }

    @Test func viewportButtonsAreMetalUIButtons() {
        #expect(ViewportPointerButton.primary.mouseButton == .primary)
        #expect(ViewportPointerButton.secondary.mouseButton == .secondary)
        #expect(ViewportPointerButton.middle.mouseButton == .middle)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: the build fails in the new tests, for example `error: extra argument 'button' in call` and `error: cannot infer contextual base in reference to member 'middle'` (`ViewportPointerButton` doesn't exist yet).

- [ ] **Step 3: Add the button and the drag-value entry points**

Create `Sources/CreatorViewport/Input/ViewportPointerButton.swift`:

```swift
/// The mouse button behind a viewport drag (spec §9, MetalUI C7's `DragGesture(button:)`).
public enum ViewportPointerButton: Hashable, Sendable {
    case primary
    case secondary
    case middle
}
```

Create `Sources/CreatorViewport/Input/ViewportPointerButton+MetalUI.swift`:

```swift
import MetalUI

extension ViewportPointerButton {
    /// The MetalUI button a viewport drag follows.
    public var mouseButton: MouseButton {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .middle: .middle
        }
    }
}
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
/// The stopgap input bindings of spec §9, kept in one place so MetalUI's C7 input APIs can replace them
/// (docs/metalui-gaps.md): primary drag orbits, Shift-drag pans, ⌥-drag zooms, F frames, and + and − zoom.
public enum ViewportInputMap {
```

with:

```swift
/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits and middle-drag pans. The keys (F frames, + and − zoom) are
/// still window-wide stopgaps until MetalUI scopes keys to an element (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
    public static let clickSlop = 3.0

    /// What a drag that begins with `modifiers` held does. Shift wins over ⌥.
    public static func dragMode(for modifiers: ViewportModifiers) -> ViewportDragMode {
        if modifiers.contains(.shift) { return .pan }
```

with:

```swift
    public static let clickSlop = 3.0
    /// How far a right or middle press moves before it drags. A right press that moves less opens the face menu.
    public static let dragThreshold = 5.0

    /// What a drag that begins with `button` pressed and `modifiers` held does. The middle button pans and the
    /// right button orbits, whatever is held. With the primary button Shift pans and ⌥ zooms; Shift wins over ⌥.
    public static func dragMode(for modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) -> ViewportDragMode {
        switch button {
        case .middle: return .pan
        case .secondary: return .orbit
        case .primary: break
        }
        if modifiers.contains(.shift) { return .pan }
```

In `Sources/CreatorViewport/Model/DragState.swift`, replace:

```swift
    var mode: ViewportDragMode
    var start: ScreenPoint
```

with:

```swift
    var mode: ViewportDragMode
    /// The button that began it: only that button's moves and release reach it.
    var button: ViewportPointerButton
    var start: ScreenPoint
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift

/// Pointer input, in viewport points (y down), from `ViewportView`'s stopgap gestures (spec §9).
extension ViewportModel {
```

with:

```swift

/// Pointer input, in viewport points (y down), from `ViewportView`'s MetalUI gestures (spec §9).
extension ViewportModel {
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift

    /// A press. What the drag will do is decided here:
    /// - on the view cube, it orbits (and a click selects a region)
    /// - on a handle's knob, it edits the handle
    /// - otherwise it depends on the modifiers (`ViewportInputMap`)
    public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers) {
        events.pressed()
        stopAnimation()
        var mode = ViewportInputMap.dragMode(for: modifiers)
        var pivot: Vector3?
        var handleStart = 0.0
        if cubeLayout.contains(point) {
            mode = .cube
        } else if let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
            mode = .handle(handle.id)
```

with:

```swift

    /// A drag's value from MetalUI: the first one begins the drag at `start` (`pointerDown`), and every one moves it
    /// to `point`. A right or middle drag while another drag is under way is ignored (`beginDragIfNeeded`).
    public func dragChanged(from start: ScreenPoint, to point: ScreenPoint, modifiers: ViewportModifiers,
                            button: ViewportPointerButton) {
        beginDragIfNeeded(from: start, modifiers: modifiers, button: button)
        guard drag?.button == button else { return }
        pointerDragged(to: point)
    }

    /// A drag's last value from MetalUI, at its release. A drag MetalUI ends without a change first begins here.
    public func dragEnded(from start: ScreenPoint, at point: ScreenPoint, modifiers: ViewportModifiers,
                          button: ViewportPointerButton) {
        beginDragIfNeeded(from: start, modifiers: modifiers, button: button)
        guard drag?.button == button else { return }
        pointerUp(at: point)
    }

    /// Begins the drag a value belongs to. The drag under way ends first, where it was, when its release must have
    /// been lost (MetalUI drops such an arena without a word, its `CI-AB`; docs/metalui-gaps.md VI-a):
    /// - a value of the same button from another press;
    /// - a primary value while another button's drag is under way: MetalUI forms the primary arena on every primary
    ///   press, apart from the button arena (`CI-F` item 3), so the primary button always gets its drag.
    /// A right or middle value while another drag is under way is ignored, as MetalUI ignores that press (`CI-AA`
    /// item 4).
    private func beginDragIfNeeded(from start: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton) {
        if let state = drag {
            let lostItsRelease = state.button == button ? state.start != start : button == .primary
            if lostItsRelease { pointerUp(at: state.last) }
        }
        if drag == nil { pointerDown(at: start, modifiers: modifiers, button: button) }
    }

    /// A press. What the drag will do is decided here:
    /// - with the primary button: on the view cube, it orbits (and a click selects a region); on a handle's knob,
    ///   it edits the handle; otherwise it depends on the modifiers (`ViewportInputMap`)
    /// - with the right button it orbits (the cube's way on the cube), and with the middle button it pans
    public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) {
        events.pressed()
        stopAnimation()
        var mode = ViewportInputMap.dragMode(for: modifiers, button: button)
        var pivot: Vector3?
        var handleStart = 0.0
        if button != .middle, cubeLayout.contains(point) {
            mode = .cube
        } else if button == .primary, let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
            mode = .handle(handle.id)
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift
        }
        drag = DragState(mode: mode, start: point, last: point, startPose: pose, pivot: pivot,
                         handleStartValue: handleStart)
```

with:

```swift
        }
        drag = DragState(mode: mode, button: button, start: point, last: point, startPose: pose, pivot: pivot,
                         handleStartValue: handleStart)
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 135 tests in 16 suites passed` (125 + 10).

- [ ] **Step 5: Wire the gestures and delete the tracker**

The view forwards each drag's values. The right and middle drags start after 5 points, so a right click still opens the face menu (MetalUI defers it to the release while a secondary drag is declared, `CI-F` item 4).

In `Sources/CreatorViewport/View/ViewportView.swift`, replace:

```swift
/// - a `MetalView` filling its space
/// - the stopgap gestures of spec §9 and the face context menu
/// - overlays for labels and the view cube's buttons
```

with:

```swift
/// - a `MetalView` filling its space
/// - its gestures (spec §9) and the face context menu
/// - overlays for labels and the view cube's buttons
```

In `Sources/CreatorViewport/View/ViewportView.swift`, replace:

```swift
    let model: ViewportModel
    let modifiers: ViewportModifierTracker

    /// `modifiers` follows the held modifier keys until MetalUI's drags report them (C7 item 5). Install it on the
    /// window once, with `ViewportModifierTracker.install(on:)`.
    public init(model: ViewportModel, modifiers: ViewportModifierTracker) {
        self.model = model
        self.modifiers = modifiers
    }
```

with:

```swift
    let model: ViewportModel

    public init(model: ViewportModel) {
        self.model = model
    }
```

In `Sources/CreatorViewport/View/ViewportView.swift`, replace:

```swift
    public var content: some ElementGroup {
        Self.stack(model: model, modifiers: modifiers)
    }
```

with:

```swift
    public var content: some ElementGroup {
        Self.stack(model: model)
    }
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
    @MainActor
    static func stack(model: ViewportModel, modifiers: ViewportModifierTracker) -> some Element {
        ZStack(alignment: .topLeading) {
            surface(model: model, modifiers: modifiers)
            for label in model.handleLabels() {
```

with:

```swift
    @MainActor
    static func stack(model: ViewportModel) -> some Element {
        ZStack(alignment: .topLeading) {
            surface(model: model)
            for label in model.handleLabels() {
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. One zero-distance drag carries every press: MetalUI reports a click as a change plus an end.
    @MainActor
    static func surface(model: ViewportModel, modifiers: ViewportModifierTracker) -> some Element {
        MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
```

with:

```swift
    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. A zero-distance primary drag carries every primary press: MetalUI reports a click as a
    /// change plus an end. The right and middle buttons drag in their own arenas (MetalUI `CI-F`).
    @MainActor
    static func surface(model: ViewportModel) -> some Element {
        MetalView(redraw: model.isAnimating ? .continuous : .onDemand, value: model.renderKey) { context in
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !model.isPointerDown {
                        model.pointerDown(at: ScreenPoint(value.startLocation), modifiers: modifiers.held)
                    }
                    model.pointerDragged(to: ScreenPoint(value.location))
                }
                .onEnded { value in
                    if !model.isPointerDown {
                        model.pointerDown(at: ScreenPoint(value.startLocation), modifiers: modifiers.held)
                    }
                    model.pointerUp(at: ScreenPoint(value.location))
                }
        )
        .onContinuousHover { phase in
```

with:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(drag(.primary, minimumDistance: 0, model: model))
        .gesture(drag(.secondary, minimumDistance: ViewportInputMap.dragThreshold, model: model))
        .gesture(drag(.middle, minimumDistance: ViewportInputMap.dragThreshold, model: model))
        .onContinuousHover { phase in
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
            }
        }
    }

```

with:

```swift
            }
        }
    }

    /// A drag with `button` that reports its values, and the modifiers held at each, to the model.
    @MainActor
    static func drag(_ button: ViewportPointerButton, minimumDistance: Double, model: ViewportModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(Float(minimumDistance)), button: button.mouseButton)
            .onChanged { value in
                model.dragChanged(from: ScreenPoint(value.startLocation), to: ScreenPoint(value.location),
                                  modifiers: ViewportModifiers(value.modifiers), button: button)
            }
            .onEnded { value in
                model.dragEnded(from: ScreenPoint(value.startLocation), at: ScreenPoint(value.location),
                                modifiers: ViewportModifiers(value.modifiers), button: button)
            }
    }

```

Delete `Sources/CreatorViewport/View/ViewportModifierTracker.swift`.

In `Sources/ViewportHarness/main.swift`, replace:

```swift
    let model = ViewportModel(kernel: kernel)
    let modifiers = ViewportModifierTracker()
    let selection = HarnessSelection()
```

with:

```swift
    let model = ViewportModel(kernel: kernel)
    let selection = HarnessSelection()
```

In `Sources/ViewportHarness/main.swift`, replace:

```swift
                                        // A window's root must be an Element, and a Component is a group, so it's wrapped.
                                        ZStack { ViewportView(model: model, modifiers: modifiers) }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    })
    modifiers.install(on: window)
    window.keymap = Keymap(ViewportKeyBindings.bindings())
```

with:

```swift
                                        // A window's root must be an Element, and a Component is a group, so it's wrapped.
                                        ZStack { ViewportView(model: model) }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    })
    window.keymap = Keymap(ViewportKeyBindings.bindings())
```

The app no longer owns a tracker (shared files: `AppRoot.swift` line 20, `AppInput.swift`):

In `Sources/CreatorApp/AppRoot.swift`, replace:

```swift
        ZStack(alignment: .topLeading) {
            ViewportView(model: model.viewport, modifiers: input.modifiers)
            VStack(alignment: .leading, spacing: AppLayout.margin.px) {
```

with:

```swift
        ZStack(alignment: .topLeading) {
            ViewportView(model: model.viewport)
            VStack(alignment: .leading, spacing: AppLayout.margin.px) {
```

In `Sources/CreatorApp/AppInput.swift`, replace:

```swift
///   frames the viewport from anywhere;
/// - `onInput`: the graph's keys, behind `ViewportModifierTracker`, which only watches modifiers (gap 5);
/// - text focus: `AppModel.releaseTextFocus` clears the window's focus, for canvas and viewport presses (gap M5-g).
```

with:

```swift
///   frames the viewport from anywhere;
/// - `onInput`: the graph's keys;
/// - text focus: `AppModel.releaseTextFocus` clears the window's focus, for canvas and viewport presses (gap M5-g).
```

In `Sources/CreatorApp/AppInput.swift`, replace:

```swift
    public let model: AppModel
    /// The held modifier keys for the viewport's drags, until MetalUI's drags report them (C7 item 5).
    public let modifiers = ViewportModifierTracker()

```

with:

```swift
    public let model: AppModel

```

In `Sources/CreatorApp/AppInput.swift`, replace:

```swift
        window.onInput = { [weak self] event in self?.handleInput(event) ?? false }
        modifiers.install(on: window)
        model.releaseTextFocus = { [weak window] in window?.focus(nil) }
```

with:

```swift
        window.onInput = { [weak self] event in self?.handleInput(event) ?? false }
        model.releaseTextFocus = { [weak window] in window?.focus(nil) }
```

- [ ] **Step 6: Check the whole package**

Run: `grep -rn ViewportModifierTracker Sources Tests` (expected: only `Sources/CreatorEditor/GraphPanelInput.swift`'s doc comment, which belongs to the graph panel's own C7 plan), then `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: only the pre-existing `ContextMenuTests.swift` warning; **919**; 0 violations. `CreatorAppTests` (55) pass unchanged: `ViewportGlueTests` still drives `pointerDown(at:modifiers:)`.

- [ ] **Step 7: Commit**

```bash
git add -A Sources/CreatorViewport Sources/ViewportHarness Sources/CreatorApp/AppRoot.swift Sources/CreatorApp/AppInput.swift Tests/CreatorViewportTests
git commit -m "feat(viewport): right-drag orbits, middle-drag pans, drags read their own modifiers (C7)"
```

### Task 3: Clicks are a `SpatialTapGesture`

C7 item 4 (`CI-B`): a click's location is the tap's. Drags never click.

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, `Sources/CreatorViewport/Input/ViewportInputMap.swift` (drop `clickSlop`), `Sources/CreatorViewport/View/ViewportView+Parts.swift`
- Test: `Tests/CreatorViewportTests/ViewportInputTests.swift`, `Tests/CreatorViewportTests/ViewportEventTests.swift`

**Interfaces:**
- Consumes: MetalUI `SpatialTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local)`, `.onEnded { (value: SpatialTapGesture.Value) in value.location }` (the release that ends the tap, local points).
- Produces: `ViewportModel.click(at point: ScreenPoint)`; `pointerUp(at:)` no longer clicks; `ViewportInputMap.clickSlop` is removed; `ViewportView.drag(_ button: ViewportPointerButton, model: ViewportModel) -> DragGesture` (every drag starts after `dragThreshold`).

- [ ] **Step 1: Write the failing tests**

The click tests now click through `click(at:)`, and four new tests pin what a click is and isn't.

In `Tests/CreatorViewportTests/ViewportInputTests.swift`, replace:

```swift
        let model = makeModel(pose: CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 0.2))
        let centre = model.cubeLayout.center
        model.pointerDown(at: centre, modifiers: [])
        model.pointerUp(at: centre)
        #expect(model.isAnimating)
```

with:

```swift
        let model = makeModel(pose: CameraPose(target: .zero, distance: 100, yaw: 0.3, pitch: 0.2))
        model.click(at: model.cubeLayout.center)
        #expect(model.isAnimating)
```

In `Tests/CreatorViewportTests/ViewportInputTests.swift`, replace:

```swift

    @Test func aClickReportsThePickAndLeavesTheCameraAlone() {
        let start = CameraPose(target: .zero, distance: 100)
```

with:

```swift

    @Test func aClickReportsThePickAtItsLocationAndLeavesTheCameraAlone() {
        let start = CameraPose(target: .zero, distance: 100)
```

In `Tests/CreatorViewportTests/ViewportInputTests.swift`, replace:

```swift
        var clicked: PickTarget??
        model.pick = { _ in .edge(solid: 0, EdgeID(3)) }
        model.events.clicked = { clicked = $0 }
        model.pointerDown(at: ScreenPoint(200, 200), modifiers: [])
        model.pointerDragged(to: ScreenPoint(201, 201))
        model.pointerUp(at: ScreenPoint(201, 201))
        #expect(clicked == .some(.edge(solid: 0, EdgeID(3))))
        #expect(model.pose == start)
    }
```

with:

```swift
        var clicked: PickTarget??
        var pickedAt: ScreenPoint?
        model.pick = { point in
            pickedAt = point
            return .edge(solid: 0, EdgeID(3))
        }
        model.events.clicked = { clicked = $0 }
        model.click(at: ScreenPoint(201, 201))
        #expect(clicked == .some(.edge(solid: 0, EdgeID(3))))
        #expect(pickedAt == ScreenPoint(201, 201))
        #expect(model.pose == start)
    }

    @Test func aDragThatComesBackToItsStartIsNotAClick() {
        let start = CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3)
        let model = makeModel(pose: start)
        var clicks = 0
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.events.clicked = { _ in clicks += 1 }
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        model.pointerDragged(to: ScreenPoint(240, 150))
        model.pointerDragged(to: ScreenPoint(201, 150))
        model.pointerUp(at: ScreenPoint(201, 150))
        #expect(clicks == 0)
        #expect(model.pose != start, "the orbit is kept, not put back")
    }

    @Test func aClickOnAHandleKnobOrTheCubeReportsNoPick() {
        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                              projection: .orthographic)
        let model = makeModel(pose: pose)
        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
                                          style: .linear, tint: .solid),
        ])
        var clicks = 0
        var handleReports = 0
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.events.clicked = { _ in clicks += 1 }
        model.events.handleChanged = { _, _, _ in handleReports += 1 }
        model.click(at: ScreenPoint(200, 75))
        model.click(at: model.cubeLayout.center)
        #expect(clicks == 0)
        #expect(handleReports == 0, "a click on a knob changes nothing")
    }

    /// A click while a drag is still under way means that drag lost its release (docs/metalui-gaps.md VI-a): it
    /// ends where it was, and the hover picks again.
    @Test func aClickAfterALostDragEndsItAndHoversAgain() {
        let model = makeModel(pose: CameraPose(target: .zero, distance: 100, yaw: 0.2, pitch: 0.3))
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .primary)
        let orbited = model.pose
        #expect(model.hovered == nil, "nothing is picked during a drag")
        model.click(at: ScreenPoint(300, 220))
        #expect(!model.isPointerDown)
        #expect(settled == [orbited], "the lost drag settled where it was")
        #expect(model.hovered == .face(solid: 0, FaceID(1)))
    }
```

In `Tests/CreatorViewportTests/ViewportEventTests.swift`, replace:

```swift
        let (model, recorder) = makeModel()
        model.pointerDown(at: ScreenPoint(200, 150), modifiers: [])
        model.pointerDragged(to: ScreenPoint(201, 150))
        model.pointerUp(at: ScreenPoint(201, 150))
        #expect(recorder.settled.isEmpty)
        #expect(recorder.presses == 1)
```

with:

```swift
        let (model, recorder) = makeModel()
        model.click(at: ScreenPoint(201, 150))
        #expect(recorder.settled.isEmpty)
        #expect(recorder.presses == 1)
    }

    @Test func aClickStopsAnAnimationWhereItIs() {
        let (model, recorder) = makeModel()
        model.perform(.rotate(.up))
        model.click(at: ScreenPoint(200, 150))
        #expect(!model.isAnimating)
        #expect(recorder.settled == [model.pose], "the click froze it where it was on screen")
        #expect(recorder.presses == 1)
```

In `Tests/CreatorViewportTests/ViewportEventTests.swift`, replace:

```swift
        #expect(model.modelArea.trailing == 300)
        let centre = model.cubeLayout.center
        model.pointerDown(at: centre, modifiers: [])
        model.pointerUp(at: centre)
        #expect(model.isAnimating, "the moved cube is still the one that's clicked")
```

with:

```swift
        #expect(model.modelArea.trailing == 300)
        model.click(at: model.cubeLayout.center)
        #expect(model.isAnimating, "the moved cube is still the one that's clicked")
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'ViewportModel' has no member 'click'`.

- [ ] **Step 3: Add `click(at:)` and stop drags clicking**

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift

    /// A release. A press that moved less than `clickSlop` is a click. It puts back any tiny orbit, then picks a
    /// cube region or reports the face or edge under the pointer. Either way the hover pick is redone where the
    /// pointer now is, because the camera may have moved under it.
    public func pointerUp(at point: ScreenPoint) {
```

with:

```swift

    /// A release that ends a drag. A drag never clicks, even one that comes back to where it began: clicks are
    /// `click(at:)`'s. The hover pick is redone where the pointer now is, because the camera may have moved under it.
    public func pointerUp(at point: ScreenPoint) {
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift
        drag = nil
        defer {
            // The release point is where the pointer is now. Released outside the view, it's not over it at all.
            let inside = !viewSize.isEmpty && (0...viewSize.width).contains(point.x)
                && (0...viewSize.height).contains(point.y)
            lastHoverPoint = inside ? point : nil
            refreshHover()
        }
        let isClick = (point - state.start).length < ViewportInputMap.clickSlop
        switch state.mode {
        case .cube where isClick:
            apply(state.startPose)
            if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
        case .orbit where isClick:
            apply(state.startPose)
            events.clicked(pick?(point))
        case .handle(let id):
            updateHandle(id, state, to: point, phase: .ended)
        default:
            break
        }
        // A drag that moved the camera settles it here. A click put it back, and a cube click animates
        // (its end reports).
        if !isAnimating, pose != state.startPose { events.cameraSettled(pose) }
    }
```

with:

```swift
        drag = nil
        if case .handle(let id) = state.mode { updateHandle(id, state, to: point, phase: .ended) }
        // A drag that moved the camera settles it here.
        if !isAnimating, pose != state.startPose { events.cameraSettled(pose) }
        pointerReleased(at: point)
    }

    /// A click: a primary press released within MetalUI's tap slop (`SpatialTapGesture`, its location the
    /// release). On the view cube it looks at the region under the pointer; on a handle's knob it does nothing;
    /// elsewhere it reports the face or edge under the pointer, or `nil` for empty space.
    ///
    /// A drag still under way ends first, where it was: a click is a primary press and release, so a primary drag
    /// under way lost its release, and the primary button wins over another (`beginDragIfNeeded`).
    public func click(at point: ScreenPoint) {
        if let state = drag { pointerUp(at: state.last) }
        events.pressed()
        stopAnimation()
        if cubeLayout.contains(point) {
            if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
        } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil {
            events.clicked(pick?(point))
        }
        pointerReleased(at: point)
    }

    /// The pointer is at the release point now. Released outside the view, it's not over it at all.
    private func pointerReleased(at point: ScreenPoint) {
        let inside = !viewSize.isEmpty && (0...viewSize.width).contains(point.x) && (0...viewSize.height).contains(point.y)
        lastHoverPoint = inside ? point : nil
        refreshHover()
    }
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
    public static let keyZoomFactor = 1.25
    /// A press that moves less than this many points before it is released is a click.
    public static let clickSlop = 3.0
    /// How far a right or middle press moves before it drags. A right press that moves less opens the face menu.
    public static let dragThreshold = 5.0
```

with:

```swift
    public static let keyZoomFactor = 1.25
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
    /// also 5 points), and a right press that moves less opens the face menu.
    public static let dragThreshold = 5.0
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 139 tests in 16 suites passed` (135 + 4; `aClickReportsThePickAndLeavesTheCameraAlone` is renamed `aClickReportsThePickAtItsLocationAndLeavesTheCameraAlone`).

- [ ] **Step 5: Put the tap on the surface**

The tap is declared before the primary drag, so it is the inner gesture: it wins a click, and the drag reports only once the tap has failed by moving (MetalUI `IX-D` item 3, probe arms `G9a`/`G9b`).

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. A zero-distance primary drag carries every primary press: MetalUI reports a click as a
    /// change plus an end. The right and middle buttons drag in their own arenas (MetalUI `CI-F`).
    @MainActor
```

with:

```swift
    /// The GPU surface and its input. It redraws on demand when `renderKey` changes, and continuously while the
    /// camera animates. The tap is declared first, so it is the inner gesture: a click is the tap's, and the
    /// primary drag reports only once the tap has failed by moving (MetalUI `IX-D` item 3). The right and middle
    /// buttons drag in their own arenas (MetalUI `CI-F`).
    @MainActor
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(drag(.primary, minimumDistance: 0, model: model))
        .gesture(drag(.secondary, minimumDistance: ViewportInputMap.dragThreshold, model: model))
        .gesture(drag(.middle, minimumDistance: ViewportInputMap.dragThreshold, model: model))
        .onContinuousHover { phase in
```

with:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(SpatialTapGesture().onEnded { model.click(at: ScreenPoint($0.location)) })
        .gesture(drag(.primary, model: model))
        .gesture(drag(.secondary, model: model))
        .gesture(drag(.middle, model: model))
        .onContinuousHover { phase in
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
    @MainActor
    static func drag(_ button: ViewportPointerButton, minimumDistance: Double, model: ViewportModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(Float(minimumDistance)), button: button.mouseButton)
            .onChanged { value in
```

with:

```swift
    @MainActor
    static func drag(_ button: ViewportPointerButton, model: ViewportModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(Float(ViewportInputMap.dragThreshold)), button: button.mouseButton)
            .onChanged { value in
```

- [ ] **Step 6: Check the whole package**

Run: `grep -rn clickSlop Sources Tests` (expected: nothing), `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: only the pre-existing warning; **923**; 0 violations. `CreatorAppTests.aPressOnTheViewportOrTheCanvasReleasesTextFocus` and `aViewportPressCommitsATypedInspectorValue` still pass: `pointerDown` still reports the press.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): clicks are a SpatialTapGesture, and a drag never clicks (C7)"
```

### Task 4: The face menu is for the face under the right press

C7 item 4 and gap 4: MetalUI's located context menu (`CI-R`) replaces the last-hover stand-in.

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift` (the `refreshHover()` doc comment), `Sources/CreatorViewport/View/ViewportView+Parts.swift`
- Test: `Tests/CreatorViewportTests/ContextMenuTests.swift`

**Interfaces:**
- Consumes: MetalUI `.contextMenu(menuItems: @escaping @MainActor (Point<Pixels>?) -> M)` on the proposal path (the closure's arity selects it; `nil` for a keyboard or accessibility open).
- Produces: `ViewportModel.contextMenuItems(at point: ScreenPoint?) -> [ViewportMenuItem]` (replaces `contextMenuItems()`); `ViewportModel.faceRef(for target: PickTarget?) -> ViewportFaceRef?` (internal; replaces `hoveredFaceRef()`).

- [ ] **Step 1: Write the failing tests**

The menu tests open the menu at a point. `movingTheCameraUnderAStillPointerRepicks` keeps pinning the hover re-pick (the tint still needs it) and stops asking the menu.

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        #expect(model.contextMenuItems() == [.lookAt(ref), .selectEdgesOfFace(ref),
                                             .showProducingNode(node, title: "Show Producing Node"),
        ])
        #expect(model.contextMenuItems().map(\.title) == ["Look At", "Select Edges of Face", "Show Producing Node"])
    }

    @Test func nothingUnderThePointerMeansNoMenu() async throws {
        let model = await model(showing: [try await fakeBox()])
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.contextMenuItems().isEmpty)
        model.pick = { _ in .face(solid: 7, FaceID(0)) }
        model.pointerHovered(at: ScreenPoint(301, 200))
        #expect(model.contextMenuItems().isEmpty, "a stale pick of a solid that is gone opens nothing")
    }
```

with:

```swift
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        let press = ScreenPoint(300, 200)
        #expect(model.contextMenuItems(at: press) == [.lookAt(ref), .selectEdgesOfFace(ref),
                                                      .showProducingNode(node, title: "Show Producing Node"),
        ])
        #expect(model.contextMenuItems(at: press).map(\.title) == ["Look At", "Select Edges of Face", "Show Producing Node"])
    }

    @Test func nothingUnderThePressMeansNoMenu() async throws {
        let model = await model(showing: [try await fakeBox()])
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).isEmpty)
        model.pick = { _ in .face(solid: 7, FaceID(0)) }
        #expect(model.contextMenuItems(at: ScreenPoint(301, 200)).isEmpty, "a stale pick of a solid that is gone opens nothing")
    }

    /// The menu is for the face under the right press, picked as the menu opens (C7 item 4), not the last hover:
    /// the pointer can move without a hover event, and the camera can move under a still pointer.
    @Test func theMenuIsForTheFaceUnderThePressNotTheLastHover() async throws {
        let model = await model(showing: [try await fakeBox()])
        var askedAt: [ScreenPoint] = []
        model.pick = { point in
            askedAt.append(point)
            return point == ScreenPoint(300, 200) ? .face(solid: 0, FaceID(2)) : .face(solid: 0, FaceID(3))
        }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.hovered == .face(solid: 0, FaceID(2)))
        #expect(model.contextMenuItems(at: ScreenPoint(120, 80)).first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))
        #expect(askedAt.last == ScreenPoint(120, 80))
    }

    @Test func noFaceMenuOverTheViewCubeOrWithoutAPointer() async throws {
        let model = await model(showing: [try await fakeBox()])
        var asked = 0
        model.pick = { _ in
            asked += 1
            return .face(solid: 0, FaceID(2))
        }
        model.pointerHovered(at: ScreenPoint(300, 200))
        asked = 0
        #expect(model.contextMenuItems(at: model.cubeLayout.center).isEmpty, "the cube is drawn over the part")
        #expect(model.contextMenuItems(at: nil).isEmpty, "a keyboard or accessibility open has no pointer")
        #expect(asked == 0)
    }
```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(2))))

```

with:

```swift
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.hovered == .face(solid: 0, FaceID(2)))

```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        #expect(model.hovered == .face(solid: 0, FaceID(3)))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))

```

with:

```swift
        #expect(model.hovered == .face(solid: 0, FaceID(3)))

```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.performKey(.zoomIn)
        #expect(model.contextMenuItems().isEmpty, "the face that was under the pointer has moved away")
        underPointer = .face(solid: 0, FaceID(1))
```

with:

```swift
        model.performKey(.zoomIn)
        #expect(model.hovered == nil, "the face that was under the pointer has moved away")
        underPointer = .face(solid: 0, FaceID(1))
```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        #expect(model.hovered == .face(solid: 0, FaceID(4)))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(4))))
    }
```

with:

```swift
        #expect(model.hovered == .face(solid: 0, FaceID(4)))
    }
```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.pick = { _ in .edge(solid: 0, EdgeID(8)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.hoveredFaceRef() == ViewportFaceRef(solidIndex: 0, face: FaceID(2)))
    }
```

with:

```swift
        model.pick = { _ in .edge(solid: 0, EdgeID(8)) }
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(2))))
    }
```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.pick = { _ in .face(solid: 0, FaceID(0)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let titles = model.contextMenuItems().map(\.title)
        let sorted = [nodeA, nodeB].sorted()
```

with:

```swift
        model.pick = { _ in .face(solid: 0, FaceID(0)) }
        let titles = model.contextMenuItems(at: ScreenPoint(300, 200)).map(\.title)
        let sorted = [nodeA, nodeB].sorted()
```

In `Tests/CreatorViewportTests/ContextMenuTests.swift`, replace:

```swift
        model.events.showProducingNode = { shown.append($0) }
        for item in model.contextMenuItems().dropFirst(2) { model.choose(item) }
        #expect(shown == sorted)
```

with:

```swift
        model.events.showProducingNode = { shown.append($0) }
        for item in model.contextMenuItems(at: ScreenPoint(300, 200)).dropFirst(2) { model.choose(item) }
        #expect(shown == sorted)
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: argument passed to call that takes no arguments` and `error: 'nil' requires a contextual type`.

- [ ] **Step 3: Pick at the press**

In `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`, replace:

```swift
extension ViewportModel {
    /// The face context menu (spec §6.3), built when the menu opens, for the face under the pointer. Over an edge,
    /// it uses the edge's first face. Over nothing it's empty, and MetalUI opens no menu.
    ///
    /// MetalUI doesn't yet give a context menu its click location (C7 item 4, docs/metalui-gaps.md), so "under the
    /// pointer" is the last hover pick. The model redoes that pick whenever the camera or the scene moves under a
    /// still pointer (`refreshHover()`), so it can't name a face that has moved away.
    public func contextMenuItems() -> [ViewportMenuItem] {
        guard let ref = hoveredFaceRef(),
              let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
```

with:

```swift
extension ViewportModel {
    /// The face context menu (spec §6.3), built when the menu opens, for the face under `point`: the right press's
    /// location, which MetalUI's located `.contextMenu` hands its builder (C7 item 4). The face is picked there and
    /// then, so it's the one under the press even if the pointer moved without a hover event or the camera moved
    /// under it. Over an edge, the menu uses the edge's first face. Over nothing, over the view cube, or opened
    /// without a pointer (`nil`: from the keyboard or accessibility) it's empty, and MetalUI opens no menu.
    public func contextMenuItems(at point: ScreenPoint?) -> [ViewportMenuItem] {
        guard let point, !cubeLayout.contains(point), let ref = faceRef(for: pick?(point)),
              let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
```

In `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`, replace:

```swift

    /// The face the context menu is about: the hovered face, or the first face of the hovered edge. `nil` if the
    /// pick is stale (its solid is gone).
    func hoveredFaceRef() -> ViewportFaceRef? {
        switch hovered {
        case .face(let solid, let face)?:
```

with:

```swift

    /// The face a context menu over `target` is about: the face, or the first face of the edge. `nil` over
    /// nothing, or for a stale pick (its solid is gone).
    func faceRef(for target: PickTarget?) -> ViewportFaceRef? {
        switch target {
        case .face(let solid, let face)?:
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
    /// Re-picks under a pointer that hasn't moved, after the camera or the scene changed beneath it, so the hover
    /// tint and the context menu (which reads the hover pick until C7 item 4) never name a face that's no longer
    /// under the pointer. Nothing is picked during a drag, so there the old pick is just dropped.
    func refreshHover() {
```

with:

```swift
    /// Re-picks under a pointer that hasn't moved, after the camera or the scene changed beneath it, so the hover
    /// tint never names a face that's no longer under the pointer. Nothing is picked during a drag, so there the old
    /// pick is just dropped.
    func refreshHover() {
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        }
        .contextMenu {
            for item in model.contextMenuItems() {
                Button(item.title) { model.choose(item) }
```

with:

```swift
        }
        .contextMenu { (location: Point<Pixels>?) in
            for item in model.contextMenuItems(at: location.map { ScreenPoint($0) }) {
                Button(item.title) { model.choose(item) }
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 141 tests in 16 suites passed` (139 + 2; `nothingUnderThePointerMeansNoMenu` is renamed `nothingUnderThePressMeansNoMenu`).

- [ ] **Step 5: Check the whole package**

Run: `grep -rn "hoveredFaceRef\|contextMenuItems()" Sources Tests` (expected: nothing), `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: only the pre-existing `ContextMenuTests.swift` warning (now at line 96); **925**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): the face menu picks at the right press (C7 located context menu)"
```

### Task 5: Two-finger scroll zooms toward the cursor

C7 item 1 (`CI-I`): `.onScrollWheel` with `ScrollEvent.location`, `phase` and `momentumPhase`. Momentum is ignored for zoom.

**Files:**
- Create: `Sources/CreatorViewport/Input/ViewportScrollPhase.swift`, `Sources/CreatorViewport/Input/ViewportScrollPhase+MetalUI.swift`, `Sources/CreatorViewport/Model/ViewportModel+Scroll.swift`
- Modify: `Sources/CreatorViewport/Input/ViewportInputMap.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift`, `Sources/CreatorViewport/View/ViewportView+Parts.swift`
- Test: `Tests/CreatorViewportTests/ScrollZoomTests.swift` (create), `Tests/CreatorViewportTests/InputMapTests.swift`

**Interfaces:**
- Consumes: MetalUI `.onScrollWheel(perform: @escaping @MainActor (ScrollEvent) -> Bool)` (proposal path; `true` claims); `ScrollEvent.delta: Point<Pixels>`, `.location: Point<Pixels>` (local), `.phase: InputPhase`, `.isMomentum: Bool`; `InputPhase` cases `.none`, `.mayBegin`, `.began`, `.changed`, `.ended`, `.cancelled`; `ScrollEvent.init(position:delta:modifiers:phase:momentumPhase:isPrecise:timestamp:)` (tests).
- Produces:
  - `public enum ViewportScrollPhase: Hashable, Sendable { case step, moving, ended, momentum }` and `init(_ event: ScrollEvent)`
  - `@discardableResult public func scrolled(by deltaY: Double, at point: ScreenPoint, phase: ViewportScrollPhase) -> Bool` and `public func waitForScroll() async` (returns once a run of wheel steps has settled, like `waitForAnimation()`) on `ViewportModel`
  - `ViewportModel.scrollStartPose: CameraPose?` and `ViewportModel.wheelSettleTask: Task<Void, Never>?` (internal, untracked)
  - `ViewportInputMap.scrollZoomPerPoint = 0.01`, `ViewportInputMap.wheelSettleDelay = 0.15`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/ScrollZoomTests.swift`:

```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// Two-finger scroll and the wheel zoom toward the cursor (spec §6.3, docs/metalui-gaps.md C7 item 1): a run of wheel
/// steps settles the camera once the wheel stops, a trackpad scroll settles it once at its end, and momentum is
/// ignored.
@MainActor
struct ScrollZoomTests {
    let size = ViewportSize(width: 400, height: 300)
    let start = CameraPose(target: .zero, distance: 100, yaw: 0.4, pitch: 0.3)
    let cursor = ScreenPoint(320, 80)

    func makeModel() -> (ViewportModel, () -> [CameraPose]) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: ManualClock())
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        return (model, { settled })
    }

    /// The model point under `cursor`, on the plane through the target.
    func pointUnderTheCursor(_ pose: CameraPose) -> Vector3 {
        let ray = CameraMath.ray(through: cursor, pose, size: size)
        return ray.point(at: (pose.target - ray.origin).dot(pose.toEye) / ray.direction.dot(pose.toEye))
    }

    @Test func aWheelStepZoomsTowardTheCursorAndSettlesWhenTheWheelStops() async throws {
        let (model, settled) = makeModel()
        let under = pointUnderTheCursor(start)
        #expect(model.scrolled(by: 10, at: cursor, phase: .step), "the viewport claims the scroll")
        #expect(isClose(model.pose.distance, 100 / exp(0.1)))
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        #expect(settled().isEmpty, "the wheel may still be turning")
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        model.scrolled(by: -10, at: cursor, phase: .step)
        await model.waitForScroll()
        #expect(isClose(model.pose.distance, 100), "scrolling the other way zooms back out")
        #expect(settled().count == 2)
    }

    /// A free-spinning wheel sends tens of steps a second (and SDL reports every scroll as a step, MetalUI `CI-I`):
    /// they settle the camera, a document write, and re-pick the hover once, not per step (spec §7.3).
    @Test func aRunOfWheelStepsSettlesOnce() async {
        let (model, settled) = makeModel()
        var picks = 0
        model.pick = { _ in
            picks += 1
            return nil
        }
        model.pointerHovered(at: cursor)
        picks = 0
        for _ in 0..<20 { model.scrolled(by: 10, at: cursor, phase: .step) }
        #expect(isClose(model.pose.distance, 100 / exp(2)))
        #expect(settled().isEmpty)
        #expect(picks == 0)
        await model.waitForScroll()
        #expect(settled() == [model.pose])
        #expect(picks == 1)
    }

    @Test func aTrackpadScrollZoomsAndSettlesOnceWhenItEnds() throws {
        let (model, settled) = makeModel()
        let under = pointUnderTheCursor(start)
        for _ in 0..<3 { model.scrolled(by: 20, at: cursor, phase: .moving) }
        #expect(isClose(model.pose.distance, 100 / exp(0.6)))
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, cursor, tolerance: 1e-9))
        #expect(settled().isEmpty, "nothing is reported while the scroll zooms")
        model.scrolled(by: 0, at: cursor, phase: .ended)
        #expect(settled() == [model.pose])
    }

    @Test func momentumIsIgnored() {
        let (model, settled) = makeModel()
        model.scrolled(by: 20, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        let zoomed = model.pose
        #expect(model.scrolled(by: 30, at: cursor, phase: .momentum), "momentum is still claimed")
        model.scrolled(by: 10, at: cursor, phase: .momentum)
        #expect(model.pose == zoomed)
        #expect(settled() == [zoomed])
    }

    @Test func aScrollThatDoesntZoomReportsNothing() {
        let (model, settled) = makeModel()
        model.scrolled(by: 0, at: cursor, phase: .ended)
        model.scrolled(by: 0, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        model.scrolled(by: .nan, at: cursor, phase: .step)
        model.scrolled(by: .infinity, at: cursor, phase: .moving)
        model.scrolled(by: 0, at: cursor, phase: .ended)
        #expect(model.pose == start)
        #expect(settled().isEmpty)
    }

    @Test func aScrollStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.up))
        #expect(model.isAnimating)
        model.scrolled(by: 20, at: cursor, phase: .moving)
        #expect(!model.isAnimating)
    }
}
```

In `Tests/CreatorViewportTests/InputMapTests.swift`, replace:

```swift
        #expect(ViewportPointerButton.middle.mouseButton == .middle)
    }
```

with:

```swift
        #expect(ViewportPointerButton.middle.mouseButton == .middle)
    }

    @Test func scrollEventsMapToZoomPhases() {
        func phase(_ phase: InputPhase, momentum: InputPhase = .none) -> ViewportScrollPhase {
            ViewportScrollPhase(ScrollEvent(position: Point(x: Pixels(0), y: Pixels(0)), delta: Point(x: Pixels(0), y: Pixels(4)),
                                            phase: phase, momentumPhase: momentum, isPrecise: true, timestamp: 0))
        }
        #expect(phase(.none) == .step, "a wheel mouse has no phase")
        #expect(phase(.mayBegin) == .moving)
        #expect(phase(.began) == .moving)
        #expect(phase(.changed) == .moving)
        #expect(phase(.ended) == .ended)
        #expect(phase(.cancelled) == .ended)
        #expect(phase(.none, momentum: .began) == .momentum)
        #expect(phase(.none, momentum: .changed) == .momentum)
        #expect(phase(.none, momentum: .ended) == .momentum)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'ViewportModel' has no member 'scrolled'`.

- [ ] **Step 3: Add the scroll phase and the zoom**

Create `Sources/CreatorViewport/Input/ViewportScrollPhase.swift`:

```swift
/// Where a scroll event sits in its gesture, as the viewport's zoom needs it (MetalUI's `ScrollEvent` phases).
public enum ViewportScrollPhase: Hashable, Sendable {
    /// A wheel mouse's step: no gesture around it. It zooms; the camera settles once the wheel has been still for
    /// `ViewportInputMap.wheelSettleDelay`.
    case step
    /// A trackpad scroll begins or continues. It zooms; the camera settles when the scroll ends.
    case moving
    /// The fingers lifted (or the system cancelled the scroll): the camera settles.
    case ended
    /// The glide after the fingers lift. Zoom ignores it (docs/metalui-gaps.md C7 item 1).
    case momentum
}
```

Create `Sources/CreatorViewport/Input/ViewportScrollPhase+MetalUI.swift`:

```swift
import MetalUI

extension ViewportScrollPhase {
    /// The phase of a MetalUI scroll event. Momentum wins over the gesture phase; no phase at all is a wheel step.
    public init(_ event: ScrollEvent) {
        if event.isMomentum {
            self = .momentum
            return
        }
        switch event.phase {
        case .none: self = .step
        case .mayBegin, .began, .changed: self = .moving
        case .ended, .cancelled: self = .ended
        }
    }
}
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits and middle-drag pans. The keys (F frames, + and − zoom) are
/// still window-wide stopgaps until MetalUI scopes keys to an element (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
```

with:

```swift
/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits, middle-drag pans and two-finger scroll zooms toward the
/// cursor. The keys (F frames, + and − zoom) are still window-wide stopgaps until MetalUI scopes keys to an element
/// (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
    public static let keyZoomFactor = 1.25
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
```

with:

```swift
    public static let keyZoomFactor = 1.25
    /// Scroll zoom: 100 points of scroll multiply or divide the camera distance by e. A wheel mouse's step is
    /// 10 points (MetalUI reports its lines × 10), so about 10%.
    public static let scrollZoomPerPoint = 0.01
    /// Wheel steps closer together than this many seconds are one zoom: the camera settles once, after the last
    /// (a free-spinning wheel sends tens of steps a second, spec §7.3).
    public static let wheelSettleDelay = 0.15
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
    @ObservationIgnored var drag: DragState?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
```

with:

```swift
    @ObservationIgnored var drag: DragState?
    /// The camera when the scroll under way (a trackpad scroll, or a run of wheel steps) began; `nil` between scrolls.
    @ObservationIgnored var scrollStartPose: CameraPose?
    /// Settles a run of wheel steps once the wheel has been still for `ViewportInputMap.wheelSettleDelay`.
    @ObservationIgnored var wheelSettleTask: Task<Void, Never>?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
```

Create `Sources/CreatorViewport/Model/ViewportModel+Scroll.swift`:

```swift
import CreatorGeometry
import Foundation

extension ViewportModel {
    /// A scroll over the viewport (spec §6.3: zoom goes towards the cursor): `deltaY` points of scroll at `point`.
    /// Scrolling by a positive `deltaY` zooms in. Nothing settles per event (spec §7.3): a trackpad scroll settles
    /// the camera once, when it ends, and a run of wheel steps once the wheel has been still for
    /// `ViewportInputMap.wheelSettleDelay`; momentum is ignored. Returns `true`: the viewport claims every scroll over
    /// it, so none reaches the window's other input.
    @discardableResult
    public func scrolled(by deltaY: Double, at point: ScreenPoint, phase: ViewportScrollPhase) -> Bool {
        let factor = exp(deltaY * ViewportInputMap.scrollZoomPerPoint)
        switch phase {
        case .step:
            zoomScrolling(by: factor, toward: point)
            settleWhenTheWheelStops()
        case .moving:
            zoomScrolling(by: factor, toward: point)
        case .ended:
            scrollEnded()
        case .momentum:
            break
        }
        return true
    }

    /// Returns once the most recent run of wheel steps has settled.
    public func waitForScroll() async {
        while let task = wheelSettleTask {
            await task.value
            if wheelSettleTask == task { return }
        }
    }

    /// One scroll event's zoom, without settling. The scroll's first event stops an animation and keeps the camera
    /// it began with.
    private func zoomScrolling(by factor: Double, toward point: ScreenPoint) {
        if scrollStartPose == nil {
            stopAnimation()
            scrollStartPose = pose
        }
        apply(CameraNavigation.zoom(pose, factor: factor, toward: point, size: viewSize))
    }

    /// Ends the run of wheel steps once the wheel has been still for `wheelSettleDelay`: each step restarts the wait.
    private func settleWhenTheWheelStops() {
        wheelSettleTask?.cancel()
        let clock = clock
        wheelSettleTask = Task { [weak self] in
            await clock.sleep(for: ViewportInputMap.wheelSettleDelay)
            guard !Task.isCancelled, let self else { return }
            scrollEnded()
        }
    }

    /// The scroll under way ended: the hover is re-picked and the camera settles, once.
    private func scrollEnded() {
        wheelSettleTask?.cancel()
        wheelSettleTask = nil
        guard let start = scrollStartPose else { return }
        scrollStartPose = nil
        refreshHover()
        if !isAnimating, pose != start { events.cameraSettled(pose) }
    }
}
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 148 tests in 17 suites passed` (141 + 7).

- [ ] **Step 5: Put the wheel on the surface**

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(SpatialTapGesture().onEnded { model.click(at: ScreenPoint($0.location)) })
```

with:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onScrollWheel { event in
            model.scrolled(by: Double(event.delta.y.value), at: ScreenPoint(event.location), phase: ViewportScrollPhase(event))
        }
        .gesture(SpatialTapGesture().onEnded { model.click(at: ScreenPoint($0.location)) })
```

- [ ] **Step 6: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: only the pre-existing warning; **932**; 0 violations.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): two-finger scroll and the wheel zoom toward the cursor (C7)"
```

### Task 6: Pinch zooms about the pinch centre

C7 item 2 (`CI-C`, `CI-D`): `MagnifyGesture`. No rotate gesture (spec §6.3 has none for the viewport).

**Files:**
- Create: `Sources/CreatorViewport/Model/PinchStart.swift`, `Sources/CreatorViewport/Model/ViewportModel+Pinch.swift`
- Modify: `Sources/CreatorViewport/Input/ViewportInputMap.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift`, `Sources/CreatorViewport/View/ViewportView+Parts.swift`
- Test: `Tests/CreatorViewportTests/PinchZoomTests.swift` (create)

**Interfaces:**
- Consumes: MetalUI `MagnifyGesture(minimumScaleDelta: Double = 0.01)`, `.onChanged`/`.onEnded` with `MagnifyGesture.Value.magnification: Double` (cumulative, `1 + Σ`) and `.startLocation: Point<Pixels>` (local, fixed for the gesture); `onEnded` comes only after a change.
- Produces: `ViewportModel.pinchChanged(magnification: Double, centre: ScreenPoint)`, `ViewportModel.pinchEnded()`, `struct PinchStart { var pose: CameraPose; var centre: ScreenPoint }` and `ViewportModel.pinchStart: PinchStart?` (internal, untracked), `ViewportInputMap.minimumMagnification = 0.05`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/PinchZoomTests.swift`:

```swift
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorViewport

/// A trackpad pinch zooms about the pinch centre (spec §6.3, docs/metalui-gaps.md C7 item 2). MetalUI's
/// magnification is cumulative from 1, so every step zooms from the camera the pinch began with.
@MainActor
struct PinchZoomTests {
    let size = ViewportSize(width: 400, height: 300)
    let start = CameraPose(target: .zero, distance: 100, yaw: 0.4, pitch: 0.3)
    let centre = ScreenPoint(120, 220)

    func makeModel() -> (ViewportModel, () -> [CameraPose]) {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: ManualClock())
        model.viewSize = size
        var settled: [CameraPose] = []
        model.events.cameraSettled = { settled.append($0) }
        return (model, { settled })
    }

    @Test func aPinchZoomsAboutItsCentreFromTheCameraItBeganWith() throws {
        let (model, settled) = makeModel()
        let ray = CameraMath.ray(through: centre, start, size: size)
        let under = ray.point(at: (start.target - ray.origin).dot(start.toEye) / ray.direction.dot(start.toEye))
        model.pinchChanged(magnification: 1.5, centre: centre)
        model.pinchChanged(magnification: 2, centre: centre)
        #expect(isClose(model.pose.distance, 50), "cumulative: 2×, not 1.5 × 2")
        #expect(isClose(try #require(CameraMath.project(under, model.pose, size: size)).point, centre, tolerance: 1e-9))
        #expect(settled().isEmpty, "nothing is reported while the pinch zooms")
        model.pinchChanged(magnification: 0.5, centre: centre)
        #expect(isClose(model.pose.distance, 200), "pinching back out goes past where it began")
        model.pinchEnded()
        #expect(settled() == [model.pose])
        model.pinchEnded()
        #expect(settled().count == 1, "one end, one report")
    }

    @Test func aSecondPinchStartsFromWhereTheFirstLeftTheCamera() {
        let (model, _) = makeModel()
        model.pinchChanged(magnification: 2, centre: centre)
        model.pinchEnded()
        model.pinchChanged(magnification: 2, centre: centre)
        #expect(isClose(model.pose.distance, 25))
    }

    /// MetalUI drops a pinch whose end was lost without a word (window resigned mid-gesture, its `CI-AB`); the next
    /// pinch must zoom from where the camera is, not from where the lost one began.
    @Test func aPinchThatLostItsEndDoesntPullTheNextOneBack() {
        let (model, settled) = makeModel()
        model.pinchChanged(magnification: 2, centre: centre)
        let lost = model.pose
        model.pinchChanged(magnification: 1.25, centre: ScreenPoint(300, 100))
        #expect(isClose(model.pose.distance, 40), "1.25× from the lost pinch's 50 mm")
        #expect(settled() == [lost], "the lost pinch settled where it was")
    }

    @Test func aHardPinchInHoldsInsteadOfSpringingBack() {
        let (model, _) = makeModel()
        model.pinchChanged(magnification: 0.2, centre: centre)
        model.pinchChanged(magnification: -0.3, centre: centre)
        #expect(isClose(model.pose.distance, 100 / ViewportInputMap.minimumMagnification))
        let held = model.pose
        model.pinchChanged(magnification: .nan, centre: centre)
        #expect(model.pose == held)
        #expect(model.pose.isFinite)
    }

    @Test func aPinchStopsACameraAnimation() {
        let (model, _) = makeModel()
        model.perform(.rotate(.left))
        model.pinchChanged(magnification: 1.2, centre: centre)
        #expect(!model.isAnimating)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'ViewportModel' has no member 'pinchChanged'` (and `pinchEnded`, and `type 'ViewportInputMap' has no member 'minimumMagnification'`).

- [ ] **Step 3: Add the pinch**

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits, middle-drag pans and two-finger scroll zooms toward the
/// cursor. The keys (F frames, + and − zoom) are still window-wide stopgaps until MetalUI scopes keys to an element
/// (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
```

with:

```swift
/// The viewport's input bindings (spec §9), in one place. Pointer input is MetalUI C7's: primary drag orbits,
/// Shift-drag pans and ⌥-drag zooms, right-drag orbits, middle-drag pans, two-finger scroll zooms toward the cursor
/// and a pinch zooms about its centre. The keys (F frames, + and − zoom) are still window-wide stopgaps until
/// MetalUI scopes keys to an element (docs/metalui-gaps.md M4-a).
public enum ViewportInputMap {
```

In `Sources/CreatorViewport/Input/ViewportInputMap.swift`, replace:

```swift
    public static let wheelSettleDelay = 0.15
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
```

with:

```swift
    public static let wheelSettleDelay = 0.15
    /// The smallest pinch magnification the zoom follows. MetalUI's magnification is 1 plus the pinch's deltas, so
    /// a hard pinch-in can reach zero or below.
    public static let minimumMagnification = 0.05
    /// How far a press moves before it drags. A primary press that moves less is a click (MetalUI's tap slop is
```

Create `Sources/CreatorViewport/Model/PinchStart.swift`:

```swift
import CreatorGeometry

/// Where a pinch in progress began: the camera it zooms from and its centre in viewport points.
struct PinchStart {
    var pose: CameraPose
    var centre: ScreenPoint
}
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
    @ObservationIgnored var wheelSettleTask: Task<Void, Never>?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
```

with:

```swift
    @ObservationIgnored var wheelSettleTask: Task<Void, Never>?
    /// Where the pinch under way began; `nil` between pinches.
    @ObservationIgnored var pinchStart: PinchStart?
    @ObservationIgnored var lastHoverPoint: ScreenPoint?
```

Create `Sources/CreatorViewport/Model/ViewportModel+Pinch.swift`:

```swift
import CreatorGeometry

extension ViewportModel {
    /// A trackpad pinch (spec §6.3, docs/metalui-gaps.md C7 item 2), from MetalUI's `MagnifyGesture`:
    /// `magnification` is cumulative from 1 since the pinch began, and `centre` is where it began (the pointer
    /// doesn't move during a pinch). The camera zooms by `magnification` from where it was when the pinch began,
    /// toward `centre`. A pinch-in to zero or below holds at `ViewportInputMap.minimumMagnification` rather than
    /// springing back; a non-finite value changes nothing. A pinch that begins somewhere else while one is under
    /// way means that one lost its end (MetalUI drops such a pinch without a word, its `CI-AB`): it ends first.
    public func pinchChanged(magnification: Double, centre: ScreenPoint) {
        guard magnification.isFinite else { return }
        if let start = pinchStart, start.centre != centre { pinchEnded() }
        if pinchStart == nil {
            stopAnimation()
            pinchStart = PinchStart(pose: pose, centre: centre)
        }
        guard let start = pinchStart else { return }
        let factor = max(magnification, ViewportInputMap.minimumMagnification)
        apply(CameraNavigation.zoom(start.pose, factor: factor, toward: centre, size: viewSize))
    }

    /// The pinch ended: the camera settles where it is, once.
    public func pinchEnded() {
        guard let start = pinchStart else { return }
        pinchStart = nil
        refreshHover()
        if !isAnimating, pose != start.pose { events.cameraSettled(pose) }
    }
}
```

- [ ] **Step 4: Run the viewport tests**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`
Expected: `Test run with 153 tests in 18 suites passed` (148 + 5).

- [ ] **Step 5: Put the pinch on the surface**

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        .gesture(drag(.middle, model: model))
        .onContinuousHover { phase in
```

with:

```swift
        .gesture(drag(.middle, model: model))
        .gesture(MagnifyGesture()
            .onChanged { model.pinchChanged(magnification: $0.magnification, centre: ScreenPoint($0.startLocation)) }
            .onEnded { _ in model.pinchEnded() })
        .onContinuousHover { phase in
```

- [ ] **Step 6: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: only the pre-existing warning; **937**; 0 violations.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): a pinch zooms about where it began (C7 MagnifyGesture)"
```

### Task 7: Cursors — a crosshair while picking, a closed hand while navigating

C7 item 5 (`CI-H`): `.pointerStyle(_:)`; MetalUI's crosshair is `.rectSelection`.

**Files:**
- Create: `Sources/CreatorViewport/Input/ViewportCursor.swift`, `Sources/CreatorViewport/View/ViewportCursor+MetalUI.swift`, `Sources/CreatorViewport/Model/ViewportModel+Cursor.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift`, `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, `Sources/CreatorViewport/View/ViewportView+Parts.swift`, `Sources/ViewportHarness/main.swift`, **shared:** `Sources/CreatorApp/AppModel+Scene.swift` (one line in `refreshScene()` and its doc comment)
- Test: `Tests/CreatorViewportTests/CursorTests.swift` (create), **shared:** `Tests/CreatorAppTests/PickCursorTests.swift` (create)

**Interfaces:**
- Consumes: MetalUI `.pointerStyle(_ style: PointerStyle?)` on the proposal path (`nil` attaches nothing, so the platform arrow shows), `PointerStyle.rectSelection`, `.grabActive`; `AppModel.pick: PickSession?` (CreatorApp, existing, observed by `observeScene()`).
- Produces:
  - `public enum ViewportCursor: Hashable, Sendable { case crosshair, grabbing }` and `var pointerStyle: PointerStyle`
  - `public var isPicking: Bool` on `ViewportModel` (tracked; the host sets it)
  - `public internal(set) var activeDragMode: ViewportDragMode?` on `ViewportModel` (tracked; written once per press and release)
  - `public var cursor: ViewportCursor?` on `ViewportModel`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/CursorTests.swift`:

```swift
import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

/// The pointer's shape (docs/metalui-gaps.md C7 item 5): a crosshair while picking, a closed hand while orbiting
/// or panning, the arrow otherwise.
@MainActor
struct CursorTests {
    func makeModel() -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        return model
    }

    @Test func theCursorIsAHandWhileOrbitingOrPanningAndACrosshairWhilePicking() {
        let model = makeModel()
        #expect(model.cursor == nil)
        model.isPicking = true
        #expect(model.cursor == .crosshair)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .orbit)
        #expect(model.cursor == .grabbing, "the hand wins while a drag navigates")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(220, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == nil)
        #expect(model.cursor == .crosshair)
        model.isPicking = false
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        #expect(model.cursor == .grabbing)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(220, 150), modifiers: [], button: .middle)
        model.dragChanged(from: model.cubeLayout.center, to: model.cubeLayout.center + ScreenPoint(10, 0), modifiers: [],
                          button: .primary)
        #expect(model.cursor == .grabbing, "dragging the cube orbits")
    }

    @Test func zoomAndHandleDragsKeepTheArrow() {
        let model = makeModel()
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        #expect(model.activeDragMode == .zoom)
        #expect(model.cursor == nil)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        model.isPicking = true
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(200, 120), modifiers: .option, button: .primary)
        #expect(model.cursor == .crosshair)
    }

    /// A drag whose release was lost leaves no closed hand behind once the primary button is used again
    /// (docs/metalui-gaps.md VI-a).
    @Test func aClickAfterALostDragBringsBackTheArrow() {
        let model = makeModel()
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(220, 150), modifiers: [], button: .middle)
        #expect(model.cursor == .grabbing)
        model.click(at: ScreenPoint(300, 220))
        #expect(model.activeDragMode == nil)
        #expect(model.cursor == nil)
    }

    @Test func cursorsAreMetalUIPointerStyles() {
        #expect(ViewportCursor.crosshair.pointerStyle == .rectSelection)
        #expect(ViewportCursor.grabbing.pointerStyle == .grabActive)
    }
}
```

Create `Tests/CreatorAppTests/PickCursorTests.swift`:

```swift
import CreatorGeometry
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// "Pick edges in view…" shows a crosshair over the viewport (docs/metalui-gaps.md C7 item 5).
@MainActor
struct PickCursorTests {
    @Test func theViewportShowsACrosshairOnlyWhilePicking() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 200))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        let app = await makeApp(builder.graph)
        #expect(!app.viewport.isPicking)
        app.beginPick(for: rule.id)
        await app.settle()
        #expect(app.pick != nil)
        #expect(app.viewport.isPicking)
        #expect(app.viewport.cursor == .crosshair)
        app.cancelPick()
        await app.settle()
        #expect(!app.viewport.isPicking)
        #expect(app.viewport.cursor == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'ViewportModel' has no member 'isPicking'` (and `cursor`, `activeDragMode`).

- [ ] **Step 3: Add the cursor to the model**

Create `Sources/CreatorViewport/Input/ViewportCursor.swift`:

```swift
/// The pointer's shape over the viewport (docs/metalui-gaps.md C7 item 5).
public enum ViewportCursor: Hashable, Sendable {
    /// Picking edges: a crosshair.
    case crosshair
    /// Orbiting or panning: a closed hand.
    case grabbing
}
```

Create `Sources/CreatorViewport/View/ViewportCursor+MetalUI.swift`:

```swift
import MetalUI

extension ViewportCursor {
    /// The MetalUI pointer style. MetalUI's crosshair is `.rectSelection` (SwiftUI has no `.crosshair`).
    public var pointerStyle: PointerStyle {
        switch self {
        case .crosshair: .rectSelection
        case .grabbing: .grabActive
        }
    }
}
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
    public var shading: ShadingMode = .shadedEdges
    /// The colour theme the viewport draws in (spec §6.6). The app shell sets it from its `ThemeStore`; a change is
```

with:

```swift
    public var shading: ShadingMode = .shadedEdges
    /// True while the host is picking edges in the view ("Pick edges in view…", spec §5.3): the pointer is a
    /// crosshair (`cursor`).
    public var isPicking = false
    /// The colour theme the viewport draws in (spec §6.6). The app shell sets it from its `ThemeStore`; a change is
```

In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:

```swift
    public internal(set) var hoveredCubeRegion: ViewCubeRegion?
    /// Bumped each time a scene's meshes are ready.
```

with:

```swift
    public internal(set) var hoveredCubeRegion: ViewCubeRegion?
    /// What the drag under way does, or `nil` between drags. It's written once at each press and release (never per
    /// move), so the view's pointer style follows it.
    public internal(set) var activeDragMode: ViewportDragMode?
    /// Bumped each time a scene's meshes are ready.
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift
                         handleStartValue: handleStart)
    }
```

with:

```swift
                         handleStartValue: handleStart)
        if activeDragMode != mode { activeDragMode = mode }
    }
```

In `Sources/CreatorViewport/Model/ViewportModel+Input.swift`, replace:

```swift
        drag = nil
        if case .handle(let id) = state.mode { updateHandle(id, state, to: point, phase: .ended) }
```

with:

```swift
        drag = nil
        activeDragMode = nil
        if case .handle(let id) = state.mode { updateHandle(id, state, to: point, phase: .ended) }
```

Create `Sources/CreatorViewport/Model/ViewportModel+Cursor.swift`:

```swift
extension ViewportModel {
    /// The pointer's shape over the viewport, or `nil` for the platform's arrow: a closed hand while a drag orbits
    /// or pans (the cube's drag orbits too), else a crosshair while the host is picking edges (`isPicking`).
    public var cursor: ViewportCursor? {
        switch activeDragMode {
        case .orbit?, .pan?, .cube?: .grabbing
        case .zoom?, .handle?, nil: isPicking ? .crosshair : nil
        }
    }
}
```

- [ ] **Step 4: Run the viewport tests, and see the app test fail**

Run: `swift test --filter CreatorViewportTests 2>&1 | grep "Test run with"`, then `swift test --filter PickCursorTests 2>&1 | grep -E "Expectation failed|Test run with"`
Expected: `Test run with 157 tests in 19 suites passed` (153 + 4); `PickCursorTests` fails at `#expect(app.viewport.isPicking)` (nothing sets it yet).

- [ ] **Step 5: The app sets `isPicking`; the surface shows the cursor; the harness can show the crosshair**

`refreshScene()` already runs whenever `pick` changes (`observeScene()` reads it), and on New and Open (a new viewport starts with `isPicking == false`).

In `Sources/CreatorApp/AppModel+Scene.swift`, replace:

```swift
    /// Shows the scene and the selected nodes' handles. While picking, only the solid being picked on, with the
    /// picked edges selected, and no handles. A scene or handles equal to what's shown aren't sent again: the
    /// observation also fires for canvas pans, camera settles and panel resizes, which change neither.
```

with:

```swift
    /// Shows the scene and the selected nodes' handles. While picking, only the solid being picked on, with the
    /// picked edges selected, no handles and a crosshair pointer. A scene or handles equal to what's shown aren't sent again: the
    /// observation also fires for canvas pans, camera settles and panel resizes, which change neither.
```

In `Sources/CreatorApp/AppModel+Scene.swift`, replace:

```swift
        let scene: [SceneItem]
        if let pick {
```

with:

```swift
        let scene: [SceneItem]
        if viewport.isPicking != (pick != nil) { viewport.isPicking = pick != nil }
        if let pick {
```

In `Sources/CreatorViewport/View/ViewportView+Parts.swift`, replace:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onScrollWheel { event in
```

with:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pointerStyle(model.cursor?.pointerStyle)
        .onScrollWheel { event in
```

In `Sources/ViewportHarness/main.swift`, replace:

```swift
/// - `HARNESS_SELECT=1` selects its top face and edges.
/// Clicking a face selects it and its edges (an edge selects that edge; empty space clears). Dragging a handle
```

with:

```swift
/// - `HARNESS_SELECT=1` selects its top face and edges.
/// - `HARNESS_PICK=1` shows the picking crosshair, as the app does while picking edges.
/// Clicking a face selects it and its edges (an edge selects that edge; empty space clears). Dragging a handle
```

In `Sources/ViewportHarness/main.swift`, replace:

```swift
    let model = ViewportModel(kernel: kernel)
    let selection = HarnessSelection()
```

with:

```swift
    let model = ViewportModel(kernel: kernel)
    model.isPicking = environment["HARNESS_PICK"] == "1"
    let selection = HarnessSelection()
```

- [ ] **Step 6: Check the whole package**

Run: `swift test --filter CreatorAppTests 2>&1 | grep "Test run with"`, `swift build --build-tests 2>&1 | grep "warning:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swiftlint lint --strict`
Expected: `Test run with 56 tests in 12 suites passed`; only the pre-existing warning; **942**; 0 violations.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Sources/ViewportHarness Sources/CreatorApp/AppModel+Scene.swift Tests/CreatorViewportTests/CursorTests.swift Tests/CreatorAppTests/PickCursorTests.swift
git commit -m "feat(viewport): a crosshair while picking and a closed hand while navigating (C7 pointer style)"
```

### Task 8: Record what C7 closed, and the human checks

**Files:**
- Modify: `docs/metalui-gaps.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, `docs/verification/human-checks.md` (group V's V3, V4 and V6; new group VC before group M5), `CLAUDE.md`, `AGENTS.md` (all shared)

**Interfaces:**
- Consumes: the names Tasks 1–7 produced (`dragChanged`/`dragEnded`, `click(at:)`, `contextMenuItems(at:)`, `scrolled(by:at:phase:)`, `pinchChanged`, `cursor`, `CameraNavigation.frame(_:_:size:insets:)`, `ViewportInsets.usable(in:)`) and the test names the gaps doc and the human checks cite.
- Produces: documentation only.

- [ ] **Step 1: The gaps doc marks items 1–5 and gaps 4 and 5 closed for the viewport, and logs VI-a**

In `docs/metalui-gaps.md`, replace:

````markdown

Nothing landed or designed yet; C7 is next after MetalUI's C4. Names below are provisional (C7's design phase
probes SwiftUI and may rule otherwise; where SwiftUI has a spelling, MetalUI takes it). MetalCreator wraps each
stopgap behind one function/modifier of its own, named after these, so the swap is local.
````

with:

````markdown

**Merged (MetalUI `c62d6ba`, record §81, rulings `CI-A`…`CI-AL`).** Every provisional name below was kept. The
refinements: `.onScrollWheel`'s closure returns `Bool` (`true` claims), the scroll's local point is
`ScrollEvent.location`, `RotateGesture.Value.rotation` is clockwise-positive, the crosshair is
`PointerStyle.rectSelection`, and the located context menu is `.contextMenu { (location: Point<Pixels>?) in … }`
(`CI-R`). **The viewport has adopted it** (plan `docs/superpowers/plans/2026-10-09-viewport-input-c7.md`): items 1–5
are closed for the viewport, and gaps 4 and 5 below with them. The graph panel's adoption (M5-e, M5-f and the
canvas's share of items 1 and 2) is a later plan; the viewport's keys still wait for key scoping (M4-a, MetalUI C9).

The provisional names, as the MetalUI session reported them on 2026-10-08 (all kept: C7's design phase probed
SwiftUI, and where SwiftUI has a spelling MetalUI took it). MetalCreator wraps each stopgap that is left (the graph
panel's, in `GraphPanelInput`) behind one function/modifier of its own, named after these, so the swap is local.
````

In `docs/metalui-gaps.md`, replace:

````markdown

- **Gap 5 (C7 item 5, now concrete): modifiers during a drag.** Shift-drag pans and ⌥-drag zooms the viewport (spec §9).
   `DragGesture.Value` has no modifiers. Stopgap: `ViewportModifierTracker` follows `.modifiersChanged` through a
````

with:

````markdown

- ✅ **Closed by C7 (viewport, 2026-10-09):** the drags read `DragGesture.Value.modifiers` and
   `ViewportModifierTracker` is deleted; the closed hand (`.grabActive`) shows while a drag orbits or pans, and the
   crosshair (`.rectSelection`) while picking.
   **Gap 5 (C7 item 5, now concrete): modifiers during a drag.** Shift-drag pans and ⌥-drag zooms the viewport (spec §9).
   `DragGesture.Value` has no modifiers. Stopgap: `ViewportModifierTracker` follows `.modifiersChanged` through a
````

In `docs/metalui-gaps.md`, replace:

````markdown
   Known limit: `held` modifiers can go stale if Shift is released while the window is inactive.
- **Gap 4 (C7 item 4, now concrete): context-menu location.** The face menu must know which face was under the
   secondary press: the press point in the element's local points. Stopgap: the last `onContinuousHover` point
````

with:

````markdown
   Known limit: `held` modifiers can go stale if Shift is released while the window is inactive.
- ✅ **Closed by C7 (viewport, 2026-10-09):** the face menu uses the located `.contextMenu` and picks at the right
   press (`ViewportModel.contextMenuItems(at:)`); clicks are a `SpatialTapGesture` (`ViewportModel.click(at:)`). A
   right-drag (`DragGesture(button: .secondary)`) orbits, and a right press that moves less than 5 points opens the
   menu on its release.
   **Gap 4 (C7 item 4, now concrete): context-menu location.** The face menu must know which face was under the
   secondary press: the press point in the element's local points. Stopgap: the last `onContinuousHover` point
````

In `docs/metalui-gaps.md`, replace:

````markdown
   event since. Wanted: the opening location passed to the `.contextMenu` builder, or `SpatialTapGesture` for secondary clicks.
- **Gap 1 (C7 item 1): scroll-wheel zoom toward the cursor.** Not available. Stopgaps: ⌥-drag and the +/− keys
   (`ViewportInputMap`). The C7 shape the viewport expects is in the "C7 status" section above.
````

with:

````markdown
   event since. Wanted: the opening location passed to the `.contextMenu` builder, or `SpatialTapGesture` for secondary clicks.
- ✅ **Closed by C7 (viewport, 2026-10-09), with items 2 and 3:** `.onScrollWheel` zooms toward `ScrollEvent.location`
   (a run of wheel steps settles the camera once the wheel has been still for 0.15 s, a trackpad scroll at its end,
   momentum ignored), `MagnifyGesture` zooms
   about `startLocation`, and middle-drag pans. ⌥-drag and the +/− keys stay. The viewport has no rotate gesture
   (spec §6.3 gives it none).
   **Gap 1 (C7 item 1): scroll-wheel zoom toward the cursor.** Not available. Stopgaps: ⌥-drag and the +/− keys
   (`ViewportInputMap`). The C7 shape the viewport expects is in the "C7 status" section above.
````

In `docs/metalui-gaps.md`, replace:

````markdown

## Node-drag performance, 2026-10-08
````

with:

````markdown

## Hit by the viewport's C7 adoption, 2026-10-09

Labelled VI-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a… and PERF-a… entries.

- **VI-a. A gesture dropped without an end tells its owner nothing.** MetalUI drops a stale button arena or pinch
  arena silently when the next press of that button, or the next pinch, arrives (`CI-AB`: no `onEnded`), and the
  primary arena's re-formation drops a drag the same way. SwiftUI resets per-gesture state on cancellation through
  `@GestureState` / `updating(_:body:)`, which MetalUI doesn't offer (`IX-B`). The viewport holds per-gesture state
  in its model: the drag's mode (and with it the closed-hand cursor) and the camera a pinch began from. Stopgap:
  `ViewportModel` ends a drag, where it was, when a value of the same button arrives from another press, or a
  primary drag value or a click arrives while another button's drag is under way (MetalUI forms the primary arena on
  every primary press, `CI-F` item 3); and a pinch when one begins at another centre
  (`aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain`, `aPrimaryDragAfterALostMiddleReleaseStillOrbits`,
  `aClickAfterALostDragEndsItAndHoversAgain`, `aClickAfterALostDragBringsBackTheArrow`,
  `aPinchThatLostItsEndDoesntPullTheNextOneBack`). What is left: nothing for primary input. A lost right or middle
  release leaves that drag, its closed hand and a still hover until the next primary press or click, or the next
  drag of the same button; until then a drag of the other of the two is ignored, as MetalUI ignores its press
  (`CI-AA` item 4). Wanted: an `onEnded` (or a separate cancellation callback) for a gesture its arena drops, or
  `@GestureState`.

## Node-drag performance, 2026-10-08
````

- [ ] **Step 2: The carry-over note marks the From M4 stopgaps and the From M6 framing item done**

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
    `ViewState` is synced without observing `pose` at 60 Hz.
  - Both input stopgaps take over `Window.onInput`: M4's `ViewportModifierTracker` and M5's `GraphPanelInput`.
    `ViewportModifierTracker.install(on:)` chains to the previous handler. Whichever is installed second must chain
    too (or share one modifier tracker), or the other silently stops seeing events.
  - `selectEdgesOfFace` → an Edges by Tag node: `.setInput(node, NodeSetting.picks, .edgePicks(picks))` with the
````

with:

````markdown
    `ViewState` is synced without observing `pose` at 60 Hz.
  - ✅ (viewport C7) Both input stopgaps take over `Window.onInput`: M4's `ViewportModifierTracker` and M5's
    `GraphPanelInput`. The viewport's tracker is gone (its drags read `DragGesture.Value.modifiers`), so only
    `GraphPanelInput` is left on `onInput`, through `AppInput`.
  - `selectEdgesOfFace` → an Edges by Tag node: `.setInput(node, NodeSetting.picks, .edgePicks(picks))` with the
````

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
- Stopgaps to delete when MetalUI C7 lands: `ViewportModifierTracker`, the hover-point context menu, window-wide viewport keys.
- `ViewportPalette` (GPU colours) duplicates spec §6.6 hex values that M5's `Palette` will also hold. M5 can't unify
````

with:

````markdown
- Stopgaps to delete when MetalUI C7 lands: `ViewportModifierTracker`, the hover-point context menu, window-wide viewport keys.
  ✅ (viewport C7, plan `2026-10-09-viewport-input-c7.md`) The tracker and the hover-point menu are gone: drags read
  `DragGesture.Value.modifiers`, and the face menu picks at the right press (`contextMenuItems(at:)`, the located
  `.contextMenu`). The keys stay window-wide (`!Panel` context) until MetalUI C9 scopes keys to an element.
  C7 also brought: two-finger scroll zooms toward the cursor (momentum ignored), pinch zooms about its centre,
  middle-drag pans, right-drag orbits (a right click still opens the menu), `SpatialTapGesture` clicks, and the
  crosshair and closed-hand cursors. The graph panel's own C7 swap (From M5) is still to do.
- `ViewportPalette` (GPU colours) duplicates spec §6.6 hex values that M5's `Palette` will also hold. M5 can't unify
````

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
  capture a `GraphPanelInput`, `EditorModel` or `ViewportModel` for the window's lifetime.
- The first framing, F and Look At frame the part in the whole viewport, not the model area the panels leave, so a
  part can sit partly under the graph panel. Owner: roadmap row "Viewport: frame in the model area" (teach
  `CameraNavigation.frame` `ViewportModel.modelArea`; the insets already exist).
- In Final preview a selected rule that feeds a feature glows nothing (spec Errata (M6)). Owner: roadmap row
````

with:

````markdown
  capture a `GraphPanelInput`, `EditorModel` or `ViewportModel` for the window's lifetime.
- ✅ (viewport C7 plan) The first framing, F and Look At frame the part in the whole viewport, not the model area the
  panels leave, so a part can sit partly under the graph panel. Owner: roadmap row "Viewport: frame in the model
  area". Done: `CameraNavigation.frame(_:_:size:insets:)` centres and fits the part in `ViewportModel.modelArea`,
  and the arrows, the cube's regions, a cube drag and the +/− keys without a pointer turn or zoom about the model
  area's centre (`modelAreaPivot(_:)`), so the part stays there; insets the view can't honour are ignored for framing
  (`ViewportInsets.usable(in:)`), though `setModelArea` still takes them unvalidated (M7 item below).
- In Final preview a selected rule that feeds a feature glows nothing (spec Errata (M6)). Owner: roadmap row
````

- [ ] **Step 3: Human checks for each gesture**

In `docs/verification/human-checks.md`, replace:

````markdown
- [ ] **V3 Pan, zoom and frame.**
  - Shift-drag pans with the pointer (the stopgap modifier tracker). Known limit (gap 5): `held` modifiers can go stale if Shift is released while the window is inactive.
  - ⌥-drag up zooms in toward where the drag began.
````

with:

````markdown
- [ ] **V3 Pan, zoom and frame.**
  - Shift-drag pans with the pointer (Shift held when the drag starts; the drag reads it from MetalUI, C7).
  - ⌥-drag up zooms in toward where the drag began.
````

In `docs/verification/human-checks.md`, replace:

````markdown
- [ ] **V4 Hover.** The face under the pointer gets a faint cyan tint that follows the pointer without flicker or lag.
  After an orbit drag, a +/− zoom or a view-cube click with the pointer left still, the tint (and a right-click menu)
  is on the face under the pointer now, not the one before the move.
  Pinned: `hoverAsksThePickerOrTheCube`, `movingTheCameraUnderAStillPointerRepicks`,
````

with:

````markdown
- [ ] **V4 Hover.** The face under the pointer gets a faint cyan tint that follows the pointer without flicker or lag.
  After an orbit drag, a +/− zoom or a view-cube click with the pointer left still, the tint is on the face under
  the pointer now, not the one before the move.
  Pinned: `hoverAsksThePickerOrTheCube`, `movingTheCameraUnderAStillPointerRepicks`,
````

In `docs/verification/human-checks.md`, replace:

````markdown
  Pinned: `ViewCubeTests`, `clickingTheCubeLooksAtTheRegionUnderThePointer`, `arrowsAndHomeAnimate`. Observed: 2026-10-07: the painted face labels sit on the faces, turn with the cube and read well (user). Animation, edge/corner views, cube drag, arrows, ⌂ and the View menu not yet confirmed.
- [ ] **V6 Face menu.** Right-click a face: Look At, Select Edges of Face and Show Producing Node.
  - Look At animates to face that face, orthographic, framed on it.
````

with:

````markdown
  Pinned: `ViewCubeTests`, `clickingTheCubeLooksAtTheRegionUnderThePointer`, `arrowsAndHomeAnimate`. Observed: 2026-10-07: the painted face labels sit on the faces, turn with the cube and read well (user). Animation, edge/corner views, cube drag, arrows, ⌂ and the View menu not yet confirmed.
- [ ] **V6 Face menu.** Right-click a face: Look At, Select Edges of Face and Show Producing Node, for the face under
  the right press (VC5 checks that after the camera moves).
  - Look At animates to face that face, orthographic, framed on it.
````

In `docs/verification/human-checks.md`, replace:

````markdown
  `gridSpacingStepsWithZoom`. Observed:

````

with:

````markdown
  `gridSpacingStepsWithZoom`. Observed:

## Group VC — viewport input on MetalUI C7

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`); MetalUI's own
group Y covers the platform side (trackpad phases, real mouse buttons, every cursor).

Run `swift run ViewportHarness` (VC7 also with `HARNESS_PICK=1`) with a trackpad and a three-button mouse; VC8 runs
`swift run MetalCreatorApp` on a saved bracket. Clicks and menu choices print to the terminal.

- [ ] **VC1 Scroll zoom.** Two-finger scroll over the part zooms toward the point under the pointer: that point
  stays put. When the fingers lift the zoom stops at once (no glide). A wheel mouse zooms in steps of about 10%;
  spinning it fast stays smooth, and the hover tint catches up just after the wheel stops.
  Scrolling one way zooms in and the other way out; note which way feels wrong, if one does (the sign is
  `ViewportModel.scrolled(by:at:phase:)`). Pinned: `ScrollZoomTests` (`aRunOfWheelStepsSettlesOnce`),
  `scrollEventsMapToZoomPhases`. Observed:
- [ ] **VC2 Pinch.** Pinching out zooms in about the point where the pinch began, and pinching in zooms out; a hard
  pinch-in holds instead of springing back. A twist does nothing. Pinned: `PinchZoomTests`. Observed:
- [ ] **VC3 Right and middle drags.** Middle-drag pans with the pointer, whatever is held. Right-drag orbits about the
  point under the pointer (on the view cube, it orbits like a cube drag) and opens no menu. A right click that
  doesn't move opens the face menu on release. Right-drag on a handle's knob orbits and leaves the value alone.
  Middle-drag, ⌘-Tab away before releasing, release, come back: a primary drag orbits at once and the closed hand
  goes. Pinned: `ButtonDragTests`, `theRightButtonOrbitsAndTheMiddleButtonPans`. Observed:
- [ ] **VC4 Clicks.** A click on a face or an edge prints `clicked` with it; on empty space `clicked: nil`. A press
  dragged more than a few points and brought back prints no click (the camera keeps the orbit). A click on a view-cube
  face still animates to it, and a click on a handle's knob prints nothing. Pinned: `aClickReportsThePickAtItsLocationAndLeavesTheCameraAlone`,
  `aDragThatComesBackToItsStartIsNotAClick`, `aClickOnAHandleKnobOrTheCubeReportsNoPick`. Observed:
- [ ] **VC5 The menu is for the face under the press.** Hover a face, scroll-zoom so another face comes under the
  still pointer, and right-click without moving: the menu is for the face under the pointer now (Look At turns to
  it). Right-click the view cube: no face menu. Pinned: `theMenuIsForTheFaceUnderThePressNotTheLastHover`,
  `noFaceMenuOverTheViewCubeOrWithoutAPointer`. Observed:
- [ ] **VC6 Modifiers mid-drag.** Hold Shift, then drag: it pans. Hold ⌥, then drag up: it zooms in. Switch to another
  app with Shift held, release Shift there, come back and drag: it orbits (no stale Shift). Pinned:
  `aPrimaryDragTakesItsModeFromItsOwnModifiers`. Observed:
- [ ] **VC7 Cursors.** A closed hand while a primary, right or middle drag orbits or pans, and while dragging the view
  cube; the arrow for a ⌥-drag zoom, a handle drag and over the cube's buttons. With `HARNESS_PICK=1` the pointer is a
  crosshair over the viewport, and a hand while a drag navigates. In the app, "Pick edges in view…" shows the
  crosshair; Done or Cancel brings the arrow back. Pinned: `CursorTests`, `theViewportShowsACrosshairOnlyWhilePicking`.
  Observed:
- [ ] **VC8 Framing in the model area (app).** Open a saved bracket with no saved camera (or press F): the part sits
  in the middle of the area right of the graph panel and left of the inspector, not under either. Dock the panel at
  the bottom and press F: the part is centred above the panel. Right-click a face ▸ Look At: the face is centred in
  the same area. With either dock, after F click ▶, then ▲, then a cube face and a cube corner, then drag the cube:
  the part turns in place, centred in the area, never swinging under the inspector or the bottom panel. With the
  pointer off the window (over the menu bar), press + and −: the part stays centred. Pinned:
  `ModelAreaFramingTests`. Observed:

````

- [ ] **Step 4: CLAUDE.md and AGENTS.md describe the new input**

In `CLAUDE.md`, replace:

````markdown
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
Viewport input stopgaps (spec §9) live only in `ViewportInputMap`, `ViewportModifierTracker` and `ViewportKeyBindings` until MetalUI C7.
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
````

with:

````markdown
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`, `click(at:)`, `contextMenuItems(at:)`, `scrolled(by:at:phase:)`,
`pinchChanged`, `cursor`), and `ViewportView` only forwards gesture values. Its keys stay window-wide stopgaps in
`ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
````

In `AGENTS.md`, replace:

````markdown
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
Viewport input stopgaps (spec §9) live only in `ViewportInputMap`, `ViewportModifierTracker` and `ViewportKeyBindings` until MetalUI C7.
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
````

with:

````markdown
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`, `click(at:)`, `contextMenuItems(at:)`, `scrolled(by:at:phase:)`,
`pinchChanged`, `cursor`), and `ViewportView` only forwards gesture values. Its keys stay window-wide stopgaps in
`ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
````

- [ ] **Step 5: Check the names the docs cite**

Run: `for t in aClickReportsThePickAtItsLocationAndLeavesTheCameraAlone aDragThatComesBackToItsStartIsNotAClick aClickOnAHandleKnobOrTheCubeReportsNoPick theMenuIsForTheFaceUnderThePressNotTheLastHover noFaceMenuOverTheViewCubeOrWithoutAPointer aPrimaryDragTakesItsModeFromItsOwnModifiers theViewportShowsACrosshairOnlyWhilePicking theRightButtonOrbitsAndTheMiddleButtonPans scrollEventsMapToZoomPhases aRunOfWheelStepsSettlesOnce aDragThatLostItsReleaseEndsWhenItsButtonDragsAgain aPrimaryDragAfterALostMiddleReleaseStillOrbits aClickAfterALostDragEndsItAndHoversAgain aClickAfterALostDragBringsBackTheArrow aPinchThatLostItsEndDoesntPullTheNextOneBack ScrollZoomTests PinchZoomTests ButtonDragTests CursorTests ModelAreaFramingTests; do grep -rq "$t" Tests || echo "missing $t"; done; grep -rn "ViewportModifierTracker" CLAUDE.md AGENTS.md docs/verification`
Expected: no output from either.

Run: `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'` and `swiftlint lint --strict`
Expected: **942**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add docs/metalui-gaps.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md docs/verification/human-checks.md CLAUDE.md AGENTS.md
git commit -m "docs: the viewport's C7 adoption closes gaps 1-5 for the viewport; human checks VC"
```

## Self-review

- **Spec coverage.** §6.3 "Orbit pivots on the point under the cursor" — right-drag uses the same pivot (Task 2, `aRightDragOrbitsAboutThePointUnderThePointer`). "Zoom goes towards the cursor" — scroll and pinch (Tasks 5, 6). "Right-click context menu on a model face" — Task 4. "F frames the selection, or everything" — kept, now in the model area (Task 1). "Drag the cube to orbit freely" — primary and right (Task 2). "Click a face" of the cube — Task 3. §9 items 1–5 — Tasks 5, 6, 2, 3/4, 7/2. §9's kept bindings: primary-drag orbit, Shift-drag pan, ⌥-drag zoom, +/−/F (unchanged keys). Errata (M6) Look At / first framing / F in the whole viewport — Task 1. §7.3 60 fps orbit: the camera still settles only at drag, scroll and pinch ends, and once per run of wheel steps (Tasks 2, 5, 6). Framing in the model area (Task 1) also re-centres the turns that used to pivot on the target (arrows, cube regions, cube drag) and the pointer-less key zoom.
- **Not covered, on purpose:** a viewport rotate gesture (not in spec §6.3); key scoping (MetalUI C9); the graph panel's C7 adoption (later plan); validating `setModelArea` (M7).
- **Placeholders:** none; every code step has its code.
- **Type consistency:** `ViewportPointerButton` (2) is used by `dragChanged`/`dragEnded` (2), `ViewportView.drag` (2, 3) and `CursorTests` (7); `ViewportScrollPhase` (5) cases `.step/.moving/.ended/.momentum` match the tests; `pinchChanged(magnification:centre:)` (6) matches the view and tests; `activeDragMode` and `cursor` (7) match `PickCursorTests`.
- **Review Focus:** each of the six lines has its test in its task (Tasks 4, 6, 2/3/7, 1, 5, 1).
- **New MetalUI gap:** VI-a (a gesture MetalUI drops without an end tells its owner nothing), logged in Task 8 with the model rules that cover it until MetalUI answers.

## Verification of this plan

Done on 2026-10-09, before saving this plan. A scratch copy of the worktree at master `d48d757` (`git archive`), with
a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (master `c62d6ba`), had every code block applied
mechanically, task by task and step by step, from this file (`In … replace` blocks must match exactly once):

| After | Red (Step 1 alone builds?) | `CreatorViewportTests` | Whole `swift test` | New warnings | `swiftlint lint --strict` |
|---|---|---|---|---|---|
| master | — | 117 | **901** | — (one pre-existing) | 0 |
| Task 1 | no: `extra argument 'insets' in call` | 125 | **909** | none | 0 |
| Task 2 | no: `extra argument 'button' in call` | 135 (also after Step 3) | **919** | none | 0 |
| Task 3 | no: `no member 'click'` | 139 | **923** | none | 0 |
| Task 4 | no: `argument passed to call that takes no arguments` | 141 | **925** | none | 0 |
| Task 5 | no: `no member 'scrolled'` (and `'waitForScroll'`) | 148 | **932** | none | 0 |
| Task 6 | no: `no member 'pinchChanged'` | 153 | **937** | none | 0 |
| Task 7 | no: `no member 'isPicking'`; after Step 3 `PickCursorTests` fails at `app.viewport.isPicking` | 157 | **942** | none | 0 |
| Task 8 | — (docs) | 157 | **942** (master + 41) | none | 0 |

Every run passed with 0 issues. "New warnings" compares `swift build --build-tests` (a separate scratch build
path, so each task's changed files recompile) against master's: the only compiler warning before and after is
`ContextMenuTests.swift`'s "'underPointer' mutated after capture by sendable closure" (line 70 on master, 96 after
Task 4 adds tests above it); OCCT's `ld: warning`s are expected. Task 8's Step 5 name check printed nothing.
Re-run on 2026-10-09 after the review revision (model-area turns and key zoom, lost releases ended by a primary
press or click, the wheel's one settle per run of steps, the C7 status sentence); the table is that run. A probe of
the review's case (1280 × 800, the bottom dock's insets top 56, bottom 320, trailing 312) kept the part's centre at
(484, 268), the model area's centre, through F, ▶, ▶, ▲, TOP and the isometric corner.

Not verified here (an agent can't): any real pointer, trackpad or cursor behaviour, which is human-check group VC.
The view glue (`ViewportView+Parts.swift`) compiles but isn't exercised by a test: MetalUI has no public headless
window (gap M6-e).
