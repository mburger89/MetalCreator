#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepSweep_Revol.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopLoc_Location.hxx>
#include <gp_Ax1.hxx>
#include <gp_Trsf.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <BRepTools.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <BRep_Tool.hxx>
#include <GCPnts_TangentialDeflection.hxx>
#include <GProp_GProps.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <TopAbs_Orientation.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <vector>

using namespace cocct;

namespace {

constexpr const char *kLoopsMessage = "The curves must be one outer loop with holes inside it.";
constexpr const char *kOpenMessage = "The curve isn't closed, so it can't be filled.";

struct point2 {
    double x = 0;
    double y = 0;
};

/// One closed loop: its wire, its edges in wire order and its outline in plane coordinates.
struct loop {
    TopoDS_Wire wire;
    std::vector<TopoDS_Edge> edges;
    std::vector<point2> outline;
    double area = 0; // signed, counter-clockwise about the plane's normal is positive
};

point2 coordinates(const gp_Pnt &p, const gp_Pnt &origin, const gp_Vec &x, const gp_Vec &y) {
    const gp_Vec d(origin, p);
    return point2{d.Dot(x), d.Dot(y)};
}

loop read_loop(const occt_shape &shape, const gp_Pnt &origin, const gp_Vec &x, const gp_Vec &y) {
    if (shape.shape.IsNull() || shape.shape.ShapeType() != TopAbs_WIRE) {
        throw user_error(kLoopsMessage);
    }
    loop out;
    out.wire = TopoDS::Wire(shape.shape);
    if (!BRep_Tool::IsClosed(out.wire)) {
        throw user_error(kOpenMessage);
    }
    for (BRepTools_WireExplorer explorer(out.wire); explorer.More(); explorer.Next()) {
        const TopoDS_Edge edge = explorer.Current();
        out.edges.push_back(edge);
        BRepAdaptor_Curve curve(edge);
        GCPnts_TangentialDeflection sampler(curve, curve.FirstParameter(), curve.LastParameter(), 0.05, 1e-4, 2);
        std::vector<point2> points;
        for (int i = 1; i <= sampler.NbPoints(); ++i) {
            points.push_back(coordinates(sampler.Value(i), origin, x, y));
        }
        if (edge.Orientation() == TopAbs_REVERSED) {
            std::reverse(points.begin(), points.end());
        }
        if (points.size() < 2) {
            throw user_error(kLoopsMessage);
        }
        // The next edge starts where this one ends, so each outline point is kept once.
        out.outline.insert(out.outline.end(), points.begin(), points.end() - 1);
    }
    if (out.edges.empty() || out.outline.size() < 3) {
        throw user_error(kLoopsMessage);
    }
    double twice = 0;
    for (std::size_t i = 0; i < out.outline.size(); ++i) {
        const point2 &a = out.outline[i];
        const point2 &b = out.outline[(i + 1) % out.outline.size()];
        twice += a.x * b.y - b.x * a.y;
    }
    out.area = twice / 2;
    return out;
}

/// Ray casting. A point exactly on the outline may go either way; callers also have the checker.
bool contains(const std::vector<point2> &polygon, const point2 &p) {
    bool inside = false;
    for (std::size_t i = 0, j = polygon.size() - 1; i < polygon.size(); j = i++) {
        const point2 &a = polygon[i];
        const point2 &b = polygon[j];
        if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
            inside = !inside;
        }
    }
    return inside;
}

bool all_inside(const std::vector<point2> &polygon, const std::vector<point2> &points) {
    return std::all_of(points.begin(), points.end(), [&](const point2 &p) { return contains(polygon, p); });
}

/// The edges of a curve's wire in wire order, which is the order of its pieces.
std::vector<TopoDS_Edge> wire_edges(const TopoDS_Wire &wire) {
    std::vector<TopoDS_Edge> edges;
    for (BRepTools_WireExplorer explorer(wire); explorer.More(); explorer.Next()) {
        edges.push_back(explorer.Current());
    }
    return edges;
}

TopoDS_Wire curve_wire(const occt_shape *curve) {
    if (!curve || curve->shape.IsNull() || curve->shape.ShapeType() != TopAbs_WIRE) {
        throw user_error("This curve can't be used.");
    }
    return TopoDS::Wire(curve->shape);
}

