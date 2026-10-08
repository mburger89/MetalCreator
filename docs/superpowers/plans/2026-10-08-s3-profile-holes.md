# MetalCreator S3: Profile Holes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Profile2D` gains holes as `(plane, outer, holes)`. The OCCT shim builds faces with inner wires. Extrude and revolve cut the holes, loft refuses them, and hole walls are named `TopoRole.side(loop:segment:)`. The `.mcgraph` format goes to version 3. Every existing caller and test keeps working unchanged.

**Architecture:**
- **Geometry.** `Profile2D` stores `outer: [Segment2D]` and `holes: [[Segment2D]]`. `init(plane:segments:)` and `segments` (get/set the outer loop) stay, so M3's profile nodes and every test compile unchanged. `loops` is `[outer] + holes`. Loop 0 is the outer loop and loop *n* is `holes[n - 1]`, which is the numbering the shim and the tags use. `isClosed` checks every loop.
- **Shim.** `occt_profile` becomes `(plane, loops, loop_count)`, where each `occt_loop` is `(segments, segment_count)` and `loops[0]` is the outer boundary. `build_profile` builds one wire per loop, makes the face from the outer wire exactly as before, then `Add`s each hole wire. A hole wire is reversed when its 2D signed area has the same sign as the outer loop's. A `BRepCheck_Analyzer` pass rejects holes that are outside the outline or overlap another loop. Extrude and revolve record hole walls as `OCCT_FROM_SEGMENT` with **`operand` = loop index**. That field was always 0 for segment records, so no struct changes.
- **Naming.** `TopoRole.side(loop: Int = 0, segment: Int)` uses a default associated value, so `.side(segment: k)` still builds an outer wall at every existing call site. Loop 0 keeps `sortKey` `side(k)` and encodes without a `loop` key, byte for byte as before. A missing `loop` decodes as 0. `GraphFile.currentFormatVersion` goes 2 → 3, because a version-2 reader would silently drop a hole wall's `loop` and misname the edge.
- **FakeKernel** gives holes the same tag and edge rules: outer loop numbered first and unchanged, then each hole. The geometry stays fake.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, OpenCascade 7.9 (Homebrew) behind `COCCT`/`CreatorOCCT`.

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§6 Kernel and graph changes, §9 row S3, §10 Kernel bullet), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§5.3 naming, §4.5 files).

**Execution order: run this plan after M4 merges into master.** M4 edits `Sources/COCCT/cocct_mesh.cpp`, `CLAUDE.md` and `docs/metalui-gaps.md`. S3 edits `cocct.h` and `cocct_build.cpp`, and only one line of `CLAUDE.md` overlaps (Task 3). Rebase `plans/s3` (or the S3 implementation branch) onto master first. If M4 changed `CLAUDE.md`, apply Task 3's edits to the merged text. **S3 does not touch `CreatorSketch`.** S4 (later) switches the sketch regions to `Profile2D` holes. No node can produce a profile with holes until S4. In S3, holes reach the kernel only from tests.

**Verification status:** Every code block in this plan was compiled and its tests run on a copy of master (`d236e73`, M0–M3) with OCCT 7.9. Tasks 1–3 together took the suite from **339 tests to 384**, with no failures and no compiler warnings on a clean build. On a master that includes M4, expect master's own count + 45. The shim's orientation rule comes from the probe in Task 1 Step 1, whose output is quoted there.

**Task order (by risk):**
1. Task 1, the shim with holes: probe, `Profile2D`, `build_profile`, marshalling, kernel checks. If OCCT's inner-wire orientation or edge history behaves differently than this plan assumes, every later task is moot.
2. Task 2, the naming and file-format change. A wrong pattern match or decode default here silently misnames saved picks.
3. Task 3, FakeKernel parity, the value-size estimate and docs.

**Decisions made in this plan:**
- **Hole orientation is decided in 2D, in the shim.** The rule is "a hole winds against the outer loop", using exact signed areas (lines and arcs via ½∮x dy − y dx). The spec's "clockwise relative to the plane normal" holds only when the outer loop is counter-clockwise. Outer loops may wind either way (M2 test `clockwiseProfileStillGivesAPositiveSolid`), and `Segment2D.arc` is always counter-clockwise, so a circular hole can't be written clockwise at all. Callers never need to orient holes. The probe showed that `ShapeFix_Face` isn't needed. Reversing a wire with `TopoDS_Wire::Reversed()` keeps its edges, so `Generated()` and `BRepSweep_Revol::Shape` still find the hole walls.
- **The loop index travels in `occt_history_record.operand`** for `OCCT_FROM_SEGMENT`: 0 is the outer loop, *n* is hole *n*. `cocct.h` documents it. Boolean, transform and blend records keep their meaning (operand = input solid). `OCCTHistoryRecord` already carries `operand`, so only `OCCTTagger` changes.
- **`occt_profile` is replaced, not extended.** `segments`/`segment_count` become `loops`/`loop_count`, as spec §6 says. `OCCTProfile.withAll` is the only place that builds `occt_profile`, so there is a single Swift caller.
- **Outer-loop identity is untouched.** A profile without holes goes through exactly the old code path: `MakeFace(outerWire, true)` with no `Add` and no analyzer. So OCCT face and edge map order, and therefore every M2/M3 `EdgeID` and naming test, stay identical.
- **`TopoRole.side` uses a default associated value (`loop: Int = 0`) rather than a static func.** Swift supports this (probe below), so `.side(segment: k)` keeps compiling as an expression. **Pattern matches must name both values.** `case .side(let s)` still compiles, but it binds the `(loop:, segment:)` tuple and gives only a deprecation warning. Task 2 fixes the two binding sites (`TopoRole.sortKey` and `NamingStabilityTests.plateSideSegment`) and adds a grep gate. Bare `case .side` matches (`EdgePick`, `NamingStabilityTests`, `BracketAcceptanceTests`) are unaffected.
- **`sortKey`:** loop 0 → `side(k)` (unchanged), loop *n* → `side(n:k)`. The colon keeps `side(1:3)` distinct from `side(13)`.
- **Codable:** a tag writes `loop` only when it isn't 0. Outer-wall tags, and so every existing `EdgePick`, encode byte-identically to version 2. A missing `loop` decodes as 0, and a negative `loop` is a `DecodingError`. The version still goes to 3 because files that do contain hole walls aren't safe for a version-2 reader.
- **Loft refuses holes** with `KernelError.invalidInput("A loft can't use profiles with holes yet.")`. Both kernels check before any other loft rule, and the shim also refuses (`user_error`) as a backstop.
- **Invalid holes are a plain error from the shim.** A hole outside the outline, crossing it, or overlapping another hole gives "Extrude failed: a hole in the profile is outside the outline or overlaps another loop." This is caught by `BRepCheck_Analyzer` on the face. A zero-area hole gives "a hole in the profile has no area."
- **The symmetric extrude stops rebuilding the profile from `segments`.** It mutates `plane` on a copy. The old code would have silently dropped the holes. This is the only `Profile2D(…, segments: profile.segments)` rebuild in `Sources` (checked by grep).
- **FakeKernel** numbers the outer loop's faces and edges exactly as before, then appends each hole loop's walls (tagged `.side(loop:segment:)`), cap edges and between-side edges. Hole corners are `.concave`. Geometry and bounds still come from the outer bounds.
- **`Profile2D.bounds` covers every loop,** which is conservative if a malformed hole sticks out. `translated(by:)` moves the holes too. `segmentCount` counts every loop and feeds `Scalar.estimatedBytes`.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency. No `@unchecked Sendable`, and no new `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- One type per Swift file, named after the type. Extensions go in `Type+Purpose.swift`.
- **No force unwraps, no force `try`, no GCD, no third-party packages.** Use `FormatStyle`, never `Formatter` subclasses or `String(format:)`.
- **All OCCT work runs under `OCCTKernel.serialized`.** Tests reach the shim only through `OCCTKernel`. Throwaway OCCT/Swift probes are compiled under the session scratchpad (`/private/tmp/claude-501/…/scratchpad`), never in a checkout.
- **Shim errors:** `cocct::user_error` messages are user-facing, lower-case and unprefixed (`KernelError.occt` adds the operation and the full stop). Any other OCCT exception gets the "occt: " prefix and is mapped to a generic sentence.
- Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis.
- **Any change older readers can't decode bumps `GraphFile.currentFormatVersion`.** This plan bumps it once, 2 → 3, in Task 2.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected noise: linker warnings that OCCT dylibs were "built for newer macOS version". Nothing else may warn.

## Review Focus

Each of these failure modes is pinned by a test in the named task. They are ordered by how likely they are to bite a user of S4's sketch regions.

1. **A hole that winds the same way as the outline.** Every circular hole does, because arcs are always counter-clockwise, and so does a clockwise outline with a counter-clockwise hole. The hole must still be cut, not added as area or turned into an invalid solid. *Task 1: `aHoleMayWindEitherWay`, `aClockwiseOutlineStillCutsItsHole`, `extrudingASquareWithACircularHoleIsAnalytic`.*
2. **Code that rebuilds a profile from `segments` silently drops its holes.** The symmetric extrude did, and so would a `translated` that maps only `segments`. *Task 1: `aSymmetricExtrudeKeepsTheHole`, `translatingMovesTheHolesToo`, `settingSegmentsKeepsTheHoles`.*
3. **A hole outside the outline, crossing it, or overlapping another hole.** S2's region finder shouldn't produce these, but a bad sketch or a future node can. The user should get a plain sentence, never a corrupt solid or OCCT text. *Task 1: `aHoleOutsideTheOutlineIsAPlainError`, `aHoleCrossingTheOutlineIsAPlainError`, `overlappingHolesAreAPlainError`.*
4. **Saved picks on outer walls from a version-2 file must still select the same edges, and new outer-wall picks must be written exactly as before.** Otherwise every M3 bracket file would drift. *Task 2: `versionTwoEdgePicksDecodeAsOuterWalls`, `outerWallPicksAreWrittenAsBefore`, `outerWallsEncodeWithoutALoop`, `outerWallSortKeysAreUnchanged`, `anOldEdgePickDecodesWithOuterWalls`.*
5. **Hole walls are misnamed when the shim reverses a hole wire,** for example as segment `3 − k`, or with loop indices swapped between two holes. Then a pick on a hole wall moves to a different wall. *Task 2: `holeWallsFollowSegmentOrderWhicheverWayTheHoleWinds`, `eachHoleGetsItsOwnLoopIndex`, `aHoleRimKeepsItsKeyWhenTheOutlineChanges`.*

Also guarded: the single-binding pattern trap (`case .side(let s)` binds a tuple and only warns) has a grep gate in Task 2 Step 6, and the `sortKey` tests in Task 2 would catch it.

---

## File Structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/CreatorGeometry/Profile2D.swift` | Modify | `outer` + `holes`, `segments` compatibility accessor, `loops`, `segmentCount`, `isClosed` over every loop, bounds over every loop |
| `Sources/CreatorGeometry/Profile2D+Shapes.swift` | Modify | `translated(by:)` moves holes |
| `Sources/COCCT/include/cocct.h` | Modify | `occt_loop`, `occt_profile.loops`, the history `operand` = loop contract, loft refuses holes |
| `Sources/COCCT/cocct_build.cpp` | Modify | `build_edge` / `build_loop` / `signed_area`, inner wires, analyzer check, per-loop history, loft refusal |
| `Sources/CreatorOCCT/OCCTProfile.swift` | Modify | Marshal every loop of every profile |
| `Sources/CreatorOCCT/OCCTKernel.swift` | Modify | Symmetric extrude keeps holes; loft refuses holes |
| `Sources/CreatorOCCT/OCCTTagger.swift` | Modify | Task 1: skip hole records. Task 2: `.side(loop: operand, segment: index)` |
| `Sources/CreatorKernel/TopoRole.swift` | Modify | `side(loop: Int = 0, segment: Int)`, loop-aware `sortKey` |
| `Sources/CreatorKernel/TopoRole+Codable.swift` | Modify | Optional `loop` key, default 0, reject negative |
| `Sources/CreatorGraph/GraphFile.swift` | Modify | `currentFormatVersion = 3` |
| `Sources/CreatorKernel/FakeKernel.swift` | Modify | Hole walls in `prism`, loft refuses holes |
| `Sources/CreatorGraph/Scalar.swift` | Modify | `estimatedBytes` counts hole segments |
| `Tests/CreatorGeometryTests/ProfileHoleTests.swift` | Create | Profile2D hole model |
| `Tests/CreatorOCCTTests/HoleConformanceTests.swift` | Create (Task 1), extend (Tasks 2, 3) | Volumes, errors, revolve, loft refusal; then tags and naming; then FakeKernel parity |
| `Tests/CreatorKernelTests/TopoRoleLoopTests.swift` | Create | sortKey, Codable, old `EdgePick` JSON |
| `Tests/CreatorGraphTests/EdgePickFileTests.swift` | Modify | Version 3, version-2 picks, hole picks |
| `Tests/CreatorOCCTTests/TaggerTests.swift` | Modify | Segment operand → loop |
| `Tests/CreatorOCCTTests/NamingStabilityTests.swift` | Modify | Two-value `.side` pattern |
| `Tests/CreatorKernelTests/FakeKernelHoleTests.swift` | Create | Fake hole topology and tags |
| `Tests/CreatorGraphTests/ProfileEstimateTests.swift` | Create | Estimate counts holes |
| `CLAUDE.md`, sketcher spec §6 | Modify | Format version 3, hole rules, the orientation erratum |

