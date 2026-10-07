# MetalCreator M2: OCCT Kernel, Tags and History — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `OCCTKernel: Kernel` on top of OpenCascade. It covers every protocol operation (extrude, revolve, loft, boolean, transform, fillet, chamfer, tessellate, export), builds real topology tables from OCCT, and carries face tags through OCCT's history so edge selections survive design changes. A kernel conformance suite and naming-stability tests prove it.

**Architecture:**
- The C shim (`COCCT`) grows from a probe into a small C API:
  - shims take profiles and planes as plain C structs
  - every shape-building call returns an owned shape plus a flat array of **history records** that say where each output face came from
  - topology and meshes come back as C arrays, each with its own free function
- `CreatorOCCT` (Swift) converts those into `Topology`/`DisplayMesh` and applies the tag rules of spec §5.3 in one pure function (`OCCTTagger`). It exposes `public actor OCCTKernel`.
- Nothing outside `CreatorOCCT` changes, except one protocol addition in `CreatorKernel`: `properties(of:)`, which reports volume, surface area and centroid so the conformance suite can check geometry through `any Kernel`.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, C++17, OpenCascade 7.9.3 (Homebrew).

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§5.1–5.3, the Errata (M0–M1) section, §7.4 M2, §8). Also read `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`; this plan discharges its "Before the first M2 OCCT operation" list.

**Decisions made in this plan:**
- **Edge and face IDs are OCCT map order.** `FaceID(n)` is index `n + 1` in `TopExp::MapShapes(shape, TopAbs_FACE)`, and the same goes for edges. That order is deterministic for a given shape, so a `Solid`'s IDs and its OCCT shape always agree.
- **Faces OCCT history does not explain** get the fallback tag `TopoRole.unnamed(face:)`. It is unstable by design, but it means a face never has an empty tag set.
- **Circular edges report their axis as `direction`.** That's what `EdgeInfo` documents and what OCCT gives. So a "parallel to Z" rule must also require `kind == .line`. This is an M3 note, and FakeKernel needs no change.
- **Extrude, revolve and loft fix inverted solids.** If OCCT returns a negative volume because of the profile's winding, the shim reverses the shape.
- **Fuse and cut call `SimplifyResult()`**, so coplanar faces merge. That keeps the L-flange union filletable, and history is updated by OCCT.
- **`OCCTKernel` uses the default actor executor.** Long OCCT calls occupy a cooperative-pool thread. That's acceptable for the slice (one kernel call at a time), and the M7 measurements will tell us whether it isn't.
- **Symmetric extrude** shifts the profile plane by −d/2 in Swift and then extrudes by d.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency. No `@unchecked Sendable`. Any `nonisolated(unsafe)` needs a comment explaining why it's sound.
- Tests use **Swift Testing** only.
- Units are millimetres, as `Double`.
- **Only `CreatorOCCT` may `import COCCT`.** No OCCT type or name appears outside `Sources/COCCT` and `Sources/CreatorOCCT`.
- **No C++ exception may cross into Swift.** Every exported shim function runs its body inside `guarded(...)` or `queried(...)`.
- **Every C allocation handed to Swift has a matching `*_free` function**, and Swift calls it in a `defer`.
- One type per Swift file, named after the type. Extensions go in `Type+Purpose.swift`. Test fixture files may hold several helpers and must say so in a header comment.
- `Kernel` conformers call `try Task.checkCancellation()` as the **first statement** of every operation.
- User-facing errors are `KernelError` with plain-language text. Raw OCCT messages never reach users unmapped.
- Avoid force unwraps and force `try`. No GCD. No third-party Swift packages.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected noise: linker warnings that OCCT dylibs were "built for newer macOS version". After Task 2, OCCT should print **nothing** to stdout during tests.

## Review Focus

These are inputs the spec implies but no other task's tests exercise. Each has a test in the named task.

