// Strip construction for the curvature-continuous fillet: classifying a strip face's edges into springs and ends,
// the quintic G2 sections between two springs, their pairing, the skinned surface and its pcurves, and the
// adaptive loop that adds sections until the strip's seams meet the tolerances (cocct_g2_blend_internal.hpp).

#include "cocct_g2_blend_internal.hpp"

#include <BRepAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepTools.hxx>
#include <Extrema_ExtPC.hxx>
#include <Geom2dAPI_Interpolate.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <Geom_BSplineCurve.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColStd_HArray1OfReal.hxx>
#include <TColgp_Array1OfPnt2d.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TColgp_HArray1OfPnt2d.hxx>

#include <algorithm>
#include <cmath>

namespace cocct::g2_blend {

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

bool is_blend(const TopoDS_Shape &face, const std::vector<TopoDS_Face> &blend) {
    for (const TopoDS_Face &b : blend) {
        if (b.IsSame(face)) {
            return true;
        }
    }
    return false;
}

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

namespace {

constexpr int kFirstSections = 9;   // cross-sections per strip to start with
constexpr int kMaxSections = 129;   // the cap: 9, 17, 33, 65, 129

/// The edge parameter of fraction `fraction` of the way from the spring's sampling start to its sampling end.
double sample_parameter(const Spring &spring, double fraction) {
    return spring.t_start + fraction * (spring.t_end - spring.t_start);
}

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
    // The search window runs past B's ends, where the curve is only an extrapolation of its polynomials: that can hold
    // a spurious minimum (even a nearer one than the true projection) that appears and vanishes with the last bits
    // of the input, and the extremum search also returns maxima. So only minima count, and of those the one nearest
    // the parameter the strip's own proportions expect (B's sample_parameter), a choice that moves continuously.
    auto project_onto_b = [&](int j, double &out) {
        Extrema_ExtPC ext(ca.Value(pairing.ta[j]), cb, lo - window, hi + window);
        if (!ext.IsDone() || ext.NbExt() == 0) {
            return false;
        }
        const double expected = pairing.tb[j];
        int best = 0;
        for (int i = 1; i <= ext.NbExt(); ++i) {
            if (!ext.IsMin(i)) {
                continue;
            }
            if (best == 0 || std::abs(ext.Point(i).Parameter() - expected) < std::abs(ext.Point(best).Parameter() - expected)) {
                best = i;
            }
        }
        if (best == 0) {
            return false;
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
            const double first = springs[side]->t_start, span = springs[side]->t_end - springs[side]->t_start;
            // Samples: evenly along the edge, plus the sections' own parameters and the middles of their spans. Where
            // the sections crowd together (a strip's ends, where the pairing bends sharply) the map from the edge
            // parameter to u bends sharply too, and evenly spaced samples cannot follow it with their end conditions.
            const std::vector<double> &paired = side == 0 ? pairing.ta : pairing.tb;
            std::vector<double> fraction;
            for (int k = 0; k < samples; ++k) {
                fraction.push_back(static_cast<double>(k) / (samples - 1));
            }
            for (int j = 0; j < sections; ++j) {
                fraction.push_back((paired[j] - first) / span);
                if (j + 1 < sections) {
                    fraction.push_back((0.5 * (paired[j] + paired[j + 1]) - first) / span);
                }
            }
            std::sort(fraction.begin(), fraction.end());
            std::vector<double> distinct{0.0};
            for (const double value : fraction) {
                if (value > distinct.back() + 1e-6 && value < 1 - 1e-6) {
                    distinct.push_back(value);
                }
            }
            distinct.push_back(1.0);
            const int count = static_cast<int>(distinct.size());
            std::vector<double> t(count), uu(count);
            bool projected = true;
            for (int k = 0; k < count && projected; ++k) {
                t[k] = k == 0 ? first : (k == count - 1 ? springs[side]->t_end : first + span * distinct[k]);
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

} // namespace

void agree_chain_tangents(Run &r) {
    occt_g2_report *const report = r.report;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<TopoDS_Edge> &kinked_joins = r.kinked_joins;
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
                                    // Every kink is a counted join: the join edge is the end that chains to the
                                    // other strip, else (never seen) the spring's own end.
                                    int join_end = end;
                                    for (int c = 0; c < 2; ++c) {
                                        if (strips[s].end_chain[c].IsSame(strip_faces[t])) {
                                            join_end = c;
                                        }
                                    }
                                    bool known = false;
                                    for (const TopoDS_Edge &join : kinked_joins) {
                                        known = known || join.IsSame(strips[s].ends[join_end]);
                                    }
                                    if (!known) {
                                        kinked_joins.push_back(strips[s].ends[join_end]);
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
}

void build_strips(Run &r) {
    occt_g2_report *const report = r.report;
    const double radius = r.radius;
    const double weight = r.weight;
    const std::vector<TopoDS_Face> &strip_faces = r.strip_faces;
    BRep_Builder &builder = r.builder;
    std::vector<StripEdges> &strips = r.strips;
    std::vector<StripState> &states = r.states;
    // Every strip is built first (so that two strips meeting at a mitre can be cut by each other), then the
    // mitres, then each strip's end edges and face.
    states.resize(strips.size());
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
}

} // namespace cocct::g2_blend