---

### Task 1: Profiles with holes through the shim (extrude, revolve, loft refusal)

**Files:**
- Probe (scratchpad only): `$SCRATCH/s3probe/holes.cpp`
- Modify: `Sources/CreatorGeometry/Profile2D.swift` (whole file), `Sources/CreatorGeometry/Profile2D+Shapes.swift:4-7`
- Modify: `Sources/COCCT/include/cocct.h:39-41, 116-140`, `Sources/COCCT/cocct_build.cpp:1-105, 144-236`
- Modify: `Sources/CreatorOCCT/OCCTProfile.swift:29-46`, `Sources/CreatorOCCT/OCCTKernel.swift:36-38, 55-57`, `Sources/CreatorOCCT/OCCTTagger.swift:13-14`
- Test: `Tests/CreatorGeometryTests/ProfileHoleTests.swift`, `Tests/CreatorOCCTTests/HoleConformanceTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Profile2D.init(plane: Plane, outer: [Segment2D], holes: [[Segment2D]] = [])`
  - `Profile2D.outer: [Segment2D]`, `Profile2D.holes: [[Segment2D]]` (both `var`)
  - `Profile2D.segments: [Segment2D]` (get/set `outer`), `Profile2D.loops: [[Segment2D]]`, `Profile2D.segmentCount: Int`
  - C: `occt_loop { const occt_segment *segments; int segment_count; }`, `occt_profile { occt_plane plane; const occt_loop *loops; int loop_count; }`
  - History: `OCCT_FROM_SEGMENT` records carry `operand` = loop (0 outer, *n* = hole *n*) and `index` = segment.
  - `KernelError.invalidInput("A loft can't use profiles with holes yet.")` from `OCCTKernel.loft`.
  - Task 1 leaves hole walls `.unnamed` (`OCCTTagger` skips `operand != 0` segment records). Task 2 names them.

- [ ] **Step 1: Run the OCCT inner-wire probe (gate: stop and report if the output differs)**

Set `SCRATCH` to the session scratchpad directory first. Never put the probe in the checkout.

```bash
export SCRATCH=/private/tmp/claude-501/<project>/<session>/scratchpad   # your session's scratchpad path
mkdir -p "$SCRATCH/s3probe" && cd "$SCRATCH/s3probe"
```

Write `holes.cpp`:

```cpp
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepSweep_Revol.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <GProp_GProps.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Solid.hxx>
#include <gp_Circ.hxx>
#include <gp_Ax2.hxx>
#include <cstdio>
#include <vector>
#include <cmath>

struct Loop { TopoDS_Wire wire; std::vector<TopoDS_Edge> edges; };

Loop square(const gp_Ax2& f, double x0, double y0, double x1, double y1, bool cw) {
  auto P=[&](double x,double y){return gp_Pnt(f.Location().XYZ()+f.XDirection().XYZ()*x+f.YDirection().XYZ()*y);};
  std::vector<gp_Pnt> c={P(x0,y0),P(x1,y0),P(x1,y1),P(x0,y1)};
  if(cw) std::swap(c[1],c[3]);
  BRepBuilderAPI_MakeWire w; Loop l;
  for(int k=0;k<4;k++){ w.Add(BRepBuilderAPI_MakeEdge(c[k],c[(k+1)%4]).Edge()); l.edges.push_back(w.Edge()); }
  l.wire=w.Wire(); return l;
}
Loop circle(const gp_Ax2& f, double cx, double cy, double r) {
  gp_Ax2 a(gp_Pnt(f.Location().XYZ()+f.XDirection().XYZ()*cx+f.YDirection().XYZ()*cy), f.Direction(), f.XDirection());
  BRepBuilderAPI_MakeWire w; Loop l;
  w.Add(BRepBuilderAPI_MakeEdge(gp_Circ(a,r),0,2*M_PI).Edge()); l.edges.push_back(w.Edge()); l.wire=w.Wire(); return l;
}
double vol(const TopoDS_Shape& s){GProp_GProps p;BRepGProp::VolumeProperties(s,p);return p.Mass();}
double area(const TopoDS_Shape& s){GProp_GProps p;BRepGProp::SurfaceProperties(s,p);return p.Mass();}

TopoDS_Face face(const Loop& outer, std::vector<Loop>& holes, std::vector<bool> reverse){
  BRepBuilderAPI_MakeFace mf(outer.wire, Standard_True);
  for(size_t i=0;i<holes.size();i++) mf.Add(reverse[i]? TopoDS::Wire(holes[i].wire.Reversed()) : holes[i].wire);
  return mf.Face();
}
int count_gen(BRepPrimAPI_MakePrism& p, const TopoDS_Edge& e, const TopoDS_Shape& out){
  TopTools_IndexedMapOfShape m; TopExp::MapShapes(out,TopAbs_FACE,m); int n=0;
  for(TopTools_ListOfShape::Iterator it(p.Generated(e)); it.More(); it.Next()) if(m.FindIndex(it.Value())>0) n++;
  return n;
}
int main(){
  gp_Ax2 xy(gp_Pnt(0,0,0),gp_Dir(0,0,1),gp_Dir(1,0,0));
  for(int oc=0;oc<2;oc++) for(int hk=0;hk<3;hk++) for(int rev=0;rev<2;rev++){
    Loop outer=square(xy,0,0,10,10,oc==1);
    std::vector<Loop> holes={ hk==0? circle(xy,5,5,2) : square(xy,3,3,7,7,hk==2) };
    TopoDS_Face f=face(outer,holes,{rev==1});
    BRepCheck_Analyzer fa(f);
    BRepPrimAPI_MakePrism pr(f,gp_Vec(0,0,3)); pr.Build();
    TopoDS_Solid s=TopoDS::Solid(pr.Shape()); BRepLib::OrientClosedSolid(s);
    BRepCheck_Analyzer sa(s);
    int gen=0; for(auto&e:holes[0].edges) gen+=count_gen(pr,e,s);
    int genOuter=0; for(auto&e:outer.edges) genOuter+=count_gen(pr,e,s);
    double holeArea = hk==0? M_PI*4 : 16;
    printf("outerCW=%d hole=%s reversed=%d faceArea=%.4f (want %.4f) faceValid=%d vol=%.4f (want %.4f) solidValid=%d holeGen=%d outerGen=%d faces=%d\n",
      oc, hk==0?"circle":(hk==1?"ccwSq":"cwSq"), rev, area(f), 100-holeArea, fa.IsValid(), vol(s), 3*(100-holeArea), sa.IsValid(), gen, genOuter,
      [&]{TopTools_IndexedMapOfShape m; TopExp::MapShapes(s,TopAbs_FACE,m); return m.Extent();}());
  }
  { Loop outer=square(xy,0,0,10,10,false); std::vector<Loop> h={circle(xy,20,5,2)};
    TopoDS_Face f=face(outer,h,{true}); BRepCheck_Analyzer fa(f); printf("outside hole: faceValid=%d area=%.3f\n", fa.IsValid(), area(f)); }
  { Loop outer=square(xy,0,0,10,10,false); std::vector<Loop> h={circle(xy,9,5,2)};
    TopoDS_Face f=face(outer,h,{true}); BRepCheck_Analyzer fa(f); printf("crossing hole: faceValid=%d area=%.3f\n", fa.IsValid(), area(f)); }
  gp_Ax2 xz(gp_Pnt(0,0,0),gp_Dir(0,-1,0),gp_Dir(1,0,0));
  for(int full=0; full<2; full++){
    Loop outer=square(xz,5,0,15,10,false); std::vector<Loop> h={circle(xz,10,5,2)};
    TopoDS_Face f=face(outer,h,{true});
    double ang = full? 2*M_PI : M_PI/2;
    BRepPrimAPI_MakeRevol rv(f,gp_Ax1(gp_Pnt(0,0,0),gp_Dir(0,0,1)),ang); rv.Build();
    TopoDS_Solid so=TopoDS::Solid(rv.Shape()); BRepLib::OrientClosedSolid(so);
    TopTools_IndexedMapOfShape m; TopExp::MapShapes(so,TopAbs_FACE,m);
    int gen=0, viaShape=0;
    for(TopTools_ListOfShape::Iterator it(rv.Generated(h[0].edges[0])); it.More(); it.Next()) if(m.FindIndex(it.Value())>0) gen++;
    TopoDS_Shape sh = const_cast<BRepSweep_Revol&>(rv.Revol()).Shape(h[0].edges[0]);
    for(TopExp_Explorer e(sh,TopAbs_FACE); e.More(); e.Next()) if(m.FindIndex(e.Current())>0) viaShape++;
    double want = ang*10*(100-4*M_PI);
    BRepCheck_Analyzer sa(so);
    printf("revolve full=%d vol=%.4f want=%.4f valid=%d faces=%d holeGen=%d holeViaShape=%d\n", full, vol(so), want, sa.IsValid(), m.Extent(), gen, viaShape);
  }
}
```