1. **Bad profiles** (segments that don't connect, a zero-length line, an open loop). The user should see a plain error, never a crash or a hang. *Task 3: `openProfileIsRejected`, `zeroLengthLineIsAPlainError`.*
2. **A boolean with nothing to cut, or an empty intersection.** Subtracting a tool that misses returns the plate unchanged with its tags. An empty intersection is a plain error. *Task 4: `subtractingAMissingToolKeepsThePlate`, `emptyIntersectionIsAPlainError`.*
3. **An impossible fillet** gives `filletFailed` with a readable message, and the kernel works normally on the next call. *Task 5: `impossibleFilletFailsCleanlyAndKernelRecovers`.*
4. **Faces with no history** get the `.unnamed` fallback. No face anywhere has an empty tag set. *Task 3: `taggerFallsBackToUnnamed`; Task 8: `noFaceIsUntaggedOrUnnamedInTheBracket`.*
5. **Calls queued by a superseded evaluation** are skipped: an operation called from a cancelled task throws `CancellationError` before touching OCCT. *Task 3: `cancelledCallIsSkipped`.*

---

## File Structure

```
Package.swift                                     CreatorOCCT gains CreatorKernel/CreatorGeometry deps (Task 2)
Sources/CreatorKernel/
  SolidProperties.swift                           (Task 1) volume, surface area, centroid
  Kernel.swift                                    (Task 1) + properties(of:)
  TopoRole.swift                                  (Task 1) + .unnamed(face:), Codable
  TopoRole+Codable.swift, EdgeKey+Codable.swift   (Task 1)
  TopoTag.swift                                   (Task 1) + Codable
  FakeKernel.swift                                (Task 1) + properties(of:)
Sources/COCCT/
  include/cocct.h                                 public C API (extended in Tasks 2–7)
  cocct_internal.hpp                              (Task 2) shared C++ helpers: guarded, queried, map_of, history builder
  cocct.cpp                                       existing probe functions (Task 2: helpers moved out, STEP writer uses init)
  cocct_inspect.cpp                               (Task 2) initialize, properties, topology
  cocct_build.cpp                                 (Task 3, 6) profile → face, extrude, revolve, loft
  cocct_ops.cpp                                   (Task 4, 5) boolean, transform, fillet, chamfer
  cocct_mesh.cpp                                  (Task 7) tessellate, compound, read STEP
Sources/CreatorOCCT/
  OCCTProperties.swift                            (Task 2)
  OCCTRawTopology.swift                           (Task 2) raw faces/edges read from the shim
  OCCTShape+Inspect.swift                         (Task 2)
  OCCTHistoryRecord.swift                         (Task 3)
  OCCTProfile.swift                               (Task 3) Profile2D/Plane → C structs
  OCCTShape+Build.swift                           (Task 3, 6)
  OCCTTagger.swift                                (Task 3) the §5.3 tag rules
  OCCTSolidStorage.swift                          (Task 3)
  KernelError+OCCT.swift                          (Task 3) OCCTError → KernelError
  OCCTKernel.swift                                (Task 3, extended 4–7)
  OCCTShape+Operations.swift                      (Task 4, 5)
  OCCTShape+Mesh.swift                            (Task 7)
Tests/CreatorKernelTests/KernelAdditionsTests.swift  (Task 1)
Tests/CreatorOCCTTests/
  RawTopologyTests.swift                          (Task 2)
  Support/KernelTestSupport.swift                 (Task 3) fixture: KernelUnderTest + helpers
  TaggerTests.swift, ExtrudeConformanceTests.swift (Task 3)
  BooleanConformanceTests.swift                   (Task 4)
  FeatureConformanceTests.swift                   (Task 5)
  SweepConformanceTests.swift                     (Task 6)
  MeshExportConformanceTests.swift                (Task 7)
  NamingStabilityTests.swift                      (Task 8)
CLAUDE.md, AGENTS.md, docs/superpowers/notes/2026-10-07-m0-m1-carryover.md   (Task 9)
```

---

### Task 1: Kernel additions — `properties(of:)`, `.unnamed` role, Codable tags

**Files:**
- Create: `Sources/CreatorKernel/SolidProperties.swift`, `Sources/CreatorKernel/TopoRole+Codable.swift`, `Sources/CreatorKernel/EdgeKey+Codable.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift`, `Sources/CreatorKernel/TopoRole.swift`, `Sources/CreatorKernel/TopoTag.swift`, `Sources/CreatorKernel/FakeKernel.swift`
- Test: `Tests/CreatorKernelTests/KernelAdditionsTests.swift`

**Interfaces:**
- Produces:
  - `public struct SolidProperties: Hashable, Sendable { volume: Double; surfaceArea: Double; centroid: Vector3 }`
  - `Kernel.properties(of solid: Solid) throws -> SolidProperties`
  - `TopoRole.unnamed(face: Int)`
  - `TopoRole`, `TopoTag` and `EdgeKey` conform to `Codable`. `EdgeKey` decoding re-canonicalises the pair.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorKernelTests/KernelAdditionsTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct KernelAdditionsTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func fakeKernelReportsBoxProperties() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided, tag: tag)
        let properties = try await kernel.properties(of: box)
        #expect(properties.volume == 6000)
        #expect(properties.surfaceArea == 2 * (10 * 20 + 20 * 30 + 30 * 10))
        #expect(properties.centroid == Vector3(0, 0, 15))
    }

    @Test func fakeKernelSkipsPropertiesWhenCancelled() async throws {
        let kernel = FakeKernel()
        let box = try await kernel.extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: tag)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.properties(of: box)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unnamedRoleHasAStableSortKey() {
        #expect(TopoRole.unnamed(face: 3).sortKey == "unnamed(3)")
    }

    @Test(arguments: [
        TopoRole.startCap, .endCap, .side(segment: 2), .unnamed(face: 7),
        .blend(sourceEdge: EdgeKey([TopoTag(node: NodeID(), item: 0, role: .endCap)], [TopoTag(node: NodeID(), item: 1, role: .side(segment: 0))])),
    ])
    func rolesRoundTripThroughJSON(_ role: TopoRole) throws {
        let data = try JSONEncoder().encode(role)
        #expect(try JSONDecoder().decode(TopoRole.self, from: data) == role)
    }

    @Test func edgeKeyRoundTripsAndStaysCanonical() throws {
        let a: Set = [TopoTag(node: NodeID(), item: 0, role: .endCap)]
        let b: Set = [TopoTag(node: NodeID(), item: 0, role: .side(segment: 1)), TopoTag(node: NodeID(), item: 2, role: .startCap)]
        let key = EdgeKey(b, a)
        let decoded = try JSONDecoder().decode(EdgeKey.self, from: try JSONEncoder().encode(key))
        #expect(decoded == key)
        #expect(decoded.sortKey == key.sortKey)
    }

    @Test func tagRoundTrips() throws {
        let tag = TopoTag(node: NodeID(), item: 4, role: .side(segment: 3))
        #expect(try JSONDecoder().decode(TopoTag.self, from: try JSONEncoder().encode(tag)) == tag)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter KernelAdditionsTests`
Expected: compile errors, for example "value of type 'FakeKernel' has no member 'properties'" and "type 'TopoRole' has no member 'unnamed'".

- [ ] **Step 3: Implement**

`Sources/CreatorKernel/SolidProperties.swift`:
```swift
import CreatorGeometry

/// Mass properties of a solid, in millimetres (volume mm³, area mm²).
public struct SolidProperties: Hashable, Sendable {
    public var volume: Double
    public var surfaceArea: Double
    public var centroid: Vector3

    public init(volume: Double, surfaceArea: Double, centroid: Vector3) {
        self.volume = volume
        self.surfaceArea = surfaceArea
        self.centroid = centroid
    }
}
```

In `Sources/CreatorKernel/Kernel.swift`, add this as the last requirement of `Kernel`:
```swift
    /// Volume, surface area and centroid. Used by inspectors and the conformance suite.
    func properties(of solid: Solid) throws -> SolidProperties
```

In `Sources/CreatorKernel/TopoRole.swift`, add the case and its sort key:
```swift
    /// A face the operation's history does not explain. Unstable across rebuilds by design;
    /// it exists so that no face ever has an empty tag set (M2 plan decision).
    case unnamed(face: Int)
```
and in `sortKey`:
```swift
        case .unnamed(let face): "unnamed(\(face))"
```

`Sources/CreatorKernel/TopoRole+Codable.swift`:
```swift
extension TopoRole: Codable {
    private enum CodingKeys: String, CodingKey { case role, segment, edge, face }
    private enum Kind: String, Codable { case startCap, endCap, side, blend, unnamed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .role) {
        case .startCap: self = .startCap
        case .endCap: self = .endCap
        case .side: self = .side(segment: try container.decode(Int.self, forKey: .segment))
        case .blend: self = .blend(sourceEdge: try container.decode(EdgeKey.self, forKey: .edge))
        case .unnamed: self = .unnamed(face: try container.decode(Int.self, forKey: .face))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .startCap:
            try container.encode(Kind.startCap, forKey: .role)
        case .endCap:
            try container.encode(Kind.endCap, forKey: .role)
        case .side(let segment):
            try container.encode(Kind.side, forKey: .role)
            try container.encode(segment, forKey: .segment)
        case .blend(let edge):
            try container.encode(Kind.blend, forKey: .role)
            try container.encode(edge, forKey: .edge)
        case .unnamed(let face):
            try container.encode(Kind.unnamed, forKey: .role)
            try container.encode(face, forKey: .face)
        }
    }
}
```

In `Sources/CreatorKernel/TopoTag.swift`, change the declaration to `public struct TopoTag: Hashable, Sendable, Codable {`. The synthesized conformance uses `node`, `item` and `role`.

`Sources/CreatorKernel/EdgeKey+Codable.swift`:
```swift
extension EdgeKey: Codable {
    private enum CodingKeys: String, CodingKey { case first, second }

    /// Decodes through `init(_:_:)`, so a hand-edited file is re-canonicalised.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            Set(try container.decode([TopoTag].self, forKey: .first)),
            Set(try container.decode([TopoTag].self, forKey: .second))
        )
    }

    /// Tag arrays are written sorted by `sortKey`, so encoding is deterministic.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(first.sorted { $0.sortKey < $1.sortKey }, forKey: .first)
        try container.encode(second.sorted { $0.sortKey < $1.sortKey }, forKey: .second)
    }
}
```

In `Sources/CreatorKernel/FakeKernel.swift`, add this beside the other operations:
```swift
    public func properties(of solid: Solid) throws -> SolidProperties {
        try Task.checkCancellation()
        operationLog.append("properties")
        let size = solid.bounds.size
        return SolidProperties(
            volume: size.x * size.y * size.z,
            surfaceArea: 2 * (size.x * size.y + size.y * size.z + size.z * size.x),
            centroid: solid.bounds.center
        )
    }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `swift test --filter CreatorKernelTests`, then `swift test`.
Expected: all PASS. CreatorGraph still compiles, because it only calls existing `Kernel` methods.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorKernel Tests/CreatorKernelTests
git commit -m "feat(kernel): add properties(of:), unnamed role and Codable tags"
```

### Task 2: Shim foundation — initialisation, properties, topology

**Files:**
- Modify: `Package.swift`, `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct.cpp`
- Create: `Sources/COCCT/cocct_internal.hpp`, `Sources/COCCT/cocct_inspect.cpp`, `Sources/CreatorOCCT/OCCTProperties.swift`, `Sources/CreatorOCCT/OCCTRawTopology.swift`, `Sources/CreatorOCCT/OCCTShape+Inspect.swift`
- Test: `Tests/CreatorOCCTTests/RawTopologyTests.swift`

**Interfaces:**
- Consumes: `OCCTShape` and its `make`/`check` helpers (M0), plus `SurfaceKind`, `CurveKind`, `Convexity`, `BoundingBox` and `Vector3`.
- Produces (C):
  - `occt_initialize()`, which is idempotent
  - `occt_read_properties` and `occt_read_topology`, plus `occt_topology_free`
  - in `cocct_internal.hpp`: `cocct::guarded`, `cocct::queried`, `cocct::set_error`, `cocct::map_of`, `cocct::distinct_faces`, `cocct::history_builder`
- Produces (Swift, internal):
  - `OCCTProperties` (`volume`, `surfaceArea`, `centroid`, `bounds`), `OCCTShape.properties() throws -> OCCTProperties` and `occtInitialize()`
  - `OCCTRawTopology` with `faces: [Face]` and `edges: [Edge]`, plus `OCCTRawTopology.read(_:) throws -> OCCTRawTopology`. Face indices are 0-based. An edge's `faces` holds 0, 1 (a seam, given twice) or 2 entries.

- [ ] **Step 1: Update `Package.swift` dependencies**

Change these two lines:
```swift
        .target(name: "CreatorOCCT", dependencies: ["COCCT", "CreatorKernel", "CreatorGeometry"]),
        .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorOCCTTests/RawTopologyTests.swift`:
```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct RawTopologyTests {
    @Test func boxPropertiesAreAnalytic() throws {
        let properties = try OCCTShape.box(10, 20, 30).properties()
        #expect(isClose(properties.volume, 6000))
        #expect(isClose(properties.surfaceArea, 2 * (200 + 600 + 300)))
        #expect(isClose(properties.centroid.x, 5) && isClose(properties.centroid.y, 10) && isClose(properties.centroid.z, 15))
        #expect(isClose(properties.bounds.min.x, 0, relative: 1e-4) && isClose(properties.bounds.max.z, 30, relative: 1e-4))
    }

    @Test func boxFacesArePlanarWithOutwardNormals() throws {
        let topology = try OCCTRawTopology.read(OCCTShape.box(10, 20, 30))
        #expect(topology.faces.count == 6)
        #expect(topology.faces.allSatisfy { $0.kind == .plane })
        for face in topology.faces {
            let normal = try #require(face.normal)
            let outward = face.centroid - Vector3(5, 10, 15)
            #expect(normal.dot(outward) > 0, "normal \(normal) points inward for centroid \(face.centroid)")
            #expect(isClose(normal.length, 1))
        }
        #expect(isClose(topology.faces.map(\.area).reduce(0, +), 2200))
    }

    @Test func boxEdgesAreConvexLinesBetweenTwoFaces() throws {
        let topology = try OCCTRawTopology.read(OCCTShape.box(10, 20, 30))
        #expect(topology.edges.count == 12)
        #expect(topology.edges.allSatisfy { $0.kind == .line && $0.convexity == .convex })
        #expect(topology.edges.allSatisfy { $0.faces.count == 2 && $0.faces[0] != $0.faces[1] })
        #expect(topology.edges.filter { isClose($0.length, 30) }.count == 4)
        let vertical = topology.edges.filter { isClose($0.length, 30) }
        #expect(vertical.allSatisfy { abs(($0.direction ?? .zero).dot(.unitZ)) > 0.999 })
    }

    @Test func initializeIsIdempotent() {
        occtInitialize()
        occtInitialize()
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `swift test --filter RawTopologyTests`
Expected: compile errors, "type 'OCCTRawTopology' not found" and "no member 'properties'".

- [ ] **Step 4: Move the shared helpers into `cocct_internal.hpp`**

`Sources/COCCT/cocct_internal.hpp`:
```cpp
// Shared, header-only C++ helpers for the shim. Not part of the public C API.
#ifndef COCCT_INTERNAL_HPP
#define COCCT_INTERNAL_HPP

#include "cocct.h"

#include <Standard_Failure.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shape.hxx>

#include <cstdlib>
#include <cstring>
#include <exception>
#include <new>
#include <vector>

struct occt_shape {
    TopoDS_Shape shape;
};

namespace cocct {

inline void set_ok(occt_status *status) {
    if (status) {
        status->ok = 1;
        status->message[0] = '\0';
    }
}

inline void set_error(occt_status *status, const char *message) {
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

/// Runs a query, returning -1 if anything throws.
template <typename Body>
auto queried(Body body) -> decltype(body()) {
    try {
        return body();
    } catch (...) {
        return static_cast<decltype(body())>(-1);
    }
}

inline TopTools_IndexedMapOfShape map_of(const TopoDS_Shape &shape, TopAbs_ShapeEnum kind) {
    TopTools_IndexedMapOfShape map;
    TopExp::MapShapes(shape, kind, map);
    return map;
}

/// The distinct faces (by `IsSame`) adjacent to `edge`. One face means a seam.
inline std::vector<TopoDS_Face> distinct_faces(const TopoDS_Shape &edge,
                                              const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces) {
    std::vector<TopoDS_Face> faces;
    if (!edge_faces.Contains(edge)) {
        return faces;
    }
    for (TopTools_ListOfShape::Iterator it(edge_faces.FindFromKey(edge)); it.More(); it.Next()) {
        bool seen = false;
        for (const TopoDS_Face &face : faces) {
            seen = seen || face.IsSame(it.Value());
        }
        if (!seen) {
            faces.push_back(TopoDS::Face(it.Value()));
        }
    }
    return faces;
}

template <typename T>
T *copy_out(const std::vector<T> &values) {
    T *out = static_cast<T *>(std::calloc(values.empty() ? 1 : values.size(), sizeof(T)));
    if (!out) {
        throw std::bad_alloc();
    }
    if (!values.empty()) {
        std::memcpy(out, values.data(), values.size() * sizeof(T));
    }
    return out;
}

/// Collects history records against the output's face map.
class history_builder {
public:
    explicit history_builder(const TopoDS_Shape &output) : out_(map_of(output, TopAbs_FACE)) {}

    /// Records every face in `piece` (a face, shell or compound) that exists in the output.
    void add(const TopoDS_Shape &piece, int kind, int operand, int index) {
        if (piece.IsNull()) {
            return;
        }
        for (TopExp_Explorer it(piece, TopAbs_FACE); it.More(); it.Next()) {
            const int found = out_.FindIndex(it.Current());
            if (found > 0) {
                records_.push_back(occt_history_record{found, kind, operand, index});
            }
        }
    }

    void add_all(const TopTools_ListOfShape &pieces, int kind, int operand, int index) {
        for (TopTools_ListOfShape::Iterator it(pieces); it.More(); it.Next()) {
            add(it.Value(), kind, operand, index);
        }
    }

    void move_into(occt_history *history) {
        history->records = copy_out(records_);
        history->count = static_cast<int>(records_.size());
    }

private:
    TopTools_IndexedMapOfShape out_;
    std::vector<occt_history_record> records_;
};

} // namespace cocct

#endif
```

In `Sources/COCCT/cocct.cpp`:
- Delete `struct occt_shape` and the whole anonymous namespace (`set_ok`, `set_error`, `guarded`, `map_of`, `queried`).
- Add `#include "cocct_internal.hpp"` and `using namespace cocct;` after the existing includes.
- In `occt_write_step`, replace the line `Interface_Static::SetCVal("write.step.unit", "MM");` with `occt_initialize();`.

Every existing function body otherwise stays the same.

- [ ] **Step 5: Extend the C header**

In `Sources/COCCT/include/cocct.h`, above the closing `#ifdef __cplusplus`, add:
```c
/// Prepares process-wide OCCT state once: STEP units (mm) and silencing OCCT's stdout
/// printer. Idempotent and thread-safe.
void occt_initialize(void);

/// History: where an output face came from. `out_face` is the 1-based index in the output's
/// face map; `operand`/`index` refer to the operation's inputs (index is 1-based for faces and
/// edges, 0-based for profile segments).
typedef enum {
    OCCT_FROM_START_CAP = 0,
    OCCT_FROM_END_CAP = 1,
    OCCT_FROM_SEGMENT = 2,
    OCCT_FROM_FACE = 3,
    OCCT_FROM_EDGE = 4
} occt_history_kind;

typedef struct {
    int out_face;
    int kind;
    int operand;
    int index;
} occt_history_record;

typedef struct {
    occt_history_record *records;
    int count;
} occt_history;

void occt_history_free(occt_history *history);

typedef struct {
    double volume;
    double area;
    double centroid[3];
    double min[3];
    double max[3];
} occt_properties;

int occt_read_properties(const occt_shape *shape, occt_properties *out, occt_status *status);

/// Surface kinds: 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus, 5 bspline, 6 other.
typedef struct {
    int kind;
    int has_normal;
    double normal[3];
    double area;
    double centroid[3];
} occt_face_info;

/// Curve kinds: 0 line, 1 circle, 2 ellipse, 3 bspline, 4 other.
/// Convexity: 0 convex, 1 concave, 2 smooth, 3 unknown.
/// face_a/face_b: 1-based face indices; equal for a seam; both 0 for a free edge.
typedef struct {
    int kind;
    int has_direction;
    double direction[3];
    double length;
    double midpoint[3];
    int convexity;
    int face_a;
    int face_b;
} occt_edge_info;

typedef struct {
    occt_face_info *faces;
    int face_count;
    occt_edge_info *edges;
    int edge_count;
} occt_topology;

int occt_read_topology(const occt_shape *shape, occt_topology *out, occt_status *status);
void occt_topology_free(occt_topology *topology);
```

- [ ] **Step 6: Implement `cocct_inspect.cpp`**

`Sources/COCCT/cocct_inspect.cpp`:
```cpp
#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBndLib.hxx>
#include <BRepGProp.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <ChFi3d.hxx>
#include <GProp_GProps.hxx>
#include <Interface_Static.hxx>
#include <Message.hxx>
#include <Message_Messenger.hxx>
#include <Message_PrinterOStream.hxx>
#include <Precision.hxx>
#include <STEPControl_Controller.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <mutex>

using namespace cocct;

namespace {

template <typename XYZLike>
void set3(double (&out)[3], const XYZLike &value) {
    out[0] = value.X();
    out[1] = value.Y();
    out[2] = value.Z();
}

void describe_face(const TopoDS_Face &face, occt_face_info &info) {
    BRepAdaptor_Surface surface(face, Standard_True);
    switch (surface.GetType()) {
    case GeomAbs_Plane: info.kind = 0; break;
    case GeomAbs_Cylinder: info.kind = 1; break;
    case GeomAbs_Cone: info.kind = 2; break;
    case GeomAbs_Sphere: info.kind = 3; break;
    case GeomAbs_Torus: info.kind = 4; break;
    case GeomAbs_BSplineSurface: info.kind = 5; break;
    default: info.kind = 6; break;
    }
    if (info.kind == 0) {
        // Outward normal from the surface derivatives, flipped for reversed faces.
        const double u = 0.5 * (surface.FirstUParameter() + surface.LastUParameter());
        const double v = 0.5 * (surface.FirstVParameter() + surface.LastVParameter());
        gp_Pnt point;
        gp_Vec du, dv;
        surface.D1(u, v, point, du, dv);
        gp_Vec normal = du.Crossed(dv);
        if (normal.Magnitude() > 1e-12) {
            if (face.Orientation() == TopAbs_REVERSED) {
                normal.Reverse();
            }
            normal.Normalize();
            set3(info.normal, normal);
            info.has_normal = 1;
        }
    } else if (info.kind == 1) {
        set3(info.normal, surface.Cylinder().Axis().Direction());
        info.has_normal = 1;
    } else if (info.kind == 2) {
        set3(info.normal, surface.Cone().Axis().Direction());
        info.has_normal = 1;
    } else if (info.kind == 4) {
        set3(info.normal, surface.Torus().Axis().Direction());
        info.has_normal = 1;
    }
    GProp_GProps properties;
    BRepGProp::SurfaceProperties(face, properties);
    info.area = properties.Mass();
    set3(info.centroid, properties.CentreOfMass());
}

int convexity_of(const TopoDS_Edge &edge, const TopoDS_Face &a, const TopoDS_Face &b) {
    try {
        switch (ChFi3d::DefineConnectType(edge, a, b, Precision::Angular(), Standard_False)) {
        case ChFiDS_Convex: return 0;
        case ChFiDS_Concave: return 1;
        case ChFiDS_Tangential: return 2;
        default: return 3;
        }
    } catch (...) {
        return 3;
    }
}

void describe_edge(const TopoDS_Edge &edge, const TopTools_IndexedMapOfShape &faces,
                   const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces, occt_edge_info &info) {
    info.convexity = 3;
    if (!BRep_Tool::Degenerated(edge)) {
        BRepAdaptor_Curve curve(edge);
        switch (curve.GetType()) {
        case GeomAbs_Line:
            info.kind = 0;
            set3(info.direction, curve.Line().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_Circle:
            info.kind = 1;
            set3(info.direction, curve.Circle().Axis().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_Ellipse:
            info.kind = 2;
            set3(info.direction, curve.Ellipse().Axis().Direction());
            info.has_direction = 1;
            break;
        case GeomAbs_BSplineCurve: info.kind = 3; break;
        default: info.kind = 4; break;
        }
        GProp_GProps properties;
        BRepGProp::LinearProperties(edge, properties);
        info.length = properties.Mass();
        set3(info.midpoint, curve.Value(0.5 * (curve.FirstParameter() + curve.LastParameter())));
    } else {
        info.kind = 4;
    }
    const std::vector<TopoDS_Face> adjacent = distinct_faces(edge, edge_faces);
    if (adjacent.size() == 1) {
        info.face_a = info.face_b = faces.FindIndex(adjacent[0]);
        info.convexity = 2;
    } else if (adjacent.size() >= 2) {
        info.face_a = faces.FindIndex(adjacent[0]);
        info.face_b = faces.FindIndex(adjacent[1]);
        info.convexity = convexity_of(edge, adjacent[0], adjacent[1]);
    }
}

} // namespace

extern "C" {

void occt_initialize(void) {
    static std::once_flag once;
    std::call_once(once, [] {
        try {
            STEPControl_Controller::Init();
            Interface_Static::SetCVal("write.step.unit", "MM");
            Message::DefaultMessenger()->RemovePrinters(STANDARD_TYPE(Message_PrinterOStream));
        } catch (...) {
            // Best effort: OCCT stays usable, only noisier.
        }
    });
}

void occt_history_free(occt_history *history) {
    if (history) {
        std::free(history->records);
        history->records = nullptr;
        history->count = 0;
    }
}

int occt_read_properties(const occt_shape *shape, occt_properties *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_properties{};
        GProp_GProps volume;
        BRepGProp::VolumeProperties(shape->shape, volume);
        GProp_GProps surface;
        BRepGProp::SurfaceProperties(shape->shape, surface);
        Bnd_Box box;
        BRepBndLib::AddOptimal(shape->shape, box, Standard_False, Standard_False);
        if (box.IsVoid()) {
            set_error(status, "the shape is empty");
            return 0;
        }
        out->volume = volume.Mass();
        out->area = surface.Mass();
        const gp_Pnt centre = volume.CentreOfMass();
        out->centroid[0] = centre.X();
        out->centroid[1] = centre.Y();
        out->centroid[2] = centre.Z();
        box.Get(out->min[0], out->min[1], out->min[2], out->max[0], out->max[1], out->max[2]);
        return 1;
    });
}

int occt_read_topology(const occt_shape *shape, occt_topology *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_topology{};
        const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);

        std::vector<occt_face_info> face_info(faces.Extent());
        for (int i = 1; i <= faces.Extent(); ++i) {
            describe_face(TopoDS::Face(faces(i)), face_info[i - 1]);
        }
        std::vector<occt_edge_info> edge_info(edges.Extent());
        for (int i = 1; i <= edges.Extent(); ++i) {
            describe_edge(TopoDS::Edge(edges(i)), faces, edge_faces, edge_info[i - 1]);
        }
        out->faces = copy_out(face_info);
        out->edges = copy_out(edge_info);
        out->face_count = faces.Extent();
        out->edge_count = edges.Extent();
        return 1;
    });
}

void occt_topology_free(occt_topology *topology) {
    if (topology) {
        std::free(topology->faces);
        std::free(topology->edges);
        *topology = occt_topology{};
    }
}

} // extern "C"
```

- [ ] **Step 7: Implement the Swift readers**

`Sources/CreatorOCCT/OCCTProperties.swift`:
```swift
import CreatorGeometry

/// Mass properties and tight bounds read from an OCCT shape.
struct OCCTProperties: Sendable {
    var volume: Double
    var surfaceArea: Double
    var centroid: Vector3
    var bounds: BoundingBox
}
```

`Sources/CreatorOCCT/OCCTRawTopology.swift`:
```swift
import COCCT
import CreatorGeometry
import CreatorKernel

/// Faces and edges exactly as the shim reports them, before tags are applied.
/// Array index n corresponds to OCCT map index n + 1.
struct OCCTRawTopology: Sendable {
    struct Face: Sendable {
        var kind: SurfaceKind
        var normal: Vector3?
        var area: Double
        var centroid: Vector3
    }

    struct Edge: Sendable {
        var kind: CurveKind
        var direction: Vector3?
        var length: Double
        var midpoint: Vector3
        var convexity: Convexity
        /// 0-based face indices: two distinct for a normal edge, the same twice for a seam,
        /// none for a free edge.
        var faces: [Int]
    }

    var faces: [Face]
    var edges: [Edge]

    static func read(_ shape: OCCTShape) throws(OCCTError) -> OCCTRawTopology {
        var raw = occt_topology()
        defer { occt_topology_free(&raw) }
        try OCCTShape.check { status in occt_read_topology(shape.raw, &raw, status) }
        let faces = UnsafeBufferPointer(start: raw.faces, count: Int(raw.face_count)).map { info in
            Face(kind: surfaceKind(info.kind), normal: info.has_normal != 0 ? vector(info.normal) : nil,
                 area: info.area, centroid: vector(info.centroid))
        }
        let edges = UnsafeBufferPointer(start: raw.edges, count: Int(raw.edge_count)).map { info in
            Edge(kind: curveKind(info.kind), direction: info.has_direction != 0 ? vector(info.direction) : nil,
                 length: info.length, midpoint: vector(info.midpoint), convexity: convexity(info.convexity),
                 faces: info.face_a > 0 && info.face_b > 0 ? [Int(info.face_a) - 1, Int(info.face_b) - 1] : [])
        }
        return OCCTRawTopology(faces: faces, edges: edges)
    }

    static func vector(_ value: (Double, Double, Double)) -> Vector3 {
        Vector3(value.0, value.1, value.2)
    }

    private static func surfaceKind(_ code: Int32) -> SurfaceKind {
        switch code {
        case 0: .plane
        case 1: .cylinder
        case 2: .cone
        case 3: .sphere
        case 4: .torus
        case 5: .bspline
        default: .other
        }
    }

    private static func curveKind(_ code: Int32) -> CurveKind {
        switch code {
        case 0: .line
        case 1: .circle
        case 2: .ellipse
        case 3: .bspline
        default: .other
        }
    }

    private static func convexity(_ code: Int32) -> Convexity {
        switch code {
        case 0: .convex
        case 1: .concave
        case 2: .smooth
        default: .unknown
        }
    }
}
```

`Sources/CreatorOCCT/OCCTShape+Inspect.swift`:
```swift
import COCCT
import CreatorGeometry

extension OCCTShape {
    func properties() throws(OCCTError) -> OCCTProperties {
        var raw = occt_properties()
        try Self.check { status in occt_read_properties(self.raw, &raw, status) }
        return OCCTProperties(
            volume: raw.volume,
            surfaceArea: raw.area,
            centroid: OCCTRawTopology.vector(raw.centroid),
            bounds: BoundingBox(min: OCCTRawTopology.vector(raw.min), max: OCCTRawTopology.vector(raw.max))
        )
    }
}

/// Prepares process-wide OCCT state (idempotent). Called by `OCCTKernel.init`.
func occtInitialize() {
    occt_initialize()
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `swift test --filter CreatorOCCTTests`
Expected: all PASS, including the M0 probe tests. **No OCCT text on stdout.** Before this task the STEP test printed transfer statistics; confirm they're gone. If the linker reports missing symbols, find the library with `nm -gU /opt/homebrew/opt/opencascade/lib/libTK*.dylib | grep <symbol>` and add it to `occtLibraries`.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): read properties and topology from OCCT shapes"
```

### Task 3: Profiles, extrude, tagging and `OCCTKernel`

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`
- Create: `Sources/COCCT/cocct_build.cpp`, `Sources/CreatorOCCT/OCCTHistoryRecord.swift`, `Sources/CreatorOCCT/OCCTProfile.swift`, `Sources/CreatorOCCT/OCCTShape+Build.swift`, `Sources/CreatorOCCT/OCCTTagger.swift`, `Sources/CreatorOCCT/OCCTSolidStorage.swift`, `Sources/CreatorOCCT/KernelError+OCCT.swift`, `Sources/CreatorOCCT/OCCTKernel.swift`
- Test (fixture): `Tests/CreatorOCCTTests/Support/KernelTestSupport.swift`
- Test: `Tests/CreatorOCCTTests/TaggerTests.swift`, `Tests/CreatorOCCTTests/ExtrudeConformanceTests.swift`

**Interfaces:**
- Consumes: Task 2 (`OCCTRawTopology`, `OCCTShape.properties()`, `history_builder`) and Task 1 (`SolidProperties`, `.unnamed`).
- Produces:
  - C: `occt_plane`, `occt_segment`, `occt_profile`, `occt_extrude(profile, distance, history, status)`
  - Swift (internal):
    - `OCCTHistoryRecord(outFace: Int /*0-based*/, kind: Kind, operand: Int, index: Int)` where `Kind` is `startCap`, `endCap`, `segment`, `face` or `edge`. `index` is 0-based for every kind.
    - `OCCTProfile.with(_:_:)` and `OCCTProfile.withAll(_:_:)`
    - `OCCTShape.extrude(_:distance:) throws -> (OCCTShape, [OCCTHistoryRecord])`
    - `OCCTTagger.topology(raw:history:inputs:tag:) -> Topology`
    - `OCCTSolidStorage(shape:faceCount:)`
    - `KernelError.occt(_:_:)`
  - Swift (public): `public actor OCCTKernel: Kernel` with `public init()`. In this task `extrude` and `properties(of:)` are real. Every other operation throws `KernelError.unsupported(<name>)` until a later task replaces it. Each one starts with `try Task.checkCancellation()`.
  - Test fixture: `KernelUnderTest` (`CaseIterable`, `.occt`, with `make() -> any Kernel`), plus the helpers `box`, `faces(_:role:of:)`, `edges(_:between:and:)` and `hasTag`.

- [ ] **Step 1: Write the test fixture**

`Tests/CreatorOCCTTests/Support/KernelTestSupport.swift`:
```swift
// Test fixture file: kernel factory and topology helpers shared by the conformance suites.
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorOCCT

/// Every kernel the conformance suite runs against. A future pure-Swift kernel is added here.
enum KernelUnderTest: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case occt

    func make() -> any Kernel {
        switch self {
        case .occt: OCCTKernel()
        }
    }

    var testDescription: String { rawValue }
}

func newTag(item: Int = 0) -> NodeTag { NodeTag(node: NodeID(), item: item) }

/// A `width` × `depth` × `height` box from a centred rectangle on XY, extruded up from z = 0.
func box(_ kernel: any Kernel, _ width: Double, _ depth: Double, _ height: Double, tag: NodeTag = newTag()) async throws -> Solid {
    try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided, tag: tag)
}

