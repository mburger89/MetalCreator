// Capping a sheet's flat holes (NS-5, Task 6; rulings R5, R12, R15, R17).
//
// The free edges of the sheet's faces are chained into loops. A closed loop whose samples lie within `flatness` of its own plane is flat;
// flat loops in one plane are nested even-odd into planar faces with holes. The caps and the sheet's faces are sewn at 0.01 mm and each
// closed shell is made a solid. The input's solids are set aside and put back as they were.

#include "cocct_progress.hpp"
#include "cocct_sheet.hpp"
#include "cocct_solids.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <BRepLib.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Builder.hxx>
#include <ShapeAnalysis_FreeBounds.hxx>
#include <TopExp.hxx>
#include <TopTools_HSequenceOfShape.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Dir.hxx>
#include <gp_Pln.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <memory>
#include <set>
#include <tuple>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kInvalidCapped = "Capping made an invalid shape; the holes can't be capped.";
constexpr double kSewTolerance = 0.01;
constexpr double kNormalTolerance = 1e-6;
constexpr int kSamplesPerEdge = 32;

struct loop_info {
    TopoDS_Wire wire;
    std::vector<int> edges; // 1-based in the input's edge map
    std::vector<gp_Pnt> points;
    gp_Pnt centre;
    gp_Dir normal = gp_Dir(0, 0, 1);
    bool flat = false;
    bool on_sheet = false; // flat, but a planar face of the sheet already lies in its plane
    // Filled once the loop's plane group is known.
    std::vector<std::pair<double, double>> plane_points;
    double signed_area = 0;
};

struct plane_group {
    gp_Pnt origin;
    gp_Dir normal;
    gp_Pln plane;
    std::vector<int> loops;
};

struct cap_made {
    TopoDS_Face face;
    std::vector<int> source_edges;
};

void sample_loop(loop_info &loop, const TopTools_IndexedMapOfShape &edge_map) {
    for (BRepTools_WireExplorer it(loop.wire); it.More(); it.Next()) {
        const TopoDS_Edge edge = it.Current();
        const int index = edge_map.FindIndex(edge);
        if (index > 0 && std::find(loop.edges.begin(), loop.edges.end(), index) == loop.edges.end()) {
            loop.edges.push_back(index);
        }
        if (BRep_Tool::Degenerated(edge)) {
            continue;
        }
        BRepAdaptor_Curve curve(edge);
        const double first = curve.FirstParameter();
        const double last = curve.LastParameter();
        const bool reversed = edge.Orientation() == TopAbs_REVERSED;
        for (int i = 0; i < kSamplesPerEdge; ++i) {
            const double t = static_cast<double>(i) / kSamplesPerEdge;
            loop.points.push_back(curve.Value(reversed ? last - (last - first) * t : first + (last - first) * t));
        }
    }
}

/// Newell's normal and the centroid of the samples; flat when every sample is within `flatness` of that plane.
void classify(loop_info &loop, double flatness) {
    const std::vector<gp_Pnt> &pts = loop.points;
    if (pts.size() < 3) {
        return;
    }
    double cx = 0, cy = 0, cz = 0;
    double nx = 0, ny = 0, nz = 0;
    for (size_t i = 0; i < pts.size(); ++i) {
        const gp_Pnt &a = pts[i];
        const gp_Pnt &b = pts[(i + 1) % pts.size()];
        cx += a.X();
        cy += a.Y();
        cz += a.Z();
        nx += (a.Y() - b.Y()) * (a.Z() + b.Z());
        ny += (a.Z() - b.Z()) * (a.X() + b.X());
        nz += (a.X() - b.X()) * (a.Y() + b.Y());
    }
    const double count = static_cast<double>(pts.size());
    loop.centre = gp_Pnt(cx / count, cy / count, cz / count);
    const double length = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (!(length > 1e-9)) {
        return;
    }
    nx /= length;
    ny /= length;
    nz /= length;
    // The sign is arbitrary: the largest component is made positive so parallel loops compare equal.
    const double ax = std::abs(nx), ay = std::abs(ny), az = std::abs(nz);
    const double biggest = ax >= ay && ax >= az ? nx : (ay >= az ? ny : nz);
    if (biggest < 0) {
        nx = -nx;
        ny = -ny;
        nz = -nz;
    }
    loop.normal = gp_Dir(nx, ny, nz);
    for (const gp_Pnt &p : pts) {
        const double distance = (p.X() - loop.centre.X()) * nx + (p.Y() - loop.centre.Y()) * ny + (p.Z() - loop.centre.Z()) * nz;
        if (std::abs(distance) > flatness) {
            return;
        }
    }
    loop.flat = true;
}

