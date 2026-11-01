// SPIKE (G-b): curvature-continuous fillet strips. OpenCascade makes the circular fillet; each strip face is then
// replaced by a B-spline surface skinned from quintic G2 Hermite sections between its two spring edges.
#include "cocct_g2_section.hpp"
#include "cocct_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepBuilderAPI_Copy.hxx>
#include <BRepFill_Filling.hxx>
#include <GeomAbs_Shape.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepLib.hxx>
#include <BRepTools.hxx>
#include <BRepTools_ReShape.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Extrema_ExtPC.hxx>
#include <Geom2dAPI_Interpolate.hxx>
#include <TColgp_HArray1OfPnt2d.hxx>
#include <Geom2d_BSplineCurve.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BezierCurve.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <TColGeom2d_Array1OfBSplineCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array1OfPnt2d.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopoDS_Wire.hxx>
#include <TopoDS_Iterator.hxx>
#include <gp_Pnt.hxx>
#include <gp_Pln.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <memory>

using namespace cocct;

namespace {

constexpr int kFirstSections = 9;   // cross-sections per strip to start with
constexpr int kMaxSections = 129;   // the cap: 9, 17, 33, 65, 129
constexpr int kCheckSamples = 128;  // samples per spring edge when a candidate strip is judged
constexpr int kMeasureSamples = 64;
constexpr double kEdgeTolerance = 1e-6;
constexpr const char *kStripMessage = "The fillet can't be made curvature continuous at this radius.";
constexpr const char *kWeightMessage = "The tangency weight is too large for this fillet.";
constexpr const char *kCornerMessage = "The fillet's corners can't be made smooth at this radius.";

gp_Vec to_vec(const g2::Vec &v) { return gp_Vec(v[0], v[1], v[2]); }
g2::Vec from_vec(const gp_Vec &v) { return {v.X(), v.Y(), v.Z()}; }
g2::Vec from_pnt(const gp_Pnt &p) { return {p.X(), p.Y(), p.Z()}; }

/// A face's geometry at the point where `edge`'s parameter is `t`, normal pointing out of the solid.
struct SurfacePoint {
    gp_Pnt p;
    gp_Vec su, sv, suu, suv, svv, n;