func hasTag(_ face: FaceInfo, _ role: TopoRole, of tag: NodeTag) -> Bool {
    face.tags.contains(TopoTag(tag, role))
}

func faces(_ solid: Solid, role: TopoRole, of tag: NodeTag) -> [FaceInfo] {
    solid.topology.faces.filter { hasTag($0, role, of: tag) }
}

/// Edges whose two adjacent faces satisfy `a` and `b` (in either order). Seams excluded.
func edges(_ solid: Solid, between a: (FaceInfo) -> Bool, and b: (FaceInfo) -> Bool) -> [EdgeInfo] {
    solid.topology.edges.filter { edge in
        guard !edge.isSeam, edge.faces.count == 2,
              let first = solid.topology.face(edge.faces[0]), let second = solid.topology.face(edge.faces[1]) else { return false }
        return (a(first) && b(second)) || (a(second) && b(first))
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/CreatorOCCTTests/TaggerTests.swift`:
```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct TaggerTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func raw(faces: Int, edges: [[Int]] = []) -> OCCTRawTopology {
        OCCTRawTopology(
            faces: (0..<faces).map { _ in .init(kind: .plane, normal: .unitZ, area: 1, centroid: .zero) },
            edges: edges.map { .init(kind: .line, direction: .unitX, length: 1, midpoint: .zero, convexity: .convex, faces: $0) }
        )
    }

    @Test func taggerFallsBackToUnnamed() {
        let topology = OCCTTagger.topology(raw: raw(faces: 2), history: [], inputs: [], tag: tag)
        #expect(topology.faces.map(\.tags) == [[TopoTag(tag, .unnamed(face: 0))], [TopoTag(tag, .unnamed(face: 1))]])
    }

    @Test func capsAndSegmentsBecomeRoles() {
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .startCap, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 1, kind: .endCap, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 2, kind: .segment, operand: 0, index: 3),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 3), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .startCap)])
        #expect(topology.faces[1].tags == [TopoTag(tag, .endCap)])
        #expect(topology.faces[2].tags == [TopoTag(tag, .side(segment: 3))])
    }

    @Test func faceRecordsCarryInputTagsAndMergeUnions() {
        let a = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let b = TopoTag(node: NodeID(), item: 1, role: .side(segment: 0))
        let inputA = Topology(faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [a])], edges: [])
        let inputB = Topology(faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [b])], edges: [])
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .face, operand: 0, index: 0),
            OCCTHistoryRecord(outFace: 0, kind: .face, operand: 1, index: 0),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [inputA, inputB], tag: tag)
        #expect(topology.faces[0].tags == [a, b])
    }

    @Test func edgeRecordsBecomeBlendsKeyedByTheInputEdge() throws {
        let top = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let side = TopoTag(node: NodeID(), item: 0, role: .side(segment: 1))
        let input = Topology(
            faces: [FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [top]),
                    FaceInfo(id: FaceID(1), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [side])],
            edges: [EdgeInfo(id: EdgeID(0), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .convex,
                             faces: [FaceID(0), FaceID(1)])]
        )
        let history = [OCCTHistoryRecord(outFace: 0, kind: .edge, operand: 0, index: 0)]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [input], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .blend(sourceEdge: EdgeKey([top], [side])))])
    }

    @Test func edgesMapToFaceIDsAndSeams() {
        let topology = OCCTTagger.topology(raw: raw(faces: 2, edges: [[0, 1], [1, 1], []]), history: [], inputs: [], tag: tag)
        #expect(topology.edges[0].faces == [FaceID(0), FaceID(1)])
        #expect(topology.edges[1].isSeam)
        #expect(topology.edges[2].faces.isEmpty)
        #expect(topology.edges.map(\.id) == [EdgeID(0), EdgeID(1), EdgeID(2)])
    }

    @Test func outOfRangeRecordsAreIgnored() {
        let history = [OCCTHistoryRecord(outFace: 9, kind: .startCap, operand: 0, index: 0),
                       OCCTHistoryRecord(outFace: 0, kind: .face, operand: 5, index: 0)]
        let topology = OCCTTagger.topology(raw: raw(faces: 1), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .unnamed(face: 0))])
    }
}
```

`Tests/CreatorOCCTTests/ExtrudeConformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct ExtrudeConformanceTests {
    @Test(arguments: KernelUnderTest.allCases)
    func boxExtrudeIsAnalytic(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await box(kernel, 10, 20, 30, tag: tag)
        let properties = try await kernel.properties(of: solid)
        #expect(isClose(properties.volume, 6000))
        #expect(solid.topology.faces.count == 6)
        #expect(solid.topology.edges.count == 12)
        #expect(isClose(solid.bounds.min.z, 0, relative: 1e-4) && isClose(solid.bounds.max.z, 30, relative: 1e-4))
        let top = try #require(faces(solid, role: .endCap, of: tag).first)
        let bottom = try #require(faces(solid, role: .startCap, of: tag).first)
        #expect((top.normal ?? .zero).dot(.unitZ) > 0.999)
        #expect((bottom.normal ?? .zero).dot(.unitZ) < -0.999)
        for k in 0..<4 {
            #expect(faces(solid, role: .side(segment: k), of: tag).count == 1)
        }
        #expect(solid.topology.faces.allSatisfy { $0.tags.count == 1 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func symmetricExtrudeStraddlesThePlane(_ under: KernelUnderTest) async throws {
        let solid = try await under.make().extrude(.rectangle(width: 2, height: 2, plane: .xy), distance: 6, mode: .symmetric, tag: newTag())
        #expect(isClose(solid.bounds.min.z, -3, relative: 1e-4))
        #expect(isClose(solid.bounds.max.z, 3, relative: 1e-4))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func circleExtrudeHasASeamAndACylinder(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let solid = try await kernel.extrude(.circle(radius: 2.5, center: .zero, plane: .xy), distance: 6, mode: .oneSided, tag: tag)
        #expect(isClose(try await kernel.properties(of: solid).volume, Double.pi * 6.25 * 6))
        #expect(solid.topology.faces.count == 3)
        let wall = try #require(faces(solid, role: .side(segment: 0), of: tag).first)
        #expect(wall.kind == .cylinder)
        #expect(solid.topology.edges.contains { $0.isSeam })
        let rims = solid.topology.edges.filter { $0.kind == .circle }
        #expect(rims.count == 2)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func profileOnTheFrontPlaneExtrudesTowardMinusY(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(.rectangle(width: 10, height: 4, plane: .xz), distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 80))
        #expect(isClose(solid.bounds.min.y, -2, relative: 1e-4) && isClose(solid.bounds.max.y, 0, relative: 1e-3))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func clockwiseProfileStillGivesAPositiveSolid(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let ccw = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let cw = Profile2D(plane: .xy, segments: ccw.segments.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return .line(b, a)
        })
        let solid = try await kernel.extrude(cw, distance: 1, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 16))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func openProfileIsRejected(_ under: KernelUnderTest) async {
        let open = Profile2D(plane: .xy, segments: [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))])
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await under.make().extrude(open, distance: 1, mode: .oneSided, tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func zeroLengthLineIsAPlainError(_ under: KernelUnderTest) async {
        let degenerate = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(0, 0)), .line(Vector2(0, 0), Vector2(1, 0)),
            .line(Vector2(1, 0), Vector2(1, 1)), .line(Vector2(1, 1), Vector2(0, 0)),
        ])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(degenerate, distance: 1, mode: .oneSided, tag: newTag())
        }
        guard case .operationFailed(let operation, let reason)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "extrude")
        #expect(!reason.isEmpty)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func nonPositiveDistanceIsRejected(_ under: KernelUnderTest) async {
        await #expect(throws: KernelError.invalidInput("Extrude distance must be greater than 0 mm.")) {
            try await under.make().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 0, mode: .oneSided, tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func cancelledCallIsSkipped(_ under: KernelUnderTest) async {
        let kernel = under.make()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func solidsFromAnotherKernelAreRejected() async throws {
        let fake = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: newTag())
        await #expect(throws: KernelError.invalidInput("This solid was made by a different kernel.")) {
            try await OCCTKernel().properties(of: fake)
        }
    }
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `swift test --filter "TaggerTests|ExtrudeConformanceTests"`
Expected: compile errors, "cannot find 'OCCTKernel'" and "cannot find 'OCCTTagger'".

