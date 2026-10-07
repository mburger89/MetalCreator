# MetalCreator M0–M1: OCCT Probe and Graph Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that OpenCascade builds, links and runs from Swift (M0). Then build the pure-Swift graph engine (geometry types, the `Kernel` protocol with a `FakeKernel`, typed sockets with list broadcasting, a cached and cancellable evaluator, undoable commands, the `.mcgraph` file format, and an observable `DocumentModel`), fully tested headless (M1).

**Architecture:**
- `COCCT` is a C-callable C++ shim over Homebrew OCCT 7.9.3. `CreatorOCCT` wraps it in Swift and is the only Swift code that imports `COCCT`.
- `CreatorGeometry` → `CreatorKernel` → `CreatorGraph` form the pure-Swift core. Graph code only ever sees `any Kernel`, and M1 tests run against `FakeKernel`.
- No MetalUI dependency yet. It arrives with the viewport plan (M4).

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, Observation, C++17, OpenCascade 7.9.3 (Homebrew).

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§3, §4, §5.1–5.2, §5.4, §7.4 M0–M1, §8). Later milestones (M2–M7) each get their own plan, written against the code this plan produces.

**Refinements to the spec made here** (each is consistent with its intent):
- `Profile2D` carries its own `plane`, because a profile is "closed 2D curves on a plane" (spec §4.2). So the kernel methods take a profile without a separate `on plane:` argument.
- OCCT is linked with explicit `-isystem`/`-L` flags pointing at `/opt/homebrew/opt/opencascade`, not through pkg-config. The Homebrew bottle ships only CMake configs and no `.pc` file (spec §5.2 left the mechanism open).
- `ConstantValue` gains a `text` case. It's used for non-socket node settings such as which graph parameter a Graph Parameter node reads.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency: data-race diagnostics are errors. Never silence them with `@unchecked Sendable` or `nonisolated(unsafe)` unless a comment explains why it is sound.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`). Never XCTest.
- Units are millimetres, stored as `Double`.
- **Only `CreatorOCCT` may `import COCCT`.** No OCCT type or name appears outside `Sources/COCCT` and `Sources/CreatorOCCT`.
- One type per Swift file, with the file named after the type. The exception is test fixture files, which are explicitly marked.
- `@Observable` classes are `@MainActor`. Use modern Swift concurrency only: no GCD and no `Task.sleep(nanoseconds:)`.
- Avoid force unwraps and force `try`.
- No third-party Swift packages. OCCT is the single approved C++ dependency.
- Every commit message ends with these two lines:
  ```
  Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS
  ```
- Work happens on branch `design/vertical-slice` (already exists, holds the spec commit) or a branch cut from it.

## Review Focus

These are inputs the spec implies but doesn't spell out, ordered by how likely they are to bite. Each has a test in the task named.

1. **An empty list reaches a broadcast input** (for example Hole count = 0, so a points list is empty). The node should succeed with empty list outputs and not error. *Test: Task 7, `emptyListProducesEmptyOutputs`.*
2. **Rapid edits during a slow evaluation** (a slider drag). Only the newest generation's results should land, and a stale result must never overwrite a newer one. *Test: Task 13, `staleEvaluationNeverOverwritesNewerResult`.*
3. **A non-finite number is typed into a field** (NaN or ±∞, which JSON cannot encode). The command should be refused with a message, so a document can always be saved. *Test: Task 11, `nonFiniteInputIsRejected`.*
4. **A hand-edited or corrupt file** containing a cycle, a link to a missing node, or an unknown node type. It should load without crashing: cyclic nodes show an error, dangling inputs show "waiting", and unknown nodes survive a save round-trip unchanged. *Tests: Task 9 `cycleInFileIsReportedNotFatal`, `danglingLinkBlocksNode`; Task 12 `unknownNodeRoundTrips`.*
5. **Undo after a coalesced slider drag** should restore the pre-drag value in one step, and a new edit after undo should clear redo. *Test: Task 11, `coalescedDragUndoesInOneStep`.*

---

## File Structure

```
MetalCreator/
  Package.swift                                  (rewritten in Task 1, extended in Task 3)
  CLAUDE.md / AGENTS.md                          (updated in Task 14)
  Sources/
    COCCT/include/cocct.h                        C API of the shim
    COCCT/cocct.cpp                              C++ implementation, catches all exceptions
    CreatorOCCT/OCCTError.swift                  Swift error carrying the shim's message
    CreatorOCCT/OCCTShape.swift                  owning Swift wrapper around occt_shape*
    CreatorGeometry/Vector2.swift, Vector3.swift, Angle.swift, Plane.swift, Axis.swift,
                    Transform.swift, BoundingBox.swift, Segment2D.swift, Profile2D.swift
    CreatorKernel/NodeID.swift, NodeTag.swift, TopoRole.swift, TopoTag.swift, EdgeKey.swift,
                  FaceID.swift, EdgeID.swift, SurfaceKind.swift, CurveKind.swift, Convexity.swift,
                  FaceInfo.swift, EdgeInfo.swift, Topology.swift, SolidStorage.swift, Solid.swift,
                  EdgeSet.swift, FaceSet.swift, DisplayMesh.swift, BooleanOp.swift,
                  ExtrudeMode.swift, ExportFormat.swift, KernelError.swift, Kernel.swift,
                  FakeKernel.swift, FakeStorage.swift
    CreatorGraph/ SocketName.swift, ParameterID.swift, SocketType.swift, ConstantValue.swift,
                  Scalar.swift, Value.swift, SocketSpec.swift, ValueUnit.swift, NodeCategory.swift,
                  InspectorSection.swift, InspectorControl.swift, InspectorAction.swift,
                  HandleSpec.swift, NodeError.swift, NodeInputs.swift, NodeOutputs.swift,
                  EvalContext.swift, NodeDefinition.swift, NodeRegistry.swift,
                  Node.swift, Endpoint.swift, Link.swift, GraphParameter.swift, Graph.swift,
                  EvaluationOrder.swift, Graph+Traversal.swift, ConnectionProblem.swift,
                  Graph+Connections.swift, GraphError.swift,
                  BroadcastPlan.swift, NodeState.swift, NodeResult.swift, CacheKey.swift,
                  ResultCache.swift, EvaluationReport.swift, Evaluator.swift,
                  GraphCommand.swift, Graph+Commands.swift, UndoStack.swift,
                  DockSide.swift, ViewState.swift, GraphFile.swift, GraphFileError.swift,
                  GraphFileIO.swift, DocumentModel.swift
  Tests/
    CreatorOCCTTests/OCCTProbeTests.swift
    CreatorGeometryTests/GeometryTests.swift
    CreatorKernelTests/TopologyTests.swift, FakeKernelTests.swift
    CreatorGraphTests/Support/TestNodes.swift     (fixture file: several small node types)
    CreatorGraphTests/Support/TestSupport.swift   (fixture helpers)
    CreatorGraphTests/ValueTests.swift, BroadcastTests.swift, RegistryTests.swift,
                      ConnectionTests.swift, EvaluatorTests.swift, CacheTests.swift,
                      CommandTests.swift, FileTests.swift, DocumentModelTests.swift
```

---

# M0 — OCCT probe

### Task 1: Package skeleton, OCCT shim, box volume

**Files:**
- Delete: `Sources/MetalCreator/MetalCreator.swift`, `Tests/MetalCreatorTests/MetalCreatorTests.swift`
- Rewrite: `Package.swift`
- Create: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct.cpp`, `Sources/CreatorOCCT/OCCTError.swift`, `Sources/CreatorOCCT/OCCTShape.swift`
- Test: `Tests/CreatorOCCTTests/OCCTProbeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (internal to `CreatorOCCT`; M2 builds `OCCTKernel` on it): `final class OCCTShape: Sendable` with `static func box(_ dx: Double, _ dy: Double, _ dz: Double) throws(OCCTError) -> OCCTShape`, `var volume: Double`, `var faceCount: Int`, `var edgeCount: Int`, `func edgeLength(at index: Int) -> Double` (1-based OCCT map index); `struct OCCTError: Error, Equatable { let message: String }`.

- [ ] **Step 1: Install OCCT and confirm the libraries exist**

Run:
```bash
brew install opencascade
ls /opt/homebrew/opt/opencascade/lib/libTKernel.dylib /opt/homebrew/opt/opencascade/lib/libTKDESTEP.dylib /opt/homebrew/opt/opencascade/include/opencascade/BRepPrimAPI_MakeBox.hxx
```
Expected: all three paths are printed and there is no "No such file" error. Version 7.9.x.

- [ ] **Step 2: Remove the placeholder target and write the M0 manifest**

```bash
rm -rf Sources/MetalCreator Tests/MetalCreatorTests
```

`Package.swift`:
```swift
// swift-tools-version: 6.4
import PackageDescription

/// Homebrew's OpenCascade install. The bottle ships CMake configs but no pkg-config file,
/// so the shim is pointed at it directly. Only the COCCT target uses these flags.
let occtPrefix = "/opt/homebrew/opt/opencascade"
let occtLibraries = [
    "TKernel", "TKMath", "TKG2d", "TKG3d", "TKGeomBase", "TKGeomAlgo", "TKBRep", "TKTopAlgo",
    "TKPrim", "TKBO", "TKBool", "TKFillet", "TKOffset", "TKMesh", "TKShHealing",
    "TKXSBase", "TKDE", "TKDESTEP", "TKDESTL",
]

let package = Package(
    name: "MetalCreator",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "COCCT",
            cxxSettings: [.unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"])],
            linkerSettings: [
                .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"]),
            ] + occtLibraries.map { .linkedLibrary($0) }
        ),
        .target(name: "CreatorOCCT", dependencies: ["COCCT"]),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT"]),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .cxx17
)
```

- [ ] **Step 3: Write the failing test**

`Tests/CreatorOCCTTests/OCCTProbeTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorOCCT

/// True when `a` and `b` agree to a relative tolerance (absolute near zero).
func isClose(_ a: Double, _ b: Double, relative: Double = 1e-6) -> Bool {
    abs(a - b) <= relative * max(1, abs(a), abs(b))
}

// STEP writing goes through OCCT's process-global Interface_Static settings, so the
// suite runs serially.
@Suite(.serialized)
struct OCCTProbeTests {
    @Test func boxHasExpectedVolumeAndTopology() throws {
        let box = try OCCTShape.box(10, 20, 30)
        #expect(isClose(box.volume, 6000))
        #expect(box.faceCount == 6)
        #expect(box.edgeCount == 12)
    }

    @Test func degenerateBoxThrowsInsteadOfCrashing() {
        #expect(throws: OCCTError.self) { try OCCTShape.box(0, 20, 30) }
    }
}
```

- [ ] **Step 4: Run the test and confirm it fails**

Run: `swift test --filter CreatorOCCTTests`
Expected: the build fails with "cannot find 'OCCTShape' in scope" (or the `COCCT` target has no sources).

- [ ] **Step 5: Write the C header**

`Sources/COCCT/include/cocct.h`:
```c
#ifndef COCCT_H
#define COCCT_H

#ifdef __cplusplus
extern "C" {
#endif

/// An owned OCCT shape. Free it with occt_shape_free.
typedef struct occt_shape occt_shape;

/// Outcome of a shim call. `ok` is 1 on success; otherwise `message` holds OCCT's reason.
typedef struct {
    int ok;
    char message[512];
} occt_status;

occt_shape *occt_make_box(double dx, double dy, double dz, occt_status *status);
void occt_shape_free(occt_shape *shape);

double occt_volume(const occt_shape *shape);
int occt_face_count(const occt_shape *shape);
int occt_edge_count(const occt_shape *shape);
/// Length of the edge at 1-based `index` in OCCT's indexed edge map, or -1 if out of range.
double occt_edge_length(const occt_shape *shape, int index);

#ifdef __cplusplus
}
#endif

#endif
```

- [ ] **Step 6: Write the C++ implementation**

`Sources/COCCT/cocct.cpp`:
```cpp
#include "cocct.h"

#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <Standard_Failure.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shape.hxx>

#include <cstring>
#include <exception>

struct occt_shape {
    TopoDS_Shape shape;
};

namespace {

void set_ok(occt_status *status) {
    if (status) {
        status->ok = 1;
        status->message[0] = '\0';
    }
}

void set_error(occt_status *status, const char *message) {
    if (status) {
        status->ok = 0;
        std::strncpy(status->message, message ? message : "unknown OCCT error", sizeof(status->message) - 1);
        status->message[sizeof(status->message) - 1] = '\0';
    }
}

/// Runs `body`, converting every C++ exception into an error status. No exception may
/// cross into Swift.
template <typename Body>
auto guarded(occt_status *status, Body body) -> decltype(body()) {
    try {
        set_ok(status);
        return body();
    } catch (const Standard_Failure &failure) {
        const char *message = failure.GetMessageString();
        set_error(status, (message && *message) ? message : failure.DynamicType()->Name());
    } catch (const std::exception &error) {
        set_error(status, error.what());
    } catch (...) {
        set_error(status, "unknown OCCT exception");
    }
    return decltype(body()){};
}

TopTools_IndexedMapOfShape map_of(const TopoDS_Shape &shape, TopAbs_ShapeEnum kind) {
    TopTools_IndexedMapOfShape map;
    TopExp::MapShapes(shape, kind, map);
    return map;
}

} // namespace

extern "C" {

occt_shape *occt_make_box(double dx, double dy, double dz, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!(dx > 0 && dy > 0 && dz > 0)) {
            set_error(status, "box sides must be greater than 0");
            return nullptr;
        }
        BRepPrimAPI_MakeBox maker(dx, dy, dz);
        return new occt_shape{maker.Shape()};
    });
}

void occt_shape_free(occt_shape *shape) { delete shape; }

double occt_volume(const occt_shape *shape) {
    GProp_GProps props;
    BRepGProp::VolumeProperties(shape->shape, props);
    return props.Mass();
}

int occt_face_count(const occt_shape *shape) { return map_of(shape->shape, TopAbs_FACE).Extent(); }

int occt_edge_count(const occt_shape *shape) { return map_of(shape->shape, TopAbs_EDGE).Extent(); }

double occt_edge_length(const occt_shape *shape, int index) {
    TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
    if (index < 1 || index > edges.Extent()) {
        return -1;
    }
    GProp_GProps props;
    BRepGProp::LinearProperties(edges(index), props);
    return props.Mass();
}

} // extern "C"
```

- [ ] **Step 7: Write the Swift wrapper**

`Sources/CreatorOCCT/OCCTError.swift`:
```swift
/// A failure reported by the OCCT shim, carrying OCCT's own message.
struct OCCTError: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}
```

`Sources/CreatorOCCT/OCCTShape.swift`:
```swift
import COCCT
import Foundation

/// Owns one OCCT shape. OCCT shapes are immutable once built, so sharing one across
/// concurrency domains is safe; the pointer is freed exactly once, in `deinit`.
final class OCCTShape: Sendable {
    // `OpaquePointer` is not Sendable. This is sound because the pointer is a `let`, is
    // never mutated through, and points at an immutable TopoDS_Shape.
    nonisolated(unsafe) let raw: OpaquePointer

    init(raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        occt_shape_free(raw)
    }

    static func box(_ dx: Double, _ dy: Double, _ dz: Double) throws(OCCTError) -> OCCTShape {
        try make { status in occt_make_box(dx, dy, dz, status) }
    }

    var volume: Double { occt_volume(raw) }
    var faceCount: Int { Int(occt_face_count(raw)) }
    var edgeCount: Int { Int(occt_edge_count(raw)) }

    /// Length of the edge at 1-based `index`, or -1 when out of range.
    func edgeLength(at index: Int) -> Double {
        occt_edge_length(raw, Int32(index))
    }

    /// Calls a shim constructor and turns a null result or error status into `OCCTError`.
    static func make(_ body: (UnsafeMutablePointer<occt_status>) -> OpaquePointer?) throws(OCCTError) -> OCCTShape {
        var status = occt_status()
        let result = body(&status)
        guard status.ok != 0, let result else {
            throw OCCTError(message: status.messageText)
        }
        return OCCTShape(raw: result)
    }
}

extension occt_status {
    /// The NUL-terminated `message` buffer as a Swift string.
    var messageText: String {
        withUnsafeBytes(of: message) { bytes in
            let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            return text.isEmpty ? "unknown OCCT error" : text
        }
    }
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `swift test --filter CreatorOCCTTests`
Expected: both tests PASS. Linker warnings like "was built for newer macOS version" are acceptable. **If the link fails with undefined symbols**, find the library that exports the symbol with `nm -gU /opt/homebrew/opt/opencascade/lib/libTK*.dylib | grep <symbol>` and add that library to `occtLibraries`.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): link OpenCascade through a C shim and build a box"
```
(Append the attribution trailer from Global Constraints to every commit message.)

### Task 2: Fillet, STEP and STL export

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct.cpp`, `Sources/CreatorOCCT/OCCTShape.swift`
- Test: `Tests/CreatorOCCTTests/OCCTProbeTests.swift`

**Interfaces:**
- Consumes: `OCCTShape`, `OCCTError`, and `OCCTShape.make(_:)` from Task 1.
- Produces: `func filleting(edge index: Int, radius: Double) throws(OCCTError) -> OCCTShape`, `func writeSTEP(to url: URL) throws(OCCTError)`, `func writeSTL(to url: URL, deflection: Double) throws(OCCTError)`.

- [ ] **Step 1: Write the failing tests** (append inside `struct OCCTProbeTests`)

```swift
    /// Index of the first edge whose length is `length`.
    func edgeIndex(of shape: OCCTShape, length: Double) throws -> Int {
        try #require((1...shape.edgeCount).first { isClose(shape.edgeLength(at: $0), length) })
    }

    @Test func filletRemovesTheAnalyticVolume() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let filleted = try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 2)
        // A radius-r fillet along a length-L edge removes r²(1 − π/4)·L. For r = 2 that's (4 − π)·L.
        #expect(isClose(filleted.volume, 6000 - (4 - Double.pi) * 30))
        #expect(filleted.faceCount == 7)
    }

    @Test func oversizedFilletThrowsWithAMessage() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let error = #expect(throws: OCCTError.self) {
            try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 15)
        }
        #expect(error?.message.isEmpty == false)
    }

    @Test func filletOnMissingEdgeThrows() throws {
        let box = try OCCTShape.box(10, 20, 30)
        #expect(throws: OCCTError.self) { try box.filleting(edge: 99, radius: 1) }
    }

    @Test func writesAStepFile() throws {
        let url = URL.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        let box = try OCCTShape.box(10, 20, 30)
        try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 2).writeSTEP(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("ISO-10303-21;"))
        #expect(text.contains("MANIFOLD_SOLID_BREP"))
    }

    @Test func writesAnStlFile() throws {
        let url = URL.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: url) }
        try OCCTShape.box(10, 20, 30).writeSTL(to: url, deflection: 0.1)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("solid"))
        #expect(text.components(separatedBy: "facet normal").count - 1 >= 12)
    }

    @Test func stepToAnUnwritablePathThrows() throws {
        let url = URL(filePath: "/nonexistent-directory/probe.step")
        #expect(throws: OCCTError.self) { try OCCTShape.box(1, 1, 1).writeSTEP(to: url) }
    }
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorOCCTTests`
Expected: compile error, "value of type 'OCCTShape' has no member 'filleting'".

- [ ] **Step 3: Extend the header** (add above the closing `#ifdef __cplusplus`)

```c
/// Fillets the edge at 1-based `edge_index` with `radius`. Returns NULL on failure.
occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status);
/// Writes `shape` as AP214 STEP in millimetres. Returns 1 on success.
int occt_write_step(const occt_shape *shape, const char *path, occt_status *status);
/// Meshes `shape` with `linear_deflection` (mm) and writes ASCII STL. Returns 1 on success.
int occt_write_stl(const occt_shape *shape, const char *path, double linear_deflection, occt_status *status);
```