    /// The second derivative of a curve in the surface leaving along the unit tangent-plane vector `t`, and the
    /// normal curvature along it (signed against the outward normal).
    double normal_curvature(const gp_Vec &t) const {
        const double g11 = su.Dot(su), g12 = su.Dot(sv), g22 = sv.Dot(sv);
        const double det = g11 * g22 - g12 * g12;
        const double r1 = t.Dot(su), r2 = t.Dot(sv);
        const double a = (r1 * g22 - r2 * g12) / det;
        const double b = (r2 * g11 - r1 * g12) / det;
        const gp_Vec second = suu * (a * a) + suv * (2 * a * b) + svv * (b * b);
        return second.Dot(n) / t.SquareMagnitude();
    }
};

SurfacePoint surface_point(const TopoDS_Face &face, const TopoDS_Edge &edge, double t) {
    double first = 0, last = 0;
    const Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(edge, face, first, last);
    if (pc.IsNull()) {
        throw user_error(kStripMessage);
    }
    const gp_Pnt2d uv = pc->Value(t);
    BRepAdaptor_Surface surface(face, Standard_False);
    SurfacePoint s;
    surface.D2(uv.X(), uv.Y(), s.p, s.su, s.sv, s.suu, s.svv, s.suv);
    s.n = s.su.Crossed(s.sv);
    if (s.n.Magnitude() < 1e-12) {
        throw user_error(kStripMessage);
    }
    s.n.Normalize();
    if (face.Orientation() == TopAbs_REVERSED) {
        s.n.Reverse();
    }
    return s;
}

struct Spring {
    TopoDS_Edge edge;
    TopoDS_Face neighbour;
    bool flipped = false; // sampled from its last parameter to its first
};

/// The edge parameter of fraction `fraction` of the way along the spring's parameter range, in the sampling direction.
double sample_parameter(const Spring &spring, double fraction) {
    BRepAdaptor_Curve curve(spring.edge);
    const double f = spring.flipped ? 1 - fraction : fraction;
    return curve.FirstParameter() + f * (curve.LastParameter() - curve.FirstParameter());
}

/// What a neighbour face gives at a section end.
struct NeighbourEnd {
    g2::EndCondition condition;
    gp_Pnt p;
    gp_Vec n;       // outward normal
    gp_Vec tangent; // of the spring edge
};

/// The neighbour's end condition across `spring`'s edge at edge parameter `t`: position, the unit direction of travel
/// (into the blend when `entering`, else out of it) and the acceleration, the normal curvature times the normal.
NeighbourEnd end_condition(const Spring &spring, double t, const gp_Pnt &other, bool entering) {
    const SurfacePoint s = surface_point(spring.neighbour, spring.edge, t);
    BRepAdaptor_Curve curve(spring.edge);
    gp_Pnt p;
    gp_Vec tangent;
    curve.D1(t, p, tangent);
    gp_Vec across = s.n.Crossed(tangent);
    if (across.Magnitude() < 1e-12) {
        throw user_error(kStripMessage);
    }
    across.Normalize();
    if (across.Dot(gp_Vec(s.p, other)) < 0) {
        across.Reverse();
    }
    const double kappa = s.normal_curvature(across);
    NeighbourEnd e;
    e.condition.position = from_pnt(s.p);
    e.condition.direction = from_vec(entering ? across : across.Reversed());
    e.condition.acceleration = from_vec(s.n * kappa);
    e.p = s.p;
    e.n = s.n;
    e.tangent = tangent;
    return e;
}

/// The edge parameters of each section's point on the first spring (linear in the parameter range) and on the second
/// (the first's point projected onto it, so a curve whose parameter runs differently from the first's is paired by
/// geometry; the ends are the ends). Falls back to the linear pairing when the projection is not monotone.
struct Pairing {
    std::vector<double> ta, tb;
};

Pairing pair_sections(const Spring &a, const Spring &b, int sections) {
    Pairing pairing;
    BRepAdaptor_Curve ca(a.edge), cb(b.edge);
    for (int j = 0; j < sections; ++j) {
        const double f = static_cast<double>(j) / (sections - 1);
        pairing.ta.push_back(sample_parameter(a, f));
        pairing.tb.push_back(sample_parameter(b, f));
    }
    const double direction = b.flipped ? -1 : 1;
    std::vector<double> projected = pairing.tb;
    bool usable = true;
    for (int j = 1; j + 1 < sections && usable; ++j) {
        Extrema_ExtPC ext(ca.Value(pairing.ta[j]), cb, cb.FirstParameter(), cb.LastParameter());
        usable = ext.IsDone() && ext.NbExt() > 0;
        if (usable) {
            int best = 1;
            for (int i = 2; i <= ext.NbExt(); ++i) {
                if (ext.SquareDistance(i) < ext.SquareDistance(best)) {
                    best = i;
                }
            }
            projected[j] = ext.Point(best).Parameter();
        }
    }
    for (int j = 1; j < sections && usable; ++j) {
        usable = direction * (projected[j] - projected[j - 1]) > 1e-12;
    }
    if (usable) {
        pairing.tb = projected;
    }
    return pairing;
}

Handle(Geom2d_BSplineCurve) line2d(const gp_Pnt2d &from, const gp_Pnt2d &to, double first, double last) {
    TColgp_Array1OfPnt2d poles(1, 2);
    poles.SetValue(1, from);
    poles.SetValue(2, to);
    TColStd_Array1OfReal knots(1, 2);
    knots.SetValue(1, first);
    knots.SetValue(2, last);
    TColStd_Array1OfInteger mults(1, 2);
    mults.SetValue(1, 2);
    mults.SetValue(2, 2);
    return new Geom2d_BSplineCurve(poles, knots, mults, 1);
}

/// The pcurve of a spring on the strip (v fixed): u as a function of the edge parameter, through the points
/// (t[j], u[j]) of the sections. A straight map (the usual case) is a line; otherwise it is interpolated.
Handle(Geom2d_Curve) spring_pcurve(std::vector<double> t, std::vector<double> u, double v) {
    if (t.front() > t.back()) {
        std::reverse(t.begin(), t.end());
        std::reverse(u.begin(), u.end());
    }
    bool straight = true;
    for (std::size_t j = 0; j < t.size(); ++j) {
        const double expected = u.front() + (u.back() - u.front()) * (t[j] - t.front()) / (t.back() - t.front());
        straight = straight && std::abs(expected - u[j]) < 1e-9;
    }
    if (straight) {
        return line2d(gp_Pnt2d(u.front(), v), gp_Pnt2d(u.back(), v), t.front(), t.back());
    }
    Handle(TColgp_HArray1OfPnt2d) points = new TColgp_HArray1OfPnt2d(1, static_cast<int>(t.size()));
    Handle(TColStd_HArray1OfReal) params = new TColStd_HArray1OfReal(1, static_cast<int>(t.size()));
    for (std::size_t j = 0; j < t.size(); ++j) {
        points->SetValue(static_cast<int>(j) + 1, gp_Pnt2d(u[j], v));
        params->SetValue(static_cast<int>(j) + 1, t[j]);
    }
    Geom2dAPI_Interpolate interpolate(points, params, Standard_False, 1e-9);
    interpolate.Perform();
    if (!interpolate.IsDone()) {
        throw user_error(kStripMessage);
    }
    return interpolate.Curve();
}

struct BuiltStrip {
    Handle(Geom_BSplineSurface) surface;
    Handle(Geom2d_Curve) pcurve[2]; // of the first and second spring
    std::vector<std::array<g2::Vec, 6>> sections;
    std::vector<NeighbourEnd> first_ends, second_ends;
};

BuiltStrip build_strip(const Spring &a, const Spring &b, double weight, int sections, bool closed) {
    BuiltStrip built;
    built.sections.resize(sections);
    const Pairing pairing = pair_sections(a, b, sections);
    BRepAdaptor_Curve ca(a.edge), cb(b.edge);
    for (int j = 0; j < sections; ++j) {
        const gp_Pnt pa = ca.Value(pairing.ta[j]);
        const gp_Pnt pb = cb.Value(pairing.tb[j]);
        const NeighbourEnd e0 = end_condition(a, pairing.ta[j], pb, true);
        const NeighbourEnd e1 = end_condition(b, pairing.tb[j], pa, false);
        const double chord = pa.Distance(pb);
        const double theta = g2::turning_angle(e0.condition.direction, e1.condition.direction);
        const double d = weight * g2::circular_tangent_length(chord, theta);
        built.sections[j] = g2::quintic_poles(e0.condition, d, e1.condition, d);
        built.first_ends.push_back(e0);
        built.second_ends.push_back(e1);
    }
    std::vector<double> u(sections);
    for (int j = 0; j < sections; ++j) {
        u[j] = static_cast<double>(j) / (sections - 1);
    }
    built.pcurve[0] = spring_pcurve(pairing.ta, u, 0);
    built.pcurve[1] = spring_pcurve(pairing.tb, u, 1);
    // Skin: one cubic interpolation along the strip per pole row, all through the same parameters. A closed strip
    // (a hole edge's) interpolates periodically through all but the last section, which repeats the first.
    const int points_count = closed ? sections - 1 : sections;
    Handle(TColStd_HArray1OfReal) params = new TColStd_HArray1OfReal(1, sections);
    for (int j = 0; j < sections; ++j) {
        params->SetValue(j + 1, u[j]);
    }
    std::vector<Handle(Geom_BSplineCurve)> rows;
    for (int i = 0; i < 6; ++i) {
        Handle(TColgp_HArray1OfPnt) points = new TColgp_HArray1OfPnt(1, points_count);
        for (int j = 0; j < points_count; ++j) {
            const g2::Vec &q = built.sections[j][i];
            points->SetValue(j + 1, gp_Pnt(q[0], q[1], q[2]));
        }
        GeomAPI_Interpolate interpolate(points, params, closed ? Standard_True : Standard_False, 1e-9);
        interpolate.Perform();
        if (!interpolate.IsDone()) {
            throw user_error(kStripMessage);
        }
        rows.push_back(interpolate.Curve());
    }
    const int count = rows[0]->NbPoles();
    TColgp_Array2OfPnt poles(1, count, 1, 6);
    for (int i = 0; i < 6; ++i) {
        if (rows[i]->NbPoles() != count) {
            throw user_error(kStripMessage);
        }
        for (int k = 1; k <= count; ++k) {
            poles.SetValue(k, i + 1, rows[i]->Pole(k));
        }
    }
    TColStd_Array1OfReal uknots(1, rows[0]->NbKnots());
    TColStd_Array1OfInteger umults(1, rows[0]->NbKnots());
    rows[0]->Knots(uknots);
    rows[0]->Multiplicities(umults);
    TColStd_Array1OfReal vknots(1, 2);
    vknots.SetValue(1, 0);
    vknots.SetValue(2, 1);
    TColStd_Array1OfInteger vmults(1, 2);
    vmults.SetValue(1, 6);
    vmults.SetValue(2, 6);
    built.surface = new Geom_BSplineSurface(poles, uknots, vknots, umults, vmults, rows[0]->Degree(), 5,
                                            closed ? Standard_True : Standard_False, Standard_False);
    return built;
}

/// The signed distance of `p` from a neighbour's surface (positive on the side its outward normal points to), by
/// projecting onto the surface itself, so a neighbour that curves away from its tangent plane is not mistaken for an
/// overshoot. Falls back to the tangent plane at `end` when the projection or the face's location isn't usable.
double offset_from(const Spring &spring, const NeighbourEnd &end, const gp_Pnt &p) {
    TopLoc_Location location;
    const Handle(Geom_Surface) surface = BRep_Tool::Surface(spring.neighbour, location);
    if (!surface.IsNull() && location.IsIdentity()) {
        GeomAPI_ProjectPointOnSurf project(p, surface);
        if (project.NbPoints() > 0) {
            double u = 0, v = 0;
            project.LowerDistanceParameters(u, v);
            gp_Pnt on;
            gp_Vec du, dv;
            surface->D1(u, v, on, du, dv);
            gp_Vec n = du.Crossed(dv);
            if (n.Magnitude() > 1e-12) {
                n.Normalize();
                if (spring.neighbour.Orientation() == TopAbs_REVERSED) {
                    n.Reverse();
                }
                return gp_Vec(on, p).Dot(n);
            }
        }
    }
    return gp_Vec(end.p, p).Dot(end.n);
}

/// Refuses sections that leave the wedge the neighbours' surfaces make at their ends (the tangency weight is too
/// large: material would be pushed past the original corner), sections whose middle strays from the circular strip's
/// own face by more than half the fillet radius or off its parameter range (a strip that isn't a sane blend), and end
/// sections that don't cross the springs squarely.
void validate_sections(const BuiltStrip &built, const TopoDS_Face &circular_face, const Spring &a, const Spring &b,
                       double radius) {
    const Handle(Geom_Surface) circular = BRep_Tool::Surface(circular_face);
    double umin = 0, umax = 0, vmin = 0, vmax = 0;
    BRepTools::UVBounds(circular_face, umin, umax, vmin, vmax);
    const double margin_u = 0.05 * (umax - umin) + 1e-9, margin_v = 0.05 * (vmax - vmin) + 1e-9;
    for (std::size_t j = 0; j < built.sections.size(); ++j) {
        const auto &poles = built.sections[j];
        g2::Vec position, d1, d2;
        g2::evaluate(poles, 0.5, position, d1, d2);
        const gp_Pnt mid(position[0], position[1], position[2]);
        GeomAPI_ProjectPointOnSurf project(mid, circular);
        if (project.NbPoints() == 0 || project.LowerDistance() > 0.5 * radius) {
            throw user_error(kStripMessage);
        }
        double pu = 0, pv = 0;
        project.LowerDistanceParameters(pu, pv);
        if ((!circular->IsUPeriodic() && (pu < umin - margin_u || pu > umax + margin_u)) ||
            (!circular->IsVPeriodic() && (pv < vmin - margin_v || pv > vmax + margin_v))) {
            throw user_error(kStripMessage);
        }
        const gp_Pnt q = project.NearestPoint();
        const NeighbourEnd &ea = built.first_ends[j], &eb = built.second_ends[j];
        if (j == 0 || j + 1 == built.sections.size()) {
            // An end section is the strip's end edge, so the chord must cross the springs squarely; a slanted
            // run-out (a blend ending on a face at an angle) isn't a cross-section and isn't supported.
            const gp_Vec chord(ea.p, eb.p);
            if (std::abs(chord.Dot(ea.tangent)) > 0.1 * chord.Magnitude() * ea.tangent.Magnitude()) {
                throw user_error(kStripMessage);
            }
        }
        const double sa = offset_from(a, ea, q) < 0 ? -1 : 1;
        const double sb = offset_from(b, eb, q) < 0 ? -1 : 1;
        const double tolerance = 0.01 * ea.p.Distance(eb.p);
        for (int k = 0; k <= 16; k += 2) {
            g2::evaluate(poles, k / 16.0, position, d1, d2);
            const gp_Pnt p(position[0], position[1], position[2]);
            if (sa * offset_from(a, ea, p) < -tolerance || sb * offset_from(b, eb, p) < -tolerance) {
                throw user_error(kWeightMessage);
            }
        }
    }
}

bool is_blend(const TopoDS_Shape &face, const std::vector<TopoDS_Face> &blend) {
    for (const TopoDS_Face &b : blend) {
        if (b.IsSame(face)) {
            return true;
        }
    }
    return false;
}

struct StripEdges {
    Spring spring[2];
    TopoDS_Edge ends[2];
    TopoDS_Face end_face[2]; // null where the end borders a blend face
    bool closed = false;     // a hole edge's strip: its one seam is both ends
};

StripEdges classify(const TopoDS_Face &strip, const TopTools_IndexedDataMapOfShapeListOfShape &edge_faces,
                    const std::vector<TopoDS_Face> &blend, const std::vector<TopoDS_Face> &strips) {
    StripEdges out;
    int springs = 0, ends = 0;
    for (TopExp_Explorer it(strip, TopAbs_EDGE); it.More(); it.Next()) {
        const TopoDS_Edge edge = TopoDS::Edge(it.Current());
        bool duplicate = false;
        for (int i = 0; i < springs; ++i) {
            duplicate = duplicate || out.spring[i].edge.IsSame(edge);
        }
        for (int i = 0; i < ends; ++i) {
            duplicate = duplicate || out.ends[i].IsSame(edge);
        }
        if (duplicate) {
            for (int i = 0; i < ends; ++i) {
                if (out.ends[i].IsSame(edge) && BRep_Tool::IsClosed(edge, strip)) {
                    out.closed = true;
                }
            }
            continue;
        }
        if (BRep_Tool::Degenerated(edge)) {
            throw user_error(kStripMessage);
        }
        TopoDS_Face other;
        for (const TopoDS_Face &face : distinct_faces(edge, edge_faces)) {
            if (!face.IsSame(strip)) {
                other = face;
            }
        }
        bool spring = false;
        if (!other.IsNull() && !is_blend(other, blend)) {
            double first = 0, last = 0;
            BRep_Tool::Range(edge, first, last);
            const double mid = 0.5 * (first + last);
            const SurfacePoint a = surface_point(strip, edge, mid);
            const SurfacePoint b = surface_point(other, edge, mid);
            spring = std::abs(a.n.Dot(b.n)) > 0.99;
        }
        if (spring && springs < 2) {
            out.spring[springs].edge = edge;
            out.spring[springs].neighbour = other;
            ++springs;
        } else if (!spring && ends < 2) {
            if (!other.IsNull() && is_blend(other, strips)) {
                // Two strips of a tangent chain share a section; two strips meeting at an angle share a mitre,
                // which has no section to replace.
                double first = 0, last = 0;
                BRep_Tool::Range(edge, first, last);
                const double mid = 0.5 * (first + last);
                if (std::abs(surface_point(strip, edge, mid).n.Dot(surface_point(other, edge, mid).n)) < 0.99) {
                    throw user_error(kStripMessage);
                }
            }
            out.ends[ends] = edge;
            if (!other.IsNull() && !is_blend(other, blend)) {
                out.end_face[ends] = other;
            }
            ++ends;
        } else {
            throw user_error(kStripMessage);
        }
    }
    if (out.closed && ends == 1) {
        out.ends[1] = out.ends[0];
        ends = 2;
    }
    if (springs != 2 || ends != 2) {
        throw user_error(kStripMessage);
    }
    // Sample both springs from the same end.
    BRepAdaptor_Curve ca(out.spring[0].edge), cb(out.spring[1].edge);
    const gp_Pnt a0 = ca.Value(ca.FirstParameter()), a1 = ca.Value(ca.LastParameter());
    const gp_Pnt b0 = cb.Value(cb.FirstParameter()), b1 = cb.Value(cb.LastParameter());
    out.spring[1].flipped = a0.Distance(b0) + a1.Distance(b1) > a0.Distance(b1) + a1.Distance(b0);
    return out;
}

/// Folds the gaps at one sample of a seam into `seam`; `a` and `b` are the two faces there, `tangent` the edge's.
void accumulate(occt_g2_seam &seam, const SurfacePoint &a, const SurfacePoint &b, const gp_Vec &tangent) {
    gp_Vec across = a.n.Crossed(tangent);
    across.Normalize();
    gp_Vec across_b = across - b.n * across.Dot(b.n);
    across_b.Normalize();
    const double ka = a.normal_curvature(across), kb = b.normal_curvature(across_b);
    const double gap = std::abs(ka - kb);
    const double allowed = std::max(0.01 * std::max(std::abs(ka), std::abs(kb)), 1e-4);
    seam.position = std::max(seam.position, a.p.Distance(b.p));
    const double cosine = std::clamp(a.n.Dot(b.n), -1.0, 1.0);
    seam.angle_degrees = std::max(seam.angle_degrees, std::acos(cosine) * 180 / kPi);
    seam.curvature = std::max(seam.curvature, gap);
    if (gap / allowed >= seam.curvature_ratio) {
        seam.curvature_ratio = gap / allowed;
        seam.curvature_allowed = allowed;
    }
}

/// The worst position, angle and curvature gaps along `edge` between the two faces that share it.
occt_g2_seam measure_seam(const TopoDS_Edge &edge, const TopoDS_Face &f1, const TopoDS_Face &f2) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(edge);
    for (int k = 0; k <= kMeasureSamples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / kMeasureSamples;
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        accumulate(seam, surface_point(f1, edge, t), surface_point(f2, edge, t), tangent);
    }
    return seam;
}

