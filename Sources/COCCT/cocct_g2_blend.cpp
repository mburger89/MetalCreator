// G-b: curvature-continuous fillets. OpenCascade makes the circular fillet; each strip face is then replaced by a
// B-spline surface skinned from quintic G2 Hermite sections between its two spring edges, and a corner where three strips
// end by one three-sided G2 patch (cocct_g2_triangle.hpp), else a G1 refill.
#include "cocct_g2_triangle.hpp"
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
#include <GeomInt_IntSS.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomProjLib.hxx>
#include <Geom2dAPI_Interpolate.hxx>
#include <TColgp_HArray1OfPnt2d.hxx>
#include <Geom2d_BSplineCurve.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_BezierCurve.hxx>
#include <Geom_BezierSurface.hxx>
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
#include <chrono>
#include <cmath>
#include <memory>

using namespace cocct;
#include <BRepCheck_Analyzer.hxx>
#include <BRepCheck_Result.hxx>

namespace {

constexpr int kFirstSections = 9;   // cross-sections per strip to start with
constexpr int kMaxSections = 129;   // the cap: 9, 17, 33, 65, 129
// Prime sample counts, so that the samples never fall on the sections (which sit at multiples of 1/2^k) and measure
// the worst place between them.
constexpr int kCheckSamples = 127;  // samples per spring edge when a candidate strip is judged
constexpr int kMeasureSamples = 61;
// Where the springs of two chained strips kink at their junction (the faces under them are only G1 there), the strip's
// across direction is the bisector's, and the curvature comparison skips this share of the edge next to the junction.
constexpr int kJunctionSamples = 2;
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
    BRepAdaptor_Surface surface(face, Standard_False);
    SurfacePoint s;
    // Where the parametrization is singular (a G2 corner patch at its centre, where three patches meet) the normal is
    // the limit: read it a hair further along the edge, towards its middle.
    const double towards_middle = (t < 0.5 * (first + last)) ? 1.0 : -1.0;
    for (int attempt = 0; attempt < 4; ++attempt) {
        const gp_Pnt2d uv = pc->Value(t + towards_middle * attempt * 1e-3 * (last - first));
        surface.D2(uv.X(), uv.Y(), s.p, s.su, s.sv, s.suu, s.svv, s.suv);
        s.n = s.su.Crossed(s.sv);
        if (s.n.Magnitude() > 1e-6) {
            break;
        }
    }
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
    double t_start = 0;   // the parameters sampling runs between: the edge's own, or extended past a slanted end
    double t_end = 0;
    bool has_tangent[2] = {false, false}; // a chain junction's agreed spring tangent at the start and end
    bool kinked[2] = {false, false};      // ... where the two springs' tangents differ by more than 0.01 degrees
    gp_Vec junction_tangent[2];
};

