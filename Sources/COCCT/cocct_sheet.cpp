#include "cocct_sheet.hpp"

#include <BOPAlgo_CheckResult.hxx>
#include <BRepAlgoAPI_Check.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <BRepOffsetAPI_MakePipeShell.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <Geom_BSplineCurve.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepAdaptor_CompCurve.hxx>
#include <BRepFill_TypeOfContact.hxx>
#include <Bnd_Box.hxx>
#include <BRepBndLib.hxx>
#include <GCPnts_AbscissaPoint.hxx>
#include <gp_Quaternion.hxx>
#include <GeomAPI_PointsToBSpline.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <gp_Ax1.hxx>
#include <gp_Trsf.hxx>
#include <BRepBuilderAPI_TransitionMode.hxx>
#include <Law_Linear.hxx>
#include <TopTools_MapOfShape.hxx>
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
#include <limits>
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
        if (!std::isfinite(distance) || distance <= 0) {
            throw user_error("The distance must be greater than 0 mm.");
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
        // A smooth loft is one span; a ruled one has a span between each pair of sections (and back to the first when closed).
        const int span_count = ruled ? (closed ? count : count - 1) : 1;
        for (int span = 0; span < span_count; ++span) {
            const std::vector<TopoDS_Edge> span_edges = wire_edges(wires[span]);
            for (std::size_t k = 0; k < span_edges.size(); ++k) {
                records.add(loft.GeneratedFace(span_edges[k]), OCCT_FROM_SEGMENT, span, static_cast<int>(k));
            }
        }
        records.move_into(history);
        boundary_table table(result);
        TopTools_IndexedDataMapOfShapeListOfShape owners;
        TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, owners);
        const auto vertices_of = [](const TopoDS_Wire &wire) {
            std::vector<gp_Pnt> points;
            for (TopExp_Explorer it(wire, TopAbs_VERTEX); it.More(); it.Next()) {
                points.push_back(BRep_Tool::Pnt(TopoDS::Vertex(it.Current())));
            }
            return points;
        };
        const auto among = [](const std::vector<gp_Pnt> &points, const gp_Pnt &p) {
            return std::any_of(points.begin(), points.end(), [&](const gp_Pnt &q) { return q.Distance(p) < 1e-5; });
        };
        if (!closed) {
            name_edges(table, wires.front(), wires.back());
            // A smooth loft over three or more sections rebuilds its end edges, so they are also found as the free
            // edges that run between the vertices of one end section.
            const std::vector<gp_Pnt> start_points = vertices_of(wires.front());
            const std::vector<gp_Pnt> end_points = vertices_of(wires.back());
            for (int i = 1; i <= owners.Extent(); ++i) {
                const TopoDS_Edge edge = TopoDS::Edge(owners.FindKey(i));
                if (BRep_Tool::Degenerated(edge) || owners(i).Extent() != 1) {
                    continue;
                }
                const gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(edge, Standard_True));
                const gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(edge, Standard_True));
                if (among(start_points, a) && among(start_points, b)) {
                    table.set(edge, kBoundaryStart);
                } else if (among(end_points, a) && among(end_points, b)) {
                    table.set(edge, kBoundaryEnd);
                }
            }
        }
        if (!sections_closed) {
            // Rails: the single-face edges that join the sections' first vertices (rail 0) or last vertices (rail 1).
            std::vector<gp_Pnt> firsts;
            std::vector<gp_Pnt> lasts;
            for (const TopoDS_Wire &wire : wires) {
                const std::vector<TopoDS_Edge> wire_list = wire_edges(wire);
                if (wire_list.empty()) {
                    continue;
                }
                firsts.push_back(BRep_Tool::Pnt(TopExp::FirstVertex(wire_list.front(), Standard_True)));
                lasts.push_back(BRep_Tool::Pnt(TopExp::LastVertex(wire_list.back(), Standard_True)));
            }
            for (int i = 1; i <= owners.Extent(); ++i) {
                const TopoDS_Edge edge = TopoDS::Edge(owners.FindKey(i));
                if (BRep_Tool::Degenerated(edge) || owners(i).Extent() != 1) {
                    continue;
                }
                const gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(edge, Standard_True));
                const gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(edge, Standard_True));
                if (among(firsts, a) && among(firsts, b)) {
                    table.set(edge, kBoundaryRail, 0);
                } else if (among(lasts, a) && among(lasts, b)) {
                    table.set(edge, kBoundaryRail, 1);
                }
            }
        }
        table.move_into(roles);
        return new occt_shape{result};
    });
}

} // extern "C"