- [ ] **Step 4: Extend the header with profiles and extrude**

Add to `cocct.h`:
```c
/// A plane: origin, unit normal, unit in-plane x axis (y = normal × x).
typedef struct {
    double origin[3];
    double normal[3];
    double x_axis[3];
} occt_plane;

/// One profile segment in plane coordinates. kind 0 = line (x0,y0)→(x1,y1);
/// kind 1 = counter-clockwise arc around (cx,cy) with `radius` from angle `start` to `end` (radians).
typedef struct {
    int kind;
    double x0, y0, x1, y1;
    double cx, cy, radius, start, end;
} occt_segment;

typedef struct {
    occt_plane plane;
    const occt_segment *segments;
    int segment_count;
} occt_profile;

/// Extrudes the profile along its plane normal by `distance`. History: start/end caps and
/// one OCCT_FROM_SEGMENT record per side face (index = segment).
occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status);
```

- [ ] **Step 5: Implement `cocct_build.cpp`**

`Sources/COCCT/cocct_build.cpp`:
```cpp
#include "cocct_internal.hpp"

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <GProp_GProps.hxx>
#include <Standard_DomainError.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Ax2.hxx>
#include <gp_Circ.hxx>
#include <gp_Vec.hxx>

#include <cmath>

using namespace cocct;

namespace {

/// A profile turned into a planar face, with its edges in segment order.
struct built_profile {
    TopoDS_Face face;
    std::vector<TopoDS_Edge> edges;
};

gp_Ax2 frame_of(const occt_plane &plane) {
    return gp_Ax2(gp_Pnt(plane.origin[0], plane.origin[1], plane.origin[2]),
                  gp_Dir(plane.normal[0], plane.normal[1], plane.normal[2]),
                  gp_Dir(plane.x_axis[0], plane.x_axis[1], plane.x_axis[2]));
}

gp_Pnt point_on(const gp_Ax2 &frame, double x, double y) {
    return gp_Pnt(frame.Location().XYZ() + frame.XDirection().XYZ() * x + frame.YDirection().XYZ() * y);
}

built_profile build_profile(const occt_profile &profile) {
    if (!profile.segments || profile.segment_count <= 0) {
        throw Standard_DomainError("the profile has no segments");
    }
    const gp_Ax2 frame = frame_of(profile.plane);
    BRepBuilderAPI_MakeWire wire;
    built_profile result;
    for (int k = 0; k < profile.segment_count; ++k) {
        const occt_segment &segment = profile.segments[k];
        TopoDS_Edge edge;
        if (segment.kind == 0) {
            const gp_Pnt a = point_on(frame, segment.x0, segment.y0);
            const gp_Pnt b = point_on(frame, segment.x1, segment.y1);
            if (a.Distance(b) <= 1e-9) {
                throw Standard_DomainError("a line in the profile has zero length");
            }
            BRepBuilderAPI_MakeEdge make(a, b);
            if (!make.IsDone()) {
                throw Standard_DomainError("a line in the profile could not be built");
            }
            edge = make.Edge();
        } else {
            if (!(segment.radius > 1e-9) || !std::isfinite(segment.radius)) {
                throw Standard_DomainError("an arc in the profile has no radius");
            }
            const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
            BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), segment.start, segment.end);
            if (!make.IsDone()) {
                throw Standard_DomainError("an arc in the profile could not be built");
            }
            edge = make.Edge();
        }
        wire.Add(edge);
        if (!wire.IsDone()) {
            throw Standard_DomainError("the profile segments do not connect");
        }
        result.edges.push_back(wire.Edge());
    }
    BRepBuilderAPI_MakeFace face(wire.Wire(), Standard_True);
    if (!face.IsDone()) {
        throw Standard_DomainError("the profile is not a closed, flat loop");
    }
    result.face = face.Face();
    return result;
}

/// OCCT may return an inside-out solid depending on profile winding; flip it if so.
TopoDS_Shape oriented(const TopoDS_Shape &shape) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties);
    return properties.Mass() < 0 ? shape.Reversed() : shape;
}

} // namespace

extern "C" {

occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profile || !std::isfinite(distance) || distance <= 0) {
            set_error(status, "extrude distance must be greater than 0");
            return nullptr;
        }
        const built_profile built = build_profile(*profile);
        const gp_Vec vector(gp_Dir(profile->plane.normal[0], profile->plane.normal[1], profile->plane.normal[2]));
        BRepPrimAPI_MakePrism prism(built.face, vector * distance);
        prism.Build();
        if (!prism.IsDone()) {
            set_error(status, "the extrusion could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(prism.Shape());
        history_builder records(solid);
        records.add(prism.FirstShape(), OCCT_FROM_START_CAP, 0, 0);
        records.add(prism.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        for (int k = 0; k < static_cast<int>(built.edges.size()); ++k) {
            records.add_all(prism.Generated(built.edges[k]), OCCT_FROM_SEGMENT, 0, k);
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

} // extern "C"
```

- [ ] **Step 6: Implement the Swift side**

`Sources/CreatorOCCT/OCCTHistoryRecord.swift`:
```swift
import COCCT

/// One shim history record, with every index made 0-based.
struct OCCTHistoryRecord: Hashable, Sendable {
    enum Kind: Sendable {
        case startCap, endCap, segment, face, edge
    }

    var outFace: Int
    var kind: Kind
    var operand: Int
    var index: Int

    /// Reads the shim's records. Out/face/edge indices arrive 1-based; segment indices 0-based.
    static func read(_ history: occt_history) -> [OCCTHistoryRecord] {
        UnsafeBufferPointer(start: history.records, count: Int(history.count)).compactMap { record in
            let kind: Kind
            switch record.kind {
            case Int32(OCCT_FROM_START_CAP.rawValue): kind = .startCap
            case Int32(OCCT_FROM_END_CAP.rawValue): kind = .endCap
            case Int32(OCCT_FROM_SEGMENT.rawValue): kind = .segment
            case Int32(OCCT_FROM_FACE.rawValue): kind = .face
            case Int32(OCCT_FROM_EDGE.rawValue): kind = .edge
            default: return nil
            }
            let index = (kind == .face || kind == .edge) ? Int(record.index) - 1 : Int(record.index)
            return OCCTHistoryRecord(outFace: Int(record.out_face) - 1, kind: kind, operand: Int(record.operand), index: index)
        }
    }
}
```

(If the importer exposes `OCCT_FROM_START_CAP` as an `Int32`-backed struct with `rawValue: UInt32`, the `Int32(... .rawValue)` form above is correct. If it imports the constants as plain `Int32` values, drop the `.rawValue` and say so in the report.)

`Sources/CreatorOCCT/OCCTProfile.swift`:
```swift
import COCCT
import CreatorGeometry

/// Converts profiles and planes to the shim's C structs for the duration of a call.
enum OCCTProfile {
    static func plane(_ plane: Plane) -> occt_plane {
        occt_plane(
            origin: (plane.origin.x, plane.origin.y, plane.origin.z),
            normal: (plane.normal.x, plane.normal.y, plane.normal.z),
            x_axis: (plane.xAxis.x, plane.xAxis.y, plane.xAxis.z)
        )
    }

    static func segment(_ segment: Segment2D) -> occt_segment {
        switch segment {
        case .line(let a, let b):
            occt_segment(kind: 0, x0: a.x, y0: a.y, x1: b.x, y1: b.y, cx: 0, cy: 0, radius: 0, start: 0, end: 0)
        case .arc(let center, let radius, let start, let end):
            occt_segment(kind: 1, x0: 0, y0: 0, x1: 0, y1: 0, cx: center.x, cy: center.y, radius: radius,
                         start: start.radians, end: end.radians)
        }
    }

    /// Calls `body` with a C view of `profile` that is valid only inside the call.
    static func with<T, E: Error>(_ profile: Profile2D, _ body: (UnsafePointer<occt_profile>) throws(E) -> T) throws(E) -> T {
        try withAll([profile]) { profiles, _ throws(E) in try body(profiles) }
    }

    /// Calls `body` with C views of every profile (contiguous), valid only inside the call.
    static func withAll<T, E: Error>(_ profiles: [Profile2D], _ body: (UnsafePointer<occt_profile>, Int) throws(E) -> T)
        throws(E) -> T {
        let segments = profiles.flatMap { $0.segments.map(segment) }
        return try segments.withUnsafeBufferPointer { buffer throws(E) in
            var offset = 0
            var views: [occt_profile] = []
            for profile in profiles {
                views.append(occt_profile(plane: plane(profile.plane), segments: buffer.baseAddress.map { $0 + offset },
                                          segment_count: Int32(profile.segments.count)))
                offset += profile.segments.count
            }
            return try views.withUnsafeBufferPointer { viewBuffer throws(E) in
                guard let base = viewBuffer.baseAddress else { preconditionFailure("withAll needs at least one profile") }
                return try body(base, viewBuffer.count)
            }
        }
    }
}
```

`Sources/CreatorOCCT/OCCTShape+Build.swift`:
```swift
import COCCT
import CreatorGeometry

extension OCCTShape {
    /// Runs a shim builder that returns a shape and fills a history; frees the history.
    static func building(_ body: (UnsafeMutablePointer<occt_history>, UnsafeMutablePointer<occt_status>) -> OpaquePointer?)
        throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        var history = occt_history()
        defer { occt_history_free(&history) }
        let shape = try make { status in body(&history, status) }
        return (shape, OCCTHistoryRecord.read(history))
    }

    static func extrude(_ profile: Profile2D, distance: Double) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_extrude(cProfile, distance, history, status) }
        }
    }
}
```

(`OCCTProfile` is generic over the closure's error type, so `throws(OCCTError)` flows through. If the compiler still can't infer the error type at a call site, annotate the closure (`{ cProfile throws(OCCTError) in ... }`, as shown) rather than falling back to untyped `throws`. Note any change in the report.)

`Sources/CreatorOCCT/OCCTSolidStorage.swift`:
```swift
import CreatorKernel

/// The OCCT shape behind a `Solid`.
final class OCCTSolidStorage: SolidStorage {
    let shape: OCCTShape
    let estimatedBytes: Int

    init(shape: OCCTShape, faceCount: Int) {
        self.shape = shape
        // Rough: B-rep plus geometry per face, plus a fixed overhead.
        self.estimatedBytes = 4096 + faceCount * 2048
    }
}
```

`Sources/CreatorOCCT/KernelError+OCCT.swift`:
```swift
import CreatorKernel

extension KernelError {
    /// Wraps a shim failure for `operation` in plain language.
    static func occt(_ operation: String, _ error: OCCTError) -> KernelError {
        .operationFailed(operation: operation, reason: plainReason(error.message))
    }

    /// OCCT's own messages are terse ("BRep_API: command not done"); make them readable.
    static func plainReason(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("not done") || lower.contains("notdone") || lower.contains("unknown occt") {
            return "the geometry could not be built with these inputs."
        }
        return message.hasSuffix(".") ? message : message + "."
    }
}
```

`Sources/CreatorOCCT/OCCTTagger.swift`:
```swift
import CreatorKernel

/// Applies spec §5.3: names every output face from the operation's history.
enum OCCTTagger {
    static func topology(raw: OCCTRawTopology, history: [OCCTHistoryRecord], inputs: [Topology], tag: NodeTag) -> Topology {
        var tags: [Int: Set<TopoTag>] = [:]
        for record in history where raw.faces.indices.contains(record.outFace) {
            switch record.kind {
            case .startCap:
                tags[record.outFace, default: []].insert(TopoTag(tag, .startCap))
            case .endCap:
                tags[record.outFace, default: []].insert(TopoTag(tag, .endCap))
            case .segment:
                tags[record.outFace, default: []].insert(TopoTag(tag, .side(segment: record.index)))
            case .face:
                guard inputs.indices.contains(record.operand),
                      inputs[record.operand].faces.indices.contains(record.index) else { continue }
                tags[record.outFace, default: []].formUnion(inputs[record.operand].faces[record.index].tags)
            case .edge:
                guard inputs.indices.contains(record.operand),
                      let edge = inputs[record.operand].edge(EdgeID(record.index)),
                      let key = inputs[record.operand].key(of: edge) else { continue }
                tags[record.outFace, default: []].insert(TopoTag(tag, .blend(sourceEdge: key)))
            }
        }
        let faces = raw.faces.enumerated().map { index, face in
            FaceInfo(id: FaceID(index), kind: face.kind, normal: face.normal, area: face.area, centroid: face.centroid,
                     tags: tags[index].flatMap { $0.isEmpty ? nil : $0 } ?? [TopoTag(tag, .unnamed(face: index))])
        }
        let edges = raw.edges.enumerated().map { index, edge in
            EdgeInfo(id: EdgeID(index), kind: edge.kind, direction: edge.direction, length: edge.length,
                     midpoint: edge.midpoint, convexity: edge.convexity, faces: edge.faces.map(FaceID.init))
        }
        return Topology(faces: faces, edges: edges)
    }
}
```

