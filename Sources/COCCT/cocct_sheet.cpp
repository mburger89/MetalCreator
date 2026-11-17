#include "cocct_sheet.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
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
        const bool outer_counter_clockwise = read[outer].area > 0;
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

} // extern "C"