/// The edge parameter of fraction `fraction` of the way from the spring's sampling start to its sampling end.
double sample_parameter(const Spring &spring, double fraction) {
    return spring.t_start + fraction * (spring.t_end - spring.t_start);
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
    // At a chain junction both strips use the bisector of the two springs' tangents, so they share one section.
    if (spring.has_tangent[0] && std::abs(t - spring.t_start) < 1e-9) {
        tangent = spring.junction_tangent[0];
    } else if (spring.has_tangent[1] && std::abs(t - spring.t_end) < 1e-9) {
        tangent = spring.junction_tangent[1];
    }
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

Pairing pair_sections(const Spring &a, const Spring &b, const std::vector<double> &fractions) {
    const int sections = static_cast<int>(fractions.size());
    Pairing pairing;
    BRepAdaptor_Curve ca(a.edge), cb(b.edge);
    for (int j = 0; j < sections; ++j) {
        pairing.ta.push_back(sample_parameter(a, fractions[j]));
        pairing.tb.push_back(sample_parameter(b, fractions[j]));
    }
    const double direction = b.t_end > b.t_start ? 1 : -1;
    std::vector<double> projected = pairing.tb;
    bool usable = true;
    const double lo = std::min(b.t_start, b.t_end), hi = std::max(b.t_start, b.t_end);
    const double window = 0.25 * (hi - lo);
    // The parameter of the point of B nearest A's point at section j (the ends may fall slightly outside B's range).
    auto project_onto_b = [&](int j, double &out) {
        Extrema_ExtPC ext(ca.Value(pairing.ta[j]), cb, lo - window, hi + window);
        if (!ext.IsDone() || ext.NbExt() == 0) {
            return false;
        }
        int best = 1;
        for (int i = 2; i <= ext.NbExt(); ++i) {
            if (ext.SquareDistance(i) < ext.SquareDistance(best)) {
                best = i;
            }
        }
        out = ext.Point(best).Parameter();
        return true;
    };
    double start_offset = 0, end_offset = 0;
    {
        double at_start = 0, at_end = 0;
        // B's own ends need not be the projections of A's: a slightly slanted end would make the pairing jump at the
        // last section, so the difference is spread over the strip's ends (weights f^6 and (1-f)^6).
        if (project_onto_b(0, at_start) && project_onto_b(sections - 1, at_end)) {
            start_offset = pairing.tb.front() - at_start;
            end_offset = pairing.tb.back() - at_end;
        }
    }
    for (int j = 1; j + 1 < sections && usable; ++j) {
        double value = 0;
        usable = project_onto_b(j, value);
        if (usable) {
            const double f = fractions[j];
            projected[j] = value + start_offset * std::pow(1 - f, 6) + end_offset * std::pow(f, 6);
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
        straight = straight && std::abs(expected - u[j]) < 1e-7;
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
    std::vector<double> ta; // each section's parameter on the first spring
};

BuiltStrip build_strip(const Spring &a, const Spring &b, double weight, const std::vector<double> &fractions, bool closed) {
    BuiltStrip built;
    const int sections = static_cast<int>(fractions.size());
    built.sections.resize(sections);
    const Pairing pairing = pair_sections(a, b, fractions);
    built.ta = pairing.ta;
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
    const std::vector<double> &u = fractions;
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
    if (!closed) {
        // The pcurves put each spring edge's own parametrization on the strip: u of the point of the boundary curve
        // nearest the edge's point at t, for many t, so that the strip's boundary and the edge agree wherever the edge's
        // parameter is not simply proportional to u.
        const Spring *springs[2] = {&a, &b};
        for (int side = 0; side < 2; ++side) {
            const Handle(Geom_Curve) boundary = built.surface->VIso(side);
            const int samples = 2 * (sections - 1) + 1;
            std::vector<double> t(samples), uu(samples);
            bool projected = true;
            for (int k = 0; k < samples && projected; ++k) {
                t[k] = springs[side]->t_start + (springs[side]->t_end - springs[side]->t_start) * k / (samples - 1);
                GeomAPI_ProjectPointOnCurve project(surface_point(springs[side]->neighbour, springs[side]->edge, t[k]).p, boundary);
                projected = project.NbPoints() > 0;
                if (projected) {
                    uu[k] = project.LowerDistanceParameter();
                    projected = k == 0 || uu[k] > uu[k - 1] - 1e-12;
                }
            }
            if (projected) {
                uu.front() = 0;
                uu.back() = 1;
                built.pcurve[side] = spring_pcurve(t, uu, side);
            }
        }
    }
    return built;
}

/// The signed distance of `p` from a neighbour's surface (positive on the side its outward normal points to), by
/// projecting onto the surface itself, so a neighbour that curves away from its tangent plane is not mistaken for an
/// overshoot. Falls back to the tangent plane at `end` when the projection or the face's location isn't usable.
double offset_from(const Spring &spring, const NeighbourEnd &end, const gp_Pnt &p) {
    TopLoc_Location location;
    const Handle(Geom_Surface) surface = BRep_Tool::Surface(spring.neighbour, location);
    if (!surface.IsNull()) {
        // The surface lives in the face's own frame: bring the point in, and the result back out.
        const gp_Trsf frame = location.Transformation();
        GeomAPI_ProjectPointOnSurf project(p.Transformed(frame.Inverted()), surface);
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
                return gp_Vec(on.Transformed(frame), p).Dot(n.Transformed(frame));
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
    const BRepAdaptor_Curve own_range(a.edge);
    for (std::size_t j = 0; j < built.sections.size(); ++j) {
        // A section past the spring's own end (built to be trimmed by the end face) lies outside the circular face.
        const bool inside = built.ta[j] >= own_range.FirstParameter() - 1e-9 && built.ta[j] <= own_range.LastParameter() + 1e-9;
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
        if (inside && ((!circular->IsUPeriodic() && (pu < umin - margin_u || pu > umax + margin_u)) ||
            (!circular->IsVPeriodic() && (pv < vmin - margin_v || pv > vmax + margin_v)))) {
            throw user_error(kStripMessage);
        }
        const gp_Pnt q = project.NearestPoint();
        const NeighbourEnd &ea = built.first_ends[j], &eb = built.second_ends[j];
        if (inside && (j == 0 || j + 1 == built.sections.size())) {
            // An end section is the strip's end edge, so the chord must cross the springs squarely; a slanted
            // run-out (a blend ending on a face at an angle) isn't a cross-section and isn't supported.
            const gp_Vec chord(ea.p, eb.p);
            if (std::abs(chord.Dot(ea.tangent)) > 0.15 * chord.Magnitude() * ea.tangent.Magnitude()) {
                throw user_error(kStripMessage);
            }
        }
        const double sa = offset_from(a, ea, q) < 0 ? -1 : 1;
        const double sb = offset_from(b, eb, q) < 0 ? -1 : 1;
        const double tolerance = 0.01 * ea.p.Distance(eb.p);
        for (int k = 0; k <= 16; ++k) {
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
    TopoDS_Face end_strip[2]; // the other strip, where the end is a mitre between two strips at an angle
    TopoDS_Face end_chain[2]; // the next strip of a tangent chain, where the end is their shared junction
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
                    out.end_strip[ends] = other; // a mitre: both strips are built past it and meet along their intersection
                } else {
                    out.end_chain[ends] = other;
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
    for (Spring &sp : out.spring) {
        BRepAdaptor_Curve c(sp.edge);
        sp.t_start = sp.flipped ? c.LastParameter() : c.FirstParameter();
        sp.t_end = sp.flipped ? c.FirstParameter() : c.LastParameter();
    }
    return out;
}

/// A strip end whose chord does not cross the springs squarely (the blend meets its end face at a slant) is built past
/// the end and trimmed by the end face. `a_end` and `b_end` are the springs' own end points, in sampling order.
struct Slant {
    bool slanted = false;
    gp_Pnt a_end, b_end;
};

/// Decides each sampling end and, for a slanted one, extends the shorter spring's sampling range past its end (by the
/// slant plus a margin) and the other's to the projection of that extended point, so the extended end is a square
/// cross-section again.
void plan_slants(StripEdges &edges, Slant slants[2]) {
    if (edges.closed) {
        return;
    }
    Spring *springs[2] = {&edges.spring[0], &edges.spring[1]};
    for (int e = 0; e < 2; ++e) {
        BRepAdaptor_Curve curves[2] = {BRepAdaptor_Curve(springs[0]->edge), BRepAdaptor_Curve(springs[1]->edge)};
        double te[2], outward[2];
        gp_Pnt point[2];
        gp_Vec tangent[2];
        for (int i = 0; i < 2; ++i) {
            const double direction = springs[i]->t_end > springs[i]->t_start ? 1 : -1;
            te[i] = e == 0 ? springs[i]->t_start : springs[i]->t_end;
            outward[i] = e == 0 ? -direction : direction;
            curves[i].D1(te[i], point[i], tangent[i]);
        }
        const gp_Vec chord(point[0], point[1]);
        gp_Vec out0 = tangent[0] * outward[0];
        out0.Normalize();
        const double m = chord.Dot(out0);
        // The end's edge, and whether it borders a face that is not a plane (a square end cannot lie on that: it is
        // built past the end and trimmed like a slanted one).
        const gp_Pnt middle((point[0].XYZ() + point[1].XYZ()) * 0.5);
        int nearest = 0;
        double nearest_gap = 1e300;
        for (int c = 0; c < 2; ++c) {
            BRepAdaptor_Curve oc(edges.ends[c]);
            const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
            if (d < nearest_gap) {
                nearest_gap = d;
                nearest = c;
            }
        }
        const bool curved_end = !edges.end_face[nearest].IsNull() &&
                                BRepAdaptor_Surface(edges.end_face[nearest], Standard_False).GetType() != GeomAbs_Plane;
        // A square section lies in the end face only if the springs run square to it: tilted by a hair, the section's
        // sag leaves the plane by more than the edge's tolerance (a drafted wall's edge meeting the base), so any
        // tilt is a slant.
        bool tilted_end = false;
        if (!edges.end_face[nearest].IsNull() && !curved_end) {
            const gp_Dir plane_normal = BRepAdaptor_Surface(edges.end_face[nearest], Standard_False).Plane().Axis().Direction();
            tilted_end = std::abs(gp_Vec(plane_normal).Dot(out0)) > 1e-6;
        }
        if (std::abs(m) <= 0.1 * chord.Magnitude() && !curved_end && !tilted_end) {
            continue;
        }
        // An end shared with a corner or the next strip of a chain is a section both must agree on; it stays square.
        if (edges.end_face[nearest].IsNull() && edges.end_strip[nearest].IsNull()) {
            continue;
        }
        slants[e].slanted = true;
        slants[e].a_end = point[0];
        slants[e].b_end = point[1];
        // The spring that ends first is extended; the other is extended to the projection of the first's new end.
        const int shorter = m > 0 ? 0 : 1, longer = 1 - shorter;
        const double length = 1.25 * std::abs(m) + 0.25 * chord.Magnitude();
        const double speed = std::max(tangent[shorter].Magnitude(), 1e-12);
        const double extended = te[shorter] + outward[shorter] * length / speed;
        const gp_Pnt target = curves[shorter].Value(extended);
        const double lo = std::min(springs[longer]->t_start, springs[longer]->t_end);
        const double hi = std::max(springs[longer]->t_start, springs[longer]->t_end);
        const double window = 0.5 * (hi - lo);
        Extrema_ExtPC ext(target, curves[longer], lo - window, hi + window);
        if (!ext.IsDone() || ext.NbExt() == 0) {
            throw user_error(kStripMessage);
        }
        int best = 1;
        for (int i = 2; i <= ext.NbExt(); ++i) {
            if (ext.SquareDistance(i) < ext.SquareDistance(best)) {
                best = i;
            }
        }
        double projected = ext.Point(best).Parameter();
        if (curves[longer].IsPeriodic()) {
            const double period = curves[longer].Period();
            projected += period * std::round((te[longer] - projected) / period);
        }
        if (outward[longer] * (projected - te[longer]) <= 0) {
            throw user_error(kStripMessage);
        }
        (e == 0 ? springs[shorter]->t_start : springs[shorter]->t_end) = extended;
        (e == 0 ? springs[longer]->t_start : springs[longer]->t_end) = projected;
    }
}

/// Folds the gaps at one sample of a seam into `seam`; `a` and `b` are the two faces there, `tangent` the edge's.
void accumulate(occt_g2_seam &seam, const SurfacePoint &a, const SurfacePoint &b, const gp_Vec &tangent,
                bool curvature = true) {
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
    if (!curvature) {
        return;
    }
    seam.curvature = std::max(seam.curvature, gap);
    if (gap / allowed >= seam.curvature_ratio) {
        seam.curvature_ratio = gap / allowed;
        seam.curvature_allowed = allowed;
    }
}

/// The worst position, angle and curvature gaps along `edge` between the two faces that share it.
occt_g2_seam measure_seam(const TopoDS_Edge &edge, const TopoDS_Face &f1, const TopoDS_Face &f2,
                          const bool exempt_ends[2] = nullptr) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(edge);
    for (int k = 0; k <= kMeasureSamples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / kMeasureSamples;
        gp_Pnt p;
        gp_Vec tangent;
        curve.D1(t, p, tangent);
        const bool near_start = exempt_ends && exempt_ends[0] && k <= kJunctionSamples;
        const bool near_end = exempt_ends && exempt_ends[1] && k >= kMeasureSamples - kJunctionSamples;
        accumulate(seam, surface_point(f1, edge, t), surface_point(f2, edge, t), tangent, !(near_start || near_end));
    }
    return seam;
}

/// The strip's gaps against one spring's neighbour, read off the candidate surface through the spring's pcurve before
/// any topology is built. `reversed`: the face is REVERSED, so its outward normal is the raw one's opposite.
bool within_tolerance(const occt_g2_seam &seam);

/// `fractions` are the sections' places along the strip; `intervals` gets, for each span between two sections, the
/// worst gap found in it as a multiple of the (halved) tolerances: more than 1 means the span needs a section.
occt_g2_seam candidate_seam(const Handle(Geom_BSplineSurface) &surface, bool reversed, const Spring &spring,
                            const Handle(Geom2d_Curve) &pcurve, const std::vector<double> &fractions,
                            std::vector<double> &intervals) {
    occt_g2_seam seam{};
    BRepAdaptor_Curve curve(spring.edge);
    const int samples = std::max(kCheckSamples, 4 * static_cast<int>(fractions.size()) + 3);
    intervals.assign(fractions.size() - 1, 0.0);
    for (int k = 0; k <= samples; ++k) {
        const double t = curve.FirstParameter() + (curve.LastParameter() - curve.FirstParameter()) * k / samples;
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
        occt_g2_seam here{};
        // The sampling start/end of the spring in parameter terms, for the junction exemption.
        const double length = std::abs(spring.t_end - spring.t_start);
        const bool near_start = spring.kinked[0] && std::abs(t - spring.t_start) < 0.0335 * length;
        const bool near_end = spring.kinked[1] && std::abs(t - spring.t_end) < 0.0335 * length;
        const bool compare_curvature = !(near_start || near_end);
        accumulate(here, strip, surface_point(spring.neighbour, spring.edge, t), tangent, compare_curvature);
        accumulate(seam, strip, surface_point(spring.neighbour, spring.edge, t), tangent, compare_curvature);
        const auto after = std::upper_bound(fractions.begin(), fractions.end(), uv.X());
        const std::size_t span = std::min<std::size_t>(std::max<std::ptrdiff_t>(after - fractions.begin() - 1, 0),
                                                       intervals.size() - 1);
        intervals[span] = std::max({intervals[span], here.position / 2e-5, here.angle_degrees / 0.005,
                                    here.curvature_ratio / 0.5});
    }
    return seam;
}

bool within_tolerance(const occt_g2_seam &seam) {
    // Half the promised tolerances, so the final measurement at other samples still has room.
    return seam.position <= 2e-5 && seam.angle_degrees <= 0.005 && seam.curvature_ratio <= 0.5;
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

// One build, with corner patches tried or not. A failure leaves `report` as far as it got (g2_corners says whether a
// patch had been committed).
static occt_shape *fillet_g2_run(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                                 bool use_patches, occt_history *history, occt_g2_report *report, occt_status *status) {
    return guarded(status, [&]() -> occt_shape * {
        *history = occt_history{};
        *report = occt_g2_report{};
        if (!shape || !edge_indices || count <= 0 || !std::isfinite(radius) || radius <= 0 || !std::isfinite(weight) || weight <= 0) {
            set_error(status, "a blend needs edges, a size and a tangency weight greater than 0");
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
        // OCCT propagates a fillet along the tangent chain of each selected edge, so the strips (and corners) are
        // those of every edge of every contour, not only of the selected ones. History keeps the selected edges' only.
        auto add_blend_faces = [&](const TopoDS_Edge &edge) {
            for (TopTools_ListOfShape::Iterator it(algo.Generated(edge)); it.More(); it.Next()) {
                strip_indices.push_back(g1_faces.FindIndex(it.Value()));
            }
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    for (TopTools_ListOfShape::Iterator it(algo.Generated(vertex)); it.More(); it.Next()) {
                        corner_indices.push_back(g1_faces.FindIndex(it.Value()));
                    }
                }
            }
        };
        for (int i = 0; i < count; ++i) {
            const TopoDS_Edge edge = TopoDS::Edge(input_edges(edge_indices[i]));
            records.add_all(algo.Generated(edge), OCCT_FROM_EDGE, 0, edge_indices[i]);
            TopoDS_Vertex first, last;
            TopExp::Vertices(edge, first, last);
            for (const TopoDS_Vertex &vertex : {first, last}) {
                if (!vertex.IsNull()) {
                    records.add_all(algo.Generated(vertex), OCCT_FROM_EDGE, 0, edge_indices[i]);
                }
            }
        }
        for (int contour = 1; contour <= algo.NbContours(); ++contour) {
            for (int j = 1; j <= algo.NbEdges(contour); ++j) {
                add_blend_faces(algo.Edge(contour, j));
            }
        }

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
        std::vector<TopoDS_Edge> kinked_joins;
        // Tangent chains: where two strips of a chain meet, the springs on one face may kink (a drafted cone meeting a
        // plane): both strips take the bisector of the two springs' tangents there, so they share one section.
        {
            auto outward_tangent = [](const Spring &spring, int end, gp_Pnt &point) {
                BRepAdaptor_Curve curve(spring.edge);
                const double direction = spring.t_end > spring.t_start ? 1 : -1;
                const double t = end == 0 ? spring.t_start : spring.t_end;
                gp_Vec tangent;
                curve.D1(t, point, tangent);
                tangent.Normalize();
                return tangent * (end == 0 ? -direction : direction);
            };
            for (std::size_t s = 0; s < strips.size(); ++s) {
                if (strips[s].closed) {
                    continue;
                }
                for (int end = 0; end < 2; ++end) {
                    for (int i = 0; i < 2; ++i) {
                        Spring &mine = strips[s].spring[i];
                        gp_Pnt point;
                        const gp_Vec outward = outward_tangent(mine, end, point);
                        for (std::size_t t = 0; t < strips.size(); ++t) {
                            if (t == s || strips[t].closed) {
                                continue;
                            }
                            bool chained = false;
                            for (int c = 0; c < 2; ++c) {
                                chained = chained || strips[s].end_chain[c].IsSame(strip_faces[t]);
                            }
                            if (!chained) {
                                continue;
                            }
                            for (Spring &other : strips[t].spring) {
                                for (int other_end = 0; other_end < 2; ++other_end) {
                                    gp_Pnt other_point;
                                    const gp_Vec other_outward = outward_tangent(other, other_end, other_point);
                                    if (other_point.Distance(point) > 1e-6 || outward.Dot(other_outward) > 0) {
                                        continue;
                                    }
                                    gp_Vec bisector = outward - other_outward;
                                    if (bisector.Magnitude() < 1e-9) {
                                        continue;
                                    }
                                    bisector.Normalize();
                                    const double kink = std::acos(std::clamp(-outward.Dot(other_outward), -1.0, 1.0)) * 180 / kPi;
                                    if (kink > 0.01) {
                                        mine.kinked[end] = true;
                                        other.kinked[other_end] = true;
                                        for (int c = 0; c < 2; ++c) {
                                            bool known = false;
                                            for (const TopoDS_Edge &join : kinked_joins) {
                                                known = known || join.IsSame(strips[s].ends[c]);
                                            }
                                            if (strips[s].end_chain[c].IsSame(strip_faces[t]) && !known) {
                                                kinked_joins.push_back(strips[s].ends[c]);
                                            }
                                        }
                                    }
                                    mine.has_tangent[end] = true;
                                    mine.junction_tangent[end] = bisector;
                                    other.has_tangent[other_end] = true;
                                    other.junction_tangent[other_end] = bisector;
                                }
                            }
                        }
                    }
                }
            }
        }
        report->g1_joins = static_cast<int>(kinked_joins.size());
        struct Replaced {
            TopoDS_Edge old_edge, new_edge;
            TopoDS_Face strip;
        };
        std::vector<Replaced> replaced;
        std::vector<TopoDS_Edge> mitre_edges;
        std::vector<bool> corner_done(corner_faces.size(), false);
        std::vector<TopoDS_Face> g2_new_faces;
        std::vector<std::vector<TopoDS_Face>> corner_patches(corner_faces.size()); // the faces a replaced corner became
        std::vector<TopoDS_Edge> g2_edges;
        // The edge where a strip, built past its end, meets that end's face (or the partner strip at a mitre): the
        // surfaces' intersection between the two springs' own end points, with pcurves on both and the old vertices.
        auto trim_edge = [&](const TopoDS_Edge &old_edge, const Handle(Geom_Surface) &surface,
                             const Handle(Geom_Surface) &face_surface, const TopLoc_Location &face_location, const gp_Pnt &a_end,
                             const gp_Pnt &b_end, bool &flip) -> TopoDS_Edge {
            if (face_surface.IsNull()) {
                throw user_error(kStripMessage);
            }
            // The intersection runs in global coordinates; the face keeps its own frame and location.
            const Handle(Geom_Surface) global_face_surface =
                face_location.IsIdentity() ? face_surface
                                           : Handle(Geom_Surface)::DownCast(face_surface->Transformed(face_location.Transformation()));
            GeomInt_IntSS intersection(surface, global_face_surface, 1e-7, Standard_True, Standard_True, Standard_True);
            int line = 0;
            double best_gap = 1e-4, pa = 0, pb = 0;
            // The parameter and distance of the point on a line: the projection, else (a point at the very end of
            // the curve, which the projection may miss by a hair) the nearer end.
            auto locate = [](const Handle(Geom_Curve) &candidate, const gp_Pnt &point, double &parameter) {
                GeomAPI_ProjectPointOnCurve project(point, candidate);
                double distance = 1e300;
                if (project.NbPoints() > 0) {
                    parameter = project.LowerDistanceParameter();
                    distance = project.LowerDistance();
                }
                for (double end : {candidate->FirstParameter(), candidate->LastParameter()}) {
                    const double d = candidate->Value(end).Distance(point);
                    if (d < distance) {
                        distance = d;
                        parameter = end;
                    }
                }
                return distance;
            };
            for (int i = 1; i <= intersection.NbLines(); ++i) {
                const Handle(Geom_Curve) candidate = intersection.Line(i);
                double ta = 0, tb = 0;
                const double gap = locate(candidate, a_end, ta) + locate(candidate, b_end, tb);
                if (gap < best_gap) {
                    best_gap = gap;
                    line = i;
                    pa = ta;
                    pb = tb;
                }
            }
            if (line == 0 || std::abs(pa - pb) < 1e-9) {
                throw user_error(kStripMessage);
            }
            const Handle(Geom_Curve) curve = intersection.Line(line);
            const double lo = std::min(pa, pb), hi = std::max(pa, pb);
            TopoDS_Vertex v1, v2;
            TopExp::Vertices(old_edge, v1, v2, Standard_False);
            const bool first_is_v1 = BRep_Tool::Pnt(v1).Distance(curve->Value(lo)) <= BRep_Tool::Pnt(v2).Distance(curve->Value(lo));
            // The intersection runs through the springs' end points to within its own accuracy: the vertices take that
            // gap as tolerance. Up to the position promise (1e-4 mm) is accepted; a larger one is not a trimmed end of
            // this strip.
            const TopoDS_Vertex &vertex_lo = first_is_v1 ? v1 : v2, &vertex_hi = first_is_v1 ? v2 : v1;
            const double gap_lo = BRep_Tool::Pnt(vertex_lo).Distance(curve->Value(lo));
            const double gap_hi = BRep_Tool::Pnt(vertex_hi).Distance(curve->Value(hi));
            if (std::max(gap_lo, gap_hi) > 1e-4) {
                throw user_error(kStripMessage);
            }
            builder.UpdateVertex(vertex_lo, std::max(BRep_Tool::Tolerance(vertex_lo), gap_lo));
            builder.UpdateVertex(vertex_hi, std::max(BRep_Tool::Tolerance(vertex_hi), gap_hi));
            TopoDS_Edge ne;
            builder.MakeEdge(ne, curve, 1e-5);
            builder.Add(ne, vertex_lo.Oriented(TopAbs_FORWARD));
            builder.Add(ne, vertex_hi.Oriented(TopAbs_REVERSED));
            builder.Range(ne, lo, hi);
            Handle(Geom2d_Curve) on_strip = intersection.HasLineOnS1(line) ? intersection.LineOnS1(line)
                                                                             : GeomProjLib::Curve2d(curve, lo, hi, surface);
            Handle(Geom2d_Curve) on_face = intersection.HasLineOnS2(line) ? intersection.LineOnS2(line)
                                                                           : GeomProjLib::Curve2d(curve, lo, hi, global_face_surface);
            if (on_strip.IsNull() || on_face.IsNull()) {
                throw user_error(kStripMessage);
            }
            builder.UpdateEdge(ne, on_strip, surface, TopLoc_Location(), 1e-5);
            builder.Range(ne, surface, TopLoc_Location(), lo, hi);
            builder.UpdateEdge(ne, on_face, face_surface, face_location, 1e-5);
            builder.Range(ne, face_surface, face_location, lo, hi);
            flip = !first_is_v1;
            return ne;
        };
        // Every strip is built first (so that two strips meeting at a mitre can be cut by each other), then the
        // mitres, then each strip's end edges and face.
        struct StripState {
            Slant slants[2];
            BuiltStrip built;
            bool swapped = false;
            TopoDS_Edge new_ends[2];
            bool flip_end[2] = {false, false}; // the new end edge runs the other way from the old one
            double spring_gap[2] = {0, 0};      // the strip's worst distance from each spring, as measured
            std::vector<std::pair<TopoDS_Edge, bool>> chain[2]; // an end that borders a G2 corner: its half edges
        };
        std::vector<StripState> states(strips.size());
        for (std::size_t s = 0; s < strips.size(); ++s) {
            const TopoDS_Face old_face = strip_faces[s];
            const Handle(Geom_Surface) circular = BRep_Tool::Surface(old_face);
            StripEdges &edges = strips[s];
            StripState &state = states[s];
            Slant(&slants)[2] = state.slants;
            plan_slants(edges, slants);
            BuiltStrip &built = state.built;
            bool &swapped = state.swapped;
            // Sections start at 9 and are added where the candidate's seams miss the (halved) tolerances: a span
            // that fails gets its middle (a closed strip doubles all of them). At 129 sections the blend fails.
            std::vector<double> fractions(kFirstSections);
            for (int j = 0; j < kFirstSections; ++j) {
                fractions[j] = static_cast<double>(j) / (kFirstSections - 1);
            }
            for (;;) {
                swapped = false;
                for (int attempt = 0; attempt < 2; ++attempt) {
                    built = build_strip(edges.spring[swapped ? 1 : 0], edges.spring[swapped ? 0 : 1], weight, fractions,
                                        edges.closed);
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
                std::vector<double> first_spans, second_spans;
                const occt_g2_seam first_seam = candidate_seam(
                    built.surface, reversed, edges.spring[swapped ? 1 : 0], built.pcurve[0], fractions, first_spans);
                const occt_g2_seam second_seam = candidate_seam(
                    built.surface, reversed, edges.spring[swapped ? 0 : 1], built.pcurve[1], fractions, second_spans);
                const bool passes = within_tolerance(first_seam) && within_tolerance(second_seam);
                if (passes) {
                    // The springs keep their own curves: their tolerance covers what the strip's boundary misses.
                    state.spring_gap[0] = first_seam.position;
                    state.spring_gap[1] = second_seam.position;
                    break;
                }
                if (static_cast<int>(fractions.size()) >= kMaxSections) {
                    throw user_error(kStripMessage);
                }
                // A failing span gets its middle; a span too narrow to halve again means the error is not one more
                // sections can remove.
                std::vector<bool> split(fractions.size() - 1, edges.closed);
                for (std::size_t j = 0; j + 1 < fractions.size(); ++j) {
                    if (first_spans[j] > 1 || second_spans[j] > 1) {
                        if (fractions[j + 1] - fractions[j] < 1e-5) {
                            throw user_error(kStripMessage);
                        }
                        split[j] = true;
                    }
                }
                std::vector<double> refined;
                for (std::size_t j = 0; j < fractions.size(); ++j) {
                    refined.push_back(fractions[j]);
                    if (j + 1 < fractions.size() && split[j]) {
                        refined.push_back(0.5 * (fractions[j] + fractions[j + 1]));
                    }
                }
                if (refined.size() == fractions.size()) {
                    // Nothing in a span failed (the gap is at a section): halve everything.
                    refined.clear();
                    for (std::size_t j = 0; j < fractions.size(); ++j) {
                        refined.push_back(fractions[j]);
                        if (j + 1 < fractions.size()) {
                            refined.push_back(0.5 * (fractions[j] + fractions[j + 1]));
                        }
                    }
                }
                if (static_cast<int>(refined.size()) > kMaxSections) {
                    throw user_error(kStripMessage);
                }
                fractions = refined;
            }
            const int sections = static_cast<int>(fractions.size());
            report->sections = std::max(report->sections, sections);
            if (s < 32) {
                report->strip_sections[s] = sections;
            }
            // Spring edges: the pcurve on the new surface.
            const Handle(Geom_Surface) surface = built.surface;
            for (int side = 0; side < 2; ++side) {
                const Spring &spring = edges.spring[(side == 0) != swapped ? 0 : 1];
                builder.UpdateEdge(spring.edge, built.pcurve[side], surface, TopLoc_Location(),
                                   std::max(kEdgeTolerance, 1.5 * state.spring_gap[side]));
                double own_first = 0, own_last = 0;
                BRep_Tool::Range(spring.edge, own_first, own_last);
                builder.Range(spring.edge, surface, TopLoc_Location(), own_first, own_last);
            }

        }

        // Mitres: two strips that meet at an angle are each built past their shared end and cut by one another;
        // the new shared edge is their intersection, between the vertices of the old one.
        for (std::size_t s = 0; s < strips.size(); ++s) {
            for (int end = 0; end < 2; ++end) {
                StripEdges &edges = strips[s];
                if (edges.closed || !states[s].slants[end].slanted) {
                    continue;
                }
                const Slant &slant = states[s].slants[end];
                const gp_Pnt middle((slant.a_end.XYZ() + slant.b_end.XYZ()) * 0.5);
                int chosen = 0;
                double best = 1e300;
                for (int c = 0; c < 2; ++c) {
                    BRepAdaptor_Curve oc(edges.ends[c]);
                    const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
                    if (d < best) {
                        best = d;
                        chosen = c;
                    }
                }
                if (edges.end_strip[chosen].IsNull() || !states[s].new_ends[chosen].IsNull()) {
                    continue;
                }
                std::size_t partner = strips.size();
                for (std::size_t t = 0; t < strips.size(); ++t) {
                    if (strip_faces[t].IsSame(edges.end_strip[chosen])) {
                        partner = t;
                    }
                }
                if (partner == strips.size() || partner == s) {
                    throw user_error(kStripMessage);
                }
                // The partner's matching end: its end edge that is this very (old) edge.
                const TopoDS_Edge old_edge = edges.ends[chosen];
                int partner_chosen = -1;
                for (int c = 0; c < 2; ++c) {
                    if (strips[partner].ends[c].IsSame(old_edge)) {
                        partner_chosen = c;
                    }
                }
                bool partner_extended = false;
                for (int e2 = 0; e2 < 2; ++e2) {
                    partner_extended = partner_extended || states[partner].slants[e2].slanted;
                }
                if (partner_chosen < 0 || !partner_extended) {
                    throw user_error(kStripMessage);
                }
                bool flip = false;
                const TopoDS_Edge ne = trim_edge(old_edge, states[s].built.surface, states[partner].built.surface,
                                                 TopLoc_Location(), slant.a_end, slant.b_end, flip);
                const TopAbs_Orientation oriented = flip ? TopAbs::Reverse(old_edge.Orientation()) : old_edge.Orientation();
                reshape.Replace(old_edge, ne.Oriented(oriented));
                replaced.push_back({old_edge, ne, TopoDS_Face()});
                states[s].new_ends[chosen] = ne;
                states[s].flip_end[chosen] = flip;
                states[partner].new_ends[partner_chosen] = ne;
                states[partner].flip_end[partner_chosen] = flip;
                mitre_edges.push_back(ne);
                ++report->mitres;
            }
        }

        // G2 corner patches. A corner whose three edges are all strip ends is replaced by one three-sided Bezier patch
        // (cocct_g2_triangle.hpp) that joins the three strips G2. A corner the patch is not accepted for (see below)
        // is left to the G1 refill after this loop.
        for (std::size_t ci = 0; ci < corner_faces.size() && use_patches; ++ci) {
            const TopoDS_Face old_corner = corner_faces[ci];
            try {
                struct EndCurve {
                    std::size_t strip = 0;
                    int end = 0;
                    TopoDS_Edge old_edge;
                    std::array<g2::Vec, 6> poles{};       // oriented V_j -> V_{j+1}
                    std::array<g2::Vec, 6> cross1{}, cross2{}; // cross-boundary derivatives, oriented alike
                    bool reversed = false;                 // against the strip's v
                    TopoDS_Vertex from, to;
                };
                std::vector<EndCurve> found;
                for (TopExp_Explorer it(old_corner, TopAbs_EDGE); it.More(); it.Next()) {
                    const TopoDS_Edge e = TopoDS::Edge(it.Current());
                    if (BRep_Tool::Degenerated(e)) {
                        continue;
                    }
                    bool known = false;
                    for (const EndCurve &c : found) {
                        known = known || c.old_edge.IsSame(e);
                    }
                    if (known) {
                        continue;
                    }
                    BRepAdaptor_Curve ec(e);
                    const gp_Pnt mid = ec.Value(0.5 * (ec.FirstParameter() + ec.LastParameter()));
                    EndCurve curve;
                    curve.old_edge = e;
                    double best = 1e300;
                    for (std::size_t s = 0; s < strips.size(); ++s) {
                        bool owns = false;
                        for (int c = 0; c < 2; ++c) {
                            owns = owns || (strips[s].ends[c].IsSame(e) && strips[s].end_face[c].IsNull() &&
                                            strips[s].end_strip[c].IsNull() && strips[s].end_chain[c].IsNull());
                        }
                        if (!owns || strips[s].closed) {
                            continue;
                        }
                        for (int end = 0; end < 2; ++end) {
                            if (states[s].slants[end].slanted) {
                                continue;
                            }
                            const auto &section = end == 0 ? states[s].built.sections.front() : states[s].built.sections.back();
                            g2::Vec at;
                            g2::Vec d1, d2;
                            g2::evaluate(section, 0.5, at, d1, d2);
                            const double d = gp_Pnt(at[0], at[1], at[2]).Distance(mid);
                            if (d < best) {
                                best = d;
                                curve.strip = s;
                                curve.end = end;
                            }
                        }
                    }
                    if (best > 0.5 * radius) {
                        throw user_error(kStripMessage);
                    }
                    found.push_back(curve);
                }
                if (found.size() != 3) {
                    throw user_error(kStripMessage);
                }
                // Cross-boundary data from each strip's surface at its end.
                for (EndCurve &curve : found) {
                    const BuiltStrip &built = states[curve.strip].built;
                    const auto &section = curve.end == 0 ? built.sections.front() : built.sections.back();
                    const double u_end = curve.end == 0 ? 0.0 : 1.0;
                    const double sigma = curve.end == 0 ? -1.0 : 1.0;
                    std::array<g2::Vec, 6> d1s{}, d2s{};
                    for (int j = 0; j < 6; ++j) {
                        gp_Pnt p;
                        gp_Vec su, sv, suu, svv, suv;
                        built.surface->D2(u_end, j / 5.0, p, su, sv, suu, svv, suv);
                        d1s[j] = {sigma * su.X(), sigma * su.Y(), sigma * su.Z()};
                        d2s[j] = {suu.X(), suu.Y(), suu.Z()};
                    }
                    curve.poles = section;
                    curve.cross1 = g2::bezier_through(d1s);
                    curve.cross2 = g2::bezier_through(d2s);
                }
                // Order the three curves into a loop V_0 -> V_1 -> V_2 -> V_0, each oriented along it.
                auto close = [](const g2::Vec &a, const g2::Vec &b) { return g2::norm(g2::sub(a, b)) < 1e-6; };
                std::vector<EndCurve> loop;
                loop.push_back(found[0]);
                std::vector<bool> used(3, false);
                used[0] = true;
                while (loop.size() < 3) {
                    bool advanced = false;
                    for (std::size_t k = 1; k < 3 && !advanced; ++k) {
                        if (used[k]) {
                            continue;
                        }
                        EndCurve next = found[k];
                        const g2::Vec tail = loop.back().poles[5];
                        if (close(next.poles[0], tail)) {
                            next.reversed = false;
                        } else if (close(next.poles[5], tail)) {
                            next.reversed = true;
                            std::reverse(next.poles.begin(), next.poles.end());
                            std::reverse(next.cross1.begin(), next.cross1.end());
                            std::reverse(next.cross2.begin(), next.cross2.end());
                        } else {
                            continue;
                        }
                        loop.push_back(next);
                        used[k] = true;
                        advanced = true;
                    }
                    if (!advanced) {
                        throw user_error(kStripMessage);
                    }
                }
                if (!close(loop[2].poles[5], loop[0].poles[0])) {
                    throw user_error(kStripMessage);
                }
                for (EndCurve &curve : loop) {
                    TopoDS_Vertex v1, v2;
                    TopExp::Vertices(curve.old_edge, v1, v2, Standard_False);
                    const bool first_is_start = close(curve.poles[0], {BRep_Tool::Pnt(v1).X(), BRep_Tool::Pnt(v1).Y(), BRep_Tool::Pnt(v1).Z()});
                    curve.from = first_is_start ? v1 : v2;
                    curve.to = first_is_start ? v2 : v1;
                }
                ++report->corner_attempts;
                const auto clock0 = std::chrono::steady_clock::now();
                g2::TriangleSide tri_sides[3];
                for (int j = 0; j < 3; ++j) {
                    tri_sides[j].poles = loop[j].poles;
                    tri_sides[j].cross1 = loop[j].cross1;
                    tri_sides[j].cross2 = loop[j].cross2;
                }
                // 1. The across scales: each strip's cross-boundary derivative must be the neighbouring end curve's tangent.
                double direction_cosine = 0;
                if (!g2::across_scales(tri_sides, direction_cosine) || direction_cosine < 0.999999) {
                    throw user_error(kStripMessage);
                }
                g2::TriangleNet tri_net;
                g2::TriangleStats stats;
                if (!g2::build_triangle(tri_sides, tri_net, stats)) {
                    throw user_error(kStripMessage);
                }
                // 2. lambda > 0 over every side (the reparametrisation is monotone) and the shared blocks agree.
                if (!(stats.min_lambda > 0) || !(stats.block_mismatch <= 1e-6)) {
                    throw user_error(kStripMessage);
                }
                const int n = g2::kTriangleDegree;
                const std::vector<g2::Vec> tensor = g2::to_tensor(tri_net);
                TColgp_Array2OfPnt tri_poles(1, n + 1, 1, n + 1);
                for (int a = 0; a <= n; ++a) {
                    for (int b = 0; b <= n; ++b) {
                        const g2::Vec &v = tensor[static_cast<std::size_t>(a) * (n + 1) + b];
                        tri_poles.SetValue(a + 1, b + 1, gp_Pnt(v[0], v[1], v[2]));
                    }
                }
                const Handle(Geom_BezierSurface) tri_surface = new Geom_BezierSurface(tri_poles);
                // 3. Regularity: a defined normal and principal curvatures within 4 / r over the interior and near the corners.
                double min_sine = 1e300, max_interior = 0;
                {
                    auto sample = [&](double x, double y, bool interior) {
                        gp_Pnt p;
                        gp_Vec su, sv, suu, svv, suv;
                        tri_surface->D2(std::min(1.0, std::max(0.0, x)), std::min(1.0, std::max(0.0, y)), p, su, sv, suu, svv, suv);
                        const gp_Vec nv = su.Crossed(sv);
                        const double area = nv.Magnitude();
                        const double e = su.Dot(su), f = su.Dot(sv), g = sv.Dot(sv);
                        min_sine = std::min(min_sine, area / std::sqrt(e * g));
                        if (area < 1e-14) {
                            throw user_error(kStripMessage);
                        }
                        if (!interior) {
                            return;
                        }
                        const gp_Vec nn = nv / area;
                        const double l = suu.Dot(nn), m = suv.Dot(nn), nq = svv.Dot(nn);
                        const double det = e * g - f * f;
                        const double kg = (l * nq - m * m) / det;
                        const double hm = (e * nq - 2 * f * m + g * l) / (2 * det);
                        const double disc = std::sqrt(std::max(0.0, hm * hm - kg));
                        max_interior = std::max(max_interior, std::max(std::abs(hm + disc), std::abs(hm - disc)));
                    };
                    const int grid = 80;
                    for (int a = 0; a <= grid; ++a) {
                        for (int b = 0; a + b <= grid; ++b) {
                            sample(static_cast<double>(a) / grid, static_cast<double>(b) / grid, a > 0 && b > 0 && a + b < grid);
                        }
                    }
                    for (double d : {1e-1, 3e-2, 1e-2, 1e-3, 1e-4}) {
                        sample(d, d, true);
                        sample(1 - 2 * d, d, true);
                        sample(d, 1 - 2 * d, true);
                        sample(d, 0, false);
                        sample(0, d, false);
                        sample(1 - d, d, false);
                        sample(1 - d, 0, false);
                        sample(d, 1 - d, false);
                        sample(0, 1 - d, false);
                    }
                }
                if (!(min_sine > 0.05) || !(max_interior <= 4.0 / radius)) {
                    throw user_error(kStripMessage); // the patch is not regular enough
                }
                const gp_Pnt2d domain[3] = {gp_Pnt2d(0, 0), gp_Pnt2d(1, 0), gp_Pnt2d(0, 1)};
                // 4. The seams against the three strips, before anything is committed: the half of the promised tolerances
                //    that strips are held to.
                {
                    auto on_surface = [](const Handle(Geom_Surface) &surface, const gp_Pnt2d &uv, bool reversed) {
                        SurfacePoint point;
                        surface->D2(uv.X(), uv.Y(), point.p, point.su, point.sv, point.suu, point.svv, point.suv);
                        point.n = point.su.Crossed(point.sv);
                        point.n.Normalize();
                        if (reversed) {
                            point.n.Reverse();
                        }
                        return point;
                    };
                    // The patch's outward side is the circular corner's, as for the face built below.
                    bool tri_reversed = false;
                    {
                        gp_Pnt middle;
                        gp_Vec da, db;
                        tri_surface->D1(1.0 / 3, 1.0 / 3, middle, da, db);
                        GeomAPI_ProjectPointOnSurf project(middle, BRep_Tool::Surface(old_corner));
                        double pu = 0, pv = 0;
                        project.LowerDistanceParameters(pu, pv);
                        gp_Pnt on_old;
                        gp_Vec oa, ob;
                        BRep_Tool::Surface(old_corner)->D1(pu, pv, on_old, oa, ob);
                        gp_Vec n_old = oa.Crossed(ob);
                        if (old_corner.Orientation() == TopAbs_REVERSED) {
                            n_old.Reverse();
                        }
                        tri_reversed = da.Crossed(db).Dot(n_old) < 0;
                    }
                    for (int j = 0; j < 3; ++j) {
                        const EndCurve &curve = loop[j];
                        const double u_end = curve.end == 0 ? 0.0 : 1.0;
                        const bool strip_reversed = strip_faces[curve.strip].Orientation() == TopAbs_REVERSED;
                        occt_g2_seam seam{};
                        for (int k = 0; k <= kMeasureSamples; ++k) {
                            const double t = static_cast<double>(k) / kMeasureSamples;
                            const double v = curve.reversed ? 1 - t : t;
                            const gp_Pnt2d uv_tri(domain[j].X() + t * (domain[(j + 1) % 3].X() - domain[j].X()),
                                                  domain[j].Y() + t * (domain[(j + 1) % 3].Y() - domain[j].Y()));
                            const g2::Vec tangent_vector = g2::bezier_derivative(curve.poles, t);
                            gp_Vec tangent = to_vec(tangent_vector);
                            if (tangent.Magnitude() < 1e-12) {
                                throw user_error(kStripMessage);
                            }
                            accumulate(seam, on_surface(states[curve.strip].built.surface, gp_Pnt2d(u_end, v), strip_reversed),
                                       on_surface(tri_surface, uv_tri, tri_reversed), tangent);
                        }
                        if (!within_tolerance(seam)) {
                            throw user_error(kStripMessage);
                        }
                    }
                }
                TopoDS_Edge tri_edges[3];
                for (int j = 0; j < 3; ++j) {
                    TColgp_Array1OfPnt end_poles(1, 6);
                    for (int i = 0; i < 6; ++i) {
                        end_poles.SetValue(i + 1, gp_Pnt(loop[j].poles[i][0], loop[j].poles[i][1], loop[j].poles[i][2]));
                    }
                    builder.MakeEdge(tri_edges[j], Handle(Geom_BezierCurve)(new Geom_BezierCurve(end_poles)), kEdgeTolerance);
                    builder.Add(tri_edges[j], loop[j].from.Oriented(TopAbs_FORWARD));
                    builder.Add(tri_edges[j], loop[j].to.Oriented(TopAbs_REVERSED));
                    builder.Range(tri_edges[j], 0, 1);
                    const EndCurve &curve = loop[j];
                    const double u_end = curve.end == 0 ? 0.0 : 1.0;
                    const double v_start = curve.reversed ? 1.0 : 0.0, v_end = curve.reversed ? 0.0 : 1.0;
                    builder.UpdateEdge(tri_edges[j], line2d(gp_Pnt2d(u_end, v_start), gp_Pnt2d(u_end, v_end), 0, 1),
                                       states[curve.strip].built.surface, TopLoc_Location(), kEdgeTolerance);
                    builder.UpdateEdge(tri_edges[j], line2d(domain[j], domain[(j + 1) % 3], 0, 1), tri_surface, TopLoc_Location(),
                                       kEdgeTolerance);
                }
                TopoDS_Face tri_face;
                builder.MakeFace(tri_face, tri_surface, kEdgeTolerance);
                TopoDS_Wire tri_wire;
                builder.MakeWire(tri_wire);
                for (int j = 0; j < 3; ++j) {
                    builder.Add(tri_wire, tri_edges[j].Oriented(TopAbs_FORWARD));
                }
                builder.Add(tri_face, tri_wire);
                {
                    gp_Pnt middle;
                    gp_Vec da, db;
                    tri_surface->D1(1.0 / 3, 1.0 / 3, middle, da, db);
                    GeomAPI_ProjectPointOnSurf project(middle, BRep_Tool::Surface(old_corner));
                    double pu = 0, pv = 0;
                    project.LowerDistanceParameters(pu, pv);
                    gp_Pnt on_old;
                    gp_Vec oa, ob;
                    BRep_Tool::Surface(old_corner)->D1(pu, pv, on_old, oa, ob);
                    gp_Vec n_old = oa.Crossed(ob);
                    if (old_corner.Orientation() == TopAbs_REVERSED) {
                        n_old.Reverse();
                    }
                    if (da.Crossed(db).Dot(n_old) < 0) {
                        tri_face.Orientation(TopAbs_REVERSED);
                    }
                }
                // Commit: the strips' end edges become the patch's sides, the old corner goes, the patch comes.
                for (int j = 0; j < 3; ++j) {
                    const EndCurve &curve = loop[j];
                    StripState &state = states[curve.strip];
                    TopoDS_Vertex old_first, old_last;
                    TopExp::Vertices(curve.old_edge, old_first, old_last, Standard_False);
                    const bool old_runs_with_loop = old_first.IsSame(curve.from);
                    for (int c = 0; c < 2; ++c) {
                        if (strips[curve.strip].ends[c].IsSame(curve.old_edge)) {
                            state.chain[c] = {{tri_edges[j], !old_runs_with_loop}};
                        }
                    }
                }
                reshape.Remove(old_corner);
                g2_new_faces.push_back(tri_face);
                corner_patches[ci].push_back(tri_face);
                for (int j = 0; j < 3; ++j) {
                    g2_edges.push_back(tri_edges[j]);
                }
                corner_done[ci] = true;
                ++report->g2_corners;
                ++report->corners;
                report->corner_milliseconds +=
                    std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - clock0).count();
                report->corner_block_mismatch = std::max(report->corner_block_mismatch, stats.block_mismatch);
                report->corner_min_lambda = report->g2_corners == 1 ? stats.min_lambda : std::min(report->corner_min_lambda, stats.min_lambda);
                report->corner_max_curvature = std::max(report->corner_max_curvature, max_interior);
                report->corner_min_sine = report->g2_corners == 1 ? min_sine : std::min(report->corner_min_sine, min_sine);
            } catch (const std::exception &) {
                // The G1 refill takes this corner.
            } catch (const Standard_Failure &) {
            }
        }

        for (std::size_t s = 0; s < strips.size(); ++s) {
            const TopoDS_Face old_face = strip_faces[s];
            StripEdges &edges = strips[s];
            StripState &state = states[s];
            Slant(&slants)[2] = state.slants;
            const BuiltStrip &built = state.built;
            const bool swapped = state.swapped;
            const Handle(Geom_Surface) surface = built.surface;
            TopoDS_Edge(&new_ends)[2] = state.new_ends;
            bool(&flip_end)[2] = state.flip_end;
            (void)swapped;
            // End edges become the first and last sections (shared with the next strip of a tangent chain).
            TopoDS_Edge seam_edge;       // a closed strip's one seam, both ends
            bool seam_reversed = false;
            for (int end = 0; end < (edges.closed ? 1 : 2); ++end) {
                if (slants[end].slanted) {
                    // A slanted end: the strip was built past the end face; its end edge is the surface's
                    // intersection with that face, between the springs' own end points.
                    const gp_Pnt a_end = slants[end].a_end, b_end = slants[end].b_end;
                    const gp_Pnt middle((a_end.XYZ() + b_end.XYZ()) * 0.5);
                    int chosen = 0;
                    double best = 1e300;
                    for (int c = 0; c < 2; ++c) {
                        BRepAdaptor_Curve oc(edges.ends[c]);
                        const double d = oc.Value(0.5 * (oc.FirstParameter() + oc.LastParameter())).Distance(middle);
                        if (d < best) {
                            best = d;
                            chosen = c;
                        }
                    }
                    if (!new_ends[chosen].IsNull()) {
                        continue; // a mitre, made with the partner strip
                    }
                    const TopoDS_Edge old_edge = edges.ends[chosen];
                    const TopoDS_Face end_face = edges.end_face[chosen];
                    TopLoc_Location face_location;
                    const Handle(Geom_Surface) face_surface = end_face.IsNull() ? Handle(Geom_Surface)()
                                                                                : BRep_Tool::Surface(end_face, face_location);
                    if (face_surface.IsNull()) {
                        throw user_error(kStripMessage);
                    }
                    TopoDS_Edge ne = trim_edge(old_edge, surface, face_surface, face_location, a_end, b_end, flip_end[chosen]);
                    const TopAbs_Orientation oriented = flip_end[chosen] ? TopAbs::Reverse(old_edge.Orientation()) : old_edge.Orientation();
                    reshape.Replace(old_edge, ne.Oriented(oriented));
                    replaced.push_back({old_edge, ne, TopoDS_Face()});
                    new_ends[chosen] = ne;
                    continue;
                }
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
                if (!state.chain[chosen].empty()) {
                    continue; // an end on a G2 corner: its two half edges stand in for it
                }
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
                    // The shared section is this strip's own, up to what the two neighbours' surfaces differ by at
                    // the junction (they agree on the spring tangent; a strip-to-strip seam is promised its
                    // position only): within 1e-4 mm, with the edge's tolerance covering the difference.
                    double deviation = 0;
                    for (int k = 0; k <= 16; ++k) {
                        const double t = k / 16.0;
                        deviation = std::max(deviation, nc.Value(t).Distance(bezier->Value(reversed ? 1 - t : t)));
                    }
                    if (deviation > 1e-4) {
                        throw user_error(kStripMessage);
                    }
                    builder.UpdateEdge(ne, std::max(BRep_Tool::Tolerance(ne), 1.5 * deviation));
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
                    if (BRepAdaptor_Surface(edges.end_face[chosen], Standard_False).GetType() != GeomAbs_Plane) {
                        throw user_error(kStripMessage);
                    }
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
                    bool expanded = false;
                    for (int c = 0; c < 2 && !expanded; ++c) {
                        if (e.IsSame(edges.ends[c]) && !state.chain[c].empty()) {
                            // A G2 corner replaced this end by two half edges, listed in the old edge's own
                            // direction; the wire takes them in the direction it traverses the old edge.
                            auto sequence = state.chain[c];
                            const bool wire_reversed = it.Value().Orientation() == TopAbs_REVERSED;
                            if (wire_reversed) {
                                std::reverse(sequence.begin(), sequence.end());
                            }
                            for (const auto &[half_edge, against] : sequence) {
                                builder.Add(new_wire, half_edge.Oriented((against != wire_reversed) ? TopAbs_REVERSED : TopAbs_FORWARD));
                            }
                            expanded = true;
                        }
                    }
                    if (expanded) {
                        continue;
                    }
                    for (int c = 0; c < 2; ++c) {
                        if (e.IsSame(edges.ends[c])) {
                            e = new_ends[c].Oriented(flip_end[c] ? TopAbs::Reverse(it.Value().Orientation()) : it.Value().Orientation());
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
        for (std::size_t ci = 0; ci < corner_faces.size(); ++ci) {
            if (corner_done[ci]) {
                continue;
            }
            const TopoDS_Face old_corner = corner_faces[ci];
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
                    // The fill meets its boundary to its own accuracy (up to the position promise): the edge's tolerance
                    // covers how far its pcurve's surface point is from the shared 3D curve, as BRepCheck measures it.
                    double deviation = 0;
                    for (int k = 0; k <= kMeasureSamples; ++k) {
                        const double t = f2 + (l2 - f2) * k / kMeasureSamples;
                        const gp_Pnt2d uv = pc->Value(t);
                        const double ts = nc.FirstParameter() + (nc.LastParameter() - nc.FirstParameter()) * k / kMeasureSamples;
                        deviation = std::max(deviation, fill_surface->Value(uv.X(), uv.Y()).Distance(nc.Value(ts)));
                    }
                    builder.UpdateEdge(shared, pc, fill_surface, TopLoc_Location(), std::max(kEdgeTolerance, 1.5 * deviation));
                    builder.Add(wire, shared.Oriented(it.Value().Orientation()));
                }
                wire.Orientation(wires.Value().Orientation());
                builder.Add(rebuilt, wire);
            }
            rebuilt.Orientation(filled.Orientation());
            reshape.Replace(old_corner, rebuilt);
            ++report->corners;
        }
        if (!g2_new_faces.empty()) {
            // The new quadrilaterals join the (still free) shell of the working copy before the replacements apply.
            TopExp_Explorer shells(work, TopAbs_SHELL);
            if (!shells.More()) {
                throw user_error(kStripMessage);
            }
            TopoDS_Shell shell = TopoDS::Shell(shells.Current());
            shell.Free(Standard_True); // a copy's shapes are frozen; this one is ours
            for (const TopoDS_Face &quad : g2_new_faces) {
                builder.Add(shell, quad);
            }
        }
        result = reshape.Apply(work);
        BRepLib::SameParameter(result, 1e-4);
        BRepLib::UpdateTolerances(result);

        // Measure the seams in the result: the strips' springs, then the corners' boundaries, kept apart.
        const TopTools_IndexedMapOfShape result_faces = map_of(result, TopAbs_FACE);
        TopTools_IndexedDataMapOfShapeListOfShape result_edge_faces;
        TopExp::MapShapesAndAncestors(result, TopAbs_EDGE, TopAbs_FACE, result_edge_faces);
        // A face of the circular result, in the new solid (by index, or through the replacements once faces were added).
        auto result_face = [&](int index) {
            return g2_new_faces.empty() ? TopoDS::Face(result_faces(index)) : TopoDS::Face(reshape.Apply(faces(index)));
        };
        std::vector<TopoDS_Face> result_strips;
        for (int index : strip_indices) {
            result_strips.push_back(result_face(index));
        }
        for (std::size_t s = 0; s < result_strips.size(); ++s) {
            const TopoDS_Face &strip = result_strips[s];
            // The strips were classified before the faces were rebuilt; their spring edges are the same edges now.
            for (const Spring &spring : strips[s].spring) {
                // The springs' junction tangents were set on the strips as first classified.
                bool exempt[2] = {false, false};
                exempt[0] = spring.flipped ? spring.kinked[1] : spring.kinked[0];
                exempt[1] = spring.flipped ? spring.kinked[0] : spring.kinked[1];
                if (report->seam_count < OCCT_G2_MAX_SEAMS) {
                    report->seams[report->seam_count++] = measure_seam(spring.edge, strip, spring.neighbour, exempt);
                }
            }
        }
        // A mitre is a crease between two strips (the circular fillet has the same one): the seam must close to within
        // the position tolerance, and its angle is recorded.
        for (const TopoDS_Edge &edge : mitre_edges) {
            if (!result_edge_faces.Contains(edge)) {
                throw user_error(kStripMessage);
            }
            const std::vector<TopoDS_Face> sides = distinct_faces(edge, result_edge_faces);
            if (sides.size() != 2) {
                throw user_error(kStripMessage);
            }
            const occt_g2_seam seam = measure_seam(edge, sides[0], sides[1]);
            if (seam.position > 1e-4) {
                throw user_error(kStripMessage);
            }
            if (report->mitre_seam_count < OCCT_G2_MAX_SEAMS) {
                report->mitre_seams[report->mitre_seam_count++] = seam;
            }
        }
        for (const TopoDS_Edge &edge : g2_edges) {
            const std::vector<TopoDS_Face> sides = distinct_faces(edge, result_edge_faces);
            if (sides.size() != 2) {
                throw user_error(kCornerMessage); // a corner's edge must border exactly two faces
            }
            if (report->corner_seam_count < OCCT_G2_MAX_SEAMS) {
                report->corner_seams[report->corner_seam_count++] = measure_seam(edge, sides[0], sides[1]);
            }
        }
        for (std::size_t ci = 0; ci < corner_indices.size(); ++ci) {
            if (ci < corner_done.size() && corner_done[ci]) {
                continue;
            }
            const int index = corner_indices[ci];
            const TopoDS_Face corner = result_face(index);
            for (TopExp_Explorer it(corner, TopAbs_EDGE); it.More(); it.Next()) {
                const TopoDS_Edge e = TopoDS::Edge(it.Current());
                if (BRep_Tool::Degenerated(e)) {
                    continue;
                }
                const std::vector<TopoDS_Face> around = distinct_faces(e, result_edge_faces);
                if (around.size() != 2) {
                    throw user_error(kCornerMessage); // a corner's edge must border exactly two faces
                }
                for (const TopoDS_Face &other : around) {
                    if (!other.IsSame(corner) && report->corner_seam_count < OCCT_G2_MAX_SEAMS) {
                        report->corner_seams[report->corner_seam_count++] = measure_seam(e, corner, other);
                    }
                }
            }
        }
        // History: the records name faces of the circular result; the final solid has its own face map (a corner that
        // became a patch is gone from the middle of it, the patch is at the end), so each record is renumbered through
        // what its face became: its replacement, or the patch faces of a corner.
        {
            const TopTools_IndexedMapOfShape final_faces = map_of(result, TopAbs_FACE);
            auto final_index = [&](const TopoDS_Shape &face) {
                int found = final_faces.FindIndex(face);
                if (found == 0) {
                    found = final_faces.FindIndex(reshape.Apply(face));
                }
                if (found == 0) {
                    // A rebuilt copy of the same face: it keeps its surface.
                    TopLoc_Location location;
                    const Handle(Geom_Surface) surface = BRep_Tool::Surface(TopoDS::Face(face), location);
                    for (int j = 1; j <= final_faces.Extent() && found == 0; ++j) {
                        TopLoc_Location other_location;
                        if (BRep_Tool::Surface(TopoDS::Face(final_faces(j)), other_location) == surface &&
                            other_location == location) {
                            found = j;
                        }
                    }
                }
                return found;
            };
            std::vector<std::vector<int>> final_of(g1_faces.Extent() + 1);
            for (int i = 1; i <= g1_faces.Extent(); ++i) {
                const TopoDS_Shape &original = faces(i);
                const TopoDS_Shape replacement = reshape.IsRecorded(original) ? reshape.Value(original) : original;
                if (replacement.IsNull()) {
                    for (std::size_t ci = 0; ci < corner_faces.size(); ++ci) {
                        if (corner_faces[ci].IsSame(original)) {
                            for (const TopoDS_Face &patch : corner_patches[ci]) {
                                const int found = final_index(patch);
                                if (found > 0) {
                                    final_of[i].push_back(found);
                                }
                            }
                        }
                    }
                } else {
                    const int found = final_index(replacement);
                    if (found > 0) {
                        final_of[i].push_back(found);
                    }
                }
            }
            std::vector<occt_history_record> renumbered;
            for (const occt_history_record &record : records.records()) {
                const std::vector<int> &now = final_of[record.out_face];
                if (now.empty()) {
                    continue; // a face of the circular result that the final solid no longer has (none is expected)
                }
                for (int index : now) {
                    renumbered.push_back(occt_history_record{index, record.kind, record.operand, record.index});
                }
            }
            records.set_records(std::move(renumbered));
        }
        // Never return a solid OCCT's checker rejects.
        if (!BRepCheck_Analyzer(result).IsValid()) {
            throw user_error(report->corners > 0 ? kCornerMessage : kStripMessage);
        }
        records.move_into(history);
        return new occt_shape{result};
    });
}

occt_shape *occt_fillet_g2(const occt_shape *shape, const int *edge_indices, int count, double radius, double weight,
                           occt_history *history, occt_g2_report *report, occt_status *status) {
    occt_shape *made = fillet_g2_run(shape, edge_indices, count, radius, weight, true, history, report, status);
    if (made || report->g2_corners == 0) {
        return made;
    }
    // A patch was committed and something later failed (a strip face, the solid's validity): the same fillet with
    // every corner refilled G1, as the corners a patch is not accepted for are.
    return fillet_g2_run(shape, edge_indices, count, radius, weight, false, history, report, status);
}

} // extern "C"