void check_valid(const TopoDS_Shape &shape, const char *message) {
    if (shape.IsNull() || !BRepCheck_Analyzer(shape).IsValid()) {
        throw user_error(message);
    }
}

/// Names the faces made from each edge of `edges` (piece k), the edges of `first` as start and of `last` as end, and
/// the edges traced by an open curve's first and last vertices as rails 0 and 1.
void name_edges(boundary_table &table, const TopoDS_Shape &first, const TopoDS_Shape &last) {
    if (!first.IsNull()) {
        for (TopExp_Explorer it(first, TopAbs_EDGE); it.More(); it.Next()) {
            table.set(it.Current(), kBoundaryStart);
        }
    }
    if (!last.IsNull()) {
        for (TopExp_Explorer it(last, TopAbs_EDGE); it.More(); it.Next()) {
            table.set(it.Current(), kBoundaryEnd);
        }
    }
}

/// The generated edges of `vertex` that are real (not collapsed onto an axis).
void set_rails(boundary_table &table, const TopTools_ListOfShape &made, int which) {
    for (TopTools_ListOfShape::Iterator it(made); it.More(); it.Next()) {
        const TopoDS_Shape &item = it.Value();
        if (item.ShapeType() == TopAbs_EDGE && !BRep_Tool::Degenerated(TopoDS::Edge(item))) {
            table.set(item, kBoundaryRail, which);
        }
    }
}

} // namespace

extern "C" {

void occt_boundary_roles_free(occt_boundary_roles *roles) {
    if (roles) {
        std::free(roles->roles);
        *roles = occt_boundary_roles{};
    }
}

occt_shape *occt_planar_surface(const occt_shape *const *loops, int loop_count, const occt_plane *plane,
                                occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        if (!loops || loop_count < 1 || !plane) {
            throw user_error(kLoopsMessage);
        }
        const gp_Pnt origin(plane->origin[0], plane->origin[1], plane->origin[2]);
        const gp_Vec normal(plane->normal[0], plane->normal[1], plane->normal[2]);
        const gp_Vec x(plane->x_axis[0], plane->x_axis[1], plane->x_axis[2]);
        const gp_Vec y = normal.Crossed(x);
        std::vector<loop> read;
        for (int i = 0; i < loop_count; ++i) {
            read.push_back(read_loop(*loops[i], origin, x, y));
        }
        // The outer loop is the largest, and it must contain every other; holes keep their input order.
        std::size_t outer = 0;
        for (std::size_t i = 1; i < read.size(); ++i) {
            if (std::abs(read[i].area) > std::abs(read[outer].area)) {
                outer = i;
            }
        }
        std::vector<std::size_t> order{outer};
        for (std::size_t i = 0; i < read.size(); ++i) {
            if (i != outer) {
                order.push_back(i);
            }
        }
        const double outer_area = std::abs(read[outer].area);
        double expected = outer_area;
        for (std::size_t n = 1; n < order.size(); ++n) {
            const loop &hole = read[order[n]];
            if (!(std::abs(hole.area) > 1e-12) || !all_inside(read[outer].outline, hole.outline)) {
                throw user_error(kLoopsMessage);
            }
            for (std::size_t m = 1; m < order.size(); ++m) {
                if (m != n && all_inside(read[order[m]].outline, hole.outline)) {
                    throw user_error(kLoopsMessage);
                }
            }
            expected -= std::abs(hole.area);
        }

        BRepBuilderAPI_MakeFace maker(read[outer].wire, Standard_True);
        if (!maker.IsDone()) {
            throw user_error(kLoopsMessage);
        }
        // MakeFace deliberately adds pcurves to the edges of the shared Curve wires; the role table below relies on
        // those edges keeping their identity (IsSame) in the face.
        // MakeFace may have reversed the outer wire to suit the plane it found, so the holes are oriented against the
        // outer wire as the face holds it, not as it was given.
        const TopoDS_Wire built_outer = BRepTools::OuterWire(maker.Face());
        const bool outer_kept = built_outer.IsNull() || built_outer.Orientation() == read[outer].wire.Orientation();
        const bool outer_counter_clockwise = (read[outer].area > 0) == outer_kept;
        for (std::size_t n = 1; n < order.size(); ++n) {
            const loop &hole = read[order[n]];
            // OCCT needs each hole wire to wind against the outer one; reversing a wire keeps its edges.
            const bool same_way = (hole.area > 0) == outer_counter_clockwise;
            maker.Add(same_way ? TopoDS::Wire(hole.wire.Reversed()) : hole.wire);
            if (!maker.IsDone()) {
                throw user_error(kLoopsMessage);
            }
        }
        TopoDS_Face face = maker.Face();
        if (!BRepCheck_Analyzer(face).IsValid()) {
            throw user_error(kLoopsMessage);
        }
        GProp_GProps properties;
        BRepGProp::SurfaceProperties(face, properties);
        // The outlines are sampled polylines, so this only catches a hole that was added the wrong way round.
        if (!(std::abs(std::abs(properties.Mass()) - expected) <= 1e-3 * std::max(1.0, outer_area))) {
            throw user_error(kLoopsMessage);
        }
        // The face looks along the plane's normal, whichever way OCCT found its own plane.
        BRepAdaptor_Surface surface(face);
        gp_Dir face_normal = surface.Plane().Axis().Direction();
        if (face.Orientation() == TopAbs_REVERSED) {
            face_normal.Reverse();
        }
        if (gp_Vec(face_normal).Dot(normal) < 0) {
            face.Reverse();
        }

        history_builder records(face);
        records.add(face, OCCT_FROM_START_CAP, 0, 0);
        records.move_into(history);
        boundary_table table(face);
        for (std::size_t n = 0; n < order.size(); ++n) {
            const loop &item = read[order[n]];
            for (std::size_t k = 0; k < item.edges.size(); ++k) {
                table.set(item.edges[k], kBoundaryPiece, static_cast<int>(n), static_cast<int>(k));
            }
        }
        table.move_into(roles);
        return new occt_shape{face};
    });
}