Run:

```bash
O=/opt/homebrew/opt/opencascade
clang++ -std=c++17 -isystem $O/include/opencascade holes.cpp -L$O/lib -Wl,-rpath,$O/lib \
  -lTKernel -lTKMath -lTKG2d -lTKG3d -lTKGeomBase -lTKGeomAlgo -lTKBRep -lTKTopAlgo -lTKPrim -o holes 2>&1 | grep -v 'built for newer'
./holes
```

Expected (recorded on OCCT 7.9 when this plan was written; a later re-run matched every row exactly). Rows elided with `...` print the other fields too; only `faceValid`, `vol`, `holeGen` and `faces` need to match, and on a `faceValid=0` row only `faceValid` matters. Read each row as "a hole wire must wind against the outer wire". The valid rows (`faceValid=1`) are exactly those where the hole's 2D winding differs from the outer loop's after the optional reversal. `holeGen` is non-zero through a reversed wire. The analyzer flags the outside and crossing holes, and a revolved circular hole's wall is found by `Generated()` for both a partial and a full revolve:

```
outerCW=0 hole=circle reversed=0 ... faceValid=0 vol=337.6991 (want 262.3009) solidValid=0 holeGen=1 outerGen=4 faces=7
outerCW=0 hole=circle reversed=1 ... faceValid=1 vol=262.3009 (want 262.3009) solidValid=1 holeGen=1 outerGen=4 faces=7
outerCW=0 hole=ccwSq reversed=0 ... faceValid=0 ...
outerCW=0 hole=ccwSq reversed=1 ... faceValid=1 vol=252.0000 (want 252.0000) solidValid=1 holeGen=4 outerGen=4 faces=10
outerCW=0 hole=cwSq reversed=0 ... faceValid=1 vol=252.0000 (want 252.0000) solidValid=1 holeGen=4 outerGen=4 faces=10
outerCW=0 hole=cwSq reversed=1 ... faceValid=0 ...
outerCW=1 hole=circle reversed=0 ... faceValid=1 vol=262.3009 (want 262.3009) ...
outerCW=1 hole=circle reversed=1 ... faceValid=0 ...
outerCW=1 hole=ccwSq reversed=0 ... faceValid=1 ...
outerCW=1 hole=ccwSq reversed=1 ... faceValid=0 ...
outerCW=1 hole=cwSq reversed=0 ... faceValid=0 ...
outerCW=1 hole=cwSq reversed=1 ... faceValid=1 ...
outside hole: faceValid=0 area=87.434
crossing hole: faceValid=0 area=87.434
revolve full=0 vol=1373.4042 want=1373.4042 valid=1 faces=7 holeGen=1 holeViaShape=1
revolve full=1 vol=5493.6170 want=5493.6170 valid=1 faces=5 holeGen=1 holeViaShape=1
```

If any valid/invalid pattern differs, or `holeGen` is 0, stop and report it: the orientation rule or the history plumbing below would be wrong.

- [ ] **Step 2: Write the failing geometry tests**

Create `Tests/CreatorGeometryTests/ProfileHoleTests.swift`:

```swift
import Testing
@testable import CreatorGeometry

struct ProfileHoleTests {
    let square = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
    let hole: [Segment2D] = Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments

    @Test func theSegmentsInitialiserMakesAProfileWithoutHoles() {
        let plain = Profile2D(plane: .xy, segments: square)
        #expect(plain.outer == square)
        #expect(plain.holes.isEmpty)
        #expect(plain.segments == square)
        #expect(plain == Profile2D(plane: .xy, outer: square))
    }

    @Test func loopsListTheOuterLoopFirst() {
        let profile = Profile2D(plane: .xy, outer: square, holes: [hole])
        #expect(profile.loops == [square, hole])
        #expect(profile.segments == square)
        #expect(profile.segmentCount == 5)
        #expect(profile != Profile2D(plane: .xy, segments: square))
    }

    @Test func settingSegmentsKeepsTheHoles() {
        var profile = Profile2D(plane: .xy, outer: square, holes: [hole])
        profile.segments = Profile2D.rectangle(width: 20, height: 20, plane: .xy).segments
        #expect(profile.holes == [hole])
    }

    @Test func isClosedChecksEveryLoop() {
        #expect(Profile2D(plane: .xy, outer: square, holes: [hole]).isClosed)
        let openHole: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))]
        #expect(!Profile2D(plane: .xy, outer: square, holes: [openHole]).isClosed)
        #expect(!Profile2D(plane: .xy, outer: square, holes: [[]]).isClosed)
        #expect(!Profile2D(plane: .xy, outer: [], holes: [hole]).isClosed)
    }

    @Test func translatingMovesTheHolesToo() {
        let moved = Profile2D(plane: .xy, outer: square, holes: [hole]).translated(by: Vector2(3, 4))
        guard case .arc(let center, _, _, _)? = moved.holes.first?.first else { Issue.record("expected an arc"); return }
        #expect(center == Vector2(4, 5))
        #expect(moved.outer[0].startPoint == Vector2(-2, -1))
    }

    @Test func boundsCoverEveryLoop() throws {
        // A hole that sticks out past the outline, so outer-only bounds would stop at x = 5.
        let stray = Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments
        let bounds = try #require(Profile2D(plane: .xy, outer: square, holes: [hole, stray]).bounds)
        #expect(bounds.min == Vector3(-5, -5, 0))
        #expect(bounds.max == Vector3(21, 5, 0))
        #expect(Profile2D(plane: .xy, outer: [], holes: [hole]).bounds != nil)
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `swift test --filter ProfileHoleTests`
Expected: compile errors such as "extra argument 'outer' in call" and "value of type 'Profile2D' has no member 'holes'".

- [ ] **Step 4: Implement `Profile2D` holes**

Replace `Sources/CreatorGeometry/Profile2D.swift` with:

```swift
/// A closed region on `plane`: one outer loop of segments and any number of hole loops inside it.
/// Holes may wind either way; the kernel orients them. Loop 0 is `outer`, loop `n` is `holes[n - 1]`,
/// which is the numbering `TopoRole.side(loop:segment:)` uses.
public struct Profile2D: Hashable, Sendable {
    public var plane: Plane
    public var outer: [Segment2D]
    public var holes: [[Segment2D]]

    public init(plane: Plane, outer: [Segment2D], holes: [[Segment2D]] = []) {
        self.plane = plane
        self.outer = outer
        self.holes = holes
    }

    /// A profile without holes.
    public init(plane: Plane, segments: [Segment2D]) {
        self.init(plane: plane, outer: segments)
    }

    /// The outer loop. For a profile without holes this is the whole profile; setting it keeps the holes.
    public var segments: [Segment2D] {
        get { outer }
        set { outer = newValue }
    }

    /// Every loop, outer first: `loops[0] == outer`, `loops[n] == holes[n - 1]`.
    public var loops: [[Segment2D]] { [outer] + holes }

    /// Segments in every loop.
    public var segmentCount: Int { loops.reduce(0) { $0 + $1.count } }

    /// True when every loop is non-empty, each segment ends where the next begins, and the last
    /// returns to the first. Says nothing about holes lying inside the outer loop; the kernel checks that.
    public var isClosed: Bool {
        loops.allSatisfy(Self.isClosedLoop)
    }

    /// World-space bounds of every loop, or `nil` for an empty profile.
    public var bounds: BoundingBox? {
        BoundingBox(points: loops.joined().flatMap(\.boundingPoints).map(plane.point))
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

    private static func isClosedLoop(_ loop: [Segment2D]) -> Bool {
        guard let first = loop.first, let last = loop.last else { return false }
        for (a, b) in zip(loop, loop.dropFirst()) where (a.endPoint - b.startPoint).length > 1e-9 {
            return false
        }
        return (last.endPoint - first.startPoint).length <= 1e-9
    }
}
```

In `Sources/CreatorGeometry/Profile2D+Shapes.swift`, replace `translated(by:)`:

```swift
    /// The same profile, holes included, moved by `offset` in plane coordinates.
    public func translated(by offset: Vector2) -> Profile2D {
        Profile2D(plane: plane, outer: outer.map { $0.translated(by: offset) },
                  holes: holes.map { hole in hole.map { $0.translated(by: offset) } })
    }
```

- [ ] **Step 5: Run the geometry tests to verify they pass**

Run: `swift test --filter CreatorGeometryTests`
Expected: PASS, with the 15 existing tests plus the 6 new ones.

- [ ] **Step 6: Write the failing kernel tests**

Create `Tests/CreatorOCCTTests/HoleConformanceTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct HoleConformanceTests {
    /// A 10 × 10 square on XY centred on the origin with a Ø4 circular hole at (1, 1).
    let plate = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                          holes: [Profile2D.circle(radius: 2, center: Vector2(1, 1), plane: .xy).segments])