/// Whether a face along the loop is a plane the loop lies in: a planar cap there would coincide with that face.
bool lies_on_sheet(const loop_info &loop, const TopTools_IndexedMapOfShape &edge_map,
                   const TopTools_IndexedDataMapOfShapeListOfShape &ancestors) {
    for (int index : loop.edges) {
        const TopoDS_Shape &edge = edge_map(index);
        for (const TopoDS_Face &face : distinct_faces(edge, ancestors)) {
            const BRepAdaptor_Surface surface(face);
            if (surface.GetType() != GeomAbs_Plane) {
                continue;
            }
            const gp_Pln plane = surface.Plane();
            const gp_Dir face_normal = plane.Axis().Direction();
            if (gp_Vec(face_normal).Crossed(gp_Vec(loop.normal)).Magnitude() > kNormalTolerance) {
                continue;
            }
            const bool coplanar = std::all_of(loop.points.begin(), loop.points.end(),
                                              [&](const gp_Pnt &p) { return plane.Distance(p) <= 0.01; });
            if (coplanar) {
                return true;
            }
        }
    }
    return false;
}

bool inside_polygon(const std::vector<std::pair<double, double>> &polygon, double x, double y) {
    bool inside = false;
    for (size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
        const double xi = polygon[i].first, yi = polygon[i].second;
        const double xj = polygon[j].first, yj = polygon[j].second;
        if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
            inside = !inside;
        }
    }
    return inside;
}

void collect(const TopoDS_Shape &shape, std::vector<TopoDS_Shape> &parts) {
    if (shape.IsNull()) {
        return;
    }
    switch (shape.ShapeType()) {
    case TopAbs_COMPOUND:
    case TopAbs_COMPSOLID:
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            collect(it.Value(), parts);
        }
        break;
    case TopAbs_SOLID:
    case TopAbs_SHELL:
    case TopAbs_FACE:
        parts.push_back(shape);
        break;
    default:
        break;
    }
}