namespace {

constexpr const char *kSweepFailed = "The sweep couldn't be made along this path.";
constexpr const char *kSweepSelf = "The sweep runs into itself; shorten the path or shrink the profile.";

/// True when `points` has one within 1e-5 mm of `p`.
bool among_points(const std::vector<gp_Pnt> &points, const gp_Pnt &p) {
    return std::any_of(points.begin(), points.end(), [&](const gp_Pnt &q) { return q.Distance(p) < 1e-5; });
}

std::vector<gp_Pnt> vertex_points(const TopoDS_Shape &shape) {
    std::vector<gp_Pnt> points;
    if (!shape.IsNull()) {
        for (TopExp_Explorer it(shape, TopAbs_VERTEX); it.More(); it.Next()) {
            points.push_back(BRep_Tool::Pnt(TopoDS::Vertex(it.Current())));
        }
    }
    return points;
}

/// The one face of `shape` that the result holds (found by IsSame), or 0 when there isn't exactly one.
int single_face_index(const TopoDS_Shape &shape, const TopTools_IndexedMapOfShape &faces) {
    int found = 0;
    if (shape.IsNull()) {
        return 0;
    }
    for (TopExp_Explorer it(shape, TopAbs_FACE); it.More(); it.Next()) {
        const int index = faces.FindIndex(it.Current());
        if (index > 0) {
            if (found != 0 && found != index) {
                return 0;
            }
            found = index;
        }
    }
    return found;
}

/// Grows the chain of `candidates` that starts at `origin`: each edge that shares an end with the chain joins it.
/// Returns which candidates joined.
std::vector<bool> grow_chain(const std::vector<std::pair<gp_Pnt, gp_Pnt>> &candidates, const gp_Pnt &origin) {
    std::vector<gp_Pnt> frontier{origin};
    std::vector<bool> claimed(candidates.size(), false);
    for (bool grew = true; grew;) {
        grew = false;
        for (std::size_t i = 0; i < candidates.size(); ++i) {
            if (claimed[i]) {
                continue;
            }
            const bool touches_a = among_points(frontier, candidates[i].first);
            const bool touches_b = among_points(frontier, candidates[i].second);
            if (touches_a || touches_b) {
                claimed[i] = true;
                grew = true;
                frontier.push_back(touches_a ? candidates[i].second : candidates[i].first);
            }
        }
    }
    return claimed;
}

/// The auxiliary spine of a twisted sweep: the path offset by a direction that is carried along the path by the
/// smallest rotation (exact for a planar path) and turned by `twist_degrees` over its length, so a profile turns by
/// that much from end to end. The offset is 1 % of the path's size, and never more than half the tightest radius of
/// curvature sampled, so the offset curve never folds over itself.
TopoDS_Wire twist_spine(const TopoDS_Wire &path, double twist_degrees) {
    static const char *const failed = "The sweep couldn't be made along this path.";
    BRepAdaptor_CompCurve curve(path);
    const double first = curve.FirstParameter();
    const double last = curve.LastParameter();
    const double length = GCPnts_AbscissaPoint::Length(curve, first, last);
    if (length < 1e-9) {
        throw user_error(failed);
    }
    Bnd_Box box;
    BRepBndLib::Add(path, box);
    double x0 = 0, y0 = 0, z0 = 0, x1 = 0, y1 = 0, z1 = 0;
    box.Get(x0, y0, z0, x1, y1, z1);
    const double diagonal = gp_Pnt(x0, y0, z0).Distance(gp_Pnt(x1, y1, z1));
    const int count = static_cast<int>(std::ceil(64 * std::max(1.0, std::abs(twist_degrees) / 90))) + 1;
    // Pass one: the points, their tangents and the tightest bend, each point a fixed arc length after the last.
    std::vector<gp_Pnt> samples;
    std::vector<gp_Dir> axes;
    double tightest = std::numeric_limits<double>::infinity();
    double u = first;
    for (int i = 0; i < count; ++i) {
        if (i == count - 1) {
            u = last;
        } else if (i > 0) {
            GCPnts_AbscissaPoint at(curve, length / (count - 1), u);
            if (!at.IsDone()) {
                throw user_error(failed);
            }
            u = at.Parameter();
        }
        gp_Pnt point;
        gp_Vec tangent;
        gp_Vec acceleration;
        curve.D2(u, point, tangent, acceleration);
        if (tangent.Magnitude() < 1e-12) {
            throw user_error(failed);
        }
        const double bend = tangent.Crossed(acceleration).Magnitude() / std::pow(tangent.Magnitude(), 3);
        if (bend > 1e-12) {
            tightest = std::min(tightest, 1 / bend);
        }
        samples.push_back(point);
        axes.emplace_back(tangent);
    }
    const double offset = std::min(0.01 * diagonal, 0.5 * tightest);
    if (offset < 1e-3) {
        throw user_error("The path bends too tightly to twist along.");
    }
    TColgp_Array1OfPnt points(1, count);
    gp_Vec direction;
    for (int i = 0; i < count; ++i) {
        const gp_Dir axis = axes[static_cast<std::size_t>(i)];
        if (i == 0) {
            // The turn is measured from here, so the starting direction only has to stand across the path.
            gp_Vec reference(1, 0, 0);
            if (std::abs(axis.X()) > 0.9) {
                reference = gp_Vec(0, 1, 0);
            }
            direction = reference - gp_Vec(axis) * reference.Dot(gp_Vec(axis));
        } else {
            gp_Trsf carry;
            carry.SetRotation(gp_Quaternion(gp_Vec(axes[static_cast<std::size_t>(i - 1)]), gp_Vec(axis)));
            direction.Transform(carry);
            direction -= gp_Vec(axis) * direction.Dot(gp_Vec(axis));
            gp_Trsf turn;
            turn.SetRotation(gp_Ax1(gp_Pnt(0, 0, 0), axis), twist_degrees * (cocct::kPi / 180) / (count - 1));
            direction.Transform(turn);
        }
        direction.Normalize();
        points.SetValue(i + 1, samples[static_cast<std::size_t>(i)].Translated(direction * offset));
    }
    GeomAPI_PointsToBSpline fit(points, 3, 3);
    if (!fit.IsDone()) {
        throw user_error(failed);
    }
    return BRepBuilderAPI_MakeWire(BRepBuilderAPI_MakeEdge(fit.Curve()).Edge()).Wire();
}

/// True when the wire is straight to within a thousandth of its extent: it has no plane to turn in, and OCCT
/// crashes sweeping a straight edge along a rail. The deviation is measured from the line through the two farthest
/// samples (over every edge), which is within a factor of two of the best fit.
bool is_nearly_straight(const TopoDS_Wire &wire) {
    std::vector<gp_Pnt> points;
    for (const TopoDS_Edge &edge : wire_edges(wire)) {
        BRepAdaptor_Curve curve(edge);
        for (int i = 0; i <= 16; ++i) {
            points.push_back(curve.Value(curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * i / 16));
        }
    }
    if (points.size() < 2) {
        return true;
    }
    std::size_t farthest = 0;
    for (std::size_t i = 1; i < points.size(); ++i) {
        if (points.front().Distance(points[i]) > points.front().Distance(points[farthest])) {
            farthest = i;
        }
    }
    const gp_Vec axis(points.front(), points[farthest]);
    const double extent = axis.Magnitude();
    if (extent < 1e-9) {
        return true;
    }
    for (const gp_Pnt &point : points) {
        if (gp_Vec(points.front(), point).Crossed(axis).Magnitude() / extent > 1e-3 * extent) {
            return false;
        }
    }
    return true;
}

} // namespace