    /// A 4 × 4 square hole centred on the origin, counter-clockwise or clockwise.
    func squareHole(clockwise: Bool) -> [Segment2D] {
        let ccw = Profile2D.rectangle(width: 4, height: 4, plane: .xy).segments
        guard clockwise else { return ccw }
        return ccw.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return .line(b, a)
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func extrudingASquareWithACircularHoleIsAnalytic(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(plate, distance: 3, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (100 - Double.pi * 4)))
        #expect(solid.topology.faces.count == 7)
        #expect(solid.topology.faces.filter { $0.kind == .cylinder }.count == 1)
    }

    @Test(arguments: KernelUnderTest.allCases, [false, true])
    func aHoleMayWindEitherWay(_ under: KernelUnderTest, clockwise: Bool) async throws {
        let kernel = under.make()
        let profile = Profile2D(plane: .xy, outer: Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments,
                                holes: [squareHole(clockwise: clockwise)])
        let solid = try await kernel.extrude(profile, distance: 2, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 2 * (100 - 16)))
        #expect(solid.topology.faces.count == 10)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aClockwiseOutlineStillCutsItsHole(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments.reversed().map { segment in
            guard case .line(let a, let b) = segment else { return segment }
            return Segment2D.line(b, a)
        }
        let profile = Profile2D(plane: .xy, outer: outline, holes: plate.holes)
        let solid = try await kernel.extrude(profile, distance: 3, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 3 * (100 - Double.pi * 4)))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func twoHolesAreBothCut(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let holes = [Vector2(-2.5, 0), Vector2(2.5, 0)].map { Profile2D.circle(radius: 1, center: $0, plane: .xy).segments }
        let profile = Profile2D(plane: .xy, outer: plate.outer, holes: holes)
        let solid = try await kernel.extrude(profile, distance: 1, mode: .oneSided, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 100 - 2 * Double.pi))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aSymmetricExtrudeKeepsTheHole(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await kernel.extrude(plate, distance: 4, mode: .symmetric, tag: newTag())
        #expect(isClose(try await kernel.properties(of: solid).volume, 4 * (100 - Double.pi * 4)))
        #expect(isClose(solid.bounds.min.z, -2, relative: 1e-4))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleOutsideTheOutlineIsAPlainError(_ under: KernelUnderTest) async {
        let stray = Profile2D(plane: .xy, outer: plate.outer,
                              holes: [Profile2D.circle(radius: 1, center: Vector2(20, 0), plane: .xy).segments])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(stray, distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleCrossingTheOutlineIsAPlainError(_ under: KernelUnderTest) async {
        let crossing = Profile2D(plane: .xy, outer: plate.outer,
                                 holes: [Profile2D.circle(radius: 2, center: Vector2(4, 0), plane: .xy).segments])
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(crossing, distance: 1, mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func overlappingHolesAreAPlainError(_ under: KernelUnderTest) async {
        let holes = [Vector2(-0.5, 0), Vector2(0.5, 0)].map { Profile2D.circle(radius: 1, center: $0, plane: .xy).segments }
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: holes), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude",
                                          reason: "a hole in the profile is outside the outline or overlaps another loop."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aZeroAreaHoleIsAPlainError(_ under: KernelUnderTest) async {
        // Closed (out and back), so it passes `isClosed` and reaches the shim's area check.
        let flat: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(0, 0))]
        let error = await #expect(throws: KernelError.self) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: [flat]), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
        #expect(error == .operationFailed(operation: "extrude", reason: "a hole in the profile has no area."))
    }

    @Test(arguments: KernelUnderTest.allCases)
    func anOpenHoleIsRejected(_ under: KernelUnderTest) async {
        let open: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1))]
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: [open]), distance: 1,
                                           mode: .oneSided, tag: newTag())
        }
    }

    /// The tube's cross-section on XZ (x 5…15, z 0…10) with a Ø4 hole at x 10, z 5, revolved about Z.
    var tubeSection: Profile2D {
        let plane = Plane(origin: .zero, normal: -.unitY, xAxis: .unitX)
        return Profile2D(plane: plane, outer: Profile2D.polyline([Vector2(5, 0), Vector2(15, 0), Vector2(15, 10), Vector2(5, 10)],
                                                                 closed: true, plane: plane).segments,
                         holes: [Profile2D.circle(radius: 2, center: Vector2(10, 5), plane: plane).segments])
    }

    @Test(arguments: KernelUnderTest.allCases, [360.0, 90.0])
    func revolvingAProfileWithAHoleMakesATubeWithACavity(_ under: KernelUnderTest, degrees: Double) async throws {
        let kernel = under.make()
        let solid = try await kernel.revolve(tubeSection, axis: .z, angle: .degrees(degrees), tag: newTag())
        // Pappus: area (100 − 4π) times the centroid's path (radius 10, both loops centred on x = 10).
        let expected = (100 - 4 * Double.pi) * 10 * degrees * .pi / 180
        #expect(isClose(try await kernel.properties(of: solid).volume, expected, relative: 1e-5))
        #expect(solid.topology.faces.contains { $0.kind == .torus })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aLoftRefusesProfilesWithHoles(_ under: KernelUnderTest) async {
        var top = plate
        top.plane = Plane.xy.offset(by: 5)
        await #expect(throws: KernelError.invalidInput("A loft can't use profiles with holes yet.")) {
            try await under.make().loft([plate, top], ruled: true, tag: newTag())
        }
    }
}
```

- [ ] **Step 7: Run them to verify they fail**

Run: `swift test --filter HoleConformanceTests`
Expected: FAIL. The current shim sees only the outer segments, so volumes are the full square (300, 200, 100, 400). Revolve volumes miss the cavity, the invalid-hole and zero-area-hole tests throw nothing, and the loft is built.

- [ ] **Step 8: Change the C API (`cocct.h`)**

In `Sources/COCCT/include/cocct.h`, replace the history comment above `occt_history_kind`:

```c
/// History: where an output face came from. `out_face` is the 1-based index in the output's
/// face map; `operand`/`index` refer to the operation's inputs (index is 1-based for faces and
/// edges, 0-based for profile segments). For OCCT_FROM_SEGMENT, `operand` is the profile loop
/// (0 = outer boundary, n = hole n, as in occt_profile.loops) and `index` the segment in that loop.
```

Replace the `occt_profile` typedef and the comments on `occt_extrude`, `occt_revolve` and `occt_loft` (from `typedef struct { occt_plane plane; const occt_segment *segments; …` through the `occt_loft` declaration):

```c
/// One closed loop of segments, in order.
typedef struct {
    const occt_segment *segments;
    int segment_count;
} occt_loop;

/// A planar region. loops[0] is the outer boundary; loops[1 ..< loop_count] are holes, which must
/// lie inside it without touching it or each other. Holes may wind either way: the shim reverses a
/// hole wire that winds the same way as the outer loop, which is what OCCT needs.
typedef struct {
    occt_plane plane;
    const occt_loop *loops;
    int loop_count;
} occt_profile;

/// Extrudes the profile along its plane normal by `distance`. History: start/end caps and
/// one OCCT_FROM_SEGMENT record per side face (operand = loop, index = segment), hole walls included.
occt_shape *occt_extrude(const occt_profile *profile, double distance, occt_history *history, occt_status *status);

/// Revolves the profile about the axis by `angle` (radians, 0 < angle <= 2π). Caps
/// (OCCT_FROM_START_CAP/END_CAP) exist only for a partial revolve; sides are OCCT_FROM_SEGMENT
/// (operand = loop, index = segment), hole walls included.
occt_shape *occt_revolve(const occt_profile *profile, const double axis_origin[3], const double axis_direction[3],
                         double angle, occt_history *history, occt_status *status);
/// Lofts through `count` profiles (ruled = straight sides). Sides are OCCT_FROM_SEGMENT (operand 0)
/// with the index of the first section's segment; caps are the first and last sections. Every
/// section must be a single loop: a profile with holes is refused.
occt_shape *occt_loft(const occt_profile *profiles, int count, int ruled, occt_history *history, occt_status *status);
```

- [ ] **Step 9: Build inner wires in the shim (`cocct_build.cpp`)**

Add two includes after `#include <BRepBuilderAPI_MakeWire.hxx>` and after `#include <TopoDS_Solid.hxx>` respectively:

```cpp
#include <BRepCheck_Analyzer.hxx>
```

```cpp
#include <TopoDS_Wire.hxx>
```

Replace everything in the anonymous namespace from `/// A profile turned into a planar face, with its edges in segment order.` up to (not including) `double volume_of(` with:

```cpp
/// A profile turned into a planar face, with each loop's edges in segment order (loop 0 = outer).
struct built_profile {
    TopoDS_Face face;
    std::vector<std::vector<TopoDS_Edge>> loops;
};

/// One loop turned into a wire, with its edges in segment order.
struct built_loop {
    TopoDS_Wire wire;
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

TopoDS_Edge build_edge(const gp_Ax2 &frame, const occt_segment &segment) {
    if (segment.kind == 0) {
        const gp_Pnt a = point_on(frame, segment.x0, segment.y0);
        const gp_Pnt b = point_on(frame, segment.x1, segment.y1);
        if (a.Distance(b) <= 1e-9) {
            throw user_error("a line in the profile has zero length");
        }
        BRepBuilderAPI_MakeEdge make(a, b);
        if (!make.IsDone()) {
            throw user_error("a line in the profile could not be built");
        }
        return make.Edge();
    }
    if (segment.kind != 1) {
        throw user_error("unknown profile segment kind");
    }
    if (!std::isfinite(segment.start) || !std::isfinite(segment.end)) {
        throw user_error("an arc in the profile has a non-finite angle");
    }
    if (!(segment.end - segment.start > 1e-12)) {
        throw user_error("an arc in the profile has no sweep");
    }
    if (!(segment.radius > 1e-9) || !std::isfinite(segment.radius)) {
        throw user_error("an arc in the profile has no radius");
    }
    if (!std::isfinite(segment.cx) || !std::isfinite(segment.cy)) {
        throw user_error("an arc in the profile has an invalid centre");
    }
    const gp_Ax2 axes(point_on(frame, segment.cx, segment.cy), frame.Direction(), frame.XDirection());
    BRepBuilderAPI_MakeEdge make(gp_Circ(axes, segment.radius), segment.start, segment.end);
    if (!make.IsDone()) {
        throw user_error("an arc in the profile could not be built");
    }
    return make.Edge();
}

built_loop build_loop(const gp_Ax2 &frame, const occt_loop &loop, bool hole) {
    if (!loop.segments || loop.segment_count <= 0) {
        throw user_error(hole ? "a hole in the profile has no segments" : "the profile has no segments");
    }
    BRepBuilderAPI_MakeWire wire;
    built_loop result;
    for (int k = 0; k < loop.segment_count; ++k) {
        wire.Add(build_edge(frame, loop.segments[k]));
        if (!wire.IsDone()) {
            throw user_error(hole ? "the segments of a hole in the profile do not connect" : "the profile segments do not connect");
        }
        result.edges.push_back(wire.Edge());
    }
    result.wire = wire.Wire();
    return result;
}

/// The loop's signed area in plane coordinates, positive when it winds counter-clockwise.
/// Exact for lines and arcs (Green's theorem, ½∮ x dy − y dx).
double signed_area(const occt_loop &loop) {
    double twice = 0;
    for (int k = 0; k < loop.segment_count; ++k) {
        const occt_segment &s = loop.segments[k];
        if (s.kind == 0) {
            twice += s.x0 * s.y1 - s.x1 * s.y0;
        } else {
            twice += s.radius * s.cx * (std::sin(s.end) - std::sin(s.start))
                - s.radius * s.cy * (std::cos(s.end) - std::cos(s.start))
                + s.radius * s.radius * (s.end - s.start);
        }
    }
    return twice / 2;
}

built_profile build_profile(const occt_profile &profile) {
    if (!profile.loops || profile.loop_count <= 0) {
        throw user_error("the profile has no segments");
    }
    const gp_Ax2 frame = frame_of(profile.plane);
    const built_loop outer = build_loop(frame, profile.loops[0], false);
    built_profile result;
    result.loops.push_back(outer.edges);
    BRepBuilderAPI_MakeFace face(outer.wire, Standard_True);
    if (!face.IsDone()) {
        throw user_error("the profile is not a closed, flat loop");
    }
    if (profile.loop_count == 1) {
        result.face = face.Face();
        return result;
    }
    const bool outer_counter_clockwise = signed_area(profile.loops[0]) > 0;
    for (int n = 1; n < profile.loop_count; ++n) {
        const built_loop hole = build_loop(frame, profile.loops[n], true);
        const double area = signed_area(profile.loops[n]);
        if (!(std::abs(area) > 1e-12)) {
            throw user_error("a hole in the profile has no area");
        }
        // OCCT needs each hole wire to wind against the outer one (S3 probe). Reversing the wire
        // keeps its edges, so Generated() still finds the hole walls.
        const bool same_way = (area > 0) == outer_counter_clockwise;
        face.Add(same_way ? TopoDS::Wire(hole.wire.Reversed()) : hole.wire);
        if (!face.IsDone()) {
            throw user_error("a hole could not be added to the profile");
        }
        result.loops.push_back(hole.edges);
    }
    result.face = face.Face();
    if (!BRepCheck_Analyzer(result.face).IsValid()) {
        throw user_error("a hole in the profile is outside the outline or overlaps another loop");
    }
    return result;
}

```

The outer loop's edge construction and every existing message are unchanged. The old inline code moved into `build_edge`/`build_loop` word for word, so `zeroLengthLineIsAPlainError` still reads "a line in the profile has zero length."

In `occt_extrude`, replace the segment loop:

```cpp
        for (int loop = 0; loop < static_cast<int>(built.loops.size()); ++loop) {
            const std::vector<TopoDS_Edge> &edges = built.loops[loop];
            for (int k = 0; k < static_cast<int>(edges.size()); ++k) {
                records.add_all(prism.Generated(edges[k]), OCCT_FROM_SEGMENT, loop, k);
            }
        }
```

In `occt_revolve`, replace the segment loop:

```cpp
        for (int loop = 0; loop < static_cast<int>(built.loops.size()); ++loop) {
            const std::vector<TopoDS_Edge> &edges = built.loops[loop];
            for (int k = 0; k < static_cast<int>(edges.size()); ++k) {
                if (revol.Generated(edges[k]).IsEmpty()) {
                    // A full revolution leaves Generated() empty for edges that sweep a planar face. The
                    // underlying sweep still knows them. The const_cast is sound: Revol() returns a const
                    // reference to MakeRevol's non-const member, and Shape(edge) does not mutate it.
                    records.add(const_cast<BRepSweep_Revol &>(revol.Revol()).Shape(edges[k]), OCCT_FROM_SEGMENT, loop, k);
                } else {
                    records.add_all(revol.Generated(edges[k]), OCCT_FROM_SEGMENT, loop, k);
                }
            }
        }
```

In `occt_loft`, refuse holes before building each section, and read the first section's outer edges:

```cpp
        for (int i = 0; i < count; ++i) {
            if (profiles[i].loop_count != 1) {
                throw user_error("a loft can't use a profile with holes");
            }
            sections.push_back(build_profile(profiles[i]));
            loft.AddWire(BRepTools::OuterWire(sections.back().face));
        }
```

```cpp
        const std::vector<TopoDS_Edge> &first = sections.front().loops.front();
```

- [ ] **Step 10: Marshal every loop (`OCCTProfile.swift`)**

Replace `withAll` in `Sources/CreatorOCCT/OCCTProfile.swift` (keep `plane`, `segment` and `with`):

```swift
    /// Calls `body` with C views of every profile (contiguous), valid only inside the call. Each
    /// view's loops are the profile's `loops`: outer first, then the holes in order.
    static func withAll<T, E: Error>(_ profiles: [Profile2D], _ body: (UnsafePointer<occt_profile>, Int) throws(E) -> T)
        throws(E) -> T {
        let loops = profiles.flatMap(\.loops)
        let segments = loops.flatMap { $0.map(segment) }
        return try segments.withUnsafeBufferPointer { segmentBuffer throws(E) in
            var offset = 0
            var loopViews: [occt_loop] = []
            for loop in loops {
                loopViews.append(occt_loop(segments: segmentBuffer.baseAddress.map { $0 + offset },
                                           segment_count: Int32(loop.count)))
                offset += loop.count
            }
            return try loopViews.withUnsafeBufferPointer { loopBuffer throws(E) in
                var first = 0
                var views: [occt_profile] = []
                for profile in profiles {
                    views.append(occt_profile(plane: plane(profile.plane), loops: loopBuffer.baseAddress.map { $0 + first },
                                              loop_count: Int32(profile.loops.count)))
                    first += profile.loops.count
                }
                return try views.withUnsafeBufferPointer { viewBuffer throws(E) in
                    guard let base = viewBuffer.baseAddress else { preconditionFailure("withAll needs at least one profile") }
                    return try body(base, viewBuffer.count)
                }
            }
        }
    }
```

- [ ] **Step 11: Keep holes in the kernel (`OCCTKernel.swift`) and park hole tags (`OCCTTagger.swift`)**

In `OCCTKernel.extrude`, replace the `let base = mode == .symmetric ? Profile2D(…segments: profile.segments) : profile` expression:

```swift
        var base = profile
        if mode == .symmetric {
            base.plane = profile.plane.offset(by: -distance / 2)
        }
```

In `OCCTKernel.loft`, directly after the `sections.count >= 2` guard:

```swift
        guard sections.allSatisfy(\.holes.isEmpty) else {
            throw KernelError.invalidInput("A loft can't use profiles with holes yet.")
        }
```

In `OCCTTagger.topology`, put this case before `case .segment:`. Task 2 replaces it. Without it, a hole wall would be named `.side(segment: k)` and collide with outer wall *k*.

```swift
            case .segment where record.operand != 0:
                continue // hole walls are named in Task 2
```

Check that no other code rebuilds a profile from `segments`:

Run: `grep -rn 'segments: .*\.segments' Sources`
Expected: no output.

- [ ] **Step 12: Run the tests to verify they pass**

Run: `swift test --filter 'HoleConformanceTests|ProfileHoleTests'`
Expected: PASS (11 hole conformance tests, 6 profile tests).

Run: `swift test`
Expected: PASS everywhere. Master's count + 18 (on `d236e73`: 357). No `EdgeID` or naming test changes, because the path for profiles without holes is unchanged.

- [ ] **Step 13: Commit**

```bash
git add Sources/CreatorGeometry/Profile2D.swift Sources/CreatorGeometry/Profile2D+Shapes.swift \
  Sources/COCCT/include/cocct.h Sources/COCCT/cocct_build.cpp \
  Sources/CreatorOCCT/OCCTProfile.swift Sources/CreatorOCCT/OCCTKernel.swift Sources/CreatorOCCT/OCCTTagger.swift \
  Tests/CreatorGeometryTests/ProfileHoleTests.swift Tests/CreatorOCCTTests/HoleConformanceTests.swift
git commit -m "feat(kernel): profiles with holes extrude and revolve through inner wires; loft refuses them"
```

---

### Task 2: Loop-aware side tags and format version 3

**Files:**
- Modify: `Sources/CreatorKernel/TopoRole.swift` (whole file), `Sources/CreatorKernel/TopoRole+Codable.swift` (whole file)
- Modify: `Sources/CreatorOCCT/OCCTTagger.swift:13-16`, `Sources/CreatorGraph/GraphFile.swift:3-4`
- Modify: `Tests/CreatorOCCTTests/NamingStabilityTests.swift:73-75`, `Tests/CreatorGraphTests/EdgePickFileTests.swift:27-31`, `Tests/CreatorOCCTTests/TaggerTests.swift:33`
- Test: `Tests/CreatorKernelTests/TopoRoleLoopTests.swift` (create), `Tests/CreatorOCCTTests/HoleConformanceTests.swift` (extend)

**Interfaces:**
- Consumes: Task 1's `Profile2D(plane:outer:holes:)`, `loops`, and the shim's `operand` = loop.
- Produces:
  - `TopoRole.side(loop: Int = 0, segment: Int)`. `.side(segment: k) == .side(loop: 0, segment: k)`.
  - `sortKey`: `side(k)` for loop 0, `side(n:k)` otherwise.
  - JSON: `{"role":"side","segment":k}` for loop 0, `{"role":"side","loop":n,"segment":k}` otherwise. A missing `loop` decodes as 0, and a negative one throws `DecodingError`.
  - `GraphFile.currentFormatVersion == 3`.

- [ ] **Step 1: Write the failing role tests**

Create `Tests/CreatorKernelTests/TopoRoleLoopTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorKernel

struct TopoRoleLoopTests {
    @Test func sideWithoutALoopIsAnOuterWall() {
        #expect(TopoRole.side(segment: 3) == .side(loop: 0, segment: 3))
        #expect(TopoRole.side(segment: 3) != .side(loop: 1, segment: 3))
    }

    @Test func outerWallSortKeysAreUnchanged() {
        #expect(TopoRole.side(segment: 3).sortKey == "side(3)")
        #expect(TopoRole.side(loop: 0, segment: 12).sortKey == "side(12)")
    }

    @Test func holeWallSortKeysNameTheLoop() {
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey == "side(1:3)")
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey != TopoRole.side(loop: 13, segment: 0).sortKey)
        #expect(TopoRole.side(loop: 1, segment: 3).sortKey != TopoRole.side(segment: 13).sortKey)
    }

    func json(_ role: TopoRole) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(role), as: UTF8.self)
    }

    @Test func outerWallsEncodeWithoutALoop() throws {
        #expect(try json(.side(segment: 2)) == #"{"role":"side","segment":2}"#)
    }

    @Test func holeWallsEncodeTheirLoop() throws {
        #expect(try json(.side(loop: 2, segment: 1)) == #"{"loop":2,"role":"side","segment":1}"#)
    }

    @Test(arguments: [TopoRole.side(loop: 1, segment: 0), .side(loop: 3, segment: 7), .side(segment: 4)])
    func sideRolesRoundTrip(_ role: TopoRole) throws {
        #expect(try JSONDecoder().decode(TopoRole.self, from: try JSONEncoder().encode(role)) == role)
    }

    @Test func aMissingLoopDecodesAsTheOuterLoop() throws {
        let role = try JSONDecoder().decode(TopoRole.self, from: Data(#"{"role":"side","segment":2}"#.utf8))
        #expect(role == .side(loop: 0, segment: 2))
    }

    @Test func aNegativeLoopIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TopoRole.self, from: Data(#"{"role":"side","loop":-1,"segment":2}"#.utf8))
        }
    }

    @Test func anOldEdgePickDecodesWithOuterWalls() throws {
        let node = NodeID()
        let json = """
        {"key": {"first": [{"node": "\(node.rawValue.uuidString)", "item": 0, "role": {"role": "endCap"}}],
                 "second": [{"node": "\(node.rawValue.uuidString)", "item": 0, "role": {"role": "side", "segment": 2}}]},
         "matchCount": 1}
        """
        let pick = try JSONDecoder().decode(EdgePick.self, from: Data(json.utf8))
        let wall = TopoTag(node: node, item: 0, role: .side(loop: 0, segment: 2))
        #expect(pick.key == EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [wall]))
    }

    @Test func aBlendOfAHoleRimRoundTrips() throws {
        let node = NodeID()
        let rim = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .side(loop: 1, segment: 0))])
        let role = TopoRole.blend(sourceEdge: rim)
        let decoded = try JSONDecoder().decode(TopoRole.self, from: try JSONEncoder().encode(role))
        #expect(decoded == role)
        #expect(decoded.sortKey == role.sortKey)
    }
}
```

- [ ] **Step 2: Write the failing file, tagger and naming tests**

In `Tests/CreatorGraphTests/EdgePickFileTests.swift`, replace `savedFilesCarryFormatVersionTwo` with:

```swift
    @Test func savedFilesCarryFormatVersionThree() throws {
        #expect(GraphFile.currentFormatVersion == 3)
        let text = String(decoding: try GraphFileIO.encode(GraphFile()), as: UTF8.self)
        #expect(text.contains(#""formatVersion" : 3"#))
    }

    @Test func versionTwoEdgePicksDecodeAsOuterWalls() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 2, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"picks": {"type": "edgePicks", "value": [{"matchCount": 1, "key": {
          "first": [{"node": "\(plate.rawValue.uuidString)", "item": 0, "role": {"role": "endCap"}}],
          "second": [{"node": "\(plate.rawValue.uuidString)", "item": 0, "role": {"role": "side", "segment": 2}}]}}]}}}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let wall = TopoTag(node: plate, item: 0, role: .side(loop: 0, segment: 2))
        #expect(file.graph.nodes[id]?.inputValues["picks"] == .edgePicks([EdgePick(key: EdgeKey([top], [wall]), matchCount: 1)]))
    }

    @Test func holeWallPicksRoundTripThroughAFile() throws {
        let top = TopoTag(node: plate, item: 0, role: .endCap)
        let rim = TopoTag(node: plate, item: 0, role: .side(loop: 1, segment: 0))
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks([EdgePick(key: EdgeKey([top], [rim]), matchCount: 1)])])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
        #expect(String(decoding: data, as: UTF8.self).contains(#""loop" : 1"#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[rule.id]?.inputValues == rule.inputValues)
    }

    @Test func outerWallPicksAreWrittenAsBefore() throws {
        let rule = makeNode(ConstantNode.self, ["picks": .edgePicks(samplePicks())])
        let text = String(decoding: try GraphFileIO.encode(GraphFile(graph: graph([rule]))), as: UTF8.self)
        #expect(!text.contains(#""loop""#))
    }
```

In `Tests/CreatorOCCTTests/TaggerTests.swift`, add before `faceRecordsCarryInputTagsAndMergeUnions`:

```swift
    @Test func segmentRecordOperandsAreProfileLoops() {
        let history = [
            OCCTHistoryRecord(outFace: 0, kind: .segment, operand: 0, index: 1),
            OCCTHistoryRecord(outFace: 1, kind: .segment, operand: 2, index: 1),
        ]
        let topology = OCCTTagger.topology(raw: raw(faces: 2), history: history, inputs: [], tag: tag)
        #expect(topology.faces[0].tags == [TopoTag(tag, .side(segment: 1))])
        #expect(topology.faces[1].tags == [TopoTag(tag, .side(loop: 2, segment: 1))])
    }
```

In `Tests/CreatorOCCTTests/HoleConformanceTests.swift`, add before the struct's closing brace:

```swift
    // MARK: - Naming (Task 2)

    func isUnnamed(_ face: FaceInfo) -> Bool {
        face.tags.contains { if case .unnamed = $0.role { true } else { false } }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func holeWallsAreTaggedWithTheirLoop(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await under.make().extrude(plate, distance: 3, mode: .oneSided, tag: tag)
        let wall = try #require(faces(solid, role: .side(loop: 1, segment: 0), of: tag).first)
        #expect(wall.kind == .cylinder)
        #expect(faces(solid, role: .side(loop: 1, segment: 0), of: tag).count == 1)
        for k in 0..<4 {
            #expect(faces(solid, role: .side(segment: k), of: tag).count == 1)
        }
        #expect(faces(solid, role: .startCap, of: tag).count == 1)
        #expect(faces(solid, role: .endCap, of: tag).count == 1)
        #expect(solid.topology.faces.allSatisfy { $0.tags.count == 1 && !isUnnamed($0) })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func outerWallsAreNamedAsWithoutTheHole(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let (plainTag, holedTag) = (newTag(), newTag())
        let plain = try await kernel.extrude(Profile2D(plane: .xy, segments: plate.outer), distance: 3, mode: .oneSided, tag: plainTag)
        let holed = try await kernel.extrude(plate, distance: 3, mode: .oneSided, tag: holedTag)
        for k in 0..<4 {
            let before = try #require(faces(plain, role: .side(segment: k), of: plainTag).first?.normal)
            let after = try #require(faces(holed, role: .side(segment: k), of: holedTag).first?.normal)
            #expect(before.dot(after) > 0.999)
        }
    }

    @Test(arguments: KernelUnderTest.allCases, [false, true])
    func holeWallsFollowSegmentOrderWhicheverWayTheHoleWinds(_ under: KernelUnderTest, clockwise: Bool) async throws {
        let tag = newTag()
        let hole = squareHole(clockwise: clockwise)
        let profile = Profile2D(plane: .xy, outer: plate.outer, holes: [hole])
        let solid = try await under.make().extrude(profile, distance: 2, mode: .oneSided, tag: tag)
        for (k, segment) in hole.enumerated() {
            let wall = try #require(faces(solid, role: .side(loop: 1, segment: k), of: tag).first)
            // A hole wall faces into the hole: towards the hole's centre, the origin.
            let midpoint = (segment.startPoint + segment.endPoint) * 0.5
            let inward = try #require(Vector3(-midpoint.x, -midpoint.y, 0).normalized)
            #expect((wall.normal ?? .zero).dot(inward) > 0.999, "hole wall \(k) normal \(String(describing: wall.normal))")
        }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func eachHoleGetsItsOwnLoopIndex(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let holes = [Vector2(-2.5, 0), Vector2(2.5, 0)].map { Profile2D.circle(radius: 1, center: $0, plane: .xy).segments }
        let solid = try await under.make().extrude(Profile2D(plane: .xy, outer: plate.outer, holes: holes), distance: 1,
                                                   mode: .oneSided, tag: tag)
        let left = try #require(faces(solid, role: .side(loop: 1, segment: 0), of: tag).first)
        let right = try #require(faces(solid, role: .side(loop: 2, segment: 0), of: tag).first)
        #expect(left.centroid.x < 0 && right.centroid.x > 0)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aRevolvedHoleWallIsTagged(_ under: KernelUnderTest) async throws {
        let tag = newTag()
        let solid = try await under.make().revolve(tubeSection, axis: .z, angle: .degrees(360), tag: tag)
        let cavity = try #require(faces(solid, role: .side(loop: 1, segment: 0), of: tag).first)
        #expect(cavity.kind == .torus)
        #expect(!solid.topology.faces.contains(where: isUnnamed))
    }

    /// A `width` × 40 plate on XY with a Ø5 hole at the origin, 6 thick.
    func holedPlate(width: Double) -> Profile2D {
        Profile2D(plane: .xy, outer: Profile2D.rectangle(width: width, height: 40, plane: .xy).segments,
                  holes: [Profile2D.circle(radius: 2.5, center: .zero, plane: .xy).segments])
    }

    @Test(arguments: KernelUnderTest.allCases)
    func aHoleRimKeepsItsKeyWhenTheOutlineChanges(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let plateTag = newTag()
        var rims: [Set<EdgeKey>] = []
        for width in [60.0, 90.0] {
            let solid = try await kernel.extrude(holedPlate(width: width), distance: 6, mode: .oneSided, tag: plateTag)
            let rim = edges(solid, between: { hasTag($0, .endCap, of: plateTag) },
                            and: { hasTag($0, .side(loop: 1, segment: 0), of: plateTag) })
            #expect(rim.count == 1)
            rims.append(Set(rim.compactMap { solid.topology.key(of: $0) }))
            let chamfered = try await kernel.chamfer(solid, edges: rim.map(\.id), distance: 0.5, tag: newTag())
            #expect(chamfered.topology.faces.count == solid.topology.faces.count + 1)
        }
        #expect(rims[0].count == 1)
        #expect(rims[0] == rims[1])
    }
```

- [ ] **Step 3: Run them to verify they fail**

Run: `swift test --filter 'TopoRoleLoopTests|EdgePickFileTests|TaggerTests|HoleConformanceTests'`
Expected: compile errors at every `.side(loop:segment:)` call, because the case has no `loop` label yet.

- [ ] **Step 4: Make the role loop-aware**

Replace `Sources/CreatorKernel/TopoRole.swift` with:

```swift
/// The stable role a face plays in the operation that created it (spec §5.3).
public indirect enum TopoRole: Hashable, Sendable {
    case startCap
    case endCap
    /// The side face swept from segment `segment` of profile loop `loop`: 0 is the outer loop,
    /// n is hole n (`Profile2D.loops`). `loop` defaults to 0, so `.side(segment: k)` is an outer wall.
    case side(loop: Int = 0, segment: Int)
    /// The blend face a fillet or chamfer made from the edge `sourceEdge`.
    case blend(sourceEdge: EdgeKey)
    /// A face the operation's history does not explain. Unstable across rebuilds by design;
    /// it exists so that no face ever has an empty tag set (M2 plan decision).
    case unnamed(face: Int)

    /// A deterministic text form, used to order tags canonically. Outer walls keep the
    /// pre-hole form `side(k)`; hole walls are `side(loop:k)`.
    public var sortKey: String {
        switch self {
        case .startCap: "startCap"
        case .endCap: "endCap"
        case .side(loop: 0, let segment): "side(\(segment))"
        case .side(let loop, let segment): "side(\(loop):\(segment))"
        case .blend(let edge): "blend(\(edge.sortKey))"
        case .unnamed(let face): "unnamed(\(face))"
        }
    }
}
```

Replace `Sources/CreatorKernel/TopoRole+Codable.swift` with:

```swift
/// `{"role": "side", "segment": k}` is an outer wall; a hole wall adds `"loop": n`. The loop is
/// written only when it isn't 0, so outer-wall tags encode exactly as they did before holes, and a
/// missing loop decodes as 0 (format version 2 files).
extension TopoRole: Codable {
    private enum CodingKeys: String, CodingKey { case role, loop, segment, edge, face }
    private enum Kind: String, Codable { case startCap, endCap, side, blend, unnamed }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .role) {
        case .startCap: self = .startCap
        case .endCap: self = .endCap
        case .side:
            let loop = try container.decodeIfPresent(Int.self, forKey: .loop) ?? 0
            guard loop >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .loop, in: container, debugDescription: "A side face's loop can't be negative.")
            }
            self = .side(loop: loop, segment: try container.decode(Int.self, forKey: .segment))
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
        case .side(let loop, let segment):
            try container.encode(Kind.side, forKey: .role)
            if loop != 0 {
                try container.encode(loop, forKey: .loop)
            }
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

- [ ] **Step 5: Name hole walls, fix the one test binding, bump the format**

In `Sources/CreatorOCCT/OCCTTagger.swift`, replace Task 1's skip and the old segment case with:

```swift
            case .segment:
                // A segment record's operand is the profile loop (0 = outer), see cocct.h.
                tags[record.outFace, default: []].insert(TopoTag(tag, .side(loop: record.operand, segment: record.index)))
```

In `Tests/CreatorOCCTTests/NamingStabilityTests.swift`, `plateSideSegment` must match outer walls only, with both values named:

```swift
    /// The plate outer-wall segment index of a key side that is exactly one plate `.side` tag, else nil.
    func plateSideSegment(_ side: Set<TopoTag>, plate: NodeID) -> Int? {
        guard side.count == 1, let tag = side.first, tag.node == plate, case .side(loop: 0, let segment) = tag.role else { return nil }
        return segment
    }
```

In `Sources/CreatorGraph/GraphFile.swift`:

```swift
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. Version-1 and -2 files still load unchanged.
    public static let currentFormatVersion = 3
```

- [ ] **Step 6: Gate against tuple-binding `.side` patterns**

`case .side(let s)` against a two-value case compiles. It binds the whole `(loop:, segment:)` tuple and gives only a deprecation warning, so a missed site silently changes names. Run:

```bash
grep -rnE '\.side\((let|var) [A-Za-z_]+\)|case let \.side\(' Sources Tests
rm -rf .build    # a clean build, so every file re-emits its warnings (about a minute)
swift build --build-tests 2>&1 | grep -E 'matching them as a tuple|warning:' | grep -v 'built for newer'
```

Expected: no output from either command. Bare `case .side` matches (`EdgePick.swift:27`, `NamingStabilityTests.swift:46,81`, `BracketAcceptanceTests.swift:94`) are fine and stay as they are.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter 'TopoRoleLoopTests|EdgePickFileTests|TaggerTests|HoleConformanceTests|NamingStabilityTests'`
Expected: PASS.

Run: `swift test`
Expected: PASS everywhere, master's count + 38 (on `d236e73`: 377). `NamingStabilityTests` and `BracketAcceptanceTests` pass unchanged: outer walls keep their keys, and no M2/M3 profile has holes.

- [ ] **Step 8: Commit**

```bash
git add Sources/CreatorKernel/TopoRole.swift Sources/CreatorKernel/TopoRole+Codable.swift \
  Sources/CreatorOCCT/OCCTTagger.swift Sources/CreatorGraph/GraphFile.swift \
  Tests/CreatorKernelTests/TopoRoleLoopTests.swift Tests/CreatorGraphTests/EdgePickFileTests.swift \
  Tests/CreatorOCCTTests/TaggerTests.swift Tests/CreatorOCCTTests/HoleConformanceTests.swift \
  Tests/CreatorOCCTTests/NamingStabilityTests.swift
git commit -m "feat(naming): hole walls are side(loop:segment:); loop 0 encodes as before; format version 3"
```

---

### Task 3: FakeKernel parity, value estimate and docs

**Files:**
- Modify: `Sources/CreatorKernel/FakeKernel.swift:40-44, 150-182`, `Sources/CreatorGraph/Scalar.swift:55`
- Modify: `CLAUDE.md` (Project state, Rules), `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md:144, 147, 149` (§6 Shim, Tags, Graph)
- Test: `Tests/CreatorKernelTests/FakeKernelHoleTests.swift`, `Tests/CreatorGraphTests/ProfileEstimateTests.swift`, `Tests/CreatorOCCTTests/HoleConformanceTests.swift` (extend: FakeKernel/OCCT parity)

**Interfaces:**
- Consumes: `Profile2D.loops`, `Profile2D.holes`, `Profile2D.segmentCount` (Task 1), `TopoRole.side(loop:segment:)` (Task 2).
- Produces: FakeKernel topology for profiles with holes. Faces are caps 0 and 1, then the outer walls, then each hole's walls in loop order. Edges are numbered per loop: cap edges per segment, then between-side edges (or a seam). The outer loop's numbering is identical to a profile without holes.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorKernelTests/FakeKernelHoleTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelHoleTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
    let circle = Profile2D.circle(radius: 2, center: .zero, plane: .xy).segments
    let square = Profile2D.rectangle(width: 4, height: 4, plane: .xy).segments

    func roles(_ solid: Solid) -> [TopoRole] { solid.topology.faces.flatMap(\.tags).map(\.role) }

    @Test func holeWallsAreTaggedWithTheirLoop() async throws {
        let solid = try await FakeKernel().extrude(Profile2D(plane: .xy, outer: outline, holes: [circle, square]), distance: 2,
                                                   mode: .oneSided, tag: tag)
        // Two caps, four outer walls, one circular hole wall, four square hole walls.
        #expect(solid.topology.faces.count == 11)
        #expect(roles(solid).filter { $0 == .side(loop: 1, segment: 0) }.count == 1)
        for k in 0..<4 {
            #expect(roles(solid).filter { $0 == .side(segment: k) }.count == 1)
            #expect(roles(solid).filter { $0 == .side(loop: 2, segment: k) }.count == 1)
        }
    }

    @Test func theOuterLoopIsNumberedAsWithoutHoles() async throws {
        let kernel = FakeKernel()
        let plain = try await kernel.extrude(Profile2D(plane: .xy, segments: outline), distance: 2, mode: .oneSided, tag: tag)
        let holed = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [square]), distance: 2,
                                             mode: .oneSided, tag: tag)
        #expect(Array(holed.topology.faces.prefix(plain.topology.faces.count)) == plain.topology.faces)
        #expect(Array(holed.topology.edges.prefix(plain.topology.edges.count)) == plain.topology.edges)
        #expect(holed.bounds == plain.bounds)
    }

    @Test func aCircularHoleHasASeamAndASquareHoleHasConcaveCorners() async throws {
        let kernel = FakeKernel()
        let round = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [circle]), distance: 2,
                                             mode: .oneSided, tag: tag)
        #expect(round.topology.edges.filter(\.isSeam).count == 1)
        let squared = try await kernel.extrude(Profile2D(plane: .xy, outer: outline, holes: [square]), distance: 2,
                                               mode: .oneSided, tag: tag)
        #expect(squared.topology.edges.filter { $0.convexity == .concave }.count == 4)
        #expect(squared.topology.edges.allSatisfy { squared.topology.key(of: $0) != nil })
    }

    @Test func anOpenHoleIsRejected() async {
        let open: [Segment2D] = [.line(Vector2(0, 0), Vector2(1, 0))]
        await #expect(throws: KernelError.invalidInput("The profile is not a closed loop.")) {
            try await FakeKernel().extrude(Profile2D(plane: .xy, outer: outline, holes: [open]), distance: 1, mode: .oneSided, tag: tag)
        }
    }

    @Test func aLoftRefusesProfilesWithHoles() async {
        let holed = Profile2D(plane: .xy, outer: outline, holes: [circle])
        await #expect(throws: KernelError.invalidInput("A loft can't use profiles with holes yet.")) {
            try await FakeKernel().loft([holed, holed], ruled: true, tag: tag)
        }
    }
}
```

Keep the face count as a literal: `2 + 4 + 1 + 4` inside `#expect` makes Swift 6.4 time out on type-checking.