/// One face (with holes) per even-depth loop of the group; null faces are skipped and counted by the caller.
std::vector<cap_made> make_caps(const plane_group &group, std::vector<loop_info> &loops, int &failed) {
    std::vector<cap_made> caps;
    const gp_Ax3 frame = group.plane.Position();
    const gp_Vec x_dir(frame.XDirection());
    const gp_Vec y_dir(frame.YDirection());
    for (int index : group.loops) {
        loop_info &loop = loops[index];
        for (const gp_Pnt &p : loop.points) {
            const gp_Vec v(group.origin, p);
            loop.plane_points.emplace_back(v.Dot(x_dir), v.Dot(y_dir));
        }
        double area = 0;
        for (size_t i = 0; i < loop.plane_points.size(); ++i) {
            const auto &a = loop.plane_points[i];
            const auto &b = loop.plane_points[(i + 1) % loop.plane_points.size()];
            area += a.first * b.second - b.first * a.second;
        }
        loop.signed_area = 0.5 * area;
    }
    const size_t count = group.loops.size();
    std::vector<int> depth(count, 0);
    std::vector<std::vector<bool>> contained(count, std::vector<bool>(count, false)); // contained[b][a]: b inside a
    for (size_t b = 0; b < count; ++b) {
        const loop_info &inner = loops[group.loops[b]];
        for (size_t a = 0; a < count; ++a) {
            if (a == b) {
                continue;
            }
            const loop_info &outer = loops[group.loops[a]];
            if (std::abs(outer.signed_area) <= std::abs(inner.signed_area)) {
                continue;
            }
            if (inside_polygon(outer.plane_points, inner.plane_points[0].first, inner.plane_points[0].second)) {
                contained[b][a] = true;
                ++depth[b];
            }
        }
    }
    for (size_t a = 0; a < count; ++a) {
        if (depth[a] % 2 != 0) {
            continue;
        }
        loop_info &outer = loops[group.loops[a]];
        // The outer wire runs counter-clockwise about the plane's normal, its holes clockwise.
        TopoDS_Shape outer_wire = BRepBuilderAPI_Copy(outer.wire, Standard_True, Standard_False).Shape();
        if (outer.signed_area < 0) {
            outer_wire = outer_wire.Reversed();
        }
        BRepBuilderAPI_MakeFace maker(group.plane, TopoDS::Wire(outer_wire), Standard_True);
        if (!maker.IsDone()) {
            ++failed;
            continue;
        }
        for (size_t b = 0; b < count; ++b) {
            if (!contained[b][a] || depth[b] != depth[a] + 1) {
                continue;
            }
            loop_info &hole = loops[group.loops[b]];
            TopoDS_Shape hole_wire = BRepBuilderAPI_Copy(hole.wire, Standard_True, Standard_False).Shape();
            if (hole.signed_area > 0) {
                hole_wire = hole_wire.Reversed();
            }
            maker.Add(TopoDS::Wire(hole_wire));
        }
        TopoDS_Face face = maker.Face();
        TopTools_ListOfShape face_edges;
        for (TopExp_Explorer it(face, TopAbs_EDGE); it.More(); it.Next()) {
            face_edges.Append(it.Current());
        }
        BRepLib::BuildPCurveForEdgesOnPlane(face_edges, face);
        cap_made cap;
        cap.face = face;
        cap.source_edges = outer.edges;
        caps.push_back(cap);
    }
    return caps;
}

} // namespace