occt_shape *occt_extrude_curve(const occt_shape *curve, const double direction[3], double distance, int symmetric,
                               occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        const TopoDS_Wire wire = curve_wire(curve);
        const gp_Vec vector(direction[0], direction[1], direction[2]);
        if (vector.Magnitude() < 1e-12) {
            throw user_error("The direction can't be zero.");
        }
        const gp_Vec unit = vector.Normalized();
        // A symmetric extrusion starts the curve distance behind its place. Moving the wire only sets a location, so
        // the caller's curve is untouched.
        TopoDS_Wire base = wire;
        if (symmetric) {
            gp_Trsf move;
            move.SetTranslation(unit.Reversed() * distance);
            base = TopoDS::Wire(wire.Moved(TopLoc_Location(move)));
        }
        BRepPrimAPI_MakePrism prism(base, unit * (symmetric ? 2 * distance : distance));
        prism.Build();
        if (!prism.IsDone()) {
            throw user_error("The curve can't be extruded.");
        }
        const TopoDS_Shape result = prism.Shape();
        check_valid(result, "The curve can't be extruded.");
        history_builder records(result);
        const std::vector<TopoDS_Edge> edges = wire_edges(base);
        for (std::size_t k = 0; k < edges.size(); ++k) {
            records.add_all(prism.Generated(edges[k]), OCCT_FROM_SEGMENT, 0, static_cast<int>(k));
        }
        records.move_into(history);
        boundary_table table(result);
        name_edges(table, prism.FirstShape(), prism.LastShape());
        if (!BRep_Tool::IsClosed(base) && !edges.empty()) {
            set_rails(table, prism.Generated(TopExp::FirstVertex(edges.front(), Standard_True)), 0);
            set_rails(table, prism.Generated(TopExp::LastVertex(edges.back(), Standard_True)), 1);
        }
        table.move_into(roles);
        return new occt_shape{result};
    });
}