extern "C" {

occt_shape *occt_sweep_curves(const occt_shape *const *profiles, int count, const occt_shape *path, int mode,
                              const double binormal[3], double end_scale, int make_solid, const occt_shape *guide,
                              double twist_degrees, occt_history *history,
                              occt_boundary_roles *roles, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        occt_initialize();
        *history = occt_history{};
        *roles = occt_boundary_roles{};
        if (!profiles || count < 1) {
            throw user_error("A sweep needs at least one profile.");
        }
        if (!std::isfinite(end_scale) || end_scale <= 0) {
            throw user_error("The end scale must be greater than 0.");
        }
        if (end_scale != 1 && count != 1) {
            throw user_error("An end scale needs exactly one profile.");
        }
        if (!std::isfinite(twist_degrees) || std::abs(twist_degrees) > 3600) {
            throw user_error("The twist must be between −3,600° and 3,600°.");
        }
        if (mode < 0 || mode > 3) {
            throw user_error(kSweepFailed);
        }
        if (twist_degrees != 0 && mode >= 2) {
            throw user_error("Twist can't be combined with a rail or a guide surface.");
        }
        if (mode >= 2 && (!guide || guide->shape.IsNull())) {
            throw user_error(mode == 2 ? "Wire a rail curve." : "Wire a guide surface.");
        }
        const TopoDS_Wire spine = curve_wire(path);
        std::vector<TopoDS_Wire> wires;
        bool all_closed = true;
        for (int i = 0; i < count; ++i) {
            wires.push_back(curve_wire(profiles[i]));
            all_closed = all_closed && BRep_Tool::IsClosed(wires.back());
        }
        BRepOffsetAPI_MakePipeShell pipe(spine);
        // A sharp corner in the path is rounded rather than mitred, which would fold the inside over itself.
        pipe.SetTransitionMode(BRepBuilderAPI_RoundCorner);
        if (mode >= 2) {
            for (const TopoDS_Wire &wire : wires) {
                if (is_nearly_straight(wire)) {
                    throw user_error(mode == 2 ? "A rail sweep needs profiles that aren't straight lines."
                                               : "A guide sweep needs profiles that aren't straight lines.");
                }
            }
        }
        if (mode == 2) {
            const TopoDS_Wire rail = curve_wire(guide);
            for (const TopoDS_Wire &wire : wires) {
                BRepExtrema_DistShapeShape distance(rail, wire);
                if (!distance.IsDone() || distance.Value() > 1e-4) {
                    throw user_error("The rail must touch every profile.");
                }
            }
            pipe.SetMode(rail, Standard_True, BRepFill_ContactOnBorder);
        } else if (mode == 3) {
            pipe.SetMode(guide->shape);
        } else if (twist_degrees != 0) {
            pipe.SetMode(twist_spine(spine, twist_degrees), Standard_False, BRepFill_NoContact);
        } else if (mode == 0) {
            pipe.SetMode(Standard_True);
        } else {
            const gp_Vec direction(binormal[0], binormal[1], binormal[2]);
            if (direction.Magnitude() < 1e-12) {
                throw user_error("The direction can't be zero.");
            }
            pipe.SetMode(gp_Dir(direction));
        }
        for (const TopoDS_Wire &wire : wires) {
            if (end_scale != 1) {
                Handle(Law_Linear) law = new Law_Linear();
                law->Set(0, 1, 1, end_scale);
                pipe.SetLaw(wire, law, Standard_False, Standard_True);
            } else {
                pipe.Add(wire, Standard_False, Standard_True);
            }
        }
        pipe.Build();
        if (!pipe.IsDone()) {
            throw user_error(kSweepFailed);
        }
        const bool solid = make_solid && all_closed;
        if (solid && !pipe.MakeSolid()) {
            throw user_error(kSweepFailed);
        }
        const TopoDS_Shape result = pipe.Shape();
        if (result.IsNull()) {
            throw user_error(kSweepFailed);
        }
        BRepAlgoAPI_Check check(result, Standard_False, Standard_True);
        for (BOPAlgo_ListOfCheckResult::Iterator it(check.Result()); it.More(); it.Next()) {
            if (it.Value().GetCheckStatus() == BOPAlgo_SelfIntersect) {
                throw user_error(kSweepSelf);
            }
        }
        check_valid(result, kSweepFailed);

        history_builder records(result);
        // Only the first profile names the sides: the faces it generates run along the path, one per path span (a
        // spine edge, or the round corner between two), in order from the path's start. The other profiles shape
        // the same faces.
        const std::vector<TopoDS_Edge> piece_edges = wire_edges(wires.front());
        for (std::size_t k = 0; k < piece_edges.size(); ++k) {
            int span = 0;
            for (TopTools_ListOfShape::Iterator it(pipe.Generated(piece_edges[k])); it.More(); it.Next(), ++span) {
                records.add(it.Value(), OCCT_FROM_SEGMENT, span, static_cast<int>(k));
            }
        }
        const TopoDS_Shape first = pipe.FirstShape();
        const TopoDS_Shape last = pipe.LastShape();
        const bool closed_path = BRep_Tool::IsClosed(spine);
        if (solid && !closed_path) {
            const TopTools_IndexedMapOfShape faces = map_of(result, TopAbs_FACE);
            const int start_cap = single_face_index(first, faces);
            const int end_cap = single_face_index(last, faces);
            if (start_cap == 0 || end_cap == 0 || start_cap == end_cap) {
                throw user_error(kSweepFailed);
            }
            records.add(faces(start_cap), OCCT_FROM_START_CAP, 0, 0);
            records.add(faces(end_cap), OCCT_FROM_END_CAP, 0, 0);
        }
        records.move_into(history);

        boundary_table table(result);
        if (!solid && !closed_path) {
            name_edges(table, first, last);
        }
        if (!solid) {
            std::vector<gp_Pnt> start_points = vertex_points(first);
            std::vector<gp_Pnt> end_points = vertex_points(last);
            if (start_points.empty()) {
                start_points = vertex_points(wires.front());
            }
            TopTools_IndexedDataMapOfShapeListOfShape owners;
            TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, owners);
            std::vector<TopoDS_Edge> rail_edges;
            std::vector<std::pair<gp_Pnt, gp_Pnt>> rail_ends;
            for (int i = 1; i <= owners.Extent(); ++i) {
                const TopoDS_Edge edge = TopoDS::Edge(owners.FindKey(i));
                if (BRep_Tool::Degenerated(edge) || owners(i).Extent() != 1) {
                    continue;
                }
                const gp_Pnt a = BRep_Tool::Pnt(TopExp::FirstVertex(edge, Standard_True));
                const gp_Pnt b = BRep_Tool::Pnt(TopExp::LastVertex(edge, Standard_True));
                // A free edge whose ends are both on one end profile is that end, though IsSame lost it. A closed path
                // has no ends.
                if (!closed_path && !BRep_Tool::IsClosed(wires.front()) && among_points(start_points, a) &&
                    among_points(start_points, b)) {
                    table.set(edge, kBoundaryStart);
                } else if (!closed_path && !BRep_Tool::IsClosed(wires.front()) && among_points(end_points, a) &&
                           among_points(end_points, b)) {
                    table.set(edge, kBoundaryEnd);
                } else {
                    rail_edges.push_back(edge);
                    rail_ends.emplace_back(a, b);
                }
            }
            if (!BRep_Tool::IsClosed(wires.front()) && !piece_edges.empty()) {
                // Rail 0 is the chain of remaining free edges that grows from the start profile's first vertex (the
                // path of the profile's first point), rail 1 the chain from its last vertex; any other stays unnamed.
                gp_Pnt origin = BRep_Tool::Pnt(TopExp::FirstVertex(piece_edges.front(), Standard_True));
                gp_Pnt tip = BRep_Tool::Pnt(TopExp::LastVertex(piece_edges.back(), Standard_True));
                if (!first.IsNull() && first.ShapeType() == TopAbs_WIRE) {
                    const std::vector<TopoDS_Edge> placed = wire_edges(TopoDS::Wire(first));
                    if (!placed.empty()) {
                        origin = BRep_Tool::Pnt(TopExp::FirstVertex(placed.front(), Standard_True));
                        tip = BRep_Tool::Pnt(TopExp::LastVertex(placed.back(), Standard_True));
                    }
                }
                const std::vector<bool> zero = grow_chain(rail_ends, origin);
                const std::vector<bool> one = grow_chain(rail_ends, tip);
                for (std::size_t i = 0; i < rail_edges.size(); ++i) {
                    if (zero[i]) {
                        table.set(rail_edges[i], kBoundaryRail, 0);
                    } else if (one[i]) {
                        table.set(rail_edges[i], kBoundaryRail, 1);
                    }
                }
            }
        }
        table.move_into(roles);
        return new occt_shape{result};
    });
}

} // extern "C"
