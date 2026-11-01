#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_Curve.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>

using namespace cocct;

namespace cocct::continuity_detail {

constexpr double kCurvatureFloor = 1e-4;

struct side_sample {
    gp_Pnt point;
    gp_Vec normal;
    double curvature = 0;
    bool ok = false;
};

/// One face of the edge: its pcurve and surface adaptor, built once per call.
struct face_side {
    const TopoDS_Face &face;
    opencascade::handle<Geom2d_Curve> pcurve;
    BRepAdaptor_Surface surface;

    face_side(const TopoDS_Edge &edge, const TopoDS_Face &f) : face(f), surface(f, Standard_True) {
        double first = 0, last = 0;
        pcurve = BRep_Tool::CurveOnSurface(edge, f, first, last);
    }
};

/// The point, outward unit normal and normal curvature across the edge (the direction in the tangent plane perpendicular to
/// `tangent`) of the face at the edge parameter `t`.
side_sample sample_side(const face_side &side, double t, const gp_Vec &tangent) {
    side_sample out;
    if (side.pcurve.IsNull()) {
        return out;
    }
    const gp_Pnt2d uv = side.pcurve->Value(t);
    gp_Pnt point;
    gp_Vec su, sv, suu, svv, suv;
    side.surface.D2(uv.X(), uv.Y(), point, su, sv, suu, svv, suv);
    gp_Vec n = su.Crossed(sv);
    if (n.Magnitude() < 1e-12) {
        return out;
    }
    n.Normalize();
    if (side.face.Orientation() == TopAbs_REVERSED) {
        n.Reverse();
    }
    // Second fundamental form uses the surface's own normal direction, so keep its sign to fix the curvature's.
    gp_Vec own = su.Crossed(sv).Normalized();
    gp_Vec across = n.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        return out;
    }
    across.Normalize();
    const double e = su.Dot(su), f = su.Dot(sv), g = sv.Dot(sv);
    const double det = e * g - f * f;
    if (det < 1e-18) {
        return out;
    }
    const double a = (across.Dot(su) * g - across.Dot(sv) * f) / det;
    const double b = (across.Dot(sv) * e - across.Dot(su) * f) / det;
    const double l = own.Dot(suu), m = own.Dot(suv), nn = own.Dot(svv);
    const double denom = e * a * a + 2 * f * a * b + g * b * b;
    if (denom < 1e-18) {
        return out;
    }
    double curvature = (l * a * a + 2 * m * a * b + nn * b * b) / denom;
    // Curvature measured against the outward normal.
    if (own.Dot(n) < 0) {
        curvature = -curvature;
    }
    out.point = point;
    out.normal = n;
    out.curvature = curvature;
    out.ok = true;
    return out;
}

} // namespace cocct::continuity_detail

namespace cocct {

occt_edge_continuity edge_continuity(const TopoDS_Edge &edge, const TopoDS_Face &face_a, const TopoDS_Face &face_b, int samples) {
    using namespace continuity_detail;
    occt_edge_continuity out{};
    BRepAdaptor_Curve curve(edge);
    const double lo = curve.FirstParameter(), hi = curve.LastParameter();
    const double margin = 0.01 * (hi - lo);
    const face_side side_a(edge, face_a), side_b(edge, face_b);
    double position = 0, angle = 0, relative = 0, absolute = 0;
    int used = 0;
    for (int i = 0; i < samples; ++i) {
        const double t = lo + margin + (hi - lo - 2 * margin) * (i + 0.5) / samples;
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        if (tangent.Magnitude() < 1e-12) {
            continue;
        }
        tangent.Normalize();
        const side_sample s1 = sample_side(side_a, t, tangent);
        const side_sample s2 = sample_side(side_b, t, tangent);
        if (!s1.ok || !s2.ok) {
            continue;
        }
        ++used;
        position = std::max(position, std::max(s1.point.Distance(s2.point), std::max(s1.point.Distance(p), s2.point.Distance(p))));
        angle = std::max(angle, std::atan2(s1.normal.Crossed(s2.normal).Magnitude(), s1.normal.Dot(s2.normal)));
        const double k1 = s1.curvature, k2 = s2.curvature;
        const double diff = std::fabs(k1 - k2);
        const double larger = std::max(std::fabs(k1), std::fabs(k2));
        // A sample passes when diff <= max(floor, 1% of the larger): the relative gap counts only samples over the floor, so the
        // two maxima OR the same way the per-sample test does.
        absolute = std::max(absolute, diff);
        if (diff > kCurvatureFloor) {
            relative = std::max(relative, diff / larger);
        }
    }
    if (used == 0) {
        throw user_error("The surfaces along this edge can't be compared.");
    }
    out.position_gap = position;
    out.angle_gap = angle;
    out.curvature_gap = relative;
    out.absolute_curvature_gap = absolute;
    return out;
}

} // namespace cocct

extern "C" {

int occt_edge_continuity_of(const occt_shape *shape, int edge_index, occt_edge_continuity *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_edge_continuity{};
        const TopTools_IndexedMapOfShape edges = map_of(shape->shape, TopAbs_EDGE);
        if (edge_index < 1 || edge_index > edges.Extent()) {
            throw user_error("That edge no longer exists.");
        }
        const TopoDS_Edge edge = TopoDS::Edge(edges.FindKey(edge_index));
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(shape->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        const std::vector<TopoDS_Face> faces = distinct_faces(edge, edge_faces);
        if (faces.size() != 2) {
            throw user_error("This edge doesn't join two faces.");
        }
        *out = edge_continuity(edge, faces[0], faces[1], 32);
        return 1;
    });
}

} // extern "C"
