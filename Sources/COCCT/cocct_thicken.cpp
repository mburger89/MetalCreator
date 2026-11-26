// Thickening a sheet into a solid (NS-5, Task 5; rulings R3 names, R7 build, R8 validity, R15 cancellation).
//
// The sheet is copied, offset once or twice (Front: the sheet and +d, Back: -d and the sheet, Both: -d/2 and +d/2), and a ruled wall
// joins each pair of matching boundary edges. Every face is sewn into closed shells, each made a solid. A sheet with no free edges
// (a closed bare shell) has no walls: its two shells make one solid with a void.

#include "cocct_offset.hpp"
#include "cocct_progress.hpp"
#include "cocct_sheet.hpp"
#include "cocct_solids.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepFill.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRep_Builder.hxx>
#include <GProp_GProps.hxx>
#include <GeomAbs_CurveType.hxx>
#include <Geom_ConicalSurface.hxx>
#include <Geom_CylindricalSurface.hxx>
#include <Geom_Plane.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Iterator.hxx>
#include <TopoDS_Shell.hxx>
#include <gp_Ax3.hxx>
#include <gp_Circ.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <map>
#include <vector>

using namespace cocct;

namespace {

constexpr double kMinimumSewing = 1e-6;

/// One side of the solid: an image of every source face and, per source boundary edge (1-based), the edge on this side.
struct layer {
    std::vector<TopoDS_Shape> faces;
    std::map<int, TopoDS_Edge> edges;
};

/// The ends of `edge` as its orientation runs them.
void oriented_ends(const TopoDS_Edge &edge, gp_Pnt &start, gp_Pnt &end) {
    BRepAdaptor_Curve curve(edge);
    start = curve.Value(curve.FirstParameter());
    end = curve.Value(curve.LastParameter());
    if (edge.Orientation() == TopAbs_REVERSED) {
        std::swap(start, end);
    }
}

/// The angle of `p` about the axis of `frame`, from its X direction.
double angle_about(const gp_Ax3 &frame, const gp_Pnt &p) {
    const gp_Vec from(frame.Location(), p);
    return std::atan2(from.Dot(gp_Vec(frame.YDirection())), from.Dot(gp_Vec(frame.XDirection())));
}

/// The angles an arc edge covers about `frame`'s axis, `first` and `last` with last >= first (a circle's parametrisation is uniform, so the
/// middle point is half way). False for a curve that isn't a circle about that axis.
bool arc_span(const TopoDS_Edge &edge, const gp_Ax3 &frame, double &first, double &last) {
    BRepAdaptor_Curve curve(edge);
    const double t0 = curve.FirstParameter();
    const double t1 = curve.LastParameter();
    const double start = angle_about(frame, curve.Value(t0));
    double half = angle_about(frame, curve.Value(0.5 * (t0 + t1))) - start;
    while (half > kPi) {
        half -= 2 * kPi;
    }
    while (half <= -kPi) {
        half += 2 * kPi;
    }
    const bool full = std::abs((t1 - t0) - 2 * kPi) < 1e-9;
    if (full) {
        first = start;
        last = start + 2 * kPi;
        return true;
    }
    const double end = start + 2 * half;
    first = std::min(start, end);
    last = std::max(start, end);
    return last - first > 1e-9;
}

/// R1: the wall between two coaxial circle arcs on an analytic surface: a cylinder for equal radii in different planes, a plane (an
/// annular sector) for arcs in one plane, otherwise a cone. Null when the pair isn't that (or won't build): the ruled wall takes it.
TopoDS_Face analytic_wall(const TopoDS_Edge &lower, const TopoDS_Edge &upper) {
    BRepAdaptor_Curve a(lower);
    BRepAdaptor_Curve b(upper);
    if (a.GetType() != GeomAbs_Circle || b.GetType() != GeomAbs_Circle) {
        return TopoDS_Face();
    }
    const gp_Circ ca = a.Circle();
    const gp_Circ cb = b.Circle();
    const gp_Vec za(ca.Axis().Direction());
    const gp_Vec zb(cb.Axis().Direction());
    if (za.Crossed(zb).Magnitude() > 1e-9) {
        return TopoDS_Face();
    }
    const gp_Vec offset(ca.Location(), cb.Location());
    if (offset.Crossed(za).Magnitude() > 1e-7) {
        return TopoDS_Face();
    }
    const gp_Ax3 frame(ca.Location(), ca.Axis().Direction(), ca.XAxis().Direction());
    const double ra = ca.Radius();
    const double rb = cb.Radius();
    const double height = offset.Dot(za);
    double a0, a1, b0, b1;
    if (!arc_span(lower, frame, a0, a1) || !arc_span(upper, frame, b0, b1) || std::abs(a0 - b0) > 1e-6 || std::abs(a1 - b1) > 1e-6) {
        return TopoDS_Face();
    }
    const bool full = std::abs((a1 - a0) - 2 * kPi) < 1e-9;
    const bool coplanar = std::abs(height) < 1e-7;
    const bool equal = std::abs(ra - rb) < 1e-7;
    constexpr double tolerance = 1e-7;
    if (coplanar && equal) {
        return TopoDS_Face();
    }
    if (!coplanar) {
        Handle(Geom_Surface) surface;
        double v0 = 0;
        double v1 = height;
        if (equal) {
            surface = new Geom_CylindricalSurface(frame, ra);
        } else {
            const double angle = std::atan((rb - ra) / height);
            if (!(std::abs(angle) > 1e-6) || !(std::abs(angle) < kPi / 2 - 1e-6)) {
                return TopoDS_Face();
            }
            surface = new Geom_ConicalSurface(frame, angle, ra);
            v1 = height / std::cos(angle);
        }
        BRepBuilderAPI_MakeFace face(surface, a0, a1, std::min(v0, v1), std::max(v0, v1), tolerance);
        return face.IsDone() ? face.Face() : TopoDS_Face();
    }
    // One plane: the larger arc outside, the smaller inside; an arc has two radial ends.
    const Handle(Geom_Plane) plane = new Geom_Plane(gp_Pln(frame));
    auto arc_edge = [&](double radius) {
        return BRepBuilderAPI_MakeEdge(gp_Circ(frame.Ax2(), radius), a0, a1).Edge();
    };
    const double outer = std::max(ra, rb);
    const double inner = std::min(ra, rb);
    auto point = [&](double radius, double angle) {
        return gp_Pnt(frame.Location().XYZ() + radius * (std::cos(angle) * frame.XDirection().XYZ() + std::sin(angle) * frame.YDirection().XYZ()));
    };
    BRepBuilderAPI_MakeWire wire;
    TopoDS_Face face;
    if (full) {
        wire.Add(arc_edge(outer));
        if (!wire.IsDone()) {
            return TopoDS_Face();
        }
        BRepBuilderAPI_MakeFace made(plane, wire.Wire(), Standard_True);
        if (!made.IsDone()) {
            return TopoDS_Face();
        }
        BRepBuilderAPI_MakeWire hole;
        hole.Add(arc_edge(inner));
        if (!hole.IsDone()) {
            return TopoDS_Face();
        }
        made.Add(TopoDS::Wire(hole.Wire().Reversed()));
        face = made.Face();
    } else {
        wire.Add(arc_edge(outer));
        wire.Add(BRepBuilderAPI_MakeEdge(point(outer, a1), point(inner, a1)).Edge());
        wire.Add(TopoDS::Edge(arc_edge(inner).Reversed()));
        wire.Add(BRepBuilderAPI_MakeEdge(point(inner, a0), point(outer, a0)).Edge());
        if (!wire.IsDone()) {
            return TopoDS_Face();
        }
        BRepBuilderAPI_MakeFace made(plane, wire.Wire(), Standard_True);
        if (!made.IsDone()) {
            return TopoDS_Face();
        }
        face = made.Face();
    }
    for (TopExp_Explorer it(face, TopAbs_EDGE); it.More(); it.Next()) {
        BRepLib::BuildPCurveForEdgeOnPlane(TopoDS::Edge(it.Current()), face);
    }
    return face;
}

/// The ruled wall between two edges, the second turned when it runs against the first.
TopoDS_Face wall_between(const TopoDS_Edge &lower, const TopoDS_Edge &upper) {
    gp_Pnt a0, a1, b0, b1;
    oriented_ends(lower, a0, a1);
    oriented_ends(upper, b0, b1);
    const bool same = a0.Distance(b0) + a1.Distance(b1) <= a0.Distance(b1) + a1.Distance(b0);
    if (!same) {
        std::swap(b0, b1);
    }
    const TopoDS_Face analytic = analytic_wall(lower, upper);
    if (!analytic.IsNull()) {
        return analytic;
    }
    // Two straight edges in one plane make a plane (a ruled B-spline wall would be accepted by nothing downstream, a fillet included).
    if (BRepAdaptor_Curve(lower).GetType() == GeomAbs_Line && BRepAdaptor_Curve(upper).GetType() == GeomAbs_Line &&
        a0.Distance(a1) > 1e-6 && a0.Distance(b0) > 1e-6 && a1.Distance(b1) > 1e-6) {
        const gp_Vec along(a0, a1);
        const gp_Vec across(a0, b0);
        const gp_Vec normal = along.Crossed(across);
        if (normal.Magnitude() > 1e-9 * along.Magnitude() * across.Magnitude()) {
            const gp_Vec unit = normal.Normalized();
            const double flat = std::abs(gp_Vec(a0, a1).Dot(unit)) + std::abs(gp_Vec(a0, b1).Dot(unit));
            if (flat < 1e-7 && b0.Distance(b1) > 1e-6) {
                BRepBuilderAPI_MakePolygon polygon(a0, a1, b1, b0, Standard_True);
                if (polygon.IsDone()) {
                    BRepBuilderAPI_MakeFace face(polygon.Wire(), Standard_True);
                    if (face.IsDone()) {
                        return face.Face();
                    }
                }
            }
        }
    }
    return BRepFill::Face(lower, same ? upper : TopoDS::Edge(upper.Reversed()));
}

double largest_tolerance(const TopoDS_Shape &shape) {
    double largest = 0;
    for (TopExp_Explorer it(shape, TopAbs_EDGE); it.More(); it.Next()) {
        largest = std::max(largest, BRep_Tool::Tolerance(TopoDS::Edge(it.Current())));
    }
    for (TopExp_Explorer it(shape, TopAbs_VERTEX); it.More(); it.Next()) {
        largest = std::max(largest, BRep_Tool::Tolerance(TopoDS::Vertex(it.Current())));
    }
    return largest;
}

double volume_of(const TopoDS_Shape &shape) {
    GProp_GProps properties;
    BRepGProp::VolumeProperties(shape, properties);
    return properties.Mass();
}

void collect(const TopoDS_Shape &shape, std::vector<TopoDS_Shape> &parts) {
    if (shape.IsNull()) {
        return;
    }
    if (shape.ShapeType() == TopAbs_COMPOUND || shape.ShapeType() == TopAbs_COMPSOLID) {
        for (TopoDS_Iterator it(shape); it.More(); it.Next()) {
            collect(it.Value(), parts);
        }
    } else {
        parts.push_back(shape);
    }
}

TopoDS_Shape one_shell(const TopoDS_Shape &shape) {
    std::vector<TopoDS_Shape> parts;
    collect(shape, parts);
    return parts.size() == 1 && parts[0].ShapeType() == TopAbs_SHELL ? parts[0] : TopoDS_Shape();
}

} // namespace