- [ ] **Step 4: Implement them in `cocct.cpp`**

Add these includes:
```cpp
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Interface_Static.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
```
Then add inside `extern "C"`:
```cpp
occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        if (edge_index < 1 || edge_index > edges.Extent()) {
            set_error(status, "edge index out of range");
            return nullptr;
        }
        BRepFilletAPI_MakeFillet fillet(shape->shape);
        fillet.Add(radius, TopoDS::Edge(edges(edge_index)));
        fillet.Build();
        if (!fillet.IsDone()) {
            set_error(status, "fillet could not be built for this radius");
            return nullptr;
        }
        return new occt_shape{fillet.Shape()};
    });
}

int occt_write_step(const occt_shape *shape, const char *path, occt_status *status) {
    return guarded(status, [&]() -> int {
        STEPControl_Writer writer;
        Interface_Static::SetCVal("write.step.unit", "MM");
        if (writer.Transfer(shape->shape, STEPControl_AsIs) != IFSelect_RetDone) {
            set_error(status, "STEP transfer failed");
            return 0;
        }
        if (writer.Write(path) != IFSelect_RetDone) {
            set_error(status, "STEP file could not be written");
            return 0;
        }
        return 1;
    });
}

int occt_write_stl(const occt_shape *shape, const char *path, double linear_deflection, occt_status *status) {
    return guarded(status, [&]() -> int {
        BRepMesh_IncrementalMesh mesher(shape->shape, linear_deflection);
        StlAPI_Writer writer;
        if (!writer.Write(shape->shape, path)) {
            set_error(status, "STL file could not be written");
            return 0;
        }
        return 1;
    });
}
```

- [ ] **Step 5: Add the Swift methods to `OCCTShape`**

```swift
    func filleting(edge index: Int, radius: Double) throws(OCCTError) -> OCCTShape {
        try Self.make { status in occt_fillet_edge(raw, Int32(index), radius, status) }
    }

    func writeSTEP(to url: URL) throws(OCCTError) {
        try Self.check { status in url.withUnsafeFileSystemRepresentation { occt_write_step(raw, $0, status) } }
    }

    func writeSTL(to url: URL, deflection: Double) throws(OCCTError) {
        try Self.check { status in
            url.withUnsafeFileSystemRepresentation { occt_write_stl(raw, $0, deflection, status) }
        }
    }

    /// Calls a shim function returning 1/0 and turns failure into `OCCTError`.
    static func check(_ body: (UnsafeMutablePointer<occt_status>) -> Int32) throws(OCCTError) {
        var status = occt_status()
        let result = body(&status)
        guard status.ok != 0, result == 1 else {
            throw OCCTError(message: status.messageText)
        }
    }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter CreatorOCCTTests`
Expected: all 8 tests PASS. If `oversizedFilletThrowsWithAMessage` fails because OCCT *succeeds* at radius 15 on a 10 mm wide box, raise the radius to 40. The point of the test is an impossible radius.

- [ ] **Step 7: Human check — open the STEP in FreeCAD or Fusion**

Run: `swift test --filter writesAStepFile` after temporarily replacing its `defer` line with `print(url.path())`, then revert the change. Open the printed file in FreeCAD (`File → Open`) or Fusion and confirm a 10×20×30 box with one rounded 30 mm edge. Record the result in the task report. **Do not commit the temporary change.**

- [ ] **Step 8: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): fillet an edge and export STEP and STL"
```

---

# M1 — Graph engine

### Task 3: `CreatorGeometry` value types

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CreatorGeometry/{Vector2,Vector3,Angle,Plane,Axis,Transform,BoundingBox,Segment2D,Profile2D}.swift`
- Test: `Tests/CreatorGeometryTests/GeometryTests.swift`

**Interfaces:**
- Produces: `Vector2`, `Vector3` (`+ - *`, unary `-`, `dot`, `cross`, `length`, `normalized: Vector3?`, `isFinite`, `.zero/.unitX/.unitY/.unitZ`), `Angle` (`radians`, `.degrees(_:)`, `degrees`), `Plane` (`origin`, `normal`, `xAxis`, `yAxis`, `.xy/.xz/.yz`, `point(_ p: Vector2) -> Vector3`, `offset(by:)`, `.through(_ point: Vector3)`), `Axis` (`origin`, `direction`, `.z`), `Transform` (`translation`, `rotationAxis: Axis?`, `rotation: Angle`, `.identity`), `BoundingBox` (`min`, `max`, `init?(points:)`, `size`, `center`, `union(_:)`, `intersection(_:) -> BoundingBox?`, `translated(by:)`), `Segment2D` (`.line(Vector2, Vector2)`, `.arc(center:radius:start:end:)`, `startPoint`, `endPoint`, `length`, `boundingPoints`), `Profile2D` (`plane`, `segments`, `isClosed`, `bounds: BoundingBox?`, `.rectangle(width:height:plane:)`, `.circle(radius:center:plane:)`). All are `Sendable` and `Hashable`. All except `Profile2D` and `Segment2D` are `Codable`.

- [ ] **Step 1: Extend `Package.swift`**

Replace the `targets:` array with:
```swift
    targets: [
        .target(
            name: "COCCT",
            cxxSettings: [.unsafeFlags(["-isystem", "\(occtPrefix)/include/opencascade"])],
            linkerSettings: [
                .unsafeFlags(["-L\(occtPrefix)/lib", "-Xlinker", "-rpath", "-Xlinker", "\(occtPrefix)/lib"]),
            ] + occtLibraries.map { .linkedLibrary($0) }
        ),
        .target(name: "CreatorOCCT", dependencies: ["COCCT"]),
        .target(name: "CreatorGeometry"),
        .target(name: "CreatorKernel", dependencies: ["CreatorGeometry"]),
        .target(name: "CreatorGraph", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT"]),
        .testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),
        .testTarget(name: "CreatorKernelTests", dependencies: ["CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorGraphTests", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry"]),
    ],
```
Create empty placeholder directories `Sources/CreatorKernel` and `Sources/CreatorGraph`, plus their test directories, each holding one file `Placeholder.swift` containing only `// Replaced in a later task.` SwiftPM refuses a target with no sources. Delete each placeholder in the task that adds that target's first real file.

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorGeometryTests/GeometryTests.swift`:
```swift
import Testing
@testable import CreatorGeometry

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }
func isClose(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

struct VectorTests {
    @Test func crossProductOfAxesIsRightHanded() {
        #expect(Vector3.unitX.cross(.unitY) == .unitZ)
        #expect(Vector3.unitY.cross(.unitZ) == .unitX)
    }

    @Test func zeroVectorHasNoDirection() {
        #expect(Vector3.zero.normalized == nil)
        #expect(Vector3(3, 0, 4).normalized.map { isClose($0.length, 1) } == true)
    }

    @Test func nanIsNotFinite() {
        #expect(Vector3(1, .nan, 0).isFinite == false)
    }
}

struct PlaneTests {
    @Test(arguments: [Plane.xy, .xz, .yz])
    func yAxisCompletesARightHandedFrame(_ plane: Plane) {
        #expect(isClose(plane.xAxis.cross(plane.yAxis), plane.normal))
    }

    @Test func xzPlaneMapsLocalYToWorldZ() {
        #expect(isClose(Plane.xz.point(Vector2(2, 5)), Vector3(2, 0, 5)))
    }

    @Test func offsetMovesAlongNormal() {
        #expect(isClose(Plane.xy.offset(by: 3).origin, Vector3(0, 0, 3)))
    }
}

struct ProfileTests {
    @Test func rectangleIsClosedAndCentred() throws {
        let rect = Profile2D.rectangle(width: 60, height: 40, plane: .xy)
        #expect(rect.segments.count == 4)
        #expect(rect.isClosed)
        let bounds = try #require(rect.bounds)
        #expect(isClose(bounds.min, Vector3(-30, -20, 0)))
        #expect(isClose(bounds.max, Vector3(30, 20, 0)))
    }

    @Test func circleIsClosedWithOneArc() throws {
        let circle = Profile2D.circle(radius: 2.5, center: Vector2(10, 0), plane: .xy)
        #expect(circle.segments.count == 1)
        #expect(circle.isClosed)
        #expect(isClose(circle.segments[0].length, 2 * .pi * 2.5))
        let bounds = try #require(circle.bounds)
        #expect(isClose(bounds.min, Vector3(7.5, -2.5, 0)))
    }

    @Test func openPolylineIsNotClosed() {
        let open = Profile2D(plane: .xy, segments: [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))])
        #expect(open.isClosed == false)
    }
}

struct BoundingBoxTests {
    @Test func emptyPointListHasNoBox() {
        #expect(BoundingBox(points: []) == nil)
    }

