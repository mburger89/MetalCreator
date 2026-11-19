#include "cocct_continuity.hpp"
#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRep_Tool.hxx>
#include <Geom2d_Curve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <BRepClass_FaceClassifier.hxx>
#include <BRepTools.hxx>
#include <Geom_Surface.hxx>
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

/// The point, outward unit normal and normal curvature across the edge (the direction in the tangent plane perpendicular to
/// `tangent`) of the face at the edge parameter `t`.
side_sample sample_side_at(const face_side &side, const gp_Pnt2d &uv, const gp_Vec &tangent) {
    side_sample out;
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

/// `sample_side_at` at the edge's own pcurve parameter `t`.
side_sample sample_side(const face_side &side, double t, const gp_Vec &tangent) {
    if (side.pcurve.IsNull()) {
        return side_sample{};
    }
    return sample_side_at(side, side.pcurve->Value(t), tangent);
}

constexpr double kProjectionLimit = 1.0;

/// `u` and `v` brought into the face's own parameter range on a periodic surface, so the classifier sees them where the face is.
void into_face_range(const TopoDS_Face &face, const opencascade::handle<Geom_Surface> &surface, double &u, double &v) {
    double u_min = 0, u_max = 0, v_min = 0, v_max = 0;
    BRepTools::UVBounds(face, u_min, u_max, v_min, v_max);
    if (surface->IsUPeriodic()) {
        const double period = surface->UPeriod();
        u = u_min + std::fmod(std::fmod(u - u_min, period) + period, period);
    }
    if (surface->IsVPeriodic()) {
        const double period = surface->VPeriod();
        v = v_min + std::fmod(std::fmod(v - v_min, period) + period, period);
    }
}

/// Side B of a two-body comparison: the face's uv at the point nearest to `p`, `ok` false when that is over 1 mm away.
side_sample sample_projected(const face_side &side, const opencascade::handle<Geom_Surface> &surface, const gp_Pnt &p,
                             const gp_Vec &tangent) {
    GeomAPI_ProjectPointOnSurf projection(p, surface);
    if (projection.NbPoints() < 1 || projection.LowerDistance() > kProjectionLimit) {
        return side_sample{};
    }
    double u = 0, v = 0;
    projection.LowerDistanceParameters(u, v);
    into_face_range(side.face, surface, u, v);
    // A point on the surface but off the trimmed face (beyond its boundary) is no sample.
    if (BRepClass_FaceClassifier(side.face, gp_Pnt2d(u, v), 1e-6).State() == TopAbs_OUT) {
        return side_sample{};
    }
    return sample_side_at(side, gp_Pnt2d(u, v), tangent);
}

constexpr double kSideStep = 0.01;

/// Whether `q`, projected onto the face's surface, lies strictly inside the trimmed face.
bool strictly_inside(const TopoDS_Face &face, const opencascade::handle<Geom_Surface> &surface, const gp_Pnt &q) {
    GeomAPI_ProjectPointOnSurf projection(q, surface);
    if (projection.NbPoints() < 1) {
        return false;
    }
    double u = 0, v = 0;
    projection.LowerDistanceParameters(u, v);
    into_face_range(face, surface, u, v);
    return BRepClass_FaceClassifier(face, gp_Pnt2d(u, v), 1e-6).State() == TopAbs_IN;
}

inward inward_direction(const TopoDS_Face &face, const opencascade::handle<Geom_Surface> &surface, const gp_Pnt &p,
                        const gp_Vec &normal, const gp_Vec &tangent) {
    inward out;
    gp_Vec across = normal.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        return out;
    }
    across.Normalize();
    const bool plus = strictly_inside(face, surface, p.Translated(across * kSideStep));
    const bool minus = strictly_inside(face, surface, p.Translated(across.Reversed() * kSideStep));
    out.found = plus || minus;
    out.both = plus && minus;
    out.direction = plus ? across : across.Reversed();
    return out;
}

} // namespace cocct::continuity_detail