In `Tests/CreatorOCCTTests/HoleConformanceTests.swift`, add before the struct's closing brace. It pins FakeKernel's hole topology to OCCT's, so a later change to either kernel can't drift silently:

```swift
    /// Each edge as "face roles | kind | convexity | seam", sorted, so two kernels' numbering doesn't matter.
    func edgeSummary(_ solid: Solid) -> [String] {
        solid.topology.edges.map { edge in
            let roles = edge.faces.compactMap { solid.topology.face($0) }
                .map { $0.tags.map(\.role.sortKey).sorted().joined(separator: "+") }.sorted()
            return "\(roles.joined(separator: "|")) \(edge.kind) \(edge.convexity) \(edge.isSeam)"
        }.sorted()
    }

    @Test func fakeKernelHoleTopologyMatchesOCCT() async throws {
        let holes = [Profile2D.rectangle(width: 2, height: 2, plane: .xy).translated(by: Vector2(-2.5, 0)).segments,
                     Profile2D.circle(radius: 1, center: Vector2(2.5, 0), plane: .xy).segments]
        let profile = Profile2D(plane: .xy, outer: plate.outer, holes: holes)
        let tag = newTag()
        let fake = try await FakeKernel().extrude(profile, distance: 2, mode: .oneSided, tag: tag)
        let occt = try await OCCTKernel().extrude(profile, distance: 2, mode: .oneSided, tag: tag)
        #expect(occt.topology.edges.count == 27)
        #expect(edgeSummary(fake) == edgeSummary(occt))
        let fakeFaces = fake.topology.faces.map(\.kind.rawValue).sorted()
        let occtFaces = occt.topology.faces.map(\.kind.rawValue).sorted()
        #expect(fakeFaces == occtFaces)
    }
```