    @Test func disjointBoxesHaveNoIntersection() throws {
        let a = try #require(BoundingBox(points: [.zero, Vector3(1, 1, 1)]))
        let b = try #require(BoundingBox(points: [Vector3(2, 2, 2), Vector3(3, 3, 3)]))
        #expect(a.intersection(b) == nil)
        #expect(a.union(b).size == Vector3(3, 3, 3))
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `swift test --filter CreatorGeometryTests`
Expected: compile errors, "cannot find 'Vector3' in scope".

- [ ] **Step 4: Implement the types**

`Sources/CreatorGeometry/Vector2.swift`:
```swift
/// A point or direction in a profile's 2D plane coordinates, in millimetres.
public struct Vector2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(0, 0)

    public static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    public static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }

    public var length: Double { (x * x + y * y).squareRoot() }
    public var isFinite: Bool { x.isFinite && y.isFinite }
}
```

`Sources/CreatorGeometry/Vector3.swift`:
```swift
/// A point or direction in model space, in millimetres.
public struct Vector3: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)
    public static let unitX = Vector3(1, 0, 0)
    public static let unitY = Vector3(0, 1, 0)
    public static let unitZ = Vector3(0, 0, 1)

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (v: Vector3, s: Double) -> Vector3 { Vector3(v.x * s, v.y * s, v.z * s) }
    public static prefix func - (v: Vector3) -> Vector3 { Vector3(-v.x, -v.y, -v.z) }

    public func dot(_ other: Vector3) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: Vector3) -> Vector3 {
        Vector3(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x)
    }

    public var length: Double { dot(self).squareRoot() }

    /// The unit vector in the same direction, or `nil` for a (near) zero-length vector.
    public var normalized: Vector3? {
        let length = length
        return length > 1e-12 ? self * (1 / length) : nil
    }

    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
```

`Sources/CreatorGeometry/Angle.swift`:
```swift
/// An angle stored in radians.
public struct Angle: Hashable, Sendable, Codable, Comparable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }

    public static func degrees(_ degrees: Double) -> Angle { Angle(radians: degrees * .pi / 180) }

    public var degrees: Double { radians * 180 / .pi }

    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}
```

`Sources/CreatorGeometry/Plane.swift`:
```swift
/// An oriented plane: an origin, a unit normal, and a unit in-plane x axis.
/// The in-plane y axis is `normal × xAxis`, so (xAxis, yAxis, normal) is right-handed.
public struct Plane: Hashable, Sendable, Codable {
    public var origin: Vector3
    public var normal: Vector3
    public var xAxis: Vector3

    public init(origin: Vector3, normal: Vector3, xAxis: Vector3) {
        self.origin = origin
        self.normal = normal
        self.xAxis = xAxis
    }

    public var yAxis: Vector3 { normal.cross(xAxis) }

    /// The ground plane. Local (x, y) → world (x, y).
    public static let xy = Plane(origin: .zero, normal: .unitZ, xAxis: .unitX)
    /// The front plane. Local (x, y) → world (x, z).
    public static let xz = Plane(origin: .zero, normal: -.unitY, xAxis: .unitX)
    /// The side plane. Local (x, y) → world (y, z).
    public static let yz = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)

    /// An XY-oriented plane through `point`, used when a vector is wired into a plane socket.
    public static func through(_ point: Vector3) -> Plane {
        Plane(origin: point, normal: .unitZ, xAxis: .unitX)
    }

    /// The world position of local plane coordinates `p`.
    public func point(_ p: Vector2) -> Vector3 { origin + xAxis * p.x + yAxis * p.y }

    /// This plane moved `distance` along its normal.
    public func offset(by distance: Double) -> Plane {
        Plane(origin: origin + normal * distance, normal: normal, xAxis: xAxis)
    }
}
```

`Sources/CreatorGeometry/Axis.swift`:
```swift
/// An infinite line used for revolves and rotations.
public struct Axis: Hashable, Sendable, Codable {
    public var origin: Vector3
    public var direction: Vector3

    public init(origin: Vector3, direction: Vector3) {
        self.origin = origin
        self.direction = direction
    }

    public static let z = Axis(origin: .zero, direction: .unitZ)
}
```

`Sources/CreatorGeometry/Transform.swift`:
```swift
/// A rigid move: rotate about `rotationAxis` by `rotation`, then translate.
public struct Transform: Hashable, Sendable, Codable {
    public var translation: Vector3
    public var rotationAxis: Axis?
    public var rotation: Angle

    public init(translation: Vector3 = .zero, rotationAxis: Axis? = nil, rotation: Angle = Angle(radians: 0)) {
        self.translation = translation
        self.rotationAxis = rotationAxis
        self.rotation = rotation
    }

    public static let identity = Transform()
}
```

`Sources/CreatorGeometry/BoundingBox.swift`:
```swift
/// An axis-aligned box in model space.
public struct BoundingBox: Hashable, Sendable, Codable {
    public var min: Vector3
    public var max: Vector3

    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }

    /// The smallest box containing `points`, or `nil` when there are none.
    public init?(points: [Vector3]) {
        guard let first = points.first else { return nil }
        var low = first
        var high = first
        for p in points.dropFirst() {
            low = Vector3(Swift.min(low.x, p.x), Swift.min(low.y, p.y), Swift.min(low.z, p.z))
            high = Vector3(Swift.max(high.x, p.x), Swift.max(high.y, p.y), Swift.max(high.z, p.z))
        }
        self.init(min: low, max: high)
    }

    public var size: Vector3 { max - min }
    public var center: Vector3 { (min + max) * 0.5 }

    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            min: Vector3(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y), Swift.min(min.z, other.min.z)),
            max: Vector3(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y), Swift.max(max.z, other.max.z))
        )
    }

    /// The overlap of two boxes, or `nil` if they don't overlap with positive volume.
    public func intersection(_ other: BoundingBox) -> BoundingBox? {
        let low = Vector3(Swift.max(min.x, other.min.x), Swift.max(min.y, other.min.y), Swift.max(min.z, other.min.z))
        let high = Vector3(Swift.min(max.x, other.max.x), Swift.min(max.y, other.max.y), Swift.min(max.z, other.max.z))
        guard low.x < high.x, low.y < high.y, low.z < high.z else { return nil }
        return BoundingBox(min: low, max: high)
    }

    public func translated(by offset: Vector3) -> BoundingBox {
        BoundingBox(min: min + offset, max: max + offset)
    }
}
```

`Sources/CreatorGeometry/Segment2D.swift`:
```swift
import Foundation

/// One piece of a profile loop, in plane coordinates.
public enum Segment2D: Hashable, Sendable {
    case line(Vector2, Vector2)
    /// A counter-clockwise arc from `start` to `end`. `end - start` of 2π is a full circle.
    case arc(center: Vector2, radius: Double, start: Angle, end: Angle)

    public var startPoint: Vector2 {
        switch self {
        case .line(let a, _): a
        case .arc(let c, let r, let start, _): c + Vector2(cos(start.radians), sin(start.radians)) * r
        }
    }

    public var endPoint: Vector2 {
        switch self {
        case .line(_, let b): b
        case .arc(let c, let r, _, let end): c + Vector2(cos(end.radians), sin(end.radians)) * r
        }
    }

    public var length: Double {
        switch self {
        case .line(let a, let b): (b - a).length
        case .arc(_, let r, let start, let end): r * (end.radians - start.radians)
        }
    }

    /// Points whose bounding box contains the segment (conservative for arcs).
    public var boundingPoints: [Vector2] {
        switch self {
        case .line(let a, let b): [a, b]
        case .arc(let c, let r, _, _): [c + Vector2(-r, -r), c + Vector2(r, r)]
        }
    }
}
```

`Sources/CreatorGeometry/Profile2D.swift`:
```swift
/// A single closed loop of segments lying on `plane`.
public struct Profile2D: Hashable, Sendable {
    public var plane: Plane
    public var segments: [Segment2D]

    public init(plane: Plane, segments: [Segment2D]) {
        self.plane = plane
        self.segments = segments
    }

    /// True when every segment ends where the next begins and the last returns to the first.
    public var isClosed: Bool {
        guard let first = segments.first, let last = segments.last else { return false }
        for (a, b) in zip(segments, segments.dropFirst()) where (a.endPoint - b.startPoint).length > 1e-9 {
            return false
        }
        return (last.endPoint - first.startPoint).length <= 1e-9
    }

    /// World-space bounds of the loop, or `nil` for an empty profile.
    public var bounds: BoundingBox? {
        BoundingBox(points: segments.flatMap(\.boundingPoints).map(plane.point))
    }

    /// A `width` × `height` rectangle centred on the plane origin, counter-clockwise from bottom-left.
    public static func rectangle(width: Double, height: Double, plane: Plane) -> Profile2D {
        let (w, h) = (width / 2, height / 2)
        let corners = [Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)]
        let segments = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % 4]) }
        return Profile2D(plane: plane, segments: segments)
    }

    public static func circle(radius: Double, center: Vector2, plane: Plane) -> Profile2D {
        Profile2D(plane: plane, segments: [.arc(center: center, radius: radius, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))])
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter CreatorGeometryTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/CreatorGeometry Sources/CreatorKernel Sources/CreatorGraph Tests/CreatorGeometryTests Tests/CreatorKernelTests Tests/CreatorGraphTests
git commit -m "feat(geometry): add vector, plane, bounds and profile value types"
```

### Task 4: `CreatorKernel` — topology, tags, `Solid`, `Kernel` protocol

**Files:**
- Delete: `Sources/CreatorKernel/Placeholder.swift`, `Tests/CreatorKernelTests/Placeholder.swift`
- Create: `Sources/CreatorKernel/{NodeID,NodeTag,TopoRole,TopoTag,EdgeKey,FaceID,EdgeID,SurfaceKind,CurveKind,Convexity,FaceInfo,EdgeInfo,Topology,SolidStorage,Solid,EdgeSet,FaceSet,DisplayMesh,BooleanOp,ExtrudeMode,ExportFormat,KernelError,Kernel}.swift`
- Test: `Tests/CreatorKernelTests/TopologyTests.swift`

**Interfaces:**
- Consumes: `CreatorGeometry` (Task 3).
- Produces:
  - `NodeID` (`rawValue: UUID`, `init()`, `Comparable`, `Codable`) and `NodeTag(node: NodeID, item: Int)`
  - `TopoRole` (`.startCap`, `.endCap`, `.side(segment:)`, `.blend(sourceEdge: EdgeKey)`, `sortKey`) and `TopoTag(node:item:role:)`, `init(_ tag: NodeTag, _ role: TopoRole)`, `sortKey`
  - `EdgeKey(_ a: Set<TopoTag>, _ b: Set<TopoTag>)`, an unordered pair
  - `FaceID(Int)`, `EdgeID(Int)`, `SurfaceKind`, `CurveKind`, `Convexity`
  - `FaceInfo`, `EdgeInfo` (with `isSeam`), `Topology` (`faces`, `edges`, `face(_:)`, `edge(_:)`, `key(of:)`)
  - `protocol SolidStorage: AnyObject, Sendable { var estimatedBytes: Int }` and `final class Solid: Sendable` (`topology`, `bounds`, `storage`, `estimatedBytes`)
  - `EdgeSet(solid:edges:)`, `FaceSet(solid:faces:)`, `DisplayMesh`
  - `BooleanOp`, `ExtrudeMode`, `ExportFormat`
  - `KernelError` with `userMessage`
  - `protocol Kernel: Actor` with the methods below

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorKernelTests/TopologyTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct TopologyTests {
    let node = NodeID()

    @Test func edgeKeyIsUnordered() {
        let top: Set = [TopoTag(node: node, item: 0, role: .endCap)]
        let side: Set = [TopoTag(node: node, item: 0, role: .side(segment: 2))]
        #expect(EdgeKey(top, side) == EdgeKey(side, top))
        #expect(EdgeKey(top, side).hashValue == EdgeKey(side, top).hashValue)
    }

    @Test func broadcastItemsGiveDistinctTags() {
        let a = TopoTag(node: node, item: 0, role: .endCap)
        let b = TopoTag(node: node, item: 1, role: .endCap)
        #expect(a != b)
    }

    @Test func blendRolesNestEdgeKeys() {
        let key = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .side(segment: 0))])
        let blend = TopoTag(node: NodeID(), item: 0, role: .blend(sourceEdge: key))
        #expect(blend.sortKey.contains("blend("))
    }

    @Test func seamEdgeHasTheSameFaceOnBothSides() {
        let seam = EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitZ, length: 6, midpoint: .zero,
                            convexity: .smooth, faces: [FaceID(2), FaceID(2)])
        #expect(seam.isSeam)
    }

    @Test func topologyKeyUsesAdjacentFaceTags() throws {
        let top = TopoTag(node: node, item: 0, role: .endCap)
        let side = TopoTag(node: node, item: 0, role: .side(segment: 0))
        let topology = Topology(
            faces: [
                FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
                FaceInfo(id: FaceID(1), kind: .plane, normal: .unitX, area: 1, centroid: .zero, tags: [side]),
            ],
            edges: [EdgeInfo(id: EdgeID(0), kind: .line, direction: .unitY, length: 1, midpoint: .zero,
                             convexity: .convex, faces: [FaceID(0), FaceID(1)])]
        )
        let edge = try #require(topology.edge(EdgeID(0)))
        #expect(topology.key(of: edge) == EdgeKey([top], [side]))
    }

    @Test func plainLanguageFilletMessageIncludesTheLimit() {
        let error = KernelError.filletFailed(radius: 8, maxRadius: 5.9, reason: "too large")
        #expect(error.userMessage.contains("8"))
        #expect(error.userMessage.contains("5.9"))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CreatorKernelTests`
Expected: compile errors, "cannot find 'NodeID' in scope".

- [ ] **Step 3: Implement the identity and tag types**

`Sources/CreatorKernel/NodeID.swift`:
```swift
import Foundation

/// Stable identity of a graph node. It lives in the kernel module because topology tags
/// name the node that created each face.
public struct NodeID: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
```

`Sources/CreatorKernel/NodeTag.swift`:
```swift
/// Which node, and which broadcast item of it, is calling the kernel.
public struct NodeTag: Hashable, Sendable, Codable {
    public var node: NodeID
    public var item: Int

    public init(node: NodeID, item: Int) {
        self.node = node
        self.item = item
    }
}
```

`Sources/CreatorKernel/TopoRole.swift`:
```swift
/// The stable role a face plays in the operation that created it (spec §5.3).
public indirect enum TopoRole: Hashable, Sendable {
    case startCap
    case endCap
    /// The side face swept from profile segment `segment`.
    case side(segment: Int)
    /// The blend face a fillet or chamfer made from the edge `sourceEdge`.
    case blend(sourceEdge: EdgeKey)

    /// A deterministic text form, used to order tags canonically.
    public var sortKey: String {
        switch self {
        case .startCap: "startCap"
        case .endCap: "endCap"
        case .side(let segment): "side(\(segment))"
        case .blend(let edge): "blend(\(edge.sortKey))"
        }
    }
}
```

`Sources/CreatorKernel/TopoTag.swift`:
```swift
/// A face's name: the node that made it, the broadcast item, and its role.
public struct TopoTag: Hashable, Sendable {
    public var node: NodeID
    public var item: Int
    public var role: TopoRole

    public init(node: NodeID, item: Int, role: TopoRole) {
        self.node = node
        self.item = item
        self.role = role
    }

    public init(_ tag: NodeTag, _ role: TopoRole) {
        self.init(node: tag.node, item: tag.item, role: role)
    }

    public var sortKey: String { "\(node.rawValue.uuidString)#\(item).\(role.sortKey)" }
}
```

`Sources/CreatorKernel/EdgeKey.swift`:
```swift
/// An edge's name: the tag sets of its two adjacent faces, as an unordered pair.
public struct EdgeKey: Hashable, Sendable {
    public let first: Set<TopoTag>
    public let second: Set<TopoTag>

    public init(_ a: Set<TopoTag>, _ b: Set<TopoTag>) {
        if Self.canonical(a) <= Self.canonical(b) {
            (first, second) = (a, b)
        } else {
            (first, second) = (b, a)
        }
    }

    public var sortKey: String { "\(Self.canonical(first))|\(Self.canonical(second))" }

    private static func canonical(_ tags: Set<TopoTag>) -> String {
        tags.map(\.sortKey).sorted().joined(separator: "+")
    }
}
```

- [ ] **Step 4: Implement the topology table types**

`Sources/CreatorKernel/FaceID.swift`:
```swift
/// Index of a face within one solid's topology table.
public struct FaceID: Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}
```

`Sources/CreatorKernel/EdgeID.swift`:
```swift
/// Index of an edge within one solid's topology table.
public struct EdgeID: Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}
```

`Sources/CreatorKernel/SurfaceKind.swift`:
```swift
public enum SurfaceKind: String, Sendable, Codable {
    case plane, cylinder, cone, sphere, torus, bspline, other
}
```

`Sources/CreatorKernel/CurveKind.swift`:
```swift
public enum CurveKind: String, Sendable, Codable {
    case line, circle, ellipse, bspline, other
}
```

`Sources/CreatorKernel/Convexity.swift`:
```swift
/// Whether the material angle across an edge is under 180° (convex), over (concave), or flat (smooth).
public enum Convexity: String, Sendable, Codable {
    case convex, concave, smooth, unknown
}
```

`Sources/CreatorKernel/FaceInfo.swift`:
```swift
import CreatorGeometry

public struct FaceInfo: Hashable, Sendable {
    public var id: FaceID
    public var kind: SurfaceKind
    /// The normal of a planar face, or the axis direction of a cylinder or cone.
    public var normal: Vector3?
    public var area: Double
    public var centroid: Vector3
    public var tags: Set<TopoTag>

    public init(id: FaceID, kind: SurfaceKind, normal: Vector3?, area: Double, centroid: Vector3, tags: Set<TopoTag>) {
        self.id = id
        self.kind = kind
        self.normal = normal
        self.area = area
        self.centroid = centroid
        self.tags = tags
    }
}
```

`Sources/CreatorKernel/EdgeInfo.swift`:
```swift
import CreatorGeometry

public struct EdgeInfo: Hashable, Sendable {
    public var id: EdgeID
    public var kind: CurveKind
    /// The direction of a straight edge, or the axis of a circular one.
    public var direction: Vector3?
    public var length: Double
    public var midpoint: Vector3
    public var convexity: Convexity
    /// The two adjacent faces. A seam edge lists the same face twice.
    public var faces: [FaceID]

    public init(id: EdgeID, kind: CurveKind, direction: Vector3?, length: Double, midpoint: Vector3,
                convexity: Convexity, faces: [FaceID]) {
        self.id = id
        self.kind = kind
        self.direction = direction
        self.length = length
        self.midpoint = midpoint
        self.convexity = convexity
        self.faces = faces
    }

    /// A seam (such as the one OCCT puts on every cylindrical wall) borders one face on
    /// both sides. Selection rules exclude seams (spec §5.1).
    public var isSeam: Bool { faces.count == 2 && faces[0] == faces[1] }
}
```

`Sources/CreatorKernel/Topology.swift`:
```swift
/// The Swift-side description of a solid's faces and edges, used by selection rules.
public struct Topology: Hashable, Sendable {
    public var faces: [FaceInfo]
    public var edges: [EdgeInfo]

    public init(faces: [FaceInfo], edges: [EdgeInfo]) {
        self.faces = faces
        self.edges = edges
    }

    public func face(_ id: FaceID) -> FaceInfo? { faces.first { $0.id == id } }
    public func edge(_ id: EdgeID) -> EdgeInfo? { edges.first { $0.id == id } }

    /// The edge's stable name, or `nil` if an adjacent face is missing from the table.
    public func key(of edge: EdgeInfo) -> EdgeKey? {
        guard edge.faces.count == 2, let a = face(edge.faces[0]), let b = face(edge.faces[1]) else { return nil }
        return EdgeKey(a.tags, b.tags)
    }
}
```

- [ ] **Step 5: Implement `Solid`, sets, meshes, enums, errors and the protocol**

`Sources/CreatorKernel/SolidStorage.swift`:
```swift
/// The kernel-private payload behind a `Solid` (an OCCT shape handle, or fake data).
public protocol SolidStorage: AnyObject, Sendable {
    /// A rough memory cost, used by the evaluator's cache budget.
    var estimatedBytes: Int { get }
}
```

`Sources/CreatorKernel/Solid.swift`:
```swift
import CreatorGeometry

/// An immutable solid produced by a kernel. Cheap to share: cached node outputs hold
/// references, never copies.
public final class Solid: Sendable {
    public let topology: Topology
    public let bounds: BoundingBox
    public let storage: any SolidStorage

    public init(topology: Topology, bounds: BoundingBox, storage: any SolidStorage) {
        self.topology = topology
        self.bounds = bounds
        self.storage = storage
    }

    public var estimatedBytes: Int {
        storage.estimatedBytes + (topology.faces.count + topology.edges.count) * 128
    }
}
```

`Sources/CreatorKernel/EdgeSet.swift`:
```swift
/// A selection of edges on one solid, produced by selection-rule nodes.
public struct EdgeSet: Sendable {
    public var solid: Solid
    public var edges: [EdgeID]

    public init(solid: Solid, edges: [EdgeID]) {
        self.solid = solid
        self.edges = edges
    }
}
```

`Sources/CreatorKernel/FaceSet.swift`:
```swift
/// A selection of faces on one solid.
public struct FaceSet: Sendable {
    public var solid: Solid
    public var faces: [FaceID]

    public init(solid: Solid, faces: [FaceID]) {
        self.solid = solid
        self.faces = faces
    }
}
```

`Sources/CreatorKernel/DisplayMesh.swift`:
```swift
import CreatorGeometry

/// Triangles for display and picking, plus the B-rep edges as polylines.
public struct DisplayMesh: Sendable {
    public var positions: [Vector3]
    public var normals: [Vector3]
    public var indices: [UInt32]
    /// The face each triangle belongs to (`indices.count / 3` entries).
    public var triangleFaces: [FaceID]
    public var edgePolylines: [EdgeID: [Vector3]]

    public init(positions: [Vector3], normals: [Vector3], indices: [UInt32], triangleFaces: [FaceID], edgePolylines: [EdgeID: [Vector3]]) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.triangleFaces = triangleFaces
        self.edgePolylines = edgePolylines
    }
}
```

`Sources/CreatorKernel/BooleanOp.swift`:
```swift
public enum BooleanOp: String, Sendable, Codable, CaseIterable {
    case union, subtract, intersect
}
```

`Sources/CreatorKernel/ExtrudeMode.swift`:
```swift
public enum ExtrudeMode: String, Sendable, Codable, CaseIterable {
    /// From the profile plane along its normal.
    case oneSided
    /// Half the distance on each side of the profile plane.
    case symmetric
}
```

`Sources/CreatorKernel/ExportFormat.swift`:
```swift
public enum ExportFormat: String, Sendable, Codable, CaseIterable {
    case step, stl
}
```

`Sources/CreatorKernel/KernelError.swift`:
```swift
import Foundation

/// A kernel failure, with a message written for the person editing the graph.
public enum KernelError: Error, Equatable, Sendable {
    case invalidInput(String)
    case operationFailed(operation: String, reason: String)
    case filletFailed(radius: Double, maxRadius: Double?, reason: String)
    case unsupported(String)
    case exportFailed(String)

    public var userMessage: String {
        switch self {
        case .invalidInput(let message):
            message
        case .operationFailed(let operation, let reason):
            "\(operation.capitalized) failed: \(reason)"
        case .filletFailed(let radius, let maxRadius?, _):
            "Radius \(radius.formatted()) mm is too large for the selected edges (max ≈ \(maxRadius.formatted()) mm)."
        case .filletFailed(let radius, nil, let reason):
            "Radius \(radius.formatted()) mm could not be applied: \(reason)"
        case .unsupported(let operation):
            "\(operation.capitalized) isn't supported by this kernel yet."
        case .exportFailed(let reason):
            "Export failed: \(reason)"
        }
    }
}
```

`Sources/CreatorKernel/Kernel.swift`:
```swift
import CreatorGeometry
import Foundation

/// The geometry kernel boundary. Everything above this protocol is pure Swift. OCCT, and
/// any future Swift kernel, live behind it (spec §5.1). Calls are serialized by the actor.
public protocol Kernel: Actor {
    func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid
    func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid
    func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid
    func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid
    func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid
    func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid
    func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid
    func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh
    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws
}
```

Delete both `Placeholder.swift` files in `CreatorKernel`.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter CreatorKernelTests`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests
git commit -m "feat(kernel): add Kernel protocol, Solid and tagged topology tables"
```

### Task 5: `FakeKernel`

**Files:**
- Create: `Sources/CreatorKernel/FakeStorage.swift`, `Sources/CreatorKernel/FakeKernel.swift`
- Test: `Tests/CreatorKernelTests/FakeKernelTests.swift`

**Interfaces:**
- Consumes: everything from Task 4.
- Produces: `public actor FakeKernel: Kernel` with `init()`, `operationLog: [String]` (one entry per call, using the method name), and `clearLog()`. It is **not geometrically correct**: solids are tagged boxes. Extrude makes one `startCap`, one `endCap` and one `side(k)` per profile segment; a single-segment profile (a circle) gets a seam edge. Fillet and chamfer add one `.blend` face per edge and throw `filletFailed(maxRadius: minimumBoxSide / 2)` when `radius * 2 >= minimumBoxSide`. Revolve and loft throw `.unsupported`. Export throws `.unsupported`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorKernelTests/FakeKernelTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func extrudedRectangleHasCapsAndFourSides() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        #expect(solid.topology.faces.count == 6)
        #expect(solid.topology.edges.count == 12)
        #expect(solid.bounds.size == Vector3(60, 40, 6))
        let roles = Set(solid.topology.faces.flatMap(\.tags).map(\.role))
        #expect(roles.contains(.endCap) && roles.contains(.side(segment: 3)))
        #expect(await kernel.operationLog == ["extrude"])
    }

    @Test func symmetricExtrudeStraddlesThePlane() async throws {
        let solid = try await FakeKernel().extrude(.rectangle(width: 2, height: 2, plane: .xy), distance: 6, mode: .symmetric, tag: tag)
        #expect(solid.bounds.min.z == -3)
        #expect(solid.bounds.max.z == 3)
    }

    @Test func extrudedCircleHasASeam() async throws {
        let solid = try await FakeKernel().extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        #expect(solid.topology.edges.contains(where: \.isSeam))
    }

    @Test(arguments: [0.0, -1.0, .nan, .infinity])
    func nonPositiveOrNonFiniteDistanceIsRejected(_ distance: Double) async {
        await #expect(throws: KernelError.self) {
            try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: distance, mode: .oneSided, tag: tag)
        }
    }

    @Test func filletAddsABlendFacePerEdge() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let vertical = box.topology.edges.filter { $0.direction == .unitZ }.map(\.id)
        let filleted = try await kernel.fillet(box, edges: vertical, radius: 2, tag: NodeTag(node: NodeID(), item: 0))
        #expect(filleted.topology.faces.count == 6 + vertical.count)
    }

    @Test func oversizedFilletReportsTheLimit() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(box, edges: [EdgeID(0)], radius: 4, tag: tag)
        }
        #expect(error == .filletFailed(radius: 4, maxRadius: 3, reason: "radius too large for the part"))
    }

    @Test func filletWithNoEdgesIsRejected() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 6, height: 6, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        await #expect(throws: KernelError.invalidInput("No edges are selected.")) {
            try await kernel.fillet(box, edges: [], radius: 1, tag: tag)
        }
    }

    @Test func subtractKeepsToolFacesForTagging() async throws {
        let kernel = FakeKernel()
        let plate = try await kernel.extrude(.rectangle(width: 60, height: 40, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        let hole = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 6, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let result = try await kernel.boolean(.subtract, plate, [hole], tag: tag)
        #expect(result.bounds == plate.bounds)
        #expect(result.topology.faces.count == plate.topology.faces.count + hole.topology.faces.count)
        #expect(Set(result.topology.faces.map(\.id)).count == result.topology.faces.count)
    }

    @Test func revolveIsUnsupported() async {
        await #expect(throws: KernelError.unsupported("revolve")) {
            try await FakeKernel().revolve(.rectangle(width: 1, height: 1, plane: .xz), axis: .z, angle: .degrees(360), tag: tag)
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter FakeKernelTests`
Expected: compile error, "cannot find 'FakeKernel' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorKernel/FakeStorage.swift`:
```swift
/// Storage for `FakeKernel` solids, which carry no real geometry.
final class FakeStorage: SolidStorage {
    var estimatedBytes: Int { 64 }
}
```

`Sources/CreatorKernel/FakeKernel.swift`:
```swift
import CreatorGeometry
import Foundation

/// A pure-Swift kernel for tests. Solids are tagged bounding boxes. Topology and tags
/// follow the real naming scheme, but the geometry is NOT correct. Never run the
/// kernel conformance suite against it (spec §5.4).
public actor FakeKernel: Kernel {
    public private(set) var operationLog: [String] = []

    public init() {}

    public func clearLog() {
        operationLog.removeAll()
    }

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        operationLog.append("extrude")
        guard distance.isFinite, distance > 0 else {
            throw KernelError.invalidInput("Extrude distance must be greater than 0 mm.")
        }
        guard profile.isClosed, let flat = profile.bounds else {
            throw KernelError.invalidInput("The profile is not a closed loop.")
        }
        let normal = profile.plane.normal
        let (back, front) = mode == .symmetric ? (-distance / 2, distance / 2) : (0, distance)
        let corners = [flat.min, flat.max].flatMap { [$0 + normal * back, $0 + normal * front] }
        guard let bounds = BoundingBox(points: corners) else {
            throw KernelError.invalidInput("The profile is empty.")
        }
        return Solid(topology: Self.prism(profile, distance: distance, tag: tag), bounds: bounds, storage: FakeStorage())
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        operationLog.append("revolve")
        throw KernelError.unsupported("revolve")
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        operationLog.append("loft")
        throw KernelError.unsupported("loft")
    }

    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        operationLog.append("boolean")
        var bounds = a.bounds
        switch op {
        case .union:
            bounds = b.reduce(a.bounds) { $0.union($1.bounds) }
        case .subtract:
            break
        case .intersect:
            for other in b {
                guard let overlap = bounds.intersection(other.bounds) else {
                    throw KernelError.operationFailed(operation: "intersect", reason: "the solids don't overlap, so the result is empty.")
                }
                bounds = overlap
            }
        }
        let topology = op == .intersect ? a.topology : b.reduce(a.topology) { Self.appending($1.topology, to: $0) }
        return Solid(topology: topology, bounds: bounds, storage: FakeStorage())
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        operationLog.append("transform")
        return Solid(topology: solid.topology, bounds: solid.bounds.translated(by: transform.translation), storage: FakeStorage())
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        operationLog.append("fillet")
        return try blend(solid, edges: edges, size: radius, tag: tag)
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        operationLog.append("chamfer")
        return try blend(solid, edges: edges, size: distance, tag: tag)
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        operationLog.append("tessellate")
        let (lo, hi) = (solid.bounds.min, solid.bounds.max)
        let positions = (0..<8).map { i in
            Vector3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)
        }
        let center = solid.bounds.center
        let indices: [UInt32] = [0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4,
                                 2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5]
        return DisplayMesh(
            positions: positions,
            normals: positions.map { ($0 - center).normalized ?? .unitZ },
            indices: indices,
            triangleFaces: Array(repeating: FaceID(0), count: indices.count / 3),
            edgePolylines: [:]
        )
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        operationLog.append("export")
        throw KernelError.unsupported("export")
    }

    // MARK: - Fake construction

    private func blend(_ solid: Solid, edges: [EdgeID], size: Double, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else {
            throw KernelError.invalidInput("The size must be greater than 0 mm.")
        }
        guard !edges.isEmpty else {
            throw KernelError.invalidInput("No edges are selected.")
        }
        let side = solid.bounds.size
        let limit = min(side.x, side.y, side.z)
        guard size * 2 < limit else {
            throw KernelError.filletFailed(radius: size, maxRadius: limit / 2, reason: "radius too large for the part")
        }
        var topology = solid.topology
        for id in edges {
            guard let edge = topology.edge(id), let key = topology.key(of: edge) else {
                throw KernelError.operationFailed(operation: "fillet", reason: "edge \(id.rawValue) doesn't exist on the input solid.")
            }
            let face = FaceID(topology.faces.count)
            topology.faces.append(FaceInfo(id: face, kind: .cylinder, normal: edge.direction, area: 0,
                                           centroid: edge.midpoint, tags: [TopoTag(tag, .blend(sourceEdge: key))]))
        }
        return Solid(topology: topology, bounds: solid.bounds, storage: FakeStorage())
    }

    /// Caps, one side per segment, and bottom, top and between-side edges. A single-segment
    /// loop (a circle) gets a seam instead of between-side edges.
    private static func prism(_ profile: Profile2D, distance: Double, tag: NodeTag) -> Topology {
        let normal = profile.plane.normal
        let count = profile.segments.count
        var faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .startCap)]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .endCap)]),
        ]
        var edges: [EdgeInfo] = []
        func addEdge(_ kind: CurveKind, _ direction: Vector3?, _ length: Double, _ convexity: Convexity, _ a: Int, _ b: Int) {
            edges.append(EdgeInfo(id: EdgeID(edges.count), kind: kind, direction: direction, length: length,
                                  midpoint: .zero, convexity: convexity, faces: [FaceID(a), FaceID(b)]))
        }
        for (k, segment) in profile.segments.enumerated() {
            let side = 2 + k
            let isLine: Bool
            if case .line = segment { isLine = true } else { isLine = false }
            faces.append(FaceInfo(id: FaceID(side), kind: isLine ? .plane : .cylinder, normal: nil, area: 0,
                                  centroid: .zero, tags: [TopoTag(tag, .side(segment: k))]))
            let along: Vector3? = isLine ? (profile.plane.point(segment.endPoint) - profile.plane.point(segment.startPoint)).normalized : normal
            addEdge(isLine ? .line : .circle, along, segment.length, .convex, 0, side)
            addEdge(isLine ? .line : .circle, along, segment.length, .convex, 1, side)
        }
        if count == 1 {
            addEdge(.line, normal, distance, .smooth, 2, 2)
        } else {
            for k in 0..<count {
                addEdge(.line, normal, distance, .convex, 2 + k, 2 + (k + 1) % count)
            }
        }
        return Topology(faces: faces, edges: edges)
    }

    /// `other`'s faces and edges, renumbered after `base`'s, appended to `base`.
    private static func appending(_ other: Topology, to base: Topology) -> Topology {
        let faceOffset = base.faces.count
        let edgeOffset = base.edges.count
        var result = base
        for var face in other.faces {
            face.id = FaceID(face.id.rawValue + faceOffset)
            result.faces.append(face)
        }
        for var edge in other.edges {
            edge.id = EdgeID(edge.id.rawValue + edgeOffset)
            edge.faces = edge.faces.map { FaceID($0.rawValue + faceOffset) }
            result.edges.append(edge)
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorKernelTests`
Expected: all PASS. In `extrudedRectangleHasCapsAndFourSides` the 12 edges are 4 bottom + 4 top + 4 vertical.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests
git commit -m "feat(kernel): add FakeKernel with tagged box topology for tests"
```

### Task 6: Socket types and runtime values

**Files:**
- Delete: `Sources/CreatorGraph/Placeholder.swift`, `Tests/CreatorGraphTests/Placeholder.swift`
- Create: `Sources/CreatorGraph/{SocketName,ParameterID,SocketType,ConstantValue,Scalar,Value}.swift`
- Test: `Tests/CreatorGraphTests/ValueTests.swift`

**Interfaces:**
- Consumes: `CreatorGeometry`, `CreatorKernel` (`Solid`, `EdgeSet`, `FaceSet`).
- Produces:
  - `SocketName` (`ExpressibleByStringLiteral`, `CodingKeyRepresentable`, `rawValue`) and `ParameterID` (`rawValue: UUID`)
  - `SocketType` (cases `number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet`; `accepts(_ source: SocketType) -> Bool`)
  - `ConstantValue` (`number, integer, bool, vector, plane, text`; custom JSON `{"type": …, "value": …}`; `isFinite`)
  - `Scalar` (runtime: the constant cases plus `profile, solid, edgeSet, faceSet`; `type: SocketType`; `init?(_ constant: ConstantValue)`; `converted(to:) -> Scalar?`; `estimatedBytes`)
  - `Value` (`.one(Scalar)`, `.list([Scalar])`; `items`; `converted(to:) -> Value?`; `estimatedBytes`)

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/ValueTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct ValueTests {
    @Test func integerWidensToNumberButNotTheReverse() {
        #expect(SocketType.number.accepts(.integer))
        #expect(!SocketType.integer.accepts(.number))
        #expect(SocketType.plane.accepts(.vector))
        #expect(!SocketType.solid.accepts(.profile))
    }

    @Test func convertsIntegerScalarToNumber() throws {
        let converted = try #require(Scalar.integer(4).converted(to: .number))
        guard case .number(let value) = converted else { Issue.record("expected number"); return }
        #expect(value == 4)
    }

    @Test func vectorConvertsToPlaneThroughThatPoint() throws {
        let converted = try #require(Scalar.vector(Vector3(1, 2, 3)).converted(to: .plane))
        guard case .plane(let plane) = converted else { Issue.record("expected plane"); return }
        #expect(plane.origin == Vector3(1, 2, 3))
        #expect(plane.normal == .unitZ)
    }

    @Test func impossibleConversionIsNil() {
        #expect(Scalar.bool(true).converted(to: .number) == nil)
    }

    @Test func listConversionFailsIfAnyItemFails() {
        #expect(Value.list([.integer(1), .bool(true)]).converted(to: .number) == nil)
    }

    @Test(arguments: [
        ConstantValue.number(6.5), .integer(4), .bool(true), .vector(Vector3(1, 2, 3)), .plane(.xz), .text("hello"),
    ])
    func constantsRoundTripThroughJSON(_ value: ConstantValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ConstantValue.self, from: data) == value)
    }

    @Test func constantJSONIsReadable() throws {
        let json = String(decoding: try JSONEncoder().encode(ConstantValue.number(6)), as: UTF8.self)
        #expect(json.contains("\"type\":\"number\""))
    }

    @Test func socketNameKeyedDictionariesEncodeAsObjects() throws {
        let json = String(decoding: try JSONEncoder().encode([SocketName("width"): ConstantValue.number(60)]), as: UTF8.self)
        #expect(json.hasPrefix("{\"width\""))
    }

    @Test func nonFiniteConstantsAreFlagged() {
        #expect(!ConstantValue.number(.nan).isFinite)
        #expect(!ConstantValue.vector(Vector3(0, .infinity, 0)).isFinite)
        #expect(ConstantValue.integer(3).isFinite)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter ValueTests`
Expected: compile errors, "cannot find 'SocketType' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorGraph/SocketName.swift`:
```swift
/// The name of a node's input or output socket, unique within that node's side.
public struct SocketName: Hashable, Sendable, Codable, Comparable, ExpressibleByStringLiteral,
    CustomStringConvertible, CodingKeyRepresentable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }

    public static func < (lhs: SocketName, rhs: SocketName) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // Lets `[SocketName: …]` encode as a JSON object rather than a flat array.
    public var codingKey: any CodingKey { Key(stringValue: rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(codingKey.stringValue)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
```

`Sources/CreatorGraph/ParameterID.swift`:
```swift
import Foundation

/// Identity of a document-level graph parameter.
public struct ParameterID: Hashable, Sendable, Codable, Comparable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: ParameterID, rhs: ParameterID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }
}
```

`Sources/CreatorGraph/SocketType.swift`:
```swift
/// The closed set of socket types (spec §4.2). `mesh` is reserved for sub-project 7.
public enum SocketType: String, Sendable, Codable, CaseIterable {
    case number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet

    /// Whether a wire carrying `source` may connect to a socket of this type.
    /// Only two implicit conversions exist: integer → number and vector → plane.
    public func accepts(_ source: SocketType) -> Bool {
        self == source || (self == .number && source == .integer) || (self == .plane && source == .vector)
    }
}
```

`Sources/CreatorGraph/ConstantValue.swift`:
```swift
import CreatorGeometry

/// A value typed into an unwired input or stored as a node setting, saved in the file.
public enum ConstantValue: Hashable, Sendable {
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case vector(Vector3)
    case plane(Plane)
    /// A non-socket setting, such as the parameter a Graph Parameter node reads.
    case text(String)

    /// False for NaN or ±∞ anywhere. JSON can't store those, so commands reject them.
    public var isFinite: Bool {
        switch self {
        case .number(let value): value.isFinite
        case .vector(let vector): vector.isFinite
        case .plane(let plane): plane.origin.isFinite && plane.normal.isFinite && plane.xAxis.isFinite
        case .integer, .bool, .text: true
        }
    }
}

extension ConstantValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case number, integer, bool, vector, plane, text }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .vector: self = .vector(try container.decode(Vector3.self, forKey: .value))
        case .plane: self = .plane(try container.decode(Plane.self, forKey: .value))
        case .text: self = .text(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let value): try container.encode(Kind.number, forKey: .type); try container.encode(value, forKey: .value)
        case .integer(let value): try container.encode(Kind.integer, forKey: .type); try container.encode(value, forKey: .value)
        case .bool(let value): try container.encode(Kind.bool, forKey: .type); try container.encode(value, forKey: .value)
        case .vector(let value): try container.encode(Kind.vector, forKey: .type); try container.encode(value, forKey: .value)
        case .plane(let value): try container.encode(Kind.plane, forKey: .type); try container.encode(value, forKey: .value)
        case .text(let value): try container.encode(Kind.text, forKey: .type); try container.encode(value, forKey: .value)
        }
    }
}
```

`Sources/CreatorGraph/Scalar.swift`:
```swift
import CreatorGeometry
import CreatorKernel

/// One runtime value flowing along a wire.
public enum Scalar: Sendable {
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case vector(Vector3)
    case plane(Plane)
    case profile(Profile2D)
    case solid(Solid)
    case edgeSet(EdgeSet)
    case faceSet(FaceSet)

    public var type: SocketType {
        switch self {
        case .number: .number
        case .integer: .integer
        case .bool: .bool
        case .vector: .vector
        case .plane: .plane
        case .profile: .profile
        case .solid: .solid
        case .edgeSet: .edgeSet
        case .faceSet: .faceSet
        }
    }

    /// The runtime form of a stored constant. `text` settings have none.
    public init?(_ constant: ConstantValue) {
        switch constant {
        case .number(let value): self = .number(value)
        case .integer(let value): self = .integer(value)
        case .bool(let value): self = .bool(value)
        case .vector(let value): self = .vector(value)
        case .plane(let value): self = .plane(value)
        case .text: return nil
        }
    }

    /// This value as `target`, applying the implicit conversions, or `nil` if impossible.
    public func converted(to target: SocketType) -> Scalar? {
        if type == target { return self }
        switch (self, target) {
        case (.integer(let value), .number): return .number(Double(value))
        case (.vector(let value), .plane): return .plane(.through(value))
        default: return nil
        }
    }

    public var estimatedBytes: Int {
        switch self {
        case .solid(let solid): solid.estimatedBytes
        case .profile(let profile): 64 + profile.segments.count * 48
        case .edgeSet(let set): 32 + set.edges.count * 8
        case .faceSet(let set): 32 + set.faces.count * 8
        case .number, .integer, .bool, .vector, .plane: 32
        }
    }
}
```

`Sources/CreatorGraph/Value.swift`:
```swift
/// What a socket carries: a single item, or a list that broadcasts (spec §4.2).
/// Nested data trees will be added in sub-project 7, so don't assume exactly two cases.
public enum Value: Sendable {
    case one(Scalar)
    case list([Scalar])

    public var items: [Scalar] {
        switch self {
        case .one(let scalar): [scalar]
        case .list(let scalars): scalars
        }
    }

    public func converted(to target: SocketType) -> Value? {
        switch self {
        case .one(let scalar):
            return scalar.converted(to: target).map(Value.one)
        case .list(let scalars):
            let converted = scalars.compactMap { $0.converted(to: target) }
            return converted.count == scalars.count ? .list(converted) : nil
        }
    }

    public var estimatedBytes: Int { items.reduce(16) { $0 + $1.estimatedBytes } }
}
```

Delete both `Placeholder.swift` files in `CreatorGraph`.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter ValueTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add socket types, constants and runtime values"
```

### Task 7: Node definitions, registry and broadcasting

**Files:**
- Create: `Sources/CreatorGraph/{ValueUnit,SocketSpec,NodeCategory,InspectorSection,InspectorControl,InspectorAction,HandleSpec,NodeError,NodeInputs,NodeOutputs,EvalContext,NodeDefinition,NodeRegistry,Node,BroadcastPlan}.swift`
- Create (fixtures): `Tests/CreatorGraphTests/Support/TestNodes.swift`, `Tests/CreatorGraphTests/Support/TestSupport.swift`
- Test: `Tests/CreatorGraphTests/RegistryTests.swift`, `Tests/CreatorGraphTests/BroadcastTests.swift`

**Interfaces:**
- Consumes: Task 6 types, plus `NodeID`, `NodeTag`, `Kernel` (Task 4).
- Produces:
  - `SocketSpec(_ name:, _ type:, access: .item/.list = .item, defaultValue: ConstantValue? = nil, unit: ValueUnit = .none, range: ClosedRange<Double>? = nil, optional: Bool = false)`
  - `NodeCategory`, `InspectorSection(title:controls:)`, `InspectorControl`, `InspectorAction`, `HandleSpec`
  - `NodeError` (`missingInput`, `typeMismatch`, `invalidValue`, with `message`)
  - `NodeInputs` (`item`, `scalar/list/number/integer/bool/vector/plane/profile/solid/edgeSet(_:)`, `has(_:)`) and `NodeOutputs(_ values:, warnings:)` / `NodeOutputs(lists:warnings:)`
  - `EvalContext(node:item:parameters:)` with `tag: NodeTag`
  - `protocol NodeDefinition`, and `NodeRegistry([…])` with `subscript(typeID:)`, `all` and `makeNode(_:at:)`
  - `Node`
  - `BroadcastPlan.make(inputs:specs:)` with `iterations`, `isSingle` and `inputs(at:)`

- [ ] **Step 1: Write the fixtures**

`Tests/CreatorGraphTests/Support/TestNodes.swift`:
```swift
// Test fixture file: it deliberately holds several small node definitions.
import CreatorGeometry
import Foundation
import CreatorKernel
@testable import CreatorGraph

enum ConstantNode: NodeDefinition {
    static let typeID = "test.constant"
    static let displayName = "Constant"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum IntegerNode: NodeDefinition {
    static let typeID = "test.integer"
    static let displayName = "Integer"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .integer, defaultValue: .integer(0))]
    static let outputs = [SocketSpec("value", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .integer(try inputs.integer("value"))])
    }
}

enum AddNode: NodeDefinition {
    static let typeID = "test.add"
    static let displayName = "Add"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("a", .number, defaultValue: .number(0)), SocketSpec("b", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("sum", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["sum": .number(try inputs.number("a") + inputs.number("b"))])
    }
}

/// Requires a wired or typed `value`; it has no default.
enum RequiredNode: NodeDefinition {
    static let typeID = "test.required"
    static let displayName = "Required"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum SumListNode: NodeDefinition {
    static let typeID = "test.sumList"
    static let displayName = "Sum List"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("values", .number, access: .list)]
    static let outputs = [SocketSpec("sum", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let total = try inputs.list("values").reduce(0.0) { sum, scalar in
            guard case .number(let value) = scalar else { throw NodeError.typeMismatch("values", expected: .number) }
            return sum + value
        }
        return NodeOutputs(["sum": .number(total)])
    }
}

/// Emits the list 0, 1, …, count − 1 as one list-valued output.
enum ListSourceNode: NodeDefinition {
    static let typeID = "test.listSource"
    static let displayName = "List Source"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("count", .integer, defaultValue: .integer(3))]
    static let outputs = [SocketSpec("values", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let count = try inputs.integer("count")
        guard count >= 0 else { throw NodeError.invalidValue("Count can't be negative.") }
        return NodeOutputs(lists: ["values": (0..<count).map { .number(Double($0)) }])
    }
}

enum FailNode: NodeDefinition {
    static let typeID = "test.fail"
    static let displayName = "Fail"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Boom")
    }
}

enum WarnNode: NodeDefinition {
    static let typeID = "test.warn"
    static let displayName = "Warn"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))], warnings: ["Careful"])
    }
}