`Sources/CreatorOCCT/OCCTKernel.swift`:
```swift
import CreatorGeometry
import CreatorKernel
import Foundation

/// The OpenCascade-backed kernel (spec §5.2). Every OCCT call is serialized by this actor,
/// which also keeps OCCT's few mutating operations (meshing) safe.
public actor OCCTKernel: Kernel {
    public init() {
        occtInitialize()
    }

    public func extrude(_ profile: Profile2D, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard distance.isFinite, distance > 0 else {
            throw KernelError.invalidInput("Extrude distance must be greater than 0 mm.")
        }
        guard profile.isClosed else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        let base = mode == .symmetric
            ? Profile2D(plane: profile.plane.offset(by: -distance / 2), segments: profile.segments)
            : profile
        return try build("extrude", inputs: [], tag: tag) { try OCCTShape.extrude(base, distance: distance) }
    }

    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("revolve")
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("loft")
    }

    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("boolean")
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("transform")
    }

    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("fillet")
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        throw KernelError.unsupported("chamfer")
    }

    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        throw KernelError.unsupported("tessellate")
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try Task.checkCancellation()
        throw KernelError.unsupported("export")
    }

    public func properties(of solid: Solid) throws -> SolidProperties {
        try Task.checkCancellation()
        do {
            let properties = try shape(of: solid).properties()
            return SolidProperties(volume: properties.volume, surfaceArea: properties.surfaceArea, centroid: properties.centroid)
        } catch let error as OCCTError {
            throw KernelError.occt("measure", error)
        }
    }

    // MARK: - Shared plumbing

    /// The OCCT shape behind a solid made by this kernel.
    func shape(of solid: Solid) throws -> OCCTShape {
        guard let storage = solid.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This solid was made by a different kernel.")
        }
        return storage.shape
    }

    /// Runs a shim builder, then reads topology and bounds and applies tags.
    func build(_ operation: String, inputs: [Topology], tag: NodeTag,
               _ body: () throws -> (OCCTShape, [OCCTHistoryRecord])) throws -> Solid {
        let built: (OCCTShape, [OCCTHistoryRecord])
        do {
            built = try body()
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
        return try solid(from: built.0, history: built.1, inputs: inputs, tag: tag, operation: operation)
    }

    func solid(from shape: OCCTShape, history: [OCCTHistoryRecord], inputs: [Topology], tag: NodeTag,
               operation: String) throws -> Solid {
        do {
            let raw = try OCCTRawTopology.read(shape)
            guard !raw.faces.isEmpty else {
                throw KernelError.operationFailed(operation: operation, reason: "the result is empty.")
            }
            let properties = try shape.properties()
            let topology = OCCTTagger.topology(raw: raw, history: history, inputs: inputs, tag: tag)
            return Solid(topology: topology, bounds: properties.bounds,
                         storage: OCCTSolidStorage(shape: shape, faceCount: raw.faces.count))
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
    }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `swift test --filter "TaggerTests|ExtrudeConformanceTests|RawTopologyTests"`, then `swift test`.
Expected: all PASS, with no OCCT stdout output.

- [ ] **Step 8: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): extrude profiles with tagged topology in OCCTKernel"
```

### Task 4: Boolean and transform

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/CreatorOCCT/OCCTKernel.swift`
- Create: `Sources/COCCT/cocct_ops.cpp`, `Sources/CreatorOCCT/OCCTShape+Operations.swift`
- Test: `Tests/CreatorOCCTTests/BooleanConformanceTests.swift`

**Interfaces:**
- Consumes: Task 3 (`OCCTKernel.build`, `shape(of:)`, `history_builder`, the fixture).
- Produces:
  - C: `occt_boolean(op, a, tools, tool_count, history, status)`, where `op` is 0 fuse, 1 cut or 2 common. Operand 0 is `a` and operand `i + 1` is tool `i`.
  - C: `occt_transform(shape, translation[3], has_rotation, axis_origin[3], axis_direction[3], angle, history, status)`
  - in `cocct_ops.cpp`: the helper `add_face_history(records, algo, input, operand)`
  - Swift: `OCCTShape.boolean(_:_:_:)` and `OCCTShape.transformed(by:)`. `OCCTKernel.boolean` and `OCCTKernel.transform` are real from this task.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/BooleanConformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct BooleanConformanceTests {
    /// A 60 × 40 × 6 plate (centred on XY, z 0…6) and four Ø5 through-tools at (±20, ±10),
    /// each tool tagged as its own broadcast item and running from z = −1 to 7.
    func plateAndHoles(_ kernel: any Kernel, plate plateTag: NodeTag, holes holeNode: NodeID)
        async throws -> (Solid, [Solid]) {
        let plate = try await box(kernel, 60, 40, 6, tag: plateTag)
        var tools: [Solid] = []
        for (item, center) in [Vector2(-20, -10), Vector2(20, -10), Vector2(-20, 10), Vector2(20, 10)].enumerated() {
            tools.append(try await kernel.extrude(.circle(radius: 2.5, center: center, plane: Plane.xy.offset(by: -1)),
                                                  distance: 8, mode: .oneSided, tag: NodeTag(node: holeNode, item: item)))
        }
        return (plate, tools)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func subtractingHolesKeepsPlateTagsAndNamesHoleWalls(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        let holeNode = NodeID()
        let (plate, tools) = try await plateAndHoles(kernel, plate: plateTag, holes: holeNode)
        let result = try await kernel.boolean(.subtract, plate, tools, tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 14400 - 4 * Double.pi * 6.25 * 6))
        #expect(result.topology.faces.count == 10)
        #expect(faces(result, role: .endCap, of: plateTag).count == 1)
        #expect(faces(result, role: .startCap, of: plateTag).count == 1)
        for k in 0..<4 {
            #expect(faces(result, role: .side(segment: k), of: plateTag).count == 1)
            #expect(faces(result, role: .side(segment: 0), of: NodeTag(node: holeNode, item: k)).count == 1)
        }
        #expect(result.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func subtractingAMissingToolKeepsThePlate(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        let plate = try await box(kernel, 10, 10, 2, tag: plateTag)
        let far = try await kernel.extrude(.rectangle(width: 1, height: 1, plane: Plane.xy.offset(by: 100)), distance: 1,
                                           mode: .oneSided, tag: newTag())
        let result = try await kernel.boolean(.subtract, plate, [far], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 200))
        #expect(faces(result, role: .endCap, of: plateTag).count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func unionOfOverlappingBoxesMergesTags(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        let result = try await kernel.boolean(.union, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 1500))
        // SimplifyResult merges the coplanar top faces into one face carrying both tags.
        #expect(result.topology.faces.contains { $0.tags.count >= 2 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func intersectKeepsTheOverlap(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 10, 10)
        let b = try await kernel.transform(try await box(kernel, 10, 10, 10), by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        let result = try await kernel.boolean(.intersect, a, [b], tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 500))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func emptyIntersectionIsAPlainError(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 1, 1, 1)
        let b = try await kernel.transform(try await box(kernel, 1, 1, 1), by: Transform(translation: Vector3(50, 0, 0)), tag: newTag())
        let error = await #expect(throws: KernelError.self) { try await kernel.boolean(.intersect, a, [b], tag: newTag()) }
        guard case .operationFailed(let operation, let reason)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "intersect")
        #expect(reason.contains("empty"))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func booleanWithNoToolsIsRejected(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 1, 1, 1)
        await #expect(throws: KernelError.invalidInput("Connect at least one tool solid.")) {
            try await kernel.boolean(.subtract, a, [], tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func translateMovesBoundsAndKeepsTags(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let original = try await box(kernel, 2, 2, 2, tag: tag)
        let moved = try await kernel.transform(original, by: Transform(translation: Vector3(5, 0, 0)), tag: newTag())
        #expect(isClose(moved.bounds.min.x, 4, relative: 1e-4) && isClose(moved.bounds.max.x, 6, relative: 1e-4))
        #expect(isClose(try await kernel.properties(of: moved).volume, 8))
        #expect(Set(moved.topology.faces.flatMap(\.tags)) == Set(original.topology.faces.flatMap(\.tags)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func rotateTurnsTheBounds(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let slab = try await box(kernel, 10, 2, 2)
        let turned = try await kernel.transform(slab, by: Transform(rotationAxis: .z, rotation: .degrees(90)), tag: newTag())
        #expect(isClose(turned.bounds.size.y, 10, relative: 1e-3))
        #expect(isClose(turned.bounds.size.x, 2, relative: 1e-3))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter BooleanConformanceTests`
Expected: FAIL with `unsupported("boolean")` and `unsupported("transform")` errors. They compile, because the stubs exist.

- [ ] **Step 3: Extend the header**

Add to `cocct.h`:
```c
/// Boolean of `a` with `tools` (op 0 fuse, 1 cut, 2 common). History operands: 0 = a, i+1 = tools[i].
occt_shape *occt_boolean(int op, const occt_shape *a, const occt_shape *const *tools, int tool_count,
                         occt_history *history, occt_status *status);
/// Rotates about the axis (if has_rotation) and then translates. History operand 0 = shape.
occt_shape *occt_transform(const occt_shape *shape, const double translation[3], int has_rotation,
                           const double axis_origin[3], const double axis_direction[3], double angle,
                           occt_history *history, occt_status *status);
```

- [ ] **Step 4: Implement `cocct_ops.cpp`**

`Sources/COCCT/cocct_ops.cpp`:
```cpp
#include "cocct_internal.hpp"

#include <BRepAlgoAPI_BooleanOperation.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepBuilderAPI_MakeShape.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <gp_Ax1.hxx>
#include <gp_Trsf.hxx>
#include <gp_Vec.hxx>

#include <cmath>
#include <memory>

using namespace cocct;

namespace {

/// Records where each face of `input` ended up: itself if kept, its pieces if modified,
/// nothing if deleted.
void add_face_history(history_builder &records, BRepBuilderAPI_MakeShape &algo, const TopoDS_Shape &input, int operand) {
    const TopTools_IndexedMapOfShape faces = map_of(input, TopAbs_FACE);
    for (int j = 1; j <= faces.Extent(); ++j) {
        const TopoDS_Shape &face = faces(j);
        if (algo.IsDeleted(face)) {
            continue;
        }
        const TopTools_ListOfShape &modified = algo.Modified(face);
        if (modified.IsEmpty()) {
            records.add(face, OCCT_FROM_FACE, operand, j);
        } else {
            records.add_all(modified, OCCT_FROM_FACE, operand, j);
        }
    }
}

bool has_solid(const TopoDS_Shape &shape) {
    return TopExp_Explorer(shape, TopAbs_SOLID).More();
}

} // namespace

extern "C" {

occt_shape *occt_boolean(int op, const occt_shape *a, const occt_shape *const *tools, int tool_count,
                         occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!a || !tools || tool_count <= 0) {
            set_error(status, "a boolean needs a solid and at least one tool");
            return nullptr;
        }
        std::unique_ptr<BRepAlgoAPI_BooleanOperation> algo;
        switch (op) {
        case 0: algo = std::make_unique<BRepAlgoAPI_Fuse>(); break;
        case 1: algo = std::make_unique<BRepAlgoAPI_Cut>(); break;
        case 2: algo = std::make_unique<BRepAlgoAPI_Common>(); break;
        default: set_error(status, "unknown boolean operation"); return nullptr;
        }
        TopTools_ListOfShape arguments;
        arguments.Append(a->shape);
        TopTools_ListOfShape toolList;
        for (int i = 0; i < tool_count; ++i) {
            toolList.Append(tools[i]->shape);
        }
        algo->SetArguments(arguments);
        algo->SetTools(toolList);
        algo->Build();
        if (!algo->IsDone() || algo->HasErrors()) {
            set_error(status, "the boolean could not be computed");
            return nullptr;
        }
        if (op != 2) {
            algo->SimplifyResult();
        }
        const TopoDS_Shape result = algo->Shape();
        if (result.IsNull() || !has_solid(result)) {
            set_error(status, "the result is empty");
            return nullptr;
        }
        history_builder records(result);
        add_face_history(records, *algo, a->shape, 0);
        for (int i = 0; i < tool_count; ++i) {
            add_face_history(records, *algo, tools[i]->shape, i + 1);
        }
        records.move_into(history);
        return new occt_shape{result};
    });
}

occt_shape *occt_transform(const occt_shape *shape, const double translation[3], int has_rotation,
                           const double axis_origin[3], const double axis_direction[3], double angle,
                           occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        gp_Trsf rotation;
        if (has_rotation) {
            rotation.SetRotation(gp_Ax1(gp_Pnt(axis_origin[0], axis_origin[1], axis_origin[2]),
                                        gp_Dir(axis_direction[0], axis_direction[1], axis_direction[2])),
                                 angle);
        }
        gp_Trsf move;
        move.SetTranslation(gp_Vec(translation[0], translation[1], translation[2]));
        const gp_Trsf total = move.Multiplied(rotation); // rotation first, then translation
        BRepBuilderAPI_Transform transform(shape->shape, total, Standard_True);
        if (!transform.IsDone()) {
            set_error(status, "the transform could not be applied");
            return nullptr;
        }
        const TopoDS_Shape result = transform.Shape();
        history_builder records(result);
        add_face_history(records, transform, shape->shape, 0);
        records.move_into(history);
        return new occt_shape{result};
    });
}

} // extern "C"
```

- [ ] **Step 5: Implement the Swift side**

`Sources/CreatorOCCT/OCCTShape+Operations.swift`:
```swift
import COCCT
import CreatorGeometry
import CreatorKernel

extension OCCTShape {
    static func boolean(_ op: BooleanOp, _ a: OCCTShape, _ tools: [OCCTShape]) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let code: Int32 = switch op {
        case .union: 0
        case .subtract: 1
        case .intersect: 2
        }
        let pointers: [OpaquePointer?] = tools.map(\.raw)
        return try pointers.withUnsafeBufferPointer { buffer throws(OCCTError) in
            try building { history, status in
                occt_boolean(code, a.raw, buffer.baseAddress, Int32(buffer.count), history, status)
            }
        }
    }

    func transformed(by transform: Transform) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let translation = [transform.translation.x, transform.translation.y, transform.translation.z]
        let axis = transform.rotationAxis ?? Axis.z
        let origin = [axis.origin.x, axis.origin.y, axis.origin.z]
        let direction = [axis.direction.x, axis.direction.y, axis.direction.z]
        let hasRotation: Int32 = transform.rotationAxis != nil && transform.rotation.radians != 0 ? 1 : 0
        return try Self.building { history, status in
            occt_transform(raw, translation, hasRotation, origin, direction, transform.rotation.radians, history, status)
        }
    }
}
```