Keep the two face-kind arrays in `let`s: comparing the two `sorted { … }` chains inside one `#expect` makes Swift 6.4 time out on type-checking.

Create `Tests/CreatorGraphTests/ProfileEstimateTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct ProfileEstimateTests {
    @Test func aProfileEstimateCountsHoleSegments() {
        let outline = Profile2D.rectangle(width: 10, height: 10, plane: .xy).segments
        let hole = Profile2D.circle(radius: 1, center: .zero, plane: .xy).segments
        #expect(Scalar.profile(Profile2D(plane: .xy, segments: outline)).estimatedBytes == 64 + 4 * 48)
        #expect(Scalar.profile(Profile2D(plane: .xy, outer: outline, holes: [hole])).estimatedBytes == 64 + 5 * 48)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'FakeKernelHoleTests|ProfileEstimateTests|fakeKernelHoleTopologyMatchesOCCT'`
Expected: FAIL. The face count is 6, not 11, and the parity summaries differ (FakeKernel has 12 edges to OCCT's 27). No `.side(loop: 1, …)` or `.side(loop: 2, …)` roles exist. The circle's seam is missing and there are no concave edges. The loft throws `unsupported("loft")`, and the estimate is `64 + 4 * 48`.

- [ ] **Step 3: Implement FakeKernel holes and the estimate**

In `Sources/CreatorKernel/FakeKernel.swift`, `loft`, after `operationLog.append("loft")`:

```swift
        guard sections.allSatisfy(\.holes.isEmpty) else {
            throw KernelError.invalidInput("A loft can't use profiles with holes yet.")
        }
```

Replace `prism` and its doc comment:

```swift
    /// Caps, then for each loop (outer first, then holes): one side face per segment tagged
    /// `.side(loop:segment:)`, bottom and top edges per segment, and between-side edges. A
    /// single-segment loop (a circle) gets a seam instead of between-side edges. Hole corners are
    /// concave. The outer loop's faces and edges are numbered exactly as for a profile without holes.
    private static func prism(_ profile: Profile2D, distance: Double, tag: NodeTag) -> Topology {
        let normal = profile.plane.normal
        var faces = [
            FaceInfo(id: FaceID(0), kind: .plane, normal: -normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .startCap)]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: normal, area: 0, centroid: .zero, tags: [TopoTag(tag, .endCap)]),
        ]
        var edges: [EdgeInfo] = []
        func addEdge(_ kind: CurveKind, _ direction: Vector3?, _ length: Double, _ convexity: Convexity, _ a: Int, _ b: Int) {
            edges.append(EdgeInfo(id: EdgeID(edges.count), kind: kind, direction: direction, length: length,
                                  midpoint: .zero, convexity: convexity, faces: [FaceID(a), FaceID(b)]))
        }
        for (loop, segments) in profile.loops.enumerated() {
            let first = faces.count
            for (k, segment) in segments.enumerated() {
                let side = first + k
                let isLine: Bool
                if case .line = segment { isLine = true } else { isLine = false }
                faces.append(FaceInfo(id: FaceID(side), kind: isLine ? .plane : .cylinder, normal: nil, area: 0,
                                      centroid: .zero, tags: [TopoTag(tag, .side(loop: loop, segment: k))]))
                let along: Vector3? = isLine ? (profile.plane.point(segment.endPoint) - profile.plane.point(segment.startPoint)).normalized : normal
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 0, side)
                addEdge(isLine ? .line : .circle, along, segment.length, .convex, 1, side)
            }
            if segments.count == 1 {
                addEdge(.line, normal, distance, .smooth, first, first)
            } else {
                for k in segments.indices {
                    addEdge(.line, normal, distance, loop == 0 ? .convex : .concave, first + k, first + (k + 1) % segments.count)
                }
            }
        }
        return Topology(faces: faces, edges: edges)
    }
```

In `Sources/CreatorGraph/Scalar.swift`, `estimatedBytes`:

```swift
        case .profile(let profile): 64 + profile.segmentCount * 48
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'FakeKernelHoleTests|ProfileEstimateTests|FakeKernelTests|HoleConformanceTests'`
Expected: PASS. The existing `FakeKernelTests` pass unchanged: 6 faces and 12 edges for a rectangle.

- [ ] **Step 5: Update the docs**

In `CLAUDE.md`, "Project state", append S3 to the list of finished milestones. For example, "M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes) and S3 (profile holes) are done.", merged with whatever M4 wrote there.

In `CLAUDE.md`, "Rules", replace `File format is version 2 (\`.edgePicks\`).` with:

```markdown
File format is version 3 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero).
`Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init from `segments`). Side tags are
`.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
binds the tuple and only warns). The shim orients hole wires against the outer wire; history `operand` on segment
records is the loop. Loft refuses profiles with holes.
```