/// Sleeps 300 ms before passing its value through, so tests can cancel mid-evaluation.
enum SlowNode: NodeDefinition {
    static let typeID = "test.slow"
    static let displayName = "Slow"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await Task.sleep(for: .milliseconds(300))
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// Reads the graph parameter named by its `parameter` text setting.
enum ParameterNode: NodeDefinition {
    static let typeID = "test.parameter"
    static let displayName = "Parameter"
    static let category = NodeCategory.value
    static let readsParameters = true
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .text(let raw)? = context.node.inputValues["parameter"],
              let uuid = UUID(uuidString: raw),
              case .number(let value)? = context.parameters[ParameterID(rawValue: uuid)] else {
            throw NodeError.invalidValue("Choose a parameter.")
        }
        return NodeOutputs(["value": .number(value)])
    }
}

/// Extrudes a centred rectangle through the kernel.
enum BoxNode: NodeDefinition {
    static let typeID = "test.box"
    static let displayName = "Box"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let profile = Profile2D.rectangle(width: try inputs.number("width"), height: try inputs.number("height"), plane: .xy)
        let solid = try await kernel.extrude(profile, distance: try inputs.number("distance"), mode: .oneSided, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}

/// Version 2 renamed its input from "old" to "value".
enum VersionedNode: NodeDefinition {
    static let typeID = "test.versioned"
    static let typeVersion = 2
    static let displayName = "Versioned"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func migrate(_ node: Node, from version: Int) -> Node {
        var migrated = node
        if version < 2, let old = migrated.inputValues.removeValue(forKey: "old") {
            migrated.inputValues["value"] = old
        }
        return migrated
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

let testRegistry = NodeRegistry([
    ConstantNode.self, IntegerNode.self, AddNode.self, RequiredNode.self, SumListNode.self, ListSourceNode.self,
    FailNode.self, WarnNode.self, SlowNode.self, ParameterNode.self, BoxNode.self, VersionedNode.self,
])
```

`Tests/CreatorGraphTests/Support/TestSupport.swift`:
```swift
// Test fixture file: helpers shared by the graph tests.
import CreatorKernel
@testable import CreatorGraph

func makeNode(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:], output: Bool = false) -> Node {
    var node = testRegistry.makeNode(definition.typeID)
    node.inputValues = values
    node.isOutput = output
    return node
}

extension Value {
    /// The numbers carried, or `nil` if any item isn't a number.
    var numbers: [Double]? {
        let values = items.compactMap { scalar -> Double? in
            if case .number(let value) = scalar { value } else { nil }
        }
        return values.count == items.count ? values : nil
    }