occt_shape *occt_revolve_curve(const occt_shape *curve, const double axis_origin[3], const double axis_direction[3],
                               double angle, occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        const TopoDS_Wire wire = curve_wire(curve);
        if (!std::isfinite(angle) || angle <= 0 || angle > 2 * kPi + 1e-9) {
            throw user_error("The angle must be more than 0\u00B0 and at most 360\u00B0.");
        }
        const bool full = angle >= 2 * kPi - 1e-9;
        const gp_Ax1 axis(gp_Pnt(axis_origin[0], axis_origin[1], axis_origin[2]),
                          gp_Dir(axis_direction[0], axis_direction[1], axis_direction[2]));
        BRepPrimAPI_MakeRevol revol(wire, axis, full ? 2 * kPi : angle);
        revol.Build();
        if (!revol.IsDone()) {
            throw user_error("The curve can't be revolved.");
        }
        const TopoDS_Shape result = revol.Shape();
        check_valid(result, "The curve can't be revolved.");
        // A full revolution leaves Generated() empty for some pieces; the underlying sweep still knows them.
        const auto generated = [&](const TopoDS_Shape &piece) {
            TopTools_ListOfShape made = revol.Generated(piece);
            if (made.IsEmpty()) {
                const TopoDS_Shape swept = const_cast<BRepSweep_Revol &>(revol.Revol()).Shape(piece);
                if (!swept.IsNull()) {
                    made.Append(swept);
                }
            }
            return made;
        };
        history_builder records(result);
        const std::vector<TopoDS_Edge> edges = wire_edges(wire);
        for (std::size_t k = 0; k < edges.size(); ++k) {
            records.add_all(generated(edges[k]), OCCT_FROM_SEGMENT, 0, static_cast<int>(k));
        }
        records.move_into(history);
        boundary_table table(result);
        if (!full) {
            name_edges(table, revol.FirstShape(), revol.LastShape());
        }
        if (!BRep_Tool::IsClosed(wire) && !edges.empty()) {
            set_rails(table, generated(TopExp::FirstVertex(edges.front(), Standard_True)), 0);
            set_rails(table, generated(TopExp::LastVertex(edges.back(), Standard_True)), 1);
        }
        table.move_into(roles);
        return new occt_shape{result};
    });
}

occt_shape *occt_loft_curves(const occt_shape *const *sections, int count, int ruled, int closed,
                             occt_history *history, occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        if (!sections || count < 2) {
            throw user_error("A loft needs at least two sections.");
        }
        std::vector<TopoDS_Wire> wires;
        for (int i = 0; i < count; ++i) {
            wires.push_back(curve_wire(sections[i]));
        }
        const bool sections_closed = BRep_Tool::IsClosed(wires.front());
        BRepOffsetAPI_ThruSections loft(Standard_False, ruled ? Standard_True : Standard_False);
        for (const TopoDS_Wire &wire : wires) {
            loft.AddWire(wire);
        }
        if (closed) {
            loft.AddWire(wires.front());
        }
        loft.Build();
        if (!loft.IsDone()) {
            throw user_error("The sections can't be lofted.");
        }
        const TopoDS_Shape result = loft.Shape();
        check_valid(result, "The sections can't be lofted.");
        history_builder records(result);
        const std::vector<TopoDS_Edge> edges = wire_edges(wires.front());
        for (std::size_t k = 0; k < edges.size(); ++k) {
            records.add(loft.GeneratedFace(edges[k]), OCCT_FROM_SEGMENT, 0, static_cast<int>(k));
        }
        records.move_into(history);
        boundary_table table(result);
        if (!closed) {
            name_edges(table, loft.FirstShape(), loft.LastShape());
            name_edges(table, wires.front(), wires.back());
        }
        if (!sections_closed && !edges.empty()) {
            // The rails are the edges of one face that are neither section: the one reaching the first section's first
            // vertex is rail 0, the one reaching its last vertex rail 1.
            TopTools_IndexedDataMapOfShapeListOfShape owners;
            TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, owners);
            const gp_Pnt from = BRep_Tool::Pnt(TopExp::FirstVertex(edges.front(), Standard_True));
            const gp_Pnt to = BRep_Tool::Pnt(TopExp::LastVertex(edges.back(), Standard_True));
            const double tolerance = 1e-5;
            for (int i = 1; i <= owners.Extent(); ++i) {
                const TopoDS_Edge edge = TopoDS::Edge(owners.FindKey(i));
                if (BRep_Tool::Degenerated(edge) || owners(i).Extent() != 1) {
                    continue;
                }
                const gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(edge, Standard_True));
                const gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(edge, Standard_True));
                if (a.Distance(from) < tolerance || b.Distance(from) < tolerance) {
                    table.set(edge, kBoundaryRail, 0);
                } else if (a.Distance(to) < tolerance || b.Distance(to) < tolerance) {
                    table.set(edge, kBoundaryRail, 1);
                }
            }
        }
        table.move_into(roles);
        return new occt_shape{result};
    });
}

} // extern "C"