occt_shape *occt_thicken(const occt_shape *sheet, double distance, int side, const occt_cancel *cancel, occt_history *history,
                         occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        if (!sheet || sheet->shape.IsNull()) {
            throw user_error("This surface can't be used.");
        }
        if (!(distance > 0) || !std::isfinite(distance)) {
            throw user_error("The distance must be greater than 0.");
        }
        poll(cancel);
        // Work on a copy: sewing must never touch the input. The copy keeps the input's face and edge order.
        const TopoDS_Shape work = BRepBuilderAPI_Copy(sheet->shape, Standard_True, Standard_False).Shape();
        const TopTools_IndexedMapOfShape faces = map_of(work, TopAbs_FACE);
        const TopTools_IndexedMapOfShape edges = map_of(work, TopAbs_EDGE);

        layer lower, upper;
        auto sheet_layer = [&](const offset_result &partner, layer &out) {
            for (int f = 1; f <= faces.Extent(); ++f) {
                out.faces.push_back(faces(f));
            }
            for (const offset_edge_pair &pair : partner.pairs) {
                out.edges[pair.source_index] = TopoDS::Edge(edges(pair.source_index));
            }
        };
        auto offset_layer = [&](const offset_result &made, layer &out) {
            out.faces = made.images;
            for (const offset_edge_pair &pair : made.pairs) {
                out.edges[pair.source_index] = pair.image;
            }
        };
        if (side == 0) {
            const offset_result up = offset_shell(work, distance, cancel);
            sheet_layer(up, lower);
            offset_layer(up, upper);
        } else if (side == 1) {
            const offset_result down = offset_shell(work, -distance, cancel);
            offset_layer(down, lower);
            sheet_layer(down, upper);
        } else {
            const offset_result down = offset_shell(work, -0.5 * distance, cancel);
            const offset_result up = offset_shell(work, 0.5 * distance, cancel);
            offset_layer(down, lower);
            offset_layer(up, upper);
        }
        poll(cancel);

        // The walls: one ruled face per source boundary edge that both sides have.
        std::vector<std::pair<int, TopoDS_Face>> walls;
        for (const auto &entry : lower.edges) {
            const auto other = upper.edges.find(entry.first);
            if (other == upper.edges.end()) {
                throw user_error(kThickenOpenEdges);
            }
            const TopoDS_Face wall = wall_between(entry.second, other->second);
            if (wall.IsNull()) {
                throw user_error(kOffsetFailed);
            }
            walls.emplace_back(entry.first, wall);
        }

        struct piece {
            TopoDS_Shape face;
            int kind;
            int index; // 1-based source face for a side face, source edge for a wall
        };
        std::vector<piece> pieces;
        for (size_t f = 0; f < lower.faces.size(); ++f) {
            pieces.push_back({lower.faces[f], OCCT_FROM_START_CAP, int(f) + 1});
            pieces.push_back({upper.faces[f], OCCT_FROM_END_CAP, int(f) + 1});
        }

        // Split the source into connected pieces (faces joined by shared edges). A piece with no wall edge is a closed bare shell:
        // its two sides are an outer shell and a void, one solid. The open pieces are sewn together with their walls.
        const int faceCount = faces.Extent();
        std::vector<int> parent(faceCount + 1);
        for (int f = 0; f <= faceCount; ++f) {
            parent[f] = f;
        }
        auto root = [&](int f) {
            while (parent[f] != f) {
                parent[f] = parent[parent[f]];
                f = parent[f];
            }
            return f;
        };
        std::map<int, int> edgeOwner;
        for (int f = 1; f <= faceCount; ++f) {
            for (TopExp_Explorer it(faces(f), TopAbs_EDGE); it.More(); it.Next()) {
                const int e = edges.FindIndex(it.Current());
                const auto found = edgeOwner.find(e);
                if (found == edgeOwner.end()) {
                    edgeOwner[e] = f;
                } else {
                    parent[root(f)] = root(found->second);
                }
            }
        }
        std::map<int, bool> componentOpen;
        for (const auto &wall : walls) {
            const auto owner = edgeOwner.find(wall.first);
            if (owner != edgeOwner.end()) {
                componentOpen[root(owner->second)] = true;
            }
        }
        auto isOpenFace = [&](int f) { return componentOpen.count(root(f)) != 0; };

        struct record_request {
            TopoDS_Shape face;
            int kind;
            int index;
        };
        std::vector<record_request> requests;
        std::vector<TopoDS_Shape> solids;

        // Closed bare shells, each on its own.
        std::map<int, std::vector<int>> closedGroups;
        for (int f = 1; f <= faceCount; ++f) {
            if (!isOpenFace(f)) {
                closedGroups[root(f)].push_back(f);
            }
        }
        for (const auto &group : closedGroups) {
            BRep_Builder make;
            TopoDS_Shell low, high;
            make.MakeShell(low);
            make.MakeShell(high);
            for (int f : group.second) {
                make.Add(low, lower.faces[f - 1]);
                make.Add(high, upper.faces[f - 1]);
            }
            const TopoDS_Shape solid = solid_with_void(low, high);
            if (solid.IsNull()) {
                throw user_error(kOffsetFailed);
            }
            solids.push_back(solid);
            for (int f : group.second) {
                requests.push_back({lower.faces[f - 1], OCCT_FROM_FACE, f});
                requests.push_back({lower.faces[f - 1], OCCT_FROM_START_CAP, 0});
                requests.push_back({upper.faces[f - 1], OCCT_FROM_FACE, f});
                requests.push_back({upper.faces[f - 1], OCCT_FROM_END_CAP, 0});
            }
        }

        // Open pieces: sew their faces and walls.
        std::vector<piece> openPieces;
        for (const piece &p : pieces) {
            if (isOpenFace(p.index)) {
                openPieces.push_back(p);
            }
        }
        if (!openPieces.empty()) {
            double tolerance = kMinimumSewing;
            for (const piece &p : openPieces) {
                tolerance = std::max(tolerance, 2 * largest_tolerance(p.face));
            }
            for (const auto &wall : walls) {
                tolerance = std::max(tolerance, 2 * largest_tolerance(wall.second));
            }
            BRepBuilderAPI_Sewing sewing(tolerance, Standard_True, Standard_True, Standard_True, Standard_False);
            for (const piece &p : openPieces) {
                sewing.Add(p.face);
            }
            for (const auto &wall : walls) {
                sewing.Add(wall.second);
            }
            sewing.Perform(progress_range(cancel));
            poll(cancel);
            std::vector<TopoDS_Shape> parts;
            collect(sewing.SewedShape(), parts);
            for (const TopoDS_Shape &part : parts) {
                if (part.ShapeType() != TopAbs_SHELL || !BRep_Tool::IsClosed(part)) {
                    throw user_error(kOffsetFailed);
                }
                const TopoDS_Shape solid = solidify_closed_shell(part);
                if (solid.IsNull()) {
                    throw user_error(kOffsetFailed);
                }
                solids.push_back(solid);
            }
            auto image_of = [&](const TopoDS_Shape &face) -> TopoDS_Shape {
                return sewing.IsModified(face) ? sewing.Modified(face) : face;
            };
            for (const piece &p : openPieces) {
                const TopoDS_Shape image = image_of(p.face);
                requests.push_back({image, OCCT_FROM_FACE, p.index});
                requests.push_back({image, p.kind, 0});
            }
            for (const auto &wall : walls) {
                requests.push_back({image_of(wall.second), OCCT_FROM_EDGE, wall.first});
            }
        }
        if (solids.empty()) {
            throw user_error(kOffsetFailed);
        }
        TopoDS_Shape result;
        if (solids.size() == 1) {
            result = solids[0];
        } else {
            BRep_Builder make;
            TopoDS_Compound compound;
            make.MakeCompound(compound);
            for (const TopoDS_Shape &solid : solids) {
                make.Add(compound, solid);
            }
            result = compound;
        }
        history_builder faces_of(result);
        for (const record_request &r : requests) {
            faces_of.add(r.face, r.kind, 0, r.index);
        }
        const std::vector<occt_history_record> records = faces_of.records();
        poll(cancel);
        if (!BRepCheck_Analyzer(result).IsValid() || largest_tolerance(result) > accepted_tolerance(sheet->shape)) {
            throw user_error(kOffsetFailed);
        }
        for (TopExp_Explorer it(result, TopAbs_SOLID); it.More(); it.Next()) {
            if (!(volume_of(it.Current()) > 0)) {
                throw user_error(kOffsetFailed);
            }
        }
        history->records = copy_out(records);
        history->count = static_cast<int>(records.size());
        return new occt_shape{result};
    });
}