    var isList: Bool { if case .list = self { true } else { false } }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorGraphTests/RegistryTests.swift`:
```swift
import Testing
@testable import CreatorGraph

struct RegistryTests {
    @Test func looksUpDefinitionsByTypeID() throws {
        let definition = try #require(testRegistry["test.add"])
        #expect(definition.displayName == "Add")
        #expect(testRegistry["missing.type"] == nil)
    }

    @Test func makeNodeUsesDefinitionMetadata() {
        let node = testRegistry.makeNode(VersionedNode.typeID, at: .init(4, 5))
        #expect(node.typeVersion == 2)
        #expect(node.name == "Versioned")
        #expect(node.position == .init(4, 5))
    }

    @Test func defaultsAreEmptyInspectorAndNoHandles() {
        #expect(AddNode.inspector.isEmpty)
        #expect(AddNode.handles.isEmpty)
        #expect(AddNode.readsParameters == false)
    }
}
```

`Tests/CreatorGraphTests/BroadcastTests.swift`:
```swift
import Testing
@testable import CreatorGraph

struct BroadcastTests {
    let specs = [SocketSpec("a", .number), SocketSpec("b", .number), SocketSpec("all", .number, access: .list)]

    @Test func singleItemsRunOnceAndStaySingle() throws {
        let plan = BroadcastPlan.make(inputs: ["a": .one(.number(1)), "b": .one(.number(2))], specs: specs)
        #expect(plan.iterations == 1)
        #expect(plan.isSingle)
        #expect(try plan.inputs(at: 0).number("b") == 2)
    }

    @Test func longestListWinsAndShorterRepeatsItsLastItem() throws {
        let plan = BroadcastPlan.make(
            inputs: ["a": .list([.number(1), .number(2), .number(3)]), "b": .list([.number(10), .number(20)])],
            specs: specs
        )
        #expect(plan.iterations == 3)
        #expect(!plan.isSingle)
        #expect(try plan.inputs(at: 2).number("a") == 3)
        #expect(try plan.inputs(at: 2).number("b") == 20)
    }

    @Test func singleItemRepeatsAcrossAList() throws {
        let plan = BroadcastPlan.make(inputs: ["a": .list([.number(1), .number(2)]), "b": .one(.number(5))], specs: specs)
        #expect(try plan.inputs(at: 1).number("b") == 5)
    }

    @Test func emptyListProducesEmptyOutputs() {
        let plan = BroadcastPlan.make(inputs: ["a": .list([]), "b": .one(.number(5))], specs: specs)
        #expect(plan.iterations == 0)
        #expect(!plan.isSingle)
    }

    @Test func listAccessSocketsReceiveTheWholeListAndDoNotBroadcast() throws {
        let plan = BroadcastPlan.make(inputs: ["all": .list([.number(1), .number(2), .number(3)])], specs: specs)
        #expect(plan.iterations == 1)
        #expect(plan.isSingle)
        #expect(try plan.inputs(at: 0).list("all").count == 3)
    }

    @Test func missingInputThrowsANamedError() {
        let inputs = BroadcastPlan.make(inputs: [:], specs: specs).inputs(at: 0)
        #expect(throws: NodeError.missingInput("a")) { try inputs.number("a") }
    }

    @Test func wrongTypeThrowsTypeMismatch() {
        let inputs = BroadcastPlan.make(inputs: ["a": .one(.bool(true))], specs: specs).inputs(at: 0)
        #expect(throws: NodeError.typeMismatch("a", expected: .number)) { try inputs.number("a") }
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `swift test --filter "RegistryTests|BroadcastTests"`
Expected: compile errors, "cannot find type 'NodeDefinition' in scope".

- [ ] **Step 4: Implement the declarative types**

`Sources/CreatorGraph/ValueUnit.swift`:
```swift
/// How a socket's number is shown and entered.
public enum ValueUnit: String, Sendable, Codable {
    case none, millimetres, degrees, count
}
```

`Sources/CreatorGraph/SocketSpec.swift`:
```swift
/// Declares one input or output socket of a node type.
public struct SocketSpec: Sendable, Equatable {
    /// `.item` sockets broadcast over lists. `.list` sockets receive the whole list at once.
    public enum Access: Sendable, Equatable { case item, list }

    public var name: SocketName
    public var type: SocketType
    public var access: Access
    public var defaultValue: ConstantValue?
    public var unit: ValueUnit
    /// A UI hint for sliders. Values outside it are allowed.
    public var range: ClosedRange<Double>?
    public var isOptional: Bool

    public init(_ name: SocketName, _ type: SocketType, access: Access = .item, defaultValue: ConstantValue? = nil,
                unit: ValueUnit = .none, range: ClosedRange<Double>? = nil, optional: Bool = false) {
        self.name = name
        self.type = type
        self.access = access
        self.defaultValue = defaultValue
        self.unit = unit
        self.range = range
        self.isOptional = optional
    }
}
```

`Sources/CreatorGraph/NodeCategory.swift`:
```swift
/// Drives a node's header colour and palette grouping (spec §6.6).
public enum NodeCategory: String, Sendable, Codable, CaseIterable {
    case value, profile, solid, selection, feature, output
}
```

`Sources/CreatorGraph/InspectorAction.swift`:
```swift
/// An inspector button's effect, carried out by the editor or viewport.
public enum InspectorAction: String, Sendable, Codable {
    case pickEdgesInView, pickFacesInView
}
```

`Sources/CreatorGraph/InspectorControl.swift`:
```swift
/// One control in a node's context inspector, bound to an input socket (spec §6.4).
public enum InspectorControl: Sendable, Equatable {
    case slider(SocketName)
    case number(SocketName)
    case integer(SocketName)
    case toggle(SocketName, label: String)
    case segmented(SocketName, options: [String])
    case planePicker(SocketName)
    case anchorGrid(SocketName)
    case ruleSummary(SocketName)
    case button(title: String, action: InspectorAction)
}
```

`Sources/CreatorGraph/InspectorSection.swift`:
```swift
/// A titled group of inspector controls, declared as data by a node definition.
public struct InspectorSection: Sendable, Equatable {
    public var title: String
    public var controls: [InspectorControl]

    public init(title: String, controls: [InspectorControl]) {
        self.title = title
        self.controls = controls
    }
}
```

`Sources/CreatorGraph/HandleSpec.swift`:
```swift
/// An in-viewport handle that edits a socket (spec §6.5). The viewport resolves its
/// origin and direction from the node's output.
public enum HandleSpec: Sendable, Equatable {
    case linear(SocketName)
    case radial(SocketName)
}
```

`Sources/CreatorGraph/NodeError.swift`:
```swift
/// A node's own failure, with a message for the person editing the graph.
public enum NodeError: Error, Equatable, Sendable {
    case missingInput(SocketName)
    case typeMismatch(SocketName, expected: SocketType)
    case invalidValue(String)

    public var message: String {
        switch self {
        case .missingInput(let socket): "Connect or set “\(socket)”."
        case .typeMismatch(let socket, let expected): "“\(socket)” needs a \(expected.rawValue)."
        case .invalidValue(let message): message
        }
    }
}
```

`Sources/CreatorGraph/NodeInputs.swift`:
```swift
import CreatorGeometry
import CreatorKernel

/// The inputs for one broadcast iteration of a node.
public struct NodeInputs: Sendable {
    public enum Slot: Sendable {
        case item(Scalar)
        case list([Scalar])
    }

    /// Which broadcast iteration this is (0-based).
    public let item: Int
    private let slots: [SocketName: Slot]

    public init(item: Int, slots: [SocketName: Slot]) {
        self.item = item
        self.slots = slots
    }

    public func has(_ name: SocketName) -> Bool { slots[name] != nil }

    public func scalar(_ name: SocketName) throws -> Scalar {
        switch slots[name] {
        case .item(let scalar)?: return scalar
        case .list(let scalars)?:
            guard let first = scalars.first else { throw NodeError.missingInput(name) }
            return first
        case nil: throw NodeError.missingInput(name)
        }
    }

    public func list(_ name: SocketName) throws -> [Scalar] {
        switch slots[name] {
        case .list(let scalars)?: return scalars
        case .item(let scalar)?: return [scalar]
        case nil: throw NodeError.missingInput(name)
        }
    }

    public func number(_ name: SocketName) throws -> Double {
        guard case .number(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .number) }
        return value
    }

    public func integer(_ name: SocketName) throws -> Int {
        guard case .integer(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .integer) }
        return value
    }

    public func bool(_ name: SocketName) throws -> Bool {
        guard case .bool(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .bool) }
        return value
    }

    public func vector(_ name: SocketName) throws -> Vector3 {
        guard case .vector(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .vector) }
        return value
    }

    public func plane(_ name: SocketName) throws -> Plane {
        guard case .plane(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .plane) }
        return value
    }

    public func profile(_ name: SocketName) throws -> Profile2D {
        guard case .profile(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .profile) }
        return value
    }

    public func solid(_ name: SocketName) throws -> Solid {
        guard case .solid(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .solid) }
        return value
    }

    public func edgeSet(_ name: SocketName) throws -> EdgeSet {
        guard case .edgeSet(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .edgeSet) }
        return value
    }
}
```

`Sources/CreatorGraph/NodeOutputs.swift`:
```swift
/// What one broadcast iteration of a node produced.
public struct NodeOutputs: Sendable {
    /// One item per output socket for this iteration.
    public var values: [SocketName: Scalar]
    /// Whole lists for generator nodes (Series, Grid Points, …). A socket listed here always
    /// becomes a `.list` output, and its items are appended for each iteration.
    public var lists: [SocketName: [Scalar]]
    /// Non-fatal problems, such as a selection rule matching a different number of edges.
    public var warnings: [String]

    public init(_ values: [SocketName: Scalar] = [:], warnings: [String] = []) {
        self.values = values
        self.lists = [:]
        self.warnings = warnings
    }

    public init(lists: [SocketName: [Scalar]], warnings: [String] = []) {
        self.values = [:]
        self.lists = lists
        self.warnings = warnings
    }
}
```

`Sources/CreatorGraph/EvalContext.swift`:
```swift
import CreatorKernel

/// Per-iteration context handed to `NodeDefinition.evaluate`.
public struct EvalContext: Sendable {
    public let node: Node
    public let item: Int
    public let parameters: [ParameterID: ConstantValue]

    public init(node: Node, item: Int, parameters: [ParameterID: ConstantValue]) {
        self.node = node
        self.item = item
        self.parameters = parameters
    }

    /// The tag kernel calls should use, so created faces are named after this node and item.
    public var tag: NodeTag { NodeTag(node: node.id, item: item) }
}
```

`Sources/CreatorGraph/NodeDefinition.swift`:
```swift
import CreatorKernel

/// A node type. Definitions are stateless and UI-free: the inspector and handles are data
/// (spec §4.3).
public protocol NodeDefinition: Sendable {
    static var typeID: String { get }
    static var typeVersion: Int { get }
    static var displayName: String { get }
    static var category: NodeCategory { get }
    static var inputs: [SocketSpec] { get }
    static var outputs: [SocketSpec] { get }
    static var inspector: [InspectorSection] { get }
    static var handles: [HandleSpec] { get }
    /// True if `evaluate` reads `context.parameters`, so parameter edits invalidate its cache.
    static var readsParameters: Bool { get }

    /// Upgrades a node saved under an older `typeVersion`.
    static func migrate(_ node: Node, from version: Int) -> Node

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs
}

extension NodeDefinition {
    public static var typeVersion: Int { 1 }
    public static var inspector: [InspectorSection] { [] }
    public static var handles: [HandleSpec] { [] }
    public static var readsParameters: Bool { false }
    public static func migrate(_ node: Node, from version: Int) -> Node { node }
}
```

`Sources/CreatorGraph/NodeRegistry.swift`:
```swift
import CreatorGeometry

/// Maps type IDs to node definitions.
public struct NodeRegistry: Sendable {
    private let definitions: [String: any NodeDefinition.Type]

    /// Duplicate type IDs are a programming error and trap.
    public init(_ definitions: [any NodeDefinition.Type]) {
        var map: [String: any NodeDefinition.Type] = [:]
        for definition in definitions {
            precondition(map[definition.typeID] == nil, "Duplicate node typeID \(definition.typeID)")
            map[definition.typeID] = definition
        }
        self.definitions = map
    }

    public subscript(typeID: String) -> (any NodeDefinition.Type)? { definitions[typeID] }

    /// Every registered definition, sorted by display name.
    public var all: [any NodeDefinition.Type] { definitions.values.sorted { $0.displayName < $1.displayName } }

    /// A fresh node of a registered type. An unregistered type gives a node with version 1
    /// whose name is the type ID.
    public func makeNode(_ typeID: String, at position: Vector2 = .zero) -> Node {
        let definition = definitions[typeID]
        return Node(typeID: typeID, typeVersion: definition?.typeVersion ?? 1,
                    name: definition?.displayName ?? typeID, position: position)
    }
}
```

`Sources/CreatorGraph/Node.swift`:
```swift
import CreatorGeometry
import CreatorKernel

/// One node instance in a graph: pure data, saved in the file.
public struct Node: Sendable, Codable, Equatable, Identifiable {
    public var id: NodeID
    public var typeID: String
    public var typeVersion: Int
    public var name: String
    /// Constants for unwired inputs, plus non-socket settings (`text`).
    public var inputValues: [SocketName: ConstantValue]
    /// Canonical left-to-right canvas position. The vertical dock uses its transpose (spec §6.2).
    public var position: Vector2
    public var isOutput: Bool

    public init(id: NodeID = NodeID(), typeID: String, typeVersion: Int = 1, name: String,
                inputValues: [SocketName: ConstantValue] = [:], position: Vector2 = .zero, isOutput: Bool = false) {
        self.id = id
        self.typeID = typeID
        self.typeVersion = typeVersion
        self.name = name
        self.inputValues = inputValues
        self.position = position
        self.isOutput = isOutput
    }
}
```

`Sources/CreatorGraph/BroadcastPlan.swift`:
```swift
/// How many times a node runs and what each iteration sees (spec §4.2 broadcasting).
public struct BroadcastPlan: Sendable {
    public let iterations: Int
    /// True when every item-access input is a single item, so outputs stay `.one`.
    public let isSingle: Bool
    private let itemInputs: [SocketName: Value]
    private let listInputs: [SocketName: [Scalar]]

    /// Item sockets broadcast over the longest list, and a shorter list repeats its last item.
    /// Any empty list means zero iterations. List sockets always get the whole list.
    public static func make(inputs: [SocketName: Value], specs: [SocketSpec]) -> BroadcastPlan {
        var itemInputs: [SocketName: Value] = [:]
        var listInputs: [SocketName: [Scalar]] = [:]
        var counts: [Int] = []
        for spec in specs {
            guard let value = inputs[spec.name] else { continue }
            switch spec.access {
            case .list:
                listInputs[spec.name] = value.items
            case .item:
                itemInputs[spec.name] = value
                if case .list(let scalars) = value { counts.append(scalars.count) }
            }
        }
        guard let longest = counts.max() else {
            return BroadcastPlan(iterations: 1, isSingle: true, itemInputs: itemInputs, listInputs: listInputs)
        }
        let iterations = counts.contains(0) ? 0 : longest
        return BroadcastPlan(iterations: iterations, isSingle: false, itemInputs: itemInputs, listInputs: listInputs)
    }

    public func inputs(at item: Int) -> NodeInputs {
        var slots: [SocketName: NodeInputs.Slot] = [:]
        for (name, value) in itemInputs {
            switch value {
            case .one(let scalar): slots[name] = .item(scalar)
            case .list(let scalars): slots[name] = .item(scalars[min(item, scalars.count - 1)])
            }
        }
        for (name, scalars) in listInputs {
            slots[name] = .list(scalars)
        }
        return NodeInputs(item: item, slots: slots)
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter "RegistryTests|BroadcastTests"`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add node definitions, registry and list broadcasting"
```

### Task 8: Graph model, traversal and connection rules

**Files:**
- Create: `Sources/CreatorGraph/{Endpoint,Link,GraphParameter,Graph,EvaluationOrder,Graph+Traversal,ConnectionProblem,Graph+Connections,GraphError}.swift`
- Modify: `Tests/CreatorGraphTests/Support/TestSupport.swift` (add the `link` and `graph` helpers)
- Test: `Tests/CreatorGraphTests/ConnectionTests.swift`

**Interfaces:**
- Consumes: `Node`, `NodeRegistry`, `SocketType.accepts` (Tasks 6–7).
- Produces:
  - `Endpoint(node:socket:)` and `Link(from:to:)`
  - `GraphParameter(id:name:type:value:min:max:step:)`
  - `Graph(nodes:links:parameters:)`, Codable with nodes written as a sorted array
  - `graph.incomingLink(to:) -> Link?`
  - `graph.evaluationOrder(for demand: Set<NodeID>) -> EvaluationOrder` (`order: [NodeID]`, `cyclic: Set<NodeID>`)
  - `graph.upstreamClosure(of:) -> Set<NodeID>` and `graph.downstreamClosure(of: Set<NodeID>) -> Set<NodeID>`
  - `graph.connectionProblem(from:to:registry:) -> ConnectionProblem?`
  - `GraphError`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/ConnectionTests.swift`:
```swift
import Testing
@testable import CreatorGraph

struct ConnectionTests {
    @Test func compatibleTypesConnect() {
        let a = makeNode(IntegerNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "value"), to: Endpoint(node: b.id, socket: "a"), registry: testRegistry) == nil)
    }

    @Test func incompatibleTypesAreRefused() {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        let g = graph([box, add])
        #expect(g.connectionProblem(from: Endpoint(node: box.id, socket: "solid"), to: Endpoint(node: add.id, socket: "a"), registry: testRegistry)
                == .typeMismatch(from: .solid, to: .number))
    }

    @Test func unknownSocketsAreRefused() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        #expect(graph([a, b]).connectionProblem(from: Endpoint(node: a.id, socket: "nope"), to: Endpoint(node: b.id, socket: "a"), registry: testRegistry)
                == .unknownSocket("nope"))
    }

    @Test func selfLinksAndCyclesAreRefused() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", b, "a")])
        #expect(g.connectionProblem(from: Endpoint(node: a.id, socket: "sum"), to: Endpoint(node: a.id, socket: "b"), registry: testRegistry) == .sameNode)
        #expect(g.connectionProblem(from: Endpoint(node: b.id, socket: "sum"), to: Endpoint(node: a.id, socket: "a"), registry: testRegistry) == .wouldCreateCycle)
    }

    @Test func evaluationOrderVisitsOnlyUpstreamOfDemand() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self), unrelated = makeNode(ConstantNode.self)
        let g = graph([a, b, unrelated], [link(a, "value", b, "a")])
        let order = g.evaluationOrder(for: [b.id])
        #expect(order.order == [a.id, b.id])
        #expect(order.cyclic.isEmpty)
    }

    @Test func cyclesInLoadedGraphsAreReportedNotLooped() {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "sum", b, "a"), link(b, "sum", a, "a")])
        #expect(g.evaluationOrder(for: [b.id]).cyclic == [a.id, b.id])
    }

    @Test func downstreamClosureFollowsLinks() {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self), c = makeNode(AddNode.self)
        let g = graph([a, b, c], [link(a, "value", b, "a"), link(b, "sum", c, "a")])
        #expect(g.downstreamClosure(of: [a.id]) == [a.id, b.id, c.id])
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter ConnectionTests`
Expected: compile errors, "cannot find 'Endpoint' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorGraph/Endpoint.swift`:
```swift
import CreatorKernel

/// One end of a wire: a node and one of its sockets.
public struct Endpoint: Hashable, Sendable, Codable {
    public var node: NodeID
    public var socket: SocketName

    public init(node: NodeID, socket: SocketName) {
        self.node = node
        self.socket = socket
    }
}
```

`Sources/CreatorGraph/Link.swift`:
```swift
/// A wire from an output socket to an input socket. An input takes at most one link.
public struct Link: Hashable, Sendable, Codable {
    public var from: Endpoint
    public var to: Endpoint

    public init(from: Endpoint, to: Endpoint) {
        self.from = from
        self.to = to
    }
}
```

`Sources/CreatorGraph/GraphParameter.swift`:
```swift
/// A named document input (for example Width or Wall), shown in the inspector. A variant
/// is a saved set of these values (spec §4.1).
public struct GraphParameter: Sendable, Codable, Equatable, Identifiable {
    public var id: ParameterID
    public var name: String
    public var type: SocketType
    public var value: ConstantValue
    public var min: Double?
    public var max: Double?
    public var step: Double?

    public init(id: ParameterID = ParameterID(), name: String, type: SocketType, value: ConstantValue,
                min: Double? = nil, max: Double? = nil, step: Double? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.value = value
        self.min = min
        self.max = max
        self.step = step
    }
}
```

`Sources/CreatorGraph/Graph.swift`:
```swift
import CreatorKernel

/// The whole recipe: nodes, wires and document parameters. Pure data.
public struct Graph: Sendable, Equatable {
    public var nodes: [NodeID: Node]
    public var links: [Link]
    public var parameters: [GraphParameter]

    public init(nodes: [NodeID: Node] = [:], links: [Link] = [], parameters: [GraphParameter] = []) {
        self.nodes = nodes
        self.links = links
        self.parameters = parameters
    }
}

extension Graph: Codable {
    private enum CodingKeys: String, CodingKey { case nodes, links, parameters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([Node].self, forKey: .nodes)
        nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        links = try container.decodeIfPresent([Link].self, forKey: .links) ?? []
        parameters = try container.decodeIfPresent([GraphParameter].self, forKey: .parameters) ?? []
    }

    /// Nodes are written as an array sorted by ID, so saved files diff cleanly.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.values.sorted { $0.id < $1.id }, forKey: .nodes)
        try container.encode(links, forKey: .links)
        try container.encode(parameters, forKey: .parameters)
    }
}
```

`Sources/CreatorGraph/EvaluationOrder.swift`:
```swift
import CreatorKernel

/// Upstream-first order for a demand set, plus any nodes caught in a cycle.
public struct EvaluationOrder: Sendable, Equatable {
    public var order: [NodeID]
    public var cyclic: Set<NodeID>
}
```

`Sources/CreatorGraph/Graph+Traversal.swift`:
```swift
import CreatorKernel

extension Graph {
    public func incomingLink(to endpoint: Endpoint) -> Link? {
        links.first { $0.to == endpoint }
    }

    /// Every node that `demand` depends on, upstream first, deterministic. Cycles (possible
    /// only in hand-edited files) are reported in `cyclic` instead of looping.
    public func evaluationOrder(for demand: Set<NodeID>) -> EvaluationOrder {
        enum Mark { case visiting, done }
        var marks: [NodeID: Mark] = [:]
        var order: [NodeID] = []
        var cyclic: Set<NodeID> = []
        var stack: [NodeID] = []

        func visit(_ id: NodeID) {
            switch marks[id] {
            case .done?:
                return
            case .visiting?:
                if let start = stack.lastIndex(of: id) { cyclic.formUnion(stack[start...]) }
                return
            case nil:
                break
            }
            guard nodes[id] != nil else { return }
            marks[id] = .visiting
            stack.append(id)
            let sources = links.filter { $0.to.node == id }.map(\.from.node).sorted()
            for source in sources { visit(source) }
            stack.removeLast()
            marks[id] = .done
            order.append(id)
        }

        for id in demand.sorted() { visit(id) }
        return EvaluationOrder(order: order, cyclic: cyclic)
    }

    /// `id` and everything it reads from, directly or indirectly.
    public func upstreamClosure(of id: NodeID) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var pending = [id]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending += links.filter { $0.to.node == next }.map(\.from.node)
        }
        return seen
    }

    /// `ids` and everything that reads from them, directly or indirectly.
    public func downstreamClosure(of ids: Set<NodeID>) -> Set<NodeID> {
        var seen: Set<NodeID> = []
        var pending = Array(ids)
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending += links.filter { $0.from.node == next }.map(\.to.node)
        }
        return seen
    }
}
```

`Sources/CreatorGraph/ConnectionProblem.swift`:
```swift
/// Why a wire can't be made.
public enum ConnectionProblem: Error, Equatable, Sendable {
    case unknownNode
    case unknownSocket(SocketName)
    case sameNode
    case typeMismatch(from: SocketType, to: SocketType)
    case wouldCreateCycle
}
```

`Sources/CreatorGraph/Graph+Connections.swift`:
```swift
extension Graph {
    /// `nil` if `from` (an output) may be wired to `to` (an input), otherwise why not.
    public func connectionProblem(from: Endpoint, to: Endpoint, registry: NodeRegistry) -> ConnectionProblem? {
        guard let source = nodes[from.node], let target = nodes[to.node],
              let sourceDefinition = registry[source.typeID], let targetDefinition = registry[target.typeID] else {
            return .unknownNode
        }
        guard let output = sourceDefinition.outputs.first(where: { $0.name == from.socket }) else { return .unknownSocket(from.socket) }
        guard let input = targetDefinition.inputs.first(where: { $0.name == to.socket }) else { return .unknownSocket(to.socket) }
        guard from.node != to.node else { return .sameNode }
        guard input.type.accepts(output.type) else { return .typeMismatch(from: output.type, to: input.type) }
        guard !upstreamClosure(of: from.node).contains(to.node) else { return .wouldCreateCycle }
        return nil
    }
}
```

`Sources/CreatorGraph/GraphError.swift`:
```swift
import CreatorKernel

/// Why a graph command was refused.
public enum GraphError: Error, Equatable, Sendable {
    case invalidConnection(ConnectionProblem)
    case nodeNotFound(NodeID)
    case duplicateNode(NodeID)
    case linkNotFound
    case parameterNotFound(ParameterID)
    case invalidValue(String)
}
```

Add these helpers to `Tests/CreatorGraphTests/Support/TestSupport.swift`, below `makeNode`:
```swift
func link(_ from: Node, _ fromSocket: SocketName, _ to: Node, _ toSocket: SocketName) -> Link {
    Link(from: Endpoint(node: from.id, socket: fromSocket), to: Endpoint(node: to.id, socket: toSocket))
}

func graph(_ nodes: [Node], _ links: [Link] = [], parameters: [GraphParameter] = []) -> Graph {
    Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links, parameters: parameters)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter "ConnectionTests|RegistryTests|BroadcastTests"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add graph model, traversal and connection rules"
```

### Task 9: Evaluator — order, inputs, broadcasting, errors

**Files:**
- Create: `Sources/CreatorGraph/{NodeState,NodeResult,CacheKey,ResultCache,EvaluationReport,Evaluator}.swift`
- Test: `Tests/CreatorGraphTests/EvaluatorTests.swift`

**Interfaces:**
- Consumes: Tasks 6–8, plus `Kernel` and `KernelError` (Task 4).
- Produces:
  - `NodeState` (`.idle(String?)`, `.evaluating`, `.ok(duration: Duration)`, `.warning(String)`, `.error(String)`) with `isSuccess`
  - `NodeResult(state:outputs:)` with `outputs: [SocketName: Value]?` and `estimatedBytes`
  - `EvaluationReport` (`results: [NodeID: NodeResult]`, `evaluatedNodes: [NodeID]`)
  - `public actor Evaluator` with `init(registry:kernel:cacheBudgetBytes:)`, `evaluate(_ graph: Graph, demand: Set<NodeID>) async throws -> EvaluationReport` (throws only `CancellationError`), `cachedEntryCount: Int` and `static func message(for: any Error) -> String`
  - `CacheKey` and `ResultCache` (internal; Task 10 adds tests for their behaviour)

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/EvaluatorTests.swift`:
```swift
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct EvaluatorTests {
    func evaluator() -> Evaluator { Evaluator(registry: testRegistry, kernel: FakeKernel()) }

    @Test func wiredValuesFlowDownstream() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let b = makeNode(AddNode.self, ["b": .number(3)], output: true)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "value", b, "a")]), demand: [b.id])
        #expect(report.results[b.id]?.outputs?["sum"]?.numbers == [5])
        #expect(report.results[b.id]?.state.isSuccess == true)
    }