In `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` §6 (line 144), replace `Hole wires are oriented clockwise relative to the plane normal.` with:

```markdown
Hole wires are oriented against the outer wire (S3 probe: OCCT needs opposite windings, and the outer loop may wind either way, so "clockwise relative to the plane normal" holds only for a counter-clockwise outline). The loop index travels in the history record's `operand`.
```

In the same section, replace the **Tags** line (line 147) with:

```markdown
**Tags:** `TopoRole.side(segment:)` becomes `side(loop: Int = 0, segment: Int)`, where `loop == 0` is the outer loop, so `.side(segment:)` still compiles and means the outer loop. `sortKey` and `Codable` stay compatible: `loop` is written only when non-zero, and a missing `loop` decodes as 0.
```

And replace the **Graph** line (line 149) with:

```markdown
**Graph:** S3 bumps `GraphFile.currentFormatVersion` to 3, because files with hole-wall picks carry a `loop` that older readers can't decode. S4 adds `ConstantValue.sketch(Sketch)` and bumps it again, to 4 (parent spec rule: a new `ConstantValue` kind means a version bump).
```

- [ ] **Step 6: Final verification**

Run: `swift test`
Expected: PASS everywhere, master's count + 45 (on `d236e73`: 384 = 339 + 45).

Run: `rm -rf .build && swift build --build-tests 2>&1 | grep -iE 'warning|error' | grep -v 'built for newer'`
Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorKernel/FakeKernel.swift Sources/CreatorGraph/Scalar.swift \
  Tests/CreatorKernelTests/FakeKernelHoleTests.swift Tests/CreatorGraphTests/ProfileEstimateTests.swift \
  Tests/CreatorOCCTTests/HoleConformanceTests.swift \
  CLAUDE.md docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md
git commit -m "feat(kernel): FakeKernel names hole walls like OCCT; docs for format version 3 and profile holes"
```

---

## What comes next

- **S4** switches `CreatorSketch` regions to `Profile2D(plane:outer:holes:)`, adds `ConstantValue.sketch`, and bumps the format again (3 → 4) for the new constant kind. S4's Sketch → Extrude integration test is the first place where holes come from a node. Its edge-pick test should pick a hole rim, which `aHoleRimKeepsItsKeyWhenTheOutlineChanges` already covers at kernel level.
- **Open risk: hole order is identity.** A hole's loop index is its position in `holes`. S2's region finder must emit holes in a deterministic order, for example by area descending, then centroid x, then y, like the regions themselves (sketcher spec §5.5). Otherwise a sketch edit that reorders holes renames their walls, and picks on hole walls drift. Record this in the S2/S4 plans.
- **Loft with holes** stays deferred. Both kernels and the shim refuse it with a plain message.