In `OCCTKernel.swift`, replace the `boolean` and `transform` stubs:
```swift
    public func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard !b.isEmpty else { throw KernelError.invalidInput("Connect at least one tool solid.") }
        let operation = switch op {
        case .union: "union"
        case .subtract: "subtract"
        case .intersect: "intersect"
        }
        let target = try shape(of: a)
        let tools = try b.map { try shape(of: $0) }
        return try build(operation, inputs: [a.topology] + b.map(\.topology), tag: tag) {
            try OCCTShape.boolean(op, target, tools)
        }
    }

    public func transform(_ solid: Solid, by transform: Transform, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard transform.translation.isFinite, transform.rotation.radians.isFinite else {
            throw KernelError.invalidInput("The move or rotation must be a finite number.")
        }
        if let axis = transform.rotationAxis, axis.direction.normalized == nil {
            throw KernelError.invalidInput("The rotation axis needs a direction.")
        }
        let source = try shape(of: solid)
        return try build("transform", inputs: [solid.topology], tag: tag) { try source.transformed(by: transform) }
    }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter "BooleanConformanceTests|ExtrudeConformanceTests"`, then `swift test`.
Expected: all PASS. If `subtractingHolesKeepsPlateTagsAndNamesHoleWalls` finds more than 10 faces because `SimplifyResult` didn't merge something, report the actual count and the face kinds before changing the assertion. The assertion encodes the spec's expectation.

- [ ] **Step 7: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): booleans and transforms that carry face tags"
```

### Task 5: Fillet and chamfer

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct_ops.cpp`, `Sources/CreatorOCCT/OCCTShape+Operations.swift`, `Sources/CreatorOCCT/OCCTKernel.swift`
- Test: `Tests/CreatorOCCTTests/FeatureConformanceTests.swift`

**Interfaces:**
- Consumes: Task 4 (`add_face_history`, `building`) and Task 3's tagger (`.edge` records become `.blend`).
- Produces:
  - C: `occt_fillet(shape, edge_indices, count, radius, history, status)` and `occt_chamfer(shape, edge_indices, count, distance, history, status)`. Edge indices are 1-based. History records kept faces with `OCCT_FROM_FACE` (operand 0) and blend faces with `OCCT_FROM_EDGE` (operand 0, input edge index).
  - Swift: `OCCTShape.blended(edges:size:chamfer:)`. `OCCTKernel.fillet` and `OCCTKernel.chamfer` are real from this task.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/FeatureConformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct FeatureConformanceTests {
    /// The four 30 mm vertical edges of a 10 × 20 × 30 box.
    func verticalEdges(_ solid: Solid) -> [EdgeInfo] {
        solid.topology.edges.filter { $0.kind == .line && isClose($0.length, 30) }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func filletRemovesTheAnalyticVolumeAndNamesTheBlend(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let key = try #require(solid.topology.key(of: edge))
        let filletTag = newTag()
        let result = try await kernel.fillet(solid, edges: [edge.id], radius: 2, tag: filletTag)
        #expect(isClose(try await kernel.properties(of: result).volume, 6000 - (4 - Double.pi) * 30))
        #expect(result.topology.faces.count == 7)
        let blends = faces(result, role: .blend(sourceEdge: key), of: filletTag)
        #expect(blends.count == 1)
        #expect(blends.first?.kind == .cylinder)
        // The six original faces keep their extrude tags.
        #expect(result.topology.faces.filter { face in face.tags.contains { $0.node != filletTag.node } }.count == 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func filletingAllVerticalEdgesKeepsEveryFaceNamed(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let result = try await kernel.fillet(solid, edges: verticalEdges(solid).map(\.id), radius: 1, tag: newTag())
        #expect(result.topology.faces.count == 10)
        #expect(result.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func chamferRemovesTheAnalyticVolume(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let result = try await kernel.chamfer(solid, edges: [edge.id], distance: 1, tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 6000 - 0.5 * 30))
        #expect(result.topology.faces.count == 7)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func impossibleFilletFailsCleanlyAndKernelRecovers(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: [edge.id], radius: 40, tag: newTag())
        }
        guard case .filletFailed(let radius, _, let reason)? = error else { Issue.record("expected filletFailed"); return }
        #expect(radius == 40)
        #expect(!reason.isEmpty)
        #expect(error?.userMessage.contains("40") == true)
        // The kernel is still usable.
        let ok = try await kernel.fillet(solid, edges: [edge.id], radius: 1, tag: newTag())
        #expect(ok.topology.faces.count == 7)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func featureInputsAreValidated(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        await #expect(throws: KernelError.invalidInput("No edges are selected.")) {
            try await kernel.fillet(solid, edges: [], radius: 1, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("Edge 999 doesn't exist on the input solid.")) {
            try await kernel.fillet(solid, edges: [EdgeID(999)], radius: 1, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The size must be greater than 0 mm.")) {
            try await kernel.chamfer(solid, edges: [EdgeID(0)], distance: .nan, tag: newTag())
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter FeatureConformanceTests`
Expected: FAIL with `unsupported("fillet")` and `unsupported("chamfer")`.

- [ ] **Step 3: Extend the header**

```c
/// Fillets the edges (1-based indices) with `radius`. History operand 0 = shape:
/// OCCT_FROM_FACE for kept/modified faces, OCCT_FROM_EDGE (index = input edge) for blend faces.
occt_shape *occt_fillet(const occt_shape *shape, const int *edge_indices, int count, double radius,
                        occt_history *history, occt_status *status);
/// Equal-distance chamfer of the edges; same history contract as occt_fillet.
occt_shape *occt_chamfer(const occt_shape *shape, const int *edge_indices, int count, double distance,
                         occt_history *history, occt_status *status);
```

- [ ] **Step 4: Implement them in `cocct_ops.cpp`**

Add these includes:
```cpp
#include <BRepFilletAPI_MakeChamfer.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <TopoDS_Edge.hxx>
```

Add to the anonymous namespace:
```cpp
/// Shared body of fillet and chamfer: `Algo` is BRepFilletAPI_MakeFillet or _MakeChamfer.
template <typename Algo>
occt_shape *blend(const occt_shape *shape, const int *edge_indices, int count, double size,
                  occt_history *history, occt_status *status, const char *failure) {
    *history = occt_history{};
    if (!shape || !edge_indices || count <= 0 || !std::isfinite(size) || size <= 0) {
        set_error(status, "a blend needs edges and a size greater than 0");
        return nullptr;
    }
    const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
    Algo algo(shape->shape);
    for (int i = 0; i < count; ++i) {
        if (edge_indices[i] < 1 || edge_indices[i] > edges.Extent()) {
            set_error(status, "edge index out of range");
            return nullptr;
        }
        algo.Add(size, TopoDS::Edge(edges(edge_indices[i])));
    }
    algo.Build();
    if (!algo.IsDone()) {
        set_error(status, failure);
        return nullptr;
    }
    const TopoDS_Shape result = algo.Shape();
    history_builder records(result);
    add_face_history(records, algo, shape->shape, 0);
    for (int i = 0; i < count; ++i) {
        records.add_all(algo.Generated(edges(edge_indices[i])), OCCT_FROM_EDGE, 0, edge_indices[i]);
    }
    records.move_into(history);
    return new occt_shape{result};
}
```

Add inside `extern "C"`:
```cpp
occt_shape *occt_fillet(const occt_shape *shape, const int *edge_indices, int count, double radius,
                        occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        return blend<BRepFilletAPI_MakeFillet>(shape, edge_indices, count, radius, history, status,
                                               "the fillet could not be built for this radius");
    });
}

occt_shape *occt_chamfer(const occt_shape *shape, const int *edge_indices, int count, double distance,
                         occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        return blend<BRepFilletAPI_MakeChamfer>(shape, edge_indices, count, distance, history, status,
                                                "the chamfer could not be built for this distance");
    });
}
```

- [ ] **Step 5: Implement the Swift side**

Add to `OCCTShape+Operations.swift`:
```swift
    /// Fillets (or chamfers) the given 0-based edge IDs.
    func blended(edges: [EdgeID], size: Double, chamfer: Bool) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let indices = edges.map { Int32($0.rawValue + 1) }
        return try indices.withUnsafeBufferPointer { buffer throws(OCCTError) in
            try Self.building { history, status in
                chamfer
                    ? occt_chamfer(raw, buffer.baseAddress, Int32(buffer.count), size, history, status)
                    : occt_fillet(raw, buffer.baseAddress, Int32(buffer.count), size, history, status)
            }
        }
    }
```

In `OCCTKernel.swift`, replace the `fillet` and `chamfer` stubs and add the shared helper:
```swift
    public func fillet(_ solid: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: radius, chamfer: false, tag: tag)
    }

    public func chamfer(_ solid: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        return try blend(solid, edges: edges, size: distance, chamfer: true, tag: tag)
    }

    private func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let operation = chamfer ? "chamfer" : "fillet"
        do {
            return try build(operation, inputs: [solid.topology], tag: tag) {
                try source.blended(edges: edges, size: size, chamfer: chamfer)
            }
        } catch KernelError.operationFailed(_, let reason) where !chamfer {
            throw KernelError.filletFailed(radius: size, maxRadius: nil, reason: reason)
        }
    }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter "FeatureConformanceTests|BooleanConformanceTests"`, then `swift test`.
Expected: all PASS. The plan doesn't pin the exact `reason` text for the radius-40 fillet. It only has to be non-empty, and the user message has to contain "40".

- [ ] **Step 7: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): fillet and chamfer with blend faces named by source edge"
```

### Task 6: Revolve and loft

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct_build.cpp`, `Sources/CreatorOCCT/OCCTShape+Build.swift`, `Sources/CreatorOCCT/OCCTKernel.swift`
- Test: `Tests/CreatorOCCTTests/SweepConformanceTests.swift`

**Interfaces:**
- Consumes: Task 3 (`build_profile`, `oriented`, `OCCTProfile.with`/`withAll`, `building`).
- Produces:
  - C: `occt_revolve(profile, axis_origin[3], axis_direction[3], angle, history, status)`, with caps only for a partial revolve
  - C: `occt_loft(profiles, count, ruled, history, status)`. Sides are `OCCT_FROM_SEGMENT` with the index of the first section's segment.
  - Swift: `OCCTShape.revolve(_:axis:angle:)` and `OCCTShape.loft(_:ruled:)`. `OCCTKernel.revolve` and `OCCTKernel.loft` are real from this task.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/SweepConformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct SweepConformanceTests {
    /// A 5 × 4 rectangle on the XZ plane spanning x 5…10, z 0…4 (a tube cross-section).
    let ring = Profile2D.rectangle(width: 5, height: 4, plane: Plane(origin: Vector3(7.5, 0, 2), normal: -.unitY, xAxis: .unitX))

    @Test(arguments: KernelUnderTest.allCases)
    func fullRevolveMakesATube(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let tube = try await kernel.revolve(ring, axis: .z, angle: .degrees(360), tag: tag)
        #expect(isClose(try await kernel.properties(of: tube).volume, Double.pi * (100 - 25) * 4, relative: 1e-5))
        #expect(tube.topology.faces.count == 4)
        #expect(faces(tube, role: .startCap, of: tag).isEmpty)
        for k in 0..<4 {
            #expect(faces(tube, role: .side(segment: k), of: tag).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func partialRevolveHasCaps(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let quarter = try await kernel.revolve(ring, axis: .z, angle: .degrees(90), tag: tag)
        #expect(isClose(try await kernel.properties(of: quarter).volume, Double.pi * (100 - 25) * 4 / 4, relative: 1e-5))
        #expect(faces(quarter, role: .startCap, of: tag).count == 1)
        #expect(faces(quarter, role: .endCap, of: tag).count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func revolveInputsAreValidated(_ under: KernelUnderTest) async {
        let kernel = under.make()
        await #expect(throws: KernelError.invalidInput("The revolve angle must be between 0° and 360°.")) {
            try await kernel.revolve(ring, axis: .z, angle: .degrees(0), tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The revolve axis needs a direction.")) {
            try await kernel.revolve(ring, axis: Axis(origin: .zero, direction: .zero), angle: .degrees(90), tag: newTag())
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func ruledLoftBetweenSquaresIsAFrustum(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let tag = newTag()
        let bottom = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let top = Profile2D.rectangle(width: 6, height: 6, plane: Plane.xy.offset(by: 10))
        let frustum = try await kernel.loft([bottom, top], ruled: true, tag: tag)
        #expect(isClose(try await kernel.properties(of: frustum).volume, 10.0 / 3.0 * (100 + 36 + 60), relative: 1e-5))
        #expect(frustum.topology.faces.count == 6)
        #expect(faces(frustum, role: .startCap, of: tag).count == 1)
        #expect(faces(frustum, role: .endCap, of: tag).count == 1)
        for k in 0..<4 {
            #expect(faces(frustum, role: .side(segment: k), of: tag).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func loftInputsAreValidated(_ under: KernelUnderTest) async {
        let kernel = under.make()
        let square = Profile2D.rectangle(width: 1, height: 1, plane: .xy)
        await #expect(throws: KernelError.invalidInput("A loft needs at least two sections.")) {
            try await kernel.loft([square], ruled: true, tag: newTag())
        }
        let circle = Profile2D.circle(radius: 1, center: .zero, plane: Plane.xy.offset(by: 5))
        await #expect(throws: KernelError.invalidInput("Every loft section needs the same number of segments.")) {
            try await kernel.loft([square, circle], ruled: true, tag: newTag())
        }
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter SweepConformanceTests`
Expected: FAIL with `unsupported("revolve")` and `unsupported("loft")`.

- [ ] **Step 3: Extend the header**

```c
/// Revolves the profile about the axis by `angle` (radians, 0 < angle <= 2π). Caps
/// (OCCT_FROM_START_CAP/END_CAP) exist only for a partial revolve; sides are OCCT_FROM_SEGMENT.
occt_shape *occt_revolve(const occt_profile *profile, const double axis_origin[3], const double axis_direction[3],
                         double angle, occt_history *history, occt_status *status);
/// Lofts through `count` profiles (ruled = straight sides). Sides are OCCT_FROM_SEGMENT with the
/// index of the first section's segment; caps are the first and last sections.
occt_shape *occt_loft(const occt_profile *profiles, int count, int ruled, occt_history *history, occt_status *status);
```

- [ ] **Step 4: Implement them in `cocct_build.cpp`**

Add these includes:
```cpp
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepTools.hxx>
#include <gp_Ax1.hxx>
```