    @Test func integerWireIsWidenedToNumber() async throws {
        let a = makeNode(IntegerNode.self, ["value": .integer(4)])
        let b = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "value", b, "a")]), demand: [b.id])
        #expect(report.results[b.id]?.outputs?["sum"]?.numbers == [4])
    }

    @Test func listsBroadcastThroughDownstreamNodes() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let add = makeNode(AddNode.self, ["b": .number(10)])
        let report = try await evaluator().evaluate(graph([list, add], [link(list, "values", add, "a")]), demand: [add.id])
        let sum = try #require(report.results[add.id]?.outputs?["sum"])
        #expect(sum.isList)
        #expect(sum.numbers == [10, 11, 12])
    }

    @Test func listAccessNodeSumsAWiredList() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let sum = makeNode(SumListNode.self)
        let report = try await evaluator().evaluate(graph([a, sum], [link(a, "value", sum, "values")]), demand: [sum.id])
        #expect(report.results[sum.id]?.outputs?["sum"]?.numbers == [2])
    }

    @Test func failingNodeShowsErrorAndDownstreamWaits() async throws {
        let fail = makeNode(FailNode.self)
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([fail, add], [link(fail, "value", add, "a")]), demand: [add.id])
        #expect(report.results[fail.id]?.state == .error("Boom"))
        guard case .idle(let reason?)? = report.results[add.id]?.state else { Issue.record("expected idle"); return }
        #expect(reason.contains("a"))
    }

    @Test func requiredUnwiredInputBlocksWithAPrompt() async throws {
        let node = makeNode(RequiredNode.self)
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state == .idle("Connect or set “value”."))
    }

    @Test func warningsSurfaceAsWarningState() async throws {
        let node = makeNode(WarnNode.self, ["value": .number(1)])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state == .warning("Careful"))
        #expect(report.results[node.id]?.outputs?["value"]?.numbers == [1])
    }

    @Test func kernelErrorsBecomePlainLanguage() async throws {
        let box = makeNode(BoxNode.self, ["distance": .number(-5)])
        let report = try await evaluator().evaluate(graph([box]), demand: [box.id])
        #expect(report.results[box.id]?.state == .error("Extrude distance must be greater than 0 mm."))
    }

    @Test func parametersFeedParameterNodes() async throws {
        let parameter = GraphParameter(name: "Width", type: .number, value: .number(60))
        let node = makeNode(ParameterNode.self, ["parameter": .text(parameter.id.rawValue.uuidString)])
        let report = try await evaluator().evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        #expect(report.results[node.id]?.outputs?["value"]?.numbers == [60])
    }

    @Test func unknownNodeTypeIsAnErrorNotACrash() async throws {
        var node = makeNode(ConstantNode.self)
        node.typeID = "future.node"
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        guard case .error(let message)? = report.results[node.id]?.state else { Issue.record("expected error"); return }
        #expect(message.contains("future.node"))
    }

    @Test func cycleInFileIsReportedNotFatal() async throws {
        let a = makeNode(AddNode.self), b = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([a, b], [link(a, "sum", b, "a"), link(b, "sum", a, "a")]), demand: [b.id])
        guard case .error(let message)? = report.results[a.id]?.state else { Issue.record("expected error"); return }
        #expect(message.contains("cycle"))
    }

    @Test func danglingLinkBlocksNode() async throws {
        let ghost = makeNode(ConstantNode.self)
        let add = makeNode(AddNode.self)
        // `ghost` is wired in but missing from the graph, as in a corrupt file.
        let report = try await evaluator().evaluate(graph([add], [link(ghost, "value", add, "a")]), demand: [add.id])
        guard case .idle? = report.results[add.id]?.state else { Issue.record("expected idle"); return }
    }

    @Test func emptyBroadcastGivesEmptyListNotError() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(0)])
        let add = makeNode(AddNode.self)
        let report = try await evaluator().evaluate(graph([list, add], [link(list, "values", add, "a")]), demand: [add.id])
        #expect(report.results[add.id]?.state.isSuccess == true)
        #expect(report.results[add.id]?.outputs?["sum"]?.numbers == [])
    }

    @Test func generatorOutputsAreListsEvenWhenSingle() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(1)])
        let report = try await evaluator().evaluate(graph([list]), demand: [list.id])
        #expect(report.results[list.id]?.outputs?["values"]?.isList == true)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter EvaluatorTests`
Expected: compile errors, "cannot find 'Evaluator' in scope".

- [ ] **Step 3: Implement the result types**

`Sources/CreatorGraph/NodeState.swift`:
```swift
/// What a node's badge shows (spec §4.4).
public enum NodeState: Sendable, Equatable {
    /// Not evaluated, with an optional reason ("Connect or set “profile”.").
    case idle(String?)
    case evaluating
    case ok(duration: Duration)
    case warning(String)
    case error(String)

    /// True for `.ok` and `.warning`: the node produced outputs.
    public var isSuccess: Bool {
        switch self {
        case .ok, .warning: true
        case .idle, .evaluating, .error: false
        }
    }
}
```

`Sources/CreatorGraph/NodeResult.swift`:
```swift
/// A node's state and, on success, its outputs.
public struct NodeResult: Sendable {
    public var state: NodeState
    public var outputs: [SocketName: Value]?

    public init(state: NodeState, outputs: [SocketName: Value]? = nil) {
        self.state = state
        self.outputs = outputs
    }

    public var estimatedBytes: Int { (outputs ?? [:]).values.reduce(64) { $0 + $1.estimatedBytes } }
}
```

`Sources/CreatorGraph/EvaluationReport.swift`:
```swift
import CreatorKernel

public struct EvaluationReport: Sendable {
    public var results: [NodeID: NodeResult]
    /// Nodes that actually ran this time (cache misses), in order.
    public var evaluatedNodes: [NodeID]
}
```

`Sources/CreatorGraph/CacheKey.swift`:
```swift
/// Identity of one node evaluation: its type, constants and upstream keys (spec §4.4).
/// Uses `Hasher`, which is seeded per process. That's fine because the cache lives in memory.
struct CacheKey: Hashable, Sendable {
    let digest: Int
}
```

`Sources/CreatorGraph/ResultCache.swift`:
```swift
import CreatorKernel

/// An LRU cache of successful node results, bounded by estimated bytes (spec §4.4).
struct ResultCache: Sendable {
    private struct Entry: Sendable {
        var result: NodeResult
        var node: NodeID
        var bytes: Int
        var lastUse: UInt64
    }

    let budgetBytes: Int
    private var entries: [CacheKey: Entry] = [:]
    private var useCounter: UInt64 = 0
    private(set) var totalBytes = 0

    init(budgetBytes: Int) {
        self.budgetBytes = budgetBytes
    }

    var count: Int { entries.count }

    mutating func result(for key: CacheKey) -> NodeResult? {
        guard var entry = entries[key] else { return nil }
        useCounter += 1
        entry.lastUse = useCounter
        entries[key] = entry
        return entry.result
    }

    mutating func insert(_ result: NodeResult, for key: CacheKey, node: NodeID) {
        if let old = entries[key] { totalBytes -= old.bytes }
        useCounter += 1
        let bytes = result.estimatedBytes
        entries[key] = Entry(result: result, node: node, bytes: bytes, lastUse: useCounter)
        totalBytes += bytes
        evictIfNeeded(protecting: key)
    }

    /// Drops entries of nodes that no longer exist in the graph.
    mutating func removeEntries(notIn nodes: Set<NodeID>) {
        for (key, entry) in entries where !nodes.contains(entry.node) {
            entries[key] = nil
            totalBytes -= entry.bytes
        }
    }

    private mutating func evictIfNeeded(protecting key: CacheKey) {
        while totalBytes > budgetBytes,
              let victim = entries.filter({ $0.key != key }).min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries[victim.key] = nil
            totalBytes -= victim.value.bytes
        }
    }
}
```

- [ ] **Step 4: Implement the evaluator**