/// The strip's gaps against one spring's neighbour, read off the candidate surface through the spring's pcurve before
/// any topology is built. `reversed`: the face is REVERSED, so its outward normal is the raw one's opposite.
occt_g2_seam candidate_seam(const Handle(Geom_BSplineSurface) &surface, bool reversed, const Spring &spring,
                            const Handle(Geom2d_Curve) &pcurve) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(spring.edge);
    for (int k = 0; k <= kCheckSamples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / kCheckSamples;
        const gp_Pnt2d uv = pcurve->Value(t);
        SurfacePoint strip;
        surface->D2(uv.X(), uv.Y(), strip.p, strip.su, strip.sv, strip.suu, strip.svv, strip.suv);
        strip.n = strip.su.Crossed(strip.sv);
        strip.n.Normalize();
        if (reversed) {
            strip.n.Reverse();
        }
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        accumulate(seam, strip, surface_point(spring.neighbour, spring.edge, t), tangent);
    }
    return seam;
}

bool within_tolerance(const occt_g2_seam &seam) {
    // Half the promised tolerances, so the final measurement at other samples still has room.
    return seam.position <= 0.5e-4 && seam.angle_degrees <= 0.005 && seam.curvature_ratio <= 0.5;
}

} // namespace

extern "C" {

double occt_g2_tangent_length(double chord, double turning_angle) {
    return g2::circular_tangent_length(chord, turning_angle);
}

int occt_g2_section_test(const double end0[9], double len0, const double end1[9], double len1, double t, double out[9]) {
    auto read = [](const double *e) {
        g2::EndCondition c;
        c.position = {e[0], e[1], e[2]};
        c.direction = {e[3], e[4], e[5]};
        c.acceleration = {e[6], e[7], e[8]};
        return c;
    };
    const auto poles = g2::quintic_poles(read(end0), len0, read(end1), len1);
    g2::Vec p, d1, d2;
    g2::evaluate(poles, t, p, d1, d2);
    for (int i = 0; i < 3; ++i) {
        out[i] = p[i];
        out[3 + i] = d1[i];
        out[6 + i] = d2[i];
    }
    return 1;
}

occt_shape *occt_fillet_g2(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                           occt_history *history, occt_g2_report *report, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        *report = occt_g2_report{};
        if (!shape || !edge_indices || count <= 0 || !std::isfinite(radius) || radius <= 0) {
            set_error(status, "a blend needs edges and a size greater than 0");
            return nullptr;
        }
        const TopTools_IndexedMapOfShape input_edges = map_of(shape->shape, TopAbs_EDGE);
        BRepFilletAPI_MakeFillet algo(shape->shape);
        for (int i = 0; i < count; ++i) {
            if (edge_indices[i] < 1 || edge_indices[i] > input_edges.Extent()) {
                set_error(status, "edge index out of range");
                return nullptr;
            }
            algo.Add(radius, TopoDS::Edge(input_edges(edge_indices[i])));
        }
        algo.Build();
        if (!algo.IsDone()) {
            set_error(status, "the fillet could not be built for this radius");
            return nullptr;
        }
        const TopoDS_Shape g1 = algo.Shape();

        // History against the circular result; a face keeps its index through the copy and the replacements.
        history_builder records(g1);
        {
            const TopTools_IndexedMapOfShape faces = map_of(shape->shape, TopAbs_FACE);
            for (int j = 1; j <= faces.Extent(); ++j) {
                const TopoDS_Shape &face = faces(j);
                if (algo.IsDeleted(face)) {
                    continue;
                }
                const TopTools_ListOfShape &modified = algo.Modified(face);
                if (modified.IsEmpty()) {
                    records.add(face, OCCT_FROM_FACE, 0, j);
                } else {
                    records.add_all(modified, OCCT_FROM_FACE, 0, j);
                }
            }
        }
        std::vector<int> strip_indices, corner_indices;
        const TopTools_IndexedMapOfShape g1_faces = map_of(g1, TopAbs_FACE);
        for (int i = 0; i < count; ++i) {
            const TopoDS_Edge edge = TopoDS::Edge(input_edges(edge_indices[i]));
            records.add_all(algo.Generated(edge), OCCT_FROM_EDGE, 0, edge_indices[i]);
            for (TopTools_ListOfShape::Iterator it(algo.Generated(edge)); it.More(); it.Next()) {
                strip_indices.push_back(g1_faces.FindIndex(it.Value()));
            }
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    records.add_all(algo.Generated(vertex), OCCT_FROM_EDGE, 0, edge_indices[i]);
                    for (TopTools_ListOfShape::Iterator it(algo.Generated(vertex)); it.More(); it.Next()) {
                        corner_indices.push_back(g1_faces.FindIndex(it.Value()));
                    }
                }
            }
        }
        records.move_into(history);

        BRepBuilderAPI_Copy copy(g1, Standard_True, Standard_False);
        const TopoDS_Shape work = copy.Shape();
        const TopTools_IndexedMapOfShape faces = map_of(work, TopAbs_FACE);
        if (faces.Extent() != g1_faces.Extent()) {
            throw user_error(kStripMessage);
        }
        std::sort(strip_indices.begin(), strip_indices.end());
        strip_indices.erase(std::unique(strip_indices.begin(), strip_indices.end()), strip_indices.end());
        std::sort(corner_indices.begin(), corner_indices.end());
        corner_indices.erase(std::unique(corner_indices.begin(), corner_indices.end()), corner_indices.end());
        std::vector<TopoDS_Face> blend_faces;
        for (int index : strip_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (int index : corner_indices) {
            blend_faces.push_back(TopoDS::Face(faces(index)));
        }
        TopTools_IndexedDataMapOfShapeListOfShape edge_faces;
        TopExp::MapShapesAndAncestors(work, TopAbs_EDGE, TopAbs_FACE, edge_faces);

        TopoDS_Shape result = work;
        BRep_Builder builder;
        BRepTools_ReShape reshape;
        std::vector<TopoDS_Face> strip_faces, corner_faces;
        for (int index : strip_indices) {
            strip_faces.push_back(TopoDS::Face(faces(index)));
        }
        for (int index : corner_indices) {
            corner_faces.push_back(TopoDS::Face(faces(index)));
        }
        std::vector<StripEdges> strips;
        for (const TopoDS_Face &face : strip_faces) {
            strips.push_back(classify(face, edge_faces, blend_faces, strip_faces));
        }
        struct Replaced {
            TopoDS_Edge old_edge, new_edge;
            TopoDS_Face strip;
        };
        std::vector<Replaced> replaced;
        // SPIKE ONLY: a weight <= 0 keeps the circular strips and just measures them (the baseline). Task 3 removes it.
        if (weight > 0) {
            for (std::size_t s = 0; s < strips.size(); ++s) {
                const TopoDS_Face old_face = strip_faces[s];
                const Handle(Geom_Surface) circular = BRep_Tool::Surface(old_face);
                StripEdges &edges = strips[s];
                BuiltStrip built;
                bool swapped = false;
                // Sections are doubled (9, 17, 33, ...) until the candidate's seams pass; the cap fails the blend.
                int sections = kFirstSections;
                for (;; sections = 2 * sections - 1) {
                    swapped = false;
                    for (int attempt = 0; attempt < 2; ++attempt) {
                        built = build_strip(edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], weight, sections, edges.closed);
                        // The raw normal must agree with the old surface's so the face keeps its orientation.
                        gp_Pnt mid;
                        gp_Vec du, dv;
                        built.surface->D1(0.5, 0.5, mid, du, dv);
                        GeomAPI_ProjectPointOnSurf project(mid, circular);
                        double u = 0, v = 0;
                        project.LowerDistanceParameters(u, v);
                        gp_Pnt q;
                        gp_Vec ou, ov;
                        circular->D1(u, v, q, ou, ov);
                        if (du.Crossed(dv).Dot(ou.Crossed(ov)) > 0) {
                            break;
                        }
                        swapped = !swapped;
                    }
                    validate_sections(built, old_face, edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], radius);
                    const bool reversed = old_face.Orientation() == TopAbs_REVERSED;
                    if (within_tolerance(candidate_seam(built.surface, reversed, edges.spring[swapped ? 1 : 0], built.pcurve[0])) &&
                        within_tolerance(candidate_seam(built.surface, reversed, edges.spring[swapped ? 0 : 1], built.pcurve[1]))) {
                        break;
                    }
                    if (sections >= kMaxSections) {
                        throw user_error(kStripMessage);
                    }
                }
                report->sections = std::max(report->sections, sections);
                if (s < 32) {
                    report->strip_sections[s] = sections;
                }
                // Spring edges: the pcurve on the new surface.
                const Handle(Geom_Surface) surface = built.surface;
                for (int side = 0; side < 2; ++side) {
                    const Spring &spring = edges.spring[(side == 0) != swapped ? 0 : 1];
                    builder.UpdateEdge(spring.edge, built.pcurve[side], surface, TopLoc_Location(), kEdgeTolerance);
                }

                // End edges become the first and last sections (shared with the next strip of a tangent chain).
                                TopoDS_Edge new_ends[2];
                TopoDS_Edge seam_edge;       // a closed strip's one seam, both ends
                bool seam_reversed = false;
                for (int end = 0; end < (edges.closed ? 1 : 2); ++end) {
                    TColgp_Array1OfPnt poles(1, 6);
                    const auto &section = end == 0 ? built.sections.front() : built.sections.back();
                    for (int i = 0; i < 6; ++i) {
                        poles.SetValue(i + 1, gp_Pnt(section[i][0], section[i][1], section[i][2]));
                    }
                    Handle(Geom_BezierCurve) bezier = new Geom_BezierCurve(poles);
                    // Which old end edge is at this section: the one whose midpoint is nearer.
                    int chosen = 0;
                    {
                        const gp_Pnt target = bezier->Value(0.5);
                        double best = 1e300;
                        for (int c = 0; c < 2; ++c) {
                            BRepAdaptor_Curve oc(edges.ends[c]);
                            const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(target);
                            if (d < best) {
                                best = d;
                                chosen = c;
                            }
                        }
                    }
                    const TopoDS_Edge old_edge = edges.ends[chosen];
                    TopoDS_Edge ne;
                    bool reversed = false;
                    for (const Replaced &r : replaced) {
                        if (r.old_edge.IsSame(old_edge)) {
                            ne = r.new_edge; // the previous strip of a tangent chain made it
                        }
                    }
                    if (!ne.IsNull()) {
                        BRepAdaptor_Curve nc(ne);
                        reversed = nc.Value(0).Distance(bezier->Value(0)) > nc.Value(0).Distance(bezier->Value(1));
                        // The shared section must be this strip's own: both are built from the same neighbours.
                        for (int k = 0; k <= 8; ++k) {
                            const double t = k / 8.0;
                            if (nc.Value(t).Distance(bezier->Value(reversed ? 1 - t : t)) > 1e-6) {
                                throw user_error(kStripMessage);
                            }
                        }
                    } else {
                        TopoDS_Vertex v1, v2;
                        TopExp::Vertices(old_edge, v1, v2, Standard_False);
                        const gp_Pnt p_first = BRep_Tool::Pnt(v1);
                        reversed = bezier->Value(0).Distance(p_first) > bezier->Value(1).Distance(p_first);
                        Handle(Geom_BezierCurve) curve = bezier;
                        if (reversed) {
                            curve = Handle(Geom_BezierCurve)::DownCast(bezier->Reversed());
                        }
                        builder.MakeEdge(ne, curve, kEdgeTolerance);
                        builder.Add(ne, v1.Oriented(TopAbs_FORWARD));
                        builder.Add(ne, v2.Oriented(TopAbs_REVERSED));
                        builder.Range(ne, 0, 1);
                        if (!edges.end_face[chosen].IsNull()) {
                            if (BRepAdaptor_Surface(edges.end_face[chosen], Standard_False).GetType() != GeomAbs_Plane) {
                                throw user_error(kStripMessage);
                            }
                        }
                        // The replacement carries the old occurrence's orientation: Replace composes the two.
                        reshape.Replace(old_edge, ne.Oriented(old_edge.Orientation()));
                        replaced.push_back({old_edge, ne, TopoDS_Face()});
                    }
                    if (edges.closed) {
                        seam_edge = ne;
                        seam_reversed = reversed;
                        new_ends[0] = new_ends[1] = ne;
                        break;
                    }
                    const double u_iso = end;
                    // Section poles run from the first spring (v = 0) to the second (v = 1).
                    const Handle(Geom2d_BSplineCurve) pcs = reversed ? line2d(gp_Pnt2d(u_iso, 1), gp_Pnt2d(u_iso, 0), 0, 1)
                                                                       : line2d(gp_Pnt2d(u_iso, 0), gp_Pnt2d(u_iso, 1), 0, 1);
                    builder.UpdateEdge(ne, pcs, surface, TopLoc_Location(), kEdgeTolerance);
                    if (!edges.end_face[chosen].IsNull()) {
                        BRepLib::BuildPCurveForEdgeOnPlane(ne, edges.end_face[chosen]);
                    }
                    new_ends[chosen] = ne;
                }
                // A closed strip's seam lies on the surface twice, at u = 0 and u = 1; which pcurve belongs to which
                // orientation is settled below by the face's own check.
                auto seam_pcurves = [&](bool swap) {
                    auto at = [&](double u) {
                        return seam_reversed ? line2d(gp_Pnt2d(u, 1), gp_Pnt2d(u, 0), 0, 1)
                                             : line2d(gp_Pnt2d(u, 0), gp_Pnt2d(u, 1), 0, 1);
                    };
                    builder.UpdateEdge(seam_edge, at(swap ? 1 : 0), at(swap ? 0 : 1), surface, TopLoc_Location(), kEdgeTolerance);
                };
                if (edges.closed) {
                    seam_pcurves(false);
                }

                // The new face: the old wire rebuilt with the new end edges.
                TopoDS_Face new_face;
                builder.MakeFace(new_face, surface, kEdgeTolerance);
                // TopoDS_Builder::Add compensates for the container's orientation, so the containers stay
                // FORWARD while they are filled and take the old orientations afterwards.
                for (TopoDS_Iterator wires(old_face, Standard_False); wires.More(); wires.Next()) {
                    TopoDS_Wire new_wire;
                    builder.MakeWire(new_wire);
                    for (TopoDS_Iterator it(wires.Value(), Standard_False); it.More(); it.Next()) {
                        TopoDS_Shape e = it.Value();
                        for (int c = 0; c < 2; ++c) {
                            if (e.IsSame(edges.ends[c])) {
                                e = new_ends[c].Oriented(it.Value().Orientation());
                            }
                        }
                        builder.Add(new_wire, e);
                    }
                    new_wire.Orientation(wires.Value().Orientation());
                    builder.Add(new_face, new_wire);
                }
                new_face.Orientation(old_face.Orientation());
                if (edges.closed && !BRepCheck_Analyzer(new_face).IsValid()) {
                    seam_pcurves(true);
                    if (!BRepCheck_Analyzer(new_face).IsValid()) {
                        throw user_error(kStripMessage);
                    }
                }
                reshape.Replace(old_face, new_face);
                for (Replaced &r : replaced) {
                    if (r.strip.IsNull()) {
                        r.strip = new_face;
                    }
                }
                ++report->strips;
            }

            // Corner patches: refilled with MakeFilling constrained G1 against the strips (and the original faces) and
            // counted in g1_corners; if that misses the position or angle tolerance the fillet fails. A crease is
            // never returned. OCCT 7.9's MakeFilling cannot constrain G2 (GeomAbs_G2 is refused, order 2 builds
            // garbage), so there is no G2 attempt.
            struct CornerEdge {
                TopoDS_Edge shared;
                TopoDS_Face support;
            };
            for (const TopoDS_Face &old_corner : corner_faces) {
                std::vector<CornerEdge> ces;
                for (TopExp_Explorer it(old_corner, TopAbs_EDGE); it.More(); it.Next()) {
                    const TopoDS_Edge e = TopoDS::Edge(it.Current());
                    if (BRep_Tool::Degenerated(e)) {
                        continue; // the sphere's pole
                    }
                    bool seen = false;
                    CornerEdge ce;
                    ce.shared = e;
                    for (const Replaced &r : replaced) {
                        if (r.old_edge.IsSame(e)) {
                            ce.shared = r.new_edge;
                            ce.support = r.strip;
                        }
                    }
                    for (const CornerEdge &known : ces) {
                        seen = seen || known.shared.IsSame(ce.shared);
                    }
                    if (seen) {
                        continue;
                    }
                    if (ce.support.IsNull()) {
                        for (const TopoDS_Face &f : distinct_faces(e, edge_faces)) {
                            if (!f.IsSame(old_corner)) {
                                ce.support = f;
                            }
                        }
                    }
                    if (ce.support.IsNull() || is_blend(ce.support, corner_faces)) {
                        throw user_error(kCornerMessage);
                    }
                    ces.push_back(ce);
                }
                struct Candidate {
                    TopoDS_Face face;
                    bool ok = false;
                };
                auto attempt = [&](GeomAbs_Shape order) -> Candidate {
                    Candidate candidate;
                    for (int init = 1; init >= 0 && !candidate.ok; --init) {
                        try {
                            BRepFill_Filling fill(5, 30, 5, Standard_False, 1e-6, 1e-6, 1e-4, 1e-3, 12, 20);
                            for (const CornerEdge &ce : ces) {
                                fill.Add(TopoDS::Edge(ce.shared.Oriented(TopAbs_FORWARD)), ce.support, order, Standard_True);
                            }
                            if (init != 0) {
                                fill.LoadInitSurface(old_corner);
                            }
                            fill.Build();
                            if (!fill.IsDone()) {
                                continue;
                            }
                            TopoDS_Face filled = fill.Face();
                            // The outward normal at the patch's middle must match the circular corner's there.
                            BRepAdaptor_Surface ns(filled, Standard_False);
                            gp_Pnt q;
                            gp_Vec a, b;
                            ns.D1(0.5 * (ns.FirstUParameter() + ns.LastUParameter()),
                                  0.5 * (ns.FirstVParameter() + ns.LastVParameter()), q, a, b);
                            gp_Vec n_new = a.Crossed(b);
                            if (filled.Orientation() == TopAbs_REVERSED) {
                                n_new.Reverse();
                            }
                            GeomAPI_ProjectPointOnSurf project(q, BRep_Tool::Surface(old_corner));
                            double u = 0, v = 0;
                            project.LowerDistanceParameters(u, v);
                            gp_Pnt c2;
                            gp_Vec oa, ob;
                            BRepAdaptor_Surface(old_corner, Standard_False).D1(u, v, c2, oa, ob);
                            gp_Vec n_old = oa.Crossed(ob);
                            if (old_corner.Orientation() == TopAbs_REVERSED) {
                                n_old.Reverse();
                            }
                            if (n_new.Dot(n_old) < 0) {
                                filled.Reverse();
                            }
                            // Measure each boundary against its support, through the fill's own edge copies.
                            bool pass = true;
                            for (const CornerEdge &ce : ces) {
                                BRepAdaptor_Curve sc(ce.shared);
                                const gp_Pnt sm = sc.Value(0.5 * (sc.FirstParameter() + sc.LastParameter()));
                                TopoDS_Edge fe;
                                for (TopExp_Explorer it(filled, TopAbs_EDGE); it.More(); it.Next()) {
                                    BRepAdaptor_Curve fc(TopoDS::Edge(it.Current()));
                                    if (fc.Value(0.5 * (fc.FirstParameter() + fc.LastParameter())).Distance(sm) < 1e-6) {
                                        fe = TopoDS::Edge(it.Current());
                                    }
                                }
                                if (fe.IsNull()) {
                                    pass = false;
                                    break;
                                }
                                BRepAdaptor_Curve fc(fe);
                                occt_g2_seam seam{};
                                for (int k = 0; k <= kMeasureSamples; ++k) {
                                    const double t = sc.FirstParameter() + (sc.LastParameter() - sc.FirstParameter()) * k / kMeasureSamples;
                                    gp_Pnt p;
                                    gp_Vec tangent;
                                    sc.D1(t, p, tangent);
                                    accumulate(seam, surface_point(ce.support, ce.shared, t), surface_point(filled, fe, t), tangent);
                                }
                                pass = pass && seam.position <= 1e-4 && seam.angle_degrees <= 0.01;
                                if (std::abs(fc.FirstParameter() - sc.FirstParameter()) > 1e-9 ||
                                    std::abs(fc.LastParameter() - sc.LastParameter()) > 1e-9) {
                                    pass = false;
                                }
                            }
                            if (pass) {
                                candidate.face = filled;
                                candidate.ok = true;
                            }
                        } catch (const Standard_Failure &failure) {
                            continue;
                        }
                    }
                    return candidate;
                };
                const Candidate chosen = attempt(GeomAbs_G1);
                if (!chosen.ok) {
                    throw user_error(kCornerMessage);
                }
                ++report->g1_corners;
                // BRepFill_Filling makes copies of its boundary edges; rebuild the face on the shared edges.
                TopoDS_Face filled = chosen.face;
                const Handle(Geom_Surface) fill_surface = BRep_Tool::Surface(filled);
                TopoDS_Face rebuilt;
                builder.MakeFace(rebuilt, fill_surface, kEdgeTolerance);
                for (TopoDS_Iterator wires(filled, Standard_False); wires.More(); wires.Next()) {
                    TopoDS_Wire wire;
                    builder.MakeWire(wire);
                    for (TopoDS_Iterator it(wires.Value(), Standard_False); it.More(); it.Next()) {
                        const TopoDS_Edge fe = TopoDS::Edge(it.Value());
                        double f2 = 0, l2 = 0;
                        const Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(fe, filled, f2, l2);
                        BRepAdaptor_Curve fc(fe);
                        const gp_Pnt fm = fc.Value(0.5 * (fc.FirstParameter() + fc.LastParameter()));
                        TopoDS_Edge shared;
                        for (const CornerEdge &ce : ces) {
                            BRepAdaptor_Curve nc(ce.shared);
                            if (nc.Value(0.5 * (nc.FirstParameter() + nc.LastParameter())).Distance(fm) < 1e-6) {
                                shared = ce.shared;
                            }
                        }
                        if (shared.IsNull() || pc.IsNull()) {
                            throw user_error(kCornerMessage);
                        }
                        BRepAdaptor_Curve nc(shared);
                        if (nc.Value(nc.FirstParameter()).Distance(fc.Value(fc.FirstParameter())) > 1e-6) {
                            throw user_error(kCornerMessage);
                        }
                        builder.UpdateEdge(shared, pc, fill_surface, TopLoc_Location(), kEdgeTolerance);
                        builder.Add(wire, shared.Oriented(it.Value().Orientation()));
                    }
                    wire.Orientation(wires.Value().Orientation());
                    builder.Add(rebuilt, wire);
                }
                rebuilt.Orientation(filled.Orientation());
                reshape.Replace(old_corner, rebuilt);
                ++report->corners;
            }
            result = reshape.Apply(work);
            BRepLib::SameParameter(result, 1e-5);
            BRepLib::UpdateTolerances(result);
        }

        // Measure the seams in the result: the strips' springs, then the corners' boundaries, kept apart.
        const TopTools_IndexedMapOfShape result_faces = map_of(result, TopAbs_FACE);
        TopTools_IndexedDataMapOfShapeListOfShape result_edge_faces;
        TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, result_edge_faces);
        std::vector<TopoDS_Face> result_blend, result_strips;
        for (int index : strip_indices) {
            result_blend.push_back(TopoDS::Face(result_faces(index)));
            result_strips.push_back(TopoDS::Face(result_faces(index)));
        }
        for (int index : corner_indices) {
            result_blend.push_back(TopoDS::Face(result_faces(index)));
        }
        for (const TopoDS_Face &strip : result_strips) {
            const StripEdges edges = classify(strip, result_edge_faces, result_blend, result_strips);
            for (const Spring &spring : edges.spring) {
                if (report->seam_count < OCCT_G2_MAX_SEAMS) {
                    report->seams[report->seam_count++] = measure_seam(spring.edge, strip, spring.neighbour);
                }
            }
        }
        if (weight > 0) {
            for (int index : corner_indices) {
                const TopoDS_Face corner = TopoDS::Face(result_faces(index));
                for (TopExp_Explorer it(corner, TopAbs_EDGE); it.More(); it.Next()) {
                    const TopoDS_Edge e = TopoDS::Edge(it.Current());
                    if (BRep_Tool::Degenerated(e)) {
                        continue;
                    }
                    for (const TopoDS_Face &other : distinct_faces(e, result_edge_faces)) {
                        if (!other.IsSame(corner) && report->corner_seam_count < OCCT_G2_MAX_SEAMS) {
                            report->corner_seams[report->corner_seam_count++] = measure_seam(e, corner, other);
                        }
                    }
                }
            }
        }
        return new occt_shape{result};
    });
}

} // extern "C"