Add inside `extern "C"`:
```cpp
occt_shape *occt_revolve(const occt_profile *profile, const double axis_origin[3], const double axis_direction[3],
                         double angle, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profile || !std::isfinite(angle) || angle <= 0 || angle > 2 * M_PI + 1e-9) {
            set_error(status, "the revolve angle must be between 0 and 360 degrees");
            return nullptr;
        }
        const built_profile built = build_profile(*profile);
        const gp_Ax1 axis(gp_Pnt(axis_origin[0], axis_origin[1], axis_origin[2]),
                          gp_Dir(axis_direction[0], axis_direction[1], axis_direction[2]));
        BRepPrimAPI_MakeRevol revol(built.face, axis, std::min(angle, 2 * M_PI));
        revol.Build();
        if (!revol.IsDone()) {
            set_error(status, "the revolve could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(revol.Shape());
        history_builder records(solid);
        records.add(revol.FirstShape(), OCCT_FROM_START_CAP, 0, 0); // absent from a full revolve
        records.add(revol.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        for (int k = 0; k < static_cast<int>(built.edges.size()); ++k) {
            records.add_all(revol.Generated(built.edges[k]), OCCT_FROM_SEGMENT, 0, k);
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}

occt_shape *occt_loft(const occt_profile *profiles, int count, int ruled, occt_history *history, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        if (!profiles || count < 2) {
            set_error(status, "a loft needs at least two sections");
            return nullptr;
        }
        std::vector<built_profile> sections;
        BRepOffsetAPI_ThruSections loft(Standard_True, ruled ? Standard_True : Standard_False);
        for (int i = 0; i < count; ++i) {
            sections.push_back(build_profile(profiles[i]));
            loft.AddWire(BRepTools::OuterWire(sections.back().face));
        }
        loft.Build();
        if (!loft.IsDone()) {
            set_error(status, "the loft could not be built");
            return nullptr;
        }
        const TopoDS_Shape solid = oriented(loft.Shape());
        history_builder records(solid);
        records.add(loft.FirstShape(), OCCT_FROM_START_CAP, 0, 0);
        records.add(loft.LastShape(), OCCT_FROM_END_CAP, 0, 0);
        const std::vector<TopoDS_Edge> &first = sections.front().edges;
        for (int k = 0; k < static_cast<int>(first.size()); ++k) {
            records.add(loft.GeneratedFace(first[k]), OCCT_FROM_SEGMENT, 0, k);
        }
        records.move_into(history);
        return new occt_shape{solid};
    });
}
```
Also add `#include <algorithm>` to `cocct_build.cpp` for `std::min`.

- [ ] **Step 5: Implement the Swift side**

Add to `OCCTShape+Build.swift`:
```swift
    static func revolve(_ profile: Profile2D, axis: Axis, angle: Angle) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        let origin = [axis.origin.x, axis.origin.y, axis.origin.z]
        let direction = [axis.direction.x, axis.direction.y, axis.direction.z]
        return try OCCTProfile.with(profile) { cProfile throws(OCCTError) in
            try building { history, status in occt_revolve(cProfile, origin, direction, angle.radians, history, status) }
        }
    }

    static func loft(_ sections: [Profile2D], ruled: Bool) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord]) {
        try OCCTProfile.withAll(sections) { profiles, count throws(OCCTError) in
            try building { history, status in occt_loft(profiles, Int32(count), ruled ? 1 : 0, history, status) }
        }
    }
```

In `OCCTKernel.swift`, replace the stubs:
```swift
    public func revolve(_ profile: Profile2D, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard angle.radians.isFinite, angle.radians > 0, angle.radians <= 2 * .pi + 1e-9 else {
            throw KernelError.invalidInput("The revolve angle must be between 0° and 360°.")
        }
        guard axis.direction.normalized != nil, axis.origin.isFinite else {
            throw KernelError.invalidInput("The revolve axis needs a direction.")
        }
        guard profile.isClosed else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        return try build("revolve", inputs: [], tag: tag) { try OCCTShape.revolve(profile, axis: axis, angle: angle) }
    }

    public func loft(_ sections: [Profile2D], ruled: Bool, tag: NodeTag) throws -> Solid {
        try Task.checkCancellation()
        guard sections.count >= 2 else { throw KernelError.invalidInput("A loft needs at least two sections.") }
        guard Set(sections.map(\.segments.count)).count == 1 else {
            throw KernelError.invalidInput("Every loft section needs the same number of segments.")
        }
        guard sections.allSatisfy(\.isClosed) else { throw KernelError.invalidInput("The profile is not a closed loop.") }
        return try build("loft", inputs: [], tag: tag) { try OCCTShape.loft(sections, ruled: ruled) }
    }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter SweepConformanceTests`, then `swift test`.
Expected: all PASS. If the full revolve reports 5 faces (OCCT can split a full revolution at a seam), report the face kinds before you touch the assertion.

- [ ] **Step 7: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): revolve and loft with capped, segment-named faces"
```

### Task 7: Tessellation, export and STEP read-back

**Files:**
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/CreatorOCCT/OCCTKernel.swift`
- Create: `Sources/COCCT/cocct_mesh.cpp`, `Sources/CreatorOCCT/OCCTShape+Mesh.swift`
- Test: `Tests/CreatorOCCTTests/MeshExportConformanceTests.swift`

**Interfaces:**
- Consumes: Task 2 (`distinct_faces`, `copy_out`) and the M0 writers `writeSTEP`/`writeSTL`.
- Produces:
  - C: `occt_mesh`, `occt_tessellate(shape, tolerance, mesh, status)`, `occt_mesh_free`, `occt_make_compound(shapes, count, status)` and `occt_read_step(path, status)`
  - Swift: `OCCTShape.mesh(tolerance:) throws -> DisplayMesh`, `OCCTShape.compound(_:)` and `OCCTShape.readSTEP(_:)`. The last is used by tests only.
  - `OCCTKernel.tessellate` and `OCCTKernel.export` are real from this task.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/MeshExportConformanceTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct MeshExportConformanceTests {
    @Test(arguments: KernelUnderTest.allCases)
    func boxMeshCoversEveryFaceAndEdge(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let mesh = try await kernel.tessellate(solid, tolerance: 0.1)
        #expect(mesh.indices.count % 3 == 0)
        #expect(mesh.triangleFaces.count == mesh.indices.count / 3)
        #expect(mesh.triangleFaces.count >= 12)
        #expect(Set(mesh.triangleFaces) == Set(solid.topology.faces.map(\.id)))
        #expect(mesh.normals.count == mesh.positions.count)
        #expect(mesh.normals.allSatisfy { isClose($0.length, 1, relative: 1e-6) })
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
        let slack = Vector3(1e-6, 1e-6, 1e-6)
        #expect(mesh.positions.allSatisfy { p in
            p.x >= solid.bounds.min.x - slack.x && p.x <= solid.bounds.max.x + slack.x
                && p.z >= solid.bounds.min.z - slack.z && p.z <= solid.bounds.max.z + slack.z
        })
        #expect(mesh.edgePolylines.count == 12)
        #expect(mesh.edgePolylines.values.allSatisfy { $0.count >= 2 })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func meshNormalsPointOutward(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 2, 2, 2)
        let mesh = try await kernel.tessellate(solid, tolerance: 0.1)
        let center = solid.bounds.center
        for triangle in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.positions[Int(mesh.indices[triangle])]
            let b = mesh.positions[Int(mesh.indices[triangle + 1])]
            let c = mesh.positions[Int(mesh.indices[triangle + 2])]
            let winding = (b - a).cross(c - a)
            #expect(winding.dot(a - center) > 0, "triangle \(triangle / 3) is wound inward")
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func seamEdgesHaveNoPolyline(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let rod = try await kernel.extrude(.circle(radius: 2, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: newTag())
        let mesh = try await kernel.tessellate(rod, tolerance: 0.05)
        let seams = rod.topology.edges.filter(\.isSeam).map(\.id)
        #expect(!seams.isEmpty)
        #expect(seams.allSatisfy { mesh.edgePolylines[$0] == nil })
        #expect(mesh.edgePolylines.count == 2)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func stepExportRoundTripsVolumeAndFaces(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let a = try await box(kernel, 10, 20, 30)
        let edge = try #require(a.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let filleted = try await kernel.fillet(a, edges: [edge.id], radius: 2, tag: newTag())
        let b = try await kernel.transform(try await box(kernel, 5, 5, 5), by: Transform(translation: Vector3(50, 0, 0)), tag: newTag())
        let url = URL.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([filleted, b], format: .step, to: url)
        let read = try OCCTShape.readSTEP(url)
        let expected = try await kernel.properties(of: filleted).volume + 125
        #expect(isClose(try read.properties().volume, expected, relative: 1e-5))
        #expect(try OCCTRawTopology.read(read).faces.count == 7 + 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func stlExportIsClosedAndManifold(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(.circle(radius: 3, center: .zero, plane: .xy), distance: 4, mode: .oneSided, tag: newTag())
        let url = URL.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .stl, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(edgeUseCounts(stl: text).values.allSatisfy { $0 == 2 }, "every mesh edge must be shared by exactly two triangles")
    }

    @Test(arguments: KernelUnderTest.allCases)
    func exportToAnUnwritablePathIsAPlainError(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 1, 1, 1)
        for format in ExportFormat.allCases {
            let error = await #expect(throws: KernelError.self) {
                try await kernel.export([solid], format: format, to: URL(filePath: "/nonexistent-directory/out.\(format.rawValue)"))
            }
            guard case .exportFailed? = error else { Issue.record("expected exportFailed for \(format)"); continue }
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func exportingNothingIsRejected(_ under: KernelUnderTest) async {
        await #expect(throws: KernelError.invalidInput("There is nothing to export.")) {
            try await under.make().export([], format: .step, to: URL.temporaryDirectory.appending(path: "empty.step"))
        }
    }

    /// Counts how many triangles use each undirected edge, after welding vertices to 1e-6 mm.
    func edgeUseCounts(stl: String) -> [String: Int] {
        func key(_ line: Substring) -> String {
            line.split(separator: " ").dropFirst().prefix(3).map { (Double($0) ?? .nan).formatted(.number.precision(.fractionLength(6))) }
                .joined(separator: ",")
        }
        let vertices = stl.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("vertex") }.map { key(Substring($0)) }
        var counts: [String: Int] = [:]
        for triangle in stride(from: 0, to: vertices.count - 2, by: 3) {
            let corners = [vertices[triangle], vertices[triangle + 1], vertices[triangle + 2]]
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let edge = [corners[a], corners[b]].sorted().joined(separator: "|")
                counts[edge, default: 0] += 1
            }
        }
        return counts
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift test --filter MeshExportConformanceTests`
Expected: compile errors, "type 'OCCTShape' has no member 'readSTEP'".

- [ ] **Step 3: Extend the header**

```c
/// Triangles per face plus B-rep edge polylines. Free with occt_mesh_free.
/// edge_offsets has edge_count + 1 entries: points of edge e (0-based) are
/// edge_points[3*edge_offsets[e] ..< 3*edge_offsets[e+1]]; seams and degenerate edges are empty.
typedef struct {
    double *positions;
    double *normals;
    int vertex_count;
    unsigned int *indices;
    int *triangle_faces;
    int triangle_count;
    double *edge_points;
    int *edge_offsets;
    int edge_count;
} occt_mesh;

int occt_tessellate(const occt_shape *shape, double tolerance, occt_mesh *out, occt_status *status);
void occt_mesh_free(occt_mesh *mesh);
/// A compound of copies-by-reference of the given shapes.
occt_shape *occt_make_compound(const occt_shape *const *shapes, int count, occt_status *status);
/// Reads a STEP file into one shape (a compound for several bodies).
occt_shape *occt_read_step(const char *path, occt_status *status);
```

- [ ] **Step 4: Implement `cocct_mesh.cpp`**

`Sources/COCCT/cocct_mesh.cpp`:
```cpp
#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <Poly_Triangulation.hxx>
#include <STEPControl_Reader.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>

#include <cmath>

using namespace cocct;

extern "C" {

int occt_tessellate(const occt_shape *shape, double tolerance, occt_mesh *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_mesh{};
        if (!std::isfinite(tolerance) || tolerance <= 0) {
            set_error(status, "the tessellation tolerance must be greater than 0");
            return 0;
        }
        BRepMesh_IncrementalMesh mesher(shape->shape, tolerance, Standard_False, 0.5, Standard_False);
        const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
        std::vector<double> positions, normals;
        std::vector<unsigned int> indices;
        std::vector<int> triangle_faces;
        for (int i = 1; i <= faces.Extent(); ++i) {
            const TopoDS_Face face = TopoDS::Face(faces(i));
            TopLoc_Location location;
            const Handle(Poly_Triangulation) &triangulation = BRep_Tool::Triangulation(face, location);
            if (triangulation.IsNull()) {
                continue;
            }
            BRepLib_ToolTriangulatedShape::ComputeNormals(face, triangulation);
            const gp_Trsf transform = location.Transformation();
            const bool reversed = face.Orientation() == TopAbs_REVERSED;
            const unsigned int base = static_cast<unsigned int>(positions.size() / 3);
            for (int n = 1; n <= triangulation->NbNodes(); ++n) {
                const gp_Pnt point = triangulation->Node(n).Transformed(transform);
                positions.insert(positions.end(), {point.X(), point.Y(), point.Z()});
                gp_Vec normal(triangulation->Normal(n));
                normal.Transform(transform);
                if (reversed) {
                    normal.Reverse();
                }
                if (normal.Magnitude() > 1e-12) {
                    normal.Normalize();
                }
                normals.insert(normals.end(), {normal.X(), normal.Y(), normal.Z()});
            }
            for (int t = 1; t <= triangulation->NbTriangles(); ++t) {
                int a = 0, b = 0, c = 0;
                triangulation->Triangle(t).Get(a, b, c);
                if (reversed) {
                    std::swap(b, c);
                }
                indices.insert(indices.end(), {base + a - 1, base + b - 1, base + c - 1});
                triangle_faces.push_back(i - 1);
            }
        }

        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        std::vector<double> edge_points;
        std::vector<int> edge_offsets{0};
        for (int e = 1; e <= edges.Extent(); ++e) {
            const TopoDS_Edge edge = TopoDS::Edge(edges(e));
            const bool seam = distinct_faces(edge, edge_faces).size() == 1;
            if (!BRep_Tool::Degenerated(edge) && !seam) {
                BRepAdaptor_Curve curve(edge);
                GCPnts_TangentialDeflection sampler(curve, 0.1, tolerance);
                for (int p = 1; p <= sampler.NbPoints(); ++p) {
                    const gp_Pnt point = sampler.Value(p);
                    edge_points.insert(edge_points.end(), {point.X(), point.Y(), point.Z()});
                }
            }
            edge_offsets.push_back(static_cast<int>(edge_points.size() / 3));
        }

        out->positions = copy_out(positions);
        out->normals = copy_out(normals);
        out->indices = copy_out(indices);
        out->triangle_faces = copy_out(triangle_faces);
        out->edge_points = copy_out(edge_points);
        out->edge_offsets = copy_out(edge_offsets);
        out->vertex_count = static_cast<int>(positions.size() / 3);
        out->triangle_count = static_cast<int>(triangle_faces.size());
        out->edge_count = edges.Extent();
        return 1;
    });
}

void occt_mesh_free(occt_mesh *mesh) {
    if (mesh) {
        std::free(mesh->positions);
        std::free(mesh->normals);
        std::free(mesh->indices);
        std::free(mesh->triangle_faces);
        std::free(mesh->edge_points);
        std::free(mesh->edge_offsets);
        *mesh = occt_mesh{};
    }
}