`Sources/CreatorGraph/Evaluator.swift`:
```swift
import CreatorKernel

/// Evaluates the part of a graph a demand set needs, upstream first, caching each node's
/// result (spec §4.4). It throws only `CancellationError`. Every other failure becomes a
/// node state.
public actor Evaluator {
    private let registry: NodeRegistry
    private let kernel: any Kernel
    private var cache: ResultCache

    public init(registry: NodeRegistry, kernel: any Kernel, cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.registry = registry
        self.kernel = kernel
        self.cache = ResultCache(budgetBytes: cacheBudgetBytes)
    }

    public var cachedEntryCount: Int { cache.count }

    public func evaluate(_ graph: Graph, demand: Set<NodeID>) async throws -> EvaluationReport {
        cache.removeEntries(notIn: Set(graph.nodes.keys))
        let plan = graph.evaluationOrder(for: demand)
        let parameters = Dictionary(graph.parameters.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        var results: [NodeID: NodeResult] = [:]
        var keys: [NodeID: CacheKey] = [:]
        var evaluated: [NodeID] = []

        for id in plan.order {
            try Task.checkCancellation()
            guard let node = graph.nodes[id] else { continue }
            if plan.cyclic.contains(id) {
                results[id] = NodeResult(state: .error("This node is part of a cycle. Remove one of the wires in the loop."))
                continue
            }
            guard let definition = registry[node.typeID] else {
                results[id] = NodeResult(state: .error("Unknown node type “\(node.typeID)”. It's kept so the file isn't damaged."))
                continue
            }
            switch gather(node, definition, graph: graph, results: results, keys: keys, parameters: parameters) {
            case .blocked(let reason):
                results[id] = NodeResult(state: .idle(reason))
            case .failed(let message):
                results[id] = NodeResult(state: .error(message))
            case .ready(let inputs, let key):
                keys[id] = key
                if let cached = cache.result(for: key) {
                    results[id] = cached
                    continue
                }
                let result = try await run(definition, node: node, inputs: inputs, parameters: parameters)
                evaluated.append(id)
                results[id] = result
                if result.state.isSuccess {
                    cache.insert(result, for: key, node: id)
                }
            }
        }
        return EvaluationReport(results: results, evaluatedNodes: evaluated)
    }

    // MARK: - Inputs

    private enum Gathered {
        case ready([SocketName: Value], CacheKey)
        case blocked(String)
        case failed(String)
    }

    private func gather(_ node: Node, _ definition: any NodeDefinition.Type, graph: Graph,
                        results: [NodeID: NodeResult], keys: [NodeID: CacheKey],
                        parameters: [ParameterID: ConstantValue]) -> Gathered {
        var inputs: [SocketName: Value] = [:]
        var hasher = Hasher()
        hasher.combine(node.typeID)
        hasher.combine(node.typeVersion)
        // Every stored constant, including non-socket settings, sorted for determinism.
        for (name, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
            hasher.combine(name)
            hasher.combine(value)
        }
        if definition.readsParameters {
            for (id, value) in parameters.sorted(by: { $0.key < $1.key }) {
                hasher.combine(id)
                hasher.combine(value)
            }
        }

        for spec in definition.inputs {
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: spec.name)) {
                guard let upstream = results[link.from.node], upstream.state.isSuccess,
                      let value = upstream.outputs?[link.from.socket] else {
                    return .blocked("Waiting on “\(spec.name)”: the node wired into it has no result.")
                }
                guard let converted = value.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” needs a \(spec.type.rawValue).")
                }
                inputs[spec.name] = converted
                hasher.combine(spec.name)
                hasher.combine(keys[link.from.node])
                hasher.combine(link.from.socket)
            } else if let constant = node.inputValues[spec.name] ?? spec.defaultValue {
                guard let scalar = Scalar(constant)?.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” has a value of the wrong type.")
                }
                inputs[spec.name] = .one(scalar)
                hasher.combine(spec.defaultValue)
            } else if !spec.isOptional {
                return .blocked(NodeError.missingInput(spec.name).message)
            }
        }
        return .ready(inputs, CacheKey(digest: hasher.finalize()))
    }

    // MARK: - Running

    private func run(_ definition: any NodeDefinition.Type, node: Node, inputs: [SocketName: Value],
                     parameters: [ParameterID: ConstantValue]) async throws -> NodeResult {
        let plan = BroadcastPlan.make(inputs: inputs, specs: definition.inputs)
        let clock = ContinuousClock()
        let start = clock.now
        var collected: [SocketName: [Scalar]] = [:]
        var producedList: Set<SocketName> = []
        var warnings: [String] = []
        do {
            for item in 0..<plan.iterations {
                try Task.checkCancellation()
                let context = EvalContext(node: node, item: item, parameters: parameters)
                let outputs = try await definition.evaluate(plan.inputs(at: item), kernel: kernel, context: context)
                for spec in definition.outputs {
                    if let list = outputs.lists[spec.name] {
                        collected[spec.name, default: []] += list
                        producedList.insert(spec.name)
                    } else if let scalar = outputs.values[spec.name] {
                        collected[spec.name, default: []].append(scalar)
                    } else {
                        throw NodeError.invalidValue("The node didn't produce its “\(spec.name)” output.")
                    }
                }
                warnings += outputs.warnings
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return NodeResult(state: .error(Self.message(for: error)))
        }

        var outputs: [SocketName: Value] = [:]
        for spec in definition.outputs {
            let scalars = collected[spec.name] ?? []
            if plan.isSingle, !producedList.contains(spec.name), let only = scalars.first, scalars.count == 1 {
                outputs[spec.name] = .one(only)
            } else {
                outputs[spec.name] = .list(scalars)
            }
        }
        let unique = Array(Set(warnings)).sorted()
        let state: NodeState = unique.isEmpty ? .ok(duration: start.duration(to: clock.now)) : .warning(unique.joined(separator: "\n"))
        return NodeResult(state: state, outputs: outputs)
    }

    /// Plain-language text for any error a node can throw.
    public static func message(for error: any Error) -> String {
        switch error {
        case let error as KernelError: error.userMessage
        case let error as NodeError: error.message
        default: String(describing: error)
        }
    }
}
```

Note on the `else if let constant` branch: the hasher already combined every `inputValues` entry at the top, so this branch only needs to add `spec.defaultValue`. That way a changed default in a newer app version still invalidates the cache.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `swift test --filter EvaluatorTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): evaluate graphs with broadcasting and plain-language errors"
```

### Task 10: Evaluator caching and cancellation

**Files:**
- Test: `Tests/CreatorGraphTests/CacheTests.swift`
- Modify (only if a test exposes a bug): `Sources/CreatorGraph/Evaluator.swift`, `Sources/CreatorGraph/ResultCache.swift`

**Interfaces:**
- Consumes: `Evaluator`, `EvaluationReport.evaluatedNodes` and `cachedEntryCount` (Task 9), and `FakeKernel.operationLog` (Task 5).
- Produces: no new API. This task pins the cache and cancellation behaviour from spec §4.4.

- [ ] **Step 1: Write the tests**

`Tests/CreatorGraphTests/CacheTests.swift`:
```swift
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct CacheTests {
    @Test func unchangedGraphIsFullyCached() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)]), b = makeNode(AddNode.self)
        let g = graph([a, b], [link(a, "value", b, "a")])
        _ = try await evaluator.evaluate(g, demand: [b.id])
        let second = try await evaluator.evaluate(g, demand: [b.id])
        #expect(second.evaluatedNodes.isEmpty)
        #expect(second.results[b.id]?.outputs?["sum"]?.numbers == [1])
    }

    @Test func editingDownstreamKeepsUpstreamCached() async throws {
        let kernel = FakeKernel()
        let evaluator = Evaluator(registry: testRegistry, kernel: kernel)
        let box = makeNode(BoxNode.self)
        let add = makeNode(AddNode.self, ["b": .number(1)])
        var g = graph([box, add])
        _ = try await evaluator.evaluate(g, demand: [box.id, add.id])
        g.nodes[add.id]?.inputValues["b"] = .number(2)
        let second = try await evaluator.evaluate(g, demand: [box.id, add.id])
        #expect(second.evaluatedNodes == [add.id])
        #expect(await kernel.operationLog == ["extrude"])
    }

    @Test func editingUpstreamInvalidatesDownstream() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)]), b = makeNode(AddNode.self)
        var g = graph([a, b], [link(a, "value", b, "a")])
        _ = try await evaluator.evaluate(g, demand: [b.id])
        g.nodes[a.id]?.inputValues["value"] = .number(5)
        let second = try await evaluator.evaluate(g, demand: [b.id])
        #expect(Set(second.evaluatedNodes) == [a.id, b.id])
        #expect(second.results[b.id]?.outputs?["sum"]?.numbers == [5])
    }

    @Test func undoToAPreviousValueHitsTheCache() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self, ["value": .number(1)])
        var g = graph([a])
        _ = try await evaluator.evaluate(g, demand: [a.id])
        g.nodes[a.id]?.inputValues["value"] = .number(2)
        _ = try await evaluator.evaluate(g, demand: [a.id])
        g.nodes[a.id]?.inputValues["value"] = .number(1)
        #expect(try await evaluator.evaluate(g, demand: [a.id]).evaluatedNodes.isEmpty)
    }

    @Test func parameterEditsInvalidateParameterReaders() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        var parameter = GraphParameter(name: "Width", type: .number, value: .number(60))
        let node = makeNode(ParameterNode.self, ["parameter": .text(parameter.id.rawValue.uuidString)])
        _ = try await evaluator.evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        parameter.value = .number(90)
        let second = try await evaluator.evaluate(graph([node], parameters: [parameter]), demand: [node.id])
        #expect(second.results[node.id]?.outputs?["value"]?.numbers == [90])
    }

    @Test func errorsAreNotCached() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let fail = makeNode(FailNode.self)
        _ = try await evaluator.evaluate(graph([fail]), demand: [fail.id])
        #expect(try await evaluator.evaluate(graph([fail]), demand: [fail.id]).evaluatedNodes == [fail.id])
    }

    @Test func deletedNodesLeaveTheCache() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let a = makeNode(ConstantNode.self), b = makeNode(ConstantNode.self, ["value": .number(2)])
        _ = try await evaluator.evaluate(graph([a, b]), demand: [a.id, b.id])
        #expect(await evaluator.cachedEntryCount == 2)
        _ = try await evaluator.evaluate(graph([a]), demand: [a.id])
        #expect(await evaluator.cachedEntryCount == 1)
    }

    @Test func tinyBudgetEvictsLeastRecentlyUsed() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel(), cacheBudgetBytes: 300)
        let nodes = (0..<5).map { makeNode(ConstantNode.self, ["value": .number(Double($0))]) }
        _ = try await evaluator.evaluate(graph(nodes), demand: Set(nodes.map(\.id)))
        #expect(await evaluator.cachedEntryCount < 5)
    }

    @Test func cancellingStopsBetweenNodes() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let slow = makeNode(SlowNode.self), after = makeNode(AddNode.self)
        let g = graph([slow, after], [link(slow, "value", after, "a")])
        let task = Task { try await evaluator.evaluate(g, demand: [after.id]) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
```

- [ ] **Step 2: Run them**

Run: `swift test --filter CacheTests`
Expected: all PASS against Task 9's implementation. If one fails, fix the evaluator or cache (not the test), re-run, and describe the fix in the commit message.

- [ ] **Step 3: Commit**

```bash
git add Tests/CreatorGraphTests Sources/CreatorGraph
git commit -m "test(graph): pin evaluator caching, eviction and cancellation"
```

### Task 11: Commands and undo

**Files:**
- Create: `Sources/CreatorGraph/GraphCommand.swift`, `Sources/CreatorGraph/Graph+Commands.swift`, `Sources/CreatorGraph/UndoStack.swift`
- Test: `Tests/CreatorGraphTests/CommandTests.swift`