namespace cocct {

namespace {

occt_edge_continuity grade_samples(const TopoDS_Edge &edge, const TopoDS_Face &face_a, const TopoDS_Face &face_b, int samples,
                                   bool project_b) {
    using namespace continuity_detail;
    occt_edge_continuity out{};
    BRepAdaptor_Curve curve(edge);
    const double lo = curve.FirstParameter(), hi = curve.LastParameter();
    const double margin = 0.01 * (hi - lo);
    const face_side side_a(edge, face_a);
    const face_side side_b = project_b ? face_side(face_b) : face_side(edge, face_b);
    const opencascade::handle<Geom_Surface> surface_a = project_b ? BRep_Tool::Surface(face_a) : opencascade::handle<Geom_Surface>();
    const opencascade::handle<Geom_Surface> surface_b = project_b ? BRep_Tool::Surface(face_b) : opencascade::handle<Geom_Surface>();
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
        side_sample s2 = project_b ? sample_projected(side_b, surface_b, p, tangent) : sample_side(side_b, t, tangent);
        if (!s1.ok || !s2.ok) {
            continue;
        }
        double sample_angle = 0;
        if (project_b) {
            // Two bodies have no shared orientation: compare the normals up to sign, the curvature following the flip.
            if (s1.normal.Dot(s2.normal) < 0) {
                s2.normal.Reverse();
                s2.curvature = -s2.curvature;
            }
            // Which way each face runs from the edge: a smooth join leaves A's inward direction continuing into B, a fold
            // returns on A's side. The deviation is the angle between A's continuation and B's inward direction.
            const inward a_in = inward_direction(face_a, surface_a, p, s1.normal, tangent);
            const inward b_in = inward_direction(face_b, surface_b, s2.point, s2.normal, tangent);
            if (!a_in.found || !b_in.found) {
                continue;
            }
            const gp_Vec continued = a_in.direction.Reversed();
            // B on both sides of the edge (the edge runs across its interior): no leaving direction, so the angle is the normals'
            // (already oriented to within a quarter turn).
            sample_angle = b_in.both ? std::atan2(s1.normal.Crossed(s2.normal).Magnitude(), s1.normal.Dot(s2.normal))
                                     : std::atan2(continued.Crossed(b_in.direction).Magnitude(), continued.Dot(b_in.direction));
        } else {
            sample_angle = std::atan2(s1.normal.Crossed(s2.normal).Magnitude(), s1.normal.Dot(s2.normal));
        }
        ++used;
        position = std::max(position, std::max(s1.point.Distance(s2.point), std::max(s1.point.Distance(p), s2.point.Distance(p))));
        angle = std::max(angle, sample_angle);
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
    if (used == 0 || (project_b && used * 2 < samples)) {
        throw user_error(project_b ? "The edge doesn't run along that face." : "The surfaces along this edge can't be compared.");
    }
    // R13: a grade across two bodies rests on at least three quarters of the samples, so a G2 never stands on half an edge.
    if (project_b && used * 4 < samples * 3) {
        throw user_error("Too few points along the edge lie on the other face to grade it.");
    }
    out.position_gap = position;
    out.angle_gap = angle;
    out.curvature_gap = relative;
    out.absolute_curvature_gap = absolute;
    return out;
}

} // namespace

occt_edge_continuity edge_continuity(const TopoDS_Edge &edge, const TopoDS_Face &face_a, const TopoDS_Face &face_b, int samples) {
    return grade_samples(edge, face_a, face_b, samples, false);
}

occt_edge_continuity edge_continuity_against(const TopoDS_Edge &edge, const TopoDS_Face &face_a, const TopoDS_Face &face_b,
                                             int samples) {
    return grade_samples(edge, face_a, face_b, samples, true);
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

int occt_edge_continuity_against(const occt_shape *first, int edge_index, const occt_shape *second, int face_index,
                                 occt_edge_continuity *out, occt_status *status) {
    return guarded(status, [&]() -> int {
        *out = occt_edge_continuity{};
        const TopTools_IndexedMapOfShape edges = map_of(first->shape, TopAbs_EDGE);
        if (edge_index < 1 || edge_index > edges.Extent()) {
            throw user_error("That edge no longer exists.");
        }
        const TopTools_IndexedMapOfShape faces = map_of(second->shape, TopAbs_FACE);
        if (face_index < 1 || face_index > faces.Extent()) {
            throw user_error("That face no longer exists.");
        }
        const TopoDS_Edge edge = TopoDS::Edge(edges.FindKey(edge_index));
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(first->shape, TopAbs_EDGE, TopAbs_FACE, edge_faces);
        const std::vector<TopoDS_Face> own = distinct_faces(edge, edge_faces);
        if (!is_boundary_edge(edge, own)) {
            throw user_error("The edge must be a surface's free edge.");
        }
        *out = edge_continuity_against(edge, own[0], TopoDS::Face(faces.FindKey(face_index)), 32);
        return 1;
    });
}

} // extern "C"