occt_shape *occt_make_compound(const occt_shape *const *shapes, int count, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!shapes || count <= 0) {
            set_error(status, "there is nothing to combine");
            return nullptr;
        }
        BRep_Builder builder;
        TopoDS_Compound compound;
        builder.MakeCompound(compound);
        for (int i = 0; i < count; ++i) {
            builder.Add(compound, shapes[i]->shape);
        }
        return new occt_shape{compound};
    });
}

occt_shape *occt_read_step(const char *path, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        if (!path) {
            set_error(status, "no file path given");
            return nullptr;
        }
        occt_initialize();
        STEPControl_Reader reader;
        if (reader.ReadFile(path) != IFSelect_RetDone) {
            set_error(status, "the STEP file could not be read");
            return nullptr;
        }
        reader.TransferRoots();
        const TopoDS_Shape shape = reader.OneShape();
        if (shape.IsNull()) {
            set_error(status, "the STEP file contains no shapes");
            return nullptr;
        }
        return new occt_shape{shape};
    });
}

} // extern "C"
```

- [ ] **Step 5: Implement the Swift side**

`Sources/CreatorOCCT/OCCTShape+Mesh.swift`:
```swift
import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

extension OCCTShape {
    func mesh(tolerance: Double) throws(OCCTError) -> DisplayMesh {
        var raw = occt_mesh()
        defer { occt_mesh_free(&raw) }
        try Self.check { status in occt_tessellate(self.raw, tolerance, &raw, status) }
        let vertexCount = Int(raw.vertex_count)
        let coordinates = UnsafeBufferPointer(start: raw.positions, count: vertexCount * 3)
        let normalCoordinates = UnsafeBufferPointer(start: raw.normals, count: vertexCount * 3)
        let positions = (0..<vertexCount).map { Vector3(coordinates[$0 * 3], coordinates[$0 * 3 + 1], coordinates[$0 * 3 + 2]) }
        let normals = (0..<vertexCount).map {
            Vector3(normalCoordinates[$0 * 3], normalCoordinates[$0 * 3 + 1], normalCoordinates[$0 * 3 + 2])
        }
        let triangleCount = Int(raw.triangle_count)
        let indices = Array(UnsafeBufferPointer(start: raw.indices, count: triangleCount * 3))
        let triangleFaces = UnsafeBufferPointer(start: raw.triangle_faces, count: triangleCount).map { FaceID(Int($0)) }
        let offsets = UnsafeBufferPointer(start: raw.edge_offsets, count: Int(raw.edge_count) + 1)
        let points = UnsafeBufferPointer(start: raw.edge_points, count: Int(offsets.last ?? 0) * 3)
        var polylines: [EdgeID: [Vector3]] = [:]
        for edge in 0..<Int(raw.edge_count) where offsets[edge + 1] > offsets[edge] {
            polylines[EdgeID(edge)] = (Int(offsets[edge])..<Int(offsets[edge + 1])).map {
                Vector3(points[$0 * 3], points[$0 * 3 + 1], points[$0 * 3 + 2])
            }
        }
        return DisplayMesh(positions: positions, normals: normals, indices: indices, triangleFaces: triangleFaces,
                           edgePolylines: polylines)
    }

    static func compound(_ shapes: [OCCTShape]) throws(OCCTError) -> OCCTShape {
        let pointers: [OpaquePointer?] = shapes.map(\.raw)
        return try pointers.withUnsafeBufferPointer { buffer throws(OCCTError) in
            try make { status in occt_make_compound(buffer.baseAddress, Int32(buffer.count), status) }
        }
    }

    /// Reads a STEP file. Used by the conformance tests; STEP import as a node is deferred (spec §11).
    static func readSTEP(_ url: URL) throws(OCCTError) -> OCCTShape {
        try make { status in url.withUnsafeFileSystemRepresentation { occt_read_step($0, status) } }
    }
}
```

In `OCCTKernel.swift`, replace the stubs:
```swift
    public func tessellate(_ solid: Solid, tolerance: Double) throws -> DisplayMesh {
        try Task.checkCancellation()
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The display tolerance must be greater than 0 mm.")
        }
        do {
            return try shape(of: solid).mesh(tolerance: tolerance)
        } catch let error as OCCTError {
            throw KernelError.occt("tessellate", error)
        }
    }

    public func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws {
        try Task.checkCancellation()
        guard !solids.isEmpty else { throw KernelError.invalidInput("There is nothing to export.") }
        let shapes = try solids.map { try shape(of: $0) }
        do {
            let combined = try shapes.count == 1 ? shapes[0] : OCCTShape.compound(shapes)
            switch format {
            case .step: try combined.writeSTEP(to: url)
            case .stl: try combined.writeSTL(to: url, deflection: 0.05)
            }
        } catch let error as OCCTError {
            throw KernelError.exportFailed(KernelError.plainReason(error.message))
        }
    }
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `swift test --filter MeshExportConformanceTests`, then `swift test`.
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/COCCT Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "feat(occt): tessellate solids and export STEP/STL from the kernel"
```

### Task 8: Naming-stability tests (the bracket at kernel level)

**Files:**
- Test: `Tests/CreatorOCCTTests/NamingStabilityTests.swift`
- Modify (only if a test exposes a real defect): any `Sources/CreatorOCCT` or `Sources/COCCT` file. Report the fix.

**Interfaces:**
- Consumes: every `OCCTKernel` operation and the fixture helpers.
- Produces: no new API. This task pins spec §8's topological-naming stability: the edge sets of the bracket's fillet and chamfer keep their meaning across Width 60→90, Hole count 4→6, and a rectangle profile swapped for a hexagon.

- [ ] **Step 1: Write the tests**

`Tests/CreatorOCCTTests/NamingStabilityTests.swift`:
```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Builds the acceptance bracket's plate (spec §7.2) directly through the kernel, the way the
/// M3 nodes will: plate → holes (one broadcast item each) → subtract → fillet the convex
/// vertical outer edges → chamfer the top-cap edges. Node identities are fixed across rebuilds,
/// exactly as in a document whose parameters change.
struct NamingStabilityTests {
    struct Nodes {
        let plate = NodeID()
        let holes = NodeID()
        let cut = NodeID()
        let fillet = NodeID()
        let chamfer = NodeID()
    }

    struct Built {
        let cut: Solid
        let filletEdges: [EdgeInfo]
        let filleted: Solid
        let chamferEdges: [EdgeInfo]
        let chamfered: Solid
    }

    func isVerticalConvexLine(_ edge: EdgeInfo) -> Bool {
        edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
    }

    func build(_ kernel: any Kernel, nodes: Nodes, outline: Profile2D, holeCenters: [Vector2]) async throws -> Built {
        let plateTag = NodeTag(node: nodes.plate, item: 0)
        let plate = try await kernel.extrude(outline, distance: 6, mode: .oneSided, tag: plateTag)
        var tools: [Solid] = []
        for (item, center) in holeCenters.enumerated() {
            tools.append(try await kernel.extrude(.circle(radius: 2.5, center: center, plane: Plane.xy.offset(by: -1)),
                                                  distance: 8, mode: .oneSided, tag: NodeTag(node: nodes.holes, item: item)))
        }
        let cut = try await kernel.boolean(.subtract, plate, tools, tag: NodeTag(node: nodes.cut, item: 0))
        let filletEdges = cut.topology.edges.filter(isVerticalConvexLine)
        let filleted = try await kernel.fillet(cut, edges: filletEdges.map(\.id), radius: 3, tag: NodeTag(node: nodes.fillet, item: 0))
        let top: (FaceInfo) -> Bool = { hasTag($0, .endCap, of: plateTag) }
        let outer: (FaceInfo) -> Bool = { face in
            face.tags.contains { tag in
                (tag.node == nodes.plate && { if case .side = tag.role { true } else { false } }())
                    || (tag.node == nodes.fillet && { if case .blend = tag.role { true } else { false } }())
            }
        }
        let chamferEdges = edges(filleted, between: top, and: outer)
        let chamfered = try await kernel.chamfer(filleted, edges: chamferEdges.map(\.id), distance: 0.5,
                                                 tag: NodeTag(node: nodes.chamfer, item: 0))
        return Built(cut: cut, filletEdges: filletEdges, filleted: filleted, chamferEdges: chamferEdges, chamfered: chamfered)
    }

    func grid(columns: Int, rows: Int, spacingX: Double, spacingY: Double) -> [Vector2] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                Vector2((Double(column) - Double(columns - 1) / 2) * spacingX, (Double(row) - Double(rows - 1) / 2) * spacingY)
            }
        }
    }

    func keys(_ edges: [EdgeInfo], in solid: Solid) -> Set<EdgeKey> {
        Set(edges.compactMap { solid.topology.key(of: $0) })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func widthChangeKeepsFilletAndChamferEdgeMeanings(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let nodes = Nodes()
        let holes = grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20)
        let narrow = try await build(kernel, nodes: nodes, outline: .rectangle(width: 60, height: 40, plane: .xy), holeCenters: holes)
        let wide = try await build(kernel, nodes: nodes, outline: .rectangle(width: 90, height: 40, plane: .xy), holeCenters: holes)
        #expect(narrow.filletEdges.count == 4)
        #expect(wide.filletEdges.count == 4)
        #expect(keys(narrow.filletEdges, in: narrow.cut) == keys(wide.filletEdges, in: wide.cut))
        #expect(narrow.chamferEdges.count == 8)
        #expect(wide.chamferEdges.count == 8)
        #expect(keys(narrow.chamferEdges, in: narrow.filleted) == keys(wide.chamferEdges, in: wide.filleted))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func holeCountChangeLeavesThePlateEdgesAlone(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let nodes = Nodes()
        let outline = Profile2D.rectangle(width: 90, height: 40, plane: .xy)
        let four = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        let six = try await build(kernel, nodes: nodes, outline: outline, holeCenters: grid(columns: 3, rows: 2, spacingX: 30, spacingY: 20))
        #expect(keys(four.filletEdges, in: four.cut) == keys(six.filletEdges, in: six.cut))
        #expect(keys(four.chamferEdges, in: four.filleted) == keys(six.chamferEdges, in: six.filleted))
        for item in 0..<6 {
            #expect(faces(six.cut, role: .side(segment: 0), of: NodeTag(node: nodes.holes, item: item)).count == 1)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func hexagonOutlineStillFilletsEveryOuterCorner(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let corners = (0..<6).map { k in Vector2(40 * cos(Double(k) * .pi / 3), 40 * sin(Double(k) * .pi / 3)) }
        let hexagon = Profile2D(plane: .xy, segments: corners.indices.map { .line(corners[$0], corners[($0 + 1) % 6]) })
        let built = try await build(kernel, nodes: Nodes(), outline: hexagon, holeCenters: grid(columns: 2, rows: 2, spacingX: 30, spacingY: 20))
        #expect(built.filletEdges.count == 6)
        #expect(built.chamferEdges.count == 12)
        let plateSides = built.filletEdges.compactMap { built.cut.topology.key(of: $0) }
        #expect(plateSides.count == 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func noFaceIsUntaggedOrUnnamedInTheBracket(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let built = try await build(kernel, nodes: Nodes(), outline: .rectangle(width: 60, height: 40, plane: .xy),
                                    holeCenters: grid(columns: 2, rows: 2, spacingX: 40, spacingY: 20))
        for solid in [built.cut, built.filleted, built.chamfered] {
            #expect(solid.topology.faces.allSatisfy { !$0.tags.isEmpty })
            #expect(solid.topology.faces.allSatisfy { face in
                !face.tags.contains { if case .unnamed = $0.role { true } else { false } }
            })
        }
        #expect(try await kernel.properties(of: built.chamfered).volume < (try await kernel.properties(of: built.cut).volume))
    }
}
```

- [ ] **Step 2: Run them**

Run: `swift test --filter NamingStabilityTests`
Expected: all PASS. If one fails, it has exposed a tagging or history defect: a key changing with geometry, or an `.unnamed` face. **Fix the shim or tagger, not the test.** Describe the cause and the fix in the report and commit message. The only acceptable test change is correcting an expected count after you've shown, with face and edge listings in the report, that the geometry really has that many edges.

- [ ] **Step 3: Commit**

```bash
git add Tests/CreatorOCCTTests Sources
git commit -m "test(occt): pin topological naming stability on the acceptance bracket"
```

### Task 9: Docs and carry-over

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`

**Interfaces:**
- Consumes: the finished M2.
- Produces: accurate agent guidance, and a carry-over note for M3 onward.

- [ ] **Step 1: Update CLAUDE.md and AGENTS.md (both)**

In "Project state":
- Change "M0 (OCCT probe) and M1 (graph engine) are done." to "M0 (OCCT probe), M1 (graph engine) and M2 (OCCT kernel) are done."
- Replace the `COCCT` + `CreatorOCCT` bullet with:
  ```markdown
  - `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
    OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
    `*_free`; no C++ exception crosses into Swift.
  ```
- Add to the rules: "Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`."

Under "Commands", add the line `swift test --filter CreatorOCCTTests  # kernel conformance + naming stability (needs OCCT)`.

- [ ] **Step 2: Update the carry-over note**

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`:
- Under "Before the first M2 OCCT operation", prefix each item handled in M2 with `✅ (M2) `: the `Interface_Static`/meshing serialization, `OCCTError` mapping, the query sentinel, stdout silencing, cancellation on entry, and the fallback tag plus Codable tags. Leave "add an unwritable-path STL test" and "O(n²) edge map" unmarked unless M2 actually did them. (The new export tests do cover an unwritable STL path; if so, mark it.)
- In "Before M3 selection-rule and profile nodes", replace the FakeKernel circle-rim bullet's first clause with: "FakeKernel and OCCTKernel both report a circle's axis as `direction` (by design); 'Edges by Direction' must require `kind == .line`." Keep the remaining FakeKernel items.
- Append a new section:
  ```markdown
  ## From M2
  - `OCCTKernel` runs on the default actor executor; long OCCT calls occupy a cooperative-pool thread. Measure in M7.
  - Fillet failures report `maxRadius: nil` (OCCT gives no limit); a search for the max radius is a later nicety.
  - Fuse/cut call `SimplifyResult()`; if that ever drops history for a face it shows up as `.unnamed` (pinned by
    `noFaceIsUntaggedOrUnnamedInTheBracket`).
  ```

- [ ] **Step 3: Verify and commit**

Run: `swift test`. Expected: every target PASSES with no OCCT stdout output.
```bash
git add CLAUDE.md AGENTS.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
git commit -m "docs: record M2 kernel boundaries and update the carry-over"
```

---

## What comes next

- **M3, the 26 nodes:** value, profile, solid, selection and feature nodes on `any Kernel`. "Edges by Tag" stores `EdgeKey`s, which are now Codable; adding a `ConstantValue` kind requires a `formatVersion` bump. The M3 plan is written against the code this plan produces.