**Interfaces:**
- Consumes: `Graph`, `connectionProblem`, `GraphError` (Task 8).
- Produces:
  - `GraphCommand` with cases `addNode(Node)`, `removeNode(NodeID)`, `restoreNode(Node, links: [Link])`, `connect(Link)`, `disconnect(Link)`, `setInput(NodeID, SocketName, ConstantValue?)`, `move(NodeID, to: Vector2)`, `rename(NodeID, String)`, `setOutput(NodeID, Bool)`, `addParameter(GraphParameter)`, `removeParameter(ParameterID)`, `setParameter(ParameterID, ConstantValue)` and `batch([GraphCommand])`, plus `touchedNodes: Set<NodeID>`
  - `mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand`, which returns the inverse
  - `UndoStack` with `record(forward:inverse:coalescingKey:)`, `endCoalescing()`, `takeUndo() -> Entry?`, `takeRedo() -> Entry?`, `canUndo` and `canRedo`

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/CommandTests.swift`:
```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct CommandTests {
    /// Applies `command`, then its inverse, and checks the graph is back where it started.
    func expectRoundTrip(_ command: GraphCommand, on start: Graph) throws {
        var g = start
        let inverse = try g.apply(command, registry: testRegistry)
        #expect(g != start)
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
    }

    @Test func everyCommandIsReversible() throws {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        let base = graph([a, b], [link(a, "value", b, "a")])
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        try expectRoundTrip(.addNode(makeNode(ConstantNode.self)), on: base)
        try expectRoundTrip(.removeNode(a.id), on: base)
        try expectRoundTrip(.disconnect(link(a, "value", b, "a")), on: base)
        try expectRoundTrip(.connect(link(a, "value", b, "b")), on: base)
        try expectRoundTrip(.setInput(b.id, "b", .number(4)), on: base)
        try expectRoundTrip(.move(a.id, to: Vector2(5, 5)), on: base)
        try expectRoundTrip(.rename(a.id, "Width"), on: base)
        try expectRoundTrip(.setOutput(b.id, true), on: base)
        try expectRoundTrip(.addParameter(parameter), on: base)
        try expectRoundTrip(.batch([.setInput(b.id, "b", .number(1)), .move(b.id, to: Vector2(1, 1))]), on: base)
    }

    @Test func removingANodeRemovesItsLinksAndUndoRestoresThem() throws {
        let a = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        var g = graph([a, b], [link(a, "value", b, "a")])
        let inverse = try g.apply(.removeNode(a.id), registry: testRegistry)
        #expect(g.links.isEmpty)
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g.links == [link(a, "value", b, "a")])
    }

    @Test func connectingAnOccupiedInputReplacesItsWire() throws {
        let a = makeNode(ConstantNode.self), c = makeNode(ConstantNode.self), b = makeNode(AddNode.self)
        var g = graph([a, b, c], [link(a, "value", b, "a")])
        let inverse = try g.apply(.connect(link(c, "value", b, "a")), registry: testRegistry)
        #expect(g.links == [link(c, "value", b, "a")])
        _ = try g.apply(inverse, registry: testRegistry)
        #expect(g.links == [link(a, "value", b, "a")])
    }

    @Test func invalidConnectionIsRefused() {
        let box = makeNode(BoxNode.self), add = makeNode(AddNode.self)
        var g = graph([box, add])
        #expect(throws: GraphError.invalidConnection(.typeMismatch(from: .solid, to: .number))) {
            try g.apply(.connect(link(box, "solid", add, "a")), registry: testRegistry)
        }
    }

    @Test(arguments: [ConstantValue.number(.nan), .number(.infinity), .vector(Vector3(0, .nan, 0))])
    func nonFiniteInputIsRejected(_ value: ConstantValue) {
        let a = makeNode(ConstantNode.self)
        var g = graph([a])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.setInput(a.id, "value", value), registry: testRegistry)
        }
    }

    @Test func nonFiniteParameterIsRejected() throws {
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6))
        var g = graph([], parameters: [parameter])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try g.apply(.setParameter(parameter.id, .number(.nan)), registry: testRegistry)
        }
    }

    @Test func commandsOnMissingNodesThrow() {
        var g = Graph()
        let ghost = makeNode(ConstantNode.self)
        #expect(throws: GraphError.nodeNotFound(ghost.id)) { try g.apply(.move(ghost.id, to: .zero), registry: testRegistry) }
    }

    @Test func coalescedDragUndoesInOneStep() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .setInput(id, "value", .number(2)), inverse: .setInput(id, "value", .number(1)), coalescingKey: "drag")
        stack.record(forward: .setInput(id, "value", .number(3)), inverse: .setInput(id, "value", .number(2)), coalescingKey: "drag")
        stack.endCoalescing()
        #expect(stack.undoEntries.count == 1)
        let entry = stack.takeUndo()
        #expect(entry?.inverse == .setInput(id, "value", .number(1)))
        #expect(entry?.forward == .setInput(id, "value", .number(3)))
    }

    @Test func newEditAfterUndoClearsRedo() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .rename(id, "A"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        _ = stack.takeUndo()
        #expect(stack.canRedo)
        stack.record(forward: .rename(id, "B"), inverse: .rename(id, "Constant"), coalescingKey: nil)
        #expect(!stack.canRedo)
    }

    @Test func sameKeyAfterEndCoalescingStartsANewStep() {
        let id = makeNode(ConstantNode.self).id
        var stack = UndoStack()
        stack.record(forward: .setInput(id, "value", .number(2)), inverse: .setInput(id, "value", .number(1)), coalescingKey: "drag")
        stack.endCoalescing()
        stack.record(forward: .setInput(id, "value", .number(3)), inverse: .setInput(id, "value", .number(2)), coalescingKey: "drag")
        #expect(stack.undoEntries.count == 2)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter CommandTests`
Expected: compile errors, "cannot find 'GraphCommand' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorGraph/GraphCommand.swift`:
```swift
import CreatorGeometry
import CreatorKernel

/// Every edit to a graph. Applying one returns its inverse (spec §4.5).
public indirect enum GraphCommand: Sendable, Equatable {
    case addNode(Node)
    case removeNode(NodeID)
    /// Re-inserts a removed node together with the links that were removed with it.
    case restoreNode(Node, links: [Link])
    /// Connects, replacing any wire already in `link.to`.
    case connect(Link)
    case disconnect(Link)
    /// Sets (or with `nil`, clears) a stored input constant or setting.
    case setInput(NodeID, SocketName, ConstantValue?)
    case move(NodeID, to: Vector2)
    case rename(NodeID, String)
    case setOutput(NodeID, Bool)
    case addParameter(GraphParameter)
    case removeParameter(ParameterID)
    case setParameter(ParameterID, ConstantValue)
    case batch([GraphCommand])

    /// Nodes whose results this command can change (for marking them `.evaluating`).
    public var touchedNodes: Set<NodeID> {
        switch self {
        case .addNode(let node), .restoreNode(let node, _): [node.id]
        case .removeNode(let id), .setInput(let id, _, _), .setOutput(let id, _): [id]
        case .connect(let link), .disconnect(let link): [link.to.node]
        case .move, .rename, .addParameter, .removeParameter, .setParameter: []
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.touchedNodes) }
        }
    }
}
```

`Sources/CreatorGraph/Graph+Commands.swift`:
```swift
import CreatorKernel

extension Graph {
    /// Applies `command` and returns the command that undoes it. On error the graph is unchanged.
    @discardableResult
    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .addNode(let node):
            guard nodes[node.id] == nil else { throw .duplicateNode(node.id) }
            nodes[node.id] = node
            return .removeNode(node.id)

        case .removeNode(let id):
            guard let node = nodes[id] else { throw .nodeNotFound(id) }
            let removed = links.filter { $0.from.node == id || $0.to.node == id }
            links.removeAll { $0.from.node == id || $0.to.node == id }
            nodes[id] = nil
            return .restoreNode(node, links: removed)

        case .restoreNode(let node, let restoredLinks):
            guard nodes[node.id] == nil else { throw .duplicateNode(node.id) }
            nodes[node.id] = node
            links += restoredLinks
            return .removeNode(node.id)

        case .connect(let link):
            if let problem = connectionProblem(from: link.from, to: link.to, registry: registry) {
                throw .invalidConnection(problem)
            }
            let replaced = incomingLink(to: link.to)
            links.removeAll { $0.to == link.to }
            links.append(link)
            if let replaced {
                return .batch([.disconnect(link), .connect(replaced)])
            }
            return .disconnect(link)

        case .disconnect(let link):
            guard links.contains(link) else { throw .linkNotFound }
            links.removeAll { $0 == link }
            return .connect(link)

        case .setInput(let id, let socket, let value):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            if let value, !value.isFinite { throw .invalidValue("Enter a finite number.") }
            let old = node.inputValues[socket]
            node.inputValues[socket] = value
            nodes[id] = node
            return .setInput(id, socket, old)

        case .move(let id, let position):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.position
            node.position = position
            nodes[id] = node
            return .move(id, to: old)

        case .rename(let id, let name):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.name
            node.name = name
            nodes[id] = node
            return .rename(id, old)

        case .setOutput(let id, let isOutput):
            guard var node = nodes[id] else { throw .nodeNotFound(id) }
            let old = node.isOutput
            node.isOutput = isOutput
            nodes[id] = node
            return .setOutput(id, old)

        case .addParameter(let parameter):
            parameters.append(parameter)
            return .removeParameter(parameter.id)

        case .removeParameter(let id):
            guard let index = parameters.firstIndex(where: { $0.id == id }) else { throw .parameterNotFound(id) }
            let removed = parameters.remove(at: index)
            return .addParameter(removed)

        case .setParameter(let id, let value):
            guard let index = parameters.firstIndex(where: { $0.id == id }) else { throw .parameterNotFound(id) }
            guard value.isFinite else { throw .invalidValue("Enter a finite number.") }
            let old = parameters[index].value
            parameters[index].value = value
            return .setParameter(id, old)

        case .batch(let commands):
            let snapshot = self
            var inverses: [GraphCommand] = []
            do {
                for command in commands {
                    inverses.append(try apply(command, registry: registry))
                }
            } catch {
                self = snapshot
                throw error
            }
            return .batch(Array(inverses.reversed()))
        }
    }
}
```

Note: undoing `removeParameter` appends the parameter at the end, not at its old index. Parameter order is display-only, and the round-trip test uses `addParameter`, whose inverse is `removeParameter`.

`Sources/CreatorGraph/UndoStack.swift`:
```swift
/// Undo history of applied commands, with slider-drag coalescing (spec §4.5).
public struct UndoStack: Sendable {
    public struct Entry: Sendable, Equatable {
        /// What redo re-applies: the latest command of a coalesced run.
        public var forward: GraphCommand
        /// What undo applies: the inverse of the first command of a coalesced run.
        public var inverse: GraphCommand
        public var coalescingKey: String?
    }

    public private(set) var undoEntries: [Entry] = []
    public private(set) var redoEntries: [Entry] = []
    private var isCoalescingOpen = false

    public init() {}

    public var canUndo: Bool { !undoEntries.isEmpty }
    public var canRedo: Bool { !redoEntries.isEmpty }

    /// Records an applied command. Consecutive records with the same non-nil key, with no
    /// `endCoalescing()` between them, merge into one entry that keeps the first inverse.
    public mutating func record(forward: GraphCommand, inverse: GraphCommand, coalescingKey: String?) {
        redoEntries.removeAll()
        if let key = coalescingKey, isCoalescingOpen, let last = undoEntries.last, last.coalescingKey == key {
            undoEntries[undoEntries.count - 1].forward = forward
        } else {
            undoEntries.append(Entry(forward: forward, inverse: inverse, coalescingKey: coalescingKey))
        }
        isCoalescingOpen = coalescingKey != nil
    }

    /// Ends the current drag, so the next record starts a new undo step.
    public mutating func endCoalescing() {
        isCoalescingOpen = false
    }

    public mutating func takeUndo() -> Entry? {
        isCoalescingOpen = false
        guard let entry = undoEntries.popLast() else { return nil }
        redoEntries.append(entry)
        return entry
    }

    public mutating func takeRedo() -> Entry? {
        isCoalescingOpen = false
        guard let entry = redoEntries.popLast() else { return nil }
        undoEntries.append(entry)
        return entry
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CommandTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add reversible graph commands and coalescing undo stack"
```

### Task 12: `.mcgraph` file format

**Files:**
- Create: `Sources/CreatorGraph/{DockSide,ViewState,GraphFile,GraphFileError,GraphFileIO}.swift`
- Test: `Tests/CreatorGraphTests/FileTests.swift`

**Interfaces:**
- Consumes: `Graph` (Task 8) and `NodeRegistry.subscript`/`migrate` (Task 7).
- Produces:
  - `DockSide` (`left`, `bottom`, `hidden`)
  - `ViewState` (`dock`, `canvasOffset: Vector2`, `canvasZoom: Double`, each tolerant of missing keys)
  - `GraphFile(formatVersion:graph:viewState:)` with `currentFormatVersion = 1`
  - `GraphFileError.newerFormat(Int)`
  - `GraphFileIO.encode(_:) throws -> Data` (pretty-printed, sorted keys) and `GraphFileIO.decode(_:registry:) throws -> GraphFile`, which migrates nodes and keeps unknown ones untouched

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/FileTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct FileTests {
    @Test func graphRoundTrips() throws {
        let a = makeNode(ConstantNode.self, ["value": .number(6)]), b = makeNode(AddNode.self, output: true)
        let parameter = GraphParameter(name: "Wall", type: .number, value: .number(6), min: 1, max: 20)
        let file = GraphFile(graph: graph([a, b], [link(a, "value", b, "a")], parameters: [parameter]),
                             viewState: ViewState(dock: .bottom, canvasOffset: Vector2(10, 20), canvasZoom: 1.5))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
    }

    @Test func encodingIsDeterministic() throws {
        let file = GraphFile(graph: graph([makeNode(ConstantNode.self), makeNode(AddNode.self)]))
        #expect(try GraphFileIO.encode(file) == GraphFileIO.encode(file))
    }

    @Test func unknownNodeRoundTrips() throws {
        var future = makeNode(ConstantNode.self, ["mystery": .text("keep me")])
        future.typeID = "future.node"
        future.typeVersion = 7
        let file = GraphFile(graph: graph([future]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded.graph.nodes[future.id] == future)
    }

    @Test func oldNodeVersionsAreMigratedOnLoad() throws {
        var old = makeNode(VersionedNode.self, ["old": .number(3)])
        old.typeVersion = 1
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(GraphFile(graph: graph([old]))), registry: testRegistry)
        let migrated = try #require(decoded.graph.nodes[old.id])
        #expect(migrated.typeVersion == 2)
        #expect(migrated.inputValues == ["value": .number(3)])
    }

    @Test func newerFormatIsRefusedWithItsVersion() throws {
        let json = #"{"formatVersion": 99, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        #expect(throws: GraphFileError.newerFormat(99)) {
            try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        }
    }

    @Test func missingViewStateUsesDefaults() throws {
        let json = #"{"formatVersion": 1, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.viewState == ViewState())
        #expect(file.viewState.dock == .left)
    }

    @Test func malformedJSONThrowsInsteadOfCrashing() {
        #expect(throws: (any Error).self) { try GraphFileIO.decode(Data("{ not json".utf8), registry: testRegistry) }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter FileTests`
Expected: compile errors, "cannot find 'GraphFile' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorGraph/DockSide.swift`:
```swift
/// Where the graph panel sits (spec §6.1).
public enum DockSide: String, Sendable, Codable, CaseIterable {
    case left, bottom, hidden
}
```

`Sources/CreatorGraph/ViewState.swift`:
```swift
import CreatorGeometry

/// Editor state saved with a document. Every key is optional when decoding, so files stay
/// readable as later milestones add fields (such as the camera in M4).
public struct ViewState: Sendable, Codable, Equatable {
    public var dock: DockSide
    public var canvasOffset: Vector2
    public var canvasZoom: Double

    public init(dock: DockSide = .left, canvasOffset: Vector2 = .zero, canvasZoom: Double = 1) {
        self.dock = dock
        self.canvasOffset = canvasOffset
        self.canvasZoom = canvasZoom
    }

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasOffset = try container.decodeIfPresent(Vector2.self, forKey: .canvasOffset) ?? .zero
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
    }
}
```

`Sources/CreatorGraph/GraphFile.swift`:
```swift
/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var graph: Graph
    public var viewState: ViewState

    public init(formatVersion: Int = GraphFile.currentFormatVersion, graph: Graph = Graph(), viewState: ViewState = ViewState()) {
        self.formatVersion = formatVersion
        self.graph = graph
        self.viewState = viewState
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, graph, viewState }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        graph = try container.decode(Graph.self, forKey: .graph)
        viewState = try container.decodeIfPresent(ViewState.self, forKey: .viewState) ?? ViewState()
    }
}
```

`Sources/CreatorGraph/GraphFileError.swift`:
```swift
public enum GraphFileError: Error, Equatable, Sendable {
    /// The file was written by a newer MetalCreator.
    case newerFormat(Int)
}
```

`Sources/CreatorGraph/GraphFileIO.swift`:
```swift
import Foundation

/// Reads and writes `.mcgraph` JSON.
public enum GraphFileIO {
    public static func encode(_ file: GraphFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Decodes and migrates old node versions. Unknown node types are kept as-is.
    public static func decode(_ data: Data, registry: NodeRegistry) throws -> GraphFile {
        var file = try JSONDecoder().decode(GraphFile.self, from: data)
        guard file.formatVersion <= GraphFile.currentFormatVersion else {
            throw GraphFileError.newerFormat(file.formatVersion)
        }
        for (id, node) in file.graph.nodes {
            guard let definition = registry[node.typeID], node.typeVersion < definition.typeVersion else { continue }
            var migrated = definition.migrate(node, from: node.typeVersion)
            migrated.typeVersion = definition.typeVersion
            file.graph.nodes[id] = migrated
        }
        return file
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter FileTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add .mcgraph file format with node migration"
```

### Task 13: `DocumentModel`

**Files:**
- Create: `Sources/CreatorGraph/DocumentModel.swift`
- Test: `Tests/CreatorGraphTests/DocumentModelTests.swift`

**Interfaces:**
- Consumes: `Evaluator` (Task 9), `GraphCommand`/`UndoStack` (Task 11), `GraphFile`/`GraphFileIO` (Task 12).
- Produces `@MainActor @Observable public final class DocumentModel` with:
  - `init(file: GraphFile = GraphFile(), registry:kernel:cacheBudgetBytes:)` and `convenience init(data: Data, registry:kernel:) throws`
  - read-only properties `graph`, `results: [NodeID: NodeResult]`, `lastGoodOutputs: [NodeID: [SocketName: Value]]`, `isEvaluating`
  - mutable `previewNode: NodeID?` and `viewState: ViewState`
  - `canUndo`, `canRedo`
  - `perform(_:coalescingKey:) throws(GraphError)`, `endCoalescing()`, `undo()`, `redo()`
  - `fileData() throws -> Data`
  - `waitForEvaluation() async`, a test and app hook that returns once the latest evaluation has been applied

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorGraphTests/DocumentModelTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

@MainActor
struct DocumentModelTests {
    func model(_ nodes: [Node], _ links: [Link] = []) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph(nodes, links)), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func outputsAreEvaluatedOnOpen() async {
        let a = makeNode(ConstantNode.self, ["value": .number(4)], output: true)
        let document = model([a])
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [4])
        #expect(!document.isEvaluating)
    }

    @Test func nonOutputNodesAreNotEvaluated() async {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        await document.waitForEvaluation()
        #expect(document.results[a.id] == nil)
    }

    @Test func previewNodeJoinsTheDemand() async {
        let a = makeNode(ConstantNode.self, ["value": .number(2)])
        let document = model([a])
        document.previewNode = a.id
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [2])
    }

    @Test func editsReevaluateAndUndoRestores() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(1)], output: true)
        let document = model([a])
        try document.perform(.setInput(a.id, "value", .number(9)))
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [9])
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.outputs?["value"]?.numbers == [1])
        #expect(document.canRedo)
    }

    @Test func lastGoodOutputSurvivesAnError() async throws {
        let box = makeNode(BoxNode.self, output: true)
        let document = model([box])
        await document.waitForEvaluation()
        #expect(document.lastGoodOutputs[box.id] != nil)
        try document.perform(.setInput(box.id, "distance", .number(-1)))
        await document.waitForEvaluation()
        guard case .error? = document.results[box.id]?.state else { Issue.record("expected error"); return }
        #expect(document.lastGoodOutputs[box.id] != nil)
    }

    @Test func staleEvaluationNeverOverwritesNewerResult() async throws {
        let slow = makeNode(SlowNode.self, ["value": .number(1)], output: true)
        let document = model([slow])
        for value in 2...6 {
            try document.perform(.setInput(slow.id, "value", .number(Double(value))), coalescingKey: "drag")
            try await Task.sleep(for: .milliseconds(20))
        }
        document.endCoalescing()
        await document.waitForEvaluation()
        #expect(document.results[slow.id]?.outputs?["value"]?.numbers == [6])
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[slow.id]?.outputs?["value"]?.numbers == [1])
    }

    @Test func deletingThePreviewNodeClearsThePreview() async throws {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        document.previewNode = a.id
        try document.perform(.removeNode(a.id))
        #expect(document.previewNode == nil)
        await document.waitForEvaluation()
        #expect(document.results[a.id] == nil)
    }

    @Test func editsMarkAffectedNodesAsEvaluating() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(1)], output: true)
        let document = model([a])
        await document.waitForEvaluation()
        try document.perform(.setInput(a.id, "value", .number(2)))
        #expect(document.results[a.id]?.state == .evaluating)
        await document.waitForEvaluation()
        #expect(document.results[a.id]?.state.isSuccess == true)
    }

    @Test func refusedCommandLeavesNoUndoStep() {
        let a = makeNode(ConstantNode.self)
        let document = model([a])
        #expect(throws: GraphError.self) { try document.perform(.setInput(a.id, "value", .number(.nan))) }
        #expect(!document.canUndo)
    }

    @Test func saveAndReopenPreservesTheDocument() async throws {
        let a = makeNode(ConstantNode.self, ["value": .number(3)], output: true)
        let document = model([a])
        document.viewState.dock = .bottom
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.graph == document.graph)
        #expect(reopened.viewState.dock == .bottom)
        await reopened.waitForEvaluation()
        #expect(reopened.results[a.id]?.outputs?["value"]?.numbers == [3])
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter DocumentModelTests`
Expected: compile error, "cannot find 'DocumentModel' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorGraph/DocumentModel.swift`:
```swift
import CreatorKernel
import Foundation
import Observation

/// One open document: the graph, its undo history and its latest evaluation. The UI observes
/// this. Every edit goes through `perform(_:coalescingKey:)`.
@MainActor
@Observable
public final class DocumentModel {
    public private(set) var graph: Graph
    public private(set) var results: [NodeID: NodeResult] = [:]
    /// The last successful outputs of each node. The viewport ghosts these when a node errors (spec §4.4).
    public private(set) var lastGoodOutputs: [NodeID: [SocketName: Value]] = [:]
    public private(set) var isEvaluating = false
    public var viewState: ViewState

    /// The node shown in "Selected node" preview mode. It joins the evaluation demand.
    public var previewNode: NodeID? = nil {
        didSet {
            if oldValue != previewNode { scheduleEvaluation() }
        }
    }

    public let registry: NodeRegistry
    private var undoStack = UndoStack()
    @ObservationIgnored private let evaluator: Evaluator
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(file: GraphFile = GraphFile(), registry: NodeRegistry, kernel: any Kernel,
                cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.graph = file.graph
        self.viewState = file.viewState
        self.registry = registry
        self.evaluator = Evaluator(registry: registry, kernel: kernel, cacheBudgetBytes: cacheBudgetBytes)
        scheduleEvaluation()
    }

    public convenience init(data: Data, registry: NodeRegistry, kernel: any Kernel) throws {
        self.init(file: try GraphFileIO.decode(data, registry: registry), registry: registry, kernel: kernel)
    }

    public var canUndo: Bool { undoStack.canUndo }
    public var canRedo: Bool { undoStack.canRedo }

    /// Applies an edit. Pass the same `coalescingKey` for every step of a slider or handle
    /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step.
    public func perform(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
        let inverse = try graph.apply(command, registry: registry)
        undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey)
        didChange(touching: command.touchedNodes)
    }

    public func endCoalescing() {
        undoStack.endCoalescing()
    }

    public func undo() {
        guard let entry = undoStack.takeUndo() else { return }
        replay(entry.inverse)
    }

    public func redo() {
        guard let entry = undoStack.takeRedo() else { return }
        replay(entry.forward)
    }

    public func fileData() throws -> Data {
        try GraphFileIO.encode(GraphFile(graph: graph, viewState: viewState))
    }

    /// Returns once the most recently scheduled evaluation has finished and been applied.
    public func waitForEvaluation() async {
        while let task = evaluationTask {
            await task.value
            if evaluationTask == task { return }
        }
    }

    // MARK: - Evaluation

    private var demand: Set<NodeID> {
        var ids = Set(graph.nodes.values.filter(\.isOutput).map(\.id))
        if let previewNode { ids.insert(previewNode) }
        return ids
    }

    private func replay(_ command: GraphCommand) {
        do {
            try graph.apply(command, registry: registry)
        } catch {
            // Undo and redo replay commands that were valid when recorded, so this means
            // the history is out of step with the graph.
            assertionFailure("Undo history could not be replayed: \(error)")
        }
        didChange(touching: command.touchedNodes)
    }

    private func didChange(touching touched: Set<NodeID>) {
        let existing = Set(graph.nodes.keys)
        results = results.filter { existing.contains($0.key) }
        lastGoodOutputs = lastGoodOutputs.filter { existing.contains($0.key) }
        for id in graph.downstreamClosure(of: touched) where results[id] != nil {
            results[id]?.state = .evaluating
        }
        if let previewNode, !existing.contains(previewNode) {
            self.previewNode = nil  // didSet schedules the evaluation
        } else {
            scheduleEvaluation()
        }
    }

    private func scheduleEvaluation() {
        evaluationTask?.cancel()
        generation += 1
        let current = generation
        let snapshot = graph
        let demand = demand
        let evaluator = evaluator
        isEvaluating = true
        evaluationTask = Task {
            let report: EvaluationReport
            do {
                report = try await evaluator.evaluate(snapshot, demand: demand)
            } catch {
                return  // Cancelled: a newer generation is already scheduled.
            }
            guard current == self.generation else { return }
            self.apply(report)
        }
    }

    private func apply(_ report: EvaluationReport) {
        for (id, result) in report.results {
            results[id] = result
            if result.state.isSuccess, let outputs = result.outputs {
                lastGoodOutputs[id] = outputs
            }
        }
        isEvaluating = false
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter DocumentModelTests`
Expected: all PASS. If `staleEvaluationNeverOverwritesNewerResult` is flaky, the generation check is being bypassed: a task is applying results after a newer `scheduleEvaluation()`. Fix the model, never the test's timing.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: every suite PASSES, with no warnings except OCCT linker "built for newer macOS" notices.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests
git commit -m "feat(graph): add observable DocumentModel with cancellable evaluation"
```

### Task 14: Project guidance and milestone close

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`
- Create: `docs/metalui-gaps.md`

**Interfaces:**
- Consumes: the finished M0–M1 code.
- Produces: up-to-date agent guidance, and the gap log MetalUI's design agent reads (spec §9).

- [ ] **Step 1: Rewrite the "Project state" and "Toolchain constraints" sections of `CLAUDE.md`**

Replace everything from `## Project state` down to (not including) `## Commands` with:
```markdown
## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe) and M1 (graph engine) are done.

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
- `CreatorKernel`: the `Kernel` protocol, `Solid`, tagged topology tables, `FakeKernel` for tests.
- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and its Swift wrapper. **The only code that may touch OCCT.**
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here.
```
Replace the toolchain lines `swift-tools-version: 6.3` with `swift-tools-version: 6.4` and `Local toolchain: Apple Swift 6.3.2` with `Local toolchain: Apple Swift 6.4`. Then add:
```markdown
- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
  Linker warnings about dylibs built for a newer macOS are expected.
```
Make the same edits in `AGENTS.md`, keeping its two Codex-specific header lines.

- [ ] **Step 2: Create the gap log**

`docs/metalui-gaps.md`:
```markdown
# MetalUI gaps hit by MetalCreator

MetalUI's design agent reads this file (MetalUI item C7). Each entry gives a concrete use case:
which button or gesture, which coordinates, what we do in the meantime.

## Reported 2026-10-07 (C7)

1. **Scroll wheel / trackpad scroll on an element.** Viewport: two-finger scroll zooms toward the
   cursor (needs the cursor position in the element's local points, plus phase and momentum).
   Graph panel: two-finger scroll pans and ⌘-scroll zooms. Stopgap: +/− keys and header zoom buttons.
2. **Magnify and rotate gestures.** Pinch zooms the viewport and graph about the pinch centre.
   Stopgap: none (keys only).
3. **Middle and other buttons, and right-drag.** Viewport: middle-drag pans, right-drag orbits.
   Stopgap: primary-drag orbits, Shift-drag pans.
4. **Click and tap location.** Viewport picking and the right-click face menu need the click point
   in local coordinates to read the ID buffer pixel. Stopgap: zero-distance `DragGesture` if allowed.
5. **Cursor from content, and modifiers during a drag.** Crosshair while picking, grab hand while
   panning, and ⌥ held mid-drag to duplicate nodes.
```

- [ ] **Step 3: Verify**

Run: `swift build 2>&1 | grep -i "warning:" | grep -v "built for newer macOS" ; swift test`
Expected: no warnings other than the OCCT macOS-version notices, and all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md AGENTS.md docs/metalui-gaps.md
git commit -m "docs: describe module boundaries and start the MetalUI gap log"
```

---

## What comes next (separate plans)

- **M2: Kernel operations, tags and history.** `OCCTKernel: Kernel` built on `OCCTShape`: topology tables from OCCT, tag propagation through `Generated`/`Modified`, the conformance suite, and naming-stability tests.
- **M3: the 26 nodes.** Including Edges by Tag, Direction and Filter, with drift warnings.
- **M4: viewport**, **M5: graph panel**, **M6: app shell and acceptance demo**, **M7: measurements.**

Each plan is written after the previous milestone lands, against the real code.