occt_shape *occt_cap_planar_holes(const occt_shape *sheet, double flatness, const occt_cancel *cancel, occt_history *history,
                                  occt_edge_history *edges, occt_cap_loops *loops_out, int *capped, int *not_flat,
                                  occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull()) {
            throw user_error("This surface can't be used.");
        }
        poll(cancel);
        // Work on a copy; it keeps the input's face and edge order.
        const TopoDS_Shape work = BRepBuilderAPI_Copy(sheet->shape, Standard_True, Standard_False).Shape();
        const TopTools_IndexedMapOfShape work_faces = map_of(work, TopAbs_FACE);
        const TopTools_IndexedMapOfShape work_edges = map_of(work, TopAbs_EDGE);

        std::vector<TopoDS_Shape> solids;
        for (TopExp_Explorer it(work, TopAbs_SOLID); it.More(); it.Next()) {
            solids.push_back(it.Current());
        }
        BRep_Builder builder;
        TopoDS_Compound rest;
        builder.MakeCompound(rest);
        std::vector<TopoDS_Face> rest_faces;
        for (TopExp_Explorer it(work, TopAbs_FACE, TopAbs_SOLID); it.More(); it.Next()) {
            rest_faces.push_back(TopoDS::Face(it.Current()));
            builder.Add(rest, it.Current());
        }

        // The free edges of the rest: one distinct face, not closed on it (a seam is), not degenerate.
        TopTools_IndexedDataMapOfShapeListOfShape ancestors;
        TopExp::MapShapesAndAncestors(rest, TopAbs_EDGE, TopAbs_FACE, ancestors);
        Handle(TopTools_HSequenceOfShape) free_edges = new TopTools_HSequenceOfShape();
        for (int i = 1; i <= ancestors.Extent(); ++i) {
            const TopoDS_Edge edge = TopoDS::Edge(ancestors.FindKey(i));
            if (is_boundary_edge(edge, distinct_faces(edge, ancestors))) {
                free_edges->Append(edge);
            }
        }
        poll(cancel);

        std::vector<loop_info> loops;
        int flat_failed = 0;
        std::vector<cap_made> caps;
        int not_flat_count = 0;
        if (free_edges->Length() > 0) {
            Handle(TopTools_HSequenceOfShape) wires;
            ShapeAnalysis_FreeBounds::ConnectEdgesToWires(free_edges, 1e-6, Standard_True, wires);
            for (int i = 1; i <= wires->Length(); ++i) {
                const TopoDS_Wire wire = TopoDS::Wire(wires->Value(i));
                TopoDS_Vertex first, last;
                TopExp::Vertices(wire, first, last);
                if (first.IsNull() || last.IsNull() || !first.IsSame(last)) {
                    continue; // an open chain isn't a hole
                }
                loop_info loop;
                loop.wire = wire;
                sample_loop(loop, work_edges);
                classify(loop, flatness);
                if (loop.flat && lies_on_sheet(loop, work_edges, ancestors)) {
                    loop.flat = false;
                    loop.on_sheet = true; // a cap here would sit on the sheet's own face: left open, and not "not flat"
                }
                loops.push_back(std::move(loop));
            }
            std::vector<plane_group> groups;
            for (size_t i = 0; i < loops.size(); ++i) {
                if (!loops[i].flat) {
                    if (!loops[i].on_sheet) {
                        ++not_flat_count;
                    }
                    continue;
                }
                bool placed = false;
                for (plane_group &group : groups) {
                    const gp_Vec cross = gp_Vec(group.normal).Crossed(gp_Vec(loops[i].normal));
                    const double offset = gp_Vec(group.origin, loops[i].centre).Dot(gp_Vec(group.normal));
                    if (cross.Magnitude() <= kNormalTolerance && std::abs(offset) <= 0.01) {
                        group.loops.push_back(static_cast<int>(i));
                        placed = true;
                        break;
                    }
                }
                if (!placed) {
                    plane_group group;
                    group.origin = loops[i].centre;
                    group.normal = loops[i].normal;
                    group.plane = gp_Pln(group.origin, group.normal);
                    group.loops.push_back(static_cast<int>(i));
                    groups.push_back(std::move(group));
                }
            }
            for (const plane_group &group : groups) {
                poll(cancel);
                std::vector<cap_made> made = make_caps(group, loops, flat_failed);
                caps.insert(caps.end(), made.begin(), made.end());
            }
            not_flat_count += flat_failed;
        }

        // Nothing to cap and the rest has free edges (open sheets): the input comes back as it was.
        const bool closed_rest = free_edges->Length() == 0;
        std::vector<TopoDS_Shape> result_parts = solids;
        std::unique_ptr<BRepBuilderAPI_Sewing> sewing;
        struct source_face {
            TopoDS_Face original;
            std::shared_ptr<BRepBuilderAPI_Copy> copier;
            TopoDS_Face copy;
        };
        std::vector<source_face> sources;
        TopoDS_Shape result;
        if (rest_faces.empty() || (caps.empty() && !closed_rest)) {
            result = work;
        } else {
            sewing = std::make_unique<BRepBuilderAPI_Sewing>(kSewTolerance, Standard_True, Standard_True, Standard_True, Standard_False);
            for (const TopoDS_Face &face : rest_faces) {
                source_face source;
                source.original = face;
                source.copier = std::make_shared<BRepBuilderAPI_Copy>(face, Standard_False, Standard_False);
                source.copy = TopoDS::Face(source.copier->Shape());
                sewing->Add(source.copy);
                sources.push_back(std::move(source));
            }
            for (const cap_made &cap : caps) {
                sewing->Add(cap.face);
            }
            sewing->Perform(progress_range(cancel));
            poll(cancel);
            std::vector<TopoDS_Shape> parts;
            collect(sewing->SewedShape(), parts);
            for (const TopoDS_Shape &found : parts) {
                // A lone face may close on itself (a sphere's one face): it is judged as the shell it makes.
                TopoDS_Shape part = found;
                if (found.ShapeType() == TopAbs_FACE) {
                    TopoDS_Shell shell;
                    builder.MakeShell(shell);
                    builder.Add(shell, found);
                    if (BRep_Tool::IsClosed(shell)) {
                        part = shell;
                    }
                }
                if (part.ShapeType() == TopAbs_SHELL && BRep_Tool::IsClosed(part)) {
                    const TopoDS_Shape solid = solidify_closed_shell(part);
                    GProp_GProps properties;
                    if (!solid.IsNull()) {
                        BRepGProp::VolumeProperties(solid, properties);
                    }
                    // A shell with no volume (two faces on top of each other) is no solid.
                    if (!solid.IsNull() && properties.Mass() > 1e-9) {
                        result_parts.push_back(solid);
                        continue;
                    }
                }
                result_parts.push_back(part);
            }
            if (result_parts.empty()) {
                throw user_error(kInvalidCapped);
            }
            if (result_parts.size() == 1) {
                result = result_parts[0];
            } else {
                TopoDS_Compound compound;
                builder.MakeCompound(compound);
                for (const TopoDS_Shape &part : result_parts) {
                    builder.Add(compound, part);
                }
                result = compound;
            }
        }
        poll(cancel);
        if (!BRepCheck_Analyzer(result).IsValid()) {
            throw user_error(kInvalidCapped);
        }

        history_builder face_history(result);
        const TopTools_IndexedMapOfShape out_faces = map_of(result, TopAbs_FACE);
        const TopTools_IndexedMapOfShape out_edges = map_of(result, TopAbs_EDGE);
        std::set<std::tuple<int, int, int>> edge_records;
        // Whatever kept its identity (the solids, an untouched sheet) keeps its names.
        for (int f = 1; f <= work_faces.Extent(); ++f) {
            face_history.add(work_faces(f), OCCT_FROM_FACE, 0, f);
        }
        for (int e = 1; e <= work_edges.Extent(); ++e) {
            const int out = out_edges.FindIndex(work_edges(e));
            if (out > 0) {
                edge_records.insert(std::make_tuple(out, 0, e));
            }
        }
        for (const source_face &source : sources) {
            const int f = work_faces.FindIndex(source.original);
            const TopoDS_Shape image = sewing->IsModified(source.copy) ? sewing->Modified(source.copy) : source.copy;
            face_history.add(image, OCCT_FROM_FACE, 0, f);
            const TopTools_IndexedMapOfShape face_edges = map_of(source.original, TopAbs_EDGE);
            for (int e = 1; e <= face_edges.Extent(); ++e) {
                const int original_index = work_edges.FindIndex(face_edges(e));
                const TopoDS_Shape copied = source.copier->ModifiedShape(face_edges(e));
                if (original_index <= 0 || copied.IsNull()) {
                    continue;
                }
                const TopoDS_Shape edge_image = sewing->IsModifiedSubShape(copied) ? sewing->ModifiedSubShape(copied) : copied;
                for (TopExp_Explorer it(edge_image, TopAbs_EDGE); it.More(); it.Next()) {
                    const int out = out_edges.FindIndex(it.Current());
                    if (out > 0) {
                        edge_records.insert(std::make_tuple(out, 0, original_index));
                    }
                }
            }
        }
        std::vector<occt_cap_loop_edge> cap_records;
        int cap_count = 0;
        if (sewing) {
            for (const cap_made &cap : caps) {
                const TopoDS_Shape image = sewing->IsModified(cap.face) ? sewing->Modified(cap.face) : cap.face;
                int found = 0;
                for (TopExp_Explorer it(image, TopAbs_FACE); it.More() && found == 0; it.Next()) {
                    found = out_faces.FindIndex(it.Current());
                }
                if (found == 0) {
                    continue;
                }
                ++cap_count;
                for (int edge : cap.source_edges) {
                    cap_records.push_back(occt_cap_loop_edge{found, edge});
                }
            }
        }
        std::vector<occt_edge_record> records;
        for (const auto &record : edge_records) {
            records.push_back(occt_edge_record{std::get<0>(record), std::get<1>(record), std::get<2>(record)});
        }
        face_history.move_into(history);
        edges->records = copy_out(records);
        edges->count = static_cast<int>(records.size());
        loops_out->records = copy_out(cap_records);
        loops_out->count = static_cast<int>(cap_records.size());
        *capped = cap_count;
        *not_flat = not_flat_count;
        return new occt_shape{result};
    });
}
